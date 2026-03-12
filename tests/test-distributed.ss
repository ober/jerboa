#!chezscheme
;;; Tests for (std actor distributed) — Location-transparent actor messaging

(import (chezscheme) (std actor core) (except (std actor cluster) node-alive?) (std actor distributed))

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

(printf "--- (std actor distributed) tests ---~%")

;;; ============================================================
;;; Parameters
;;; ============================================================

(test "default-send-timeout" (*default-send-timeout*) 5000)
(test "cluster-name default" (*cluster-name*) "local")

(*cluster-name* "node-1")
(test "cluster-name param set" (*cluster-name*) "node-1")
(*cluster-name* "local")  ;; reset

;;; ============================================================
;;; Remote refs
;;; ============================================================

(let ([ref (make-remote-ref "node-2" 'worker-1)])
  (test "remote-ref?" (remote-ref? ref) #t)
  (test "remote-ref? false" (remote-ref? "not-a-ref") #f)
  (test "remote-ref-node" (remote-ref-node ref) "node-2")
  (test "remote-ref-id"   (remote-ref-id   ref) 'worker-1))

;; remote-ref is not an actor-ref
(let ([ref (make-remote-ref "node-2" 'foo)])
  (test "remote-ref not actor-ref?" (actor-ref? ref) #f))

;;; ============================================================
;;; Serialization
;;; ============================================================

(let ([msg '(hello world 42)])
  (let ([bv (serialize-message msg)])
    (test "serialize type" (bytevector? bv) #t)
    (test "deserialize roundtrip" (deserialize-message bv) msg)))

(let ([msg "a simple string"])
  (test "serialize string" (deserialize-message (serialize-message msg)) msg))

(let ([msg '(1 2 (3 4) "nested")])
  (test "serialize nested" (deserialize-message (serialize-message msg)) msg))

(let ([msg '#(1 2 3)])
  (test "serialize vector" (deserialize-message (serialize-message msg)) msg))

(let ([msg 42])
  (test "serialize number" (deserialize-message (serialize-message msg)) msg))

(let ([msg #t])
  (test "serialize boolean" (deserialize-message (serialize-message msg)) #t))

;;; ============================================================
;;; Cluster-wide name registration
;;; ============================================================

;; Register a local actor and find it by name
(let* ([results '()]
       [actor (spawn-actor
                (lambda (msg)
                  (set! results (cons msg results))))])
  (cluster-register! 'test-actor-1 actor)
  (test "cluster-register! found" (cluster-whereis 'test-actor-1) actor)
  (test "cluster-registered-names includes"
    (member 'test-actor-1 (cluster-registered-names))
    (list 'test-actor-1)))

;; whereis unknown name returns #f
(test "cluster-whereis unknown" (cluster-whereis 'no-such-actor) #f)

;;; ============================================================
;;; dsend to local actor
;;; ============================================================

(let* ([received '()]
       [done-mutex (make-mutex)]
       [done-cond  (make-condition)]
       [actor (spawn-actor
                (lambda (msg)
                  (with-mutex done-mutex
                    (set! received (cons msg received))
                    (condition-signal done-cond))))])
  ;; dsend to a local actor-ref
  (dsend actor 'hello)
  ;; Wait for delivery
  (with-mutex done-mutex
    (unless (pair? received)
      (condition-wait done-cond done-mutex)))
  (test "dsend local" received '(hello)))

;;; ============================================================
;;; Process groups
;;; ============================================================

(let* ([group (make-process-group "workers")]
       [msgs-a '()]
       [msgs-b '()]
       [actor-a (spawn-actor (lambda (m) (set! msgs-a (cons m msgs-a))))]
       [actor-b (spawn-actor (lambda (m) (set! msgs-b (cons m msgs-b))))])

  (test "process-group-members empty" (process-group-members group) '())

  (process-group-join! group actor-a)
  (test "process-group-members one" (length (process-group-members group)) 1)

  (process-group-join! group actor-b)
  (test "process-group-members two" (length (process-group-members group)) 2)

  ;; No duplicate joins
  (process-group-join! group actor-a)
  (test "process-group no dup" (length (process-group-members group)) 2)

  (process-group-leave! group actor-a)
  (test "process-group-leave" (length (process-group-members group)) 1)
  (test "process-group member after leave"
    (member actor-a (process-group-members group)) #f))

;;; ============================================================
;;; process-group-broadcast!
;;; ============================================================

(let* ([group (make-process-group "broadcast-test")]
       [count-mutex (make-mutex)]
       [count 0]
       [done-cond (make-condition)]
       [make-counting-actor
        (lambda ()
          (spawn-actor
            (lambda (msg)
              (with-mutex count-mutex
                (set! count (+ count 1))
                (when (= count 2)
                  (condition-signal done-cond))))))])
  (let ([a1 (make-counting-actor)]
        [a2 (make-counting-actor)])
    (process-group-join! group a1)
    (process-group-join! group a2)
    (process-group-broadcast! group 'ping)
    ;; Wait for both to receive
    (with-mutex count-mutex
      (let loop ()
        (when (< count 2)
          (condition-wait done-cond count-mutex)
          (loop))))
    (test "broadcast both received" count 2)))

;;; ============================================================
;;; Distributed supervisor
;;; ============================================================

(let* ([sup (make-dist-supervisor)]
       [started '()])
  (test "dist-supervisor-children empty" (dist-supervisor-children sup) '())

  (dist-supervisor-start-child! sup 'worker-1
    (lambda () (let loop ([msg (receive)]) (loop (receive)))))

  (let ([children (dist-supervisor-children sup)])
    (test "dist-supervisor-children count" (length children) 1)
    (test "dist-supervisor child id" (caar children) 'worker-1))

  (dist-supervisor-start-child! sup 'worker-2
    (lambda () (let loop ([msg (receive)]) (loop (receive)))))

  (test "dist-supervisor two children" (length (dist-supervisor-children sup)) 2))

;;; ============================================================
;;; Node monitoring
;;; ============================================================

;; monitor-node / demonitor-node
(let* ([fired '()]
       [cb (lambda (node-name) (set! fired (cons node-name fired)))])
  (monitor-node "test-node" cb)
  ;; Stop a node to trigger monitor
  (let ([n (start-node! "test-node")])
    (stop-node! n)
    ;; Monitor should have fired via on-node-leave hook
    (test "monitor fired" (member "test-node" fired) '("test-node")))
  ;; Demonitor
  (demonitor-node "test-node" cb))

;;; ============================================================
;;; node-alive? and ping-node
;;; ============================================================

(let ([n (start-node! "ping-test-node")])
  (test "node-alive? true" (node-alive? "ping-test-node") #t)
  (test "ping-node ok" (ping-node "ping-test-node" 100) 'ok)
  (stop-node! n)
  (test "node-alive? false after stop" (node-alive? "ping-test-node") #f)
  (test "ping-node timeout" (ping-node "ping-test-node" 100) 'timeout))

;; Unknown node
(test "node-alive? unknown" (node-alive? "nonexistent-node") #f)
(test "ping-node unknown" (ping-node "nonexistent-node" 100) 'timeout)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
