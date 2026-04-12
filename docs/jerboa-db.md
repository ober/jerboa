# Jerboa-DB: Datomic Without the JVM

**Goal:** A fully-featured Datomic clone built entirely on Jerboa, using LevelDB for
index storage and DuckDB for analytics.  Single binary, embeddable, distributed,
with a Datalog query engine and immutable time-travel over all data.

**Status:** 2026-04-12 — All 8 phases implemented (31 files, ~6200 lines, 34/34 tests passing)

---

## Why Build This

Datomic is arguably the most innovative database of the last decade.  Its core
ideas — immutable facts, time-travel, Datalog queries, separation of reads and
writes, entity-attribute-value modeling — changed how Clojure developers think
about data.

But Datomic has problems:

1. **JVM-only.** Requires a running JVM peer process consuming 2-8GB of RAM.
2. **Proprietary.** Datomic Pro is closed-source.  Datomic Cloud is AWS-only.
3. **Complex deployment.** Transactor + peer + storage backend (DynamoDB/PostgreSQL/Cassandra).
4. **Expensive.** Datomic Pro licenses cost thousands per year.
5. **No embeddable mode.** Can't embed Datomic in a CLI tool, edge device, or serverless function.

The open-source alternatives (DataScript, XTDB, Datahike, Datalevin) each make
trade-offs:

| System | Language | Storage | Datalog | Time-Travel | Distributed | Embeddable |
|---|---|---|---|---|---|---|
| Datomic Pro | JVM | DynamoDB/SQL | Yes | Yes | Yes | No |
| XTDB v2 | JVM | Arrow/Parquet | Yes | Yes | Yes | No |
| DataScript | Clojure/JS | In-memory | Yes | No | No | Yes (JS) |
| Datahike | JVM | Pluggable | Yes | Partial | No | No |
| Datalevin | JVM | LMDB | Yes | No | No | No |
| **Jerboa-DB** | **Native** | **LevelDB + DuckDB** | **Yes** | **Yes** | **Yes** | **Yes** |

Jerboa-DB fills a gap that doesn't exist today: a **native, embeddable,
distributed, time-traveling Datalog database** that ships as a single binary and
requires zero external infrastructure.

### Why Jerboa Is the Right Platform

This isn't just "rewrite Datomic in Scheme."  Jerboa has building blocks that
make this project tractable in a way it wouldn't be in Go, Rust, or Python:

| Datomic Concept | Jerboa Building Block | Status |
|---|---|---|
| Immutable fact store | `(std mvcc)` — MVCC with time-travel | Exists |
| EAVT/AEVT/VAET indices | `(std db leveldb)` — LSM tree with bloom filters | Exists |
| Datalog query engine | `(std datalog)` — semi-naive evaluation | Exists |
| Logic variable unification | `(std logic)` — full miniKanren | Exists |
| Persistent collections | `(std data pmap)`, `(std pvec)`, `(std pset)` | Exists |
| Transaction log | `(std event-source)` — immutable event log | Exists |
| Schema validation | `(std schema)` — composable validators | Exists |
| Serialization (wire format) | `(std text edn)`, `(std text msgpack)`, `(std fasl)` | Exists |
| Peer caching | `(std misc lru-cache)` — O(1) LRU | Exists |
| Concurrent reads | `(std concur stm)` — optimistic transactions | Exists |
| Distributed consensus | `(std raft)` — leader election + log replication | Exists |
| Replicated state | `(std actor crdt)` — OR-Set, LWW-Register, etc. | Exists |
| Content addressing | `(std content-address)` — hash-based storage | Exists |
| Analytical queries | `(std db duckdb)` — columnar OLAP engine | Exists |
| Connection pooling | `(std db conpool)` — thread-safe pool | Exists |
| Actor supervision | `(std actor)` — OTP-style fault tolerance | Exists |
| HTTP API server | `(std net fiber-httpd)` — fiber-native HTTP | Exists |
| Binary encoding | `(std text cbor)`, `(std text msgpack)` | Exists |
| Compression | `(std compress zlib)` — gzip for segment files | Exists |
| UUID generation | `(std misc uuid)` — v4 random UUIDs | Exists |
| Sorted indices | `(std misc rbtree)`, `(std ds sorted-map)` | Exists |
| File-backed B+ tree | `(std mmap-btree)` — transactional | Exists |
| Memory-mapped I/O | `(std os mmap)` — zero-copy file access | Exists |
| Relational algebra | `(std misc relation)` — join, project, select | Exists |
| Protocol dispatch | `(std protocol)` — Clojure-style protocols | Exists |
| Transducer pipelines | `(std transducer)` — streaming transforms | Exists |
| Lazy sequences | `(std lazy)`, `(std misc lazy-seq)` | Exists |

Every row in that table is code that already exists and is tested.  The work is
**composition and integration**, not building from scratch.

---

## Datomic Concepts: A Primer

For readers unfamiliar with Datomic, here are the core concepts that Jerboa-DB
will implement:

### The Datom

The fundamental unit of data is a **datom** — a 5-tuple:

```
[entity  attribute  value  transaction  added?]
[  E        A         V       T          op  ]
```

- **Entity (E):** A unique identifier (integer or tempid).  Like a row ID, but
  entities can have any number of attributes.
- **Attribute (A):** A keyword naming the property.  `:person/name`, `:order/total`.
  Attributes have schemas: type, cardinality, uniqueness, indexing.
- **Value (V):** The data.  Strings, numbers, booleans, refs (pointers to other
  entities), instants (timestamps), UUIDs, bytes.
- **Transaction (T):** The transaction ID that asserted this datom.  Transactions
  are themselves entities with metadata (timestamp, author, etc.).
- **Added? (op):** Boolean.  `true` = assert, `false` = retract.  Retracting a
  datom doesn't delete it — it adds a new datom recording the retraction.

### Immutability and Accretion

Datomic never updates or deletes data.  It only **adds new facts**.  Changing
`:person/name` from "Alice" to "Alicia" means:

```
[42 :person/name "Alice"  1000 true ]    ;; original assertion
[42 :person/name "Alice"  1005 false]    ;; retraction
[42 :person/name "Alicia" 1005 true ]    ;; new assertion
```

All three datoms are stored forever.  The "current" database is the most recent
true assertion.  But you can always ask "what was the database at T=1000?" and
get back "Alice."

### Indices

Datomic maintains four covering indices over all datoms:

| Index | Sort Order | Use Case |
|---|---|---|
| **EAVT** | Entity → Attribute → Value → Tx | "All attributes of entity 42" |
| **AEVT** | Attribute → Entity → Value → Tx | "All entities with :person/name" |
| **AVET** | Attribute → Value → Entity → Tx | "Entity where :email = 'a@b.com'" (unique lookup) |
| **VAET** | Value → Attribute → Entity → Tx | "All entities referencing entity 42" (reverse refs) |

Each index stores the same datoms in a different sort order.  Every datom
appears in EAVT and AEVT; AVET is populated only for attributes with
`:db/index true`; VAET is populated only for `:db.type/ref` attributes.

### Datalog Queries

Queries use Datalog, a declarative logic language:

```clojure
;; Find all people older than 30
[:find ?name ?age
 :where [?e :person/name ?name]
        [?e :person/age  ?age]
        [(> ?age 30)]]

;; Find all orders for a person
[:find ?order-id ?total
 :in $ ?person-name
 :where [?p :person/name ?person-name]
        [?o :order/person ?p]
        [?o :order/id ?order-id]
        [?o :order/total ?total]]
```

Each clause `[?e :attr ?v]` is a pattern match against the datom store.  The
query planner chooses which index to scan based on which positions are bound.

### Transactions

Transactions are atomic batches of assertions and retractions:

```clojure
[{:db/id "tempid-alice"
  :person/name "Alice"
  :person/age 30}
 {:db/id "tempid-bob"
  :person/name "Bob"
  :person/age 25}
 [:db/retract 42 :person/email "old@example.com"]]
```

Each transaction:
1. Gets a monotonically increasing transaction ID (T)
2. Resolves tempids to permanent entity IDs
3. Validates against the schema
4. Writes datoms to all relevant indices
5. Records itself as an entity with `:db/txInstant`

### Database Values (db)

A **database value** is an immutable snapshot at a point in time.  Queries run
against a db value, not the live transactor.  This means:

- Queries never block writes
- Long-running analytical queries see a consistent snapshot
- You can pass db values across threads, serialize them, compare them

### Pull API

The pull API retrieves entity data as nested maps:

```clojure
(pull db [:person/name :person/age {:person/friends [:person/name]}] entity-id)
;; => {:person/name "Alice"
;;     :person/age 30
;;     :person/friends [{:person/name "Bob"} {:person/name "Carol"}]}
```

This replaces the need for ORMs.  The shape of the data is specified at query
time, not in a schema mapping.

### History and As-Of

```clojure
(d/as-of db tx-1000)          ;; db as it was at transaction 1000
(d/since db tx-1000)           ;; only datoms added after tx 1000
(d/history db)                 ;; all datoms, including retracted ones
```

---

## Architecture

```
                          ┌──────────────────────┐
                          │   Client / REPL       │
                          │   (std csp clj)       │
                          └──────────┬───────────┘
                                     │  Datalog query / transact
                                     ▼
                     ┌───────────────────────────────┐
                     │         Peer (Connection)      │
                     │                                │
                     │  ┌────────────┐ ┌───────────┐ │
                     │  │ Query      │ │ Pull API  │ │
                     │  │ Engine     │ │           │ │
                     │  │ (Datalog)  │ │ (entity   │ │
                     │  │            │ │  walking) │ │
                     │  └─────┬──────┘ └─────┬─────┘ │
                     │        │              │        │
                     │        ▼              ▼        │
                     │  ┌────────────────────────┐   │
                     │  │   Index Manager         │   │
                     │  │                         │   │
                     │  │  EAVT  AEVT  AVET VAET │   │
                     │  │  (LevelDB databases)    │   │
                     │  └────────────┬────────────┘   │
                     │               │                │
                     │  ┌────────────┴────────────┐   │
                     │  │   Cache Layer            │   │
                     │  │   (LRU + object cache)   │   │
                     │  └────────────┬────────────┘   │
                     └───────────────┼────────────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    ▼                ▼                ▼
           ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
           │  Transaction  │ │   LevelDB    │ │   DuckDB     │
           │  Log          │ │              │ │              │
           │  (append-only │ │  4 sorted    │ │  Analytical  │
           │   segment     │ │  indices     │ │  replica     │
           │   files)      │ │  (LSM tree   │ │  (columnar,  │
           │               │ │   + bloom)   │ │   Parquet,   │
           │               │ │              │ │   SQL)       │
           └──────────────┘ └──────────────┘ └──────────────┘
```

### Component Roles

**Peer (Connection):** The client-facing object.  Holds a reference to the
current db value, submits transactions, runs queries.  Multiple peers can share
the same storage (read replicas) or operate embedded in-process.

**Transaction Log:** An append-only sequence of all transactions.  Each entry
contains the tx-id, timestamp, and the set of datoms (assertions + retractions).
Stored as segment files using MessagePack or FASL encoding.  This is the
**source of truth** — indices can always be rebuilt from the log.

**LevelDB Indices:** Four separate LevelDB databases (EAVT, AEVT, AVET, VAET),
each storing datoms sorted in the corresponding order.  LevelDB provides:
- Fast reads via LSM tree with bloom filters (10-bit)
- 64MB LRU cache per index for hot data
- Compression for reduced disk footprint
- Iterator-based range scans (essential for index lookups)
- FASL-encoded datom values for fast Scheme deserialization

**DuckDB Analytical Replica:** A columnar copy of the datom store for analytical
queries.  When you need `GROUP BY`, `WINDOW`, or aggregation over millions of
datoms, DuckDB handles it with vectorized execution.  The replica is
asynchronously updated from the transaction log.  This is the "bring your own
analytics engine" story that Datomic lacks.

**Cache Layer:** An LRU cache over LevelDB reads.  Hot entities stay in memory as
Scheme objects (persistent maps).  Cache invalidation is trivial because data is
immutable — new transactions only add entries, they never modify existing ones.

---

## Data Model

### Datom Representation

```scheme
;; A datom is a 5-element record
(defstruct datom (e a v tx added?))

;; Entity IDs are 64-bit integers
;; Attribute IDs are interned keywords → integer lookup
;; Values are typed (see schema)
;; Transaction IDs are monotonically increasing integers
;; added? is a boolean
```

### Datom Encoding for LevelDB

LevelDB keys and values are bytevectors.  Datoms are encoded as fixed-width keys
so that LevelDB's default bytewise comparison gives the correct sort order:

```
EAVT key: [E:8 bytes][A:4 bytes][V-hash:8 bytes][T:8 bytes]  = 28 bytes
AEVT key: [A:4 bytes][E:8 bytes][V-hash:8 bytes][T:8 bytes]  = 28 bytes
AVET key: [A:4 bytes][V-hash:8 bytes][E:8 bytes][T:8 bytes]  = 28 bytes
VAET key: [V-hash:8 bytes][A:4 bytes][E:8 bytes][T:8 bytes]  = 28 bytes
```

Values that fit in 8 bytes (integers, booleans, instants) are encoded inline.
Larger values (strings, bytes, refs) are stored as FASL-encoded LevelDB values
alongside the key, and the 8-byte FNV-1a hash is stored in the index key.

The `added?` flag is encoded in the high bit of the transaction ID:
- `T` with high bit 0 = assertion
- `T` with high bit 1 = retraction

This keeps keys fixed-width and lets cursor scans naturally interleave
assertions and retractions in transaction order.

### Schema Attributes

Every attribute has a schema definition, which is itself stored as datoms on a
schema entity:

```scheme
;; Define a schema attribute
(transact! conn
  [{:db/ident       :person/name
    :db/valueType   :db.type/string
    :db/cardinality :db.cardinality/one
    :db/doc         "A person's full name"}

   {:db/ident       :person/friends
    :db/valueType   :db.type/ref
    :db/cardinality :db.cardinality/many
    :db/doc         "References to friend entities"}

   {:db/ident       :person/email
    :db/valueType   :db.type/string
    :db/cardinality :db.cardinality/one
    :db/unique      :db.unique/identity
    :db/index       true}])
```

Supported value types:

| Type | Scheme Representation | Byte Width |
|---|---|---|
| `:db.type/string` | string | variable (hash in key) |
| `:db.type/long` | fixnum/bignum | 8 |
| `:db.type/double` | flonum | 8 |
| `:db.type/boolean` | boolean | 1 (padded to 8) |
| `:db.type/instant` | datetime | 8 (epoch nanos) |
| `:db.type/uuid` | uuid-string | 16 (hash in key) |
| `:db.type/ref` | entity-id | 8 |
| `:db.type/keyword` | keyword | variable (interned to 4-byte id) |
| `:db.type/bytes` | bytevector | variable (hash in key) |
| `:db.type/symbol` | symbol | variable (hash in key) |

Cardinality:

| Cardinality | Meaning |
|---|---|
| `:db.cardinality/one` | Single value per entity+attribute.  New assertion retracts the old. |
| `:db.cardinality/many` | Multiple values per entity+attribute.  Each is independent. |

Uniqueness:

| Uniqueness | Meaning |
|---|---|
| `:db.unique/value` | No two entities may have the same value for this attribute. |
| `:db.unique/identity` | Upsert: if an entity with this value exists, merge into it. |

---

## Core API Design

### Connection and Database

```scheme
(import (jerboa prelude)
        (jerboa-db core))

;; Create or open a database
(def conn (connect "path/to/data"))

;; Get current database value (immutable snapshot)
(def db (db conn))

;; Time-travel
(def db-yesterday (as-of db #:t 1000))
(def db-recent    (since db #:t 1000))
(def db-full      (history db))
```

### Transacting Data

```scheme
;; Assert new entities
(transact! conn
  [{:db/id (tempid)
    :person/name "Alice"
    :person/age 30
    :person/email "alice@example.com"}

   {:db/id (tempid)
    :person/name "Bob"
    :person/age 25}])
;; => {:db-before <db> :db-after <db> :tx-data [datoms...] :tempids {..}}

;; Retract a specific datom
(transact! conn
  [[:db/retract 42 :person/email "alice@example.com"]])

;; Retract an entire entity
(transact! conn
  [[:db/retractEntity 42]])

;; CAS (compare-and-swap) — atomic conditional update
(transact! conn
  [[:db/cas 42 :person/age 30 31]])
;; Only succeeds if current value is exactly 30
```

### Datalog Queries

```scheme
;; Find all people older than 30
(q '[:find ?name ?age
     :where [?e :person/name ?name]
            [?e :person/age ?age]
            [(> ?age 30)]]
   db)
;; => #{["Alice" 35] ["Carol" 42]}

;; Parameterized query
(q '[:find ?name
     :in $ ?min-age
     :where [?e :person/name ?name]
            [?e :person/age ?age]
            [(>= ?age ?min-age)]]
   db 21)
;; => #{["Alice"] ["Bob"] ["Carol"]}

;; Find with aggregation
(q '[:find (count ?e) (avg ?age)
     :where [?e :person/age ?age]]
   db)
;; => #{[150 34.2]}

;; Rules (reusable query fragments)
(def rules
  '[[(ancestor ?x ?y)
     [?x :person/parent ?y]]
    [(ancestor ?x ?y)
     [?x :person/parent ?z]
     (ancestor ?z ?y)]])

(q '[:find ?ancestor
     :in $ % ?person
     :where [?p :person/name ?person]
            (ancestor ?p ?ancestor)]
   db rules "Alice")
```

### Pull API

```scheme
;; Simple pull
(pull db [:person/name :person/age] entity-id)
;; => {:person/name "Alice" :person/age 30}

;; Nested pull (follow refs)
(pull db [:person/name
          {:person/friends [:person/name :person/age]}]
     entity-id)
;; => {:person/name "Alice"
;;     :person/friends [{:person/name "Bob" :person/age 25}
;;                      {:person/name "Carol" :person/age 42}]}

;; Wildcard pull
(pull db '[*] entity-id)
;; => all attributes of the entity

;; Reverse refs
(pull db [:person/name {:person/_friends [:person/name]}] entity-id)
;; => {:person/name "Alice"
;;     :person/_friends [{:person/name "Dave"}]}
;; (entities that have Alice as a friend)

;; Pull with limits and defaults
(pull db [{(:person/friends :limit 5) [:person/name]}
          (:person/nickname :default "N/A")]
     entity-id)
```

### Entity API

```scheme
;; Get an entity as a lazy, navigable map
(def alice (entity db 42))

(:person/name alice)          ;; => "Alice"
(:person/age alice)           ;; => 30
(:person/friends alice)       ;; => lazy set of entity objects

;; Touch: realize all attributes eagerly
(touch alice)
;; => {:db/id 42 :person/name "Alice" :person/age 30 ...}
```

### History and Auditing

```scheme
;; Full history of an attribute
(q '[:find ?v ?tx ?added
     :where [42 :person/name ?v ?tx ?added]]
   (history db))
;; => #{["Alice" 1000 true] ["Alice" 1005 false] ["Alicia" 1005 true]}

;; Transaction metadata
(q '[:find ?time ?author
     :where [?tx :db/txInstant ?time]
            [?tx :tx/author ?author]]
   db)

;; What changed in a specific transaction
(def tx-report (tx-range (log conn) 1005 1006))
;; => list of datoms added in transaction 1005
```

### Analytical Queries (DuckDB Integration)

```scheme
;; For queries that need SQL-style aggregation, window functions,
;; or need to scan millions of datoms:

(analytics conn
  "SELECT a.v AS name, b.v AS age
   FROM eavt a
   JOIN eavt b ON a.e = b.e
   WHERE a.a = 'person/name'
     AND b.a = 'person/age'
     AND CAST(b.v AS INTEGER) > 30
   ORDER BY b.v DESC
   LIMIT 100")

;; Or with Parquet export for external tools:
(export-parquet conn "path/to/snapshot.parquet"
  :attributes [:person/name :person/age :person/email])
```

---

## Module Structure

Jerboa-DB will be organized as a set of `(jerboa-db ...)` modules:

```
lib/jerboa-db/
├── core.sls              ;; connect, db, transact!, q, pull, entity
├── datom.sls             ;; datom record, encoding/decoding, comparison
├── schema.sls            ;; attribute definitions, validation, type coercion
├── index/
│   ├── leveldb.sls        ;; LevelDB index backend (persistent)
│   ├── memory.sls         ;; In-memory RB-tree backend (testing/embedded)
│   └── protocol.sls       ;; Index protocol (pluggable backends)
├── tx.sls                ;; Transaction processing, tempid resolution, CAS
├── tx-log.sls            ;; Append-only transaction log (segment files)
├── query/
│   ├── engine.sls         ;; Datalog query compiler and executor
│   ├── planner.sls        ;; Query plan optimization (clause reordering)
│   ├── functions.sls      ;; Built-in query functions (>, <, count, sum, etc.)
│   ├── rules.sls          ;; Rule expansion and recursive evaluation
│   ├── aggregates.sls     ;; Aggregate functions (count, sum, avg, min, max)
│   └── pull.sls           ;; Pull API implementation (pattern walking)
├── entity.sls            ;; Lazy entity map with navigation
├── cache.sls             ;; LRU datom/entity cache with invalidation
├── history.sls           ;; as-of, since, history database views
├── analytics.sls         ;; DuckDB integration for OLAP queries
├── encoding.sls          ;; Binary encoding for datom keys and values
├── server.sls            ;; HTTP/WebSocket API server (fiber-httpd)
├── peer.sls              ;; Peer protocol for distributed reads
├── replication.sls       ;; Raft-based transactor HA + read replicas
└── migrate.sls           ;; Schema migration utilities
```

### Dependency Map (Jerboa stdlib modules used)

```
(jerboa-db core)
├── (std db leveldb)             ;; Index storage (LSM tree + bloom filters)
├── (std db duckdb)              ;; Analytical query engine
├── (std datalog)                ;; Datalog evaluation (base for query engine)
├── (std logic)                  ;; miniKanren (constraint solving in queries)
├── (std mvcc)                   ;; MVCC semantics (for db snapshot values)
├── (std event-source)           ;; Transaction log architecture
├── (std data pmap)              ;; Entity maps (persistent HAMT)
├── (std pvec)                   ;; Datom vectors (persistent)
├── (std pset)                   ;; Entity sets (persistent)
├── (std misc rbtree)            ;; In-memory sorted indices
├── (std ds sorted-map)          ;; Range queries
├── (std concur stm)             ;; Concurrent connection state
├── (std misc lru-cache)         ;; Hot entity/datom cache
├── (std misc uuid)              ;; Entity ID generation
├── (std text edn)               ;; EDN wire format
├── (std text msgpack)           ;; Binary encoding for tx-log segments
├── (std fasl)                   ;; Fast binary encoding for snapshots
├── (std compress zlib)          ;; Segment file compression
├── (std schema)                 ;; Attribute schema validation
├── (std protocol)               ;; Pluggable backends via protocols
├── (std multi)                  ;; Multimethod dispatch for value types
├── (std transducer)             ;; Streaming query results
├── (std misc lazy-seq)          ;; Lazy entity navigation
├── (std component)              ;; Service lifecycle management
├── (std actor)                  ;; Supervised transactor process
├── (std raft)                   ;; Distributed consensus (HA mode)
├── (std actor crdt)             ;; Replicated metadata
├── (std net fiber-httpd)        ;; REST/WebSocket API server
├── (std net router)             ;; HTTP routing
├── (std crypto hmac)            ;; Transaction signing
├── (std db conpool)             ;; Connection pooling
├── (std misc relation)          ;; Relational algebra for joins
└── (std content-address)        ;; Content-addressed value deduplication
```

---

## Implementation Plan

### Phase 1: Core — In-Memory Datomic (the proof of concept)

**Goal:** A working Datomic that stores everything in memory.  No LevelDB, no
DuckDB, no networking.  Prove the data model, query engine, and transaction
processing work correctly.

**Deliverable:** `(jerboa-db core)` usable from the REPL.

#### 1.1 Datom Record and Encoding

```scheme
;; lib/jerboa-db/datom.sls

(defstruct datom (e a v tx added?))

;; Comparison functions for index ordering
(def (datom-compare-eavt a b) ...)
(def (datom-compare-aevt a b) ...)
(def (datom-compare-avet a b) ...)
(def (datom-compare-vaet a b) ...)
```

Build on `defstruct` from the prelude.  Datom comparison uses cascading numeric
comparison on entity, attribute (interned to integers), value (type-specific),
and transaction.

#### 1.2 In-Memory Indices

```scheme
;; lib/jerboa-db/index/memory.sls

;; Each index is a sorted-map (red-black tree) keyed by datom comparison
(def (make-mem-index comparator)
  (make-rbtree comparator))

(def (index-add! idx datom)
  (rbtree-insert idx datom #t))

(def (index-range idx start-datom end-datom)
  ;; Cursor scan using rbtree-fold with bounds
  ...)

(def (index-lookup idx e a v)
  ;; Point lookup — construct a probe datom with known components,
  ;; scan from that point
  ...)
```

Use `(std misc rbtree)` for sorted storage.  Four instances: EAVT, AEVT, AVET,
VAET.  The protocol from 1.5 will abstract over this.

#### 1.3 Schema and Attribute Registry

```scheme
;; lib/jerboa-db/schema.sls

;; Attribute record — derived from datoms on schema entities
(defstruct db-attribute
  (ident          ;; keyword (:person/name)
   id             ;; integer (interned for fast index keys)
   value-type     ;; :db.type/string, :db.type/long, etc.
   cardinality    ;; :db.cardinality/one or :db.cardinality/many
   unique         ;; #f, :db.unique/value, or :db.unique/identity
   index?         ;; boolean — populate AVET?
   is-component?  ;; boolean — cascade retractions?
   doc            ;; string or #f
   no-history?))  ;; boolean — skip history for this attr?

;; Schema validation at transaction time
(def (validate-datom schema datom) ...)
(def (coerce-value attr-type raw-value) ...)
```

Build on `defstruct` + `(std schema)` for validation predicates.

#### 1.4 Transaction Processing

```scheme
;; lib/jerboa-db/tx.sls

;; A transaction is a list of operations:
;;   {:db/id <eid-or-tempid> :attr val ...}    → assert map
;;   [:db/add eid attr val]                     → assert datom
;;   [:db/retract eid attr val]                 → retract datom
;;   [:db/retractEntity eid]                    → retract all datoms for entity
;;   [:db/cas eid attr old-val new-val]         → compare-and-swap

(defstruct tx-report
  (db-before db-after tx-data tempids))

(def (process-transaction db tx-data)
  ;; 1. Allocate transaction entity ID (monotonic counter)
  ;; 2. Resolve tempids → permanent entity IDs
  ;;    - Tempids within a transaction are consistent (same tempid = same entity)
  ;;    - :db.unique/identity triggers upsert (find existing entity)
  ;; 3. Expand map operations into individual datom assertions
  ;; 4. Handle :db.cardinality/one (auto-retract old value)
  ;; 5. Validate all datoms against schema
  ;; 6. Check uniqueness constraints
  ;; 7. Add transaction metadata datom (:db/txInstant)
  ;; 8. Write datoms to all indices
  ;; 9. Return tx-report with before/after db values
  ...)
```

#### 1.5 Index Protocol (Pluggable Backend)

```scheme
;; lib/jerboa-db/index/protocol.sls
(import (std protocol))

(defprotocol DatomIndex
  ;; Add a datom to the index
  (idx-add! [idx datom])

  ;; Remove a datom from the index (for index rebuild only)
  (idx-remove! [idx datom])

  ;; Range scan: return lazy sequence of datoms between start and end
  (idx-range [idx start-datom end-datom])

  ;; Point lookup: return datoms matching known components
  (idx-seek [idx components])

  ;; Count datoms in range
  (idx-count [idx start-datom end-datom])

  ;; Snapshot: return an immutable view at current state
  (idx-snapshot [idx]))
```

Memory backend (Phase 1) and LevelDB backend (Phase 2) both implement this
protocol.

#### 1.6 Datalog Query Engine

This is the largest component.  It extends `(std datalog)` with:

```scheme
;; lib/jerboa-db/query/engine.sls

;; Parse Datomic-style query syntax into internal representation
(def (parse-query form) ...)

;; Query clause types:
;;   [?e :attr ?v]         → index scan (data pattern)
;;   [(> ?x 10)]           → predicate filter (expression clause)
;;   [(str ?first ?last)]  → function call (binding form)
;;   (rule-name ?x ?y)     → rule invocation

;; Query planning: choose index based on bound variables
;; If ?e is bound:     use EAVT
;; If :attr is bound:  use AEVT (or AVET if ?v is also bound)
;; If ?v is bound:     use VAET (for refs)
;; Reorder clauses to bind variables early (most selective first)

(def (plan-query parsed-query db) ...)
(def (execute-plan plan db inputs) ...)
```

The planner constructs an execution DAG where each node is an index scan or
a filter, and edges represent variable bindings flowing between clauses.
Transducers are used for streaming intermediate results.

#### 1.7 Pull API

```scheme
;; lib/jerboa-db/query/pull.sls

;; Pull pattern := [attr-spec ...]
;; attr-spec   := keyword
;;              | {keyword pull-pattern}     ;; nested (follow refs)
;;              | (keyword :as alias)
;;              | (keyword :limit n)
;;              | (keyword :default val)
;;              | '*                         ;; wildcard

(def (pull db pattern eid)
  ;; 1. For each attr-spec in pattern:
  ;;    - Look up datoms in EAVT for (eid, attr)
  ;;    - For cardinality/one: return single value
  ;;    - For cardinality/many: return set of values
  ;;    - For nested patterns: recursively pull referenced entities
  ;;    - For reverse attrs (_friends): scan VAET for (eid, attr)
  ;; 2. Return persistent hash map
  ...)

(def (pull-many db pattern eids)
  (map (lambda (eid) (pull db pattern eid)) eids))
```

#### 1.8 Database Values and Time-Travel

```scheme
;; lib/jerboa-db/history.sls

;; A db value is a snapshot: a reference to the indices at a specific tx
(defstruct db-value
  (connection     ;; back-reference to connection
   basis-tx       ;; the transaction this snapshot is based on
   indices        ;; EAVT/AEVT/AVET/VAET (snapshots or filters)
   schema         ;; attribute registry at this point in time
   as-of-tx       ;; #f for current, or a tx-id for time-travel
   since-tx       ;; #f for current, or a tx-id for since filter
   history?))     ;; #t if this is a history view (includes retractions)

(def (as-of db tx-id)
  ;; Return a new db-value that filters datoms to those with tx <= tx-id
  (make-db-value
    (db-value-connection db)
    (db-value-basis-tx db)
    (db-value-indices db)
    (db-value-schema db)
    tx-id #f #f))

(def (since db tx-id)
  ;; Return a new db-value that only shows datoms with tx > tx-id
  (make-db-value ... since-tx: tx-id ...))

(def (history db)
  ;; Return a db-value that includes all datoms (even retracted)
  (make-db-value ... history?: #t ...))
```

**Phase 1 success criteria:**
- Schema definition and validation works
- Transacting entities with tempid resolution works
- Cardinality/one auto-retraction works
- Unique identity upsert works
- Datalog queries against EAVT/AEVT/AVET/VAET return correct results
- Pull API navigates refs and reverse refs
- `as-of` returns correct historical state
- 1000 entities with 10 attributes each, queried in < 10ms
- All operations available from the REPL

### Phase 2: Persistence — LevelDB Backend

**Goal:** Replace in-memory indices with LevelDB.  Data survives process restarts.
Transaction log is durable.

#### 2.1 LevelDB Index Backend

```scheme
;; lib/jerboa-db/index/leveldb.sls

(def (make-leveldb-index name db-handle)
  ;; Each covering index (EAVT, AEVT, AVET, VAET) gets its own
  ;; LevelDB database directory.  Keys are 28-byte encoded datom keys
  ;; that sort correctly via bytewise comparison.
  ;; Values are FASL-encoded full datom records.
  ...)

;; Implement DatomIndex protocol for LevelDB
;; add! — encode key + FASL value, leveldb-put
;; remove! — encode key, leveldb-delete
;; range-query — iterator-based scan from lo-key to hi-key
;; count-range — key-only fold for counting
;; all-datoms — full table scan (expensive, use sparingly)
```

Key implementation detail: LevelDB iterators are used for range scans.
`leveldb-fold` iterates from a start key to an end key, reconstructing datoms
from FASL-encoded values.  Bloom filters (10-bit) accelerate point lookups.
Each index gets a 64MB LRU cache for hot data.

#### 2.2 Binary Encoding

```scheme
;; lib/jerboa-db/encoding.sls

;; Encode entity ID as big-endian 8 bytes (for correct bytewise sort order)
(def (encode-eid eid)
  (let ([bv (make-bytevector 8)])
    (bytevector-u64-set! bv 0 eid (endianness big))
    bv))

;; Encode attribute ID as big-endian 4 bytes
(def (encode-aid aid)
  (let ([bv (make-bytevector 4)])
    (bytevector-u32-set! bv 0 aid (endianness big))
    bv))

;; Encode value based on type
(def (encode-value attr-type value)
  (case attr-type
    [(:db.type/long)    (encode-i64 value)]
    [(:db.type/double)  (encode-f64-sortable value)]
    [(:db.type/boolean) (if value #vu8(1) #vu8(0))]
    [(:db.type/instant) (encode-i64 (datetime->epoch value))]
    [(:db.type/ref)     (encode-eid value)]
    [(:db.type/string :db.type/uuid :db.type/bytes :db.type/keyword)
     ;; Variable-length: hash to 8 bytes for the index key,
     ;; store full value in value-store
     (content-hash-bytes value)]
    [else (error 'encode-value "unknown type" attr-type)]))

;; EAVT key construction
(def (make-eavt-key e a v tx added?)
  (let ([bv (make-bytevector 28)])
    (bytevector-copy! (encode-eid e) 0 bv 0 8)
    (bytevector-copy! (encode-aid a) 0 bv 8 4)
    (bytevector-copy! (encode-value-hash v) 0 bv 12 8)
    (bytevector-u64-set! bv 20
      (if added? tx (bitwise-ior tx #x8000000000000000))
      (endianness big))
    bv))
```

IEEE 754 doubles are encoded with a bit-flip trick (XOR sign bit, flip all
bits if negative) so that bytewise comparison matches numeric comparison.  This
is critical for LevelDB range scans on numeric values.

#### 2.3 Transaction Log Segments

```scheme
;; lib/jerboa-db/tx-log.sls

;; The transaction log is a sequence of segment files.
;; Each segment contains a batch of transactions.
;; Format: MessagePack-encoded records, gzip-compressed.

(defstruct tx-log-entry
  (tx-id          ;; monotonic transaction ID
   tx-instant     ;; datetime
   datoms))       ;; list of datoms (encoded as vectors)

;; Append a transaction to the log
(def (tx-log-append! log entry)
  ;; 1. Encode entry with msgpack
  ;; 2. Append to current segment file
  ;; 3. If segment exceeds size threshold, rotate to new segment
  ;; 4. fsync for durability
  ...)

;; Replay log to rebuild indices (disaster recovery)
(def (tx-log-replay log from-tx index-fn)
  ;; Read all segments from from-tx forward
  ;; Call index-fn for each datom
  ;; Uses transducers for streaming (no full materialization)
  ...)
```

#### 2.4 Value Store

```scheme
;; lib/jerboa-db/encoding.sls (continued)

;; Large values (strings, bytevectors) are stored separately.
;; The index key contains only the hash; the full value lives here.
;; This is another LevelDB database.

(def (value-store-put! env value)
  ;; 1. Compute SHA-256 hash of value
  ;; 2. Check if already exists (content-addressed → deduplication!)
  ;; 3. Store hash → value in LevelDB "values" database
  ;; 4. Return 8-byte truncated hash for index key
  ...)
```

Content addressing gives automatic deduplication.  If 10,000 entities all have
`:country "United States"`, that string is stored once.

**Phase 2 success criteria:**
- All Phase 1 tests pass with LevelDB backend
- Database survives process restart (`kill -9` + restart = no data loss)
- 1 million datoms indexed in < 30 seconds
- Point lookups in < 100 microseconds (LevelDB bloom filter + LRU cache)
- Range scans stream without materializing all datoms
- Transaction log can rebuild indices from scratch

### Phase 3: Query Engine — Production Datalog

**Goal:** A query engine that handles real workloads: clause reordering,
aggregation, rules, built-in functions, and streaming results.

#### 3.1 Query Planner

```scheme
;; lib/jerboa-db/query/planner.sls

;; Clause reordering: put the most selective clauses first.
;; Selectivity heuristic:
;;   1. Clauses with more bound variables are more selective
;;   2. Unique attributes are maximally selective
;;   3. Ref attributes (VAET) are moderately selective
;;   4. Unbounded scans (only attribute bound) are least selective

(def (reorder-clauses clauses bound-vars schema)
  ;; Score each clause based on which variables are already bound
  ;; Sort by selectivity (highest first)
  ;; This is the single biggest performance lever in the query engine
  ...)

;; Choose index for a data pattern [?e :attr ?v]
(def (choose-index pattern bound-vars schema)
  (let ([e-bound? (bound? (pattern-entity pattern) bound-vars)]
        [a-bound? (pattern-attribute pattern)]  ;; always bound in valid query
        [v-bound? (bound? (pattern-value pattern) bound-vars)]
        [attr-info (schema-lookup schema (pattern-attribute pattern))])
    (cond
      [e-bound?  'eavt]                          ;; entity known → EAVT
      [(and v-bound? (ref-type? attr-info)) 'vaet]  ;; ref value known → VAET
      [(and v-bound? (indexed? attr-info))  'avet]  ;; indexed + value → AVET
      [else 'aevt])))                              ;; attribute scan → AEVT
```

#### 3.2 Aggregate Functions

```scheme
;; lib/jerboa-db/query/aggregates.sls

;; Built-in aggregates (matching Datomic's set)
;; (count ?x)           → count of distinct values
;; (count-distinct ?x)  → count of distinct values
;; (sum ?x)             → sum of numeric values
;; (avg ?x)             → average
;; (min ?x)             → minimum
;; (max ?x)             → maximum
;; (median ?x)          → median (not in Datomic, but we add it)
;; (rand N ?x)          → N random samples
;; (sample N ?x)        → N random samples (Datomic name)
;; (distinct ?x)        → set of distinct values

;; Custom aggregates via protocol
(defprotocol Aggregate
  (agg-init [agg])
  (agg-step [agg state value])
  (agg-complete [agg state]))
```

#### 3.3 Built-in Functions

```scheme
;; lib/jerboa-db/query/functions.sls

;; Predicate clauses: [(> ?age 30)]
;; These filter — they don't bind new variables

;; Function clauses: [(str ?first " " ?last) ?full-name]
;; These compute and bind the result to ?full-name

;; Built-in predicates
;;   >, <, >=, <=, =, not=, zero?, pos?, neg?, even?, odd?
;;   string-starts-with?, string-ends-with?, string-contains?

;; Built-in functions
;;   str, subs, upper-case, lower-case, count (string length)
;;   +, -, *, /, mod, inc, dec, abs, max, min
;;   ground (bind a value: [(ground 42) ?x])
;;   get-else (default value: [(get-else $ ?e :attr default) ?v])
;;   missing? (true if entity lacks attribute)
;;   tuple (construct a tuple from variables)
```

#### 3.4 Rule System

```scheme
;; lib/jerboa-db/query/rules.sls

;; Rules are reusable query fragments, enabling recursion.
;; Defined as: [(rule-name ?arg ...) clause clause ...]

;; Rule expansion at query time:
;; 1. Parse rule definitions
;; 2. When a rule invocation appears in a query, expand it
;; 3. Handle recursive rules via fixed-point iteration
;;    (same semi-naive approach as (std datalog))
;; 4. Memoize intermediate results to avoid recomputation
```

**Phase 3 success criteria:**
- Query planner chooses correct index (verified by `explain` output)
- Clause reordering makes multi-clause queries 10-100x faster
- Aggregation works: count, sum, avg, min, max
- Recursive rules (ancestor, transitive closure) work
- Built-in functions work in filter and binding positions
- Query over 1M datoms completes in < 1 second for typical OLTP patterns

### Phase 4: DuckDB Analytics Layer

**Goal:** Wire DuckDB as an analytical query engine for workloads that don't
fit Datalog — aggregation over large datasets, window functions, ad-hoc SQL.

#### 4.1 DuckDB Replica

```scheme
;; lib/jerboa-db/analytics.sls

;; Maintain a DuckDB database as a columnar replica of the datom store.
;; Schema:
;;   CREATE TABLE datoms (
;;     e BIGINT, a INTEGER, v VARCHAR,
;;     v_long BIGINT, v_double DOUBLE, v_bool BOOLEAN,
;;     v_instant TIMESTAMP, v_ref BIGINT,
;;     tx BIGINT, added BOOLEAN
;;   );
;;
;; Separate typed columns avoid the "everything is a string" problem.
;; The query engine selects the right column based on schema type.

(def (sync-to-duckdb! conn duckdb-conn from-tx)
  ;; Read transaction log entries since from-tx
  ;; Batch-insert datoms into DuckDB using prepared statements
  ;; Uses transducers for streaming from tx-log → DuckDB
  ...)

;; Convenience: SQL over the datom store
(def (analytics conn sql-string . params)
  ;; 1. Ensure DuckDB replica is synced to latest tx
  ;; 2. Execute SQL query against DuckDB
  ;; 3. Return results as list of alists
  ...)
```

#### 4.2 Parquet Export/Import

```scheme
;; Export database snapshot to Parquet (for external analytics)
(def (export-parquet conn path . opts)
  ;; Uses DuckDB's native Parquet writer
  ;; Options: :attributes (subset), :as-of (time-travel), :format (wide/long)
  ...)

;; Import external data as datoms
(def (import-parquet conn path mapping)
  ;; mapping: column-name → attribute keyword
  ;; Each row becomes an entity, each column becomes an attribute
  ...)

;; Same for CSV
(def (import-csv conn path mapping) ...)
```

**Phase 4 success criteria:**
- DuckDB replica stays within 1 second of latest transaction
- SQL aggregation over 10M datoms completes in < 5 seconds
- Parquet export produces valid files readable by pandas/DuckDB/Spark
- CSV/Parquet import creates correct datoms with schema validation

### Phase 5: Server Mode

**Goal:** A standalone Jerboa-DB server accessible over HTTP and WebSocket,
enabling multi-client access and remote peers.

#### 5.1 HTTP API

```scheme
;; lib/jerboa-db/server.sls

;; REST endpoints:
;; POST /api/transact        — submit transaction
;; POST /api/query           — run Datalog query
;; POST /api/pull            — pull entity data
;; GET  /api/entity/:eid     — get entity by ID
;; GET  /api/db/stats        — database statistics
;; GET  /api/db/schema       — current schema
;; GET  /health              — health check

;; WebSocket endpoint:
;; WS /api/tx-stream         — stream transaction reports in real-time
;;                              (clients subscribe and get notified of every tx)

;; Wire format: EDN (primary) or JSON (for non-Scheme clients)
```

Built on `(std net fiber-httpd)` + `(std net router)` + `(std net fiber-ws)`.
One fiber per connection.  Queries run against immutable db snapshots so they
never block the transactor.

#### 5.2 Client Library

```scheme
;; lib/jerboa-db/peer.sls

;; Remote peer — connects to a Jerboa-DB server
(def remote-conn (connect-remote "http://localhost:8484"))

;; Same API as embedded mode
(def db (db remote-conn))
(q '[:find ...] db)
(pull db pattern eid)
(transact! remote-conn tx-data)

;; Transparent caching: the peer caches db segments locally
;; and only fetches deltas from the server.
```

#### 5.3 Transaction Stream

```scheme
;; Real-time change feed over WebSocket
;; Clients subscribe and receive tx-reports as they happen.
;; This enables:
;;   - UI live updates (like Firebase)
;;   - ETL pipelines that react to database changes
;;   - Read replicas that stay in sync

(def (tx-stream conn handler)
  ;; handler: (lambda (tx-report) ...)
  ;; Called for every committed transaction
  ...)
```

**Phase 5 success criteria:**
- Server handles 10K concurrent query connections
- Transactions via HTTP complete in < 50ms (excluding network)
- WebSocket tx-stream delivers updates within 5ms of commit
- Remote peer API is identical to embedded API

### Phase 6: Distribution (Raft-based HA)

**Goal:** Multi-node Jerboa-DB with automatic failover.  One transactor (leader),
multiple read replicas (followers).

#### 6.1 Raft-Based Transactor

```scheme
;; lib/jerboa-db/replication.sls

;; The transactor is a Raft leader.
;; Transactions are proposed to the Raft log.
;; Once committed by majority, they're applied to local indices.
;; Followers apply transactions from the Raft log.

;; Uses (std raft) for leader election and log replication.
;; Uses (std actor transport) for inter-node communication.
```

#### 6.2 Read Replicas

```scheme
;; Followers maintain full index copies (LevelDB).
;; They tail the transaction log and apply transactions locally.
;; Queries against followers are eventually consistent
;; (typically < 100ms behind the leader).

;; Consistency options:
;; :read-committed   — any follower, may be slightly behind
;; :read-latest      — leader only, always current
;; :as-of tx-id      — any node, guaranteed consistent at that tx
```

**Phase 6 success criteria:**
- Leader failure triggers automatic election within 5 seconds
- Read replicas stay within 100ms of leader during normal operation
- No data loss on leader failure (Raft quorum guarantees)
- Client automatically reconnects to new leader

### Phase 7: Polish and Ecosystem

#### 7.1 Schema Migrations

```scheme
;; Adding new attributes is always safe (additive schema).
;; Renaming/removing requires migration:

(def (migrate! conn migration)
  ;; migration is a list of operations:
  ;; [:rename-attr :old/name :new/name]
  ;; [:merge-attr :from :into merge-fn]
  ;; [:split-attr :from :into-a :into-b split-fn]
  ;; [:add-index :attr]
  ;; [:remove-index :attr]
  ...)
```

#### 7.2 Backup and Restore

```scheme
(backup! conn "path/to/backup")
;; Serializes all indices + connection state as FASL + gzip
;; Point-in-time: backup is consistent at the latest committed tx

(restore! "path/to/backup" "path/to/new-db")
;; Copies data files, verifies integrity, opens new connection
```

#### 7.3 CLI

```bash
# Start server
jerboa-db serve --port 8484 --data /var/lib/jerboa-db

# Interactive query REPL
jerboa-db repl --connect http://localhost:8484

# Import data
jerboa-db import --format csv --mapping mapping.edn data.csv

# Export snapshot
jerboa-db export --format parquet --as-of 2026-04-01 snapshot.parquet

# Backup
jerboa-db backup --data /var/lib/jerboa-db --output /backup/

# Stats
jerboa-db stats --data /var/lib/jerboa-db
```

#### 7.4 Monitoring

```scheme
;; Prometheus metrics
;; jerboa_db_datoms_total
;; jerboa_db_transactions_total
;; jerboa_db_transaction_duration_seconds (histogram)
;; jerboa_db_query_duration_seconds (histogram by complexity)
;; jerboa_db_index_size_bytes (by index name)
;; jerboa_db_cache_hit_ratio
;; jerboa_db_replication_lag_seconds
```

---

## Performance Targets

| Metric | Target | Datomic Comparison |
|---|---|---|
| Point entity lookup | < 10 microseconds | Comparable (LevelDB bloom filter) |
| Simple 2-clause query | < 1ms | Comparable |
| Complex 5-clause query | < 50ms | Comparable |
| Transaction (10 datoms) | < 5ms | Faster (no JVM overhead) |
| Transaction (1000 datoms) | < 100ms | Comparable |
| Bulk import (1M datoms) | < 60 seconds | Faster (LevelDB batch write) |
| Cold start | < 200ms | 10-100x faster (no JVM) |
| Memory (1M datoms) | < 200MB | 5-10x less (no JVM heap) |
| Binary size | < 30MB | N/A (Datomic is 60MB+ JARs) |
| Max database size | 1TB+ (disk limit) | Comparable |
| Concurrent readers | Unlimited (immutable db-values) | Comparable |
| Aggregate over 10M datoms | < 5s (DuckDB) | Faster (columnar engine) |

### Why These Numbers Are Achievable

- **LevelDB** provides fast reads via LSM tree with bloom filters + 64MB LRU cache
- **FASL encoding** — Chez native binary format, fast deserialization without boxing
- **Chez Scheme** compiles to native code — no JVM interpreter warmup
- **Persistent data structures** share structure — low GC pressure
- **DuckDB** is a world-class columnar engine for analytical queries
- **Fiber-based server** handles 100K connections on one process

---

## The DuckDB Advantage

Datomic's biggest weakness is analytical queries.  Aggregating over millions of
datoms requires custom index scans and client-side computation.  XTDB v2
addressed this with Apache Arrow, but it's still JVM-only.

Jerboa-DB's DuckDB integration provides:

1. **Full SQL over datoms** — GROUP BY, HAVING, WINDOW functions, CTEs, subqueries
2. **Vectorized execution** — DuckDB processes data in columnar batches, 10-100x
   faster than row-by-row Datalog evaluation for aggregation
3. **Parquet interop** — Export snapshots to Parquet for external tools (Python,
   R, Spark, dbt)
4. **Time-series queries** — DuckDB handles temporal aggregation natively:
   ```sql
   SELECT date_trunc('hour', v_instant) AS hour,
          COUNT(*) AS events
   FROM datoms
   WHERE a = 'event/timestamp'
   GROUP BY 1
   ORDER BY 1
   ```
5. **No external infrastructure** — DuckDB runs in-process, same as LevelDB

This gives Jerboa-DB a **dual-engine architecture**: Datalog for navigational
queries (follow relationships, traverse graphs) and SQL for analytical queries
(aggregate, window, report).  No other Datomic-like system offers both.

---

## What Jerboa-DB Proves About Jerboa

When someone sees Jerboa-DB and asks "could I build this in Go/Rust/Python?",
the honest answer is: not easily.

| Requirement | Go | Rust | Python | Jerboa |
|---|---|---|---|---|
| Datalog query engine | Build from scratch | Build from scratch | DataScript (JS FFI) | `(std datalog)` exists |
| Persistent data structures | None in stdlib | None in stdlib | None in stdlib | pmap, pvec, pset exist |
| MVCC with time-travel | Build from scratch | Build from scratch | Build from scratch | `(std mvcc)` exists |
| Event sourcing | Build from scratch | Build from scratch | Build from scratch | `(std event-source)` exists |
| Raft consensus | etcd/raft (library) | raft-rs (library) | None | `(std raft)` exists |
| LevelDB bindings | goleveldb | leveldb-rs | plyvel | `(std db leveldb)` exists |
| DuckDB bindings | go-duckdb | duckdb-rs | duckdb-python | `(std db duckdb)` exists |
| Macro system for DSL | None | proc_macro (complex) | None | Chez hygienic macros |
| EDN format | Third-party | Third-party | Third-party | `(std text edn)` exists |
| Actor supervision | Third-party | Third-party | None | `(std actor)` exists |
| Fiber-based server | goroutines (yes) | tokio (yes) | asyncio (limited) | `(std net fiber-httpd)` exists |
| Single static binary | Yes | Yes | No | Yes (musl) |
| REPL-driven development | No | No | Partial | Yes |
| Embeddable as library | Yes | Yes | Yes | Yes |

Jerboa has **15 of the required building blocks already built and tested**.  In
Go or Rust, you'd be starting with 2-3 (bindings to LevelDB and DuckDB) and
building the other 12 from scratch.  That's the difference between a 6-month
project and a multi-year one.

---

## Implementation Scorecard (2026-04-12)

### Core (Phase 1) — Complete

| Feature | Status | Notes |
|---|---|---|
| Datom model (E-A-V-T-op) | Done | 5-tuple record, 4 comparators, sentinel boundaries |
| Four covering indices (EAVT/AEVT/AVET/VAET) | Done | In-memory RB-tree + LevelDB backends |
| Schema registry | Done | Intern, lookup, bootstrap attrs (db/ident through db/noHistory) |
| Transaction processing | Done | Tempid resolution, auto-retract, upsert, CAS, entity retract |
| Current-state resolution | Done | Groups by (e,a,v), keeps highest-tx, filters retracted |
| Datalog query engine | Done | Parse, plan, execute with index selection |
| Clause reordering | Done | Selectivity scoring, greedy ordering |
| Recursive rules | Done | Fixed-point evaluation, variable renaming for hygiene |
| Pull API | Done | Nesting, wildcards, reverse refs, limits, defaults, cycle detection |
| Lazy entity maps | Done | On-demand loading, touch for eager materialization |
| Time-travel (as-of, since, history) | Done | Temporal filters on db-value snapshots |
| Schema migration | Done | rename, merge, split, add-index, remove-index |
| Binary encoding (28-byte keys) | Done | Big-endian ints, sortable doubles, FNV-1a hashing |
| LRU cache | Done | O(1) get/put, hit/miss stats |

### Persistence (Phase 2) — Complete

| Feature | Status | Notes |
|---|---|---|
| LevelDB index backend | Done | 4 separate LevelDB databases, 28-byte keys, FASL values |
| Lazy backend loading | Done | `eval`-based import; LevelDB only loaded for non-memory paths |
| Connection close/cleanup | Done | Closes all 4 LevelDB handles |
| LevelDB options | Done | 64MB LRU cache, bloom filters (10-bit), compression |

### Query Engine (Phase 3) — Complete

| Feature | Status | Notes |
|---|---|---|
| `not` / `not-join` clauses | Done | Filter out binding sets matching negated patterns |
| `or` / `or-join` clauses | Done | Union of binding sets from disjunctive branches |
| Collection binding `[?x ...]` in `:in` | Done | Pass a set, match any member |
| Relation binding `[[?x ?y]]` in `:in` | Done | Pass a relation, join against it |
| Tuple binding `[?x ?y]` in `:in` | Done | Destructure a single tuple |
| Lookup refs in transactions | Done | `(attr-ident value)` pair resolves via unique attribute |
| Nested maps in transactions | Done | Component entities auto-created from nested alists |
| Predicates | Done | `zero?`, `pos?`, `neg?`, `even?`, `odd?`, `starts-with?`, `ends-with?`, `contains?` |
| Functions | Done | `str`, `subs`, `upper-case`, `lower-case`, `inc`, `dec`, `abs`, `mod`, `ground`, `get-else`, `missing?`, `tuple`, `count` |
| Aggregates | Done | `count`, `count-distinct`, `sum`, `avg`, `min`, `max`, `median`, `rand`, `sample`, `distinct` |
| Query explain | Done | Dump chosen plan for debugging |

### Analytics (Phase 4) — Complete

| Feature | Status | Notes |
|---|---|---|
| DuckDB integration | Done | Real `(std db duckdb)` calls, typed value columns |
| SQL query interface | Done | `analytics-query` over synced datom store |
| Parquet export/import | Done | `export-parquet`, `import-parquet` |
| CSV import | Done | `import-csv` with column-to-attribute mapping |
| Analytics sync | Done | `analytics-sync!` materializes datoms → DuckDB |

### Server Mode (Phase 5) — Complete

| Feature | Status | Notes |
|---|---|---|
| HTTP server | Done | `(std net fiber-httpd)` with 7 REST routes |
| WebSocket tx-stream | Done | `(std net fiber-ws)` real-time transaction feed |
| Remote peer client | Done | `(std net request)` + `(std text edn)` wire format |
| EDN wire format | Done | Full EDN serialization for queries and results |
| Routes | Done | `/transact`, `/q`, `/pull`, `/entity`, `/schema`, `/stats`, `/db` |

### Distribution (Phase 6) — Complete

| Feature | Status | Notes |
|---|---|---|
| Raft consensus | Done | `(std raft)` leader election + log replication |
| Replicated transactions | Done | Leader-only writes, callback-based apply |
| Consistency levels | Done | `:read-committed`, `:read-latest`, `:as-of` |
| Start/stop replication | Done | Clean lifecycle management |

### Polish (Phase 7) — Complete

| Feature | Status | Notes |
|---|---|---|
| Backup/restore | Done | FASL + gzip serialization, full db state |
| Prometheus metrics | Done | tx duration, query duration, datom counts, cache stats |
| Excision (GDPR) | Done | Physical removal from all 4 indices by entity, attribute, or datom |
| Online reindexing | Done | `reindex!` and `reindex-attribute!` with full rebuild |
| Test suite | Done | 34 integration tests, all passing |

### Advanced Features (Phase 8) — Complete

| Feature | Status | Notes |
|---|---|---|
| Attribute predicates / entity specs | Done | `define-spec`, `validate-entity`, `check-entity-spec`; `spec/ident` + `spec/attrs` schema entities |
| Composite tuples | Done | `db/tupleAttrs` triggers auto-generation of composite datom on component change |
| Fulltext search | Done | In-memory inverted index; tokenized by word, case-insensitive; `fulltext-search` on connection |
| CLI tools | Done | `bin/jerboa-db.ss`; `serve`, `stats`, `backup`, `gc`, `repl`, `import`, `export` subcommands |
| Datom garbage collection | Done | `gc-collect!` / `gc-stats` compact retracted `db/noHistory` datoms; optional full-GC mode |
| Automatic client failover | Done | `connect-remote*` accepts URL list; exponential backoff (100/200/400 ms) with URL rotation |
| Content-addressed value store | Done | FNV-1a keyed in-memory hashtable; `value-store-put!` deduplicates equal values |
| Transaction log durability | Done | `sync` foreign-procedure called after each segment write to guarantee fsync on flush |

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| LevelDB write amplification | LSM compaction spikes under heavy write load | Tune bloom filter bits and LRU cache size |
| DuckDB sync lag | Analytical queries see stale data | Configurable sync interval; explicit `sync!` for consistency |
| Query planner quality | Bad plans → slow queries | Start with heuristic, add cost-based planning later |
| Schema migrations on large DBs | Downtime for reindexing | Online reindexing with `reindex!` / `reindex-attribute!` |
| Datalog vs SQL confusion | Two query languages → cognitive load | Clear docs: Datalog for navigation, SQL for analytics |
| Memory pressure from caching | OOM on large working sets | LRU with configurable max size; eviction metrics |

---

## Related Work

- `docs/jerboa-edge.md` — Webhook service demo (uses Jerboa-DB as storage in Phase 3)
- `docs/clojure-left.md` — Clojure gap analysis (Jerboa-DB fills the "database" gap)
- `lib/std/mvcc.sls` — Starting point for MVCC semantics
- `lib/std/datalog.sls` — Starting point for query engine
- `lib/std/event-source.sls` — Starting point for transaction log
- `lib/std/db/leveldb.sls` — LevelDB FFI bindings
- `lib/std/db/duckdb.sls` — DuckDB integration
- Rich Hickey, "The Database as a Value" (2012) — foundational Datomic talk
- `https://docs.datomic.com/` — Datomic reference documentation
- `https://www.xtdb.com/` — XTDB v2 (modern open-source Datomic alternative)
