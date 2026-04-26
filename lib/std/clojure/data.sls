#!chezscheme
;;; (std clojure data) — clojure.data compatibility
;;;
;;; Recursive comparison of two values returning a list of three
;;; elements `(only-in-a only-in-b in-both)`:
;;;
;;;   only-in-a — what `a` has that `b` lacks (or where they differ)
;;;   only-in-b — what `b` has that `a` lacks (or where they differ)
;;;   in-both   — what is identical in both, in the same shape
;;;
;;; Recognised containers: lists, vectors, persistent-map,
;;; persistent-set, persistent-vector, hash-table.  Anything else
;;; is compared with `equal?` — equal scalars become
;;; `(#f #f a)`, unequal scalars become `(a b #f)`.
;;;
;;;   (diff '(1 2 3) '(1 2 4))      => ((#f #f 3) (#f #f 4) (1 2 #f))
;;;   (diff (persistent-map :a 1 :b 2) (persistent-map :b 2 :c 3))
;;;     => (pmap{:a 1} pmap{:c 3} pmap{:b 2})

(library (std clojure data)
  (export diff)

  (import (except (chezscheme) make-hash-table hash-table?)
          (only (jerboa runtime)
                make-hash-table hash-table? hash-keys hash-ref hash-put!)
          (only (std pmap)
                persistent-map? persistent-map make-persistent-map
                persistent-map-set persistent-map-ref persistent-map-has?
                persistent-map->list persistent-map-size)
          (only (std pset)
                persistent-set? persistent-set
                persistent-set-add persistent-set-contains?
                persistent-set->list persistent-set-size)
          (only (std pvec)
                persistent-vector? persistent-vector
                persistent-vector->list persistent-vector-length))

  ;; ---- helpers --------------------------------------------------

  (define (empty-pmap) (persistent-map))
  (define (empty-pset) (persistent-set))

  (define (pmap-empty? m) (zero? (persistent-map-size m)))
  (define (pset-empty? s) (zero? (persistent-set-size s)))

  ;; If a result map/set is empty, return #f instead — clojure.data
  ;; reports "no contribution" as nil, not as an empty container.
  (define (pmap-or-false m) (if (pmap-empty? m) #f m))
  (define (pset-or-false s) (if (pset-empty? s) #f s))

  ;; ---- map diff -------------------------------------------------

  (define (diff-pmap a b)
    ;; First pass: walk keys of a.  For each key, either it's
    ;; missing in b (goes to only-a), or it's in b — recurse on
    ;; values and split the result across the three buckets.
    (let-values ([(only-a only-b both)
                  (let loop ([pairs (persistent-map->list a)]
                             [oa (empty-pmap)]
                             [ob (empty-pmap)]
                             [bo (empty-pmap)])
                    (cond
                      [(null? pairs) (values oa ob bo)]
                      [else
                       (let* ([kv (car pairs)] [k (car kv)] [va (cdr kv)])
                         (cond
                           [(persistent-map-has? b k)
                            (let* ([vb (persistent-map-ref b k)]
                                   [d  (diff va vb)]
                                   [da (car d)] [db (cadr d)] [bv (caddr d)])
                              (loop (cdr pairs)
                                    (if da (persistent-map-set oa k da) oa)
                                    (if db (persistent-map-set ob k db) ob)
                                    (if bv (persistent-map-set bo k bv) bo)))]
                           [else
                            (loop (cdr pairs)
                                  (persistent-map-set oa k va) ob bo)]))]))])
      ;; Second pass: keys present in b but not in a → only-b.
      (let loop2 ([pairs (persistent-map->list b)] [ob only-b])
        (cond
          [(null? pairs)
           (list (pmap-or-false only-a)
                 (pmap-or-false ob)
                 (pmap-or-false both))]
          [else
           (let* ([kv (car pairs)] [k (car kv)] [vb (cdr kv)])
             (loop2 (cdr pairs)
                    (if (persistent-map-has? a k)
                        ob
                        (persistent-map-set ob k vb))))]))))

  ;; ---- set diff -------------------------------------------------

  (define (diff-pset a b)
    (let ([only-a (empty-pset)]
          [only-b (empty-pset)]
          [both   (empty-pset)])
      (for-each
        (lambda (x)
          (if (persistent-set-contains? b x)
              (set! both (persistent-set-add both x))
              (set! only-a (persistent-set-add only-a x))))
        (persistent-set->list a))
      (for-each
        (lambda (x)
          (unless (persistent-set-contains? a x)
            (set! only-b (persistent-set-add only-b x))))
        (persistent-set->list b))
      (list (pset-or-false only-a)
            (pset-or-false only-b)
            (pset-or-false both))))

  ;; ---- sequential diff (lists, vectors, persistent-vectors) ----
  ;;
  ;; clojure.data treats two seqs elementwise: at each index, recurse;
  ;; trailing elements in the longer seq go to the corresponding
  ;; only-in-X result.  The output container shape mirrors the
  ;; input (list-in → list-out, vector-in → vector-out,
  ;; pvec-in → pvec-out).

  (define (seq-len kind seq)
    (case kind
      [(list)        (length seq)]
      [(vector)      (vector-length seq)]
      [(pvec)        (persistent-vector-length seq)]))

  (define (seq-ref kind seq i)
    (case kind
      [(list)        (list-ref seq i)]
      [(vector)      (vector-ref seq i)]
      [(pvec)        (list-ref (persistent-vector->list seq) i)]))

  (define (seq-build kind elements)
    (case kind
      [(list)   elements]
      [(vector) (list->vector elements)]
      [(pvec)   (apply persistent-vector elements)]))

  (define (all-false? lst)
    (let loop ([l lst])
      (cond [(null? l) #t]
            [(car l) #f]
            [else (loop (cdr l))])))

  (define (drop-trailing-falses lst)
    ;; reverse, drop leading #f, reverse back
    (let loop ([l (reverse lst)])
      (cond [(null? l) '()]
            [(car l) (reverse l)]
            [else (loop (cdr l))])))

  (define (or-false? kind lst)
    (and (not (null? lst)) (seq-build kind lst)))

  (define (diff-seq kind a b)
    (let* ([la (seq-len kind a)]
           [lb (seq-len kind b)]
           [common (min la lb)])
      (let loop ([i 0]
                 [oa '()] [ob '()] [bo '()])
        (cond
          [(< i common)
           (let* ([va (seq-ref kind a i)]
                  [vb (seq-ref kind b i)]
                  [d  (diff va vb)])
             (loop (+ i 1)
                   (cons (car d) oa)
                   (cons (cadr d) ob)
                   (cons (caddr d) bo)))]
          [else
           (let* ([oa* (let lp ([i common] [acc oa])
                        (if (>= i la) acc
                            (lp (+ i 1) (cons (seq-ref kind a i) acc))))]
                  [ob* (let lp ([i common] [acc ob])
                        (if (>= i lb) acc
                            (lp (+ i 1) (cons (seq-ref kind b i) acc))))]
                  [oa-list (reverse oa*)]
                  [ob-list (reverse ob*)]
                  [bo-list (drop-trailing-falses (reverse bo))])
             (list (if (all-false? oa-list) #f (or-false? kind oa-list))
                   (if (all-false? ob-list) #f (or-false? kind ob-list))
                   (or-false? kind bo-list)))]))))

  ;; ---- public diff ----------------------------------------------

  (define (diff a b)
    (cond
      [(equal? a b)
       (list #f #f a)]
      [(and (persistent-map? a) (persistent-map? b))
       (diff-pmap a b)]
      [(and (persistent-set? a) (persistent-set? b))
       (diff-pset a b)]
      [(and (persistent-vector? a) (persistent-vector? b))
       (diff-seq 'pvec a b)]
      [(and (vector? a) (vector? b))
       (diff-seq 'vector a b)]
      [(and (list? a) (list? b))
       (diff-seq 'list a b)]
      [(and (hash-table? a) (hash-table? b))
       ;; Convert to pmap for the comparison; result returned as pmaps.
       (let ([ma (empty-pmap)] [mb (empty-pmap)])
         (for-each (lambda (k) (set! ma (persistent-map-set ma k (hash-ref a k))))
                   (hash-keys a))
         (for-each (lambda (k) (set! mb (persistent-map-set mb k (hash-ref b k))))
                   (hash-keys b))
         (diff-pmap ma mb))]
      [else
       ;; Disparate or unrecognised types: full a / full b / nothing.
       (list a b #f)]))

) ;; end library
