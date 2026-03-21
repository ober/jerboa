#!chezscheme
;;; (std os temp) — Temporary file and directory management
;;;
;;; Create and auto-cleanup temporary files and directories.

(library (std os temp)
  (export make-temporary-file make-temporary-directory
          call-with-temporary-file call-with-temporary-directory)

  (import (chezscheme))

  (define dummy-load (load-shared-object "libc.so.6"))

  (define c-mkstemp
    (foreign-procedure "mkstemp" (u8*) int))

  (define c-mkdtemp
    (foreign-procedure "mkdtemp" (u8*) void*))

  (define c-close
    (foreign-procedure "close" (int) int))

  (define c-unlink
    (foreign-procedure "unlink" (string) int))

  (define c-rmdir
    (foreign-procedure "rmdir" (string) int))

  ;; Convert string to null-terminated bytevector
  (define (string->bv str)
    (let ([bv (make-bytevector (+ (string-length str) 1))])
      (do ([i 0 (+ i 1)])
          ((= i (string-length str)))
        (bytevector-u8-set! bv i (char->integer (string-ref str i))))
      (bytevector-u8-set! bv (string-length str) 0)
      bv))

  ;; Extract string from null-terminated bytevector
  (define (bv->string bv)
    (let loop ([i 0] [acc '()])
      (let ([b (bytevector-u8-ref bv i)])
        (if (= b 0)
            (list->string (reverse acc))
            (loop (+ i 1) (cons (integer->char b) acc))))))

  ;; Create a temporary file, return its path
  (define make-temporary-file
    (case-lambda
      [() (make-temporary-file "/tmp/jerboa-XXXXXX")]
      [(template)
       (let* ([bv (string->bv template)]
              [fd (c-mkstemp bv)])
         (when (< fd 0)
           (error 'make-temporary-file "mkstemp failed" template))
         (c-close fd)
         (bv->string bv))]))

  ;; Create a temporary directory, return its path
  (define make-temporary-directory
    (case-lambda
      [() (make-temporary-directory "/tmp/jerboa-XXXXXX")]
      [(template)
       (let* ([bv (string->bv template)]
              [result (c-mkdtemp bv)])
         (when (= result 0)
           (error 'make-temporary-directory "mkdtemp failed" template))
         (bv->string bv))]))

  ;; Create temp file, call proc with path, cleanup on exit
  (define (call-with-temporary-file proc)
    (let ([path (make-temporary-file)])
      (dynamic-wind
        void
        (lambda () (proc path))
        (lambda () (c-unlink path)))))

  ;; Create temp directory, call proc with path, cleanup on exit
  (define (call-with-temporary-directory proc)
    (let ([path (make-temporary-directory)])
      (dynamic-wind
        void
        (lambda () (proc path))
        (lambda () (c-rmdir path)))))

) ;; end library
