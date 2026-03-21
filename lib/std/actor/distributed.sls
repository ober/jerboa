#!chezscheme
;;; (std actor distributed) — Location-transparent distributed actor messaging
;;;
;;; Builds on (std actor core) and (std actor cluster) to provide:
;;;   - Location-transparent send (dsend / dsend/ask)
;;;   - Cluster-wide name registration
;;;   - Process groups (broadcast)
;;;   - Distributed supervision
;;;   - Node failure detection / monitoring
;;;   - Simple serialization via write/read on string ports

(library (std actor distributed)
  (export
    ;; Location-transparent send
    dsend
    dsend/ask

    ;; Remote actor references
    make-remote-ref
    remote-ref?
    remote-ref-node
    remote-ref-id

    ;; Cluster-wide name registration
    cluster-register!
    cluster-whereis
    cluster-registered-names

    ;; Process groups
    make-process-group
    process-group-join!
    process-group-leave!
    process-group-members
    process-group-broadcast!

    ;; Distributed supervision
    make-dist-supervisor
    dist-supervisor-start-child!
    dist-supervisor-children

    ;; Failure detection
    monitor-node
    demonitor-node
    node-alive?
    ping-node

    ;; Serialization
    serialize-message
    deserialize-message

    ;; Configuration parameters
    *default-send-timeout*
    *cluster-name*
    *max-message-size*)

  (import (chezscheme)
          (std actor core)
          (except (std actor cluster) node-alive?))

  ;; ======================================================================
  ;; Configuration parameters
  ;; ======================================================================

  (define *default-send-timeout* (make-parameter 5000))  ;; 5 seconds in ms
  (define *cluster-name*         (make-parameter "local"))

  ;; ======================================================================
  ;; Remote actor references
  ;; ======================================================================

  ;; A remote-ref identifies an actor on a specific cluster node by name.
  (define-record-type remote-ref-rec
    (fields
      (immutable node)    ;; node name (string or symbol)
      (immutable id))     ;; actor name or id
    (sealed #t))

  (define (make-remote-ref node-name actor-id)
    (make-remote-ref-rec node-name actor-id))

  (define (remote-ref? x) (remote-ref-rec? x))
  (define (remote-ref-node x) (remote-ref-rec-node x))
  (define (remote-ref-id x)   (remote-ref-rec-id   x))

  ;; Is actor-ref local? (uses (std actor core) actor-ref? predicate)
  (define (%local-ref? ref)
    (actor-ref? ref))

  ;; ======================================================================
  ;; Location-transparent send
  ;; ======================================================================

  ;; (dsend actor-ref msg)
  ;; Works for both local actor-refs and remote-refs.
  ;; For local refs, delegates directly to (send).
  ;; For remote refs, looks up the named actor on the target node.
  (define (dsend ref msg)
    (cond
      [(%local-ref? ref)
       ;; Local actor: use the core send
       (send ref msg)]
      [(remote-ref? ref)
       ;; Remote: find actor in cluster registry
       (let* ([node-name (remote-ref-node ref)]
              [actor-id  (remote-ref-id   ref)]
              [node      (cluster-node-by-name node-name)])
         (if node
           (let ([actor (remote-whereis node actor-id)])
             (if actor
               (send actor msg)
               (error 'dsend "actor not found on node" actor-id node-name)))
           (error 'dsend "node not found" node-name)))]
      [else
       (error 'dsend "not a valid actor reference" ref)]))

  ;; (dsend/ask actor-ref msg timeout-ms) -> reply or #f
  ;; Sends msg and waits for a reply; uses a temporary channel actor.
  (define (dsend/ask ref msg timeout-ms)
    (let* ([result-box (make-mutex)]
           [reply      #f]
           [replied?   #f]
           [cond-var   (make-condition)]
           [lock       (make-mutex)])
      ;; Spawn a one-shot reply actor
      (let ([reply-actor
             (spawn-actor
               (lambda (m)
                 (with-mutex lock
                   (set! reply m)
                   (set! replied? #t)
                   (condition-signal cond-var))))])
        ;; Send original message with reply-to field prepended
        (dsend ref (list 'ask reply-actor msg))
        ;; Wait for reply with timeout
        (let ([deadline (+ (current-time-ms) timeout-ms)])
          (with-mutex lock
            (let loop ()
              (unless replied?
                (let ([now (current-time-ms)])
                  (when (< now deadline)
                    (condition-wait cond-var lock)
                    (loop))))))
          (if replied? reply #f)))))

  (define (current-time-ms)
    (* 1000 (time-second (current-time))))

  ;; ======================================================================
  ;; Cluster-wide name registration
  ;; ======================================================================

  ;; Global name table: name -> actor-ref (local refs)
  (define *global-registry*       (make-hashtable equal-hash equal?))
  (define *global-registry-mutex* (make-mutex))

  ;; (cluster-register! name actor-ref) — register actor under a cluster-wide name
  (define (cluster-register! name actor-ref)
    (with-mutex *global-registry-mutex*
      (hashtable-set! *global-registry* name actor-ref))
    ;; Also register on all alive nodes in the cluster
    (for-each
      (lambda (node)
        (remote-register! node name actor-ref))
      (cluster-nodes)))

  ;; (cluster-whereis name) -> actor-ref or #f (searches local registry first)
  (define (cluster-whereis name)
    (or (with-mutex *global-registry-mutex*
          (hashtable-ref *global-registry* name #f))
        (whereis/any name)))

  ;; (cluster-registered-names) -> list of names
  (define (cluster-registered-names)
    (with-mutex *global-registry-mutex*
      (vector->list (hashtable-keys *global-registry*))))

  ;; ======================================================================
  ;; Process groups
  ;; ======================================================================

  (define-record-type process-group-rec
    (fields
      (immutable name)
      (mutable   members)   ;; list of actor-refs (or remote-refs)
      (immutable mutex))
    (sealed #t))

  (define (make-process-group name)
    (make-process-group-rec name '() (make-mutex)))

  (define (process-group-join! group ref)
    (with-mutex (process-group-rec-mutex group)
      (unless (member ref (process-group-rec-members group))
        (process-group-rec-members-set! group
          (cons ref (process-group-rec-members group))))))

  (define (process-group-leave! group ref)
    (with-mutex (process-group-rec-mutex group)
      (process-group-rec-members-set! group
        (filter (lambda (r) (not (equal? r ref)))
                (process-group-rec-members group)))))

  (define (process-group-members group)
    (with-mutex (process-group-rec-mutex group)
      (list-copy (process-group-rec-members group))))

  (define (process-group-broadcast! group msg)
    (for-each (lambda (ref) (dsend ref msg))
              (process-group-members group)))

  ;; ======================================================================
  ;; Distributed supervision
  ;; ======================================================================

  (define-record-type dist-sup-rec
    (fields
      (mutable children)    ;; list of (id node-hint actor-ref)
      (immutable mutex))
    (sealed #t))

  (define (make-dist-supervisor)
    (make-dist-sup-rec '() (make-mutex)))

  ;; (dist-supervisor-start-child! sup id proc [node-hint])
  ;; node-hint: a node name (string) or #f for local
  (define (dist-supervisor-start-child! sup id proc . rest)
    (let* ([node-hint (if (null? rest) #f (car rest))]
           [actor
            (if (or (not node-hint)
                    (equal? node-hint (*cluster-name*)))
              ;; Start locally
              (spawn-actor proc)
              ;; Simulate remote placement: start locally but tag with node
              (spawn-actor proc))])
      (with-mutex (dist-sup-rec-mutex sup)
        (dist-sup-rec-children-set! sup
          (cons (list id node-hint actor)
                (filter (lambda (c) (not (equal? (car c) id)))
                        (dist-sup-rec-children sup)))))
      actor))

  (define (dist-supervisor-children sup)
    (with-mutex (dist-sup-rec-mutex sup)
      (map (lambda (c)
             (list (list-ref c 0) (list-ref c 1) (list-ref c 2)))
           (dist-sup-rec-children sup))))

  ;; ======================================================================
  ;; Node failure detection
  ;; ======================================================================

  ;; Monitor table: node-name -> list of callbacks
  (define *node-monitors*       (make-hashtable equal-hash equal?))
  (define *node-monitors-mutex* (make-mutex))

  ;; (monitor-node node-name callback)
  ;; callback is called with node-name when node is detected as down
  (define (monitor-node node-name callback)
    (with-mutex *node-monitors-mutex*
      (hashtable-update! *node-monitors* node-name
        (lambda (cbs) (cons callback cbs)) '())))

  ;; (demonitor-node node-name callback)
  (define (demonitor-node node-name callback)
    (with-mutex *node-monitors-mutex*
      (hashtable-update! *node-monitors* node-name
        (lambda (cbs) (filter (lambda (c) (not (eq? c callback))) cbs))
        '())))

  ;; (node-alive? target-name) -> #t/#f
  ;; Uses cluster-node-by-name (which searches alive nodes).
  ;; Returns #t if the node exists in the cluster and is alive.
  (define (node-alive? target-name)
    ;; cluster-node-by-name searches (cluster-nodes) which already
    ;; filters to only alive nodes. So if found, it's alive.
    (if (cluster-node-by-name target-name) #t #f))

  ;; (ping-node node-name timeout-ms) -> 'ok or 'timeout
  ;; Uses cluster membership as a proxy for connectivity.
  (define (ping-node node-name timeout-ms)
    (if (node-alive? node-name)
      'ok
      'timeout))

  ;; Internal: notify monitors of a failed node
  (define (%notify-node-failure! node-name)
    (let ([cbs (with-mutex *node-monitors-mutex*
                 (hashtable-ref *node-monitors* node-name '()))])
      (for-each (lambda (cb) (cb node-name)) cbs)))

  ;; ======================================================================
  ;; Serialization
  ;; ======================================================================

  ;; Serialize a message to a bytevector using write.
  ;; Only works for data that is writable/readable (no procedures, etc.)
  (define (serialize-message msg)
    (let ([port (open-output-string)])
      (write msg port)
      (string->utf8 (get-output-string port))))

  ;; Maximum allowed message size (bytes) for deserialization.
  (define *max-message-size* (make-parameter (* 1 1024 1024)))  ;; 1MB default

  ;; Deserialize a message from a bytevector.
  ;; HARDENED: Disables read-eval (#. syntax) to prevent code execution
  ;; during deserialization, and enforces message size limits.
  (define (deserialize-message bv)
    (when (> (bytevector-length bv) (*max-message-size*))
      (error 'deserialize-message
             "message exceeds maximum allowed size"
             (bytevector-length bv) (*max-message-size*)))
    (let ([port (open-input-string (utf8->string bv))])
      (parameterize ([read-eval #f])
        (read port))))

  ;; Hook into cluster leave events so monitors fire automatically.
  ;; Must be after all define forms (it's an expression, not a definition).
  (on-node-leave
    (lambda (node)
      (%notify-node-failure! (node-name node))))

  ) ;; end library
