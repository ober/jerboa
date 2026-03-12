#!/usr/bin/env scheme-script
;;; Tests for Profile-Guided Optimization (Phase 5a — Track 11.3)

(import (chezscheme) (std compiler pgo))

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

(define-syntax check-true  (syntax-rules () [(_ n e) (check n e => #t)]))
(define-syntax check-false (syntax-rules () [(_ n e) (check n e => #f)]))

(printf "~n--- Basic State ---~n")

(check-false "profiling initially off"   (profile-running?))
(check       "initial count is zero"     (profile-call-count 'nonexistent) => 0)

(printf "~n--- define/profile ---~n")

(define/profile (add a b) (+ a b))
(define/profile (mul a b) (* a b))

(check "define/profile result unchanged" (add 3 4) => 7)
(check "count 0 before profiling"        (profile-call-count 'add) => 0)

(printf "~n--- with-profiling ---~n")

(check-false "off before block" (profile-running?))

(with-profiling
  (add 1 2)
  (add 3 4)
  (mul 5 6))

(check-false "off after block"  (profile-running?))
(check "add called 2 times"     (profile-call-count 'add) => 2)
(check "mul called 1 time"      (profile-call-count 'mul) => 1)

(printf "~n--- Manual Enable/Disable ---~n")

(profiling-enable!)
(check-true "enabled" (profile-running?))
(add 10 20)
(profiling-disable!)
(check-false "disabled" (profile-running?))

(check "add now 3 (2+1)" (profile-call-count 'add) => 3)

(printf "~n--- profile-reset! ---~n")

(profile-reset!)
(check "add reset to 0" (profile-call-count 'add) => 0)
(check "mul reset to 0" (profile-call-count 'mul) => 0)

(printf "~n--- profile-data / hot-functions ---~n")

(with-profiling
  (add 1 2) (add 3 4) (add 5 6)
  (mul 1 2))

(let ([data (profile-data)])
  (check-true "profile-data is list"  (list? data))
  (check      "has 2 entries"  (length data) => 2))

(let ([hot (profile-hot-functions 2)])
  (check-true "returns list"        (list? hot))
  (check      "top entry is add"    (caar hot) => 'add))

(let ([hot1 (profile-hot-functions 1)])
  (check "top-1 has 1 entry" (length hot1) => 1))

(printf "~n--- profile-guided-inline? ---~n")

(check-true  "inline add (>=3)"  (profile-guided-inline? 'add 3))
(check-false "no inline add (>10)" (profile-guided-inline? 'add 10))
(check-false "no inline unknown"   (profile-guided-inline? 'unknown 1))

(printf "~n--- Save and Load ---~n")

(let ([tmpfile "/tmp/test-pgo-phase5a.prof"])
  (profile-save tmpfile)
  (check-true "file exists" (file-exists? tmpfile))
  (let ([loaded (profile-load tmpfile)])
    (check-true "loaded is list"     (list? loaded))
    (check-true "non-empty"          (not (null? loaded))))
  (profile-reset!)
  (profile-load! tmpfile)
  (check "add restored" (profile-call-count 'add) => 3)
  (check "mul restored" (profile-call-count 'mul) => 1)
  (delete-file tmpfile))

(printf "~n--- define-pgo-module ---~n")

(define-pgo-module (my-module core)
  (define/profile (triple x) (* x 3)))

(with-profiling (triple 7))
(check "pgo function works"   (triple 5) => 15)
(check "pgo function counted" (profile-call-count 'triple) => 1)

(printf "~n===========================================~n")
(printf "Tests: ~a  |  Passed: ~a  |  Failed: ~a~n"
        test-count pass-count fail-count)
(printf "===========================================~n")
(when (> fail-count 0)
  (printf "~nFAILED~n")
  (exit 1))
(printf "~nAll tests passed!~n")
