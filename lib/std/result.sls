#!chezscheme
;;; (std result) — Result/Either monad for composable error handling
;;;
;;; Inspired by Rust's Result<T,E> and Clojure's approach to error values.
;;; Provides ok/err constructors, predicates, and combinators for
;;; building error-handling pipelines without exceptions.

(library (std result)
  (export
    ;; Constructors
    ok err
    ;; Predicates
    ok? err? result?
    ;; Accessors
    unwrap unwrap-err unwrap-or unwrap-or-else
    ;; Mapping / chaining
    map-ok map-err
    and-then or-else
    flatten-result
    ;; Conversion
    result->values
    try-result try-result*
    result->option
    ;; Collection operations
    results-partition
    map-results
    filter-ok filter-err
    sequence-results
    ;; Utilities
    ok->list err->list)

  (import (chezscheme))

  ;; --- Records ---

  (define-record-type result-ok (fields value))
  (define-record-type result-err (fields value))

  ;; --- Constructors ---

  (define (ok v) (make-result-ok v))
  (define (err e) (make-result-err e))

  ;; --- Predicates ---

  (define (ok? r) (result-ok? r))
  (define (err? r) (result-err? r))
  (define (result? r) (or (result-ok? r) (result-err? r)))

  ;; --- Accessors ---

  ;; Unwrap ok value or raise error
  (define (unwrap r)
    (if (ok? r)
      (result-ok-value r)
      (error 'unwrap "called unwrap on err" (result-err-value r))))

  ;; Unwrap err value or raise error
  (define (unwrap-err r)
    (if (err? r)
      (result-err-value r)
      (error 'unwrap-err "called unwrap-err on ok" (result-ok-value r))))

  ;; Unwrap ok value or return default
  (define (unwrap-or r default)
    (if (ok? r) (result-ok-value r) default))

  ;; Unwrap ok value or call thunk for default
  (define (unwrap-or-else r thunk)
    (if (ok? r) (result-ok-value r) (thunk)))

  ;; --- Mapping / Chaining ---

  ;; Apply f to ok value, leave err untouched
  (define (map-ok f r)
    (if (ok? r)
      (ok (f (result-ok-value r)))
      r))

  ;; Apply f to err value, leave ok untouched
  (define (map-err f r)
    (if (err? r)
      (err (f (result-err-value r)))
      r))

  ;; Monadic bind: f must return a result
  ;; (and-then (ok 5) (lambda (x) (ok (* x 2)))) => (ok 10)
  ;; (and-then (err "bad") (lambda (x) (ok (* x 2)))) => (err "bad")
  (define (and-then r f)
    (if (ok? r)
      (f (result-ok-value r))
      r))

  ;; Try alternative on error
  ;; (or-else (err "bad") (lambda (e) (ok 0))) => (ok 0)
  (define (or-else r f)
    (if (err? r)
      (f (result-err-value r))
      r))

  ;; Flatten nested results: (ok (ok x)) => (ok x)
  (define (flatten-result r)
    (if (and (ok? r) (result? (result-ok-value r)))
      (result-ok-value r)
      r))

  ;; --- Conversion ---

  ;; Convert result to values: (values value-or-#f error-or-#f)
  (define (result->values r)
    (if (ok? r)
      (values (result-ok-value r) #f)
      (values #f (result-err-value r))))

  ;; Wrap an expression that might throw — catches exceptions as err
  ;; (try-result (/ 1 0)) => (err <condition>)
  (define-syntax try-result
    (syntax-rules ()
      [(_ body)
       (guard (exn [#t (err exn)])
         (ok body))]))

  ;; try-result* — wrap body, convert exception message to string err
  (define-syntax try-result*
    (syntax-rules ()
      [(_ body)
       (guard (exn
               [#t (err (if (message-condition? exn)
                           (condition-message exn)
                           (format "~a" exn)))])
         (ok body))]))

  ;; Convert to option: ok -> value, err -> #f
  (define (result->option r)
    (if (ok? r) (result-ok-value r) #f))

  ;; --- Collection Operations ---

  ;; Partition a list of results into (ok-values . err-values)
  (define (results-partition results)
    (let loop ([rest results] [oks '()] [errs '()])
      (if (null? rest)
        (cons (reverse oks) (reverse errs))
        (let ([r (car rest)])
          (if (ok? r)
            (loop (cdr rest) (cons (result-ok-value r) oks) errs)
            (loop (cdr rest) oks (cons (result-err-value r) errs)))))))

  ;; Map a function that returns results, collect all
  (define (map-results f lst)
    (map f lst))

  ;; Keep only ok values
  (define (filter-ok results)
    (let loop ([rest results] [acc '()])
      (if (null? rest) (reverse acc)
        (if (ok? (car rest))
          (loop (cdr rest) (cons (result-ok-value (car rest)) acc))
          (loop (cdr rest) acc)))))

  ;; Keep only err values
  (define (filter-err results)
    (let loop ([rest results] [acc '()])
      (if (null? rest) (reverse acc)
        (if (err? (car rest))
          (loop (cdr rest) (cons (result-err-value (car rest)) acc))
          (loop (cdr rest) acc)))))

  ;; Collect list of results into result of list
  ;; All must be ok, or returns first err
  (define (sequence-results results)
    (let loop ([rest results] [acc '()])
      (cond
        [(null? rest) (ok (reverse acc))]
        [(ok? (car rest))
         (loop (cdr rest) (cons (result-ok-value (car rest)) acc))]
        [else (car rest)])))  ;; return first err

  ;; --- Utilities ---

  ;; ok -> (value), err -> ()
  (define (ok->list r)
    (if (ok? r) (list (result-ok-value r)) '()))

  ;; err -> (value), ok -> ()
  (define (err->list r)
    (if (err? r) (list (result-err-value r)) '()))

  ) ;; end library
