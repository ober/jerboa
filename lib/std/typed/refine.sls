#!chezscheme
;;; (std typed refine) — Refinement Types
;;;
;;; A refinement type combines a base type predicate with an additional
;;; predicate. Values are checked at runtime (in define/r and lambda/r).
;;;
;;; API:
;;;   (Refine base-type pred)         — construct a refinement type spec (macro)
;;;   (make-refinement name base pred) — runtime refinement descriptor
;;;   (refinement? v)                  — predicate
;;;   (refinement-base r)              — base type symbol
;;;   (refinement-pred r)              — the refinement predicate
;;;   (refinement-name r)              — name (for error messages)
;;;   (satisfies-refinement? r val)    — runtime check, returns boolean
;;;   (check-refinement! r val who)    — check or raise error
;;;   (assert-refined expr R)          — assert in-place
;;;
;;;   Built-in refinements: NonNeg Positive NonNull NonEmpty Bounded
;;;                         NonZero Natural
;;;
;;;   (define/r (f [arg : RType] ...) body ...)  — define with checked args
;;;   (lambda/r ([arg : RType] ...) body ...)    — lambda with checked args
;;;   (with-refinement-context (proven ...) body ...) — track proven refinements
;;;   (refine-branch cond-test val refine body)  — conditional refinement

(library (std typed refine)
  (export
    ;; Type constructors
    Refine
    make-refinement
    refinement?
    refinement-base
    refinement-pred
    refinement-name
    ;; Checking
    satisfies-refinement?
    check-refinement!
    assert-refined
    ;; Common built-in refinements
    NonNeg
    Positive
    NonNull
    NonEmpty
    Bounded
    NonZero
    Natural
    ;; Annotated define/lambda
    define/r
    lambda/r
    ;; Flow-sensitive
    with-refinement-context
    refine-branch)

  (import (chezscheme))

  ;; ========== Refinement descriptor ==========

  (define-record-type refinement-descriptor
    (fields
      (immutable name)   ; symbol or string for error messages
      (immutable base)   ; base type predicate (procedure)
      (immutable pred))  ; refinement predicate (procedure)
    (sealed #t))

  (define (make-refinement name base pred)
    (make-refinement-descriptor name base pred))

  (define (refinement? v)
    (refinement-descriptor? v))

  (define (refinement-name r)
    (refinement-descriptor-name r))

  (define (refinement-base r)
    (refinement-descriptor-base r))

  (define (refinement-pred r)
    (refinement-descriptor-pred r))

  ;; ========== Runtime checking ==========

  (define (satisfies-refinement? r val)
    ;; Check base type first, then the refinement predicate.
    (let ([base (refinement-descriptor-base r)]
          [pred (refinement-descriptor-pred r)])
      (and (if base (base val) #t)
           (pred val))))

  (define (check-refinement! r val who)
    (unless (satisfies-refinement? r val)
      (error (or who 'check-refinement!)
        (format "refinement ~a failed for value ~a"
                (refinement-descriptor-name r)
                val)
        val)))

  ;; (assert-refined val R) — check and return val
  (define-syntax assert-refined
    (lambda (stx)
      (syntax-case stx ()
        [(_ val-expr R)
         #'(let ([v val-expr])
             (check-refinement! R v 'assert-refined)
             v)])))

  ;; (Refine base pred) — create a one-off refinement type
  ;; This is a macro that produces a refinement descriptor at runtime.
  (define-syntax Refine
    (lambda (stx)
      (syntax-case stx ()
        [(_ base-pred refine-pred)
         #'(make-refinement 'anonymous base-pred refine-pred)]
        [(_ name base-pred refine-pred)
         #'(make-refinement 'name base-pred refine-pred)])))

  ;; ========== Common built-in refinements ==========

  (define NonNeg
    (make-refinement 'NonNeg number? (lambda (x) (>= x 0))))

  (define Positive
    (make-refinement 'Positive number? (lambda (x) (> x 0))))

  (define NonNull
    (make-refinement 'NonNull #f (lambda (x) (not (null? x)))))

  (define NonEmpty
    (make-refinement 'NonEmpty #f (lambda (x)
                                    (cond
                                      [(list? x) (not (null? x))]
                                      [(string? x) (> (string-length x) 0)]
                                      [(vector? x) (> (vector-length x) 0)]
                                      [else (not (null? x))]))))

  ;; (Bounded lo hi) — a refinement parameterized by bounds
  (define (Bounded lo hi)
    (make-refinement
      (string->symbol (format "Bounded[~a,~a]" lo hi))
      number?
      (lambda (x) (and (>= x lo) (<= x hi)))))

  (define NonZero
    (make-refinement 'NonZero number? (lambda (x) (not (zero? x)))))

  (define Natural
    (make-refinement 'Natural #f (lambda (x) (and (integer? x) (>= x 0)))))

  ;; ========== define/r and lambda/r ==========
  ;;
  ;; Syntax: (define/r (name [arg : RefType] ...) body ...)
  ;; Each [arg : RefType] where RefType is a refinement descriptor causes
  ;; a runtime check on function entry.

  ;; Parse a list of arg specs, each either [name : RType] or name.
  ;; Returns two lists: (names rtypes-or-#f).
  ;; When called at expand time, use the procedural helper below.

  ;; lambda/r and define/r use a helper to process argument specs.
  ;; Each arg-spec can be:
  ;;   [name : RType]   — a 3-element list with : in the middle
  ;;   name             — a plain identifier (no refinement)

  (define-syntax lambda/r
    (lambda (stx)
      (define (typed-arg? x)
        ;; A typed arg is a 3-element list with : in the middle
        (and (list? x)
             (= (length x) 3)
             (eq? (cadr x) ':)))
      (syntax-case stx ()
        [(_ argspecs body ...)
         (let* ([raw-args (syntax->datum #'argspecs)]
                [has-typed? (and (list? raw-args)
                                 (exists typed-arg? raw-args))]
                ;; Use the lambda/r keyword as context identifier for datum->syntax
                [ctx (car (syntax->list stx))])
           (if has-typed?
             (let* ([all-names (map (lambda (x)
                                      (if (typed-arg? x) (car x) x))
                                    raw-args)]
                    [typed-only (filter typed-arg? raw-args)])
               (with-syntax
                 ([(arg-name ...) (map (lambda (n) (datum->syntax ctx n))
                                        all-names)]
                  [(check-name ...) (map (lambda (ta)
                                            (datum->syntax ctx (car ta)))
                                          typed-only)]
                  [(rtype-name ...) (map (lambda (ta)
                                            (datum->syntax ctx (caddr ta)))
                                          typed-only)])
                 #'(lambda (arg-name ...)
                     (check-refinement! rtype-name check-name 'lambda/r) ...
                     body ...)))
             #'(lambda argspecs body ...)))])))

  (define-syntax define/r
    (lambda (stx)
      (define (typed-arg? x)
        (and (list? x)
             (= (length x) 3)
             (eq? (cadr x) ':)))
      (syntax-case stx ()
        [(_ (name . argspecs) body ...)
         (let* ([raw-args (syntax->datum #'argspecs)]
                [has-typed? (and (list? raw-args)
                                 (exists typed-arg? raw-args))])
           (if has-typed?
             (let* ([all-names (map (lambda (x)
                                      (if (typed-arg? x) (car x) x))
                                    raw-args)]
                    [typed-only (filter typed-arg? raw-args)]
                    [fn-name (syntax->datum #'name)])
               (with-syntax
                 ([(arg-name ...) (map (lambda (n) (datum->syntax #'name n))
                                        all-names)]
                  [(check-name ...) (map (lambda (ta)
                                            (datum->syntax #'name (car ta)))
                                          typed-only)]
                  [(rtype-name ...) (map (lambda (ta)
                                            (datum->syntax #'name (caddr ta)))
                                          typed-only)]
                  [who (datum->syntax #'name fn-name)])
                 #'(define (name arg-name ...)
                     (check-refinement! rtype-name check-name 'who) ...
                     body ...)))
             #'(define (name . argspecs) body ...)))]
        [(_ name val)
         #'(define name val)])))

  ;; ========== Flow-sensitive refinement context ==========
  ;;
  ;; with-refinement-context: track which refinements are already proven
  ;; to avoid redundant checks.

  ;; A parameter holding a list of (value . refinement-name) pairs.
  (define *refinement-context*
    (make-parameter '()))

  ;; with-refinement-context: mark some (val refinement-name) pairs as proven
  (define-syntax with-refinement-context
    (lambda (stx)
      (syntax-case stx ()
        [(_ ((val-expr refinement-name) ...) body ...)
         #'(parameterize
               ([*refinement-context*
                 (append
                   (list (cons val-expr 'refinement-name) ...)
                   (*refinement-context*))])
             body ...)])))

  ;; refine-branch: in a conditional, assert refinement in the true branch
  ;; (refine-branch val R true-branch false-branch)
  ;; In the true branch, val is known to satisfy R.
  (define-syntax refine-branch
    (lambda (stx)
      (syntax-case stx ()
        [(_ val-expr R true-body false-body)
         #'(let ([v val-expr])
             (if (satisfies-refinement? R v)
               (begin true-body)
               (begin false-body)))])))

) ; end library
