#!chezscheme
;;; (std sorted-set) — Persistent sorted set
;;;
;;; A thin wrapper over `(std ds sorted-map)` that models a sorted set
;;; as a sorted-map where every key maps to `#t`. Provides Clojure's
;;; `sorted-set` surface: ordered iteration, min/max, range queries,
;;; and O(log n) add/remove/contains? against a red-black tree.
;;;
;;; This module is re-exported from `(std clojure)` with the Clojure
;;; name `sorted-set` wired into the polymorphic `conj` / `disj` /
;;; `contains?` / `count` / `first` / `last` / `seq` dispatch, and
;;; with the clojure.set algebra (`union`/`intersection`/`difference`)
;;; operating on sorted sets.
;;;
;;; API:
;;;   sorted-set                  — variadic constructor (default cmp)
;;;   sorted-set-by               — variadic constructor with custom cmp
;;;   sorted-set?                 — predicate
;;;   sorted-set-empty            — empty sorted set (default cmp)
;;;   sorted-set-add ss x         — insert, returns new set
;;;   sorted-set-remove ss x      — delete, returns new set
;;;   sorted-set-contains? ss x   — membership check
;;;   sorted-set-size ss          — cardinality
;;;   sorted-set-min ss           — smallest element or #f
;;;   sorted-set-max ss           — largest element or #f
;;;   sorted-set-range ss lo hi   — list of elements in [lo, hi]
;;;   sorted-set->list ss         — ordered list of elements
;;;   sorted-set-fold ss proc init — left fold with proc : (x acc) -> acc

(library (std sorted-set)
  (export sorted-set sorted-set-by sorted-set?
          sorted-set-empty
          sorted-set-add sorted-set-remove
          sorted-set-contains? sorted-set-size
          sorted-set-min sorted-set-max
          sorted-set-range sorted-set->list
          sorted-set-fold)

  (import (chezscheme)
          (std ds sorted-map))

  ;; Internal record: a wrapper around a sorted-map where every key
  ;; maps to #t. We rename the constructor/predicate to avoid colliding
  ;; with the public variadic `sorted-set` and the public `sorted-set?`.
  (define-record-type (sset-rec %make-sset sset-rec?)
    (fields (immutable sm sset-sm)))

  (define sorted-set? sset-rec?)

  ;; Empty sorted-set using the default comparator.
  (define sorted-set-empty (%make-sset (sorted-map-empty)))

  ;; Variadic constructor — Clojure: (sorted-set 3 1 2) → {1 2 3}.
  (define (sorted-set . items)
    (if (null? items)
        sorted-set-empty
        (let loop ([s sorted-set-empty] [rest items])
          (if (null? rest)
              s
              (loop (sorted-set-add s (car rest)) (cdr rest))))))

  ;; Variadic constructor with a custom comparator — Clojure:
  ;; (sorted-set-by cmp 3 1 2).
  (define (sorted-set-by cmp . items)
    (let ([empty (%make-sset (make-sorted-map cmp))])
      (let loop ([s empty] [rest items])
        (if (null? rest)
            s
            (loop (sorted-set-add s (car rest)) (cdr rest))))))

  ;; Add an element. Idempotent: adding an existing element returns
  ;; an equivalent set (structurally shared internal nodes).
  (define (sorted-set-add ss x)
    (%make-sset (sorted-map-insert (sset-sm ss) x #t)))

  ;; Remove an element. If the element isn't present, returns `ss`.
  (define (sorted-set-remove ss x)
    (%make-sset (sorted-map-delete (sset-sm ss) x)))

  (define (sorted-set-contains? ss x)
    ;; sorted-map-lookup returns the value (which is always #t here)
    ;; for a present key, or #f for an absent key — perfect for a
    ;; boolean membership predicate.
    (if (sorted-map-lookup (sset-sm ss) x) #t #f))

  (define (sorted-set-size ss)
    (sorted-map-size (sset-sm ss)))

  (define (sorted-set-min ss)
    ;; sorted-map-min returns (cons k v) or #f.
    (let ([r (sorted-map-min (sset-sm ss))])
      (if r (car r) #f)))

  (define (sorted-set-max ss)
    (let ([r (sorted-map-max (sset-sm ss))])
      (if r (car r) #f)))

  ;; Return the list of elements in [lo, hi], in sorted order.
  ;; Clojure's `subseq` is richer (supports open/closed bounds); we
  ;; offer the simple closed-interval version that matches
  ;; sorted-map-range's semantics.
  (define (sorted-set-range ss lo hi)
    (sorted-map-keys (sorted-map-range (sset-sm ss) lo hi)))

  (define (sorted-set->list ss)
    (sorted-map-keys (sset-sm ss)))

  ;; Left fold over elements in ascending order:
  ;;   (proc element acc) → acc
  (define (sorted-set-fold ss proc init)
    (sorted-map-fold (sset-sm ss)
                     (lambda (k v acc) (proc k acc))
                     init))

) ;; end library
