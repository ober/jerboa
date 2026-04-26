#!chezscheme
;;; (std clojure walk) — clojure.walk compatibility
;;;
;;; Generic structure-preserving tree walking.  Each public entry
;;; receives a function and a form, recurses into the form's children,
;;; and reconstructs the same kind of container with the transformed
;;; children.
;;;
;;; Recognised containers (read on input, preserved on output):
;;;
;;;   - cons / list / improper list
;;;   - vector
;;;   - hash-table        (mutable, as built by `make-hash-table`)
;;;   - persistent-map    (a.k.a. imap, from (std pmap))
;;;   - persistent-vector (from (std pvec))
;;;   - persistent-set    (from (std pset))
;;;   - record            (defstruct / define-record-type) — fields
;;;     are walked and a new instance is built with the same rtd.
;;;
;;; Anything else is treated as a leaf (string, number, symbol, char,
;;; bytevector, procedure, eof, ...).
;;;
;;;   (postwalk (lambda (x) (if (number? x) (* 2 x) x))
;;;             '(1 (2 (3 :tag)) #(4 5)))
;;;     ;; => (2 (4 (6 :tag)) #(8 10))
;;;
;;;   (keywordize-keys (hash-map "a" 1 "b" 2))
;;;     ;; => persistent map with keys :a, :b

(library (std clojure walk)
  (export
    walk
    prewalk
    postwalk
    keywordize-keys
    stringify-keys
    prewalk-replace
    postwalk-replace)

  (import (except (chezscheme) make-hash-table hash-table?)
          (only (jerboa runtime)
                keyword? keyword->string string->keyword
                make-hash-table hash-table? hash-keys hash-ref hash-put!)
          (only (std pmap)
                persistent-map? persistent-map make-persistent-map
                persistent-map->list persistent-map-set persistent-map-ref
                persistent-map-has? in-pmap-pairs)
          (only (std pvec)
                persistent-vector? persistent-vector
                persistent-vector->list)
          (only (std pset)
                persistent-set? persistent-set
                persistent-set->list))

  ;; ---- Container detection helpers ----------------------------

  ;; Records are deliberately treated as leaves: rebuilding a fresh
  ;; instance via `record-constructor` is fragile across rtds with
  ;; parents, mutable invariants, or non-trivial constructors.  Code
  ;; that wants to walk record fields can convert to a map first
  ;; (via the polymorphic `assoc` in (std clojure)) and walk the map.

  (define (hash-table-walk f ht)
    (let ([new (make-hash-table)])
      (for-each
        (lambda (k)
          (let ([v (hash-ref ht k)])
            (hash-put! new (f k) (f v))))
        (hash-keys ht))
      new))

  (define (pmap-walk f pm)
    (let loop ([pairs (persistent-map->list pm)]
               [acc (persistent-map)])
      (cond
        [(null? pairs) acc]
        [else
         (let* ([kv (car pairs)]
                [k (car kv)]
                [v (cdr kv)])
           (loop (cdr pairs) (persistent-map-set acc (f k) (f v))))])))

  (define (pvec-walk f pv)
    (apply persistent-vector
           (map f (persistent-vector->list pv))))

  (define (pset-walk f ps)
    (apply persistent-set
           (map f (persistent-set->list ps))))

  (define (list-walk f form)
    ;; Preserve improper lists.  (a b . c) walks each cell.
    (let loop ([l form])
      (cond
        [(null? l) '()]
        [(pair? l) (cons (f (car l)) (loop (cdr l)))]
        [else (f l)])))

  ;; ---- walk ----------------------------------------------------

  ;; (walk INNER OUTER FORM)
  ;;
  ;; Apply INNER to each immediate child of FORM, reconstruct the same
  ;; container with the results, then call OUTER on the reconstructed
  ;; container.  This is the primitive on top of which prewalk and
  ;; postwalk are built.
  (define (walk inner outer form)
    (cond
      [(pair? form)              (outer (list-walk inner form))]
      [(vector? form)            (outer (vector-map inner form))]
      [(persistent-map? form)    (outer (pmap-walk inner form))]
      [(persistent-vector? form) (outer (pvec-walk inner form))]
      [(persistent-set? form)    (outer (pset-walk inner form))]
      [(hash-table? form)        (outer (hash-table-walk inner form))]
      [else                      (outer form)]))

  ;; (prewalk F FORM)  — F is called before recursion (top-down).
  ;; (postwalk F FORM) — F is called after recursion (bottom-up).
  (define (prewalk f form)
    (walk (lambda (x) (prewalk f x)) (lambda (x) x) (f form)))

  (define (postwalk f form)
    (walk (lambda (x) (postwalk f x)) f form))

  ;; ---- Convenience wrappers -----------------------------------

  ;; Walk every key in any map-like container; convert string keys to
  ;; keywords (ignoring non-string keys).
  (define (keywordize-keys form)
    (postwalk
      (lambda (x)
        (cond
          [(persistent-map? x)
           (let loop ([pairs (persistent-map->list x)]
                      [acc (persistent-map)])
             (cond
               [(null? pairs) acc]
               [else
                (let* ([kv (car pairs)]
                       [k (car kv)]
                       [v (cdr kv)]
                       [k* (if (string? k) (string->keyword k) k)])
                  (loop (cdr pairs) (persistent-map-set acc k* v)))]))]
          [(hash-table? x)
           (let ([new (make-hash-table)])
             (for-each
               (lambda (k)
                 (let ([v (hash-ref x k)])
                   (hash-put! new
                              (if (string? k) (string->keyword k) k)
                              v)))
               (hash-keys x))
             new)]
          [else x]))
      form))

  ;; Inverse of keywordize-keys: keyword keys become strings.
  (define (stringify-keys form)
    (postwalk
      (lambda (x)
        (cond
          [(persistent-map? x)
           (let loop ([pairs (persistent-map->list x)]
                      [acc (persistent-map)])
             (cond
               [(null? pairs) acc]
               [else
                (let* ([kv (car pairs)]
                       [k (car kv)]
                       [v (cdr kv)]
                       [k* (if (keyword? k) (keyword->string k) k)])
                  (loop (cdr pairs) (persistent-map-set acc k* v)))]))]
          [(hash-table? x)
           (let ([new (make-hash-table)])
             (for-each
               (lambda (k)
                 (let ([v (hash-ref x k)])
                   (hash-put! new
                              (if (keyword? k) (keyword->string k) k)
                              v)))
               (hash-keys x))
             new)]
          [else x]))
      form))

  ;; SMAP can be: persistent-map, hash-table, or alist.  In each case,
  ;; if a leaf x is a key in SMAP it is replaced with the corresponding
  ;; value; otherwise x is returned unchanged.
  (define (%lookup-replacement smap x)
    (cond
      [(persistent-map? smap)
       (if (persistent-map-has? smap x)
           (persistent-map-ref smap x)
           x)]
      [(hash-table? smap)
       (if (hashtable-contains? smap x) (hash-ref smap x) x)]
      [(list? smap)
       (cond [(assoc x smap) => cdr] [else x])]
      [else x]))

  ;; (prewalk-replace SMAP FORM)  — replace each occurrence of a key
  ;; in SMAP with its mapped value, top-down.
  (define (prewalk-replace smap form)
    (prewalk (lambda (x) (%lookup-replacement smap x)) form))

  (define (postwalk-replace smap form)
    (postwalk (lambda (x) (%lookup-replacement smap x)) form))

) ;; end library
