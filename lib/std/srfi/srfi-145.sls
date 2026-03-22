#!chezscheme
;;; :std/srfi/145 -- Assumptions (SRFI-145)
;;; (assume expr message ...) asserts that expr is true.
;;; If expr is false, signals an error with the given messages.

(library (std srfi srfi-145)
  (export assume)

  (import (chezscheme))

  (define-syntax assume
    (syntax-rules ()
      [(_ expr rest ...)
       (unless expr
         (error 'assume "assumption violated" 'expr rest ...))]))

) ;; end library
