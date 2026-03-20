# What Changed: Newer Branch Merge

**Date:** 2026-03-20
**Commits:** 7 (4751ac3..590c7d5)
**Files changed:** 29
**Lines added:** 4,135+

This merge implements all 30 items from the porting-driven feature roadmap (`newer.md`),
adding 16 new modules, enhancing 3 existing modules, verifying 14 pre-existing modules,
and adding comprehensive documentation. The goal: make porting `gerbil-*` projects to
`jerboa-*` dramatically easier.

---

## New Modules

### `(std gambit-compat)` — One-Stop Gambit/Gerbil Compatibility
**File:** `lib/std/gambit-compat.sls`

The single most impactful addition. Import this one module and get 150+ Gambit/Gerbil
functions without writing any compat shims. Re-exports everything from `(jerboa core)`
and `(std sugar)`, plus adds:

- `u8vector-append`, `open-input-u8vector`, `open-output-u8vector`, `get-output-u8vector`
- `write-subu8vector`, `read-subu8vector`
- `f64vector->list`
- `void?`, `let/cc`, `with-exception-catcher*`, `with-unwind-protect`
- `current-second`, `date->string*` (SRFI-19 format strings)
- `getenv*`, `setenv*`, `get-environment-variables`, `cpu-count`
- `directory-files*` (Gambit settings-list style)
- `truncate-quotient`, `truncate-remainder`
- `hash-constructor` macro, `gerbil-parameterize` macro
- `pp` (pretty-print alias)

**Usage:**
```scheme
(import (except (chezscheme)
          make-hash-table hash-table? iota 1+ 1- getenv
          path-extension path-absolute?
          thread? make-mutex mutex? mutex-name
          box box? unbox set-box!)
        (std gambit-compat))
```

### `(std misc list-builder)` — O(1) Append List Builder
**File:** `lib/std/misc/list-builder.sls`

Eliminates the `reverse` accumulator pattern. Uses a sentinel head node + tail pointer
for O(1) append in insertion order.

```scheme
(with-list-builder (push!)
  (for-each (lambda (x) (when (> x 3) (push! x)))
            '(1 5 2 7 3 8)))
;; => (5 7 8)

(with-list-builder (push! peek)    ;; two-arg form with peek
  (push! 'a) (push! 'b)
  (push! (length (peek))))
;; => (a b 2)
```

### `(std misc number)` — Numeric Utilities
**File:** `lib/std/misc/number.sls`

- `natural?`, `positive-integer?` — type predicates
- `clamp` — bound a value between min and max
- `divmod` — quotient + remainder as multiple values
- `number->padded-string` — zero-padded formatting with optional base (hex outputs lowercase)
- `number->human-readable` — `1536` → `"1.5K"`, `1048576` → `"1M"`
- `integer-length*` — bit length of an integer
- `fixnum->flonum` — exact→inexact conversion

### `(std net uri)` — URI Parsing and Encoding
**File:** `lib/std/net/uri.sls`

Full URI parsing with record type accessors:

```scheme
(let ([u (uri-parse "https://user:pass@example.com:8080/path?key=val#frag")])
  (uri-scheme u)    ;; "https"
  (uri-host u)      ;; "example.com"
  (uri-port u)      ;; 8080
  (uri-path u)      ;; "/path"
  (uri-query u)     ;; "key=val"
  (uri-fragment u))  ;; "frag"
```

Also provides:
- `uri-encode` / `uri-decode` — percent-encoding
- `uri->string` — reconstruct URI from components
- `query-string->alist` / `alist->query-string` — form data conversion

### `(std misc walist)` — Weak Association List
**File:** `lib/std/misc/walist.sls`

Association list backed by `make-weak-eq-hashtable`. Entries are automatically
removed when keys are garbage collected.

- `make-walist`, `walist-ref`, `walist-set!`, `walist-delete!`
- `walist-length`, `walist-keys`, `walist->alist`

### `(std values)` — Multiple Values Utilities
**File:** `lib/std/values.sls`

- `values->list` — convert multiple values to a list (macro)
- `values-ref` — extract nth value (macro)
- `receive` — SRFI-8 binding form: `(receive (a b c) (values 1 2 3) (+ a b c))`

### `(std assert)` — Assertion Library
**File:** `lib/std/assert.sls`

- `assert!` — with expression text in error message, optional custom message
- `assert-equal!` — compare with `equal?`, shows both values on mismatch
- `assert-pred` — `(assert-pred string? 42)` → error showing predicate and value
- `assert-exception` — assert a thunk raises, returns the caught exception

### `(std misc path)` — Path Utilities
**File:** `lib/std/misc/path.sls`

- `path-normalize` — resolve `.` and `..` components
- `path-split` — split into component list
- `path-relative?` — `#t` if path doesn't start with `/`
- `subpath` — safe path joining with `/` separators
- `path-default-extension` — add extension only if none exists (auto-adds `.` prefix)

### `(std interface)` — Interface Protocol
**File:** `lib/std/interface.sls`

Declare required methods for a type and check satisfaction at runtime:

```scheme
(definterface Printable (to-string describe))
(interface-register-method! 'my-type 'to-string)
(interface-register-method! 'my-type 'describe)
(Printable? 'my-type)   ;; #t
(Printable? 'other)     ;; #f
```

### `(std generic)` — Generic Functions
**File:** `lib/std/generic.sls`

Type-based dispatch using `defgeneric` / `defspecific`:

```scheme
(defgeneric describe (obj))
(defspecific (describe (obj 'string)) (string-append "String: " obj))
(defspecific (describe (obj 'number)) (string-append "Number: " (number->string obj)))
(describe "hello")  ;; "String: hello"
(describe 42)       ;; "Number: 42"
```

Dispatches on record-type-descriptors for records, symbols for built-in types
(`string`, `number`, `pair`, `vector`, `symbol`, `boolean`, `char`, etc.).

### `(std markup xml)` — XML Module Alias
**File:** `lib/std/markup/xml.sls`

Thin re-export of `(std text xml)`. Gerbil projects import `(std markup xml)` but
jerboa has the module at `(std text xml)`. This alias bridges the gap.

### `(std parser)` — Parser Combinators
**File:** `lib/std/parser.sls`

Recursive-descent parser combinator library. Parsers are procedures taking
`(string, position)` and returning `parse-result` or `parse-failure`.

**Base parsers:**
- `parse-char`, `parse-satisfy`, `parse-any-char`, `parse-literal`, `parse-eof`

**Combinators:**
- `parse-seq`, `parse-alt`, `parse-many`, `parse-many1`
- `parse-optional`, `parse-between`, `parse-sep-by`, `parse-map`

**Running:**
- `parse-string` — throws on failure
- `parse-string*` — returns `parse-failure` on failure (non-throwing)

```scheme
(let ([num (parse-map (parse-many1 (parse-char char-numeric?))
                      (lambda (chars) (string->number (list->string chars))))])
  (parse-result-value (parse-string num "42")))  ;; 42
```

### `(std srfi srfi-43)` — Vector Library
**File:** `lib/std/srfi/srfi-43.sls`

SRFI-43 vector operations not in Chez:
- `vector-unfold`, `vector-unfold-right`
- `vector-index`, `vector-index-right`, `vector-skip`, `vector-skip-right`
- `vector-any`, `vector-every`, `vector-count`
- `vector-fold`, `vector-fold-right`
- `vector-swap!`, `vector-reverse!`, `vector-map!`
- `vector-append`, `vector-concatenate`, `vector-empty?`
- `vector-copy!` (SRFI-43 arg order), `vector-reverse-copy!`

### `(std srfi srfi-128)` — Comparators
**File:** `lib/std/srfi/srfi-128.sls`

Comparator objects for sorted containers:
- `make-comparator`, `comparator?`
- `=?`, `<?`, `>?`, `<=?`, `>=?`
- Pre-built: `boolean-comparator`, `char-comparator`, `string-comparator`,
  `number-comparator`, `symbol-comparator`
- `make-default-comparator`, `default-hash`

### `(std srfi srfi-141)` — Integer Division
**File:** `lib/std/srfi/srfi-141.sls`

All five division types from SRFI-141:
- `floor/`, `floor-quotient`, `floor-remainder`
- `truncate/`, `truncate-quotient`, `truncate-remainder`
- `ceiling/`, `ceiling-quotient`, `ceiling-remainder`
- `euclidean/`, `euclidean-quotient`, `euclidean-remainder`
- `balanced/`, `balanced-quotient`, `balanced-remainder`

### `(jerboa translator)` — Gerbil-to-Jerboa Source Translator
**File:** `lib/jerboa/translator.sls`

Utilities for build scripts that translate Gerbil source to Chez-compatible R6RS.

**String-level transforms:**
- `translate-keywords` — `#:name` → `'name:`
- `translate-brackets` — `[x y z]` → `(list x y z)` (context-aware, preserves binding brackets)
- `translate-hash-bang` — `#!void` → `(void)`, `#!eof` → `(eof-object)`

**S-expression transforms:**
- `translate-defstruct` — to `define-record-type`
- `translate-let-hash` — passthrough (handled by runtime)
- `translate-using` — to `let` binding
- `translate-parameterize` — passthrough
- `translate-imports` — `:std/foo/bar` → `(std foo bar)`, `:gerbil/gambit` → `(jerboa core)`

**Pipeline:**
- `make-translator` — compose transform chains
- `default-transforms` — standard transform set
- `translate-file` — full file translation (read → transform → write)

---

## Enhanced Modules

### `(std misc process)` — Process Control Additions
- **`process-kill`** — send signal to a process (default SIGTERM), via FFI `kill()`
- **`tty?`** — check if a port/fd is a terminal, via FFI `isatty()`

### `(std os temporaries)` — Expanded Temp File API
- **`with-temporary-directory`** — scoped temp directory with recursive cleanup
- **`create-temporary-file`** — returns `(values path port)`
- **`temporary-file-directory`** — parameter (respects `$TMPDIR`)

### `(std net request)` — Header Format Helpers
- **`headers->alist`** — convert `"Name: Value"` strings to dotted pairs
- **`alist->headers`** — convert dotted pairs to `"Name: Value"` strings

---

## Bug Fixes

### `(jerboa core)`
- **`with-exception-catcher`** — fixed non-continuable exception bug. Was defined as
  `(define with-exception-catcher with-exception-handler)` which doesn't escape via
  `call/cc`, so the handler returned into a non-continuable context. Now properly wraps
  in `call-with-current-continuation`.

### `(std sugar)`
- **`<>` and `<...>` auxiliary syntax** — now exported so `cut`/`cute` work across
  module boundaries. R6RS `syntax-rules` literals match by binding, so the use site
  must import the same `<>` binding as the macro definition.

---

## Documentation

### `docs/import-conflicts.md`
Comprehensive guide to name collisions between `(chezscheme)`, `(jerboa core)`, and
`(std ...)` modules. Includes:
- Full conflict matrix with resolution for each symbol
- Common import templates (minimal, full stdlib, test files)
- Tips for avoiding conflicts

### `newer.md`
The 30-feature roadmap with effort/impact matrix and gerbil import frequency data.

---

## Tests

| Test File | Module Coverage | Tests |
|-----------|----------------|-------|
| `tests/test-gambit-compat.ss` | gambit-compat | 84 |
| `tests/test-newer-batch1.ss` | list-builder, number, uri, walist, values, assert | 84 |
| `tests/test-newer-batch2.ss` | path, interface, generic, temporaries, markup/xml | 36 |
| `tests/test-newer-batch3.ss` | parser, srfi-43, srfi-128, srfi-141, translator | 69 |
| `tests/test-newer-verify.ss` | iter, srfi-1, srfi-13, srfi-19, logging, crypto, config, channels, test | 57 |
| **Total** | | **330** |

All tests pass with `scheme --libdirs lib --script tests/test-*.ss`.

---

## Verified Pre-Existing Modules

These modules already existed in jerboa and were verified to provide the APIs
needed for Gerbil porting (57 tests in `test-newer-verify.ss`):

| Module | Key APIs Verified |
|--------|-------------------|
| `(std iter)` | `for/collect`, `for/fold`, `in-range`, `in-list`, `in-string` |
| `(std srfi srfi-1)` | `iota`, `fold`, `zip`, `take`, `drop`, `filter-map`, `any`, `every` |
| `(std srfi srfi-13)` | `string-contains`, `string-prefix?`, `string-trim-both`, `string-pad`, `string-join` |
| `(std srfi srfi-19)` | `current-date`, `date->string`, `time->seconds`, `date-year` |
| `(std logger)` | `start-logger!`, `current-logger`, `deflogger`, `infof`, `errorf` |
| `(std crypto digest)` | `sha256`, `md5`, `sha1` |
| `(std config)` | Module loads and provides config API |
| `(std misc channel)` | `make-channel`, `channel-put`, `channel-get`, `channel-close`, `channel-select` |
| `(std test)` | `test-suite`, `test-case`, `check`, `run-tests!` |
| `(std actor)` | Actor system with supervisor, protocol, scheduler sub-modules |
| `(jerboa build)` | Native binary toolchain with incremental compilation, WPO, cross-compilation |
| spawn/threading | `spawn`, `spawn/name`, `thread-join!`, `thread-sleep!`, `mutex-lock!` |
