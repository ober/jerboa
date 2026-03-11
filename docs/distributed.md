# Distributed Actors in Jerboa

This document covers the distributed computing system built on top of Jerboa's actor model. It spans three libraries plus the unified facade:

| Library | Purpose |
|---|---|
| `(std actor transport)` | TCP wire protocol, serialization, connection pool |
| `(std actor cluster)` | Node membership, remote registry, distributed supervision |
| `(std actor crdt)` | Conflict-free replicated data types |
| `(std actor)` | Unified facade re-exporting all actor layers |

---

## Overview

Jerboa actors are ordinary Chez Scheme closures running in threads. The distributed layer extends local actors to span multiple OS processes or machines:

- **Transport** handles the TCP wire protocol. Messages are serialized with Chez's `fasl-write`/`fasl-read` and framed with a 4-byte big-endian length header. A cookie-based FNV-1a handshake authenticates connections.
- **Cluster** manages the set of live nodes and provides a remote actor registry. It also offers an in-process simulation mode useful for testing without real TCP sockets.
- **CRDTs** give you data structures that multiple nodes can update independently and merge without conflict. They are plain Scheme values — not actors — but are designed to be carried in actor messages.

---

## Transport Layer — `(std actor transport)`

### Startup Sequence

Before any remote `send` can work you must:

1. Call `(start-node! host port cookie)` to give this process its identity.
2. Call `(start-node-server! port)` to accept inbound connections.
3. Wire the transport into the core layer:
   ```scheme
   (set-remote-send-handler!
     (lambda (actor msg)
       (transport-remote-send! actor msg)))
   ```

### Exported Symbols

#### `(start-node! host port cookie)` → `string`

Registers this process as a cluster node. Returns the node-id string `"host:port"`. Must be called before making any remote sends.

- `host` — string, e.g. `"127.0.0.1"` or `"myhost.example.com"`
- `port` — exact integer
- `cookie` — shared secret string; peers must use the same value

```scheme
(import (std actor transport))
(start-node! "127.0.0.1" 9000 "secret")
;; => "127.0.0.1:9000"
```

#### `(current-node-id)` → `string` or `#f`

Returns the node-id set by `start-node!`, or `#f` if not yet initialized.

#### `(start-node-server! listen-port)`

Starts a TCP accept loop in a background thread. For each incoming connection, spawns another thread that performs the cookie handshake then dispatches inbound `(send actor-id payload)` frames to local actors via `lookup-local-actor`.

Returns immediately; the server runs until the process exits or `transport-shutdown!` is called.

#### `(make-remote-actor-ref id node-id)` → `actor-ref`

Creates an actor reference pointing to actor `id` on the remote node `node-id` (a `"host:port"` string). The returned ref has no local mailbox; passing it to `send` routes through the remote-send handler.

```scheme
(define remote-worker
  (make-remote-actor-ref 42 "10.0.0.2:9001"))
(send remote-worker '(do-work some-data))
```

#### `(transport-remote-send! actor msg)`

The implementation you install via `set-remote-send-handler!`. Obtains (or opens) a pooled TCP connection to the actor's node, then writes a framed `(send actor-id msg)` envelope. On any I/O error it drops the connection from the pool and re-raises the exception so the caller can decide how to handle it.

#### `(drop-connection! node-id)`

Removes a node's connection from the pool, closing the socket. The next `send` to that node will open a fresh connection. Useful after detecting a network partition.

#### `(transport-shutdown!)`

Closes all pooled connections gracefully. Call this before process exit.

#### `(message->bytes msg)` → `bytevector`

Serializes `msg` to a framed bytevector: `[4-byte BE length][fasl body]`. Exposed for testing.

#### `(bytes->message frame)` → `any`

Deserializes a framed bytevector back to a Scheme value. Exposed for testing. Signals an error if the bytevector is shorter than 4 bytes.

### Serialization

Messages are serialized with Chez Scheme's built-in `fasl-write` / `fasl-read`. This means:

- Any `fasl`-serializable value travels over the wire: numbers, strings, symbols, pairs, vectors, bytevectors, booleans.
- Procedures and ports **cannot** be serialized; do not put them in messages.
- Actor refs serialized this way become opaque values on the remote end — use `make-remote-actor-ref` explicitly to create references that the remote side can send back to.

### Wire Protocol

```
Connection lifecycle:
  client → server: (hello "our-node-id" fnv1a-hash)
  server → client: (ok "their-node-id")     ; on success
  server → client: (error "reason")          ; on failure → connection closed

Message frames:
  [0..3] big-endian uint32: body length N
  [4..4+N-1] fasl-encoded body
  body shape for sends: (send local-actor-id payload)
```

The cookie hash is `FNV-1a("cookie:peer-node-id")`. For production use, replace this with an HMAC-SHA256 scheme — the comment in the source notes this explicitly.

---

## Cluster Management — `(std actor cluster)`

> **Note:** The current implementation is an **in-process simulation**. Nodes are Scheme records sharing memory rather than separate OS processes communicating over TCP. This makes the cluster APIs fully testable in a single process. To build a real multi-process cluster, combine this module with `(std actor transport)`.

### Exported Symbols

#### Node Management

##### `(start-node! name . opts)` → `node`

Creates and registers a new cluster node. Accepts keyword options:

| Keyword | Value | Meaning |
|---|---|---|
| `#:listen` | string | listen address (metadata only in simulation) |
| `#:cookie` | string | auth cookie (metadata only in simulation) |
| `#:seeds` | list | seed node addresses (metadata only in simulation) |

```scheme
(import (std actor cluster))
(define n1 (start-node! "node1" #:listen "127.0.0.1:9000"))
(define n2 (start-node! "node2" #:listen "127.0.0.1:9001"))
```

##### `(stop-node! node)`

Marks the node as dead, removes it from the cluster registry, and fires leave hooks.

##### `(node? x)` → `boolean`

Predicate.

##### `(node-name node)` → `string`

Returns the human-readable name given to `start-node!`.

##### `(node-id node)` → `symbol`

Returns the unique symbol identifier generated at startup (includes a timestamp).

##### `(node-alive? node)` → `boolean`

Returns `#t` until `stop-node!` is called.

##### `(current-node)` → `node` or `#f`

Returns the node currently associated with the running thread (set via the `*current-node*` parameter). Useful inside actors that need to know which node they are on.

#### Cluster Operations

##### `(cluster-join! node1 node2)`

Records both nodes as members of the same cluster. In the simulation, this just ensures both are in the global registry. In a real implementation this would trigger gossip to exchange membership lists.

##### `(cluster-leave! node)`

Equivalent to `(stop-node! node)`.

##### `(cluster-nodes)` → `list of node`

Returns all currently alive nodes.

##### `(cluster-node-by-name name)` → `node` or `#f`

Finds a live node by its string name. Returns `#f` if not found.

##### `(on-node-join hook)`

Registers a procedure `(lambda (node) ...)` called whenever a new node joins. Multiple hooks are allowed and run in LIFO order.

##### `(on-node-leave hook)`

Registers a procedure `(lambda (node) ...)` called whenever a node leaves.

#### Remote Actor Registry

Each node has a local name→actor table. These procedures let you publish and look up named actors across nodes.

##### `(remote-register! node name actor-ref)`

Associates `name` (a symbol) with `actor-ref` in `node`'s registry. No-op if the node is not alive.

##### `(remote-unregister! node name)`

Removes the name from `node`'s registry.

##### `(remote-whereis node name)` → `actor-ref` or `#f`

Looks up `name` in a specific node's registry. Returns `#f` if the node is dead or the name is not registered.

##### `(whereis/any name)` → `actor-ref` or `#f`

Searches all alive nodes for a registered name. Returns the first match found, or `#f`. Useful when you don't care which node hosts the actor.

#### Distributed Supervision

A distributed supervisor places worker actors across cluster nodes according to a placement strategy. When a node fails, it reschedules the workers that were on that node onto surviving nodes.

##### `(make-distributed-supervisor name strategy)` → `distributed-supervisor`

Creates a supervisor record. `strategy` is one of the three built-in placement strategy procedures or a custom `(lambda (nodes dsup id) → node)`.

##### `(distributed-supervisor? x)` → `boolean`

Predicate.

##### `(dsupervisor-start-child! dsup id proc . opts)` → `actor-ref` or `#f`

Starts a child actor:

- Applies the placement strategy to pick a target node.
- Calls `(fork-thread proc)` to simulate starting the actor on that node.
- Registers the actor's id in the target node's registry.
- `opts` optionally provides the restart type: `'permanent` (default), `'transient`, or `'temporary`.

Returns the actor-ref, or `#f` if no nodes are available.

##### `(dsupervisor-which-children dsup)` → `list`

Returns a list of `(id node-name restart-type)` triples describing all managed children.

##### `(dsupervisor-stop-child! dsup id)`

Stops and unregisters the child with the given id.

##### `(dsupervisor-handle-node-failure! dsup failed-node)`

Call this when you detect that `failed-node` has gone down (e.g. from an `on-node-leave` hook). Restarts all `permanent` and `transient` children that were on the failed node by placing them on the remaining nodes via the placement strategy. `temporary` children are not restarted.

#### Placement Strategies

##### `strategy/round-robin`

A procedure `(nodes dsup id) → node`. Rotates through nodes in order, using a global counter protected by a mutex.

##### `strategy/least-loaded`

Picks the node with the fewest actors currently registered in its local registry.

##### `strategy/local-first`

Prefers placing on `(current-node)` if it is in the nodes list, falling back to `strategy/round-robin` otherwise.

---

## CRDTs — `(std actor crdt)`

CRDTs (Conflict-Free Replicated Data Types) are mutable Scheme objects designed for concurrent multi-node use. The merge operations are:

- **Commutative** — `merge(a, b) = merge(b, a)`
- **Associative** — `merge(a, merge(b, c)) = merge(merge(a, b), c)`
- **Idempotent** — `merge(a, a) = a`

This means you can ship a CRDT state to any node in any order, merge it any number of times, and always arrive at the same result. No coordination protocol is required.

All CRDT types are thread-safe: every mutating operation holds an internal mutex.

### G-Counter (Grow-Only Counter)

A counter that can only be incremented. Each node maintains its own component; the global value is the sum of all components. Merge takes the pairwise maximum.

```scheme
(make-gcounter node-id)         ; node-id is a symbol identifying this replica
(gcounter? x)
(gcounter-increment! gc)        ; increment by 1
(gcounter-increment! gc amount) ; increment by amount
(gcounter-value gc)             ; sum of all components → exact integer
(gcounter-merge! target other)  ; merge other into target in place
(gcounter-state gc)             ; → alist of (node-id . count)
```

### PN-Counter (Positive-Negative Counter)

Supports both increment and decrement by maintaining two G-Counters internally. Value = positive − negative.

```scheme
(make-pncounter node-id)
(pncounter? x)
(pncounter-increment! pnc)        ; increment by 1
(pncounter-increment! pnc amount)
(pncounter-decrement! pnc)        ; decrement by 1
(pncounter-decrement! pnc amount)
(pncounter-value pnc)             ; → possibly negative integer
(pncounter-merge! target other)
```

### G-Set (Grow-Only Set)

Elements can only be added; removal is not supported. Merge is set union.

```scheme
(make-gset)
(gset? x)
(gset-add! gs elem)
(gset-member? gs elem)       ; → boolean
(gset-value gs)              ; → list of elements
(gset-merge! target other)
```

### OR-Set (Observed-Remove Set)

Supports add and remove with correct semantics across concurrent updates. Each `add` attaches a unique tag; `remove` only removes tags observed at the time of the remove. If two nodes concurrently add the same element then one removes it, the add wins on merge.

```scheme
(make-orset)
(orset? x)
(orset-add! os elem)
(orset-remove! os elem)
(orset-member? os elem)     ; → boolean
(orset-value os)            ; → list of elements currently in the set
(orset-merge! target other)
```

### LWW-Register (Last-Write-Wins Register)

Stores a single value with a timestamp. On merge, the higher timestamp wins.

```scheme
(make-lww-register)
(lww-register? x)
(lww-register-set! r val)           ; uses current-time as timestamp
(lww-register-set! r val timestamp) ; explicit timestamp (inexact number)
(lww-register-value r)              ; current value
(lww-register-timestamp r)          ; current timestamp
(lww-register-merge! target other)
```

Concurrent writes to the same timestamp are non-deterministic (the existing value wins). Use `make-mv-register` if you need to preserve all concurrent values.

### MV-Register (Multi-Value Register)

Uses vector clocks to track causality. When two writes are concurrent (neither happened-before the other), both values are preserved. Reading returns a list of all concurrent values; the application must reconcile them.

```scheme
(make-mv-register)
(mv-register? x)
(mv-register-set! r node-id val)   ; write val on behalf of node-id
(mv-register-values r)             ; → list of concurrent values
(mv-register-merge! target other)
```

### Vector Clocks

Vector clocks underpin the MV-Register and are exposed for advanced use.

```scheme
(make-vclock)
(vclock? x)
(vclock-increment! vc node-id)      ; increment this node's component
(vclock-get vc node-id)             ; → integer count for node-id
(vclock-merge! target other)        ; take pairwise max in place
(vclock-happens-before? a b)        ; → boolean: a causally precedes b?
(vclock-concurrent? a b)            ; → boolean: neither precedes the other?
(vclock->alist vc)                  ; → alist of (node-id . count)
```

---

## Actor Facade — `(std actor)`

Import `(std actor)` to get all local actor functionality in one go. For remote sends, additionally import `(std actor transport)`.

```scheme
(import (std actor))
```

### Core Actor API

#### `(spawn-actor behavior)` → `actor-ref`
#### `(spawn-actor behavior name)` → `actor-ref`

Creates a new actor with the given behavior procedure `(lambda (msg) ...)`. The actor starts in idle state; the first `send` triggers execution. Optionally supply a `name` symbol for debugging and registry use.

#### `(spawn-actor/linked behavior)` → `actor-ref`
#### `(spawn-actor/linked behavior name)` → `actor-ref`

Like `spawn-actor` but creates a bidirectional link between the spawning actor and the new child. When either dies, the other receives an `(EXIT dead-id reason)` message.

#### `(send actor msg)`

Delivers `msg` to the actor's mailbox. If the actor is local and idle, schedules it immediately. If the actor is dead, calls the dead-letter handler. If the actor is remote, routes through the handler installed by `set-remote-send-handler!`.

#### `(self)` → `actor-ref` or `#f`

Returns the current actor's reference. Returns `#f` when called from outside any actor behavior.

#### `(actor-id)` → `integer` or `#f`

Returns the numeric id of the current actor.

#### `(actor-alive? actor)` → `boolean`

Returns `#t` if the actor has not yet died.

#### `(actor-kill! actor)`

Forcefully terminates the actor, setting its exit reason to `'killed`. Delivers `(EXIT id 'killed)` to linked actors and `(DOWN tag id 'killed)` to monitors.

#### `(actor-wait! actor)`

Blocks the calling thread until the actor's state becomes `'dead`. Useful in tests and at shutdown.

#### `(actor-ref? x)` → `boolean`
#### `(actor-ref-id actor)` → `integer`
#### `(actor-ref-node actor)` → `string` or `#f`
#### `(actor-ref-name actor)` → `symbol` or `#f`

Accessors. `actor-ref-node` returns `#f` for local actors and a `"host:port"` string for remote refs.

#### `(set-dead-letter-handler! proc)`

Installs `(lambda (msg dest-actor) ...)` as the handler for messages sent to dead actors. The default handler prints to `(current-error-port)`.

#### `(set-remote-send-handler! proc)`

Installs `(lambda (actor msg) ...)` as the handler for sends to remote actors. Call with `transport-remote-send!` from `(std actor transport)`.

#### `(lookup-local-actor id)` → `actor-ref` or `#f`

Looks up a local actor by its numeric id. Used by the transport layer to dispatch inbound messages.

#### `(make-remote-actor-ref id node-id)` → `actor-ref`

Creates a stub actor reference pointing to `id` on `node-id`. See the transport layer section.

### Protocol API

#### `(defprotocol name clause ...)` — macro

Defines a typed message protocol. Each clause `(msg-name field ...)` generates:

- A sealed record type `name:msg-name` with the given fields.
- A tell helper `name:msg-name!` that sends the message.
- If the clause ends with `->`, an ask helper `name:msg-name?!` that blocks for a reply.

```scheme
(defprotocol counter
  (increment amount)
  (get-value -> result))

;; Generated:
;;   (counter:increment! actor amount)      ; tell
;;   (counter:get-value?! actor)            ; ask — blocks for reply
;;   counter:increment? counter:get-value?  ; predicates
```

#### `(ask actor-ref msg)` → `future`

Sends `msg` wrapped in an ask envelope and returns a future. The actor behavior must call `(reply value)` to complete the future. Non-blocking on the caller's side.

#### `(ask-sync actor-ref msg)` → `value`
#### `(ask-sync actor-ref msg timeout-secs)` → `value`

Like `ask` but blocks until the reply arrives. Polls every 10 ms when a timeout is given; raises an error if the timeout elapses.

#### `(tell actor-ref msg)`

Alias for `send`.

#### `(reply value)`

Inside a behavior invoked via `ask`, sends `value` back to the caller. Raises an error if called outside an ask context.

#### `(reply-to)` → `actor-ref` or `#f`

Returns the actor that sent the current ask message.

#### `(with-ask-context msg body-proc)` — macro

Unwraps an ask envelope if present and sets up the reply context, then calls `(body-proc actual-msg)`. If `msg` is not an ask envelope, calls `body-proc` directly. Use this in behaviors that must handle both fire-and-forget and ask messages.

### Supervisor API

#### `(make-child-spec id start-thunk restart shutdown type)` → `child-spec`

Constructs a child specification:

| Parameter | Type | Values |
|---|---|---|
| `id` | symbol | unique within the supervisor |
| `start-thunk` | `(lambda () → actor-ref)` | called to spawn the child |
| `restart` | symbol | `'permanent`, `'transient`, `'temporary` |
| `shutdown` | `'brutal-kill` or number | graceful shutdown timeout in seconds |
| `type` | symbol | `'worker` or `'supervisor` |

#### `(start-supervisor strategy child-specs)` → `actor-ref`
#### `(start-supervisor strategy child-specs max-restarts)` → `actor-ref`
#### `(start-supervisor strategy child-specs max-restarts period-secs)` → `actor-ref`

Starts a supervisor actor. `strategy` is one of `'one-for-one`, `'one-for-all`, `'rest-for-one`. Default restart intensity: 10 restarts per 5 seconds.

- `one-for-one` — restart only the failed child.
- `one-for-all` — restart all children when any one fails.
- `rest-for-one` — restart the failed child and all children started after it.

#### `(supervisor-which-children sup)` → `list`

Returns `((id status actor-ref) ...)` where `status` is `'running`, `'stopped`, or `'dead`.

#### `(supervisor-count-children sup)` → `(values total active)`

Returns total child count and count of running children.

#### `(supervisor-terminate-child! sup id)`

Stops the named child gracefully (or with `brutal-kill`).

#### `(supervisor-restart-child! sup id)` → `'ok` or `'not-found`

Restarts a stopped child. Only works if the child is in `'stopped` state.

#### `(supervisor-start-child! sup spec)` → `actor-ref`

Dynamically adds and starts a new child from a child spec.

#### `(supervisor-delete-child! sup id)`

Stops and permanently removes a child from the supervisor.

### Registry API

#### `(start-registry!)` → `actor-ref`

Starts the global actor name registry. Must be called once at startup.

#### `(register! name actor-ref)`

Registers `actor-ref` under `name` (a symbol). Automatically unregisters when the actor dies.

#### `(unregister! name)`

Removes a name from the registry.

#### `(whereis name)` → `actor-ref` or `#f`

Looks up a name in the local registry.

#### `(registered-names)` → `list of symbol`

Returns all currently registered names.

#### `registry-actor`

The actor-ref of the registry process itself.

### Scheduler API

#### `(make-scheduler n-workers)` → `scheduler`
#### `(scheduler-start! sched)`
#### `(scheduler-stop! sched)`
#### `(scheduler-submit! sched thunk)`
#### `(scheduler-worker-count sched)` → `integer`
#### `(current-scheduler)` → `scheduler` or `#f`
#### `(default-scheduler)` → `scheduler`
#### `(cpu-count)` → `integer`
#### `(set-actor-scheduler! submit-proc)`

By default actors run 1:1 with OS threads. The scheduler switches to M:N mode: a fixed pool of worker threads runs actor tasks cooperatively. Call `(set-actor-scheduler! (scheduler-submit! my-sched))` after starting a scheduler to activate M:N dispatch.

---

## Complete Examples

### Example 1: Two-Node Cluster Communicating

```scheme
(import (chezscheme)
        (std actor)
        (std actor transport))

;; --- Node A (runs on 127.0.0.1:9000) ---
(define (run-node-a)
  (start-node! "127.0.0.1" 9000 "shared-secret")
  (start-node-server! 9000)
  (set-remote-send-handler!
    (lambda (actor msg) (transport-remote-send! actor msg)))

  ;; Spawn a local echo actor
  (define echo
    (spawn-actor
      (lambda (msg)
        (display "Node A received: ")
        (display msg)
        (newline)
        (flush-output-port (current-output-port)))))

  ;; Make it findable across the cluster
  (start-registry!)
  (register! 'echo echo)
  (display "Node A running, echo registered\n")
  (flush-output-port (current-output-port))

  ;; Keep alive
  (let loop ()
    (sleep (make-time 'time-duration 0 1))
    (loop)))

;; --- Node B (runs on 127.0.0.1:9001) ---
(define (run-node-b)
  (start-node! "127.0.0.1" 9001 "shared-secret")
  (start-node-server! 9001)
  (set-remote-send-handler!
    (lambda (actor msg) (transport-remote-send! actor msg)))

  ;; Reference the echo actor on node A
  ;; Actor ids are assigned sequentially; in a real system you'd look up
  ;; the id from a naming service.  Here we use 0 as a known id.
  (define remote-echo (make-remote-actor-ref 0 "127.0.0.1:9000"))

  (send remote-echo "hello from node B")
  (display "Node B sent message\n")
  (flush-output-port (current-output-port))
  (transport-shutdown!))
```

### Example 2: Distributed Counter Using G-Counter CRDT

This example shows two actors sharing state through CRDT merges. In a real cluster you would send the CRDT state in messages and merge on receipt.

```scheme
(import (chezscheme)
        (std actor)
        (std actor crdt))

;; Two replicas with their own node identities
(define replica-a (make-gcounter 'node-a))
(define replica-b (make-gcounter 'node-b))

;; Independent increments on each replica
(gcounter-increment! replica-a 5)
(gcounter-increment! replica-a 3)
(gcounter-increment! replica-b 7)

;; Each replica sees only its local count
(display (gcounter-value replica-a))  ; => 8
(display (gcounter-value replica-b))  ; => 7

;; Simulate exchanging state: A sends its state to B, B merges
(gcounter-merge! replica-b replica-a)

;; After merge, B has the global total
(display (gcounter-value replica-b))  ; => 15  (8 + 7)

;; A also merges B's state
(gcounter-merge! replica-a replica-b)
(display (gcounter-value replica-a))  ; => 15  (converged)


;; Wrap in actors for async updates
(define (make-counter-actor node-id)
  (let ([gc (make-gcounter node-id)])
    (spawn-actor
      (lambda (msg)
        (cond
          [(eq? (car msg) 'increment)
           (gcounter-increment! gc (cadr msg))]
          [(eq? (car msg) 'merge)
           (gcounter-merge! gc (cadr msg))]
          [(eq? (car msg) 'query)
           (reply (gcounter-value gc))]
          [(eq? (car msg) 'state)
           (reply gc)])))))

(define counter-a (make-counter-actor 'node-a))
(define counter-b (make-counter-actor 'node-b))

(send counter-a '(increment 10))
(send counter-b '(increment 20))

;; Exchange states to converge
(let ([state-a (ask-sync counter-a '(state))])
  (send counter-b (list 'merge state-a)))

(display (ask-sync counter-b '(query)))  ; => 30
```

### Example 3: Fault-Tolerant Service with Supervision

```scheme
(import (chezscheme)
        (std actor))

(start-registry!)

;; A worker that can crash
(define (make-database-worker)
  (spawn-actor
    (lambda (msg)
      (with-ask-context msg
        (lambda (actual)
          (cond
            [(equal? (car actual) 'query)
             (reply (format "result for: ~a" (cadr actual)))]
            [(equal? (car actual) 'crash)
             (error 'database-worker "simulated crash")]
            [else
             (reply 'unknown-command)]))))
    'db-worker))

;; Build a supervision tree
(define db-spec
  (make-child-spec
    'database                    ; id
    make-database-worker         ; start-thunk
    'permanent                   ; always restart on crash
    5                            ; 5-second graceful shutdown
    'worker))

(define supervisor
  (start-supervisor 'one-for-one (list db-spec)
    5   ; max 5 restarts
    10  ; per 10 seconds
    ))

;; Find the worker through the registry
(register! 'database (car (map caddr (supervisor-which-children supervisor))))

;; Normal operation
(let ([worker (whereis 'database)])
  (display (ask-sync worker '(query "users")))
  (newline))

;; Force a crash — supervisor will restart automatically
(let ([worker (whereis 'database)])
  (send worker '(crash)))

;; Give the supervisor a moment to restart the worker
(sleep (make-time 'time-duration 100000000 0))

;; After restart, the worker is back
(let ([worker (car (map caddr (supervisor-which-children supervisor)))])
  (display (ask-sync worker '(query "orders")))
  (newline))
```

### Example 4: Named Actor Registry Across Nodes

```scheme
(import (chezscheme)
        (std actor)
        (std actor cluster))

;; Simulate two nodes in-process
(define node-a (start-node! "alpha"))
(define node-b (start-node! "beta"))
(cluster-join! node-a node-b)

;; Register hook to print membership changes
(on-node-join  (lambda (n) (format #t "~a joined~%" (node-name n))))
(on-node-leave (lambda (n) (format #t "~a left~%"  (node-name n))))

;; Register actors by name on specific nodes
(define service-actor
  (spawn-actor
    (lambda (msg)
      (with-ask-context msg
        (lambda (actual) (reply (list 'echo actual)))))
    'service))

(remote-register! node-a 'my-service service-actor)

;; Look up on the specific node
(let ([ref (remote-whereis node-a 'my-service)])
  (display ref)
  (newline))

;; Look up on any node — useful when you don't know placement
(let ([ref (whereis/any 'my-service)])
  (when ref
    (display (ask-sync ref '(ping)))
    (newline)))

;; Simulate node failure and distributed supervisor recovery
(define dsup (make-distributed-supervisor "main" strategy/round-robin))

(dsupervisor-start-child! dsup 'worker-1
  (lambda ()
    (let loop ()
      (sleep (make-time 'time-duration 0 1))
      (loop))))

(display (dsupervisor-which-children dsup))
(newline)

;; Simulate node-a going down — workers are restarted on node-b
(stop-node! node-a)
(dsupervisor-handle-node-failure! dsup node-a)

(display (dsupervisor-which-children dsup))
(newline)
```

---

## Notes and Limitations

- **Transport authentication** uses FNV-1a, which is fast but not cryptographically secure. The source file contains a comment suggesting replacement with HMAC-SHA256 for production.
- **Cluster** is currently an in-process simulation. There is no gossip protocol, no partition detection, and no membership persistence across process restarts.
- **CRDT merges are destructive** (`merge! target other` modifies `target` in place). If you need immutable snapshots, copy the state out first (e.g. via `gcounter-state`).
- **MV-Register** can accumulate unbounded concurrent values if `mv-register-set!` is called from many nodes without causal ordering. Applications should read and resolve the values list periodically.
- **fasl serialization** is Chez-specific and not interoperable with other Scheme implementations or languages.
