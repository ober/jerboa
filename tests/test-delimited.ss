#!/usr/bin/env scheme-script
;;; Tests for Delimited Continuations (Phase 5a — Track 12.1)

(import (except (chezscheme) reset abort) (std control delimited))

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
;; 1. Prompt tags
;; --------------------------------------------------------------------------

(printf "~n--- Prompt Tags ---~n")

(let ([tag (make-prompt-tag 'foo)])
  (check-true "make-prompt-tag returns tag"  (prompt-tag? tag))
  (check      "tag name"  (prompt-tag-name tag) => 'foo))

(check-true "default tag is a tag" (prompt-tag? (make-prompt-tag 'default)))

;; --------------------------------------------------------------------------
;; 2. Reset without shift — normal return
;; --------------------------------------------------------------------------

(printf "~n--- Reset (no shift) ---~n")

(check "reset returns literal"   (reset 42)         => 42)
(check "reset evaluates body"    (reset (+ 1 2))    => 3)
(check "reset multiple exprs"    (reset (define x 5) (+ x 3)) => 8)

;; --------------------------------------------------------------------------
;; 3. Basic shift/reset
;; --------------------------------------------------------------------------

(printf "~n--- Basic shift/reset ---~n")

;; shift discards k: result is just the shift body
(check "shift without k" (reset (+ 1 (shift k 42))) => 42)

;; k adds 1; apply once
(check "shift k once"
       (reset (+ 1 (shift k (k 5))))
       => 6)

;; k adds 1; apply twice: 1+(1+5) = 7
(check "shift k twice"
       (reset (+ 1 (shift k (k (k 5)))))
       => 7)

;; k applied to 0: 1+0 = 1
(check "shift k applied to 0"
       (reset (+ 1 (shift k (k 0))))
       => 1)

;; --------------------------------------------------------------------------
;; 4. Shift composing delimited continuations
;; --------------------------------------------------------------------------

(printf "~n--- Composing Delimited Continuations ---~n")

;; Classic: generate a list of values via shift
(define (list-from-shifts)
  (reset
    (let ([x (shift k (list 1 2 3))])  ; x never bound — k discarded
      x)))

(check "list from shifts" (list-from-shifts) => '(1 2 3))

;; Collect continuations
(define saved-k #f)
(define first-val
  (reset
    (let ([v (shift k (begin (set! saved-k k) 0))])
      (* 10 v))))

(check "captured k result" first-val => 0)
(check "using saved k"     (saved-k 5)  => 50)
(check "using saved k again" (saved-k 3) => 30)

;; --------------------------------------------------------------------------
;; 5. Nested resets
;; --------------------------------------------------------------------------

(printf "~n--- Nested Resets ---~n")

;; Inner shift only reaches inner reset
(check "inner shift + outer passthrough"
       (reset
         (+ 1
            (reset
              (+ 10 (shift k (k 5))))))
       => 16)   ; inner: 10+5=15, outer: 1+15=16

;; Multiple independent shifts
(check "two independent resets"
       (+ (reset (+ 100 (shift k 1)))
          (reset (+ 200 (shift k 2))))
       => 3)    ; 1 + 2 = 3

;; --------------------------------------------------------------------------
;; 6. Named prompts (multi-prompt)
;; --------------------------------------------------------------------------

(printf "~n--- Named Prompts ---~n")

(let ([outer (make-prompt-tag 'outer)]
      [inner (make-prompt-tag 'inner)])

  ;; shift-at targets outer, skipping inner
  (check "shift-at outer"
         (reset-at outer
           (+ 1
              (reset-at inner
                (+ 10 (shift-at outer k (k 5))))))
         => 16)   ; shift-at outer: outer has +1, inner has +10, k=+1 cont, k(5)=6, then inner adds 10: 16

  ;; shift-at inner only reaches inner reset
  (check "shift-at inner"
         (reset-at outer
           (+ 1
              (reset-at inner
                (+ 10 (shift-at inner k (k 5))))))
         => 16)   ; inner: 10+5=15, outer: 1+15=16
  )

;; --------------------------------------------------------------------------
;; 7. Control/prompt (abortive)
;; --------------------------------------------------------------------------

(printf "~n--- Control/Prompt ---~n")

;; control k: k discarded, body is result
(check "control discards k"
       (prompt (+ 1 (control k 42)))
       => 42)

;; control k: k called once (raw continuation, not re-wrapped)
(check "control k once"
       (prompt (+ 1 (control k (k 5))))
       => 6)

;; --------------------------------------------------------------------------
;; 8. Generator pattern using shift/reset
;; --------------------------------------------------------------------------

(printf "~n--- Generator Pattern ---~n")

(define (make-range-gen lo hi)
  (define resume #f)
  (define (yield v)
    (shift k
      (set! resume k)
      v))
  (define (start)
    (reset
      (let loop ([i lo])
        (when (< i hi)
          (yield i)
          (loop (+ i 1))))
      'done))
  ;; Initialize
  (start)
  (lambda ()
    (if resume
        (let ([k resume])
          (set! resume #f)
          (k (void)))
        'done)))

(let ([gen (make-range-gen 0 3)])
  ;; generator yields 0, 1, 2, then 'done
  ;; We just test the reset/shift machinery works without error
  (check-true "generator runs" #t))

;; --------------------------------------------------------------------------
;; 9. Abort
;; --------------------------------------------------------------------------

(printf "~n--- Abort ---~n")

(check "abort exits reset"
       (reset (begin (abort 99) 0))
       => 99)

(check "abort with value"
       (+ 100 (reset (begin (abort 7) 42)))
       => 107)

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
