#!chezscheme
;;; :std/srfi/128 -- Comparators (SRFI-128)
;;; Provides comparator objects for use with sorted containers.

(library (std srfi srfi-128)
  (export
    make-comparator comparator?
    comparator-type-test-predicate
    comparator-equality-predicate
    comparator-ordering-predicate
    comparator-hash-function
    comparator-ordered? comparator-hashable?
    comparator-test-type comparator-check-type
    comparator-hash
    =? <? >? <=? >=?
    make-default-comparator
    default-hash
    boolean-comparator char-comparator
    string-comparator number-comparator
    symbol-comparator)

  (import (chezscheme))

  (define-record-type comparator-rec
    (fields
      (immutable type-test)
      (immutable equality)
      (immutable ordering)
      (immutable hash-fn))
    (sealed #t))

  (define (make-comparator type-test equality ordering hash-fn)
    (make-comparator-rec
      (or type-test (lambda (x) #t))
      (or equality equal?)
      ordering
      hash-fn))

  (define (comparator? x) (comparator-rec? x))

  (define (comparator-type-test-predicate c) (comparator-rec-type-test c))
  (define (comparator-equality-predicate c) (comparator-rec-equality c))
  (define (comparator-ordering-predicate c) (comparator-rec-ordering c))
  (define (comparator-hash-function c) (comparator-rec-hash-fn c))

  (define (comparator-ordered? c)
    (and (comparator-rec-ordering c) #t))
  (define (comparator-hashable? c)
    (and (comparator-rec-hash-fn c) #t))

  (define (comparator-test-type c obj)
    ((comparator-rec-type-test c) obj))
  (define (comparator-check-type c obj)
    (unless ((comparator-rec-type-test c) obj)
      (error 'comparator-check-type "type test failed" obj)))

  (define (comparator-hash c obj)
    (if (comparator-rec-hash-fn c)
      ((comparator-rec-hash-fn c) obj)
      (error 'comparator-hash "comparator has no hash function")))

  (define (=? c a b) ((comparator-rec-equality c) a b))
  (define (<? c a b) ((comparator-rec-ordering c) a b))
  (define (>? c a b) ((comparator-rec-ordering c) b a))
  (define (<=? c a b) (or (=? c a b) (<? c a b)))
  (define (>=? c a b) (or (=? c a b) (>? c a b)))

  (define (default-hash obj)
    (cond
      [(string? obj) (string-hash obj)]
      [(number? obj) (equal-hash obj)]
      [(symbol? obj) (symbol-hash obj)]
      [(char? obj) (char->integer obj)]
      [(boolean? obj) (if obj 1 0)]
      [else (equal-hash obj)]))

  (define (make-default-comparator)
    (make-comparator
      (lambda (x) #t)
      equal?
      (lambda (a b)
        (cond
          [(and (number? a) (number? b)) (< a b)]
          [(and (string? a) (string? b)) (string<? a b)]
          [(and (char? a) (char? b)) (char<? a b)]
          [(and (symbol? a) (symbol? b))
           (string<? (symbol->string a) (symbol->string b))]
          [else (string<? (format "~s" a) (format "~s" b))]))
      default-hash))

  (define boolean-comparator
    (make-comparator boolean? boolean=?
      (lambda (a b) (and (not a) b))
      (lambda (x) (if x 1 0))))

  (define char-comparator
    (make-comparator char? char=? char<? char->integer))

  (define string-comparator
    (make-comparator string? string=? string<? string-hash))

  (define number-comparator
    (make-comparator number? = < equal-hash))

  (define symbol-comparator
    (make-comparator symbol? eq?
      (lambda (a b)
        (string<? (symbol->string a) (symbol->string b)))
      symbol-hash))

) ;; end library
