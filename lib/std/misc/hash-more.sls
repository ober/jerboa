#!chezscheme
;;; (std misc hash-more) — Extended hash table operations
;;;
;;; Additional hash operations common in Gerbil code but not in jerboa runtime.

(library (std misc hash-more)
  (export hash-filter hash-map/values
          hash-ref/default hash-value-set!
          hash->alist hash-union hash-intersect
          hash-count hash-any hash-every
          ;; better2 #6 additions
          hash-fold hash-find hash-clear!
          hash-copy hash-merge
          hash-keys/list hash-values/list)

  (import (chezscheme))

  ;; Create an empty hash table with the same type as ht
  (define (clone-empty ht)
    (let ([equiv (hashtable-equivalence-function ht)]
          [hashfn (hashtable-hash-function ht)])
      (if hashfn
          (make-hashtable hashfn equiv)
          ;; eq or eqv hashtable — no hash function
          (cond
            [(eq? equiv eq?) (make-eq-hashtable)]
            [(eq? equiv eqv?) (make-eqv-hashtable)]
            [else (make-hashtable equal-hash equiv)]))))

  ;; Filter entries by predicate (key value → bool)
  (define (hash-filter pred ht)
    (let ([result (clone-empty ht)])
      (let-values ([(keys vals) (hashtable-entries ht)])
        (do ([i 0 (+ i 1)])
            ((= i (vector-length keys)) result)
          (when (pred (vector-ref keys i) (vector-ref vals i))
            (hashtable-set! result
                            (vector-ref keys i)
                            (vector-ref vals i)))))))

  ;; Map over values only, keeping keys
  (define (hash-map/values proc ht)
    (let ([result (clone-empty ht)])
      (let-values ([(keys vals) (hashtable-entries ht)])
        (do ([i 0 (+ i 1)])
            ((= i (vector-length keys)) result)
          (hashtable-set! result
                          (vector-ref keys i)
                          (proc (vector-ref vals i)))))))

  ;; Hash ref with explicit default (never errors)
  (define (hash-ref/default ht key default)
    (hashtable-ref ht key default))

  ;; Alias for hashtable-set! (Gerbil naming)
  (define hash-value-set! hashtable-set!)

  ;; Convert hash to association list
  (define (hash->alist ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let loop ([i (- (vector-length keys) 1)] [acc '()])
        (if (< i 0)
            acc
            (loop (- i 1) (cons (cons (vector-ref keys i)
                                      (vector-ref vals i))
                                acc))))))

  ;; Merge two hash tables with conflict resolution
  (define hash-union
    (case-lambda
      [(ht1 ht2)
       (hash-union ht1 ht2 (lambda (k v1 v2) v2))]
      [(ht1 ht2 merge-fn)
       (let ([result (hashtable-copy ht1 #t)])
         (let-values ([(keys vals) (hashtable-entries ht2)])
           (do ([i 0 (+ i 1)])
               ((= i (vector-length keys)) result)
             (let ([k (vector-ref keys i)]
                   [v (vector-ref vals i)])
               (if (hashtable-contains? result k)
                   (hashtable-set! result k
                                   (merge-fn k (hashtable-ref result k #f) v))
                   (hashtable-set! result k v))))))]))

  ;; Intersection: only keys in both tables
  (define hash-intersect
    (case-lambda
      [(ht1 ht2)
       (hash-intersect ht1 ht2 (lambda (k v1 v2) v1))]
      [(ht1 ht2 merge-fn)
       (let ([result (clone-empty ht1)])
         (let-values ([(keys vals) (hashtable-entries ht1)])
           (do ([i 0 (+ i 1)])
               ((= i (vector-length keys)) result)
             (let ([k (vector-ref keys i)]
                   [v (vector-ref vals i)])
               (when (hashtable-contains? ht2 k)
                 (hashtable-set! result k
                                 (merge-fn k v (hashtable-ref ht2 k #f))))))))]))

  ;; Count entries satisfying predicate
  (define (hash-count pred ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let loop ([i 0] [n 0])
        (if (= i (vector-length keys))
            n
            (loop (+ i 1)
                  (if (pred (vector-ref keys i) (vector-ref vals i))
                      (+ n 1) n))))))

  ;; Any entry satisfies predicate?
  (define (hash-any pred ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let loop ([i 0])
        (and (< i (vector-length keys))
             (or (pred (vector-ref keys i) (vector-ref vals i))
                 (loop (+ i 1)))))))

  ;; Every entry satisfies predicate?
  (define (hash-every pred ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let loop ([i 0])
        (or (= i (vector-length keys))
            (and (pred (vector-ref keys i) (vector-ref vals i))
                 (loop (+ i 1)))))))

  ;; ========== better2 #6 additions ==========

  ;; Fold over hash entries
  (define (hash-fold proc init ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let loop ([i 0] [acc init])
        (if (= i (vector-length keys))
            acc
            (loop (+ i 1)
                  (proc (vector-ref keys i) (vector-ref vals i) acc))))))

  ;; Find first entry satisfying predicate, return (key . value) or #f
  (define (hash-find pred ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let loop ([i 0])
        (cond
          [(= i (vector-length keys)) #f]
          [(pred (vector-ref keys i) (vector-ref vals i))
           (cons (vector-ref keys i) (vector-ref vals i))]
          [else (loop (+ i 1))]))))

  ;; Clear all entries from a hash table
  (define (hash-clear! ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (do ([i 0 (+ i 1)])
          ((= i (vector-length keys)))
        (hashtable-delete! ht (vector-ref keys i)))))

  ;; Shallow copy of a hash table
  (define (hash-copy ht)
    (hashtable-copy ht #t))

  ;; Merge: same as hash-union but more Gerbil-idiomatic name
  (define hash-merge hash-union)

  ;; Extract keys as a list
  (define (hash-keys/list ht)
    (vector->list (hashtable-keys ht)))

  ;; Extract values as a list
  (define (hash-values/list ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (vector->list vals)))

) ;; end library
