#!chezscheme
;;; Tests for (std actor supervisor) — OTP supervision trees

(import (chezscheme) (jerboa core)
        (std actor core) (std actor protocol) (std actor supervisor))

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

(printf "--- (std actor supervisor) tests ---~%")

;; Test 1: start-supervisor starts all children
(let ([sup (start-supervisor
              'one-for-one
              (list
                (make-child-spec 'a (lambda () (spawn-actor (lambda (msg) (void)))) 'permanent 1.0 'worker)
                (make-child-spec 'b (lambda () (spawn-actor (lambda (msg) (void)))) 'permanent 1.0 'worker))
              10 5)])
  (wait-ms 50)
  (let ([children (supervisor-which-children sup)])
    (test "start-count"   (length children) 2)
    (test "start-status-a" (cadr (assq 'a children)) 'running)
    (test "start-status-b" (cadr (assq 'b children)) 'running))
  (actor-kill! sup))

;; Helper: look up actor-ref for a named child
(define (child-ref sup name)
  (caddr (assq name (supervisor-which-children sup))))

;; Test 2: one-for-one — only crashed child is restarted
(let ([started-a 0] [started-b 0])
  (let ([sup (start-supervisor
                'one-for-one
                (list
                  (make-child-spec 'a
                    (lambda ()
                      (set! started-a (+ started-a 1))
                      (spawn-actor (lambda (msg) (match msg ['crash (error 'a "crash")]))))
                    'permanent 1.0 'worker)
                  (make-child-spec 'b
                    (lambda ()
                      (set! started-b (+ started-b 1))
                      (spawn-actor (lambda (msg) (void))))
                    'permanent 1.0 'worker))
                10 5)])
    (wait-ms 50)
    (test "one-for-one-initial-a" started-a 1)
    (test "one-for-one-initial-b" started-b 1)
    ;; Crash child a
    (send (child-ref sup 'a) 'crash)
    (wait-ms 150)  ;; wait for restart
    (test "one-for-one-restarted-a"  started-a 2)
    (test "one-for-one-b-untouched"  started-b 1)
    (actor-kill! sup)))

;; Test 3: one-for-all — all children restarted when one crashes
;; Use brutal-kill shutdown so restart-all! doesn't wait on graceful timeout.
(let ([started-a 0] [started-b 0])
  (let ([sup (start-supervisor
                'one-for-all
                (list
                  (make-child-spec 'a
                    (lambda ()
                      (set! started-a (+ started-a 1))
                      (spawn-actor (lambda (msg) (match msg ['crash (error 'a "crash")]))))
                    'permanent 'brutal-kill 'worker)
                  (make-child-spec 'b
                    (lambda ()
                      (set! started-b (+ started-b 1))
                      (spawn-actor (lambda (msg) (void))))
                    'permanent 'brutal-kill 'worker))
                10 5)])
    (wait-ms 50)
    (send (child-ref sup 'a) 'crash)
    (wait-ms 300)
    (test "one-for-all-restarted-a" started-a 2)
    (test "one-for-all-restarted-b" started-b 2)
    (actor-kill! sup)))

;; Test 4: permanent — always restarts (even on kill)
(let ([started 0])
  (let ([sup (start-supervisor
                'one-for-one
                (list (make-child-spec 'w
                        (lambda ()
                          (set! started (+ started 1))
                          (spawn-actor (lambda (msg) (void))))
                        'permanent 'brutal-kill 'worker))
                10 5)])
    (wait-ms 50)
    (actor-kill! (child-ref sup 'w))
    (wait-ms 150)
    (test "permanent-restart" started 2)
    (actor-kill! sup)))

;; Test 5: temporary — never restarts
(let ([started 0])
  (let ([sup (start-supervisor
                'one-for-one
                (list (make-child-spec 'w
                        (lambda ()
                          (set! started (+ started 1))
                          (spawn-actor (lambda (msg) (error 'w "crash"))))
                        'temporary 'brutal-kill 'worker))
                10 5)])
    (wait-ms 50)
    (send (child-ref sup 'w) 'go)
    (wait-ms 150)
    (test "temporary-no-restart" started 1)
    (actor-kill! sup)))

;; Test 6: transient — restarts on crash but not on kill
(let ([started 0])
  (let ([sup (start-supervisor
                'one-for-one
                (list (make-child-spec 'w
                        (lambda ()
                          (set! started (+ started 1))
                          (spawn-actor (lambda (msg) (error 'w "crash"))))
                        'transient 'brutal-kill 'worker))
                10 5)])
    (wait-ms 50)
    ;; Crash it (error = abnormal exit) — should restart
    (send (child-ref sup 'w) 'go)
    (wait-ms 150)
    (test "transient-crash-restart" started 2)
    ;; Kill it (killed = normal-ish) — should NOT restart
    (actor-kill! (child-ref sup 'w))
    (wait-ms 150)
    (test "transient-kill-no-restart" started 2)
    (actor-kill! sup)))

;; Test 7: dynamic child management
(let ([sup (start-supervisor 'one-for-one '() 10 5)])
  (wait-ms 20)
  (let ([new-ref (supervisor-start-child! sup
                   (make-child-spec 'dyn
                     (lambda () (spawn-actor (lambda (msg) (void))))
                     'permanent 1.0 'worker))])
    (test "dynamic-start" (actor-ref? new-ref) #t)
    (supervisor-terminate-child! sup 'dyn)
    (wait-ms 50)
    (let ([ch (supervisor-which-children sup)])
      (test "dynamic-terminate-status"
            (cadr (assq 'dyn ch))
            'stopped))
    (supervisor-delete-child! sup 'dyn)
    (wait-ms 20)
    (test "dynamic-delete" (length (supervisor-which-children sup)) 0))
  (actor-kill! sup))

;; Test 8: restart intensity — supervisor dies after too many restarts
;; max-restarts=2 within period=1s means the 3rd restart in 1s kills the supervisor.
(let ([sup (start-supervisor
              'one-for-one
              (list (make-child-spec 'c
                      (lambda () (spawn-actor (lambda (msg) (error 'c "crash"))))
                      'permanent 'brutal-kill 'worker))
              2   ;; max 2 restarts
              1)]) ;; within 1 second
  (wait-ms 50)
  ;; Trigger 3 rapid crashes (3rd one exceeds intensity)
  (send (child-ref sup 'c) 'go)
  (wait-ms 50)
  (send (child-ref sup 'c) 'go)
  (wait-ms 50)
  (send (child-ref sup 'c) 'go)
  (wait-ms 300)
  (test "intensity-sup-dead" (actor-alive? sup) #f))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
