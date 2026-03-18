#!chezscheme
;;; :std/os/temporaries -- Temporary file utilities

(library (std os temporaries)
  (export make-temporary-file-name with-temporary-file)

  (import (chezscheme))

  (define _libc-loaded
    (let ((v (getenv "JEMACS_STATIC")))
      (if (and v (not (string=? v "")) (not (string=? v "0")))
          #f  ; symbols already in static binary
          (load-shared-object "libc.so.6"))))
  (define getpid (foreign-procedure "getpid" () int))

  (define *temp-counter* 0)

  (define (make-temporary-file-name . rest)
    (let ((prefix (if (pair? rest) (car rest) "jerboa"))
          (dir (or (getenv "TMPDIR") "/tmp")))
      (set! *temp-counter* (+ *temp-counter* 1))
      (format "~a/~a-~a-~a" dir prefix (getpid) *temp-counter*)))

  (define (with-temporary-file proc . rest)
    (let ((name (apply make-temporary-file-name rest)))
      (dynamic-wind
        (lambda () #f)
        (lambda () (proc name))
        (lambda () (when (file-exists? name) (delete-file name))))))

  ) ;; end library
