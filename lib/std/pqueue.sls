#!chezscheme
;;; (std pqueue) — Persistent FIFO queue
;;;
;;; A thin compatibility wrapper over `(std srfi srfi-134)` ideques
;;; that exposes Clojure's `PersistentQueue` surface: `pqueue-empty`,
;;; `pqueue-conj` (enqueue at the back), `pqueue-peek` (look at the
;;; front), `pqueue-pop` (dequeue from the front). Ideques are
;;; doubly-ended and provide a superset of what a queue needs, but
;;; this module intentionally only exposes the FIFO operations so that
;;; the type can later be swapped for a dedicated single-ended queue
;;; without breaking callers.
;;;
;;; This module is re-exported from `(std clojure)` with the Clojure
;;; names `peek` and `pop` wired up polymorphically across pairs,
;;; persistent vectors, and persistent queues.
;;;
;;; API:
;;;   persistent-queue            — variadic constructor
;;;   pqueue-empty                — empty queue constant
;;;   pqueue?                     — predicate
;;;   pqueue-conj q x             — enqueue one item, returns new queue
;;;   pqueue-peek q               — front element, or #f when empty
;;;   pqueue-pop q                — drop front, returns new queue
;;;                                 (#f or same-empty-queue if empty)
;;;   pqueue-count q              — number of queued items
;;;   pqueue->list q              — front-to-back list
;;;   list->pqueue lst            — build from a list
;;;   pqueue-empty? q             — empty predicate

(library (std pqueue)
  (export persistent-queue pqueue-empty pqueue?
          pqueue-conj pqueue-peek pqueue-pop
          pqueue-count pqueue->list
          list->pqueue pqueue-empty?)

  (import (chezscheme)
          (std srfi srfi-134))

  ;; The empty queue is just an empty ideque. `pqueue-empty` is a
  ;; fresh ideque each library load — because ideques are mutable
  ;; internally we avoid aliasing a single instance across threads.
  (define pqueue-empty (ideque))

  ;; Variadic constructor: (persistent-queue 1 2 3) → front=1, back=3.
  (define (persistent-queue . items)
    (list->ideque items))

  (define (list->pqueue items)
    (list->ideque items))

  (define pqueue? ideque?)

  (define (pqueue-conj q x)
    ;; ideque-add-back is O(1) amortized — matching Clojure's
    ;; PersistentQueue.conj which appends to the tail.
    (ideque-add-back q x))

  (define (pqueue-peek q)
    ;; Clojure's peek returns nil on an empty queue. We model nil
    ;; as #f so callers can use `or` / `when-let` ergonomically.
    (if (ideque-empty? q) #f (ideque-front q)))

  (define (pqueue-pop q)
    ;; pop on an empty queue: Clojure raises. We preserve that so
    ;; programs that shouldn't be popping an empty queue fail loud.
    (if (ideque-empty? q)
        (error 'pqueue-pop "cannot pop from an empty queue")
        (ideque-remove-front q)))

  (define pqueue-count ideque-length)
  (define pqueue->list ideque->list)
  (define pqueue-empty? ideque-empty?)

) ;; end library
