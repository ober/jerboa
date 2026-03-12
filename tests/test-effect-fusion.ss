#!/usr/bin/env scheme-script
;;; Tests for Effect Fusion (Phase 5d — Track 16.1)

(import (chezscheme) (std effect) (std effect fusion))

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

;; Define test effects
(defeffect Log (write msg))
(defeffect State (get) (put val))

;; --------------------------------------------------------------------------
;; 1. Basic with-fused-handlers — single effect
;; --------------------------------------------------------------------------

(printf "~n--- Single Effect ---~n")

(let ([log-buf '()])
  (with-fused-handlers
    ([Log (write (k msg)
           (set! log-buf (append log-buf (list msg)))
           (resume k (void)))])
    (perform (Log write "hello"))
    (perform (Log write "world")))
  (check "messages logged" log-buf => '("hello" "world")))

;; --------------------------------------------------------------------------
;; 2. with-fused-handlers — two effects in one form
;; --------------------------------------------------------------------------

(printf "~n--- Two Effects ---~n")

(let ([state 0]
      [log-buf '()])
  (with-fused-handlers
    ([State
      (get   (k)     (resume k state))
      (put   (k val) (set! state val) (resume k (void)))]
     [Log
      (write (k msg) (set! log-buf (cons msg log-buf)) (resume k (void)))])
    (perform (State put 10))
    (perform (Log write "set to 10"))
    (perform (State put (+ (perform (State get)) 5)))
    (perform (Log write "incremented")))
  (check "final state" state => 15)
  (check "log messages" (reverse log-buf) => '("set to 10" "incremented")))

;; --------------------------------------------------------------------------
;; 3. Return value passes through
;; --------------------------------------------------------------------------

(printf "~n--- Return Value ---~n")

(let ([result
       (with-fused-handlers
         ([Log (write (k msg) (resume k (void)))])
         (perform (Log write "ignored"))
         42)])
  (check "return value from body" result => 42))

;; --------------------------------------------------------------------------
;; 4. Fusion statistics
;; --------------------------------------------------------------------------

(printf "~n--- Fusion Statistics ---~n")

(fusion-stats-reset!)
(let ([stats (handler-fusion-stats)])
  (check "stats is alist" (list? stats) => #t))

;; --------------------------------------------------------------------------
;; 5. Nested with-fused-handlers
;; --------------------------------------------------------------------------

(printf "~n--- Nested ---~n")

(let ([calls '()])
  (with-fused-handlers
    ([Log (write (k msg)
           (set! calls (append calls (list (string-append "outer:" msg))))
           (resume k (void)))])
    (with-fused-handlers
      ([Log (write (k msg)
             (set! calls (append calls (list (string-append "inner:" msg))))
             (resume k (void)))])
      (perform (Log write "x"))))
  (check "inner handler shadows outer" calls => '("inner:x")))

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
