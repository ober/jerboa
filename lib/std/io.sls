#!chezscheme
;;; (std io) — Structured I/O for s-expressions
;;;
;;; Convenience procedures for reading/writing s-expression data files.

(library (std io)
  (export read-sexp-file write-sexp-file
          read-sexp-port write-sexp-port
          read-all write-all
          with-input with-output)
  (import (chezscheme))

  (define (read-all port)
    (let lp ([acc '()])
      (let ([datum (read port)])
        (if (eof-object? datum)
            (reverse acc)
            (lp (cons datum acc))))))

  (define (write-all lst port)
    (for-each (lambda (datum)
                (write datum port)
                (newline port))
              lst))

  (define read-sexp-port read-all)
  (define write-sexp-port write-all)

  (define (read-sexp-file path)
    (call-with-input-file path read-all))

  (define (write-sexp-file lst path)
    (call-with-output-file path
      (lambda (port) (write-all lst port))
      'replace))

  (define-syntax with-input
    (syntax-rules ()
      [(_ path body ...)
       (call-with-input-file path
         (lambda (port)
           (parameterize ([current-input-port port])
             body ...)))]))

  (define-syntax with-output
    (syntax-rules ()
      [(_ path body ...)
       (call-with-output-file path
         (lambda (port)
           (parameterize ([current-output-port port])
             body ...))
         'replace)]))

  ) ;; end library
