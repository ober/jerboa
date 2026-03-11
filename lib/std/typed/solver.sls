#!chezscheme
;;; (std typed solver) — Lightweight constraint solver for static refinement proofs
;;;
;;; Handles only LITERALS conservatively:
;;;   - 0 is zero, null is null, 1 2 3... are positive, "" is empty-string
;;;   - Branching: in (if (null? x) ...) true-branch, x is null-refined
;;;   - Returns 'satisfied | 'violated | 'unknown
;;;
;;; API:
;;;   (make-constraint pred args)    — constraint record
;;;   (constraint? v)                — predicate
;;;   (constraint-pred c)            — symbol
;;;   (constraint-args c)            — list
;;;   (solve-constraint c)           — 'satisfied | 'violated | 'unknown
;;;   (can-prove? c)                 — boolean
;;;   (can-refute? c)                — boolean
;;;   (is-literal-zero? expr)        — boolean
;;;   (is-literal-null? expr)        — boolean
;;;   (is-literal-positive? expr)    — boolean
;;;   (make-solver-context)          — fresh context
;;;   (solver-context-add! ctx var refinement) — record known fact
;;;   (solver-context-lookup ctx var)          — lookup refinement or #f
;;;   (with-solver-context ctx thunk)          — run with context

(library (std typed solver)
  (export
    ;; Constraint representation
    make-constraint
    constraint?
    constraint-pred
    constraint-args
    ;; Solving
    solve-constraint
    can-prove?
    can-refute?
    ;; Literal analysis
    is-literal-zero?
    is-literal-null?
    is-literal-positive?
    ;; Context
    make-solver-context
    solver-context-add!
    solver-context-lookup
    with-solver-context)

  (import (chezscheme))

  ;; ========== Constraint record ==========

  (define-record-type constraint-record
    (fields
      (immutable pred)   ; symbol naming the predicate, e.g. 'zero? 'null? 'positive?
      (immutable args))  ; list of argument expressions (datums or symbols)
    (sealed #t))

  (define (make-constraint pred args)
    (make-constraint-record pred args))

  (define (constraint? v)
    (constraint-record? v))

  (define (constraint-pred c)
    (constraint-record-pred c))

  (define (constraint-args c)
    (constraint-record-args c))

  ;; ========== Literal analysis ==========
  ;;
  ;; These operate on datum expressions (the value itself or quoted data).

  ;; Is the expression provably zero (the number zero)?
  (define (is-literal-zero? expr)
    (and (number? expr) (zero? expr)))

  ;; Is the expression provably null (empty list)?
  (define (is-literal-null? expr)
    (null? expr))

  ;; Is the expression provably positive (a positive number literal)?
  (define (is-literal-positive? expr)
    (and (number? expr) (positive? expr)))

  ;; Is the expression provably a non-empty string?
  (define (is-literal-non-empty-string? expr)
    (and (string? expr) (> (string-length expr) 0)))

  ;; Is the expression provably a non-zero number?
  (define (is-literal-nonzero? expr)
    (and (number? expr) (not (zero? expr))))

  ;; Is the expression provably non-negative?
  (define (is-literal-nonneg? expr)
    (and (number? expr) (>= expr 0)))

  ;; Is the expression provably an exact non-negative integer (natural)?
  (define (is-literal-natural? expr)
    (and (integer? expr) (exact? expr) (>= expr 0)))

  ;; ========== Solver context ==========
  ;;
  ;; A context maps variable names (symbols) to known refinements (symbols
  ;; like 'null, 'positive, 'zero, 'non-null, etc.).

  (define (make-solver-context)
    (make-eq-hashtable))

  (define (solver-context-add! ctx var-sym refinement-sym)
    (hashtable-set! ctx var-sym refinement-sym))

  (define (solver-context-lookup ctx var-sym)
    (hashtable-ref ctx var-sym #f))

  ;; Current solver context (a parameter)
  (define *current-solver-context*
    (make-parameter #f))

  (define (with-solver-context ctx thunk)
    (parameterize ([*current-solver-context* ctx])
      (thunk)))

  ;; ========== Core solver ==========
  ;;
  ;; solve-constraint: given a constraint, try to prove it satisfied or violated.
  ;; Returns one of: 'satisfied 'violated 'unknown
  ;;
  ;; We only handle simple cases to be conservative (never false-proved).

  (define (solve-constraint c)
    (let ([pred (constraint-pred c)]
          [args (constraint-args c)])
      (case pred
        ;; (zero? x) — satisfied iff x is the literal 0
        [(zero?)
         (if (pair? args)
           (let ([x (car args)])
             (cond
               [(is-literal-zero? x)     'satisfied]
               [(is-literal-positive? x) 'violated]
               [(and (number? x) (not (zero? x))) 'violated]
               ;; Check context if x is a symbol
               [(and (symbol? x) (*current-solver-context*))
                (let ([known (solver-context-lookup (*current-solver-context*) x)])
                  (cond
                    [(eq? known 'zero)     'satisfied]
                    [(eq? known 'positive) 'violated]
                    [(eq? known 'nonzero)  'violated]
                    [else 'unknown]))]
               [else 'unknown]))
           'unknown)]

        ;; (null? x) — satisfied iff x is '()
        [(null?)
         (if (pair? args)
           (let ([x (car args)])
             (cond
               [(is-literal-null? x) 'satisfied]
               [(and (pair? x))      'violated]  ; a pair can't be null
               [(and (symbol? x) (*current-solver-context*))
                (let ([known (solver-context-lookup (*current-solver-context*) x)])
                  (cond
                    [(eq? known 'null)     'satisfied]
                    [(eq? known 'non-null) 'violated]
                    [(eq? known 'pair)     'violated]
                    [else 'unknown]))]
               [else 'unknown]))
           'unknown)]

        ;; (positive? x) — satisfied iff x is a positive number literal
        [(positive?)
         (if (pair? args)
           (let ([x (car args)])
             (cond
               [(is-literal-positive? x) 'satisfied]
               [(is-literal-zero? x)     'violated]
               [(and (number? x) (negative? x)) 'violated]
               [(and (symbol? x) (*current-solver-context*))
                (let ([known (solver-context-lookup (*current-solver-context*) x)])
                  (cond
                    [(eq? known 'positive) 'satisfied]
                    [(eq? known 'zero)     'violated]
                    [(eq? known 'negative) 'violated]
                    [else 'unknown]))]
               [else 'unknown]))
           'unknown)]

        ;; (negative? x)
        [(negative?)
         (if (pair? args)
           (let ([x (car args)])
             (cond
               [(and (number? x) (negative? x)) 'satisfied]
               [(and (number? x) (>= x 0))      'violated]
               [(and (symbol? x) (*current-solver-context*))
                (let ([known (solver-context-lookup (*current-solver-context*) x)])
                  (cond
                    [(eq? known 'negative) 'satisfied]
                    [(eq? known 'positive) 'violated]
                    [(eq? known 'zero)     'violated]
                    [else 'unknown]))]
               [else 'unknown]))
           'unknown)]

        ;; (number? x) — satisfied for all number literals only
        [(number?)
         (if (pair? args)
           (let ([x (car args)])
             (cond
               [(number? x) 'satisfied]
               ;; Only say violated for concrete non-number literals (not symbols, which are variables)
               [(or (string? x) (boolean? x) (null? x) (pair? x))
                'violated]
               [else 'unknown]))
           'unknown)]

        ;; (string? x) — satisfied for string literals
        [(string?)
         (if (pair? args)
           (let ([x (car args)])
             (cond
               [(string? x) 'satisfied]
               [(or (number? x) (boolean? x) (null? x) (pair? x)) 'violated]
               [else 'unknown]))
           'unknown)]

        ;; (boolean? x)
        [(boolean?)
         (if (pair? args)
           (let ([x (car args)])
             (cond
               [(boolean? x) 'satisfied]
               [(or (number? x) (string? x) (null? x) (pair? x)) 'violated]
               [else 'unknown]))
           'unknown)]

        ;; (pair? x)
        [(pair?)
         (if (pair? args)
           (let ([x (car args)])
             (cond
               [(pair? x)   'satisfied]
               [(null? x)   'violated]
               [(number? x) 'violated]
               [(string? x) 'violated]
               [(boolean? x) 'violated]
               [(and (symbol? x) (*current-solver-context*))
                (let ([known (solver-context-lookup (*current-solver-context*) x)])
                  (cond
                    [(eq? known 'pair)     'satisfied]
                    [(eq? known 'null)     'violated]
                    [else 'unknown]))]
               [else 'unknown]))
           'unknown)]

        ;; (integer? x)
        [(integer?)
         (if (pair? args)
           (let ([x (car args)])
             (cond
               [(and (number? x) (integer? x)) 'satisfied]
               [(and (number? x) (not (integer? x))) 'violated]
               [(string? x) 'violated]
               [else 'unknown]))
           'unknown)]

        ;; (equal? x y) — only handle literal equality
        [(equal? eqv? eq?)
         (if (and (pair? args) (pair? (cdr args)))
           (let ([x (car args)] [y (cadr args)])
             (cond
               [(equal? x y) 'satisfied]
               [(and (self-evaluating? x) (self-evaluating? y)
                     (not (equal? x y)))
                'violated]
               [else 'unknown]))
           'unknown)]

        ;; Default: unknown
        [else 'unknown])))

  ;; Helper: is this a self-evaluating datum?
  (define (self-evaluating? x)
    (or (number? x) (string? x) (boolean? x) (char? x) (null? x)))

  ;; ========== can-prove? / can-refute? ==========

  (define (can-prove? c)
    (eq? (solve-constraint c) 'satisfied))

  (define (can-refute? c)
    (eq? (solve-constraint c) 'violated))

) ; end library
