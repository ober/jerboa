#!chezscheme
;;; (std os path-util) -- Enhanced Path & Filesystem Utilities
;;;
;;; Higher-level filesystem operations building on (std os path):
;;;   - path-walk: recursive directory traversal
;;;   - path-find: find files matching predicate
;;;   - path-glob: find files matching glob pattern
;;;   - file-size, file-mtime: file metadata
;;;   - with-temp-directory: scoped temp dir
;;;   - copy-file, move-file: file operations
;;;   - ensure-directory: create directory tree
;;;
;;; Usage:
;;;   (import (std os path-util))
;;;   (path-walk "src" (lambda (dir files subdirs) ...))
;;;   (path-find "src" (lambda (p) (string-suffix? p ".ss")))
;;;   (file-size "data.csv")     ; => 1234

(library (std os path-util)
  (export
    path-walk
    path-find
    path-glob
    file-size
    file-exists-safe?
    directory-exists?
    ensure-directory
    with-temp-directory
    copy-file
    path-relative
    path-common-prefix
    directory-files
    directory-files-recursive
    string-suffix?)

  (import (chezscheme))

  ;; ========== Directory Walking ==========
  (define (path-walk dir proc)
    ;; Walk directory tree, calling (proc dir-path files subdirs)
    ;; for each directory. files and subdirs are lists of names (not full paths).
    (guard (exn [#t (void)])
      (let* ([entries (map entry->string (directory-list dir))]
             [files '()]
             [subdirs '()])
        (for-each
          (lambda (e)
            (let ([full (string-append dir "/" e)])
              (if (file-directory? full)
                (set! subdirs (cons e subdirs))
                (set! files (cons e files)))))
          entries)
        (proc dir (reverse files) (reverse subdirs))
        (for-each
          (lambda (sd)
            (path-walk (string-append dir "/" sd) proc))
          (reverse subdirs)))))

  ;; ========== Find Files ==========
  (define (path-find dir pred)
    ;; Recursively find files where (pred full-path) is true
    (let ([results '()])
      (path-walk dir
        (lambda (d files subdirs)
          (for-each
            (lambda (f)
              (let ([full (string-append d "/" f)])
                (when (pred full)
                  (set! results (cons full results)))))
            files)))
      (reverse results)))

  ;; ========== Glob ==========
  (define (path-glob dir pattern)
    ;; Find files matching a simple glob pattern (just filename, not path)
    (path-find dir
      (lambda (path)
        (glob-match? pattern (path-strip-directory path)))))

  ;; Simple glob matching for filename portion
  (define (glob-match? pattern str)
    (match-glob (string->list pattern) (string->list str)))

  (define (match-glob pat str)
    (cond
      [(and (null? pat) (null? str)) #t]
      [(null? pat) #f]
      [(eqv? (car pat) #\*)
       (let loop ([s str])
         (cond
           [(match-glob (cdr pat) s) #t]
           [(null? s) #f]
           [else (loop (cdr s))]))]
      [(eqv? (car pat) #\?)
       (and (pair? str) (match-glob (cdr pat) (cdr str)))]
      [(null? str) #f]
      [(eqv? (car pat) (car str))
       (match-glob (cdr pat) (cdr str))]
      [else #f]))

  ;; ========== File Metadata ==========
  (define (file-size path)
    (guard (exn [#t #f])
      (let ([port (open-file-input-port path)])
        (let ([size (port-length port)])
          (close-port port)
          size))))

  (define (file-exists-safe? path)
    (guard (exn [#t #f])
      (file-exists? path)))

  (define (directory-exists? path)
    (and (file-exists? path) (file-directory? path)))

  ;; ========== Directory Operations ==========
  (define (ensure-directory path)
    ;; Create directory and all parents
    (unless (directory-exists? path)
      (let ([parent (path-directory* path)])
        (when (and (> (string-length parent) 0)
                   (not (string=? parent path))
                   (not (string=? parent ".")))
          (ensure-directory parent)))
      (guard (exn [#t (void)])  ;; may already exist (race)
        (mkdir path))))

  (define (with-temp-directory proc)
    ;; Create a temp dir, call (proc dir-path), then clean up
    (let ([dir (format "/tmp/jerboa-tmp-~a-~a" (random 999999999) (time-nanosecond (current-time)))])
      (mkdir dir)
      (dynamic-wind
        (lambda () (void))
        (lambda () (proc dir))
        (lambda ()
          (guard (exn [#t (void)])
            (remove-directory-recursive dir))))))

  ;; ========== File Operations ==========
  (define (copy-file src dst)
    (let ([data (call-with-port (open-file-input-port src)
                  (lambda (in)
                    (let loop ([chunks '()])
                      (let ([buf (get-bytevector-n in 65536)])
                        (if (eof-object? buf)
                          (bytevector-concat (reverse chunks))
                          (loop (cons buf chunks)))))))])
      (call-with-port (open-file-output-port dst (file-options no-fail))
        (lambda (out)
          (put-bytevector out data)))))

  ;; ========== Path Utilities ==========
  (define (path-relative base path)
    ;; Make path relative to base
    (let ([base (ensure-trailing-slash base)])
      (if (string-prefix? path base)
        (substring path (string-length base) (string-length path))
        path)))

  (define (path-common-prefix paths)
    ;; Find longest common directory prefix
    (if (null? paths) ""
      (let loop ([prefix (car paths)] [rest (cdr paths)])
        (if (null? rest) prefix
          (loop (common-prefix prefix (car rest)) (cdr rest))))))

  (define (directory-files dir)
    ;; List files (not subdirs) in a directory
    (guard (exn [#t '()])
      (let ([entries (map entry->string (directory-list dir))])
        (filter (lambda (e)
                  (not (file-directory? (string-append dir "/" e))))
                entries))))

  (define (directory-files-recursive dir)
    ;; All files recursively
    (path-find dir (lambda (p) #t)))

  ;; ========== String Helpers ==========
  (define (string-suffix? str suffix)
    (let ([slen (string-length str)]
          [plen (string-length suffix)])
      (and (>= slen plen)
           (string=? (substring str (- slen plen) slen) suffix))))

  (define (string-prefix? str prefix)
    (and (>= (string-length str) (string-length prefix))
         (string=? (substring str 0 (string-length prefix)) prefix)))

  (define (path-strip-directory path)
    (let ([idx (string-last-index path #\/)])
      (if idx (substring path (+ idx 1) (string-length path)) path)))

  (define (path-directory* path)
    (let ([idx (string-last-index path #\/)])
      (if idx (substring path 0 idx) ".")))

  (define (string-last-index str ch)
    (let loop ([i (- (string-length str) 1)])
      (cond
        [(< i 0) #f]
        [(char=? (string-ref str i) ch) i]
        [else (loop (- i 1))])))

  (define (ensure-trailing-slash s)
    (if (and (> (string-length s) 0)
             (not (char=? (string-ref s (- (string-length s) 1)) #\/)))
      (string-append s "/")
      s))

  (define (common-prefix a b)
    (let ([n (min (string-length a) (string-length b))])
      (let loop ([i 0])
        (if (or (= i n) (not (char=? (string-ref a i) (string-ref b i))))
          (substring a 0 i)
          (loop (+ i 1))))))

  (define (entry->string e)
    (if (symbol? e) (symbol->string e) e))

  (define (remove-directory-recursive dir)
    (for-each
      (lambda (e)
        (let ([path (string-append dir "/" (entry->string e))])
          (if (file-directory? path)
            (remove-directory-recursive path)
            (delete-file path))))
      (directory-list dir))
    (delete-directory dir))

  (define (bytevector-concat bvs)
    (if (null? bvs) (make-bytevector 0)
      (let* ([total (apply + (map bytevector-length bvs))]
             [result (make-bytevector total)])
        (let loop ([bvs bvs] [pos 0])
          (if (null? bvs) result
            (let ([bv (car bvs)])
              (bytevector-copy! bv 0 result pos (bytevector-length bv))
              (loop (cdr bvs) (+ pos (bytevector-length bv)))))))))

) ;; end library
