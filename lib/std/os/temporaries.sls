#!chezscheme
;;; :std/os/temporaries -- Temporary file utilities

(library (std os temporaries)
  (export make-temporary-file-name
          with-temporary-file
          with-temporary-directory
          create-temporary-file
          temporary-file-directory)

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

  ;; Parameter for temp directory (respects TMPDIR)
  (define temporary-file-directory
    (make-parameter (or (getenv "TMPDIR") "/tmp")))

  (define (with-temporary-file proc . rest)
    (let ((name (apply make-temporary-file-name rest)))
      (dynamic-wind
        (lambda () #f)
        (lambda () (proc name))
        (lambda () (when (file-exists? name) (delete-file name))))))

  ;; Create a temporary file and return (values path port)
  (define (create-temporary-file . rest)
    (let ((name (apply make-temporary-file-name rest)))
      (let ((port (open-output-file name)))
        (values name port))))

  ;; Scoped temporary directory with recursive cleanup
  (define (with-temporary-directory proc . rest)
    (let ((dir (apply make-temporary-file-name rest)))
      (mkdir dir)
      (dynamic-wind
        (lambda () #f)
        (lambda () (proc dir))
        (lambda () (rm-rf dir)))))

  (define (rm-rf path)
    (when (file-exists? path)
      (if (file-directory? path)
        (begin
          (for-each (lambda (f)
                      (rm-rf (string-append path "/" f)))
                    (directory-list path))
          (delete-directory path))
        (delete-file path))))

  ) ;; end library
