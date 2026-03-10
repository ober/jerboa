#!chezscheme
;;; :std/error -- Gerbil error types and utilities

(library (std error)
  (export
    error? error-message error-irritants error-trace
    Error ContractViolation
    raise-error with-exception-handler)
  (import (chezscheme))

  ;; In Chez, errors are conditions. Provide Gerbil-compatible access.

  (define (error-message e)
    (if (message-condition? e)
      (condition-message e)
      (format "~a" e)))

  (define (error-irritants e)
    (if (irritants-condition? e)
      (condition-irritants e)
      '()))

  (define (error-trace e)
    (if (condition? e)
      (format "~a" e)
      ""))

  ;; Error constructor compatible with Gerbil
  (define (Error message . irritants)
    (condition
      (make-error)
      (make-message-condition message)
      (make-irritants-condition irritants)))

  (define (ContractViolation message . irritants)
    (condition
      (make-assertion-violation)
      (make-message-condition message)
      (make-irritants-condition irritants)))

  (define (raise-error where message . irritants)
    (raise (condition
             (make-error)
             (make-who-condition where)
             (make-message-condition message)
             (make-irritants-condition irritants))))

  ) ;; end library
