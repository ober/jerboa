#!chezscheme
;;; :std/srfi/113 -- Sets and Bags (SRFI-113)
;;; Sets use hashtables with comparators; bags track element counts.

(library (std srfi srfi-113)
  (export
    set set? set-empty? set-size set-member?
    set-adjoin set-delete set-union set-intersection
    set-difference set-xor set->list list->set
    set-map set-filter set-fold set-for-each
    set-any? set-every?
    bag bag? bag-adjoin bag-delete bag-count
    bag->list list->bag)

  (import (chezscheme))

  ;; ---- Comparator protocol (inline, compatible with SRFI-128) ----
  ;; A comparator here is a vector: #(type-test equality ordering hash-fn)
  ;; But we also accept SRFI-128 comparator records if present.

  (define (comp-equality c)
    (cond
      [(procedure? c) c]  ;; bare equality predicate
      [(vector? c) (vector-ref c 1)]
      [else equal?]))

  (define (comp-hash c)
    (cond
      [(vector? c) (vector-ref c 3)]
      [else equal-hash]))

  ;; ---- Set type ----
  ;; A set is a record with a comparator and a hashtable.

  (define-record-type set-rec
    (fields (immutable comparator)
            (immutable table))
    (sealed #t))

  (define (set? x) (set-rec? x))

  (define (make-set-from-ht comp ht)
    (make-set-rec comp ht))

  (define (set-ht-copy s)
    (hashtable-copy (set-rec-table s) #t))

  (define (set comp . elements)
    (let ([ht (make-hashtable (comp-hash comp) (comp-equality comp))])
      (for-each (lambda (e) (hashtable-set! ht e #t)) elements)
      (make-set-rec comp ht)))

  (define (set-empty? s)
    (= 0 (hashtable-size (set-rec-table s))))

  (define (set-size s)
    (hashtable-size (set-rec-table s)))

  (define (set-member? s elem default)
    (if (hashtable-contains? (set-rec-table s) elem)
      elem
      default))

  (define (set-adjoin s . elements)
    (let ([ht (set-ht-copy s)])
      (for-each (lambda (e) (hashtable-set! ht e #t)) elements)
      (make-set-from-ht (set-rec-comparator s) ht)))

  (define (set-delete s . elements)
    (let ([ht (set-ht-copy s)])
      (for-each (lambda (e) (hashtable-delete! ht e)) elements)
      (make-set-from-ht (set-rec-comparator s) ht)))

  (define (set-union s1 s2)
    (let ([ht (set-ht-copy s1)])
      (vector-for-each
        (lambda (k) (hashtable-set! ht k #t))
        (hashtable-keys (set-rec-table s2)))
      (make-set-from-ht (set-rec-comparator s1) ht)))

  (define (set-intersection s1 s2)
    (let ([comp (set-rec-comparator s1)]
          [ht1 (set-rec-table s1)]
          [ht2 (set-rec-table s2)]
          [ht (make-hashtable (comp-hash (set-rec-comparator s1))
                              (comp-equality (set-rec-comparator s1)))])
      (vector-for-each
        (lambda (k)
          (when (hashtable-contains? ht2 k)
            (hashtable-set! ht k #t)))
        (hashtable-keys ht1))
      (make-set-from-ht comp ht)))

  (define (set-difference s1 s2)
    (let ([comp (set-rec-comparator s1)]
          [ht (set-ht-copy s1)]
          [ht2 (set-rec-table s2)])
      (vector-for-each
        (lambda (k)
          (when (hashtable-contains? ht2 k)
            (hashtable-delete! ht k)))
        (hashtable-keys (set-rec-table s1)))
      (make-set-from-ht comp ht)))

  (define (set-xor s1 s2)
    (let ([comp (set-rec-comparator s1)]
          [ht (make-hashtable (comp-hash (set-rec-comparator s1))
                              (comp-equality (set-rec-comparator s1)))]
          [ht1 (set-rec-table s1)]
          [ht2 (set-rec-table s2)])
      ;; Elements in s1 but not s2
      (vector-for-each
        (lambda (k)
          (unless (hashtable-contains? ht2 k)
            (hashtable-set! ht k #t)))
        (hashtable-keys ht1))
      ;; Elements in s2 but not s1
      (vector-for-each
        (lambda (k)
          (unless (hashtable-contains? ht1 k)
            (hashtable-set! ht k #t)))
        (hashtable-keys ht2))
      (make-set-from-ht comp ht)))

  (define (set->list s)
    (vector->list (hashtable-keys (set-rec-table s))))

  (define (list->set comp lst)
    (apply set comp lst))

  (define (set-map comp proc s)
    (let ([ht (make-hashtable (comp-hash comp) (comp-equality comp))])
      (vector-for-each
        (lambda (k) (hashtable-set! ht (proc k) #t))
        (hashtable-keys (set-rec-table s)))
      (make-set-from-ht comp ht)))

  (define (set-filter pred s)
    (let ([comp (set-rec-comparator s)]
          [ht (make-hashtable (comp-hash (set-rec-comparator s))
                              (comp-equality (set-rec-comparator s)))])
      (vector-for-each
        (lambda (k) (when (pred k) (hashtable-set! ht k #t)))
        (hashtable-keys (set-rec-table s)))
      (make-set-from-ht comp ht)))

  (define (set-fold proc seed s)
    (let ([keys (hashtable-keys (set-rec-table s))])
      (let loop ([i 0] [acc seed])
        (if (= i (vector-length keys))
          acc
          (loop (+ i 1) (proc (vector-ref keys i) acc))))))

  (define (set-for-each proc s)
    (vector-for-each proc (hashtable-keys (set-rec-table s))))

  (define (set-any? pred s)
    (let ([keys (hashtable-keys (set-rec-table s))])
      (let loop ([i 0])
        (cond
          [(= i (vector-length keys)) #f]
          [(pred (vector-ref keys i)) #t]
          [else (loop (+ i 1))]))))

  (define (set-every? pred s)
    (let ([keys (hashtable-keys (set-rec-table s))])
      (let loop ([i 0])
        (cond
          [(= i (vector-length keys)) #t]
          [(not (pred (vector-ref keys i))) #f]
          [else (loop (+ i 1))]))))

  ;; ---- Bag type ----
  ;; A bag is like a set but tracks counts. Uses a hashtable mapping elem->count.

  (define-record-type bag-rec
    (fields (immutable comparator)
            (immutable table))
    (sealed #t))

  (define (bag? x) (bag-rec? x))

  (define (bag comp . elements)
    (let ([ht (make-hashtable (comp-hash comp) (comp-equality comp))])
      (for-each
        (lambda (e)
          (hashtable-update! ht e (lambda (c) (+ c 1)) 0))
        elements)
      (make-bag-rec comp ht)))

  (define (bag-adjoin b . elements)
    (let ([ht (hashtable-copy (bag-rec-table b) #t)])
      (for-each
        (lambda (e)
          (hashtable-update! ht e (lambda (c) (+ c 1)) 0))
        elements)
      (make-bag-rec (bag-rec-comparator b) ht)))

  (define (bag-delete b . elements)
    (let ([ht (hashtable-copy (bag-rec-table b) #t)])
      (for-each
        (lambda (e)
          (let ([c (hashtable-ref ht e 0)])
            (if (<= c 1)
              (hashtable-delete! ht e)
              (hashtable-set! ht e (- c 1)))))
        elements)
      (make-bag-rec (bag-rec-comparator b) ht)))

  (define (bag-count b elem)
    (hashtable-ref (bag-rec-table b) elem 0))

  (define (bag->list b)
    (let ([ht (bag-rec-table b)]
          [result '()])
      (let-values ([(keys vals) (hashtable-entries ht)])
        (do ([i 0 (+ i 1)])
            ((= i (vector-length keys)) result)
          (let ([k (vector-ref keys i)]
                [n (vector-ref vals i)])
            (do ([j 0 (+ j 1)])
                ((= j n))
              (set! result (cons k result))))))))

  (define (list->bag comp lst)
    (apply bag comp lst))

) ;; end library
