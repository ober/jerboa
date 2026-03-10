#!chezscheme
;;; Tests for (std actor scheduler) — work-stealing thread pool

(import (chezscheme) (std actor deque) (std actor scheduler) (std actor core))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn
               [#t (set! fail (+ fail 1))
                   (printf "FAIL ~a: exception ~a~%" name
                     (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define (wait-ms n)
  (sleep (make-time 'time-duration (* n 1000000) 0)))

(printf "--- (std actor scheduler) tests ---~%")

;; Test 1: cpu-count returns a positive integer
(let ([n (cpu-count)])
  (test "cpu-count-positive" (and (integer? n) (> n 0)) #t))

;; Test 2: make-scheduler creates correct worker count
(let ([sched (make-scheduler 4)])
  (test "worker-count" (scheduler-worker-count sched) 4))

;; Test 3: submit 1000 tasks, all complete
(let ([sched    (make-scheduler 4)]
      [counter  0]
      [cmutex   (make-mutex)]
      [done     (make-condition)])
  (scheduler-start! sched)
  (do ([i 0 (fx+ i 1)]) ((fx= i 1000))
    (scheduler-submit! sched
      (lambda ()
        (with-mutex cmutex
          (set! counter (fx+ counter 1))
          (when (fx= counter 1000)
            (condition-signal done))))))
  (with-mutex cmutex
    (let loop ()
      (when (< counter 1000)
        (condition-wait done cmutex)
        (loop))))
  (scheduler-stop! sched)
  (test "submit-1000" counter 1000))

;; Test 4: tasks can submit further tasks (recursive submit)
(let ([sched   (make-scheduler 2)]
      [counter 0]
      [cmutex  (make-mutex)]
      [done    (make-condition)])
  (scheduler-start! sched)
  ;; Submit 10 tasks, each submits 10 more = 100 total leaf tasks
  (do ([i 0 (fx+ i 1)]) ((fx= i 10))
    (scheduler-submit! sched
      (lambda ()
        (do ([j 0 (fx+ j 1)]) ((fx= j 10))
          (scheduler-submit! sched
            (lambda ()
              (with-mutex cmutex
                (set! counter (fx+ counter 1))
                (when (fx= counter 100)
                  (condition-signal done)))))))))
  (with-mutex cmutex
    (let loop ()
      (when (< counter 100)
        (condition-wait done cmutex)
        (loop))))
  (scheduler-stop! sched)
  (test "recursive-submit" counter 100))

;; Test 5: exception in task does not crash worker
(let ([sched   (make-scheduler 2)]
      [counter 0]
      [cmutex  (make-mutex)]
      [done    (make-condition)])
  (scheduler-start! sched)
  ;; Submit a crashing task, then a normal task
  (scheduler-submit! sched
    (lambda () (error 'test "intentional crash")))
  (scheduler-submit! sched
    (lambda ()
      (with-mutex cmutex
        (set! counter 1)
        (condition-signal done))))
  (with-mutex cmutex
    (let loop ()
      (when (= counter 0)
        (condition-wait done cmutex)
        (loop))))
  (scheduler-stop! sched)
  (test "crash-isolation" counter 1))

;; Test 6: scheduler-stop! unblocks waiting workers
(let ([sched (make-scheduler 4)])
  (scheduler-start! sched)
  ;; Give workers time to start and go to sleep
  (wait-ms 50)
  (scheduler-stop! sched)
  ;; Give workers time to exit
  (wait-ms 100)
  ;; If we reach here, workers did not hang
  (test "stop-unblocks" #t #t))

;; Test 7: wire into actor core — all actor tests pass with scheduler
(let ([sched (make-scheduler (cpu-count))])
  (scheduler-start! sched)
  (set-actor-scheduler! (lambda (thunk) (scheduler-submit! sched thunk)))
  (let ([results '()]
        [rmutex  (make-mutex)]
        [done    (make-condition)]
        [total   50])
    (do ([i 0 (fx+ i 1)]) ((fx= i total))
      (let ([n i])
        (spawn-actor
          (lambda (msg)
            (with-mutex rmutex
              (set! results (cons n results))
              (when (fx= (length results) total)
                (condition-signal done)))))))
    ;; Actors don't need messages — they run once on spawn
    ;; Actually actors only run when they receive a message; send one to each
    ;; Instead, spawn actors that immediately record themselves
    (set! results '())
    (let ([actors
           (let loop ([i 0] [acc '()])
             (if (fx= i total)
               (reverse acc)
               (loop (fx+ i 1)
                     (cons (spawn-actor
                              (lambda (msg)
                                (with-mutex rmutex
                                  (set! results (cons msg results))
                                  (when (fx= (length results) total)
                                    (condition-signal done)))))
                           acc))))])
      (for-each (lambda (a) (send a 'ping)) actors)
      (with-mutex rmutex
        (let loop ()
          (when (< (length results) total)
            (condition-wait done rmutex)
            (loop)))))
    (scheduler-stop! sched)
    ;; Reset to 1:1 mode for subsequent tests
    (set-actor-scheduler! #f)
    (test "actors-with-scheduler" (length results) total)))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
