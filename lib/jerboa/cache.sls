#!chezscheme
;;; (jerboa cache) — Content-addressed compilation cache
;;;
;;; Hashes source + dependencies + Chez version to produce cache keys.
;;; Avoids recompilation when inputs haven't changed.
;;;
;;; Cache layout:
;;;   ~/.jerboa/cache/<sha256>.so
;;;
;;; Cache key = SHA-256(source-content || dep-hash-1 || ... || chez-version || opt-level)

(library (jerboa cache)
  (export
    cache-directory
    cache-lookup
    cache-store!
    cache-key
    with-compilation-cache
    cache-stats
    cache-clear!)
  (import (chezscheme))

  ;; ========== Configuration ==========

  (define cache-directory
    (make-parameter
      (let ([home (getenv "HOME")])
        (if home
          (string-append home "/.jerboa/cache")
          "/tmp/jerboa-cache"))))

  ;; ========== Hashing ==========

  ;; Simple string hash using Chez's built-in (not cryptographic, but fast)
  ;; For production, this should use SHA-256 from chez-crypto
  ;; FNV-1a hash producing a 128-bit hex string for cache keys
  (define (string-hash-256 str)
    (let ([len (string-length str)])
      (let loop ([i 0] [h1 14695981039346656037] [h2 6364136223846793005])
        (if (= i len)
          (string-append
            (number->string (mod (abs h1) (expt 2 64)) 16)
            (number->string (mod (abs h2) (expt 2 64)) 16))
          (let ([byte (char->integer (string-ref str i))])
            (loop (+ i 1)
                  (mod (* (bitwise-xor h1 byte) 1099511628211) (expt 2 64))
                  (mod (* (bitwise-xor h2 (+ byte 37)) 6364136223846793005) (expt 2 64))))))))

  ;; Compute cache key from source file and its dependencies
  (define (cache-key source-path dep-hashes opt-level)
    (let* ([source-content (call-with-port (open-input-file source-path)
                             (lambda (p)
                               (get-string-all p)))]
           [chez-ver (scheme-version)]
           [key-material (apply string-append
                           source-content
                           (number->string opt-level)
                           chez-ver
                           (map (lambda (h) (or h "")) dep-hashes))])
      (string-hash-256 key-material)))

  ;; ========== Cache Operations ==========

  (define (ensure-cache-dir!)
    (let ([dir (cache-directory)])
      (unless (file-exists? dir)
        (mkdir-p dir))))

  (define (cache-path key)
    (string-append (cache-directory) "/" key ".so"))

  ;; Look up a cached .so by its key
  ;; Returns the path if found, #f if not
  (define (cache-lookup key)
    (let ([path (cache-path key)])
      (if (file-exists? path) path #f)))

  ;; Store a compiled .so file in the cache
  (define (cache-store! key so-path)
    (ensure-cache-dir!)
    (let ([dest (cache-path key)])
      (unless (file-exists? dest)
        ;; Copy the file
        (let ([data (call-with-port (open-file-input-port so-path)
                      (lambda (p) (get-bytevector-all p)))])
          (call-with-port (open-file-output-port dest)
            (lambda (p) (put-bytevector p data)))))))

  ;; ========== High-Level API ==========

  ;; Compile a file with caching
  ;; Returns the .so path (from cache or freshly compiled)
  (define (with-compilation-cache source-path output-path dep-hashes opt-level compile-thunk)
    (let* ([key (cache-key source-path dep-hashes opt-level)]
           [cached (cache-lookup key)])
      (if cached
        ;; Cache hit — copy to output
        (begin
          (let ([data (call-with-port (open-file-input-port cached)
                        (lambda (p) (get-bytevector-all p)))])
            (call-with-port (open-file-output-port output-path
                              (file-options no-fail))
              (lambda (p) (put-bytevector p data))))
          output-path)
        ;; Cache miss — compile and store
        (begin
          (compile-thunk)
          (when (file-exists? output-path)
            (cache-store! key output-path))
          output-path))))

  ;; ========== Maintenance ==========

  (define (cache-stats)
    (let ([dir (cache-directory)])
      (if (file-exists? dir)
        (let ([files (directory-list dir)])
          (let ([count (length files)]
                [size (fold-left
                        (lambda (acc f)
                          (let* ([path (string-append dir "/" f)]
                                 [fsize (call-with-port (open-file-input-port path)
                                          (lambda (p)
                                            (set-port-position! p (+ (port-position p) 0))
                                            (let ([data (get-bytevector-all p)])
                                              (if (eof-object? data) 0
                                                  (bytevector-length data)))))])
                            (+ acc fsize)))
                        0 files)])
            (values count size)))
        (values 0 0))))

  (define (cache-clear!)
    (let ([dir (cache-directory)])
      (when (file-exists? dir)
        (for-each
          (lambda (f)
            (delete-file (string-append dir "/" f)))
          (directory-list dir)))))

  ;; Create ~/.jerboa/cache directory tree
  (define (mkdir-p path)
    ;; Use system mkdir -p since Chez doesn't have recursive mkdir
    (system (format "mkdir -p '~a'" path)))

  ) ;; end library
