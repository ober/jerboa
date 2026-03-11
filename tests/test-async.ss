#!chezscheme
;;; Tests for (std async) — Async I/O runtime

(import (chezscheme) (std async) (std misc channel))

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

(printf "--- (std async) tests ---~%")

;;; Test 1: run-async with a simple value
(test "run-async simple"
  (run-async (lambda () 42))
  42)

;;; Test 2: run-async with spawn
(test "run-async spawn"
  (run-async
    (lambda ()
      (let ([result #f])
        ;; Spawn a task that sets result
        (Async spawn (lambda () (set! result 'done)))
        ;; Give spawned task time to run (sleep briefly)
        (async-sleep 10)
        result)))
  'done)

;;; Test 3: async-task returns a promise
(test "async-task/promise"
  (run-async
    (lambda ()
      (let ([p (async-task (lambda () (+ 1 2)))])
        ;; Wait for the task to complete
        (async-sleep 20)
        (if (async-promise-resolved? p)
          (async-promise-value p)
          'not-resolved))))
  3)

;;; Test 4: promises resolve correctly
(test "promise/resolve"
  (let ([p (make-async-promise)])
    (async-promise-resolve! p 99)
    (and (async-promise-resolved? p)
         (async-promise-value p)))
  99)

;;; Test 5: promise can only be resolved once
(test "promise/resolve-once"
  (let ([p (make-async-promise)])
    (async-promise-resolve! p 'first)
    (async-promise-resolve! p 'second)  ;; should be ignored
    (async-promise-value p))
  'first)

;;; Test 6: Async await on pre-resolved promise
(test "await/pre-resolved"
  (run-async
    (lambda ()
      (let ([p (make-async-promise)])
        (async-promise-resolve! p 'ready)
        (Async await p))))
  'ready)

;;; Test 7: async sleep
(test "async-sleep"
  (run-async
    (lambda ()
      (let ([t0 (current-time 'time-monotonic)])
        (async-sleep 50)
        (let ([t1 (current-time 'time-monotonic)])
          ;; Should have slept at least ~50ms
          (let ([elapsed-ms
                 (+ (* 1000 (- (time-second t1) (time-second t0)))
                    (quotient (- (time-nanosecond t1) (time-nanosecond t0)) 1000000))])
            (>= elapsed-ms 40))))))  ;; allow some slack
  #t)

;;; Test 8: async channels — basic get/put
(test "async-channel/basic"
  (run-async
    (lambda ()
      (let ([ch (make-channel)])
        (Async spawn (lambda () (async-channel-put ch 'hello)))
        (async-sleep 20)
        (let-values ([(v ok) (channel-try-get ch)])
          (if ok v 'empty)))))
  'hello)

;;; Test 9: multiple spawned tasks
(test "async/multiple-tasks"
  (run-async
    (lambda ()
      (let ([results (make-channel)])
        (Async spawn (lambda () (async-channel-put results 1)))
        (Async spawn (lambda () (async-channel-put results 2)))
        (Async spawn (lambda () (async-channel-put results 3)))
        (async-sleep 50)
        (let ([got '()])
          (let loop ()
            (let-values ([(v ok) (channel-try-get results)])
              (when ok
                (set! got (cons v got))
                (loop))))
          (length got)))))
  3)

;;; Test 10: run-async/workers
(test "run-async/workers"
  (run-async/workers
    (lambda ()
      (let ([p (async-task (lambda () (* 6 7)))])
        (async-sleep 30)
        (if (async-promise-resolved? p)
          (async-promise-value p)
          'timeout)))
    2)
  42)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
