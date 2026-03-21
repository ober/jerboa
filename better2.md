# Better2: 30 More Features for Gerbil→Jerboa Translation

Second round of features identified from analysis of 45 gerbil-* repos, Chez Scheme 10.4.0,
and real translation gaps discovered during jerboa-shell and jerboa-emacs porting.

---

## Translator Enhancements (1–5)

### 1. `translate-using` — Method Dispatch with `using`
**Status:** DONE
**File:** `lib/jerboa/translator.sls`

Translate Gerbil's `using` operator (735 usage sites across gerbil-* repos):
- `(using obj Type method)` → `(Type-method obj)` accessor call
- Critical for gerbil-origin, gerbil-litehtml, gerbil-persist

**Impact:** 735 usage sites; blocks most OOP-heavy ports.

### 2. `translate-define-values` — Multiple Value Binding
**Status:** DONE
**File:** `lib/std/sugar.sls` + `lib/jerboa/translator.sls`

Add `define-values` macro (223 usage sites):
- `(define-values (a b c) (values 1 2 3))`
- Sugar form for binding multiple return values at top level

**Impact:** 223 call sites across gerbil projects.

### 3. `translate-hash-operations` — Hash API Normalization
**Status:** DONE
**File:** `lib/jerboa/translator.sls`

Normalize remaining Gerbil hash operations to jerboa equivalents:
- `(hash-ref ht key)` (2-arg, errors) → passes through (jerboa has it)
- `(hash-set! ht key val)` → `(hash-put! ht key val)` (rename)
- `(hash-delete! ht key)` → `(hash-remove! ht key)` (rename)
- `(hash-contains? ht key)` → `(hash-key? ht key)` (rename)

**Impact:** 300+ sites using Gerbil hash naming.

### 4. `translate-gerbil-void` — Variadic void Compatibility
**Status:** DONE
**File:** `lib/jerboa/translator.sls`

Gerbil's `void` is variadic (accepts any args, returns void). Chez's `void` takes 0 args.
`(with-catch void thunk)` crashes in Chez because the handler calls `(void error)`.
- `(void)` → passes through
- `(void expr ...)` → `(begin expr ... (void))` or `(lambda _ (void))` in handler context

**Impact:** Every project using `(with-catch void ...)` pattern.

### 5. `translate-import-paths` — Module Path Normalization
**Status:** DONE
**File:** `lib/jerboa/translator.sls`

Normalize Gerbil import paths to R6RS library names:
- `:std/sugar` → `(std sugar)`
- `:std/misc/string` → `(std misc string)`
- `:std/text/json` → `(std text json)`
- Handle `(only-in ...)`, `(except-in ...)`, `(rename-in ...)`

**Impact:** Every Gerbil file needs this.

---

## Missing Stdlib Completions (6–15)

### 6. `(std misc hash-more)` Completion — fold, find, clear, copy
**Status:** DONE
**File:** `lib/std/misc/hash-more.sls`

Add missing hash operations (184 usage sites):
- `hash-fold` — fold over entries
- `hash-find` — find first matching entry
- `hash-clear!` — clear all entries
- `hash-copy` — shallow copy
- `hash-merge` — merge (already in gambit-compat, need in hash-more)
- `hash-keys`, `hash-values` — extract keys/values as lists

**Impact:** 184 usage sites across gerbil projects.

### 7. `(std iter)` Completion — in-port, in-lines, in-chars, in-bytes
**Status:** DONE
**File:** `lib/std/iter.sls`

Add I/O iterators missing from iter.sls:
- `in-port` — iterate over datums from a port (using read)
- `in-lines` — iterate over lines from a port (using read-line)
- `in-chars` — iterate over characters from a port
- `in-bytes` — iterate over bytes from a binary port
- `in-producer` — iterate over results of a thunk until EOF

**Impact:** Common pattern in file-processing code.

### 8. `(std source)` — Source Location Tracking
**Status:** DONE
**File:** `lib/std/source.sls`

Compile-time source location macros (10 import sites):
- `this-source-file` — expands to current file path string
- `this-source-directory` — expands to directory of current file
- `this-source-location` — expands to `(file line column)` list
- Leverages Chez's `source-condition` and annotation system

**Impact:** Used in logging, error reporting, and build systems.

### 9. `(std misc wg)` — Wait Groups
**Status:** DONE
**File:** `lib/std/misc/wg.sls`

Go-style wait group for thread coordination:
- `make-wg` — create wait group
- `wg-add` — increment pending count
- `wg-done` — decrement (signal completion)
- `wg-wait` — block until count reaches 0
- Complements barriers (fixed N) with dynamic count

**Impact:** Common concurrency pattern in gerbil-origin, gerbil-persist.

### 10. `(std text/char-set)` — Character Sets
**Status:** DONE
**File:** `lib/std/text/char-set.sls`

Character set operations for text processing:
- `char-set`, `char-set?`, `char-set-contains?`
- `char-set:letter`, `char-set:digit`, `char-set:whitespace`
- `char-set-union`, `char-set-intersection`, `char-set-complement`
- `char-set->list`, `string->char-set`
- Used by parsers, validators, tokenizers

**Impact:** Foundation for text processing modules.

### 11. `(std os/temp)` — Temporary Files/Directories
**Status:** DONE
**File:** `lib/std/os/temp.sls`

Temporary file management:
- `make-temporary-file` — create temp file, return path
- `make-temporary-directory` — create temp dir, return path
- `call-with-temporary-file` — auto-cleanup on exit
- `call-with-temporary-directory` — auto-cleanup on exit
- Uses Chez's foreign-procedure for mkstemp/mkdtemp

**Impact:** Test suites, build systems, data processing pipelines.

### 12. `(std os/file-info)` — File Metadata via stat
**Status:** DONE
**File:** `lib/std/os/file-info.sls`

File metadata access:
- `file-info` — returns record with size, mtime, mode, uid, gid
- `file-size`, `file-mtime`, `file-mode` — individual accessors
- `file-type` — regular, directory, symlink, pipe, socket
- `file-executable?`, `file-readable?`, `file-writable?`
- Uses Chez's foreign-procedure for stat(2)

**Impact:** 200+ lines of FFI in jerboa-shell compat; every project touching files.

### 13. `(std os/pipe)` — Pipe Operations
**Status:** DONE
**File:** `lib/std/os/pipe.sls`

Unix pipe operations:
- `open-pipe` — create pipe, return (input-port . output-port)
- `pipe->ports` — convert pipe fds to Scheme ports
- Uses Chez's foreign-procedure for pipe(2)

**Impact:** Process pipelines, IPC between threads.

### 14. `(std os/tty)` — Terminal Control
**Status:** DONE
**File:** `lib/std/os/tty.sls`

Terminal detection and raw mode:
- `tty?` — is port a terminal?
- `tty-size` — (values rows cols)
- `tty-raw-mode!` — set terminal to raw mode
- `tty-cooked-mode!` — restore cooked mode
- `with-raw-mode` — RAII wrapper
- Uses Chez FFI for isatty, ioctl TIOCGWINSZ, tcsetattr

**Impact:** jerboa-shell and jerboa-emacs both need this.

### 15. `(std text/ini)` — INI File Parsing
**Status:** DONE
**File:** `lib/std/text/ini.sls`

Simple INI/config file parser:
- `ini-read` — parse INI file to nested alist
- `ini-write` — write alist as INI file
- `ini-ref` — lookup section.key
- Handles sections, comments (#, ;), key=value pairs

**Impact:** Config files in jerboa-shell, various utilities.

---

## Chez Scheme Power Features (16–23)

### 16. `(std guardian)` — GC Guardians for Resource Cleanup
**Status:** DONE
**File:** `lib/std/guardian.sls`

Expose Chez's guardian system (GC-triggered cleanup):
- `make-guardian` — create a guardian
- `guardian-register!` — register object for finalization
- `guardian-drain!` — collect all finalized objects
- Pattern for auto-closing file handles, freeing foreign memory

**Impact:** Memory-safe resource management without explicit close.

### 17. `(std trace)` — Function Tracing & Debugging
**Status:** DONE
**File:** `lib/std/trace.sls`

Expose Chez's tracing system:
- `trace-define` — define with automatic call tracing
- `trace-lambda` — lambda with tracing
- `trace-let` — let with tracing
- `untrace` — remove tracing
- `trace-output-port` — control trace output destination

**Impact:** Interactive debugging without external tools.

### 18. `(std compile)` — Compilation Utilities
**Status:** DONE
**File:** `lib/std/compile.sls`

Expose Chez's compilation infrastructure:
- `compile-file` — compile .sls to .so
- `compile-whole-program` — whole-program optimization
- `compile-to-port` — compile to binary port
- `optimize-level` — get/set optimization level (0-3)
- `generate-wpo-files` — enable whole-program optimization files

**Impact:** Build systems, deployment, performance optimization.

### 19. `(std symbol-property)` — Symbol Property Lists
**Status:** DONE
**File:** `lib/std/symbol-property.sls`

Expose Chez's symbol property system:
- `putprop` — attach property to symbol
- `getprop` — retrieve property from symbol
- `remprop` — remove property
- `property-list` — get all properties of a symbol
- Unique to Chez: per-symbol key-value store without external hash table

**Impact:** Code generation, macro metadata, DSL implementation.

### 20. `(std fixnum)` — Extended Fixnum Operations
**Status:** DONE
**File:** `lib/std/fixnum.sls`

Re-export Chez's fixnum-specific operations:
- `fx+`, `fx-`, `fx*`, `fxdiv`, `fxmod` — fixnum arithmetic
- `fxlogand`, `fxlogor`, `fxlogxor`, `fxlognot` — bitwise
- `fxsll`, `fxsrl`, `fxsra` — shifts
- `fx=`, `fx<`, `fx>`, `fx<=`, `fx>=` — comparisons
- `fixnum-width`, `greatest-fixnum`, `least-fixnum`

**Impact:** Performance-critical inner loops, protocol parsing.

### 21. `(std port-position)` — Port Position Tracking
**Status:** DONE
**File:** `lib/std/port-position.sls`

Expose Chez's port position API:
- `port-position` — current position in port
- `set-port-position!` — seek to position
- `port-has-port-position?` — can this port report position?
- `port-has-set-port-position!?` — can this port seek?
- `port-length` — total length (for file ports)

**Impact:** Binary protocol parsing, file format readers, seekable I/O.

### 22. `(std record-meta)` — Advanced Record Features
**Status:** DONE
**File:** `lib/std/record-meta.sls`

Expose Chez's advanced record type features:
- `record-type-descriptor` — get RTD from instance
- `record-constructor-descriptor` — get RCD
- `record-type-name`, `record-type-parent` — introspection
- `record-type-field-names` — list fields
- `nongenerative`, `sealed`, `opaque` — record type options
- `record-rtd` — RTD from instance (for dispatching)

**Impact:** Serialization, debugging, generic programming.

### 23. `(std cafe)` — REPL Customization
**Status:** DONE
**File:** `lib/std/cafe.sls`

Expose Chez's REPL (cafe) customization:
- `waiter-prompt-string` — customize REPL prompt
- `waiter-prompt-and-read` — custom read hook
- `new-cafe` — launch nested REPL
- `cafe-eval` — evaluate in cafe context
- `reset-handler` — custom reset behavior

**Impact:** Development tooling, embedded REPLs.

---

## Quality of Life (24–30)

### 24. `(std misc string-more)` Completion — split, replace, filter
**Status:** DONE
**File:** `lib/std/misc/string-more.sls`

Add missing string operations:
- `string-split` — split string by delimiter (117 usage sites!)
- `string-replace` — replace substring occurrences
- `string-filter` — filter characters by predicate
- `string-upcase`, `string-downcase` — case conversion
- `string-reverse` — reverse a string

**Impact:** 312 usage sites across gerbil projects.

### 25. `(std misc vector-more)` — Extended Vector Operations
**Status:** DONE
**File:** `lib/std/misc/vector-more.sls`

Vector operations matching Gerbil patterns:
- `vector-map` — already in Chez but not R6RS
- `vector-for-each` — iterate with index
- `vector-filter` — filter elements
- `vector-fold` — fold over vector
- `vector-append` — concatenate vectors
- `vector-copy` — with optional start/end

**Impact:** Data processing with vectors instead of lists.

### 26. `(std misc alist-more)` — Extended Alist Operations
**Status:** DONE
**File:** `lib/std/misc/alist-more.sls`

Alist operations beyond what's in misc/alist.sls:
- `alist-ref/default` — lookup with default
- `alist-update` — functional update
- `alist-merge` — merge two alists
- `alist-filter` — filter entries
- `alist->hash` — convert to hash table
- `hash->alist` — already in hash-more, add reverse

**Impact:** Config handling, lightweight key-value stores.

### 27. `(std misc port-utils)` — Port Convenience Functions
**Status:** DONE
**File:** `lib/std/misc/port-utils.sls`

Port utilities matching Gambit/Gerbil patterns:
- `read-all-as-string` — read entire port to string
- `read-all-as-bytes` — read entire port to bytevector
- `call-with-input-string` — open string port, call proc, close
- `call-with-output-string` — open string port, call proc, extract
- `with-output-to-string` — capture output to string
- `with-input-from-string` — read from string

**Impact:** 270 usage sites for port I/O patterns.

### 28. `(std misc numeric)` — Numeric Utilities
**Status:** DONE
**File:** `lib/std/misc/numeric.sls`

Numeric utilities from Gerbil:
- `clamp` — clamp value to range
- `lerp` — linear interpolation
- `in-range?` — range check (different from in-range iterator)
- `integer->bytevector`, `bytevector->integer` — for protocol parsing
- `number->padded-string` — zero-padded number formatting

**Impact:** Protocol implementations, data formatting.

### 29. `(std debug/pp)` — Pretty Printer
**Status:** DONE
**File:** `lib/std/debug/pp.sls`

Expose Chez's pretty printer with Gerbil-compatible API:
- `pp` — pretty-print to current output
- `pp-to-string` — pretty-print to string
- `pretty-print-columns` — control line width
- `pprint` — alias for pretty-print (Gerbil naming)

**Impact:** Debugging, REPL output, code generation.

### 30. `(std misc/with-destroy)` — Resource Management Macro
**Status:** DONE
**File:** `lib/std/misc/with-destroy.sls`

RAII-style resource management (Gerbil pattern):
- `with-destroy` — ensure cleanup on exit (normal or exception)
- `defstruct` with `:destroy` method support
- Pattern: `(with-destroy (obj (make-resource)) body ...)`
- Calls `(destroy obj)` on scope exit

**Impact:** File handles, network connections, FFI resources.

---

## Implementation Tracking

| # | Feature | Status | Tests | Docs | Committed |
|---|---------|--------|-------|------|-----------|
| 1 | translate-using | DONE | ✓ | ✓ | ✓ |
| 2 | define-values | DONE | ✓ | ✓ | ✓ |
| 3 | translate-hash-operations | DONE | ✓ | ✓ | ✓ |
| 4 | translate-gerbil-void | DONE | ✓ | ✓ | ✓ |
| 5 | translate-import-paths | DONE | ✓ | ✓ | ✓ |
| 6 | hash-more completion | DONE | ✓ | ✓ | ✓ |
| 7 | iter completion | DONE | ✓ | ✓ | ✓ |
| 8 | source location | DONE | ✓ | ✓ | ✓ |
| 9 | wait groups | DONE | ✓ | ✓ | ✓ |
| 10 | char-set | DONE | ✓ | ✓ | ✓ |
| 11 | temp files | DONE | ✓ | ✓ | ✓ |
| 12 | file-info | DONE | ✓ | ✓ | ✓ |
| 13 | pipe | DONE | ✓ | ✓ | ✓ |
| 14 | tty | DONE | ✓ | ✓ | ✓ |
| 15 | ini parser | DONE | ✓ | ✓ | ✓ |
| 16 | guardian | DONE | ✓ | ✓ | ✓ |
| 17 | trace | DONE | ✓ | ✓ | ✓ |
| 18 | compile | DONE | ✓ | ✓ | ✓ |
| 19 | symbol-property | DONE | ✓ | ✓ | ✓ |
| 20 | fixnum | DONE | ✓ | ✓ | ✓ |
| 21 | port-position | DONE | ✓ | ✓ | ✓ |
| 22 | record-meta | DONE | ✓ | ✓ | ✓ |
| 23 | cafe | DONE | ✓ | ✓ | ✓ |
| 24 | string-more completion | DONE | ✓ | ✓ | ✓ |
| 25 | vector-more | DONE | ✓ | ✓ | ✓ |
| 26 | alist-more | DONE | ✓ | ✓ | ✓ |
| 27 | port-utils | DONE | ✓ | ✓ | ✓ |
| 28 | numeric utils | DONE | ✓ | ✓ | ✓ |
| 29 | pretty printer | DONE | ✓ | ✓ | ✓ |
| 30 | with-destroy | DONE | ✓ | ✓ | ✓ |
