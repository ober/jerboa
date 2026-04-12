#!chezscheme
;;; (std clojure seq) — Unified sequence abstraction
;;;
;;; Provides polymorphic versions of core sequence functions that work
;;; on any seqable collection: lists, vectors, persistent vectors/maps/sets,
;;; sorted sets, hash tables, strings, and lazy sequences.
;;;
;;; In Clojure, (map inc [1 2 3]) just works. This module provides that
;;; same experience by converting collections to sequences (via `seq`)
;;; before operating, and then returning lists as the universal seq type.
;;;
;;; Usage:
;;;   (import (std clojure seq))
;;;   (seq-map inc (persistent-vector 1 2 3))   ;; => (2 3 4)
;;;   (seq-filter even? (hash-set 1 2 3 4))     ;; => (2 4)
;;;   (seq-take 3 (sorted-set 5 3 1 4 2))       ;; => (1 2 3)
;;;
;;; These are meant to be re-exported from (std clojure) as `map`, `filter`,
;;; etc., shadowing the prelude versions with polymorphic ones.

(library (std clojure seq)
  (export
    ;; The seq protocol function
    seqable? seq->list
    ;; Polymorphic sequence operations
    seq-map seq-filter seq-remove
    seq-take seq-drop seq-take-while seq-drop-while
    seq-reduce seq-some seq-every?
    seq-sort seq-sort-by
    seq-distinct seq-flatten
    seq-partition seq-partition-by seq-partition-all
    seq-group-by seq-frequencies
    seq-interpose seq-interleave
    seq-mapcat seq-keep
    seq-map-indexed
    seq-concat
    seq-into
    seq-count seq-empty?
    seq-nth seq-first seq-rest
    seq-second seq-last
    seq-butlast
    seq-reverse
    seq-zip seq-zipmap)

  (import (except (chezscheme)
                  make-hash-table hash-table? iota 1+ 1-
                  sort sort!
                  partition)
          (std pvec)
          (std pmap)
          (std pset)
          (std sorted-set)
          (std seq)    ;; for lazy-seq?
          (rename (std sort) (sort std-sort)))

  ;; ---- seqable? — can this value be turned into a sequence? ----
  (define (seqable? x)
    (or (null? x)
        (pair? x)
        (vector? x)
        (string? x)
        (persistent-vector? x)
        (persistent-map? x)
        (persistent-set? x)
        (sorted-set? x)
        (hashtable? x)
        (lazy-seq? x)
        (eq? x #f)))

  ;; ---- seq->list — convert any seqable to a list ----
  ;; This is the core of the abstraction: everything goes through list.
  ;; Returns '() for nil/empty (matching Clojure's seq semantics), or a list.
  (define (seq->list coll)
    (cond
      [(eq? coll #f) '()]
      [(null? coll) '()]
      [(pair? coll) coll]
      [(lazy-seq? coll) (lazy->list coll)]  ;; before vector? — lazy seqs are 3-vectors
      [(vector? coll) (vector->list coll)]
      [(string? coll) (string->list coll)]
      [(persistent-vector? coll) (persistent-vector->list coll)]
      [(persistent-map? coll) (persistent-map->list coll)]
      [(persistent-set? coll) (persistent-set->list coll)]
      [(sorted-set? coll) (sorted-set->list coll)]
      [(hashtable? coll) (hashtable->alist coll)]
      [else (error 'seq->list "not seqable" coll)]))

  ;; Helper to get alist from chez hashtable
  (define (hashtable->alist ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let ([n (vector-length keys)])
        (let lp ([i 0] [acc '()])
          (if (= i n) (reverse acc)
              (lp (+ i 1)
                  (cons (cons (vector-ref keys i) (vector-ref vals i))
                        acc)))))))

  ;; ---- Polymorphic sequence operations ----

  (define (seq-map f . colls)
    (if (null? (cdr colls))
        (map f (seq->list (car colls)))
        (apply map f (map seq->list colls))))

  (define (seq-filter pred coll)
    (filter pred (seq->list coll)))

  (define (seq-remove pred coll)
    (filter (lambda (x) (not (pred x))) (seq->list coll)))

  (define seq-take
    (case-lambda
      [(n coll)
       (let lp ([lst (seq->list coll)] [n n] [acc '()])
         (if (or (zero? n) (null? lst))
             (reverse acc)
             (lp (cdr lst) (- n 1) (cons (car lst) acc))))]))

  (define seq-drop
    (case-lambda
      [(n coll)
       (let lp ([lst (seq->list coll)] [n n])
         (if (or (zero? n) (null? lst))
             lst
             (lp (cdr lst) (- n 1))))]))

  (define (seq-take-while pred coll)
    (let lp ([lst (seq->list coll)] [acc '()])
      (if (or (null? lst) (not (pred (car lst))))
          (reverse acc)
          (lp (cdr lst) (cons (car lst) acc)))))

  (define (seq-drop-while pred coll)
    (let lp ([lst (seq->list coll)])
      (if (or (null? lst) (not (pred (car lst))))
          lst
          (lp (cdr lst)))))

  (define seq-reduce
    (case-lambda
      [(f coll)
       (let ([lst (seq->list coll)])
         (if (null? lst)
             (f)
             (fold-left f (car lst) (cdr lst))))]
      [(f init coll)
       (fold-left f init (seq->list coll))]))

  (define (seq-some pred coll)
    (let lp ([lst (seq->list coll)])
      (cond
        [(null? lst) #f]
        [(pred (car lst)) => (lambda (v) v)]
        [else (lp (cdr lst))])))

  (define (seq-every? pred coll)
    (let lp ([lst (seq->list coll)])
      (cond
        [(null? lst) #t]
        [(not (pred (car lst))) #f]
        [else (lp (cdr lst))])))

  (define (seq-sort cmp coll)
    (std-sort (seq->list coll) cmp))

  (define (seq-sort-by keyfn cmp coll)
    (std-sort (seq->list coll)
              (lambda (a b) (cmp (keyfn a) (keyfn b)))))

  (define (seq-distinct coll)
    (let ([seen (make-hashtable equal-hash equal?)])
      (let lp ([lst (seq->list coll)] [acc '()])
        (if (null? lst)
            (reverse acc)
            (let ([x (car lst)])
              (if (hashtable-ref seen x #f)
                  (lp (cdr lst) acc)
                  (begin
                    (hashtable-set! seen x #t)
                    (lp (cdr lst) (cons x acc)))))))))

  (define (seq-flatten coll)
    (let lp ([lst (seq->list coll)] [acc '()])
      (if (null? lst)
          (reverse acc)
          (let ([x (car lst)])
            (if (or (pair? x) (null? x))
                (lp (cdr lst) (append (reverse (lp x '())) acc))
                (lp (cdr lst) (cons x acc)))))))

  (define (seq-partition n coll)
    (let lp ([lst (seq->list coll)] [acc '()])
      (if (< (length-at-least lst n) n)
          (reverse acc)
          (lp (list-tail lst n)
              (cons (take-n lst n) acc)))))

  (define (length-at-least lst n)
    (let lp ([l lst] [c 0])
      (if (or (null? l) (= c n)) c
          (lp (cdr l) (+ c 1)))))

  (define (take-n lst n)
    (let lp ([l lst] [n n] [acc '()])
      (if (zero? n) (reverse acc)
          (lp (cdr l) (- n 1) (cons (car l) acc)))))

  (define (seq-partition-all n coll)
    (let lp ([lst (seq->list coll)] [acc '()])
      (if (null? lst)
          (reverse acc)
          (let ([chunk (list-head* lst n)])
            (lp (list-tail* lst n)
                (cons chunk acc))))))

  (define (list-head* lst n)
    (let lp ([l lst] [n n] [acc '()])
      (if (or (zero? n) (null? l)) (reverse acc)
          (lp (cdr l) (- n 1) (cons (car l) acc)))))

  (define (list-tail* lst n)
    (let lp ([l lst] [n n])
      (if (or (zero? n) (null? l)) l
          (lp (cdr l) (- n 1)))))

  (define (seq-partition-by f coll)
    (let ([lst (seq->list coll)])
      (if (null? lst)
          '()
          (let lp ([rest (cdr lst)]
                   [prev-val (f (car lst))]
                   [group (list (car lst))]
                   [acc '()])
            (if (null? rest)
                (reverse (cons (reverse group) acc))
                (let ([cur-val (f (car rest))])
                  (if (equal? cur-val prev-val)
                      (lp (cdr rest) cur-val
                          (cons (car rest) group) acc)
                      (lp (cdr rest) cur-val
                          (list (car rest))
                          (cons (reverse group) acc)))))))))

  (define (seq-group-by f coll)
    (let ([ht (make-hashtable equal-hash equal?)])
      (for-each
        (lambda (x)
          (let ([k (f x)])
            (hashtable-update! ht k
              (lambda (v) (append v (list x)))
              '())))
        (seq->list coll))
      ;; Convert to alist
      (hashtable->alist ht)))

  (define (seq-frequencies coll)
    (let ([ht (make-hashtable equal-hash equal?)])
      (for-each
        (lambda (x)
          (hashtable-update! ht x (lambda (n) (+ n 1)) 0))
        (seq->list coll))
      (hashtable->alist ht)))

  (define (seq-interpose sep coll)
    (let ([lst (seq->list coll)])
      (if (or (null? lst) (null? (cdr lst)))
          lst
          (let lp ([rest (cdr lst)] [acc (list (car lst))])
            (if (null? rest)
                (reverse acc)
                (lp (cdr rest) (cons (car rest) (cons sep acc))))))))

  (define (seq-interleave . colls)
    (let ([lists (map seq->list colls)])
      (let lp ([lsts lists] [acc '()])
        (if (exists null? lsts)
            (reverse acc)
            (lp (map cdr lsts)
                (fold-right cons acc (map car lsts)))))))

  (define (seq-mapcat f coll)
    (apply append (map f (seq->list coll))))

  (define (seq-keep f coll)
    (let lp ([lst (seq->list coll)] [acc '()])
      (if (null? lst)
          (reverse acc)
          (let ([v (f (car lst))])
            (if v
                (lp (cdr lst) (cons v acc))
                (lp (cdr lst) acc))))))

  (define (seq-map-indexed f coll)
    (let lp ([lst (seq->list coll)] [i 0] [acc '()])
      (if (null? lst)
          (reverse acc)
          (lp (cdr lst) (+ i 1) (cons (f i (car lst)) acc)))))

  (define (seq-concat . colls)
    (apply append (map seq->list colls)))

  (define (seq-into to-coll from-coll)
    (cond
      [(null? to-coll) (seq->list from-coll)]
      [(pair? to-coll) (append to-coll (seq->list from-coll))]
      [(vector? to-coll)
       (list->vector (append (vector->list to-coll) (seq->list from-coll)))]
      [(persistent-vector? to-coll)
       (fold-left persistent-vector-append to-coll (seq->list from-coll))]
      [(persistent-set? to-coll)
       (fold-left (lambda (s x) (persistent-set-add s x))
                  to-coll (seq->list from-coll))]
      [(persistent-map? to-coll)
       (fold-left (lambda (m kv) (persistent-map-set m (car kv) (cdr kv)))
                  to-coll (seq->list from-coll))]
      [else (error 'seq-into "unsupported target collection" to-coll)]))

  (define (seq-count coll)
    (length (seq->list coll)))

  (define (seq-empty? coll)
    (null? (seq->list coll)))

  (define (seq-nth coll n)
    (list-ref (seq->list coll) n))

  (define (seq-first coll)
    (let ([lst (seq->list coll)])
      (if (null? lst) #f (car lst))))

  (define (seq-rest coll)
    (let ([lst (seq->list coll)])
      (if (null? lst) '() (cdr lst))))

  (define (seq-second coll)
    (let ([lst (seq->list coll)])
      (if (or (null? lst) (null? (cdr lst))) #f (cadr lst))))

  (define (seq-last coll)
    (let ([lst (seq->list coll)])
      (if (null? lst) #f
          (let lp ([l lst])
            (if (null? (cdr l)) (car l) (lp (cdr l)))))))

  (define (seq-butlast coll)
    (let ([lst (seq->list coll)])
      (if (or (null? lst) (null? (cdr lst)))
          '()
          (let lp ([l lst] [acc '()])
            (if (null? (cdr l))
                (reverse acc)
                (lp (cdr l) (cons (car l) acc)))))))

  (define (seq-reverse coll)
    (reverse (seq->list coll)))

  (define (seq-zip . colls)
    (apply map list (map seq->list colls)))

  (define (seq-zipmap ks vs)
    (let lp ([ks (seq->list ks)] [vs (seq->list vs)] [acc pmap-empty])
      (if (or (null? ks) (null? vs))
          acc
          (lp (cdr ks) (cdr vs)
              (persistent-map-set acc (car ks) (car vs))))))

) ;; end library
