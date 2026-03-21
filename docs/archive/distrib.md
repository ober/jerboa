# Distributed Computing Roadmap for Jerboa

Ship work from one jerboa program to other jerboa programs on remote servers.

## Existing Foundation

Jerboa already has:

| Layer | Module | What It Does |
|-------|--------|-------------|
| Transport | `(std net tcp-raw)` | POSIX sockets, fd-based, EINTR retry |
| Transport | `(std net tcp)` | Gerbil-compatible ports over TCP |
| Framing | `(std actor transport)` | 4-byte length + FASL body, cookie auth |
| Actors | `(std actor core)` | spawn, send, link, monitor, remote refs |
| Protocol | `(std actor protocol)` | ask/reply RPC, fire-and-forget tell |
| Supervision | `(std actor supervisor)` | OTP-style restart trees |
| Registry | `(std actor registry)` | Global named actor lookup |
| Scheduler | `(std actor scheduler)` | Work-stealing M:N thread pool |
| Clustering | `(std actor cluster)` | Node join/leave, remote registry |
| Distributed | `(std actor distributed)` | Location-transparent dsend, process groups |
| CRDTs | `(std actor crdt)` | G-Counter, PN-Counter, OR-Set, LWW-Register |
| Checkpoint | `(std actor checkpoint)` | FASL-based actor state snapshots |
| Serialization | `(std fasl)` | Binary serialization, 1000x faster than text |
| Persistence | `(std persist closure)` | Data checkpoint/resume via FASL |
| gRPC | `(std net grpc)` | S-expression RPC over TCP |
| HTTP | `(std net httpd)` | HTTP server with routing |
| Pools | `(std net pool)` | Generic connection pooling |
| Zero-Copy | `(std net zero-copy)` | Pre-allocated buffer pools |
| STM | `(std concur stm)` | Software transactional memory |
| Async | `(std concur async-await)` | Promise-based concurrency |
| Structured | `(std concur structured)` | Lexically-scoped task lifetimes |

**The bones are production-grade.** What's missing is the glue that turns "actors can send messages" into "programs can ship work to remote servers."

---

## 10 Features to Build

### 1. `(std net code-ship)` — Remote Code Shipping

The biggest gap. Distributed actors send *messages* (data), not *code*. To send work to a remote jerboa instance, you need to ship a computation.

Chez's `compile` + FASL can serialize compiled code objects. A remote node receives a FASL bytevector, loads it, runs it. This is the Ray/Spark model.

```scheme
;; Ship a lambda + data to a remote node, get result back
(define result
  (remote-eval node
    '(lambda (data)
       (import (std text csv))
       (let ([rows (csv-parse data)])
         (length (filter anomalous? rows))))
    my-csv-data))

;; Ship a named function (already deployed on worker)
(remote-call node 'process-batch batch-42)

;; Ship compiled code object via FASL
(let ([code (compile '(lambda (x) (* x x)))])
  (remote-eval/compiled node code 42))
;; => 1764
```

**Implementation:**
- Serialize S-expression via FASL, ship over TCP transport
- Remote node `eval`s in a sandboxed environment
- Result serialized back via FASL
- Timeout + error propagation
- Optional: ship pre-compiled code objects (Chez `compile` output)

**Chez leverage:** `compile` for runtime compilation, `eval` for execution, FASL for serialization of both code and data.

---

### 2. `(std net worker-pool)` — Worker Pool Service

A daemon that listens for work requests. Start `jerboa-worker` on N machines, submit work from your main program.

```scheme
;; Start worker daemon (on each server)
(define worker (start-worker-daemon
  #:port 9090
  #:threads 8
  #:imports '((std text csv) (std crypto digest))))

;; Client: connect to pool of workers
(define pool (connect-worker-pool
  '("srv1:9090" "srv2:9090" "srv3:9090" "srv4:9090")))

;; Submit work — automatic load balancing
(define results
  (distributed-map pool
    (lambda (chunk) (heavy-computation chunk))
    (chunk-data big-dataset 100)))
;; 100 chunks distributed across 4 servers, results collected

;; Single remote eval
(define result (pool-eval pool '(+ 1 2 3)))

;; Pool status
(pool-status pool)
;; => ((srv1 #:load 0.85 #:tasks 12)
;;     (srv2 #:load 0.42 #:tasks 6)
;;     (srv3 #:load 0.91 #:tasks 14)
;;     (srv4 #:load 0.30 #:tasks 4))
```

**Implementation:**
- Worker daemon: TCP server + thread pool + FASL framing
- Client: connection pool to all workers, round-robin or least-loaded dispatch
- Heartbeat: periodic ping, remove dead workers from pool
- Retry: if worker dies mid-task, re-submit to another
- Backpressure: workers report queue depth, client routes accordingly

**Protocol (over existing transport framing):**
```
Client → Worker: (submit task-id thunk-fasl data-fasl timeout-ms)
Worker → Client: (result task-id value-fasl)
Worker → Client: (error task-id message)
Client → Worker: (ping)
Worker → Client: (pong #:load 0.85 #:queue-depth 12)
Client → Worker: (cancel task-id)
```

---

### 3. `(std net task-queue)` — Persistent Task Queues

Durable work queues. Submit tasks, workers pull them. If a worker dies, the task gets reassigned. Like Celery/Sidekiq but in Scheme.

```scheme
;; Broker (central coordinator)
(define broker (start-task-broker #:port 9091 #:persist "/var/jerboa/tasks/"))

;; Producer: submit tasks
(task-submit! broker 'process-report {:file "big.csv" :format 'csv})
(task-submit! broker 'send-email {:to "alice@x.com" :subject "Done"})

;; Consumer: pull and execute tasks
(task-worker broker
  (lambda (task)
    (case (task-type task)
      [(process-report) (process-csv (task-data task))]
      [(send-email) (send-mail (task-data task))])))

;; Task status
(task-status broker task-id)
;; => 'running | 'pending | 'completed | 'failed | 'retrying

;; Retry policy
(task-submit! broker 'flaky-api data
  #:retries 3
  #:retry-delay 5000   ;; ms
  #:timeout 30000)     ;; ms

;; Scheduled tasks (run at specific time)
(task-schedule! broker 'nightly-report data
  #:at (make-time 'time-utc 0 1711065600))  ;; specific timestamp

;; Priority queues
(task-submit! broker 'urgent-alert data #:priority 'high)
```

**Implementation:**
- Broker: TCP server, in-memory queue + FASL persistence to disk
- At-least-once delivery: tasks acked after completion, re-queued on timeout
- Visibility timeout: claimed tasks invisible to other workers for N seconds
- Dead letter queue: tasks that fail after max retries
- FASL persistence: append-only log, periodic compaction

---

### 4. `(std actor consensus)` — Raft Consensus

Distributed agreement. Leader election, replicated log, linearizable reads. Foundation for distributed locks, config management, primary/replica.

```scheme
;; Start a Raft cluster
(define node (make-raft-node
  #:id "node-1"
  #:peers '("node-2:9100" "node-3:9100")
  #:port 9100
  #:state-machine (lambda (state cmd)
                    (case (car cmd)
                      [(set) (cons (cons (cadr cmd) (caddr cmd)) state)]
                      [(get) (assq (cadr cmd) state)]))))

(raft-start! node)

;; Propose a command (goes through leader)
(raft-propose! node '(set counter 42))

;; Read (linearizable — goes through leader)
(raft-read node '(get counter))
;; => (counter . 42)

;; Leader info
(raft-leader node)     ;; => "node-2"
(raft-state node)      ;; => 'follower | 'candidate | 'leader

;; Distributed lock built on Raft
(with-distributed-lock cluster "my-lock"
  (do-critical-section))
```

**Implementation:**
- Leader election via randomized timeouts
- Log replication with majority quorum
- Snapshot + log compaction for bounded memory
- Pre-vote extension to prevent disruptions
- ~500 lines for core Raft, ~200 for transport integration

---

### 5. `(std net pubsub)` — Publish/Subscribe Messaging

Broadcast patterns across nodes. Topic-based routing with wildcards.

```scheme
;; Broker
(define broker (start-pubsub-broker #:port 9092))

;; Publisher (on any node)
(define pub (pubsub-connect "broker:9092"))
(publish! pub "system.metrics.cpu" {:host "srv1" :value 0.85})
(publish! pub "system.metrics.mem" {:host "srv1" :value 0.62})
(publish! pub "app.events.login" {:user "alice"})

;; Subscriber (on any node)
(define sub (pubsub-connect "broker:9092"))
(subscribe! sub "system.metrics.*"
  (lambda (topic msg)
    (when (> (hashtable-ref msg 'value 0) 0.9)
      (alert! topic msg))))

(subscribe! sub "app.events.#"  ;; # matches multiple levels
  (lambda (topic msg) (log-event topic msg)))

;; Unsubscribe
(unsubscribe! sub "system.metrics.*")

;; Fan-out: all subscribers get every matching message
;; Fan-in: multiple publishers on same topic
```

**Implementation:**
- Broker: topic trie for O(log n) wildcard matching
- Subscribers: persistent TCP connections, push-based delivery
- QoS levels: at-most-once (fast) or at-least-once (ack-based)
- Retention: optionally persist last N messages per topic

---

### 6. `(std net dht)` — Distributed Hash Table

Consistent hashing for sharding data across nodes. Automatic rebalancing.

```scheme
;; Create DHT cluster
(define dht (join-dht '("node1:9200" "node2:9200" "node3:9200")))

;; Store/retrieve (key → responsible node determined by hash ring)
(dht-put! dht "user:alice" {:name "Alice" :age 30})
(dht-get dht "user:alice")
;; => {:name "Alice" :age 30}

;; Key is hashed to a position on the ring
;; Each node owns a range of the ring
;; Replication factor: store on N consecutive nodes
(dht-put! dht "user:bob" data #:replicas 3)

;; When nodes join/leave, only 1/N keys need to move
(dht-join! dht "node4:9200")   ;; automatic rebalancing
(dht-leave! dht "node2:9200")  ;; keys redistributed

;; Range queries (if keys are ordered)
(dht-range dht "user:a" "user:m")
```

**Implementation:**
- Consistent hashing with virtual nodes (128 vnodes per physical node)
- Gossip protocol for membership
- Sloppy quorum for availability (read R of N, write W of N)
- Hinted handoff for temporary failures
- Anti-entropy via Merkle trees

---

### 7. `(std stream distributed)` — Distributed Stream Processing

Process infinite event streams across nodes. Windowed aggregations, joins, exactly-once semantics.

```scheme
;; Define a processing topology
(define topology
  (stream-topology "click-analytics"
    ;; Source: read from pubsub topic
    (source "clicks" (pubsub-source "events.clicks"))

    ;; Filter
    (processor "valid-clicks" '("clicks")
      (lambda (event) (and (event-url event) event)))

    ;; Key-by for partitioning
    (partition "by-url" '("valid-clicks")
      (lambda (event) (event-url event)))

    ;; Windowed aggregation (60-second tumbling windows)
    (window "counts" '("by-url")
      #:type 'tumbling
      #:size 60
      (lambda (window events)
        {:url (window-key window)
         :count (length events)
         :period (window-start window)}))

    ;; Sink: write to another topic
    (sink "output" '("counts")
      (pubsub-sink "analytics.url-counts"))))

;; Deploy across cluster
(stream-deploy! cluster topology #:parallelism 4)
;; Each partition runs on a different node
;; Automatic failover: if a node dies, partitions reassigned

;; Monitor
(stream-metrics topology)
;; => ((clicks #:throughput 15000/s #:lag 42)
;;     (counts #:throughput 250/s #:windows-open 180))
```

**Implementation:**
- DAG of processors, partitioned by key
- Exactly-once via idempotent writes + offset tracking
- Watermarks for out-of-order event handling
- Checkpoint state to FASL periodically
- Built on existing pubsub + worker pool

---

### 8. `(std net discovery)` — Service Discovery

Nodes announce capabilities, others discover them. No hardcoded addresses.

```scheme
;; Service registration (on each server)
(service-register! discovery "image-processor"
  #:host (hostname)
  #:port 9090
  #:capacity 8
  #:tags '(gpu cuda)
  #:health-check (lambda () (gpu-available?)))

(service-register! discovery "csv-cruncher"
  #:host (hostname)
  #:port 9091
  #:capacity 16
  #:tags '(cpu high-memory))

;; Service discovery (from client)
(define svc (service-discover discovery "image-processor"))
;; => (#:host "gpu-srv1" #:port 9090 #:load 0.3)

;; Discover with constraints
(define svcs (service-discover-all discovery "image-processor"
  #:tags '(gpu)
  #:max-load 0.8))

;; Automatic load-balanced calls
(define result
  (service-call discovery "image-processor" 'resize
    image 800 600))
;; Picks least-loaded healthy instance automatically

;; Watch for changes
(service-watch! discovery "csv-cruncher"
  (lambda (event svc)
    (case event
      [(joined) (printf "New cruncher: ~a~n" svc)]
      [(left) (printf "Cruncher down: ~a~n" svc)]
      [(unhealthy) (printf "Cruncher sick: ~a~n" svc)])))
```

**Implementation:**
- Registry: centralized (simple) or gossip-based (resilient)
- Health checks: periodic TCP connect + custom health function
- TTL: services expire if not refreshed
- DNS-SD compatible naming (optional)
- Built on existing actor cluster + gRPC

---

### 9. `(std debug distributed-trace)` — Distributed Tracing

When a request flows across 5 servers, trace it end-to-end. OpenTelemetry-compatible spans.

```scheme
;; Start a trace
(with-trace "process-order" {:order-id 12345}
  ;; Span 1: validate (local)
  (with-span "validate"
    (validate-order order))

  ;; Span 2: charge (remote — trace context propagated automatically)
  (with-span "charge-payment"
    (remote-call payment-svc 'charge order))

  ;; Span 3: ship (remote)
  (with-span "ship-order"
    (remote-call shipping-svc 'ship order)))

;; Trace context flows through actor messages automatically
;; Each span records: start-time, end-time, parent-span, attributes

;; Collect traces
(trace-export! collector traces)
;; Outputs Jaeger/Zipkin-compatible format

;; Trace sampling
(set-trace-sampler! (rate-sampler 0.01))  ;; sample 1% of requests
```

**Implementation:**
- Thread-local trace context (trace-id, span-id, parent-span-id)
- Automatic propagation through actor send/dsend
- W3C Trace Context headers for HTTP
- Span collector with configurable export (stdout, file, network)
- Sampling strategies: always, never, rate-based, parent-based

---

### 10. `(std actor migrate)` — Live Actor Migration

Move a running actor (state + mailbox) from one node to another without downtime.

```scheme
;; Migrate actor to another node
(migrate-actor! actor-ref target-node)
;; 1. Pause actor on source (drain current message)
;; 2. Serialize state + pending mailbox via FASL
;; 3. Ship to target node over transport
;; 4. Restore actor on target, resume processing
;; 5. Update registry — all refs transparently redirect
;; 6. Future messages route to new location

;; Bulk migration (rebalancing)
(rebalance-actors! cluster
  #:strategy 'least-loaded
  #:max-concurrent 5)

;; Migration with handoff period (no message loss)
(migrate-actor! actor-ref target-node
  #:mode 'seamless       ;; buffer messages during transfer
  #:timeout 30000)       ;; abort if takes > 30s

;; Auto-migration on node shutdown
(on-node-drain node
  (lambda (actors)
    (distribute-actors! actors remaining-nodes)))
```

**Implementation:**
- Pause: set actor flag, let current behavior complete
- Serialize: FASL for state, drain mailbox to list, FASL that too
- Transfer: ship over existing transport layer (4-byte length + FASL)
- Restore: create actor on target, inject state + mailbox, register
- Redirect: update cluster registry, source node forwards stale messages
- Depends on: checkpointing (already exists), transport (already exists)

---

## Implementation Priority

Build in this order — each builds on the previous:

| Priority | Feature             | Module                          | Dependencies          | Effort     |
|----------|---------------------|---------------------------------|-----------------------|------------|
| **P1**   | Worker Pool         | `(std net worker-pool)`         | tcp, fasl, transport  | ~400 lines |
| **P1**   | Service Discovery   | `(std net discovery)`           | tcp, actor/registry   | ~300 lines |
| **P1**   | Task Queue          | `(std net task-queue)`          | worker-pool, fasl     | ~400 lines |
| **P2**   | Pub/Sub             | `(std net pubsub)`              | tcp, fasl             | ~350 lines |
| **P2**   | Code Shipping       | `(std net code-ship)`           | worker-pool, compile  | ~250 lines |
| **P2**   | Distributed Tracing | `(std debug distributed-trace)` | actor/protocol        | ~300 lines |
| **P3**   | DHT                 | `(std net dht)`                 | tcp, discovery        | ~500 lines |
| **P3**   | Raft Consensus      | `(std actor consensus)`         | tcp, fasl             | ~500 lines |
| **P3**   | Stream Processing   | `(std stream distributed)`      | pubsub, task-queue    | ~600 lines |
| **P3**   | Actor Migration     | `(std actor migrate)`           | checkpoint, transport | ~350 lines |

## The End Goal

```scheme
;; Your main program
(import (std net worker-pool)
        (std net discovery)
        (std net task-queue))

;; Find all available compute workers on the network
(define pool (discover-workers "compute-cluster"))

;; Ship 1000 tasks across all workers — automatic load balancing,
;; retry on failure, results collected in order
(define results
  (distributed-map pool
    (lambda (chunk)
      (import (std text csv))
      (analyze-data (csv-parse chunk)))
    (chunk-file "huge-dataset.csv" 1000)))

(printf "Processed ~a chunks across ~a workers~n"
  (length results) (pool-size pool))
```

That's the vision: write normal Scheme, run it across a fleet of jerboa servers.
