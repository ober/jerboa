#!/usr/bin/env scheme-script
;;; Tests for Async/Await (Phase 5d — Track 17.3)

(import (chezscheme) (std concur async-await))

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
;; 1. Promise construction
;; --------------------------------------------------------------------------

(printf "~n--- Promise Construction ---~n")

(let ([p (make-promise)])
  (check-true "promise? yes"        (promise? p))
  (check      "promise? no"         (promise? 42) => #f)
  (check      "initially unresolved" (promise-resolved? p) => #f))

;; --------------------------------------------------------------------------
;; 2. Promise resolve and await
;; --------------------------------------------------------------------------

(printf "~n--- Resolve and Await ---~n")

(let ([p (make-promise)])
  (promise-resolve! p 42)
  (check "resolved promise"  (promise-resolved? p) => #t)
  (check "await resolved"    (promise-await p) => 42))

;; Resolve idempotent
(let ([p (make-promise)])
  (promise-resolve! p 1)
  (promise-resolve! p 2)  ; second resolve ignored
  (check "resolve idempotent" (promise-await p) => 1))

;; --------------------------------------------------------------------------
;; 3. Promise reject
;; --------------------------------------------------------------------------

(printf "~n--- Reject ---~n")

(let ([p (make-promise)])
  (promise-reject! p (condition (make-message-condition "boom")))
  (check-true "rejected resolved" (promise-resolved? p))
  (let ([caught #f])
    (call-with-current-continuation
      (lambda (k)
        (with-exception-handler
          (lambda (e) (set! caught #t) (k (void)))
          (lambda () (promise-await p)))))
    (check "await re-raises rejection" caught => #t)))

;; --------------------------------------------------------------------------
;; 4. async spawns background computation
;; --------------------------------------------------------------------------

(printf "~n--- async ---~n")

(let ([p (async (lambda () (* 6 7)))])
  (check-true "async returns promise" (promise? p))
  (check "async result"               (await p) => 42))

(let ([p (async (lambda ()
                  (sleep (make-time 'time-duration 100000000 0))  ; 100ms
                  99))])
  (check "async sleeps then resolves" (await p) => 99))

;; --------------------------------------------------------------------------
;; 5. await on plain value
;; --------------------------------------------------------------------------

(printf "~n--- await plain value ---~n")

(check "await non-promise passthrough" (await 123) => 123)

;; --------------------------------------------------------------------------
;; 6. await-all
;; --------------------------------------------------------------------------

(printf "~n--- await-all ---~n")

(let ([p1 (async (lambda () 1))]
      [p2 (async (lambda () 2))]
      [p3 (async (lambda () 3))])
  (let ([results (await-all p1 p2 p3)])
    (check "await-all results" results => '(1 2 3))))

;; --------------------------------------------------------------------------
;; 7. define-async
;; --------------------------------------------------------------------------

(printf "~n--- define-async ---~n")

(define-async (add-async a b)
  (+ a b))

(let ([p (add-async 10 32)])
  (check-true "define-async returns promise" (promise? p))
  (check "define-async result" (await p) => 42))

;; --------------------------------------------------------------------------
;; 8. Cancellation tokens
;; --------------------------------------------------------------------------

(printf "~n--- Cancellation ---~n")

(let* ([cts (make-cancellation-token-source)]
       [tok (cts-token cts)])
  (check-true "token is token"      (cancellation-token? tok))
  (check      "initially live"      (begin (check-cancellation! tok) #t) => #t)
  (cts-cancel! cts)
  (let ([cancelled #f])
    (call-with-current-continuation
      (lambda (k)
        (with-exception-handler
          (lambda (e) (set! cancelled #t) (k (void)))
          (lambda () (check-cancellation! tok)))))
    (check "check-cancellation! raises after cancel" cancelled => #t)))

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
