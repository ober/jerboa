#!chezscheme
;;; (std comptime) — Zig-style compile-time execution
;;;
;;; Execute arbitrary Scheme expressions at compile time and splice results.
;;; Uses Chez's eval-when and meta facilities.
;;;
;;; API:
;;;   (comptime expr)                  — evaluate expr at compile time, splice result
;;;   (define-comptime (name args ...) body ...) — define a compile-time function
;;;   (comptime-define name expr)      — define a compile-time constant
;;;   (comptime-table proc n)          — generate a lookup vector at compile time
;;;   (comptime-cond pred then else)   — conditional compilation

(library (std comptime)
  (export comptime define-comptime comptime-define
          comptime-table comptime-cond comptime-if)

  (import (chezscheme))

  ;; comptime: evaluate at expand time, splice the result as a literal
  (define-syntax comptime
    (lambda (stx)
      (syntax-case stx ()
        [(k expr)
         (let ([val (eval (syntax->datum #'expr))])
           (datum->syntax #'k val))])))

  ;; define-comptime: define a function available at compile time
  ;; The function is available both at compile time (meta level) and runtime.
  (define-syntax define-comptime
    (syntax-rules ()
      [(_ (name arg ...) body ...)
       (begin
         (meta define (name arg ...) body ...)
         (define (name arg ...) body ...))]))

  ;; comptime-define: bind a name to a compile-time computed value
  (define-syntax comptime-define
    (lambda (stx)
      (syntax-case stx ()
        [(k name expr)
         (let ([val (eval (syntax->datum #'expr))])
           (with-syntax ([v (datum->syntax #'k val)])
             #'(define name v)))])))

  ;; comptime-table: generate a vector lookup table at compile time
  ;; (comptime-table (lambda (i) (* i i)) 256) => #(0 1 4 9 16 ...)
  (define-syntax comptime-table
    (lambda (stx)
      (syntax-case stx ()
        [(k proc-expr size-expr)
         (let* ([proc (eval (syntax->datum #'proc-expr))]
                [size (eval (syntax->datum #'size-expr))]
                [vec (let ([v (make-vector size)])
                       (do ([i 0 (+ i 1)])
                           ((= i size) v)
                         (vector-set! v i (proc i))))])
           ;; Convert to list form that syntax can handle
           (with-syntax ([v (datum->syntax #'k (vector->list vec))])
             #'(list->vector 'v)))])))

  ;; comptime-if: conditional compilation
  (define-syntax comptime-if
    (lambda (stx)
      (syntax-case stx ()
        [(_ pred-expr then-expr else-expr)
         (if (eval (syntax->datum #'pred-expr))
           #'then-expr
           #'else-expr)])))

  ;; comptime-cond: multi-branch conditional compilation
  (define-syntax comptime-cond
    (syntax-rules (else)
      [(_ [else body ...])
       (begin body ...)]
      [(_ [pred body ...] rest ...)
       (comptime-if pred (begin body ...) (comptime-cond rest ...))]))

) ;; end library
