#!chezscheme
;;; (std stxutil) — Syntax utilities for macro writers
;;;
;;; Helpers for working with syntax objects in define-syntax macros.

(library (std stxutil)
  (export stx-car stx-cdr stx-null? stx-pair? stx-list?
          stx-map stx-for-each stx-length
          stx->datum datum->stx
          stx-identifier? stx-e
          genident with-syntax*)

  (import (chezscheme))

  ;; Accessors that work on both syntax objects and raw pairs
  (define (stx-car stx)
    (syntax-case stx ()
      [(a . d) #'a]))

  (define (stx-cdr stx)
    (syntax-case stx ()
      [(a . d) #'d]))

  (define (stx-null? stx)
    (syntax-case stx ()
      [() #t]
      [_ #f]))

  (define (stx-pair? stx)
    (syntax-case stx ()
      [(a . d) #t]
      [_ #f]))

  (define (stx-list? stx)
    (syntax-case stx ()
      [() #t]
      [(a . d) (stx-list? #'d)]
      [_ #f]))

  (define (stx-length stx)
    (let loop ([s stx] [n 0])
      (syntax-case s ()
        [() n]
        [(a . d) (loop #'d (+ n 1))])))

  (define (stx-map proc stx)
    (syntax-case stx ()
      [() '()]
      [(a . d) (cons (proc #'a) (stx-map proc #'d))]))

  (define (stx-for-each proc stx)
    (syntax-case stx ()
      [() (void)]
      [(a . d) (begin (proc #'a) (stx-for-each proc #'d))]))

  ;; Convert syntax to datum
  (define (stx->datum stx)
    (syntax->datum stx))

  ;; Convert datum to syntax using a context
  (define (datum->stx ctx datum)
    (datum->syntax ctx datum))

  ;; Check if syntax is an identifier
  (define (stx-identifier? stx)
    (identifier? stx))

  ;; Extract datum from syntax (alias for syntax->datum)
  (define (stx-e stx)
    (syntax->datum stx))

  ;; Generate a unique identifier
  (define genident
    (case-lambda
      [() (car (generate-temporaries '(g)))]
      [(prefix) (car (generate-temporaries (list prefix)))]))

  ;; Sequential with-syntax: each binding can refer to previous ones.
  ;; (with-syntax* ((a expr1) (b expr2-using-a)) body)
  ;; Implemented as a macro.
  (define-syntax with-syntax*
    (syntax-rules ()
      [(_ () body ...) (begin body ...)]
      [(_ ((pat expr) rest ...) body ...)
       (with-syntax ([pat expr])
         (with-syntax* (rest ...) body ...))]))

) ;; end library
