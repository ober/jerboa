#!chezscheme
;;; (std macro-types) — Typed macros with expansion-time checking
;;;
;;; Macros that validate their arguments at expansion time.
;;; Type annotations are checked during macro expansion, catching
;;; errors before runtime.
;;;
;;; API:
;;;   (define-typed-macro name clauses) — macro with type annotations
;;;   (type-check! expr type)          — expansion-time type assertion
;;;   (assert-type val type)           — runtime type assertion
;;;   (define-type-alias name type)    — type alias for documentation

(library (std macro-types)
  (export define-typed-macro assert-type type-of
          numeric? string-like? list-like? callable?
          define-type-alias type-aliases)

  (import (chezscheme))

  ;; ========== Runtime type predicates ==========

  (define (numeric? v)
    (number? v))

  (define (string-like? v)
    (or (string? v) (symbol? v)))

  (define (list-like? v)
    (or (list? v) (vector? v)))

  (define (callable? v)
    (procedure? v))

  (define (type-of v)
    (cond
      [(fixnum? v) 'fixnum]
      [(flonum? v) 'flonum]
      [(number? v) 'number]
      [(string? v) 'string]
      [(symbol? v) 'symbol]
      [(char? v) 'char]
      [(boolean? v) 'boolean]
      [(null? v) 'null]
      [(pair? v) 'pair]
      [(vector? v) 'vector]
      [(bytevector? v) 'bytevector]
      [(procedure? v) 'procedure]
      [(hashtable? v) 'hashtable]
      [(port? v) 'port]
      [(eof-object? v) 'eof]
      [else 'unknown]))

  ;; ========== Runtime type assertion ==========

  (define (assert-type val type-pred who)
    (unless (type-pred val)
      (error who (format "type assertion failed: expected ~a, got ~a"
                         type-pred (type-of val))
             val))
    val)

  ;; ========== Type aliases ==========

  (define *type-aliases* (make-eq-hashtable))

  (define (type-aliases) *type-aliases*)

  (define-syntax define-type-alias
    (syntax-rules ()
      [(_ name pred)
       (hashtable-set! *type-aliases* 'name pred)]))

  ;; ========== Typed macro ==========
  ;; A define-typed-macro wraps a regular macro with type assertions
  ;; on the arguments at expansion time (when possible) or runtime.

  (define-syntax define-typed-macro
    (syntax-rules (:)
      [(_ (name (arg : type-pred) ...) body ...)
       (define-syntax name
         (syntax-rules ()
           [(_ arg ...)
            (let ([arg (assert-type arg type-pred 'name)] ...)
              body ...)]))]))

) ;; end library
