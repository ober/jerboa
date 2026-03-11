#!chezscheme
;;; (std raft) — Raft Consensus Algorithm (In-Memory Simulation)
;;;
;;; Full Raft state machine: follower/candidate/leader states.
;;; Nodes communicate via Scheme channels (in-process simulation).
;;; No network I/O — designed to be connected to a transport layer.
;;;
;;; Raft summary:
;;;   - Nodes start as followers with random election timeouts
;;;   - Follower → Candidate when election timeout fires
;;;   - Candidate requests votes; wins if majority
;;;   - Leader sends heartbeats to prevent election timeouts
;;;   - Log entries replicated from leader to followers
;;;   - Commit when majority acknowledge

(library (std raft)
  (export
    make-raft-node
    raft-start!
    raft-stop!
    raft-propose!
    raft-leader?
    raft-term
    raft-state
    raft-log
    raft-commit-index
    make-raft-cluster
    raft-cluster-nodes
    raft-cluster-leader)

  (import (chezscheme) (std misc channel))

  ;; ========== Log Entry ==========

  (define-record-type log-entry
    (fields index term command)
    (protocol
      (lambda (new)
        (lambda (index term command)
          (new index term command)))))

  ;; ========== Message Types ==========
  ;; Messages sent between nodes via channels.

  ;; RequestVote RPC: candidate → all nodes
  (define (make-vote-request term candidate-id last-log-index last-log-term)
    (vector 'request-vote term candidate-id last-log-index last-log-term))
  (define (vote-request? msg) (and (vector? msg) (eq? (vector-ref msg 0) 'request-vote)))
  (define (vote-request-term msg) (vector-ref msg 1))
  (define (vote-request-candidate-id msg) (vector-ref msg 2))
  (define (vote-request-last-log-index msg) (vector-ref msg 3))
  (define (vote-request-last-log-term msg) (vector-ref msg 4))

  ;; VoteResponse: node → candidate
  (define (make-vote-response term granted? voter-id)
    (vector 'vote-response term granted? voter-id))
  (define (vote-response? msg) (and (vector? msg) (eq? (vector-ref msg 0) 'vote-response)))
  (define (vote-response-term msg) (vector-ref msg 1))
  (define (vote-response-granted? msg) (vector-ref msg 2))

  ;; AppendEntries RPC: leader → followers (also used as heartbeat)
  (define (make-append-entries term leader-id prev-log-index prev-log-term entries commit-index)
    (vector 'append-entries term leader-id prev-log-index prev-log-term entries commit-index))
  (define (append-entries? msg) (and (vector? msg) (eq? (vector-ref msg 0) 'append-entries)))
  (define (append-entries-term msg) (vector-ref msg 1))
  (define (append-entries-leader-id msg) (vector-ref msg 2))
  (define (append-entries-prev-log-index msg) (vector-ref msg 3))
  (define (append-entries-prev-log-term msg) (vector-ref msg 4))
  (define (append-entries-entries msg) (vector-ref msg 5))
  (define (append-entries-commit-index msg) (vector-ref msg 6))

  ;; AppendEntriesResponse
  (define (make-append-response term success? follower-id match-index)
    (vector 'append-response term success? follower-id match-index))
  (define (append-response? msg) (and (vector? msg) (eq? (vector-ref msg 0) 'append-response)))
  (define (append-response-term msg) (vector-ref msg 1))
  (define (append-response-success? msg) (vector-ref msg 2))
  (define (append-response-follower-id msg) (vector-ref msg 3))
  (define (append-response-match-index msg) (vector-ref msg 4))

  ;; ClientPropose: client → leader
  (define (make-client-propose command reply-ch)
    (vector 'client-propose command reply-ch))
  (define (client-propose? msg) (and (vector? msg) (eq? (vector-ref msg 0) 'client-propose)))
  (define (client-propose-command msg) (vector-ref msg 1))
  (define (client-propose-reply-ch msg) (vector-ref msg 2))

  ;; Stop signal
  (define %stop-signal (list 'stop))

  ;; ========== Raft Node ==========

  (define-record-type (raft-node %make-raft-node raft-node?)
    (fields
      id                         ;; node identifier (symbol/number)
      (mutable current-term)     ;; current term
      (mutable voted-for)        ;; candidate voted for in current term (#f if none)
      (mutable log)              ;; list of log-entry (index 1-based, stored in order)
      (mutable commit-index)     ;; highest committed log index
      (mutable last-applied)     ;; highest applied log index
      (mutable state)            ;; 'follower | 'candidate | 'leader
      inbox                      ;; channel for receiving messages
      (mutable peers)            ;; list of (id . channel) for other nodes
      (mutable votes-received)   ;; set of voter IDs in current election
      (mutable next-index)       ;; per-follower: next log index to send (leader only)
      (mutable match-index)      ;; per-follower: highest replicated index (leader only)
      (mutable running?)         ;; is this node running?
      mutex                      ;; protects mutable fields
      (mutable election-timer)   ;; thread for election timeout
      (mutable heartbeat-timer)  ;; thread for heartbeat
      (mutable committed-log)    ;; applied entries (for inspection)
    ))

  (define (make-raft-node id)
    (%make-raft-node
      id
      0          ;; current-term
      #f         ;; voted-for
      '()        ;; log
      0          ;; commit-index
      0          ;; last-applied
      'follower  ;; state
      (make-channel 64)  ;; inbox
      '()        ;; peers
      '()        ;; votes-received
      '()        ;; next-index
      '()        ;; match-index
      #f         ;; running?
      (make-mutex)
      #f         ;; election-timer thread
      #f         ;; heartbeat-timer thread
      '()        ;; committed-log
    ))

  ;; Accessors for exported API
  (define (raft-term node) (raft-node-current-term node))
  (define (raft-state node) (raft-node-state node))
  (define (raft-log node) (raft-node-log node))
  (define (raft-commit-index node) (raft-node-commit-index node))
  (define (raft-leader? node) (eq? (raft-node-state node) 'leader))

  ;; ========== Utility Helpers ==========

  (define (log-last-index node)
    (let ([log (raft-node-log node)])
      (if (null? log) 0 (log-entry-index (car (last-pair log))))))

  (define (log-last-term node)
    (let ([log (raft-node-log node)])
      (if (null? log) 0 (log-entry-term (car (last-pair log))))))

  (define (log-entry-at node index)
    (let loop ([log (raft-node-log node)])
      (cond
        [(null? log) #f]
        [(= (log-entry-index (car log)) index) (car log)]
        [else (loop (cdr log))])))

  (define (majority count)
    (+ (quotient count 2) 1))

  ;; Random election timeout: 150–300ms
  (define (election-timeout-ms)
    (+ 150 (random 150)))

  ;; Heartbeat interval: 50ms
  (define heartbeat-interval-ms 50)

  ;; Send to a peer by looking up their channel
  (define (send-to-peer node peer-id msg)
    (let ([entry (assv peer-id (raft-node-peers node))])
      (when entry
        (guard (exn [#t (void)])
          (channel-put (cdr entry) msg)))))

  ;; Broadcast to all peers
  (define (broadcast-to-peers node msg)
    (for-each
      (lambda (entry) (send-to-peer node (car entry) msg))
      (raft-node-peers node)))

  ;; ========== State Transitions ==========

  (define (become-follower! node term)
    (raft-node-current-term-set! node term)
    (raft-node-voted-for-set! node #f)
    (raft-node-state-set! node 'follower)
    (raft-node-votes-received-set! node '())
    (stop-heartbeat! node)
    (reset-election-timer! node))

  (define (become-candidate! node)
    (let ([new-term (+ (raft-node-current-term node) 1)])
      (raft-node-current-term-set! node new-term)
      (raft-node-state-set! node 'candidate)
      (raft-node-voted-for-set! node (raft-node-id node))
      (raft-node-votes-received-set! node (list (raft-node-id node)))
      ;; Send RequestVote to all peers
      (let ([req (make-vote-request
                   new-term
                   (raft-node-id node)
                   (log-last-index node)
                   (log-last-term node))])
        (broadcast-to-peers node req))
      ;; Check if we already have majority (single node cluster)
      (check-election-won! node)
      (reset-election-timer! node)))

  (define (become-leader! node)
    (raft-node-state-set! node 'leader)
    (stop-election-timer! node)
    ;; Initialize next-index and match-index for followers
    (let ([next-idx (+ (log-last-index node) 1)])
      (raft-node-next-index-set! node
        (map (lambda (entry) (cons (car entry) next-idx))
             (raft-node-peers node)))
      (raft-node-match-index-set! node
        (map (lambda (entry) (cons (car entry) 0))
             (raft-node-peers node))))
    ;; Send immediate heartbeat
    (send-heartbeats! node)
    (start-heartbeat! node))

  ;; ========== Election Timeout ==========

  (define (reset-election-timer! node)
    (stop-election-timer! node)
    (when (raft-node-running? node)
      (let ([t (fork-thread
                 (lambda ()
                   (let ([timeout-ms (election-timeout-ms)])
                     (sleep (make-time 'time-duration
                              (* timeout-ms 1000000) 0))
                     (when (and (raft-node-running? node)
                                (not (eq? (raft-node-state node) 'leader)))
                       (channel-put (raft-node-inbox node)
                                    (vector 'election-timeout))))))])
        (raft-node-election-timer-set! node t))))

  (define (stop-election-timer! node)
    ;; Can't kill threads in Chez, but the timer checks running? before firing
    (raft-node-election-timer-set! node #f))

  ;; ========== Heartbeat ==========

  (define (start-heartbeat! node)
    (let ([t (fork-thread
               (lambda ()
                 (let loop ()
                   (when (and (raft-node-running? node)
                              (eq? (raft-node-state node) 'leader))
                     (sleep (make-time 'time-duration
                              (* heartbeat-interval-ms 1000000) 0))
                     (when (and (raft-node-running? node)
                                (eq? (raft-node-state node) 'leader))
                       (channel-put (raft-node-inbox node)
                                    (vector 'heartbeat-tick)))
                     (loop)))))])
      (raft-node-heartbeat-timer-set! node t)))

  (define (stop-heartbeat! node)
    (raft-node-heartbeat-timer-set! node #f))

  (define (send-heartbeats! node)
    (let ([term (raft-node-current-term node)]
          [id (raft-node-id node)]
          [commit (raft-node-commit-index node)])
      (for-each
        (lambda (peer-entry)
          (let* ([peer-id (car peer-entry)]
                 [ni (cdr (assv peer-id (raft-node-next-index node)))]
                 [prev-index (- ni 1)]
                 [prev-term (let ([e (log-entry-at node prev-index)])
                              (if e (log-entry-term e) 0))]
                 ;; entries from ni onwards
                 [entries (filter (lambda (e)
                                    (>= (log-entry-index e) ni))
                                  (raft-node-log node))])
            (send-to-peer node peer-id
              (make-append-entries term id prev-index prev-term
                                   entries commit))))
        (raft-node-peers node))))

  ;; ========== Election Check ==========

  (define (check-election-won! node)
    (when (eq? (raft-node-state node) 'candidate)
      (let* ([cluster-size (+ 1 (length (raft-node-peers node)))]
             [votes (length (raft-node-votes-received node))])
        (when (>= votes (majority cluster-size))
          (become-leader! node)))))

  ;; ========== Log Replication ==========

  (define (apply-committed-entries! node)
    (let loop ()
      (when (> (raft-node-commit-index node) (raft-node-last-applied node))
        (let ([next-apply (+ (raft-node-last-applied node) 1)])
          (let ([entry (log-entry-at node next-apply)])
            (when entry
              (raft-node-committed-log-set! node
                (append (raft-node-committed-log node)
                        (list entry)))
              (raft-node-last-applied-set! node next-apply)
              (loop)))))))

  (define (try-advance-commit-index! node)
    ;; Find highest N > commit-index where majority have match-index >= N
    (when (eq? (raft-node-state node) 'leader)
      (let ([cluster-size (+ 1 (length (raft-node-peers node)))]
            [current-commit (raft-node-commit-index node)])
        (let loop ([n (log-last-index node)])
          (when (> n current-commit)
            (let* ([entry (log-entry-at node n)]
                   [replicated
                    (if entry
                      ;; count how many have match-index >= n
                      (+ 1 ;; leader itself
                         (length
                           (filter (lambda (mi-entry)
                                     (>= (cdr mi-entry) n))
                                   (raft-node-match-index node))))
                      0)])
              (if (and entry
                       (= (log-entry-term entry) (raft-node-current-term node))
                       (>= replicated (majority cluster-size)))
                (begin
                  (raft-node-commit-index-set! node n)
                  (apply-committed-entries! node))
                (loop (- n 1)))))))))

  ;; ========== Message Handlers ==========

  (define (handle-message! node msg)
    (cond
      ;; Election timeout → start election
      [(and (vector? msg) (eq? (vector-ref msg 0) 'election-timeout))
       (when (not (eq? (raft-node-state node) 'leader))
         (become-candidate! node))]

      ;; Heartbeat tick → send heartbeats as leader
      [(and (vector? msg) (eq? (vector-ref msg 0) 'heartbeat-tick))
       (when (eq? (raft-node-state node) 'leader)
         (send-heartbeats! node))]

      ;; RequestVote
      [(vote-request? msg)
       (let* ([term (vote-request-term msg)]
              [candidate (vote-request-candidate-id msg)]
              [last-idx (vote-request-last-log-index msg)]
              [last-t (vote-request-last-log-term msg)])
         ;; Step down if term > current
         (when (> term (raft-node-current-term node))
           (become-follower! node term))
         ;; Grant vote if:
         ;; 1) term >= our term
         ;; 2) haven't voted or voted for this candidate
         ;; 3) candidate log is at least as up-to-date
         (let* ([up-to-date?
                 (or (> last-t (log-last-term node))
                     (and (= last-t (log-last-term node))
                          (>= last-idx (log-last-index node))))]
                [grant?
                 (and (= term (raft-node-current-term node))
                      (or (not (raft-node-voted-for node))
                          (equal? (raft-node-voted-for node) candidate))
                      up-to-date?)])
           (when grant?
             (raft-node-voted-for-set! node candidate)
             (reset-election-timer! node))
           (send-to-peer node candidate
             (make-vote-response (raft-node-current-term node)
                                 grant?
                                 (raft-node-id node)))))]

      ;; VoteResponse
      [(vote-response? msg)
       (let ([term (vote-response-term msg)]
             [granted? (vote-response-granted? msg)])
         (when (> term (raft-node-current-term node))
           (become-follower! node term))
         (when (and granted?
                    (eq? (raft-node-state node) 'candidate)
                    (= term (raft-node-current-term node)))
           (raft-node-votes-received-set! node
             (cons (vector-ref msg 3) (raft-node-votes-received node)))
           (check-election-won! node)))]

      ;; AppendEntries (heartbeat or log replication)
      [(append-entries? msg)
       (let* ([term (append-entries-term msg)]
              [leader-id (append-entries-leader-id msg)]
              [prev-idx (append-entries-prev-log-index msg)]
              [prev-term (append-entries-prev-log-term msg)]
              [entries (append-entries-entries msg)]
              [leader-commit (append-entries-commit-index msg)])
         ;; Step down if newer term
         (when (> term (raft-node-current-term node))
           (become-follower! node term))
         (let ([success?
                (and (>= term (raft-node-current-term node))
                     ;; Prev log entry check
                     (or (= prev-idx 0)
                         (let ([prev-entry (log-entry-at node prev-idx)])
                           (and prev-entry
                                (= (log-entry-term prev-entry) prev-term)))))])
           (when (and success? (>= term (raft-node-current-term node)))
             ;; Reset election timer (valid leader heartbeat)
             (when (eq? (raft-node-state node) 'candidate)
               (become-follower! node term))
             (reset-election-timer! node)
             ;; Append new entries (remove conflicting + add new)
             (when (pair? entries)
               (let* ([existing (raft-node-log node)]
                      ;; Keep entries before first new entry
                      [keep (filter (lambda (e)
                                      (< (log-entry-index e) prev-idx))
                                    existing)])
                 ;; Append entries from leader
                 (raft-node-log-set! node (append keep entries))))
             ;; Update commit index
             (when (> leader-commit (raft-node-commit-index node))
               (raft-node-commit-index-set! node
                 (min leader-commit (log-last-index node)))
               (apply-committed-entries! node)))
           ;; Send response
           (send-to-peer node leader-id
             (make-append-response
               (raft-node-current-term node)
               success?
               (raft-node-id node)
               (log-last-index node)))))]

      ;; AppendEntriesResponse (leader handles)
      [(append-response? msg)
       (when (eq? (raft-node-state node) 'leader)
         (let* ([term (append-response-term msg)]
                [success? (append-response-success? msg)]
                [follower-id (append-response-follower-id msg)]
                [match-idx (append-response-match-index msg)])
           (when (> term (raft-node-current-term node))
             (become-follower! node term))
           (when (and success?
                      (eq? (raft-node-state node) 'leader))
             ;; Update match-index and next-index for this follower
             (raft-node-match-index-set! node
               (map (lambda (mi)
                      (if (equal? (car mi) follower-id)
                        (cons follower-id (max (cdr mi) match-idx))
                        mi))
                    (raft-node-match-index node)))
             (raft-node-next-index-set! node
               (map (lambda (ni)
                      (if (equal? (car ni) follower-id)
                        (cons follower-id (+ match-idx 1))
                        ni))
                    (raft-node-next-index node)))
             (try-advance-commit-index! node))))]

      ;; ClientPropose
      [(client-propose? msg)
       (let ([cmd (client-propose-command msg)]
             [reply-ch (client-propose-reply-ch msg)])
         (if (eq? (raft-node-state node) 'leader)
           (let* ([new-index (+ (log-last-index node) 1)]
                  [entry (make-log-entry
                           new-index
                           (raft-node-current-term node)
                           cmd)])
             (raft-node-log-set! node
               (append (raft-node-log node) (list entry)))
             (send-heartbeats! node)
             (when reply-ch
               (channel-put reply-ch (cons 'ok new-index))))
           (when reply-ch
             (channel-put reply-ch (cons 'not-leader #f)))))]

      ;; Stop signal
      [(eq? msg %stop-signal)
       (raft-node-running?-set! node #f)]))

  ;; ========== Node Lifecycle ==========

  (define (raft-start! node)
    (raft-node-running?-set! node #t)
    ;; Start main message loop in a thread
    (fork-thread
      (lambda ()
        (reset-election-timer! node)
        (let loop ()
          (when (raft-node-running? node)
            (let ([msg (channel-get (raft-node-inbox node))])
              (with-mutex (raft-node-mutex node)
                (handle-message! node msg))
              (loop))))))
    node)

  (define (raft-stop! node)
    (raft-node-running?-set! node #f)
    (guard (exn [#t (void)])
      (channel-put (raft-node-inbox node) %stop-signal)))

  (define (raft-propose! node command)
    ;; Propose a command. Returns (values 'ok index) or (values 'not-leader #f)
    (let ([reply-ch (make-channel 1)])
      (channel-put (raft-node-inbox node)
                   (make-client-propose command reply-ch))
      (let ([result (channel-get reply-ch)])
        (values (car result) (cdr result)))))

  ;; ========== Cluster ==========

  (define-record-type (raft-cluster %make-raft-cluster raft-cluster?)
    (fields (immutable node-list raft-cluster-node-list)))

  (define (make-raft-cluster node-count)
    (let* ([nodes (let build ([i 0] [acc '()])
                    (if (= i node-count)
                      (reverse acc)
                      (build (+ i 1) (cons (make-raft-node i) acc))))]
           [peer-map (map (lambda (n)
                            (cons (raft-node-id n) (raft-node-inbox n)))
                          nodes)])
      ;; Wire up peers (each node knows all others)
      (for-each
        (lambda (node)
          (raft-node-peers-set! node
            (filter (lambda (entry)
                      (not (equal? (car entry) (raft-node-id node))))
                    peer-map)))
        nodes)
      (%make-raft-cluster nodes)))

  (define (raft-cluster-nodes cluster)
    (raft-cluster-node-list cluster))

  (define (raft-cluster-leader cluster)
    (let loop ([nodes (raft-cluster-node-list cluster)])
      (cond
        [(null? nodes) #f]
        [(raft-leader? (car nodes)) (car nodes)]
        [else (loop (cdr nodes))])))

) ;; end library
