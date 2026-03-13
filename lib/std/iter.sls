#!chezscheme
;;; :std/iter -- Gerbil-compatible iterator macros
;;;
;;; Provides for, for/collect, for/fold, for/or, for/and
;;; with iterator constructors: in-list, in-vector, in-range,
;;; in-string, in-hash-keys, in-hash-values, in-hash-pairs,
;;; in-naturals, in-indexed

(library (std iter)
  (export
    for for/collect for/fold for/or for/and
    in-list in-vector in-range in-string
    in-hash-keys in-hash-values in-hash-pairs
    in-naturals in-indexed)

  (import (except (chezscheme)
            make-hash-table hash-table? iota 1+ 1-)
          (jerboa runtime))

  ;; Iterator constructors — return plain lists for simplicity
  ;; (Gerbil iterators are more complex, but lists suffice for porting)

  (define (in-list lst) lst)

  (define (in-vector vec)
    (vector->list vec))

  (define in-range
    (case-lambda
      ((end) (in-range 0 end 1))
      ((start end) (in-range start end 1))
      ((start end step)
       (let loop ([i start] [acc '()])
         (if (if (positive? step) (>= i end) (<= i end))
           (reverse acc)
           (loop (+ i step) (cons i acc)))))))

  (define (in-string str)
    (string->list str))

  (define (in-hash-keys ht)
    (hash-keys ht))

  (define (in-hash-values ht)
    (hash-values ht))

  (define (in-hash-pairs ht)
    (hash->list ht))

  (define in-naturals
    (case-lambda
      (() (in-naturals 0))
      ((start)
       ;; Returns an infinite-ish list — but for/collect with zip will stop
       ;; at the shorter list. Use iota for bounded ranges.
       ;; For practical use, generate up to a reasonable limit.
       ;; In real Gerbil this is lazy; here we rely on for macros to limit.
       (let loop ([i start] [acc '()] [n 0])
         (if (>= n 100000) (reverse acc)
           (loop (+ i 1) (cons i acc) (+ n 1)))))))

  (define (in-indexed lst)
    ;; Returns list of (index . element) pairs
    (let loop ([rest lst] [i 0] [acc '()])
      (if (null? rest) (reverse acc)
        (loop (cdr rest) (+ i 1) (cons (cons i (car rest)) acc)))))

  ;; for — side-effecting iteration
  (define-syntax for
    (syntax-rules ()
      [(_ ((var iter-expr)) body ...)
       (for-each (lambda (var) body ...) iter-expr)]
      [(_ ((var1 iter1) (var2 iter2)) body ...)
       (let loop ([l1 iter1] [l2 iter2])
         (when (and (pair? l1) (pair? l2))
           (let ([var1 (car l1)] [var2 (car l2)])
             body ...
             (loop (cdr l1) (cdr l2)))))]
      [(_ ((var1 iter1) (var2 iter2) (var3 iter3)) body ...)
       (let loop ([l1 iter1] [l2 iter2] [l3 iter3])
         (when (and (pair? l1) (pair? l2) (pair? l3))
           (let ([var1 (car l1)] [var2 (car l2)] [var3 (car l3)])
             body ...
             (loop (cdr l1) (cdr l2) (cdr l3)))))]))

  ;; for/collect — collect results into a list
  (define-syntax for/collect
    (syntax-rules ()
      [(_ ((var iter-expr)) body ...)
       (map (lambda (var) body ...) iter-expr)]
      [(_ ((var1 iter1) (var2 iter2)) body ...)
       (let loop ([l1 iter1] [l2 iter2] [acc '()])
         (if (or (null? l1) (null? l2))
           (reverse acc)
           (let ([var1 (car l1)] [var2 (car l2)])
             (loop (cdr l1) (cdr l2) (cons (begin body ...) acc)))))]))

  ;; for/fold — fold with accumulator
  (define-syntax for/fold
    (syntax-rules ()
      [(_ ((acc init)) ((var iter-expr)) body ...)
       (let loop ([rest iter-expr] [acc init])
         (if (null? rest) acc
           (let ([var (car rest)])
             (loop (cdr rest) (begin body ...)))))]
      [(_ ((acc init)) ((var1 iter1) (var2 iter2)) body ...)
       (let loop ([l1 iter1] [l2 iter2] [acc init])
         (if (or (null? l1) (null? l2)) acc
           (let ([var1 (car l1)] [var2 (car l2)])
             (loop (cdr l1) (cdr l2) (begin body ...)))))]))

  ;; for/or — return first truthy result
  (define-syntax for/or
    (syntax-rules ()
      [(_ ((var iter-expr)) body ...)
       (let loop ([rest iter-expr])
         (if (null? rest) #f
           (let ([var (car rest)])
             (or (begin body ...) (loop (cdr rest))))))]))

  ;; for/and — return #f if any result is #f
  (define-syntax for/and
    (syntax-rules ()
      [(_ ((var iter-expr)) body ...)
       (let loop ([rest iter-expr])
         (if (null? rest) #t
           (let ([var (car rest)])
             (and (begin body ...) (loop (cdr rest))))))]))

  ) ;; end library
