#!chezscheme
;;; Tests for (std pqueue) and Clojure's peek/pop polymorphism.
;;;
;;; Exercises the pqueue-* primitives directly and verifies the
;;; polymorphic conj/peek/pop dispatch in (std clojure) handles
;;; lists, persistent vectors, and persistent queues.

(import (chezscheme)
        (std pqueue)
        (std pvec)
        (std clojure))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(define-syntax test-true
  (syntax-rules ()
    [(_ name expr)
     (test name (if expr #t #f) #t)]))

(printf "--- (std pqueue) + Clojure peek/pop ---~%~%")

;;; ===== pqueue primitives =====

(test "pqueue-empty is empty"
  (pqueue-empty? pqueue-empty)
  #t)

(test "pqueue? accepts the empty queue"
  (pqueue? pqueue-empty)
  #t)

(test "pqueue? rejects plain list"
  (pqueue? '(1 2 3))
  #f)

(test "persistent-queue constructor builds front-to-back"
  (pqueue->list (persistent-queue 1 2 3 4))
  '(1 2 3 4))

(test "pqueue-conj appends at the back"
  (pqueue->list
    (pqueue-conj (pqueue-conj (pqueue-conj pqueue-empty 'a) 'b) 'c))
  '(a b c))

(test "pqueue-peek returns the front"
  (pqueue-peek (persistent-queue 10 20 30))
  10)

(test "pqueue-peek on empty returns #f"
  (pqueue-peek pqueue-empty)
  #f)

(test "pqueue-pop drops the front"
  (pqueue->list (pqueue-pop (persistent-queue 1 2 3)))
  '(2 3))

(test "pqueue-pop twice"
  (pqueue->list (pqueue-pop (pqueue-pop (persistent-queue 1 2 3))))
  '(3))

(test "pqueue-count"
  (pqueue-count (persistent-queue 'a 'b 'c 'd))
  4)

(test "list->pqueue round-trips"
  (pqueue->list (list->pqueue '(x y z)))
  '(x y z))

;;; ===== conj polymorphism — existing types still work =====

(test "conj on list prepends"
  (conj '(1 2 3) 0)
  '(0 1 2 3))

(test "conj on mutable vector appends"
  (conj (vector 1 2 3) 4)
  (vector 1 2 3 4))

;;; ===== conj on persistent vector =====

(test "conj on persistent-vector appends"
  (persistent-vector->list
    (conj (persistent-vector 1 2 3) 4))
  '(1 2 3 4))

(test "conj on persistent-vector multiple"
  (persistent-vector->list
    (conj (persistent-vector 1) 2 3 4))
  '(1 2 3 4))

;;; ===== conj on pqueue =====

(test "conj on pqueue single"
  (pqueue->list (conj pqueue-empty 'x))
  '(x))

(test "conj on pqueue multiple — order preserved"
  (pqueue->list (conj (persistent-queue 1 2) 3 4 5))
  '(1 2 3 4 5))

;;; ===== peek polymorphism =====

(test "peek list = first"
  (peek '(10 20 30))
  10)

(test "peek empty list is #f"
  (peek '())
  #f)

(test "peek pqueue = front"
  (peek (persistent-queue 'a 'b 'c))
  'a)

(test "peek empty pqueue is #f"
  (peek pqueue-empty)
  #f)

(test "peek persistent-vector = last (stack end)"
  (peek (persistent-vector 1 2 3 4))
  4)

(test "peek empty persistent-vector is #f"
  (peek (persistent-vector))
  #f)

(test "peek mutable vector = last"
  (peek (vector 'x 'y 'z))
  'z)

;;; ===== pop polymorphism =====

(test "pop list = rest"
  (pop '(1 2 3 4))
  '(2 3 4))

(test "pop pqueue = drop front"
  (pqueue->list (pop (persistent-queue 1 2 3 4)))
  '(2 3 4))

(test "pop persistent-vector = drop last (stack end)"
  (persistent-vector->list
    (pop (persistent-vector 1 2 3 4)))
  '(1 2 3))

(test "pop persistent-vector until empty"
  (persistent-vector->list
    (pop (pop (pop (persistent-vector 1 2 3)))))
  '())

;;; ===== Queue used as a work queue — FIFO semantics =====

(test "pqueue FIFO drain via peek + pop"
  (let loop ([q (persistent-queue 'a 'b 'c 'd)] [acc '()])
    (if (pqueue-empty? q)
        (reverse acc)
        (loop (pop q) (cons (peek q) acc))))
  '(a b c d))

;;; ===== Empty-queue semantics =====

(test "pop on empty pqueue raises"
  (guard (exn [#t 'raised])
    (pop pqueue-empty))
  'raised)

(test "pop on empty list raises"
  (guard (exn [#t 'raised])
    (pop '()))
  'raised)

(test "pop on empty persistent-vector raises"
  (guard (exn [#t 'raised])
    (pop (persistent-vector)))
  'raised)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
