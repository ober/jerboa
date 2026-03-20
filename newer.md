# Newer: Porting-Driven Feature Roadmap

Features prioritized by direct impact on porting `~/mine/gerbil-*` to `~/mine/jerboa-*`.
Based on analysis of 45 gerbil projects (3,400+ .ss files), 4 existing jerboa ports,
and 1,200+ lines of compatibility shims that shouldn't need to exist.

---

## Priority 1: Compat Shim Killers

These features directly eliminate code in the existing jerboa-es-proxy (640 lines)
and jerboa-shell (849 lines) compatibility shims. Every line of compat shim is a
maintenance burden and a source of subtle bugs.

### 1. Gambit Compatibility Layer (`lib/std/gambit-compat.sls`)

**Impact:** Eliminates 400+ lines of duplicated compat code across jerboa-es-proxy and jerboa-shell.

The #1 pain point in every port. Both jerboa-es-proxy and jerboa-shell independently
wrote their own `(compat gambit)` modules with overlapping functionality. This should
be in jerboa's stdlib so every port doesn't reinvent it.

Must provide:
- **u8vector aliases**: `make-u8vector`, `u8vector-ref`, `u8vector-set!`, `u8vector-length`, `u8vector->list`, `list->u8vector`, `subu8vector`, `u8vector-append`, `u8vector?` (all mapping to Chez bytevector ops)
- **f64vector aliases**: `make-f64vector`, `f64vector-ref`, `f64vector-set!`, `f64vector-length` (mapping to Chez flvector)
- **String/bytes conversion**: `string->bytes`, `bytes->string` (UTF-8), `object->string` (like Gerbil's `~s` format)
- **Void handling**: `void`, `void?` (Chez has `(void)` but not `void?`)
- **Box type**: `box`, `box?`, `unbox`, `set-box!` (Chez has these but they may conflict — re-export cleanly)
- **Random**: `random-integer` (Chez has `random` but different API)
- **Display**: `display-exception` (format any condition for human reading)
- **Process info**: `##cpu-count` / `cpu-count` (via `(machine-type)` or FFI)
- **Port utilities**: `call-with-input-string`, `call-with-output-string`, `open-input-u8vector`, `open-output-u8vector`, `get-output-u8vector`
- **GC interface**: `##gc` / `collect`, `##get-live-percent`

This is not about being Gambit — it's about having one canonical place for these
primitives so every port doesn't write its own buggy version.

### 2. Process Management Expansion (`lib/std/misc/process.sls` enhancement)

**Impact:** Eliminates 200+ lines of FFI process code in jerboa-shell's compat shim.

jerboa already has `run-process` and `open-process` but the shell port needed to
write its own `process-status` with FFI waitpid, `process-pid`, and terminal control.
Expand the existing module:

- **`process-pid`**: Get PID from a process port (the shell wrote FFI for this)
- **`process-status` with waitpid options**: WNOHANG, WUNTRACED (shell needs non-blocking wait)
- **`process-kill`**: Send signal to process (currently requires FFI `kill`)
- **`file-info` record**: `file-size`, `file-mtime`, `file-atime`, `file-mode`, `file-type`, `file-uid`, `file-gid` via FFI stat (shell wrote 8 separate FFI calls for this)
- **`user-info`**: `user-name`, `user-home` via getpwuid/getpwnam
- **`tty?`**: Test if a port is a terminal (isatty FFI)
- **`tty-mode-set!`**: Raw/cooked terminal mode (shell wrote its own)

### 3. Spawn & Basic Concurrency (`lib/std/concurrency.sls` or prelude addition)

**Impact:** Used in 460 call sites across gerbil projects. Both jerboa-es-proxy and jerboa-shell shim this.

Gerbil's `spawn` is everywhere. Chez has `fork-thread` but the API differs:

- **`spawn`**: `(spawn thunk)` — create and start a thread, return thread object
- **`spawn/name`**: `(spawn/name name thunk)` — named thread (199 occurrences in gerbil projects)
- **`spawn/group`**: `(spawn/group name thunk)` — thread group (19 occurrences)
- **`thread-sleep!`**: Seconds-based sleep (Chez has `sleep` with time objects — bridge the gap)
- **`with-lock`**: `(with-lock mutex thunk)` — already in sugar.sls, ensure it works with spawn

---

## Priority 2: Most-Imported Missing Modules

These are the modules imported 50+ times across gerbil projects that jerboa
doesn't yet provide (or provides incompletely).

### 4. Iterator Protocol (`lib/std/iter.sls`)

**Impact:** 228 imports across gerbil projects. The #1 missing module by import count.

Gerbil's iterator system is used constantly for concise data processing:

```scheme
(for/collect ((x (in-range 10))) (* x x))         ; => (0 1 4 9 16 ...)
(for/fold ((sum 0)) ((x (in-list '(1 2 3)))) (+ sum x))  ; => 6
(for ((k v) (in-hash ht))) (printf "~a: ~a\n" k v))
```

Must provide:
- **Generators**: `in-range`, `in-list`, `in-vector`, `in-string`, `in-hash`, `in-iota`, `in-port`, `in-lines`, `in-naturals`, `in-indexed`
- **Consumers**: `for`, `for/collect`, `for/fold`, `for/or`, `for/and`
- **Transformers**: `in-filter`, `in-map`, `in-take`, `in-drop`, `in-zip`
- Protocol should be macro-based for zero-overhead iteration (no closure allocation in tight loops)

### 5. SRFI-13 String Library (`lib/std/srfi/srfi-13.sls`)

**Impact:** 349 imports. The #3 most-imported module overall.

jerboa's `(std misc string)` covers the basics but SRFI-13 is much richer.
Many gerbil projects import SRFI-13 directly. Provide the full standard:

- **Predicates**: `string-null?`, `string-every`, `string-any`
- **Constructors**: `string-tabulate`, `string-unfold`, `string-unfold-right`
- **Selection**: `string-take`, `string-drop`, `string-take-right`, `string-drop-right`, `string-pad`, `string-pad-right`
- **Comparison**: `string-ci=`, case-insensitive variants
- **Searching**: `string-count`, `string-contains-ci`, `string-skip`, `string-skip-right`
- **Folding**: `string-fold`, `string-fold-right`, `string-for-each-index`
- **Modification**: `string-replace`, `string-delete`, `string-filter`
- **Reverse**: `string-reverse`, `string-concatenate`, `string-concatenate-reverse`

### 6. SRFI-1 List Library (`lib/std/srfi/srfi-1.sls`)

**Impact:** 107 imports. Many functions used 100+ times each.

jerboa's `(std misc list)` has `take`, `drop`, `any`, `every`, `filter-map`, but
SRFI-1 is much larger and gerbil projects expect the full set:

- **Constructors**: `iota`, `circular-list`, `list-tabulate`, `cons*`
- **Predicates**: `proper-list?`, `circular-list?`, `null-list?`, `not-pair?`
- **Selectors**: `first`..`tenth`, `take-right`, `drop-right`, `split-at`, `last`, `last-pair`
- **Fold/unfold**: `fold`, `fold-right`, `unfold`, `unfold-right`, `reduce`, `reduce-right`
- **Mapping**: `map!`, `filter-map`, `append-map`, `pair-for-each`
- **Filtering**: `partition`, `remove`, `span`, `break`
- **Searching**: `find`, `any`, `every`, `list-index`, `take-while`, `drop-while`
- **Set operations**: `lset-union`, `lset-intersection`, `lset-difference`, `lset-adjoin`
- **Association lists**: `alist-cons`, `alist-copy`, `alist-delete`

### 7. List Builder (`lib/std/misc/list-builder.sls`)

**Impact:** 31 imports, 108 occurrences. Small but extremely useful macro.

```scheme
(with-list-builder (push!)
  (for-each (lambda (x)
              (when (> x 3) (push! x)))
            '(1 5 2 7 3 8)))
; => (5 7 8)
```

Eliminates the reverse-accumulator pattern that litters imperative Scheme code.
One macro, huge ergonomic win.

### 8. Number Utilities (`lib/std/misc/number.sls`)

**Impact:** 59 imports across gerbil projects.

- **Parsing**: `string->number/base`, `number->string` with radix and padding
- **Predicates**: `natural?`, `positive-integer?`, `negative?`
- **Arithmetic**: `clamp`, `divmod`, `integer-length`
- **Formatting**: `number->padded-string`, `number->human-readable` (1024 -> "1K")
- **Conversion**: `fixnum->flonum`, `integer->char-hex`

### 9. Date & Time (SRFI-19) (`lib/std/srfi/srfi-19.sls`)

**Impact:** 44 imports. Essential for any project that touches timestamps.

The jerboa-es-proxy compat shim includes a partial `date->string` implementation.
Provide the full SRFI-19:

- **Time types**: `current-time`, `time-utc`, `time-tai`, `time-duration`
- **Time operations**: `time-difference`, `add-duration`, `subtract-duration`
- **Date type**: `make-date`, `date->string`, `string->date`
- **Date fields**: `date-year`, `date-month`, `date-day`, `date-hour`, `date-minute`, `date-second`
- **Conversion**: `time-utc->date`, `date->time-utc`, `date->julian-day`
- **Formatting**: `date->string` with `~Y-~m-~d ~H:~M:~S` template syntax

### 10. Temporary Files & Directories (`lib/std/os/temporaries.sls`)

**Impact:** 37 imports. Used by any program that does file processing.

jerboa has `with-temp-directory` in `(std os path-util)` but Gerbil's
`(std os temporaries)` has a richer API:

- **`make-temporary-file-name`**: Generate unique temp path
- **`with-temporary-file`**: Scoped temp file with cleanup
- **`with-temporary-directory`**: Scoped temp dir with cleanup
- **`temporary-file-directory`**: Get/set temp dir (respects `TMPDIR`)
- **`create-temporary-file`**: Create and return path + port

---

## Priority 3: Porting Accelerators

Features that appear 20-50 times in imports but enable entire categories of ports.

### 11. Structured Logging (`lib/std/logging.sls`)

**Impact:** 51 imports across 6 gerbil projects. Every production service needs this.

jerboa has `(std logger)` — verify it provides the Gerbil-compatible API:

- **`deflogger`**: Define a module-level logger with category
- **Level functions**: `debugf`, `infof`, `warnf`, `errorf`, `criticalf`
- **Configuration**: `start-logger!`, `current-logger`, `current-log-level`
- **Output**: Formatted timestamps, log level, category, message
- **Rotation**: Optional file rotation by size/time

### 12. HTTP Client Improvements (`lib/std/net/request.sls` enhancement)

**Impact:** 53 imports, 15 projects. Already exists but needs Gerbil API compat.

The jerboa-es-proxy compat shim wraps jerboa's HTTP client to match Gerbil's API.
Key differences to resolve:

- **Headers format**: Gerbil uses `(("Name" . "Value") ...)` dotted pairs. jerboa uses `("Name" :: "Value")` triples. Pick one and provide the other as a helper.
- **SSL context**: `(insecure-client-ssl-context)` — Gerbil pattern for dev/testing
- **Streaming**: `http-request` with streaming response body
- **Cookies**: Basic cookie jar support
- **Timeouts**: Connection and read timeouts

### 13. URI/URL Parsing (`lib/std/net/uri.sls`)

**Impact:** 26 imports. Required for any HTTP/API work.

- **`uri-parse`**: Parse URI string into components
- **`uri-scheme`**, **`uri-host`**, **`uri-port`**, **`uri-path`**, **`uri-query`**, **`uri-fragment`**
- **`uri-encode`** / **`uri-decode`**: Percent-encoding
- **`uri->string`**: Reconstruct URI from components
- **`query-string->alist`** / **`alist->query-string`**: Form data

### 14. Crypto Digest (`lib/std/crypto/digest.sls`)

**Impact:** 57 imports across 16 projects. jerboa has `(std crypto)` modules — ensure digest coverage.

Must provide:
- **`digest`**: Generic digest function accepting algorithm symbol
- **`sha256`**, **`sha1`**, **`md5`**: Direct convenience functions
- **`hmac`**: HMAC with any digest algorithm
- **Streaming**: `open-digest`, `digest-update!`, `digest-final!` for large data
- **`random-bytes`**: Cryptographically secure random bytes

### 15. Assertion Library (`lib/std/assert.sls`)

**Impact:** 37 imports. Used for defensive programming.

```scheme
(assert! (> x 0))                    ; raises with source location
(assert! (string? name) "expected string")  ; custom message
```

jerboa has `assert!` in `(std sugar)` — verify it matches Gerbil's:
- Reports the failing expression in the error message
- Supports optional message argument
- Optionally includes source location

### 16. Configuration (`lib/std/config.sls` enhancement)

**Impact:** 16 imports. Used by services and CLI tools.

Gerbil's config module provides:
- **`defconfig`**: Declare config keys with defaults and types
- **`getconfig`**: Read config value (env var > config file > default)
- **Config file formats**: INI-style and s-expression
- **`config-path`**: XDG-compliant config directory resolution

### 17. Path Utilities (`lib/std/misc/path.sls`)

**Impact:** 47 imports. jerboa has path ops in prelude but not as a standalone module.

Some gerbil projects import `(std misc path)` specifically. Provide as a
re-exporting module or expand with:

- **`path-default-extension`**: Add extension only if none exists
- **`path-normalize`**: Resolve `.` and `..` components
- **`path-relative?`**: Test for relative path
- **`path-split`**: Split into components list
- **`subpath`**: Safe path joining that prevents directory traversal

### 18. Multiple Values Utilities (`lib/std/values.sls`)

**Impact:** 18 imports. Small but fills an ergonomic gap.

- **`values->list`**: Convert multiple values to a list
- **`values-map`**: Map over multiple values
- **`values-filter`**: Filter multiple values
- **`let-values`** / **`receive`**: SRFI-8/11 binding forms (Chez has `let-values` but `receive` is convenient)
- **`values-count`**: Number of values returned

---

## Priority 4: Enabling Specific Project Ports

Each of these enables porting one or more specific gerbil projects.

### 19. Channels (`lib/std/misc/channel.sls`)

**Impact:** 14 imports, but `<-` (channel receive) appears 2,057 times. Enables gerbil-shell, gerbil-tui, gerbil-signal.

Go-style unbuffered and buffered channels:

- **`make-channel`** / **`make-channel/bounded`**: Create channels
- **`channel-put`** / **`channel-get`**: Send/receive (blocking)
- **`channel-try-put`** / **`channel-try-get`**: Non-blocking variants
- **`channel-close`**: Close a channel
- **`channel-closed?`**: Test if closed
- **`select`**: Wait on multiple channels (like Go's `select`)

### 20. Actor Enhancements (`lib/std/actor.sls` expansion)

**Impact:** 48 imports across 3 large projects (gerbil-origin, gerbil-shell, gerbil-lsp).

jerboa has `(std actor)` — verify it provides Gerbil-compatible patterns:

- **`defproto`**: Protocol definition macro
- **`@message`**: Message dispatch
- **`!!`** / **`<-`**: Send/receive operators
- **`start-actor!`**: Actor lifecycle
- **Remote actors**: TCP transport for distributed systems
- **Supervisors**: Restart strategies (one-for-one, one-for-all)

### 21. Parser Combinators (`lib/std/parser.sls`)

**Impact:** 14 imports each for `parser/ll1` and `parser/base`. Enables gerbil-lsp, gerbil-emacs.

- **Base**: `token`, `satisfy`, `literal`, `eof`
- **Combinators**: `seq`, `alt`, `many`, `many1`, `optional`, `between`, `sep-by`
- **LL(1)**: `deflexer`, `defparser` macros for grammar-driven parsing
- **Error reporting**: Position tracking with line/column

### 22. XML/SXML Utilities (`lib/std/markup/xml.sls` or `lib/std/text/xml.sls` compat)

**Impact:** 13 imports. jerboa has `(std text xml)` but gerbil imports `(std markup xml)`.

Ensure API compatibility:
- **`read-xml`** / **`write-xml`**: Parse/serialize XML
- **`xml->sxml`** / **`sxml->xml`**: SXML conversion
- **`sxml-select`**: XPath-like queries on SXML trees
- Provide `(std markup xml)` as an alias if jerboa uses `(std text xml)`

### 23. Weak Alist (`lib/std/misc/walist.sls`)

**Impact:** 13 imports, 214 occurrences. Used for caches and observers.

Association list backed by weak references — entries are automatically
removed when keys are garbage collected:

- **`make-walist`**: Create a weak alist
- **`walist-ref`** / **`walist-set!`**: Get/set entries
- **`walist->alist`**: Snapshot to regular alist
- Chez has `weak-cons` and `bwp-object?` which make this implementable

### 24. Interface Protocol (`lib/std/interface.sls`)

**Impact:** 15 imports. Enables type-safe dispatch patterns.

Gerbil's interface system:

```scheme
(definterface Printable
  (to-string))

(defmethod {to-string my-record}
  (format "MyRecord(~a)" (my-record-field self)))
```

- **`definterface`**: Declare required methods
- **`implements?`**: Runtime check
- **Interface dispatch**: Method tables for protocol-based programming

### 25. Generic Functions (`lib/std/generic.sls`)

**Impact:** 20 imports. Enables CLOS-like dispatch.

```scheme
(defgeneric describe (obj))
(defspecific (describe (obj <string>)) (format "String: ~a" obj))
(defspecific (describe (obj <number>)) (format "Number: ~a" obj))
```

- **`defgeneric`**: Declare a generic function
- **`defspecific`** / **`defmethod`**: Add specializations
- **Type-based dispatch**: Using Chez's record system for type discrimination

---

## Priority 5: Quality-of-Life for Large Ports

These aren't missing modules but cross-cutting improvements that reduce
friction across every port.

### 26. Import Conflict Resolution Guide & Helpers

**The #1 developer experience problem** in jerboa porting. Every jerboa-* project
has dozens of `(except ...)` clauses because names collide between `(chezscheme)`,
`(jerboa core)`, and `(std ...)` modules.

Known conflicts from the existing ports:
- `(chezscheme)` vs jerboa: `sort`, `filter`, `format`, `printf`, `fprintf`, `iota`, `1+`, `1-`, `getenv`, `make-hash-table`, `box`, `box?`, `unbox`, `set-box!`, `path-extension`, `path-absolute?`, `make-mutex`, `mutex?`
- `(std misc string)` vs `(jerboa core)`: `string-split`, `string-join`, `string-index`, `string-trim`, `string-prefix?`
- `(std misc list)` vs `(jerboa core)`: `any`, `every`, `take`, `drop`, `filter-map`
- `(std format)` vs `(chezscheme)`: `format`

Solutions:
- **`(jerboa prelude/clean)`**: A prelude variant that does NOT re-export conflicting Chez names, so `(import (chezscheme) (jerboa prelude/clean))` just works
- **`(std compat/import-sets)`**: Pre-built `(except ...)` sets: `(import (chezscheme (except-jerboa-conflicts)))`
- **Document the full conflict matrix** in a reference file

### 27. Gerbil Source Translator Improvements

Both jerboa-es-proxy and jerboa-shell have source translators (build-jerboa.ss).
Common transformations that could be shared:

- **`#:keyword`** syntax → quoted symbols or Chez keyword objects
- **`[x y]`** bracket forms → context-dependent list/binding normalization
- **`##gambit-primitive`** → Chez equivalent or FFI shim
- **`defstruct`** → R6RS `define-record-type` expansion
- **`let-hash`** → binding form expansion
- **`using`** → method dispatch expansion
- **`parameterize`** differences (Chez `parameterize` is thread-local; Gerbil's is not)

A shared `(jerboa translator)` library would prevent each port from
reinventing these transformations.

### 28. Build System (`lib/jerboa/build.sls`)

Every jerboa-* project needs a build script. A standard build system would provide:

- **`define-library-target`**: Compile .sls to .so
- **`define-program-target`**: Compile to standalone executable
- **`define-test-target`**: Run test files
- **Dependency tracking**: Only recompile changed files
- **Library path management**: Automatic `--libdirs` configuration
- **Cross-project dependencies**: Pull in other jerboa-* libraries

### 29. Test Framework Enhancements (`lib/std/test.sls`)

**Impact:** 411 imports (test is the 3rd most-imported module overall).

jerboa has `(std test)` — ensure it matches Gerbil's `:std/test` API:

- **`check`** with `=>`: `(check (+ 1 2) => 3)`
- **`check-equal?`**, **`check-pred`**, **`check-exn`**
- **`test-suite`** / **`test-case`**: Structured test organization
- **`run-tests!`**: Discover and run all tests
- **Output**: TAP or human-readable format with colors
- **`check-output`**: Capture and compare stdout/stderr

### 30. SRFI Compatibility Bundle

Several SRFIs appear repeatedly in gerbil projects. Provide a compatibility layer:

| SRFI | Imports | Purpose | Status in Chez |
|------|---------|---------|----------------|
| SRFI-1 | 107 | List library | Partial (via misc/list) |
| SRFI-13 | 349 | String library | Partial (via misc/string) |
| SRFI-19 | 44 | Date/time | Not provided |
| SRFI-26 | ~100 | `cut`/`cute` | In sugar.sls |
| SRFI-43 | 10 | Vector library | Chez has most ops |
| SRFI-115 | 12 | Regex | Via pregexp |
| SRFI-128 | 10 | Comparators | Not provided |
| SRFI-141 | 15 | Integer division | Chez has most ops |
| SRFI-146 | 16 | Mappings | Not provided |

For SRFIs that Chez mostly covers (43, 141), thin wrappers suffice.
For SRFIs Chez lacks (1, 13, 19, 128, 146), full implementations needed.

---

## Summary: Effort vs. Impact Matrix

| # | Feature | Effort | Impact | Unblocks |
|---|---------|--------|--------|----------|
| 1 | Gambit compat layer | Medium | **Critical** | Every port |
| 2 | Process management | Medium | **Critical** | jerboa-shell, jerboa-coreutils |
| 3 | Spawn & concurrency | Small | **Critical** | Every concurrent port |
| 4 | Iterator protocol | Large | **High** | Most ports |
| 5 | SRFI-13 strings | Medium | **High** | Most ports |
| 6 | SRFI-1 lists | Medium | **High** | Most ports |
| 7 | List builder | Small | Medium | 31 import sites |
| 8 | Number utilities | Small | Medium | 59 import sites |
| 9 | SRFI-19 date/time | Medium | Medium | Timestamp-heavy ports |
| 10 | Temporaries | Small | Medium | File-processing ports |
| 11 | Structured logging | Medium | Medium | Production services |
| 12 | HTTP client fixes | Small | Medium | API client ports |
| 13 | URI parsing | Small | Medium | Web-related ports |
| 14 | Crypto digest | Small | Medium | Security-related ports |
| 15 | Assertions | Small | Low | Defensive code |
| 16 | Configuration | Medium | Low | Service ports |
| 17 | Path utilities | Small | Low | Already mostly covered |
| 18 | Values utilities | Small | Low | 18 import sites |
| 19 | Channels | Medium | Medium | Concurrent ports |
| 20 | Actor enhancements | Large | Medium | 3 large projects |
| 21 | Parser combinators | Large | Low | 2 projects |
| 22 | XML compat | Small | Low | Module path alias |
| 23 | Weak alist | Small | Low | Cache patterns |
| 24 | Interface protocol | Medium | Low | Type-safe dispatch |
| 25 | Generic functions | Medium | Low | CLOS-like patterns |
| 26 | Import conflict guide | Small | **High** | Developer experience |
| 27 | Source translator | Large | **High** | Every port |
| 28 | Build system | Large | Medium | Project structure |
| 29 | Test framework | Medium | Medium | All test suites |
| 30 | SRFI bundle | Large | **High** | API compatibility |

**Recommended execution order:** 1, 3, 26, 7, 5, 6, 4, 2, 9, 10, 12, 13, 14, 8, 11, 19, 29, 30.
Start with compat shim killers and the easy wins, then build up the module ecosystem.

---

## Appendix: Gerbil Import Frequency Data

Top 30 most-imported modules across 45 gerbil-* projects (3,418 .ss files):

```
  987  :std/sugar
  411  :std/test
  379  :std/format
  357  :std/error
  349  :std/srfi/13
  284  :gerbil/gambit
  241  :std/cli/getopt
  228  :std/iter
  203  :std/sort
  176  :std/misc/ports
  166  :std/text/json
  124  :std/foreign
  120  :std/misc/process
  112  :std/misc/string
  107  :std/srfi/1
   94  :std/pregexp
   80  :std/misc/list
   79  :std/text/base64
   72  :std/io
   64  :std/text/hex
   59  :std/misc/number
   57  :std/crypto/digest
   56  :std/text/utf8
   53  :std/net/request
   51  :std/logger
   48  :std/actor
   47  :std/misc/path
   46  :std/misc/repr
   44  :std/srfi/19
   37  :std/assert
```
