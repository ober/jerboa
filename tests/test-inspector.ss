#!/usr/bin/env scheme-script
;;; Tests for Stack Frame Inspector (Phase 5c — Track 14.1)

(import (chezscheme) (std debug inspector))

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
;; 1. Frame records
;; --------------------------------------------------------------------------

(printf "~n--- Frame Records ---~n")

(let ([f (make-frame 'foo '((x . 1) (y . 2)))])
  (check-true "frame? yes"     (frame? f))
  (check      "frame? no"      (frame? 42) => #f)
  (check      "frame-name"     (frame-name f) => 'foo)
  (check      "frame-locals"   (frame-locals f) => '((x . 1) (y . 2))))

;; --------------------------------------------------------------------------
;; 2. Stack initially empty
;; --------------------------------------------------------------------------

(printf "~n--- Initial Stack ---~n")

(check "initial stack empty" (current-stack-frames) => '())

;; --------------------------------------------------------------------------
;; 3. with-tracked-call pushes frames
;; --------------------------------------------------------------------------

(printf "~n--- with-tracked-call ---~n")

(with-tracked-call 'outer '()
  (check "one frame in stack"
         (length (current-stack-frames))
         => 1)
  (check "frame name is outer"
         (frame-name (car (current-stack-frames)))
         => 'outer)
  (with-tracked-call 'inner '((a . 42))
    (check "two frames in stack"
           (length (current-stack-frames))
           => 2)
    (check "innermost frame name"
           (frame-name (car (current-stack-frames)))
           => 'inner)))

(check "stack empty after tracked calls" (current-stack-frames) => '())

;; --------------------------------------------------------------------------
;; 4. stack-trace produces a string
;; --------------------------------------------------------------------------

(printf "~n--- stack-trace ---~n")

(with-tracked-call 'alpha '()
  (with-tracked-call 'beta '((v . 99))
    (let ([trace (stack-trace)])
      (check-true "trace is string"   (string? trace))
      (check-true "trace mentions #0"
                  (let ([n "#0"] [nlen 2] [tlen (string-length trace)])
                    (let loop ([i 0])
                      (cond [(> (+ i nlen) tlen) #f]
                            [(string=? (substring trace i (+ i nlen)) n) #t]
                            [else (loop (+ i 1))]))))
      (check-true "trace mentions beta"
                  (let ([n "beta"] [nlen 4] [tlen (string-length trace)])
                    (let loop ([i 0])
                      (cond [(> (+ i nlen) tlen) #f]
                            [(string=? (substring trace i (+ i nlen)) n) #t]
                            [else (loop (+ i 1))])))))))

;; --------------------------------------------------------------------------
;; 5. call-with-inspector — exception path
;; --------------------------------------------------------------------------

(printf "~n--- call-with-inspector ---~n")

(let ([caught-exn #f]
      [caught-frames #f])
  (call-with-inspector
    (lambda ()
      (with-tracked-call 'boom '()
        (error 'test "oops")))
    (lambda (exn frames)
      (set! caught-exn exn)
      (set! caught-frames frames)))
  (check-true "exn captured"    (condition? caught-exn))
  (check-true "frames captured" (list? caught-frames)))

;; --------------------------------------------------------------------------
;; 6. with-stack-inspector macro
;; --------------------------------------------------------------------------

(printf "~n--- with-stack-inspector ---~n")

(let ([saw-exn #f])
  (with-stack-inspector
    ((e frames)
     (set! saw-exn #t))
    (with-tracked-call 'test-fn '()
      (error 'test "whoops")))
  (check-true "macro catches exception" saw-exn))

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
