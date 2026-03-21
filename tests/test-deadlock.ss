#!chezscheme
;;; Tests for (std concur deadlock) — runtime deadlock detection

(import (chezscheme)
        (std concur deadlock))

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

(printf "--- Deadlock Detection Tests ---~%~%")

;; ========== Basic API ==========

(printf "-- Basic API --~%")

(test "*deadlock-detection-enabled* defaults to #t"
  (*deadlock-detection-enabled*)
  #t)

(test "no deadlock on clean state"
  (deadlock?)
  #f)

(test "detect-deadlock returns #f on clean state"
  (detect-deadlock)
  #f)

;; ========== Wait-for graph management ==========

(printf "~%-- Wait-for graph --~%")

(test "register and unregister waiting"
  (begin
    (register-waiting! 'thread-1 'resource-A)
    (unregister-waiting! 'thread-1)
    (deadlock?))
  #f)

(test "holding and releasing"
  (begin
    (holding-resource! 'thread-1 'resource-A)
    (releasing-resource! 'thread-1 'resource-A)
    (deadlock?))
  #f)

;; ========== Deadlock detection ==========

(printf "~%-- Cycle detection --~%")

(test "detect simple deadlock cycle"
  (begin
    ;; Thread 1 holds A, waits for B
    (holding-resource! 'thread-1 'resource-A)
    (register-waiting! 'thread-1 'resource-B)
    ;; Thread 2 holds B, waits for A
    (holding-resource! 'thread-2 'resource-B)
    (register-waiting! 'thread-2 'resource-A)
    ;; Should detect cycle
    (let ([result (deadlock?)])
      ;; Clean up
      (unregister-waiting! 'thread-1)
      (unregister-waiting! 'thread-2)
      (releasing-resource! 'thread-1 'resource-A)
      (releasing-resource! 'thread-2 'resource-B)
      result))
  #t)

(test "no false positive for chain without cycle"
  (begin
    ;; Thread 3 holds C, thread 4 waits for C — no cycle
    (holding-resource! 'thread-3 'resource-C)
    (register-waiting! 'thread-4 'resource-C)
    (let ([result (deadlock?)])
      (unregister-waiting! 'thread-4)
      (releasing-resource! 'thread-3 'resource-C)
      result))
  #f)

;; ========== Deadlock condition ==========

(printf "~%-- Deadlock condition type --~%")

(test "make-deadlock-condition creates condition"
  (deadlock-condition? (make-deadlock-condition '(a b a)))
  #t)

(test "deadlock-condition-cycle returns cycle"
  (deadlock-condition-cycle (make-deadlock-condition '(1 2 1)))
  '(1 2 1))

;; ========== Instrumented mutex ==========

(printf "~%-- Instrumented mutex --~%")

(test "deadlock-checked-mutex-lock! and unlock! work"
  (let ([m (make-mutex)])
    (deadlock-checked-mutex-lock! m)
    (deadlock-checked-mutex-unlock! m)
    #t)
  #t)

;; ========== Drop-in replacements ==========

(printf "~%-- Drop-in replacements --~%")

(test "make-checked-mutex creates a usable mutex"
  (let ([m (make-checked-mutex "test-mutex")])
    (mutex? m))
  #t)

(test "with-checked-mutex executes body"
  (let ([m (make-checked-mutex "test-wc")])
    (with-checked-mutex m
      42))
  42)

(test "with-checked-mutex handles exceptions"
  (guard (exn [#t #t])
    (let ([m (make-checked-mutex "test-exc")])
      (with-checked-mutex m
        (error 'test "intentional")))
    #f)
  #t)

;; ========== Report ==========

(printf "~%-- Report --~%")

(test "deadlock-detection-report returns string"
  (string? (deadlock-detection-report))
  #t)

;; ========== Summary ==========

(printf "~%Deadlock detection tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
