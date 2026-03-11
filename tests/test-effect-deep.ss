#!chezscheme
;;; Tests for (std effect deep) — Deep algebraic effect handlers

(import (chezscheme) (std effect) (std effect deep))

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
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(printf "--- (std effect deep) tests ---~%")

;;;; Define effects for testing

(defeffect Ask
  (ask))

(defeffect Counter
  (tick))

(defeffect State
  (get)
  (put val))

(defeffect Choose
  (flip))

;;;; Test 1: Basic deep handler — handler persists across multiple resumes

(test "deep/basic persists across multiple performs"
  (let ([answer 42])
    (with-deep-handler ([Ask
                         (ask (k) (k answer))])
      ;; Perform the same effect twice — deep handler handles both
      (let ([a (Ask ask)]
            [b (Ask ask)])
        (+ a b))))
  84)

;;;; Test 2: Counter example — count how many times an effect is performed

(test "deep/counter counts multiple performs"
  (let ([count 0])
    (with-deep-handler ([Counter
                         (tick (k)
                           (set! count (+ count 1))
                           (k (void)))])
      (Counter tick)
      (Counter tick)
      (Counter tick)
      count))
  3)

;;;; Test 3: Deep handler vs shallow handler behavior

;; A shallow handler is consumed after first resume.
;; A deep handler persists — so we can call twice and both get handled.
(test "deep/persists where shallow would not"
  (let ([n 0])
    (with-deep-handler ([Counter
                         (tick (k)
                           (set! n (+ n 1))
                           (k (void)))])
      (Counter tick)
      (Counter tick)
      n))
  2)

;;;; Test 4: Nested deep handlers — inner handler takes priority

(defeffect Signal
  (send val))

(test "deep/nested inner wins"
  (with-deep-handler ([Signal
                       (send (k v) (k (+ v 1000)))])
    (with-deep-handler ([Signal
                         (send (k v) (k (* v 2)))])
      ;; Inner handler multiplies by 2, NOT the outer which adds 1000
      (Signal send 5)))
  10)

;;;; Test 5: Deep handler with return value propagation

(test "deep/return value propagation"
  (with-deep-handler ([Ask
                       (ask (k) (k "hello"))])
    (string-append (Ask ask) " " (Ask ask)))
  "hello hello")

;;;; Test 6: Handler that returns without resuming (abort)

(test "deep/handler returns without resuming"
  (call-with-current-continuation
    (lambda (escape)
      (with-deep-handler ([Signal
                           (send (k v) (escape (string-append "aborted:" (number->string v))))])
        (Signal send 99)
        "never-reached")))
  "aborted:99")

;;;; Test 7: Deep handler with multiple effect operations in same defeffect

(test "deep/multiple ops in same defeffect — get"
  (let ([st 10])
    (with-deep-handler ([State
                         (get (k) (k st))
                         (put (k v) (set! st v) (k (void)))])
      (State get)))
  10)

(test "deep/multiple ops in same defeffect — put then get"
  (let ([st 0])
    (with-deep-handler ([State
                         (get (k) (k st))
                         (put (k v) (set! st v) (k (void)))])
      (State put 77)
      (State get)))
  77)

;;;; Test 8: State effect with deep handler — get/put/get all handled

(test "deep/state get-put-get sequence"
  (let ([st 1])
    (with-deep-handler ([State
                         (get (k) (k st))
                         (put (k v) (set! st v) (k (void)))])
      (State put (+ (State get) 10))
      (State put (+ (State get) 5))
      (State get)))
  16)

;;;; Test 9: Exception in resumed computation still propagates

(test "deep/exception in resumed computation propagates"
  (guard (exn [(and (message-condition? exn)
                    (string=? (condition-message exn) "test error"))
               'caught-error])
    (with-deep-handler ([Ask
                         (ask (k) (k 42))])
      (let ([v (Ask ask)])
        (error 'test-fn "test error" v))
      'no-error))
  'caught-error)

;;;; Test 10: Deep handler composition — two effects both handled

(test "deep/composition of two effects"
  (let ([log '()] [st 0])
    (with-deep-handler ([State
                         (get (k) (k st))
                         (put (k v) (set! st v) (k (void)))]
                        [Signal
                         (send (k v)
                           (set! log (append log (list v)))
                           (k (void)))])
      (State put 5)
      (Signal send 'a)
      (State put (+ (State get) 3))
      (Signal send 'b)
      (list (State get) log)))
  '(8 (a b)))

;;;; Test 11: Deep handler preserves handler across multiple separate calls

(test "deep/handler active for all sub-calls"
  (let ([calls '()])
    (with-deep-handler ([Counter
                         (tick (k)
                           (set! calls (cons 'ticked calls))
                           (k (void)))])
      (define (do-n-ticks n)
        (when (> n 0)
          (Counter tick)
          (do-n-ticks (- n 1))))
      (do-n-ticks 4)
      (reverse calls)))
  '(ticked ticked ticked ticked))

;;;; Test 12: Deep handler resume value is used

(test "deep/resume value threaded through"
  (with-deep-handler ([Ask
                       (ask (k) (k 7))])
    (* (Ask ask) (Ask ask) (Ask ask)))
  343)

;;;; Test 13: Nested deep handlers — outer handles what inner doesn't

(defeffect Inner
  (inner-op))

(defeffect Outer
  (outer-op))

(test "deep/nested — each handler handles own effect"
  (with-deep-handler ([Outer
                       (outer-op (k) (k 'outer))])
    (with-deep-handler ([Inner
                         (inner-op (k) (k 'inner))])
      (list (Inner inner-op) (Outer outer-op) (Inner inner-op))))
  '(inner outer inner))

;;;; Test 14: Deep handler with stateful mutation inside handler

(test "deep/stateful mutation in handler accumulates"
  (let ([sum 0])
    (with-deep-handler ([Signal
                         (send (k v) (set! sum (+ sum v)) (k sum))])
      ;; Each resume returns cumulative sum
      (let* ([a (Signal send 1)]
             [b (Signal send 2)]
             [c (Signal send 3)])
        (list a b c))))
  '(1 3 6))

;;;; Test 15: Unhandled effect inside deep handler body still raises

(defeffect Unhandled2
  (boom2))

(test "deep/unhandled effect still raises"
  (guard (exn [(effect-not-handled? exn) 'caught])
    (with-deep-handler ([Ask
                         (ask (k) (k 1))])
      (Unhandled2 boom2)
      'missed))
  'caught)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
