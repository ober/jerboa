# Jerboa TODO

Updated 2026-03-21.

Tracks remaining work. Items marked DONE were either already implemented
or completed in the March 2026 sprint. Remaining items are genuinely open.

---

## Completed

### Developer Experience
- [x] **CLI entry point** — `bin/jerboa` with run, test, eval, repl, build, version (`bin/jerboa`)
- [x] **Error messages** — `(std errors)` with "did you mean" suggestions, Levenshtein distance, `install-error-handler!`
- [x] **Import conflict ergonomics** — `(jerboa prelude clean)` conflict-free prelude + `docs/import-conflicts.md` reference

### Language Features
- [x] **String interpolation** — `(std interpolate)` macro: `(interpolate "Hello ${name}")`
- [x] **Struct pattern matching** — `(std match2)` with `define-match-type`, sealed hierarchies, exhaustiveness
- [x] **Iterator protocol** — `(std iter)` with `for/collect`, `for/fold`, `in-range`, `in-hash-*`, etc.
- [x] **Interface/protocol system** — `(std interface)` with `definterface` + `(std generic)` with `defgeneric`

### Standard Library
- [x] **SRFI-1** (list library, 271 lines), **SRFI-13** (string library, 258 lines), **SRFI-14** (character sets), **SRFI-19** (date/time), **SRFI-43** (vectors), **SRFI-128** (comparators), **SRFI-141** (integer division)
- [x] **Process management** — `(std misc process)` with `process-port-pid`, `process-kill`, `tty?`
- [x] **Spawn/concurrency** — `(std misc thread)` with `spawn`, `spawn/name`, `spawn/group`, `thread-sleep!`
- [x] **CLI framework** — `(std cli multicall)` subcommands, `(std cli style)` ANSI colors, `(std cli completion)` bash/zsh
- [x] **Serialization** — `(std text toml)`, `(std text msgpack)`, `(std text cbor)`, `(std io)` structured I/O
- [x] **Networking** — `(std net smtp)`, `(std net json-rpc)`, `(std net udp)`, `(std net address)`

### Ecosystem & Tooling
- [x] **Package manager** — `(jerboa pkg)` with semver + `(jerboa lock)` with lockfiles
- [x] **Build system** — `(std build)` with module discovery, DAG ordering, content hashing
- [x] **Source translator** — `(jerboa translator)` with 20+ transform functions

### Validation & Trust
- [x] **CI pipeline** — `.github/workflows/test.yml` (GitHub Actions)
- [x] **Benchmark suite** — `benchmarks/bench-core.ss` (hash tables, match, sort, JSON, iterators, structs)
- [x] **Example applications** — `examples/hello-api.ss`, `examples/cli-tool.ss`, `examples/data-pipeline.ss`, `examples/chat-server.ss`
- [x] **Ports documentation** — `docs/ports.md`

### Documentation
- [x] **Quickstart guide** — `docs/quickstart.md`
- [x] **Migration guide** — `docs/migration.md`
- [x] **Import conflict reference** — `docs/import-conflicts.md`
- [x] **API reference generator** — `tools/gen-api-docs.ss`

- [x] **Struct patterns in prelude match** — `(jerboa prelude)` now re-exports `(std match2)`'s `match` with struct patterns, sealed hierarchies, active patterns, and `match/strict`
- [x] **Package registry** — `(jerboa registry)` with GitHub-based install/uninstall/update; `bin/jerboa install/uninstall/update/list` CLI commands
- [x] **LSP server** — `(std lsp server)` + `(std lsp symbols)` with JSON-RPC over stdio; `tools/jerboa-lsp.ss` entry point; completion, hover, go-to-definition, diagnostics
- [x] **Protocol Buffers** — `(std protobuf)` wire format encoder/decoder (proto3); varint, fixed32/64, length-delimited, zigzag, embedded messages

---

## Remaining — Gerbil Parity Sprint (50 features)

Features that Gerbil has but Jerboa does not. Organized by category.

### Core Language (4)

- [x] **1. `(std amb)`** — Nondeterministic computation with backtracking (amb, amb-find, amb-collect, amb-assert)
- [x] **2. `(std lazy)`** — Lazy streams (lazy, delay, force, lcons, ltake, ldrop, lmap, lfilter, lfold, lappend)
- [x] **3. `(std ref)`** — Generic polymorphic accessor (ref, ref-set! for lists, vectors, hash tables, strings)
- [x] **4. `(std deprecation)`** — Deprecation warnings with source location and migration hints

### Data Structures (7)

- [x] **5. `(std misc plist)`** — Property lists (pget, pput, pdel, plist->alist, alist->plist, plist-keys)
- [x] **6. `(std misc evector)`** — Expandable/growable vectors (make-evector, evector-push!, evector-pop!, evector-ref, evector->vector)
- [x] **7. `(std misc rbtree)`** — Red-black balanced BST (rbtree-insert, rbtree-lookup, rbtree-delete, rbtree-fold, rbtree->list)
- [x] **8. `(std misc decimal)`** — Exact decimal arithmetic (decimal+, decimal*, decimal/, decimal-round, string->decimal, decimal->string)
- [x] **9. `(std misc prime)`** — Primality testing, prime generation, factorization (prime?, next-prime, primes-up-to, factorize)
- [x] **10. `(std misc dag)`** — DAG operations (make-dag, dag-add-edge!, topological-sort, dag-reachable, dag-sources, dag-sinks)
- [x] **11. `(std misc shared)`** — Thread-safe shared mutable state (make-shared, shared-ref, shared-set!, shared-update!, shared-cas!)

### Text & Encoding (4)

- [x] **12. `(std text utf16)`** — UTF-16 encoding/decoding (string->utf16, utf16->string, utf16-length, BOM handling)
- [x] **13. `(std text utf32)`** — UTF-32 encoding/decoding (string->utf32, utf32->string)
- [x] **14. `(std text base58)`** — Base58 encoding for Bitcoin/IPFS (base58-encode, base58-decode, base58check-encode)
- [x] **15. `(std text html)`** — HTML parsing and generation (html-escape, html-unescape, parse-html, html->sxml)

### Markup (3)

- [x] **16. `(std markup sxml)`** — SXML representation, construction, and manipulation (sxml:element?, sxml:attributes, sxml:children)
- [x] **17. `(std markup sxml-path)`** — XPath-like queries on SXML trees (sxpath, sxml:select, node-typeof?, node-join)
- [x] **18. `(std markup sxml-print)`** — SXML to HTML/XML serialization (sxml->html, sxml->xml, sxml->string)

### Networking (4)

- [x] **19. `(std net socks)`** — SOCKS4/5 proxy client (socks-connect, socks4-connect, socks5-connect, with-socks-proxy)
- [x] **20. `(std net s3)`** — AWS S3 client (s3-put-object, s3-get-object, s3-list-bucket, s3-delete-object, sigv4 signing)
- [x] **21. `(std net sasl)`** — SASL authentication mechanisms (sasl-plain, sasl-scram-sha-256, sasl-step)
- [x] **22. `(std net bio)`** — Buffered network I/O (make-bio-input, make-bio-output, bio-read-line, bio-read-bytes, bio-flush)

### Web (2)

- [x] **23. `(std web fastcgi)`** — FastCGI protocol (fastcgi-accept, fastcgi-respond, fastcgi-params)
- [x] **24. `(std web rack)`** — Middleware/handler composable web interface (make-app, wrap-middleware, rack-run)

### MIME (2)

- [x] **25. `(std mime struct)`** — MIME message structure (make-mime-message, mime-headers, mime-body, multipart-encode, multipart-decode)
- [x] **26. `(std mime types)`** — MIME type database (extension->mime-type, mime-type->extension, mime-type?)

### Crypto (2)

- [x] **27. `(std crypto bn)`** — Big number arithmetic (bn+, bn*, bn-mod, bn-expt-mod, bn->bytevector, bytevector->bn)
- [x] **28. `(std crypto dh)`** — Diffie-Hellman key exchange (dh-generate-parameters, dh-generate-key, dh-compute-shared)

### Database (2)

- [x] **29. `(std db dbi)`** — Generic database interface (dbi-connect, dbi-query, dbi-exec, dbi-prepare, dbi-with-transaction)
- [x] **30. `(std db conpool)`** — Database connection pooling (make-connection-pool, pool-acquire, pool-release, with-connection)

### Parser Framework (2)

- [x] **31. `(std parser deflexer)`** — Lexer definition macro (deflexer, define-token, lex-string, lex-port)
- [x] **32. `(std parser defparser)`** — Parser definition macro with grammar rules (defparser, define-rule, parse)

### Protobuf Enhanced (2)

- [x] **33. `(std protobuf macros)`** — defmessage macro for defining proto3 message types as Scheme records
- [x] **34. `(std protobuf grammar)`** — .proto file parser (read-proto-file, proto->scheme)

### Debug (3)

- [x] **35. `(std debug heap)`** — Heap introspection and GC stats (heap-size, gc-count, gc-time, object-counts)
- [x] **36. `(std debug memleak)`** — Memory leak detection (track-allocation, report-leaks, with-leak-check)
- [x] **37. `(std debug threads)`** — Thread inspection and debugging (thread-list, thread-backtrace, thread-state)

### I/O (3)

- [x] **38. `(std io bio)`** — Buffered I/O with lookahead (make-buffered-input, buffered-peek, buffered-read-line, buffered-unread)
- [x] **39. `(std io strio)`** — String-based I/O with readers/writers (make-string-reader, reader-peek, reader-read-while)
- [x] **40. `(std io delimited)`** — Delimited text I/O (read-delimited, read-line*, read-until, write-delimited)

### CLI (1)

- [x] **41. `(std cli print-exit)`** — Print formatted output and exit (print-exit, print-error-exit, exit/success, exit/failure)

### SRFI (9)

- [x] **42. `(std srfi srfi-41)`** — Streams: lazy sequences (stream-cons, stream-null, stream-car, stream-cdr, stream-map, stream-filter, stream-fold)
- [x] **43. `(std srfi srfi-42)`** — Eager comprehensions (do-ec, list-ec, vector-ec, sum-ec, every?-ec, first-ec)
- [x] **44. `(std srfi srfi-113)`** — Sets and bags (set, bag, set-adjoin, set-delete, set-union, set-intersection, set-difference)
- [x] **45. `(std srfi srfi-121)`** — Generators (make-coroutine-generator, generator->list, gmap, gfilter, gfold)
- [x] **46. `(std srfi srfi-132)`** — Sort libraries (list-sort, list-stable-sort, vector-sort, vector-stable-sort, list-merge, vector-merge)
- [x] **47. `(std srfi srfi-133)`** — Extended vector library (vector-unfold, vector-map, vector-for-each, vector-fold, vector-count, vector-index)
- [x] **48. `(std srfi srfi-134)`** — Immutable deques (ideque, ideque-front, ideque-back, ideque-add-front, ideque-add-back, ideque-remove-front)
- [x] **49. `(std srfi srfi-144)`** — Flonum library (fl+, fl*, flsqrt, flexp, fllog, flsin, flcos, fl=, fl<, flonum constants)
- [x] **50. `(std srfi srfi-158)`** — Generators and accumulator (generator, circular-generator, make-accumulator, generator-fold, generator-for-each)

### Networking Polish (existing)

- **HTTP client API compat** — header format differences vs Gerbil
