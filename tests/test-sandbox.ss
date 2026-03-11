#!chezscheme
;;; Tests for (std capability sandbox) — Enhanced capability sandbox

(import (chezscheme) (std capability sandbox))

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

(define-syntax test-error
  (syntax-rules ()
    [(_ name expr)
     (guard (exn [#t (set! pass (+ pass 1)) (printf "  ok ~a~%" name)])
       expr
       (set! fail (+ fail 1))
       (printf "FAIL ~a: expected error but got none~%" name))]))

(printf "--- (std capability sandbox) tests ---~%~%")

;; ===== Policy =====

(printf "-- sandbox policy --~%")

(test "make-sandbox-policy creates policy"
  (sandbox-policy? (make-sandbox-policy))
  #t)

(test "sandbox-policy? false for vector"
  (sandbox-policy? (vector 'not-a-policy))
  #f)

(test "sandbox-policy? false for #f"
  (sandbox-policy? #f)
  #f)

(test "policy-allow! adds capability"
  (let ([p (make-sandbox-policy)])
    (policy-allow! p 'arithmetic)
    (memq 'arithmetic (policy-allowed p)))
  '(arithmetic))

(test "policy-deny! adds to denied"
  (let ([p (make-sandbox-policy)])
    (policy-deny! p 'network)
    (memq 'network (policy-denied p)))
  '(network))

(test "policy-allow-import! adds module"
  (let ([p (make-sandbox-policy)])
    (policy-allow-import! p 'chezscheme)
    (memq 'chezscheme (policy-allowed-imports p)))
  '(chezscheme))

(test "policy-deny-import! adds module to denied"
  (let ([p (make-sandbox-policy)])
    (policy-deny-import! p 'ffi)
    (memq 'ffi (policy-denied-imports p)))
  '(ffi))

(test "policy allows after policy-allow!"
  (let ([p (make-sandbox-policy)])
    (policy-allow! p 'arithmetic)
    (policy-allows? p 'arithmetic))
  #t)

(test "policy denies unknown capability"
  (policy-allows? (make-sandbox-policy) 'network)
  #f)

(test "denied takes precedence over allowed"
  (let ([p (make-sandbox-policy)])
    (policy-allow! p 'network)
    (policy-deny! p 'network)
    (policy-allows? p 'network))
  #f)

;; ===== Built-in Policies =====

(printf "~%-- built-in policies --~%")

(test "minimal-policy is sandbox-policy"
  (sandbox-policy? minimal-policy)
  #t)

(test "minimal-policy denies arithmetic by default"
  (policy-allows? minimal-policy 'arithmetic)
  #f)

(test "standard-policy is sandbox-policy"
  (sandbox-policy? standard-policy)
  #t)

(test "standard-policy allows arithmetic"
  (policy-allows? standard-policy 'arithmetic)
  #t)

(test "standard-policy allows string-ops"
  (policy-allows? standard-policy 'string-ops)
  #t)

(test "standard-policy denies network"
  (policy-allows? standard-policy 'network)
  #f)

(test "network-policy allows network"
  (policy-allows? network-policy 'network)
  #t)

(test "network-policy allows arithmetic"
  (policy-allows? network-policy 'arithmetic)
  #t)

(test "fs-policy allows filesystem"
  (policy-allows? fs-policy 'filesystem)
  #t)

(test "fs-policy denies network"
  (policy-allows? fs-policy 'network)
  #f)

;; ===== Sandbox Creation =====

(printf "~%-- sandbox creation --~%")

(test "make-sandbox creates sandbox"
  (sandbox? (make-sandbox standard-policy))
  #t)

(test "sandbox? false for #f"
  (sandbox? #f)
  #f)

(test "sandbox? false for policy"
  (sandbox? standard-policy)
  #f)

(test "sandbox-allowed? checks policy"
  (sandbox-allowed? (make-sandbox standard-policy) 'arithmetic)
  #t)

(test "sandbox-allowed? false for denied capability"
  (sandbox-allowed? (make-sandbox standard-policy) 'network)
  #f)

(test "sandbox-allowed? with custom policy"
  (let* ([p (make-sandbox-policy)]
         [_ (policy-allow! p 'custom-cap)]
         [sb (make-sandbox p)])
    (sandbox-allowed? sb 'custom-cap))
  #t)

;; ===== Sandbox Run =====

(printf "~%-- sandbox-run --~%")

(test "sandbox-run returns result"
  (sandbox-run standard-policy (lambda () (+ 1 2)))
  3)

(test "sandbox-run with list computation"
  (sandbox-run standard-policy (lambda () (map (lambda (x) (* x x)) '(1 2 3 4))))
  '(1 4 9 16))

(test "sandbox-run catches errors and returns condition"
  (condition? (sandbox-run standard-policy (lambda () (error 'test "boom"))))
  #t)

(test "sandbox-run error message preserved"
  (let ([err (sandbox-run standard-policy (lambda () (error 'test "expected error")))])
    (and (condition? err)
         (message-condition? err)
         (string=? (condition-message err) "expected error")))
  #t)

(test "sandbox-run with minimal-policy works for pure computation"
  (sandbox-run minimal-policy (lambda () (* 6 7)))
  42)

;; ===== Sandbox Eval =====

(printf "~%-- sandbox-eval --~%")

(test "sandbox-eval evaluates expression"
  (sandbox-eval (make-sandbox standard-policy) '(+ 1 2 3))
  6)

(test "sandbox-eval evaluates string operations"
  (sandbox-eval (make-sandbox standard-policy) '(string-append "hello" " " "world"))
  "hello world")

(test "sandbox-eval evaluates list ops"
  (sandbox-eval (make-sandbox standard-policy) '(length '(1 2 3 4 5)))
  5)

;; ===== Sandbox Violations =====

(printf "~%-- sandbox violations --~%")

(test "make-sandbox-violation creates condition"
  (sandbox-violation?
    (condition (make-sandbox-violation 'network 'test)
               (make-message-condition "denied")))
  #t)

(test "sandbox-violation-capability"
  (sandbox-violation-capability
    (condition (make-sandbox-violation 'filesystem 'sandbox-load)
               (make-message-condition "denied")))
  'filesystem)

(test "sandbox-violation-context"
  (sandbox-violation-context
    (condition (make-sandbox-violation 'network 'my-func)
               (make-message-condition "denied")))
  'my-func)

(test "sandbox-load raises violation for minimal policy"
  (sandbox-violation?
    (guard (e [#t e])
      (sandbox-load (make-sandbox minimal-policy) "/tmp/nonexistent.ss")))
  #t)

;; ===== with-sandbox macro =====

(printf "~%-- with-sandbox --~%")

(test "with-sandbox computes result"
  (with-sandbox standard-policy
    (+ 10 20))
  30)

(test "with-sandbox multiple expressions"
  (with-sandbox standard-policy
    (define x 5)
    (* x x))
  25)

(test "with-sandbox catches errors"
  (condition? (with-sandbox minimal-policy
    (error 'test "deliberate")))
  #t)

;; ===== sandbox-run/timeout =====

(printf "~%-- sandbox-run/timeout --~%")

(test "sandbox-run/timeout completes fast computation"
  (sandbox-run/timeout standard-policy (lambda () (* 6 7)) 5000)
  42)

(test "sandbox-run/timeout returns condition on error"
  (condition?
    (sandbox-run/timeout standard-policy
                         (lambda () (error 'test "deliberate"))
                         5000))
  #t)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
