#!chezscheme
;;; Tests for (std actor core) — spawn, send, lifecycle, links, monitors

(import (chezscheme) (jerboa core) (std actor core))

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

;; Helper: wait up to timeout-ms for pred to become true; error if not
(define (wait-until pred timeout-ms)
  (let loop ([elapsed 0])
    (cond
      [(pred) #t]
      [(>= elapsed timeout-ms)
       (error 'wait-until (format "timed out after ~ams" timeout-ms))]
      [else
       (sleep (make-time 'time-duration 10000000 0))  ;; 10ms
       (loop (+ elapsed 10))])))

(printf "--- (std actor core) tests ---~%")

;; Test 1: spawn returns an actor-ref
(let ([a (spawn-actor (lambda (msg) (void)))])
  (test "spawn-returns-actor-ref" (actor-ref? a) #t)
  (test "spawn-alive" (actor-alive? a) #t)
  (actor-kill! a))

;; Test 2: send delivers message to behavior
(let ([got #f]
      [m (make-mutex)] [c (make-condition)])
  (let ([a (spawn-actor
              (lambda (msg)
                (with-mutex m (set! got msg) (condition-signal c))))])
    (send a 'ping)
    (with-mutex m (let loop () (unless got (condition-wait c m) (loop))))
    (test "send-delivers" got 'ping)
    (actor-kill! a)))

;; Test 3: actor-kill! marks actor dead
(let ([a (spawn-actor (lambda (msg) (void)))])
  (actor-kill! a)
  (wait-until (lambda () (not (actor-alive? a))) 500)
  (test "kill-dead" (actor-alive? a) #f))

;; Test 4: messages to dead actor go to dead-letter handler
(let ([dl #f])
  (set-dead-letter-handler! (lambda (msg dest) (set! dl msg)))
  (let ([a (spawn-actor (lambda (msg) (void)))])
    (actor-kill! a)
    (wait-until (lambda () (not (actor-alive? a))) 500)
    (send a 'orphan)
    (sleep (make-time 'time-duration 20000000 0))
    (test "dead-letter" dl 'orphan))
  (set-dead-letter-handler!
    (lambda (msg dest)
      (fprintf (current-error-port) "DEAD LETTER: ~s~%" msg))))

;; Test 5: actor-wait! returns after kill
(let ([a (spawn-actor (lambda (msg) (void)))]
      [returned #f]
      [m (make-mutex)] [c (make-condition)])
  (fork-thread
    (lambda ()
      (actor-wait! a)
      (with-mutex m (set! returned #t) (condition-signal c))))
  (sleep (make-time 'time-duration 20000000 0))
  (actor-kill! a)
  (with-mutex m (let loop () (unless returned (condition-wait c m) (loop))))
  (test "actor-wait" returned #t))

;; Test 6: linked actors — child death notifies parent
;; The child is spawned FROM WITHIN the parent's behavior, so (self) is set.
(let ([exit-got #f]
      [child-id #f]
      [m (make-mutex)] [c (make-condition)])
  (let ([parent
         (spawn-actor
           (lambda (msg)
             (match msg
               ['spawn-child
                ;; Spawn a linked child from inside this behavior
                (let ([child (spawn-actor/linked
                               (lambda (msg2) (error 'child "deliberate crash")))])
                  (set! child-id (actor-ref-id child))
                  (send child 'go))]
               [('EXIT _ _)
                (with-mutex m (set! exit-got msg) (condition-signal c))]
               [_ (void)])))])
    (send parent 'spawn-child)
    (with-mutex m (let loop () (unless exit-got (condition-wait c m) (loop))))
    (test "linked-exit-kind"  (car  exit-got) 'EXIT)
    (test "linked-exit-id"    (cadr exit-got) child-id)))

;; Test 7: self returns current actor-ref inside behavior
(let ([self-ref #f]
      [m (make-mutex)] [c (make-condition)])
  (let ([a (spawn-actor
              (lambda (msg)
                (with-mutex m (set! self-ref (self)) (condition-signal c))))])
    (send a 'go)
    (with-mutex m (let loop () (unless self-ref (condition-wait c m) (loop))))
    (test "self-eq" self-ref a)))

;; Test 8: actor processes multiple messages in order
(let ([log '()]
      [m (make-mutex)] [c (make-condition)])
  (let ([a (spawn-actor
              (lambda (msg)
                (with-mutex m
                  (set! log (cons msg log))
                  (when (= msg 5) (condition-signal c)))))])
    (do ([i 1 (+ i 1)]) ((> i 5)) (send a i))
    (with-mutex m
      (let loop () (unless (= (length log) 5) (condition-wait c m) (loop))))
    (test "message-order" (reverse log) '(1 2 3 4 5))))

;; Test 9: two actors ping-pong 100 times
(let ([count 0]
      [m (make-mutex)] [c (make-condition)])
  (define pong-ref #f)
  (define ping-ref
    (spawn-actor
      (lambda (msg)
        (match msg
          ['pong
           (with-mutex m
             (set! count (+ count 1))
             (if (= count 100)
               (condition-signal c)
               (send pong-ref 'ping)))]))))
  (set! pong-ref
    (spawn-actor
      (lambda (msg)
        (match msg ['ping (send ping-ref 'pong)]))))
  (send pong-ref 'ping)
  (with-mutex m (let loop () (unless (= count 100) (condition-wait c m) (loop))))
  (test "ping-pong-100" count 100))

;; Test 10: 500 actors each receive one message
(let ([counter 0]
      [m (make-mutex)] [c (make-condition)])
  (do ([i 0 (+ i 1)]) ((= i 500))
    (let ([a (spawn-actor
                (lambda (msg)
                  (with-mutex m
                    (set! counter (+ counter 1))
                    (when (= counter 500) (condition-signal c)))))])
      (send a 'go)))
  (with-mutex m
    (let loop () (unless (= counter 500) (condition-wait c m) (loop))))
  (test "500-actors" counter 500))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
