#!chezscheme
;;; :std/misc/ports -- Port utilities

(library (std misc ports)
  (export read-all-as-string read-all-as-lines
          read-file-string read-file-lines
          write-file-string
          with-input-from-string with-output-to-string)
  (import (except (chezscheme) with-input-from-string with-output-to-string))

  (define (read-all-as-string port)
    (let loop ([chars '()])
      (let ([ch (read-char port)])
        (if (eof-object? ch)
          (list->string (reverse chars))
          (loop (cons ch chars))))))

  (define (read-all-as-lines port)
    (let loop ([lines '()])
      (let ([line (get-line port)])
        (if (eof-object? line)
          (reverse lines)
          (loop (cons line lines))))))

  (define (read-file-string filename)
    (call-with-input-file filename read-all-as-string))

  (define (read-file-lines filename)
    (call-with-input-file filename read-all-as-lines))

  (define (write-file-string filename str)
    (call-with-output-file filename
      (lambda (port) (display str port))
      'replace))

  (define (with-input-from-string str thunk)
    (let ([port (open-input-string str)])
      (parameterize ([current-input-port port])
        (thunk))))

  (define (with-output-to-string thunk)
    (let ([port (open-output-string)])
      (parameterize ([current-output-port port])
        (thunk))
      (get-output-string port)))

  ) ;; end library
