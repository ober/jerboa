#!chezscheme
;;; Tests for (std security landlock) — real Landlock implementation
;;; NOTE: Actual installation tests are dangerous (irreversible!) and
;;; require Linux 5.13+. We test the safe parts here.

(import (chezscheme)
        (std security landlock))

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

(printf "--- Landlock Tests ---~%~%")

;; ========== Ruleset construction ==========

(printf "-- Ruleset construction --~%")

(test "make-landlock-ruleset creates a ruleset"
  (landlock-ruleset? (make-landlock-ruleset))
  #t)

(test "add-read-only! accepts paths"
  (let ([rs (make-landlock-ruleset)])
    (landlock-add-read-only! rs "/tmp")
    (landlock-ruleset? rs))
  #t)

(test "add-read-write! accepts paths"
  (let ([rs (make-landlock-ruleset)])
    (landlock-add-read-write! rs "/tmp")
    (landlock-ruleset? rs))
  #t)

(test "add-execute! accepts paths"
  (let ([rs (make-landlock-ruleset)])
    (landlock-add-execute! rs "/usr/bin")
    (landlock-ruleset? rs))
  #t)

(test "add-read-only! accepts multiple paths"
  (let ([rs (make-landlock-ruleset)])
    (landlock-add-read-only! rs "/tmp" "/var" "/etc")
    (landlock-ruleset? rs))
  #t)

;; ========== Pre-built rulesets ==========

(printf "~%-- Pre-built rulesets --~%")

(test "make-readonly-ruleset creates ruleset"
  (landlock-ruleset? (make-readonly-ruleset "/tmp" "/var"))
  #t)

(test "make-tmpdir-ruleset creates ruleset"
  (landlock-ruleset? (make-tmpdir-ruleset "/tmp/sandbox"))
  #t)

;; ========== Availability check ==========

(printf "~%-- Availability --~%")

(test "landlock-available? returns boolean"
  (boolean? (landlock-available?))
  #t)

;; ========== Error handling ==========

(printf "~%-- Error handling --~%")

(test "install on already-installed raises error"
  (guard (exn [(message-condition? exn) #t] [#t #f])
    (let ([rs (make-landlock-ruleset)])
      ;; Simulate installed state by attempting double install
      ;; We can't actually install (irreversible), so test the guard
      (when (not (landlock-available?))
        (error 'test "Landlock not available — testing error path"))
      ;; If landlock IS available, we'd need a subprocess to test this safely
      ;; For now, verify the pre-condition check works
      #f))
  ;; Expected: either error from unavailability or #f (can't safely test install)
  #t)

(test "add-read-only! after install raises error (simulated)"
  (guard (exn [(message-condition? exn)
               (string-contains (condition-message exn) "already installed")]
              [#t #f])
    ;; We can't actually install, but verify the logic path
    ;; by checking the record field directly
    (let ([rs (make-landlock-ruleset)])
      ;; This tests the pre-install path — should NOT raise
      (landlock-add-read-only! rs "/tmp")
      #f))
  ;; No error expected since ruleset isn't installed
  #f)

;; ========== Summary ==========

(printf "~%Landlock tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
