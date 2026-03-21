#!chezscheme
;;; (std misc func) — Functional combinators
;;;
;;; Core functional utilities matching Gerbil's patterns.

(library (std misc func)
  (export compose compose1 identity constantly flip
          curry curryn negate conjoin disjoin
          memo-proc juxt)

  (import (chezscheme))

  ;; Identity function
  (define (identity x) x)

  ;; Return a function that always returns val
  (define (constantly val)
    (lambda args val))

  ;; Swap first two arguments
  (define (flip f)
    (lambda (a b . rest)
      (apply f b a rest)))

  ;; Compose functions (right-to-left): (compose f g h) = (lambda (x) (f (g (h x))))
  ;; Handles multiple return values between stages.
  (define (compose . procs)
    (cond
      [(null? procs) values]
      [(null? (cdr procs)) (car procs)]
      [else
       (let ([f (car procs)]
             [g (apply compose (cdr procs))])
         (lambda args
           (call-with-values (lambda () (apply g args)) f)))]))

  ;; Compose for single-value functions (no call-with-values overhead)
  (define (compose1 . procs)
    (cond
      [(null? procs) identity]
      [(null? (cdr procs)) (car procs)]
      [else
       (let ([f (car procs)]
             [g (apply compose1 (cdr procs))])
         (lambda (x) (f (g x))))]))

  ;; Partial application (curry first argument)
  (define (curry f . args)
    (lambda rest
      (apply f (append args rest))))

  ;; Curry N arguments
  (define (curryn n f)
    (if (<= n 0)
        (f)
        (lambda (x)
          (curryn (- n 1) (curry f x)))))

  ;; Negate a predicate
  (define (negate pred)
    (lambda args
      (not (apply pred args))))

  ;; AND predicates: all must be true
  (define (conjoin . preds)
    (lambda (x)
      (let loop ([ps preds])
        (or (null? ps)
            (and ((car ps) x) (loop (cdr ps)))))))

  ;; OR predicates: any must be true
  (define (disjoin . preds)
    (lambda (x)
      (let loop ([ps preds])
        (and (not (null? ps))
             (or ((car ps) x) (loop (cdr ps)))))))

  ;; Simple memoization (eq? hash table)
  (define (memo-proc proc)
    (let ([cache (make-eq-hashtable)])
      (lambda (x)
        (or (hashtable-ref cache x #f)
            (let ([v (proc x)])
              (hashtable-set! cache x v)
              v)))))

  ;; Apply multiple functions to same args, return list of results
  (define (juxt . procs)
    (lambda args
      (map (lambda (f) (apply f args)) procs)))

) ;; end library
