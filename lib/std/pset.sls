#!chezscheme
;;; (std pset) — Persistent Sets (HAMT-backed)
;;;
;;; Immutable hash sets with structural sharing, built on top of
;;; (std pmap). Element equality follows equal?, hashing uses
;;; equal-hash, matching Clojure's default set semantics.
;;;
;;; A persistent-set is a record wrapper around a %pmap whose keys
;;; are the set elements and whose values are the sentinel #t. The
;;; wrapper exists so that (persistent-set? x) distinguishes sets
;;; from maps, and so set-specific ops like union / intersection
;;; / difference can dispatch cleanly.
;;;
;;; Usage:
;;;   (import (std pset))
;;;
;;;   (def s (persistent-set 1 2 3))
;;;   (persistent-set-contains? s 2)      ;; => #t
;;;   (persistent-set-size s)             ;; => 3
;;;
;;;   (def s2 (persistent-set-add s 4))
;;;   (def s3 (persistent-set-remove s 1))
;;;
;;;   (persistent-set-union (persistent-set 1 2) (persistent-set 2 3))
;;;   ;; => #{1 2 3}
;;;
;;;   (persistent-set-intersection (persistent-set 1 2 3) (persistent-set 2 3 4))
;;;   ;; => #{2 3}
;;;
;;;   (persistent-set-difference (persistent-set 1 2 3) (persistent-set 2))
;;;   ;; => #{1 3}
;;;
;;; Short `pset-` aliases are exported for terseness.

(library (std pset)
  (export
    ;; Construction
    persistent-set make-persistent-set pset-empty
    ;; Type predicate
    persistent-set? pset?
    ;; Access / membership
    persistent-set-contains? persistent-set-size
    pset-contains? pset-size
    ;; Functional update
    persistent-set-add persistent-set-remove
    pset-add pset-remove
    ;; Conversion / iteration
    persistent-set->list pset->list
    persistent-set-for-each pset-for-each
    persistent-set-fold pset-fold
    persistent-set-map pset-map
    persistent-set-filter pset-filter
    ;; Set operations
    persistent-set-union persistent-set-intersection persistent-set-difference
    pset-union pset-intersection pset-difference
    persistent-set-subset? pset-subset?
    persistent-set=? pset=?
    persistent-set-hash pset-hash
    in-pset
    ;; Transient variant for bulk construction
    transient-set transient-set?
    tset-add! tset-remove! tset-contains? tset-size
    persistent-set!)

  (import (chezscheme)
          (std pmap))

  ;;; ========== Set record ==========

  (define-record-type %pset
    (fields (immutable map)))     ;; wraps an underlying %pmap

  (define (persistent-set? x) (%pset? x))
  (define pset? persistent-set?)

  (define pset-empty (make-%pset pmap-empty))

  (define (make-persistent-set . items)
    (let ([t (transient-map pmap-empty)])
      (for-each (lambda (x) (tmap-set! t x #t)) items)
      (make-%pset (persistent-map! t))))

  (define (persistent-set . items)
    (apply make-persistent-set items))

  ;;; ========== Access ==========

  (define (persistent-set-size s)
    (persistent-map-size (%pset-map s)))

  (define (persistent-set-contains? s item)
    (persistent-map-has? (%pset-map s) item))

  (define pset-size persistent-set-size)
  (define pset-contains? persistent-set-contains?)

  ;;; ========== Functional update ==========

  (define (persistent-set-add s item)
    (if (persistent-set-contains? s item)
        s
        (make-%pset (persistent-map-set (%pset-map s) item #t))))

  (define (persistent-set-remove s item)
    (if (persistent-set-contains? s item)
        (make-%pset (persistent-map-delete (%pset-map s) item))
        s))

  (define pset-add persistent-set-add)
  (define pset-remove persistent-set-remove)

  ;;; ========== Iteration ==========

  (define (persistent-set-for-each proc s)
    ;; proc: (item) -> unused
    (persistent-map-for-each
      (lambda (k v) (proc k))
      (%pset-map s)))

  (define (persistent-set->list s)
    (persistent-map-keys (%pset-map s)))

  (define (persistent-set-fold proc init s)
    ;; proc: (acc item) -> new-acc
    (persistent-map-fold
      (lambda (acc k v) (proc acc k))
      init
      (%pset-map s)))

  (define (persistent-set-map proc s)
    ;; proc: (item) -> new-item
    (let ([t (transient-map pmap-empty)])
      (persistent-set-for-each
        (lambda (x) (tmap-set! t (proc x) #t))
        s)
      (make-%pset (persistent-map! t))))

  (define (persistent-set-filter pred s)
    (let ([t (transient-map pmap-empty)])
      (persistent-set-for-each
        (lambda (x) (when (pred x) (tmap-set! t x #t)))
        s)
      (make-%pset (persistent-map! t))))

  (define pset->list persistent-set->list)
  (define pset-for-each persistent-set-for-each)
  (define pset-fold persistent-set-fold)
  (define pset-map persistent-set-map)
  (define pset-filter persistent-set-filter)

  ;;; ========== Set operations ==========

  (define (persistent-set-union s1 s2)
    ;; All items in s1 OR s2
    (let ([t (transient-map (%pset-map s1))])
      (persistent-set-for-each
        (lambda (x) (tmap-set! t x #t))
        s2)
      (make-%pset (persistent-map! t))))

  (define (persistent-set-intersection s1 s2)
    ;; Items present in BOTH
    (let ([t (transient-map pmap-empty)]
          ;; Iterate the smaller one for efficiency
          [smaller (if (< (persistent-set-size s1) (persistent-set-size s2)) s1 s2)]
          [larger  (if (< (persistent-set-size s1) (persistent-set-size s2)) s2 s1)])
      (persistent-set-for-each
        (lambda (x) (when (persistent-set-contains? larger x) (tmap-set! t x #t)))
        smaller)
      (make-%pset (persistent-map! t))))

  (define (persistent-set-difference s1 s2)
    ;; Items in s1 but not in s2
    (let ([t (transient-map pmap-empty)])
      (persistent-set-for-each
        (lambda (x) (unless (persistent-set-contains? s2 x) (tmap-set! t x #t)))
        s1)
      (make-%pset (persistent-map! t))))

  (define (persistent-set-subset? s1 s2)
    ;; Is every element of s1 also in s2?
    (let ([ok #t])
      (persistent-set-for-each
        (lambda (x) (when (not (persistent-set-contains? s2 x)) (set! ok #f)))
        s1)
      ok))

  (define (persistent-set=? s1 s2)
    (and (= (persistent-set-size s1) (persistent-set-size s2))
         (persistent-set-subset? s1 s2)))

  ;; Order-independent structural hash. Mirrors persistent-map-hash
  ;; but only consumes the keys (values are always the sentinel #t).
  (define (persistent-set-hash s)
    (let ([h 0])
      (persistent-set-for-each
        (lambda (x) (set! h (bitwise-xor h (equal-hash x))))
        s)
      (bitwise-xor h (equal-hash (persistent-set-size s)))))

  ;; Iterator — returns a list of elements, compatible with (std iter).
  (define (in-pset s)
    (persistent-set->list s))

  (define pset-union persistent-set-union)
  (define pset-intersection persistent-set-intersection)
  (define pset-difference persistent-set-difference)
  (define pset-subset? persistent-set-subset?)
  (define pset=? persistent-set=?)
  (define pset-hash persistent-set-hash)

  ;;; ========== Transients (set variant) ==========
  ;;
  ;; Mirrors tmap for bulk construction — wrap a transient-map whose
  ;; keys are the set elements.

  (define-record-type %tset
    (fields (immutable tmap)))

  (define (transient-set s)
    (cond
      [(persistent-set? s) (make-%tset (transient-map (%pset-map s)))]
      [else (error 'transient-set "expected a persistent-set" s)]))

  (define (transient-set? x) (%tset? x))

  (define (tset-check who t)
    (unless (%tset? t)
      (error who "expected a transient-set" t)))

  (define (tset-add! t item)
    (tset-check 'tset-add! t)
    (tmap-set! (%tset-tmap t) item #t)
    t)

  (define (tset-remove! t item)
    (tset-check 'tset-remove! t)
    (tmap-delete! (%tset-tmap t) item)
    t)

  (define (tset-contains? t item)
    (tset-check 'tset-contains? t)
    (tmap-has? (%tset-tmap t) item))

  (define (tset-size t)
    (tset-check 'tset-size t)
    (tmap-size (%tset-tmap t)))

  (define (persistent-set! t)
    (tset-check 'persistent-set! t)
    (make-%pset (persistent-map! (%tset-tmap t))))

  ;;; ========== Chez equal? / equal-hash integration ==========
  ;; Two sets with the same elements compare equal via (equal? s1 s2)
  ;; and hash to the same value, so a pset can key an equal-hashtable.
  (record-type-equal-procedure (record-type-descriptor %pset)
    (lambda (a b rec-equal?) (persistent-set=? a b)))
  (record-type-hash-procedure (record-type-descriptor %pset)
    (lambda (s rec-hash) (persistent-set-hash s)))

  ;;; ========== Printer ==========
  ;; Surface form: #{e1 e2 e3}. Matches Clojure set literal syntax.
  (record-writer (record-type-descriptor %pset)
    (lambda (s port wr)
      (write-char #\# port)
      (write-char #\{ port)
      (let ([first? #t])
        (persistent-set-for-each
          (lambda (x)
            (if first? (set! first? #f) (write-char #\space port))
            (wr x port))
          s))
      (write-char #\} port)))

) ;; end library
