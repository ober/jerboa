# Jerboa Library Gap Analysis

Gerbil has ~438 `:std/*` modules. Jerboa currently implements 51. This document tracks coverage and what's needed to close the gap.

## Current Coverage (51 modules)

| Category | Jerboa | Gerbil | Coverage |
|----------|--------|--------|----------|
| Core (sort, format, error, sugar, pregexp, logger, test) | 7 | ~15 | 47% |
| text/* (json, csv, hex, base64, utf8, xml, yaml) | 7 | ~15 | 47% |
| misc/* (string, list, alist, ports, channel, thread, process, queue, bytes, uuid, repr, completion) | 12 | ~38 | 32% |
| os/* (path, env, signal, temporaries, fdio, epoll, inotify) | 7 | ~16 | 44% |
| crypto/* (digest, cipher, hmac, pkey, kdf, etc) | 6 | ~9 | 67% |
| net/* (request, httpd, ssl) | 3 | ~40+ | 8% |
| db/* (leveldb, sqlite, postgresql) | 3 | ~4 | 75% |
| cli/* (getopt) | 1 | ~4 | 25% |
| srfi/* (13, 19) | 2 | ~60+ | 3% |
| compress/* (zlib) | 1 | 0 | N/A |
| pcre2 | 1 | 0 | N/A |

## External chez-* Libraries

### Already Integrated

| Library | Wraps | Jerboa Modules |
|---------|-------|---------------|
| chez-ssl | OpenSSL TLS/TCP | `(std net ssl)` |
| chez-https | HTTP client+server | `(std net request)`, `(std net httpd)` |
| chez-zlib | zlib compression | `(std compress zlib)` |
| chez-pcre2 | PCRE2 regex | `(std pcre2)` |
| chez-yaml | YAML parser | `(std text yaml)` |
| chez-leveldb | LevelDB | `(std db leveldb)` |

### Completed (New)

| Library | Wraps | Jerboa Modules | Status |
|---------|-------|---------------|--------|
| chez-epoll | Linux epoll | `(std os epoll)` | Done |
| chez-inotify | Linux inotify | `(std os inotify)` | Done |
| chez-crypto | OpenSSL EVP | `(std crypto cipher)`, `(std crypto hmac)`, `(std crypto pkey)`, `(std crypto kdf)`, `(std crypto etc)` | Done |
| chez-sqlite | SQLite3 | `(std db sqlite)` | Done |
| chez-postgresql | libpq | `(std db postgresql)` | Done |

## Pure Scheme Modules (No External Deps)

### High Priority — Commonly Used

| Module | Description | Status |
|--------|-------------|--------|
| `(std iter)` | Iteration protocol | TODO |
| `(std interface)` | Interface/protocol system | TODO |
| `(std generic)` | Generic functions (CLOS-lite) | TODO |
| `(std event)` | Event/sync system | TODO |
| `(std coroutine)` | Coroutines via continuations | TODO |
| `(std lazy)` | Lazy evaluation (delay/force) | TODO |
| `(std values)` | Multiple-values utilities | TODO |
| `(std ref)` | Generic ref/set! | TODO |
| `(std contract)` | Design-by-contract | TODO |
| `(std amb)` | Nondeterminism | TODO |
| `(std net uri)` | URI parsing/encoding | TODO |
| `(std net address)` | Network address parsing | TODO |
| `(std net json-rpc)` | JSON-RPC protocol | TODO |
| `(std parser)` | Parser combinators | TODO |
| `(std protobuf)` | Protocol Buffers | TODO |

### misc/* — Data Structures & Utilities

| Module | Description | Status |
|--------|-------------|--------|
| `(std misc hash)` | Extended hash utilities | TODO |
| `(std misc func)` | Function combinators | TODO |
| `(std misc number)` | Number utilities | TODO |
| `(std misc decimal)` | Decimal arithmetic | TODO |
| `(std misc deque)` | Double-ended queue | TODO |
| `(std misc pqueue)` | Priority queue | TODO |
| `(std misc rbtree)` | Red-black tree | TODO |
| `(std misc lru)` | LRU cache | TODO |
| `(std misc dag)` | DAG operations | TODO |
| `(std misc shuffle)` | Random shuffle | TODO |
| `(std misc vector)` | Vector utilities | TODO |
| `(std misc symbol)` | Symbol utilities | TODO |
| `(std misc plist)` | Property lists | TODO |
| `(std misc text)` | Text utilities | TODO |
| `(std misc walist)` | Weak-alist | TODO |
| `(std misc list-builder)` | List builder pattern | TODO |
| `(std misc timeout)` | Timeout utilities | TODO |
| `(std misc barrier)` | Thread barrier | TODO |
| `(std misc rwlock)` | Read-write lock | TODO |
| `(std misc concurrent-plan)` | Concurrent DAG executor | TODO |
| `(std misc atom)` | Atomic reference | TODO |
| `(std misc sync)` | Synchronization primitives | TODO |
| `(std misc wg)` | WaitGroup | TODO |
| `(std misc evector)` | Extensible vector | TODO |
| `(std misc shared)` | Shared structure detection | TODO |
| `(std misc path)` | Path utilities (beyond os/path) | TODO |
| `(std misc prime)` | Prime numbers | TODO |
| `(std misc template)` | String templates | TODO |

### text/* — Text Processing

| Module | Description | Status |
|--------|-------------|--------|
| `(std text base58)` | Base58 encode/decode | TODO |
| `(std text utf16)` | UTF-16 utilities | TODO |
| `(std text utf32)` | UTF-32 utilities | TODO |
| `(std text char-set)` | Character sets (SRFI-14) | TODO |
| `(std text zlib)` | zlib in text format | Covered by `(std compress zlib)` |

### os/* — Operating System

| Module | Description | Status |
|--------|-------------|--------|
| `(std os hostname)` | Get hostname | TODO |
| `(std os pid)` | Process ID utilities | TODO |
| `(std os pipe)` | Pipe creation | TODO |
| `(std os flock)` | File locking | TODO |
| `(std os fcntl)` | fcntl operations | TODO |
| `(std os error)` | OS error codes | TODO |
| `(std os fd)` | File descriptor utilities | TODO |
| `(std os socket)` | Raw socket operations | TODO |
| `(std os epoll)` | Linux epoll | Done |
| `(std os inotify)` | Linux inotify | Done |
| `(std os kqueue)` | BSD kqueue | N/A (Linux only) |
| `(std os signalfd)` | Linux signalfd | TODO |

### cli/* — Command Line

| Module | Description | Status |
|--------|-------------|--------|
| `(std cli multicall)` | Busybox-style multicall | TODO |
| `(std cli shell)` | Shell completion generation | TODO |
| `(std cli print-exit)` | Print-and-exit patterns | TODO |

### net/* — Networking (beyond HTTP)

| Module | Description | Status |
|--------|-------------|--------|
| `(std net websocket)` | WebSocket client/server | TODO |
| `(std net smtp)` | SMTP email sending | TODO |
| `(std net socks)` | SOCKS proxy | TODO |
| `(std net s3)` | AWS S3 client | TODO |
| `(std net repl)` | Network REPL | TODO |
| `(std net bio)` | Buffered network I/O | TODO |
| `(std net socket)` | Socket abstraction | TODO |

### markup/* — HTML/XML/TAL

| Module | Description | Status |
|--------|-------------|--------|
| `(std markup html)` | HTML generation | TODO |
| `(std markup xml)` | XML processing | Partially covered by `(std text xml)` |
| `(std markup sxml)` | SXML processing | TODO |
| `(std markup tal)` | TAL templates | TODO |

### Other

| Module | Description | Status |
|--------|-------------|--------|
| `(std mime types)` | MIME type database | TODO |
| `(std io)` | Buffered I/O framework | TODO |
| `(std debug DBG)` | Debug printing | TODO |
| `(std debug heap)` | Heap analysis | TODO |
| `(std debug threads)` | Thread debugging | TODO |
| `(std web fastcgi)` | FastCGI protocol | TODO |
| `(std web rack)` | Rack-style web framework | TODO |

### srfi/* — Scheme Requests for Implementation

| Module | Description | Status |
|--------|-------------|--------|
| `(std srfi 1)` | List library | TODO |
| `(std srfi 8)` | receive (multiple values) | TODO |
| `(std srfi 9)` | Records | TODO |
| `(std srfi 14)` | Character sets | TODO |
| `(std srfi 41)` | Streams (lazy lists) | TODO |
| `(std srfi 42)` | Eager comprehensions | TODO |
| `(std srfi 43)` | Vector library | TODO |
| `(std srfi 78)` | Lightweight testing | TODO |
| `(std srfi 95)` | Sorting and merging | TODO |
| `(std srfi 101)` | Purely functional random-access pairs | TODO |
| `(std srfi 113)` | Sets and bags | TODO |
| `(std srfi 115)` | Regexp | TODO |
| `(std srfi 116)` | Immutable pairs | TODO |
| `(std srfi 117)` | Queues based on lists | TODO |
| `(std srfi 121)` | Generators | TODO |
| `(std srfi 124)` | Ephemerons | TODO |
| `(std srfi 125)` | Hash tables | TODO |
| `(std srfi 127)` | Lazy sequences | TODO |
| `(std srfi 128)` | Comparators | TODO |
| `(std srfi 130)` | Cursor-based string library | TODO |
| `(std srfi 132)` | Sort libraries | TODO |
| `(std srfi 133)` | Vector library (R7RS-compatible) | TODO |
| `(std srfi 134)` | Immutable deques | TODO |
| `(std srfi 135)` | Immutable texts | TODO |
| `(std srfi 141)` | Integer division | TODO |
| `(std srfi 143)` | Fixnums | TODO |
| `(std srfi 144)` | Flonums | TODO |
| `(std srfi 145)` | Assumptions | TODO |
| `(std srfi 146)` | Mappings | TODO |
| `(std srfi 151)` | Bitwise operations | TODO |
| `(std srfi 158)` | Generators and accumulators | TODO |
| `(std srfi 159)` | Combinator formatting | TODO |
| `(std srfi 160)` | Homogeneous numeric vector | TODO |
| `(std srfi 212)` | Aliases | TODO |

## Actor System

The Gerbil actor system (v13 + v18, ~30+ modules) is deeply tied to the Gerbil runtime and would require significant design work to port. This is out of scope for initial coverage.

## I/O System

Gerbil's `:std/io` subsystem (~30+ modules) provides a layered buffered I/O framework. Chez Scheme's built-in port system covers most use cases, but a compatibility layer could be built for code that depends on bio/strio APIs.
