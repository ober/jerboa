#!chezscheme
;;; Tests for (std actor cluster) and (std actor crdt)

(import (chezscheme) (std actor crdt) (std actor cluster))

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

(printf "--- (std actor crdt) + (std actor cluster) tests ---~%")

;;; ======== G-Counter ========

(printf "~%-- G-Counter --~%")

(let ([gc (make-gcounter 'node1)])
  (test "gcounter: initial value"
    (gcounter-value gc)
    0)

  (gcounter-increment! gc)
  (gcounter-increment! gc)
  (test "gcounter: after 2 increments"
    (gcounter-value gc)
    2)

  (gcounter-increment! gc 5)
  (test "gcounter: increment by 5"
    (gcounter-value gc)
    7)

  ;; Merge two G-Counters
  (let ([gc2 (make-gcounter 'node2)])
    (gcounter-increment! gc2 10)
    (gcounter-merge! gc gc2)
    (test "gcounter: merge from another node"
      (gcounter-value gc)
      17)

    ;; Idempotent merge
    (gcounter-merge! gc gc2)
    (test "gcounter: merge is idempotent"
      (gcounter-value gc)
      17)

    ;; Commutative merge
    (let ([gc3 (make-gcounter 'node1)]
          [gc4 (make-gcounter 'node2)])
      (gcounter-increment! gc3 3)
      (gcounter-increment! gc4 7)
      (gcounter-merge! gc3 gc4)
      (let ([merged-3-then-4 (gcounter-value gc3)])
        (let ([gc5 (make-gcounter 'node2)]
              [gc6 (make-gcounter 'node1)])
          (gcounter-increment! gc5 7)
          (gcounter-increment! gc6 3)
          (gcounter-merge! gc5 gc6)
          (test "gcounter: merge is commutative"
            merged-3-then-4
            (gcounter-value gc5))))))

  (test "gcounter: state is alist"
    (pair? (gcounter-state gc))
    #t))

;;; ======== PN-Counter ========

(printf "~%-- PN-Counter --~%")

(let ([pnc (make-pncounter 'node1)])
  (test "pncounter: initial value"
    (pncounter-value pnc)
    0)

  (pncounter-increment! pnc 5)
  (pncounter-decrement! pnc 2)
  (test "pncounter: increment 5, decrement 2"
    (pncounter-value pnc)
    3)

  (let ([pnc2 (make-pncounter 'node2)])
    (pncounter-increment! pnc2 10)
    (pncounter-merge! pnc pnc2)
    (test "pncounter: merge"
      (pncounter-value pnc)
      13)))

;;; ======== G-Set ========

(printf "~%-- G-Set --~%")

(let ([gs (make-gset)])
  (test "gset: initial empty"
    (gset-value gs)
    '())

  (gset-add! gs 'apple)
  (gset-add! gs 'banana)
  (test "gset: member after add"
    (gset-member? gs 'apple)
    #t)

  (test "gset: non-member"
    (gset-member? gs 'cherry)
    #f)

  (let ([gs2 (make-gset)])
    (gset-add! gs2 'cherry)
    (gset-merge! gs gs2)
    (test "gset: after merge has cherry"
      (gset-member? gs 'cherry)
      #t)

    (test "gset: merge is idempotent"
      (begin (gset-merge! gs gs2) (gset-member? gs 'cherry))
      #t))

  (test "gset: all values present"
    (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
               (gset-value gs))
    '(apple banana cherry)))

;;; ======== OR-Set ========

(printf "~%-- OR-Set --~%")

(let ([os (make-orset)])
  (test "orset: initial not member"
    (orset-member? os 'x)
    #f)

  (orset-add! os 'x)
  (test "orset: member after add"
    (orset-member? os 'x)
    #t)

  (orset-remove! os 'x)
  (test "orset: not member after remove"
    (orset-member? os 'x)
    #f)

  ;; Add-wins: concurrent add and remove — add survives in OR-Set
  ;; Simulate: node A removes x, node B adds x concurrently
  (let ([os-a (make-orset)]
        [os-b (make-orset)])
    (orset-add! os-a 'x)
    (orset-add! os-b 'x)
    ;; os-a removes x, os-b doesn't know about it
    (orset-remove! os-a 'x)
    ;; Merge: os-b's add (which os-a didn't know about) survives
    (orset-merge! os-a os-b)
    (test "orset: add-wins on concurrent add/remove"
      (orset-member? os-a 'x)
      #t)))

;;; ======== LWW-Register ========

(printf "~%-- LWW-Register --~%")

(let ([r (make-lww-register)])
  (test "lww: initial value is #f"
    (lww-register-value r)
    #f)

  (lww-register-set! r 'hello 100.0)
  (test "lww: value after set"
    (lww-register-value r)
    'hello)

  (lww-register-set! r 'world 200.0)
  (test "lww: newer value wins"
    (lww-register-value r)
    'world)

  (lww-register-set! r 'old 50.0)
  (test "lww: older value ignored"
    (lww-register-value r)
    'world)

  (let ([r2 (make-lww-register)])
    (lww-register-set! r2 'newest 999.0)
    (lww-register-merge! r r2)
    (test "lww: merge takes newer"
      (lww-register-value r)
      'newest)

    ;; Idempotent
    (lww-register-merge! r r2)
    (test "lww: merge idempotent"
      (lww-register-value r)
      'newest)))

;;; ======== MV-Register ========

(printf "~%-- MV-Register --~%")

(let ([r (make-mv-register)])
  (test "mv: initial values empty"
    (mv-register-values r)
    '())

  (mv-register-set! r 'node1 42)
  (test "mv: single value"
    (mv-register-values r)
    '(42))

  ;; Sequential update: overwrites
  (mv-register-set! r 'node1 99)
  (test "mv: sequential update replaces"
    (mv-register-values r)
    '(99))

  ;; Concurrent writes from different nodes
  (let ([r2 (make-mv-register)]
        [r3 (make-mv-register)])
    (mv-register-set! r2 'node1 'a)
    (mv-register-set! r3 'node2 'b)
    ;; Merge concurrent writes
    (mv-register-merge! r2 r3)
    (test "mv: concurrent values both preserved"
      (= (length (mv-register-values r2)) 2)
      #t)
    (test "mv: both values present"
      (and (member 'a (mv-register-values r2))
           (member 'b (mv-register-values r2))
           #t)
      #t)))

;;; ======== Vector Clock ========

(printf "~%-- Vector Clock --~%")

(let ([vc1 (make-vclock)]
      [vc2 (make-vclock)])
  (test "vclock: initial get is 0"
    (vclock-get vc1 'node1)
    0)

  (vclock-increment! vc1 'node1)
  (vclock-increment! vc1 'node1)
  (test "vclock: increment and get"
    (vclock-get vc1 'node1)
    2)

  (vclock-increment! vc2 'node2)
  (test "vclock: happens-before (vc2 before vc1 after merge?)"
    (vclock-happens-before? vc2 vc1)
    #f)

  (vclock-merge! vc1 vc2)
  (test "vclock: after merge, vc2 happens-before vc1"
    (vclock-happens-before? vc2 vc1)
    #t)

  (test "vclock->alist"
    (pair? (vclock->alist vc1))
    #t))

;;; ======== Cluster: Node Management ========

(printf "~%-- Cluster: Node Management --~%")

(let ([n1 (start-node! "worker-1")]
      [n2 (start-node! "worker-2")])

  (test "node?: predicate"
    (node? n1)
    #t)

  (test "node-name"
    (node-name n1)
    "worker-1")

  (test "node-alive? after start"
    (node-alive? n1)
    #t)

  (test "cluster-nodes includes both"
    (>= (length (cluster-nodes)) 2)
    #t)

  (test "cluster-node-by-name"
    (and (cluster-node-by-name "worker-1") #t)
    #t)

  ;; Remote registry
  (remote-register! n1 'foo 42)
  (test "remote-whereis: found"
    (remote-whereis n1 'foo)
    42)

  (test "remote-whereis: not found"
    (remote-whereis n1 'bar)
    #f)

  (remote-unregister! n1 'foo)
  (test "remote-unregister!"
    (remote-whereis n1 'foo)
    #f)

  ;; whereis/any
  (remote-register! n2 'service 99)
  (test "whereis/any: finds across nodes"
    (whereis/any 'service)
    99)

  ;; Stop node
  (stop-node! n1)
  (test "node-alive? after stop"
    (node-alive? n1)
    #f)

  (stop-node! n2))

;;; ======== Cluster: Distributed Supervisor ========

(printf "~%-- Distributed Supervisor --~%")

(let ([n1 (start-node! "sup-node-1")]
      [n2 (start-node! "sup-node-2")])

  (cluster-join! n1 n2)

  (let ([dsup (make-distributed-supervisor 'test-dsup strategy/round-robin)])

    (test "distributed-supervisor?: predicate"
      (distributed-supervisor? dsup)
      #t)

    ;; Start children (using no-op thunks)
    (dsupervisor-start-child! dsup 'child-a (lambda () (void)))
    (dsupervisor-start-child! dsup 'child-b (lambda () (void)))

    (test "dsupervisor-which-children: 2 children"
      (length (dsupervisor-which-children dsup))
      2)

    (test "dsupervisor-which-children: child-a present"
      (and (assq 'child-a (dsupervisor-which-children dsup)) #t)
      #t)

    ;; Stop a child
    (dsupervisor-stop-child! dsup 'child-a)
    (test "dsupervisor-stop-child!"
      (length (dsupervisor-which-children dsup))
      1)

    ;; Node failure handling
    (dsupervisor-start-child! dsup 'child-c (lambda () (void)))
    (let* ([before-count (length (dsupervisor-which-children dsup))]
           [child-c-node (cadar (filter (lambda (c) (eq? (car c) 'child-c))
                                        (dsupervisor-which-children dsup)))])
      ;; Simulate failure of child-c's node
      (when child-c-node
        (let ([failing-node (cluster-node-by-name child-c-node)])
          (when failing-node
            (stop-node! failing-node)
            (dsupervisor-handle-node-failure! dsup failing-node)))))

    (test "dsup: children list non-empty after failure handling"
      (>= (length (dsupervisor-which-children dsup)) 1)
      #t))

  (for-each (lambda (n) (when (node-alive? n) (stop-node! n))) (list n1 n2)))

;;; ======== Placement strategies ========

(printf "~%-- Placement strategies --~%")

(let ([n1 (start-node! "pl-1")]
      [n2 (start-node! "pl-2")]
      [n3 (start-node! "pl-3")])
  (let ([nodes (list n1 n2 n3)])

    (test "strategy/least-loaded: returns a node"
      (node? (strategy/least-loaded nodes #f #f))
      #t)

    (test "strategy/round-robin: returns a node"
      (node? (strategy/round-robin nodes #f #f))
      #t)

    (test "strategy/local-first: no current-node falls back to round-robin"
      (node? (strategy/local-first nodes #f #f))
      #t))

  (for-each stop-node! (list n1 n2 n3)))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
