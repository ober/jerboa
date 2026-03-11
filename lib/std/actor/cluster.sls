#!chezscheme
;;; (std actor cluster) — Node Discovery and Distributed Supervision
;;;
;;; Step 28: Node Discovery and Clustering
;;;   start-node!       — start a cluster node (in-process simulation)
;;;   stop-node!        — stop a cluster node
;;;   node?             — predicate
;;;   node-name         — node name
;;;   node-alive?       — is the node alive?
;;;   cluster-join!     — join a cluster
;;;   cluster-nodes     — list all known nodes
;;;   whereis           — look up actor in registry, optionally on remote node
;;;
;;; Step 29: Distributed Supervision
;;;   make-distributed-supervisor  — supervisor managing actors across nodes
;;;   dsupervisor-start-child!     — start child with placement strategy
;;;   dsupervisor-which-children   — list children and their node placements
;;;   dsupervisor-restart-on-failure — called when a node fails, restarts children
;;;
;;; Note: This is an in-process simulation. Real distributed clustering
;;; would require TCP/UDP sockets and serialization.

(library (std actor cluster)
  (export
    ;; Step 28: Node management
    start-node!
    stop-node!
    node?
    node-name
    node-id
    node-alive?
    current-node

    ;; Step 28: Cluster operations
    cluster-join!
    cluster-leave!
    cluster-nodes
    cluster-node-by-name
    on-node-join
    on-node-leave

    ;; Step 28: Remote actor registry
    remote-register!
    remote-unregister!
    remote-whereis
    whereis/any

    ;; Step 29: Distributed supervision
    make-distributed-supervisor
    distributed-supervisor?
    dsupervisor-start-child!
    dsupervisor-which-children
    dsupervisor-stop-child!
    dsupervisor-handle-node-failure!

    ;; Step 29: Placement strategies
    strategy/round-robin
    strategy/least-loaded
    strategy/local-first)

  (import (chezscheme))

  ;; ========== Node ==========

  (define-record-type (node make-node-raw node?)
    (fields
      (immutable name    node-name)
      (immutable id      node-id)
      (mutable   alive?  node-alive? node-set-alive!)
      (immutable registry node-registry)   ;; eq-hashtable: name → pid
      (immutable metadata node-metadata)  ;; string-hashtable: key → val
      (immutable mutex    node-mutex)))

  (define (start-node! name . opts)
    (let ([id   (string->symbol (format "node-~a-~a" name (time-second (current-time))))]
          [meta (make-hashtable equal-hash equal?)])
      ;; Process keyword options
      (let loop ([opts opts])
        (unless (null? opts)
          (cond
            [(eq? (car opts) '#:listen)
             (hashtable-set! meta 'listen (cadr opts))
             (loop (cddr opts))]
            [(eq? (car opts) '#:cookie)
             (hashtable-set! meta 'cookie (cadr opts))
             (loop (cddr opts))]
            [(eq? (car opts) '#:seeds)
             (hashtable-set! meta 'seeds (cadr opts))
             (loop (cddr opts))]
            [else (loop (cdr opts))])))
      (let ([n (make-node-raw name id #t
                  (make-eq-hashtable) meta (make-mutex))])
        ;; Register globally
        (with-mutex *cluster-mutex*
          (hashtable-set! *cluster-nodes* id n))
        ;; Notify join hooks
        (for-each (lambda (hook) (hook n)) *join-hooks*)
        n)))

  (define (stop-node! n)
    (with-mutex (node-mutex n)
      (node-set-alive! n #f))
    ;; Notify leave hooks
    (for-each (lambda (hook) (hook n)) *leave-hooks*)
    ;; Remove from global cluster
    (with-mutex *cluster-mutex*
      (hashtable-delete! *cluster-nodes* (node-id n))))

  ;; Thread-local current node (simulated via parameter)
  (define *current-node* (make-parameter #f))
  (define (current-node) (*current-node*))

  ;; ========== Cluster ==========

  ;; Global cluster registry
  (define *cluster-mutex*  (make-mutex))
  (define *cluster-nodes*  (make-eq-hashtable))  ;; id → node
  (define *join-hooks*     '())
  (define *leave-hooks*    '())

  (define (cluster-join! node1 node2)
    ;; Simulate joining: node1 discovers node2 (and vice versa)
    ;; In real implementation this would exchange membership lists
    (with-mutex *cluster-mutex*
      (hashtable-set! *cluster-nodes* (node-id node1) node1)
      (hashtable-set! *cluster-nodes* (node-id node2) node2)))

  (define (cluster-leave! node)
    (stop-node! node))

  (define (cluster-nodes)
    (with-mutex *cluster-mutex*
      (let-values ([(ids nodes) (hashtable-entries *cluster-nodes*)])
        (filter node-alive? (vector->list nodes)))))

  (define (cluster-node-by-name name)
    (let ([nodes (cluster-nodes)])
      (let loop ([ns nodes])
        (cond
          [(null? ns) #f]
          [(equal? (node-name (car ns)) name) (car ns)]
          [else (loop (cdr ns))]))))

  (define (on-node-join hook)
    (set! *join-hooks* (cons hook *join-hooks*)))

  (define (on-node-leave hook)
    (set! *leave-hooks* (cons hook *leave-hooks*)))

  ;; ========== Remote Actor Registry ==========

  (define (remote-register! node name pid)
    (when (node-alive? node)
      (with-mutex (node-mutex node)
        (hashtable-set! (node-registry node) name pid))))

  (define (remote-unregister! node name)
    (with-mutex (node-mutex node)
      (hashtable-delete! (node-registry node) name)))

  (define (remote-whereis node name)
    ;; Look up a named actor on a specific node
    (and (node-alive? node)
         (with-mutex (node-mutex node)
           (hashtable-ref (node-registry node) name #f))))

  (define (whereis/any name)
    ;; Find a named actor on any alive node (returns first found)
    (let loop ([nodes (cluster-nodes)])
      (cond
        [(null? nodes) #f]
        [(remote-whereis (car nodes) name) => values]
        [else (loop (cdr nodes))])))

  ;; ========== Step 29: Distributed Supervisor ==========

  ;; Child spec: (id proc node . restart-type)
  ;; restart-type: 'permanent | 'transient | 'temporary

  (define-record-type (distributed-supervisor make-dsup-raw distributed-supervisor?)
    (fields
      (immutable name       dsup-name)
      (mutable   children   dsup-children  dsup-set-children!)  ;; list of child-info
      (immutable strategy   dsup-strategy)  ;; placement strategy proc
      (immutable mutex      dsup-mutex)))

  ;; child-info: (id proc assigned-node pid restart-type)
  (define (child-info-id   c) (list-ref c 0))
  (define (child-info-proc c) (list-ref c 1))
  (define (child-info-node c) (list-ref c 2))
  (define (child-info-pid  c) (list-ref c 3))
  (define (child-info-restart-type c) (list-ref c 4))

  (define (make-distributed-supervisor name strategy)
    (make-dsup-raw name '() strategy (make-mutex)))

  (define (dsupervisor-start-child! dsup id proc . opts)
    (let* ([restart-type (if (null? opts) 'permanent (car opts))]
           [nodes    (cluster-nodes)]
           [target   ((dsup-strategy dsup) nodes dsup id)]
           [pid      (and target
                          (node-alive? target)
                          ;; Simulate starting the actor on target node
                          (let ([p (fork-thread proc)])
                            (remote-register! target id p)
                            p))]
           [child    (list id proc target pid restart-type)])
      (with-mutex (dsup-mutex dsup)
        (dsup-set-children! dsup
          (cons child
                (filter (lambda (c) (not (eq? (child-info-id c) id)))
                        (dsup-children dsup)))))
      pid))

  (define (dsupervisor-which-children dsup)
    (with-mutex (dsup-mutex dsup)
      (map (lambda (c)
             (list (child-info-id c)
                   (and (child-info-node c) (node-name (child-info-node c)))
                   (child-info-restart-type c)))
           (dsup-children dsup))))

  (define (dsupervisor-stop-child! dsup id)
    (with-mutex (dsup-mutex dsup)
      (let ([child (find (lambda (c) (eq? (child-info-id c) id))
                         (dsup-children dsup))])
        (when child
          (let ([node (child-info-node child)])
            (when node (remote-unregister! node id)))
          (dsup-set-children! dsup
            (filter (lambda (c) (not (eq? (child-info-id c) id)))
                    (dsup-children dsup)))))))

  (define (dsupervisor-handle-node-failure! dsup failed-node)
    ;; Find all children on the failed node and restart them on survivors
    (let ([affected
           (with-mutex (dsup-mutex dsup)
             (filter (lambda (c)
                       (and (child-info-node c)
                            (eq? (node-id (child-info-node c))
                                 (node-id failed-node))))
                     (dsup-children dsup)))])
      ;; Restart permanent and transient children
      (for-each
        (lambda (child)
          (let ([id   (child-info-id child)]
                [proc (child-info-proc child)]
                [rt   (child-info-restart-type child)])
            (when (memq rt '(permanent transient))
              (dsupervisor-start-child! dsup id proc rt))))
        affected)))

  ;; ========== Placement Strategies ==========

  ;; strategy/round-robin: place children in rotating order across nodes
  (define *rr-counter* 0)
  (define *rr-mutex*   (make-mutex))

  (define (strategy/round-robin nodes dsup id)
    (if (null? nodes) #f
      (with-mutex *rr-mutex*
        (let ([idx (remainder *rr-counter* (length nodes))])
          (set! *rr-counter* (+ *rr-counter* 1))
          (list-ref nodes idx)))))

  ;; strategy/least-loaded: pick node with fewest registered actors
  (define (strategy/least-loaded nodes dsup id)
    (if (null? nodes) #f
      (let loop ([best (car nodes)] [best-count (node-load (car nodes))]
                 [rest (cdr nodes)])
        (if (null? rest)
          best
          (let ([c (node-load (car rest))])
            (if (< c best-count)
              (loop (car rest) c (cdr rest))
              (loop best best-count (cdr rest))))))))

  (define (node-load n)
    (with-mutex (node-mutex n)
      (let-values ([(ks _) (hashtable-entries (node-registry n))])
        (vector-length ks))))

  ;; strategy/local-first: prefer the current node, fall back to round-robin
  (define (strategy/local-first nodes dsup id)
    (let ([current (current-node)])
      (if (and current (memq current nodes))
        current
        (strategy/round-robin nodes dsup id))))

  ) ;; end library
