#!chezscheme
;;; :std/values -- Multiple values utilities

(library (std values)
  (export values->list
          values-ref
          receive)
  (import (chezscheme))

  ;; (values->list expr) -- captures multiple values as a list
  (define-syntax values->list
    (syntax-rules ()
      [(_ expr)
       (call-with-values (lambda () expr) list)]))

  ;; (values-ref expr index) -- extract the nth value
  (define-syntax values-ref
    (syntax-rules ()
      [(_ expr index)
       (call-with-values (lambda () expr)
         (lambda args (list-ref args index)))]))

  ;; SRFI-8: receive
  ;; (receive formals expr body ...)
  ;; Binds the multiple values of expr to formals and evaluates body.
  (define-syntax receive
    (syntax-rules ()
      [(_ formals expr body ...)
       (call-with-values (lambda () expr)
         (lambda formals body ...))]))

  ) ;; end library
