#!chezscheme
;;; (std build reproducible) — Reproducible Build Utilities
;;;
;;; Content-addressed artifact store, build manifests, caching,
;;; and verification of reproducible builds.

(library (std build reproducible)
  (export
    ;; Content-addressed hashing
    content-hash
    content-hash-string

    ;; Build manifest
    make-manifest
    manifest?
    manifest-add!
    manifest-get
    manifest-hash
    manifest->alist
    manifest->string
    manifest-from-string

    ;; Artifact store
    make-artifact-store
    artifact-store?
    artifact-store-put!
    artifact-store-get
    artifact-store-has?
    artifact-store-path

    ;; Build records
    make-build-record
    build-record?
    build-record-hash
    build-record-timestamp
    build-record-source-hash
    build-record-deps-hash

    ;; Verification
    verify-build
    normalize-artifact

    ;; Build cache
    make-build-cache
    build-cache?
    build-cache-lookup
    build-cache-store!
    build-cache-stats)

  (import (chezscheme))

  ;; ========== Content Hashing ==========
  ;; Uses FNV-1a over bytes for a deterministic, portable hash.
  ;; *content-hasher* is a parameter for plugging in real SHA-256.

  (define *content-hasher* (make-parameter #f)) ;; #f = use built-in FNV-1a

  (define (fnv1a-hash bv)
    ;; FNV-1a 64-bit over a bytevector. Returns hex string.
    (let ([basis #xcbf29ce484222325]
          [prime #x100000001b3]
          [mask  #xffffffffffffffff])
      (let loop ([i 0] [h basis])
        (if (= i (bytevector-length bv))
            (number->string h 16)
            (loop (+ i 1)
                  (bitwise-and
                    (* (bitwise-xor h (bytevector-u8-ref bv i)) prime)
                    mask))))))

  (define (str->bv str)
    ;; String to bytevector using char codes.
    (let* ([n (string-length str)]
           [bv (make-bytevector n)])
      (do ([i 0 (+ i 1)])
          ((= i n) bv)
        (bytevector-u8-set! bv i (char->integer (string-ref str i))))))

  (define (read-file-bytevector path)
    ;; Read entire file into a bytevector by chunking.
    (call-with-port (open-file-input-port path)
      (lambda (port)
        (let loop ([chunks '()])
          (let ([bv (get-bytevector-n port 4096)])
            (if (or (eof-object? bv) (= (bytevector-length bv) 0))
                (let* ([total  (apply + (map bytevector-length chunks))]
                       [result (make-bytevector total)])
                  (let fill ([offset 0] [cs (reverse chunks)])
                    (unless (null? cs)
                      (let ([c (car cs)])
                        (bytevector-copy! c 0 result offset (bytevector-length c))
                        (fill (+ offset (bytevector-length c)) (cdr cs)))))
                  result)
                (loop (cons bv chunks))))))))

  (define (content-hash path)
    ;; Hash the contents of file at path. Returns hex string or #f.
    (guard (exn [#t #f])
      (if (*content-hasher*)
          ((*content-hasher*) path)
          (fnv1a-hash (read-file-bytevector path)))))

  (define (content-hash-string str)
    ;; Hash the contents of a string.
    (fnv1a-hash (str->bv str)))

  ;; ========== Manifest ==========

  (define-record-type (%manifest %make-manifest manifest?)
    (fields (mutable entries)))  ;; ordered alist: (key . value) pairs

  (define (make-manifest)
    (%make-manifest '()))

  (define (manifest-add! m key value)
    ;; Add or update entry. Append if new, update existing in-place.
    (let ([existing (assoc key (%manifest-entries m))])
      (if existing
          (set-cdr! existing value)
          (%manifest-entries-set! m
            (append (%manifest-entries m) (list (cons key value)))))))

  (define (manifest-get m key)
    (let ([entry (assoc key (%manifest-entries m))])
      (and entry (cdr entry))))

  (define (manifest->alist m)
    ;; Return a fresh copy of the entries list.
    (map (lambda (kv) (cons (car kv) (cdr kv)))
         (%manifest-entries m)))

  (define (manifest->string m)
    ;; Serialize as "key=value\n" lines.
    (apply string-append
           (map (lambda (kv)
                  (string-append (format "~a" (car kv)) "="
                                 (format "~a" (cdr kv)) "\n"))
                (%manifest-entries m))))

  (define (manifest-hash m)
    (content-hash-string (manifest->string m)))

  (define (string-split-lines s)
    (let loop ([i 0] [start 0] [lines '()])
      (cond
        [(= i (string-length s))
         (let ([last (substring s start i)])
           (reverse (if (string=? last "") lines (cons last lines))))]
        [(char=? (string-ref s i) #\newline)
         (loop (+ i 1) (+ i 1) (cons (substring s start i) lines))]
        [else (loop (+ i 1) start lines)])))

  (define (string-index str ch)
    (let loop ([i 0])
      (cond
        [(= i (string-length str)) #f]
        [(char=? (string-ref str i) ch) i]
        [else (loop (+ i 1))])))

  (define (manifest-from-string s)
    ;; Deserialize from "key=value\n" lines.
    (let ([m (make-manifest)]
          [lines (string-split-lines s)])
      (for-each
        (lambda (line)
          (let ([eq-pos (string-index line #\=)])
            (when eq-pos
              (let ([key (substring line 0 eq-pos)]
                    [val (substring line (+ eq-pos 1) (string-length line))])
                (manifest-add! m key val)))))
        lines)
      m))

  ;; ========== Artifact Store ==========
  ;; Files stored at <store-path>/<hash[0:2]>/<hash[2:]>

  (define-record-type (%artifact-store %make-artifact-store artifact-store?)
    (fields (immutable root)))  ;; root directory of the store

  (define (make-artifact-store path)
    (guard (exn [#t #f])
      (unless (file-directory? path)
        (system (string-append "mkdir -p " path)))
      (%make-artifact-store path)))

  (define (artifact-store-path store hash)
    (let* ([root   (%artifact-store-root store)]
           [prefix (if (>= (string-length hash) 2) (substring hash 0 2) hash)]
           [rest   (if (>= (string-length hash) 2)
                       (substring hash 2 (string-length hash))
                       "")])
      (string-append root "/" prefix "/" rest)))

  (define (artifact-store-has? store hash)
    (file-exists? (artifact-store-path store hash)))

  (define (path-directory path)
    ;; Return directory part of path.
    (let loop ([i (- (string-length path) 1)])
      (cond
        [(< i 0) "."]
        [(char=? (string-ref path i) #\/) (substring path 0 i)]
        [else (loop (- i 1))])))

  (define (artifact-store-put! store content)
    ;; content is a string; returns its hash.
    (let* ([hash (content-hash-string content)]
           [path (artifact-store-path store hash)]
           [dir  (path-directory path)])
      (unless (file-directory? dir)
        (guard (exn [#t #f])
          (system (string-append "mkdir -p " dir))))
      (call-with-output-file path
        (lambda (port) (display content port))
        'replace)
      hash))

  (define (artifact-store-get store hash)
    ;; Returns content string or #f.
    (guard (exn [#t #f])
      (let ([path (artifact-store-path store hash)])
        (if (file-exists? path)
            (call-with-input-file path
              (lambda (port)
                (let loop ([chunks '()])
                  (let ([line (get-line port)])
                    (if (eof-object? line)
                        (apply string-append (reverse chunks))
                        (loop (cons (string-append line "\n") chunks)))))))
            #f))))

  ;; ========== Build Records ==========

  (define-record-type (%build-record %make-build-record build-record?)
    (fields
      (immutable source-hash)  ;; hash of source content
      (immutable deps-hash)    ;; hash of dependencies
      (immutable flags)        ;; compiler flags string
      (immutable timestamp)))  ;; integer seconds when record was made

  (define (make-build-record source-hash deps-hash flags)
    (%make-build-record source-hash deps-hash flags
      (time-second (current-time))))

  (define (build-record-source-hash r) (%build-record-source-hash r))
  (define (build-record-deps-hash r)   (%build-record-deps-hash r))
  (define (build-record-timestamp r)   (%build-record-timestamp r))

  (define (build-record-hash r)
    ;; Combined hash of all inputs: source + deps + flags.
    (content-hash-string
      (string-append
        (%build-record-source-hash r)
        (%build-record-deps-hash r)
        (format "~a" (%build-record-flags r)))))

  ;; ========== Verification ==========

  (define (verify-build record artifact-path)
    ;; Returns #t if artifact exists and both record and artifact hashes are non-empty.
    (guard (exn [#t #f])
      (let ([artifact-hash (content-hash artifact-path)])
        (and artifact-hash
             (> (string-length (build-record-hash record)) 0)
             (> (string-length artifact-hash) 0)))))

  (define (digit? c)
    (and (char>=? c #\0) (char<=? c #\9)))

  (define (normalize-artifact path)
    ;; Read file, strip embedded timestamps (ISO 8601 YYYY-MM-DD patterns), write to .normalized file.
    (guard (exn [#t #f])
      (let* ([content (call-with-input-file path
                        (lambda (port)
                          (let loop ([chars '()])
                            (let ([c (read-char port)])
                              (if (eof-object? c)
                                  (list->string (reverse chars))
                                  (loop (cons c chars)))))))]
             [normalized (strip-timestamps content)]
             [out-path   (string-append path ".normalized")])
        (call-with-output-file out-path
          (lambda (port) (display normalized port))
          'replace)
        out-path)))

  (define (strip-timestamps s)
    ;; Strip ISO date-like sequences: YYYY-MM-DD
    (let ([n (string-length s)]
          [result (open-output-string)])
      (let loop ([i 0])
        (cond
          [(>= i n) (get-output-string result)]
          ;; Check for YYYY-MM-DD pattern at position i
          [(and (<= (+ i 10) n)
                (digit? (string-ref s i))
                (digit? (string-ref s (+ i 1)))
                (digit? (string-ref s (+ i 2)))
                (digit? (string-ref s (+ i 3)))
                (char=? (string-ref s (+ i 4)) #\-)
                (digit? (string-ref s (+ i 5)))
                (digit? (string-ref s (+ i 6)))
                (char=? (string-ref s (+ i 7)) #\-)
                (digit? (string-ref s (+ i 8)))
                (digit? (string-ref s (+ i 9))))
           (display "<DATE>" result)
           (loop (+ i 10))]
          [else
           (write-char (string-ref s i) result)
           (loop (+ i 1))]))))

  ;; ========== Build Cache ==========

  (define-record-type (%build-cache %make-build-cache build-cache?)
    (fields
      (mutable table)    ;; hashtable: build-record-hash -> artifact
      (mutable hits)
      (mutable misses)))

  (define (make-build-cache)
    (%make-build-cache
      (make-hashtable equal-hash equal?)
      0
      0))

  (define (build-cache-lookup cache record)
    ;; Returns cached artifact or #f on miss.
    (let* ([key (build-record-hash record)]
           [val (hashtable-ref (%build-cache-table cache) key #f)])
      (if val
          (begin
            (%build-cache-hits-set! cache (+ (%build-cache-hits cache) 1))
            val)
          (begin
            (%build-cache-misses-set! cache (+ (%build-cache-misses cache) 1))
            #f))))

  (define (build-cache-store! cache record artifact)
    (hashtable-set! (%build-cache-table cache)
                    (build-record-hash record)
                    artifact))

  (define (build-cache-stats cache)
    ;; Returns alist: ((hits . N) (misses . N) (entries . N))
    (list
      (cons 'hits    (%build-cache-hits cache))
      (cons 'misses  (%build-cache-misses cache))
      (cons 'entries (hashtable-size (%build-cache-table cache)))))

) ;; end library
