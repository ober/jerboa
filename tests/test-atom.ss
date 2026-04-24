#!chezscheme
;;; Tests for (std misc atom) — atom, watches, volatiles.

(import (jerboa prelude))

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

(printf "--- atom / watches / volatiles ---~%~%")

;;; ---- Core atom ops (regression safety) ----

(test "atom deref initial"
  (deref (atom 42))
  42)

(test "reset! returns new value"
  (let ([a (atom 0)])
    (list (reset! a 10) (deref a)))
  '(10 10))

(test "swap! variadic"
  (let ([a (atom 10)])
    (swap! a + 3 4)
    (deref a))
  17)

(test "compare-and-set! success"
  (let ([a (atom 5)])
    (list (compare-and-set! a 5 100) (deref a)))
  '(#t 100))

(test "compare-and-set! failure"
  (let ([a (atom 5)])
    (list (compare-and-set! a 999 100) (deref a)))
  '(#f 5))

;;; ---- Watches ----

(test "add-watch! fires on reset!"
  (let ([a (atom 0)]
        [seen (atom '())])
    (add-watch! a 'w
      (lambda (k atm old new)
        (swap! seen (lambda (xs) (cons (list k old new) xs)))))
    (reset! a 42)
    (reverse (deref seen)))
  '((w 0 42)))

(test "add-watch! fires on swap!"
  (let ([a (atom 1)]
        [calls (atom '())])
    (add-watch! a 'tracker
      (lambda (k atm old new)
        (swap! calls (lambda (xs) (cons (cons old new) xs)))))
    (swap! a + 2)
    (swap! a * 5)
    (reverse (deref calls)))
  '((1 . 3) (3 . 15)))

(test "add-watch! gets atom reference"
  (let ([a (atom 0)]
        [seen (atom #f)])
    (add-watch! a 'who
      (lambda (k atm old new)
        (reset! seen (eq? atm a))))
    (reset! a 1)
    (deref seen))
  #t)

(test "add-watch! receives key"
  (let ([a (atom 0)]
        [seen-key (atom #f)])
    (add-watch! a 'my-key
      (lambda (k atm old new) (reset! seen-key k)))
    (reset! a 1)
    (deref seen-key))
  'my-key)

(test "multiple watches all fire"
  (let ([a (atom 0)]
        [w1 (atom 0)]
        [w2 (atom 0)])
    (add-watch! a 'one (lambda (k atm old new) (swap! w1 + 1)))
    (add-watch! a 'two (lambda (k atm old new) (swap! w2 + 1)))
    (reset! a 1)
    (reset! a 2)
    (list (deref w1) (deref w2)))
  '(2 2))

(test "same-key re-add replaces previous callback"
  (let ([a (atom 0)]
        [seen (atom #f)])
    (add-watch! a 'k (lambda (k atm old new) (reset! seen 'first)))
    (add-watch! a 'k (lambda (k atm old new) (reset! seen 'second)))
    (reset! a 1)
    (deref seen))
  'second)

(test "remove-watch! stops firing"
  (let ([a (atom 0)]
        [count (atom 0)])
    (add-watch! a 'w (lambda (k atm old new) (swap! count + 1)))
    (reset! a 1)
    (reset! a 2)
    (remove-watch! a 'w)
    (reset! a 3)
    (deref count))
  2)

(test "remove-watch! idempotent on missing key"
  (let ([a (atom 0)])
    (remove-watch! a 'never-registered)
    (deref a))
  0)

(test "compare-and-set! success fires watches"
  (let ([a (atom 10)]
        [count (atom 0)])
    (add-watch! a 'w (lambda (k atm old new) (swap! count + 1)))
    (compare-and-set! a 10 20)
    (deref count))
  1)

(test "compare-and-set! failure does NOT fire watches"
  (let ([a (atom 10)]
        [count (atom 0)])
    (add-watch! a 'w (lambda (k atm old new) (swap! count + 1)))
    (compare-and-set! a 999 20)
    (deref count))
  0)

(test "watch exception does not break the atom"
  (let ([a (atom 0)])
    (add-watch! a 'bad (lambda (k atm old new) (error 'bad "boom")))
    (reset! a 1)
    (reset! a 2)
    (deref a))
  2)

(test "watch can reenter atom (runs outside lock)"
  (let ([a (atom 0)]
        [log (atom '())])
    (add-watch! a 'w
      (lambda (k atm old new)
        ;; Reading deref here would deadlock if watches ran inside the mutex.
        (swap! log (lambda (xs) (cons (deref atm) xs)))))
    (reset! a 1)
    (reset! a 2)
    (reverse (deref log)))
  '(1 2))

(test "add-watch! / remove-watch! return atom for chaining"
  (let ([a (atom 0)])
    (eq? (remove-watch! (add-watch! a 'w (lambda args #f)) 'w)
         a))
  #t)

;;; ---- Volatiles ----

(test "volatile! constructs"
  (volatile? (volatile! 42))
  #t)

(test "volatile? rejects non-volatiles"
  (list (volatile? 42) (volatile? (atom 0)) (volatile? '()))
  '(#f #f #f))

(test "vderef reads"
  (vderef (volatile! 'hi))
  'hi)

(test "vreset! sets and returns new"
  (let ([v (volatile! 0)])
    (list (vreset! v 10) (vderef v)))
  '(10 10))

(test "vswap! applies function"
  (let ([v (volatile! 10)])
    (list (vswap! v + 5) (vderef v)))
  '(15 15))

(test "vswap! variadic"
  (let ([v (volatile! 2)])
    (vswap! v * 3 4)
    (vderef v))
  24)

(test "volatile has no watches"
  ;; Sanity: volatiles aren't atoms, no watch API applies.
  (not (atom? (volatile! 0)))
  #t)

;;; ---- Validators (Round 5 §31) ----

(import (only (std misc atom) set-validator! get-validator))

(test "get-validator default is #f"
  (get-validator (atom 0))
  #f)

(test "set-validator! then get-validator round-trips"
  (let ([a (atom 0)]
        [v (lambda (n) (and (integer? n) (>= n 0)))])
    (set-validator! a v)
    (eq? (get-validator a) v))
  #t)

(test "set-validator! rejects installing on value that fails predicate"
  (let ([a (atom -1)])
    (guard (exn [else 'caught])
      (set-validator! a (lambda (n) (>= n 0)))
      'passed))
  'caught)

(test "reset! honors validator (accept)"
  (let ([a (atom 0)])
    (set-validator! a (lambda (n) (integer? n)))
    (reset! a 42))
  42)

(test "reset! honors validator (reject)"
  (let ([a (atom 0)])
    (set-validator! a (lambda (n) (integer? n)))
    (guard (exn [else 'caught])
      (reset! a "not-an-int")
      'passed))
  'caught)

(test "reset! rejection leaves old value"
  (let ([a (atom 7)])
    (set-validator! a (lambda (n) (integer? n)))
    (guard (exn [else (deref a)])
      (reset! a "bad")
      'impossible))
  7)

(test "swap! honors validator"
  (let ([a (atom 5)])
    (set-validator! a (lambda (n) (and (integer? n) (< n 10))))
    (swap! a + 3))
  8)

(test "swap! rejects and keeps old value"
  (let ([a (atom 5)])
    (set-validator! a (lambda (n) (< n 10)))
    (guard (exn [else (deref a)])
      (swap! a + 100)))
  5)

(test "compare-and-set! honors validator (reject)"
  (let ([a (atom 1)])
    (set-validator! a (lambda (n) (odd? n)))
    (guard (exn [else (deref a)])
      (compare-and-set! a 1 2)
      'impossible))
  1)

(test "clearing validator by setting to #f"
  (let ([a (atom 0)])
    (set-validator! a (lambda (n) (>= n 0)))
    (set-validator! a #f)
    (reset! a -42))
  -42)

(test "validator that throws treated as rejection"
  ;; Validator throws on the *new* value only; the current value
  ;; passes so set-validator! installs cleanly. The throw then
  ;; surfaces on reset!, which must leave the old value in place.
  (let ([a (atom 1)])
    (set-validator! a (lambda (n) (if (= n 1) #t (error 'v "nope"))))
    (guard (exn [else (deref a)])
      (reset! a 2)
      'impossible))
  1)

(test "validator not called on failing CAS"
  ;; Install the validator first, then zero the counter, then test
  ;; that CAS with a wrong `expected` skips the validator entirely.
  (let ([a (atom 1)]
        [calls 0])
    (set-validator! a (lambda (n) (set! calls (+ calls 1)) #t))
    (set! calls 0)
    (compare-and-set! a 99 100)  ;; current is 1, expected 99 — CAS fails
    calls)
  0)

;;; ---- Summary ----
(printf "~%atom: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
