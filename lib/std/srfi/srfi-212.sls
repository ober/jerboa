#!chezscheme
;;; :std/srfi/212 -- Aliases (SRFI-212)
;;; (alias new-name old-name) creates a binding identical to old-name.
;;; Works for both variables and syntax.

(library (std srfi srfi-212)
  (export alias)

  (import (except (chezscheme) alias))

  (define-syntax alias
    (syntax-rules ()
      [(_ new old)
       (define-syntax new (identifier-syntax old))]))
)
