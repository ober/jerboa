#!chezscheme
;;; :std/srfi/8 -- SRFI-8 receive: Binding to values of multiple-value expressions
;;; (receive formals expr body ...) binds the values of expr to formals.

(library (std srfi srfi-8)
  (export receive)

  (import (chezscheme))

  (define-syntax receive
    (syntax-rules ()
      [(_ formals expr body ...)
       (call-with-values (lambda () expr) (lambda formals body ...))]))

) ;; end library
