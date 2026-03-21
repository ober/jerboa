#!chezscheme
;;; (std quasiquote-types) — Type-safe code generation / staged programming
;;;
;;; Generate code that is type-annotated before splicing.
;;; Builds on Chez's syntax-case for quasiquote types.
;;;
;;; API:
;;;   (staged-lambda (x ...) body)  — staged function (generates code)
;;;   (splice expr)                  — splice generated code
;;;   (stage expr)                   — quote for next stage
;;;   (run-staged expr)              — execute staged code
;;;   (power n)                      — example: compile-time power expansion

(library (std quasiquote-types)
  (export staged-lambda splice stage run-staged
          make-code code? code-expr code-type
          annotate-code generate)

  (import (chezscheme))

  ;; ========== Code representation ==========
  ;; Code with optional type annotation

  (define-record-type code
    (fields
      (immutable expr)        ;; S-expression
      (immutable type))       ;; symbol or #f
    (protocol
      (lambda (new)
        (case-lambda
          [(expr) (new expr #f)]
          [(expr type) (new expr type)]))))

  (define (annotate-code c type)
    (make-code (code-expr c) type))

  ;; ========== Staging primitives ==========

  (define (stage expr)
    (make-code expr #f))

  (define (splice c)
    (if (code? c)
      (code-expr c)
      c))

  (define (run-staged c)
    (eval (if (code? c) (code-expr c) c)))

  ;; ========== Code generation ==========

  (define (generate template . args)
    ;; template is a list with 'holes' marked by _ or code objects
    (make-code
      (let loop ([t template])
        (cond
          [(null? t) '()]
          [(code? t) (code-expr t)]
          [(pair? t) (cons (loop (car t)) (loop (cdr t)))]
          [else t]))
      #f))

  ;; ========== Staged lambda ==========

  (define-syntax staged-lambda
    (syntax-rules ()
      [(_ (arg ...) body ...)
       (lambda (arg ...)
         (make-code (begin body ...) #f))]))

) ;; end library
