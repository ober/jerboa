#!chezscheme
;;; Tests for (std task) — Structured concurrency

(import (chezscheme) (std task))

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
           (begin (set! pass (+ pass 1))
                  (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~a, expected ~a~%" name got expected)))))]))

(printf "--- (std task) tests ---~%")

;; Test 1: Cancel token
(let ([tok (make-cancel-token)])
  (test "token not cancelled" (cancelled? tok) #f)
  (cancel! tok)
  (test "token cancelled" (cancelled? tok) #t))

;; Test 2: Future
(let ([fut (make-future)])
  (test "future not done" (future-done? fut) #f)
  (fork-thread (lambda ()
    (sleep (make-time 'time-duration 10000000 0))
    (future-complete! fut 42)))
  (test "future-get blocks" (future-get fut) 42)
  (test "future done" (future-done? fut) #t))

;; Test 3: Basic task group — all tasks complete
(let ([results (make-vector 3 #f)])
  (with-task-group
    (lambda (tg)
      (task-group-spawn tg (lambda () (vector-set! results 0 'a)))
      (task-group-spawn tg (lambda () (vector-set! results 1 'b)))
      (task-group-spawn tg (lambda () (vector-set! results 2 'c)))))
  (test "task-group all complete 0" (vector-ref results 0) 'a)
  (test "task-group all complete 1" (vector-ref results 1) 'b)
  (test "task-group all complete 2" (vector-ref results 2) 'c))

;; Test 4: task-group-async returns futures
(let-values ([(r1 r2)
              (with-task-group
                (lambda (tg)
                  (let ([f1 (task-group-async tg (lambda () (* 6 7)))]
                        [f2 (task-group-async tg (lambda () (+ 10 20)))])
                    (values (future-get f1) (future-get f2)))))])
  (test "async result 1" r1 42)
  (test "async result 2" r2 30))

;; Test 5: Task exception propagates
(test "task exception propagates"
  (guard (exn [#t (and (message-condition? exn)
                       (string=? (condition-message exn) "boom"))])
    (with-task-group
      (lambda (tg)
        (task-group-spawn tg (lambda () (error 'test "boom")))
        (task-group-spawn tg (lambda ()
          (sleep (make-time 'time-duration 100000000 0))
          'ok)))))
  #t)

;; Test 6: Task group cancellation
(let ([tok-captured #f])
  (with-task-group
    (lambda (tg)
      (set! tok-captured (task-group-cancel-tok tg))
      (task-group-cancel! tg)))
  (test "cancel token from group" (cancelled? tok-captured) #t))

;; Test 7: Empty task group — returns body's value
(test "empty task group"
  (with-task-group (lambda (tg) 'done))
  'done)

;; Actually with-task-group doesn't return a value explicitly, let's check it doesn't error
(test "empty task group no error"
  (guard (exn [#t #f])
    (with-task-group (lambda (tg) 'ok))
    #t)
  #t)

;; Test 8: Many concurrent tasks
(let ([counter 0]
      [mx (make-mutex)])
  (with-task-group
    (lambda (tg)
      (do ([i 0 (+ i 1)]) ((= i 100))
        (task-group-spawn tg
          (lambda ()
            (with-mutex mx
              (set! counter (+ counter 1))))))))
  (test "100 concurrent tasks" counter 100))

(printf "~%~a tests, ~a passed, ~a failed~%" (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
