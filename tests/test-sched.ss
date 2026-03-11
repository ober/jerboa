#!chezscheme
(import (chezscheme) (std sched))

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

(printf "--- Phase 2d: M:N Scheduler ---~%~%")

;; Test 1: make-scheduler creates a scheduler
(test "make-scheduler default"
  (scheduler? (make-scheduler))
  #t)

;; Test 2: make-scheduler with explicit thread count
(test "make-scheduler with count"
  (scheduler? (make-scheduler 2))
  #t)

;; Test 3: scheduler-thread-count
(test "scheduler-thread-count"
  (scheduler-thread-count (make-scheduler 3))
  3)

;; Test 4: scheduler-running? before run
(test "scheduler-not-running-initially"
  (scheduler-running? (make-scheduler))
  #f)

;; Test 5: scheduler-run! starts workers
(let ([s (make-scheduler 2)])
  (scheduler-run! s)
  (test "scheduler-running-after-run"
    (scheduler-running? s)
    #t)
  (scheduler-stop! s))

;; Test 6: scheduler-task-count initially 0
(test "scheduler-task-count-initially-zero"
  (scheduler-task-count (make-scheduler))
  0)

;; Test 7: tasks execute via scheduler
(let ([s (make-scheduler 2)]
      [results (make-vector 3 #f)])
  (scheduler-run! s)
  (scheduler-spawn! s (lambda () (vector-set! results 0 'done-0)))
  (scheduler-spawn! s (lambda () (vector-set! results 1 'done-1)))
  (scheduler-spawn! s (lambda () (vector-set! results 2 'done-2)))
  ;; Wait for tasks to complete
  (sleep (make-time 'time-duration 200000000 0))
  (scheduler-stop! s)
  (test "tasks-executed-0" (vector-ref results 0) 'done-0)
  (test "tasks-executed-1" (vector-ref results 1) 'done-1)
  (test "tasks-executed-2" (vector-ref results 2) 'done-2))

;; Test 8: current-scheduler inside with-scheduler
(let ([s (make-scheduler 1)])
  (with-scheduler s
    (test "current-scheduler-in-with"
      (eq? (current-scheduler) s)
      #t)))

;; Test 9: scheduler-stop! makes running? false
(let ([s (make-scheduler 1)])
  (scheduler-run! s)
  (scheduler-stop! s)
  (test "scheduler-stopped"
    (scheduler-running? s)
    #f))

;; Test 10: tasks that raise errors don't crash scheduler
(let ([s (make-scheduler 1)]
      [counter (make-vector 1 0)])
  (scheduler-run! s)
  (scheduler-spawn! s (lambda () (error 'test "deliberate error")))
  (scheduler-spawn! s (lambda ()
    (vector-set! counter 0 (+ (vector-ref counter 0) 1))))
  (sleep (make-time 'time-duration 150000000 0))
  (scheduler-stop! s)
  (test "scheduler-survives-error"
    (vector-ref counter 0)
    1))

;; Test 11: multiple spawn after run
(let ([s (make-scheduler 2)]
      [done (make-vector 1 0)]
      [m (make-mutex)])
  (scheduler-run! s)
  (let loop ([i 0])
    (when (< i 5)
      (scheduler-spawn! s
        (lambda ()
          (mutex-acquire m)
          (vector-set! done 0 (+ (vector-ref done 0) 1))
          (mutex-release m)))
      (loop (+ i 1))))
  (sleep (make-time 'time-duration 200000000 0))
  (scheduler-stop! s)
  (test "multiple-tasks-all-run"
    (vector-ref done 0)
    5))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
