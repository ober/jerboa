#!chezscheme
;;; (std lens) — First-class optics: lenses, prisms, traversals
;;;
;;; Composable getters/setters for deeply nested immutable data.
;;;
;;; API:
;;;   (make-lens getter setter)     — create a lens
;;;   (lens? x)                     — test for lens
;;;   (view lens data)              — get the focused value
;;;   (set lens data val)           — set the focused value (returns new data)
;;;   (over lens data proc)         — apply proc to focused value
;;;   (compose-lens l1 l2 ...)      — compose lenses (left to right, outer to inner)
;;;   (make-prism match construct)  — create a prism for sum types
;;;   (preview prism data)          — try to get value (returns #f if no match)
;;;   (review prism val)            — construct from value
;;;   (make-traversal get-all modify-all) — traversal over multiple foci
;;;   (traverse-view trav data)     — get all focused values
;;;   (traverse-over trav data proc) — apply proc to all focused values
;;;   (each-traversal)              — traversal over list elements
;;;   (identity-lens)               — identity lens (no-op)
;;;   (car-lens) (cdr-lens)         — lenses for pairs
;;;   (list-ref-lens n)             — lens for list element at index n
;;;   (hash-ref-lens key)           — lens for hashtable entry

(library (std lens)
  (export make-lens lens? view set over compose-lens
          make-prism prism? preview review
          make-traversal traversal? traverse-view traverse-over
          each-traversal identity-lens
          car-lens cdr-lens list-ref-lens hash-ref-lens
          vector-ref-lens)

  (import (chezscheme))

  ;; ========== Lens ==========

  (define-record-type lens-impl
    (fields (immutable getter) (immutable setter))
    (sealed #t))

  (define (make-lens getter setter)
    (make-lens-impl getter setter))

  (define (lens? x) (lens-impl? x))

  (define (view lens data)
    ((lens-impl-getter lens) data))

  (define (set lens data val)
    ((lens-impl-setter lens) data val))

  (define (over lens data proc)
    (set lens data (proc (view lens data))))

  ;; ========== Lens composition ==========

  (define compose-lens
    (case-lambda
      [() (identity-lens)]
      [(l) l]
      [(l1 l2)
       (make-lens
         (lambda (data) (view l2 (view l1 data)))
         (lambda (data val)
           (over l1 data (lambda (inner) (set l2 inner val)))))]
      [(l1 l2 . rest)
       (apply compose-lens (compose-lens l1 l2) rest)]))

  ;; ========== Prism ==========

  (define-record-type prism-impl
    (fields (immutable match) (immutable construct))
    (sealed #t))

  (define (make-prism match construct)
    (make-prism-impl match construct))

  (define (prism? x) (prism-impl? x))

  (define (preview prism data)
    ((prism-impl-match prism) data))

  (define (review prism val)
    ((prism-impl-construct prism) val))

  ;; ========== Traversal ==========

  (define-record-type traversal-impl
    (fields (immutable get-all) (immutable modify-all))
    (sealed #t))

  (define (make-traversal get-all modify-all)
    (make-traversal-impl get-all modify-all))

  (define (traversal? x) (traversal-impl? x))

  (define (traverse-view trav data)
    ((traversal-impl-get-all trav) data))

  (define (traverse-over trav data proc)
    ((traversal-impl-modify-all trav) data proc))

  ;; ========== Standard optics ==========

  (define (identity-lens)
    (make-lens
      (lambda (x) x)
      (lambda (_x v) v)))

  (define (car-lens)
    (make-lens car (lambda (p v) (cons v (cdr p)))))

  (define (cdr-lens)
    (make-lens cdr (lambda (p v) (cons (car p) v))))

  (define (list-ref-lens n)
    (make-lens
      (lambda (lst) (list-ref lst n))
      (lambda (lst val)
        (let loop ([l lst] [i 0])
          (cond
            [(null? l) '()]
            [(= i n) (cons val (cdr l))]
            [else (cons (car l) (loop (cdr l) (+ i 1)))])))))

  (define (vector-ref-lens n)
    (make-lens
      (lambda (vec) (vector-ref vec n))
      (lambda (vec val)
        (let ([new (vector-copy vec)])
          (vector-set! new n val)
          new))))

  (define (hash-ref-lens key)
    (make-lens
      (lambda (ht) (hashtable-ref ht key #f))
      (lambda (ht val)
        (let ([new (hashtable-copy ht #t)])
          (hashtable-set! new key val)
          new))))

  ;; ========== Standard traversals ==========

  (define (each-traversal)
    (make-traversal
      (lambda (lst) lst)  ;; get-all: return all elements
      (lambda (lst proc) (map proc lst))))  ;; modify-all: map proc

) ;; end library
