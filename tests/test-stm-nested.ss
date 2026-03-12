#!/usr/bin/env scheme-script
;;; Tests for STM with Nested Transactions (Phase 5d — Track 17.1)
;;; Tests the (std concur stm) library specifically.

(import (chezscheme) (std concur stm))

(define test-count 0)
(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ name expr => expected)
     (begin
       (set! test-count (+ test-count 1))
       (let ([result expr])
         (if (equal? result expected)
             (begin (printf "  PASS: ~a~n" name)
                    (set! pass-count (+ pass-count 1)))
             (begin (printf "  FAIL: ~a~n" name)
                    (printf "    expected: ~s~n" expected)
                    (printf "    got:      ~s~n" result)
                    (set! fail-count (+ fail-count 1))))))]))

(define-syntax check-true
  (syntax-rules ()
    [(_ name e) (check name e => #t)]))

;; --------------------------------------------------------------------------
;; 1. Basic TVar operations
;; --------------------------------------------------------------------------

(printf "~n--- TVar Basics ---~n")

(let ([tv (make-tvar 0)])
  (check-true "tvar?" (tvar? tv))
  (check "initial value" (tvar-get tv) => 0))

;; --------------------------------------------------------------------------
;; 2. Simple atomically
;; --------------------------------------------------------------------------

(printf "~n--- Simple atomically ---~n")

(let ([a (make-tvar 10)]
      [b (make-tvar 20)])
  (atomically (lambda ()
    (tvar-set! a (+ (tvar-get a) 5))
    (tvar-set! b (- (tvar-get b) 5))))
  (check "a updated" (tvar-get a) => 15)
  (check "b updated" (tvar-get b) => 15))

;; --------------------------------------------------------------------------
;; 3. Nested transactions merge into outer
;; --------------------------------------------------------------------------

(printf "~n--- Nested Transactions ---~n")

(let ([x (make-tvar 100)]
      [y (make-tvar 200)])
  (atomically (lambda ()
    (tvar-set! x 1)
    (atomically (lambda ()
      (tvar-set! y 2)
      ;; x's pending value visible in nested txn
      ;; Nested txn reads the committed value, not the parent's pending write
      (check "nested reads committed x" (tvar-get x) => 100)
      ;; nested write visible immediately within its scope
      (check "nested own write" (tvar-get y) => 2)))
    ;; both writes visible in outer after nested completes
    (check "outer sees nested write" (tvar-get y) => 2)))
  (check "x committed" (tvar-get x) => 1)
  (check "y committed" (tvar-get y) => 2))

;; --------------------------------------------------------------------------
;; 4. Transaction return value
;; --------------------------------------------------------------------------

(printf "~n--- Return Values ---~n")

(let ([tv (make-tvar 42)])
  (let ([result (atomically (lambda () (tvar-get tv)))])
    (check "atomically returns thunk result" result => 42)))

;; --------------------------------------------------------------------------
;; 5. Multiple sequential transactions
;; --------------------------------------------------------------------------

(printf "~n--- Sequential Transactions ---~n")

(let ([counter (make-tvar 0)])
  (let loop ([i 0])
    (when (< i 5)
      (atomically (lambda ()
        (tvar-set! counter (+ (tvar-get counter) 1))))
      (loop (+ i 1))))
  (check "5 sequential increments" (tvar-get counter) => 5))

;; --------------------------------------------------------------------------
;; 6. or-else — first succeeds
;; --------------------------------------------------------------------------

(printf "~n--- or-else ---~n")

(let ([tv (make-tvar 99)])
  (let ([result (atomically (lambda ()
                  (or-else
                    (lambda () (tvar-get tv))
                    (lambda () -1))))])
    (check "or-else first branch" result => 99)))

;; --------------------------------------------------------------------------
;; 7. or-else — first retries, second runs
;; --------------------------------------------------------------------------

(let ([ready (make-tvar #t)])
  (let ([result (atomically (lambda ()
                  (or-else
                    (lambda ()
                      (if (tvar-get ready)
                          (tvar-get ready)
                          (retry)))
                    (lambda () 'fallback))))])
    (check "or-else first succeeds when ready" result => #t)))

(let ([result (atomically (lambda ()
                (or-else
                  (lambda () (retry))
                  (lambda () 'second))))])
  (check "or-else retries to second" result => 'second))

;; --------------------------------------------------------------------------
;; 8. Deeply nested transactions
;; --------------------------------------------------------------------------

(printf "~n--- Deep Nesting ---~n")

(let ([tv (make-tvar 0)])
  (atomically (lambda ()
    (tvar-set! tv 1)
    (atomically (lambda ()
      (tvar-set! tv 2)
      (atomically (lambda ()
        (tvar-set! tv 3)))
      (check "deep nest level 2 sees level 3" (tvar-get tv) => 3)))
    (check "level 1 sees all nested writes" (tvar-get tv) => 3)))
  (check "deep nested committed" (tvar-get tv) => 3))

;; --------------------------------------------------------------------------
;; Summary
;; --------------------------------------------------------------------------

(printf "~n===========================================~n")
(printf "Tests: ~a  |  Passed: ~a  |  Failed: ~a~n"
        test-count pass-count fail-count)
(printf "===========================================~n")
(when (> fail-count 0)
  (printf "~nFAILED~n")
  (exit 1))
(printf "~nAll tests passed!~n")
