#!/usr/bin/env scheme-script
;;; Tests for Closure Inspection (Phase 5c — Track 14.2)

(import (chezscheme) (std debug closure-inspect))

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
;; 1. Construction and type predicates
;; --------------------------------------------------------------------------

(printf "~n--- Construction ---~n")

(let ([tc (make-tracked-closure '((x . 1) (y . 2)) (lambda (z) z))])
  (check-true "tracked-closure? yes" (tracked-closure? tc))
  (check      "not tracked-closure?" (tracked-closure? 42) => #f)
  (check      "closure-arity result" (closure-min-arity tc) => 1))

;; --------------------------------------------------------------------------
;; 2. Free variable access
;; --------------------------------------------------------------------------

(printf "~n--- Free Variable Access ---~n")

(let ([tc (make-tracked-closure '((a . 10) (b . 20) (c . 30)) (lambda () 'dummy))])
  (check "free-vars list"
         (map car (closure-free-variables tc))
         => '(a b c))
  (check "free-var a value"
         (cdr (assq 'a (closure-free-variables tc)))
         => 10))

;; --------------------------------------------------------------------------
;; 3. Mutation of free variables
;; --------------------------------------------------------------------------

(printf "~n--- Mutation ---~n")

(let ([tc (make-tracked-closure '((x . 5)) (lambda () 'dummy))])
  (closure-set-free-variable! tc 'x 99)
  (check "after set! x"
         (cdr (assq 'x (closure-free-variables tc)))
         => 99))

;; --------------------------------------------------------------------------
;; 4. closure-with — create updated copy
;; --------------------------------------------------------------------------

(printf "~n--- closure-with ---~n")

(let* ([tc1 (make-tracked-closure '((n . 1)) (lambda () 'dummy))]
       [tc2 (closure-with tc1 '((n . 42) (m . 7)))])
  (check "tc2 n updated"
         (cdr (assq 'n (closure-free-variables tc2)))
         => 42)
  (check "tc2 m added"
         (cdr (assq 'm (closure-free-variables tc2)))
         => 7)
  (check "tc1 n unchanged"
         (cdr (assq 'n (closure-free-variables tc1)))
         => 1))

;; --------------------------------------------------------------------------
;; 5. Arity introspection
;; --------------------------------------------------------------------------

(printf "~n--- Arity ---~n")

(let ([tc0 (make-tracked-closure '() (lambda () 42))]
      [tc2 (make-tracked-closure '() (lambda (a b) (+ a b)))]
      [tc+ (make-tracked-closure '() (lambda args (length args)))])
  (check "min-arity 0"   (closure-min-arity tc0) => 0)
  (check "min-arity 2"   (closure-min-arity tc2) => 2)
  (check "max-arity var" (closure-max-arity tc+) => #f))

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
