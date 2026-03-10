# Things I Learned: Converting gerbil-lsp to jerboa-lsp

Notes from porting a 53-module Gerbil Scheme LSP server to run on Chez Scheme
via the Jerboa translation framework. Covers bugs found, compatibility issues,
and design decisions.

## Jerboa Framework Bugs Found and Fixed

### 1. Dotted Pair Reversal in the Reader

**File:** `src/reader/reader.sls` (line 249)
**Commit:** `87acce6`

The reader reversed elements in improper lists. `(foo a b . rest)` was read as
`(b a foo . rest)`. This caused function parameter lists to be scrambled whenever
a rest argument was present — the last required parameter became the function
name.

**Root cause:** Double-reversal. As the reader consumed tokens, it accumulated
them in `acc` via prepend, giving `acc = (b a foo)`. The code then called
`(reverse acc)` producing `(foo a b)`, but the subsequent `build` loop folded
left-to-right, reversing again to `(b a foo . rest)`.

**Fix:** Removed `(reverse acc)`. The accumulator is already in the right order
for the fold:

```scheme
;; acc = (b a foo) — fold produces (foo a b . rest)
(let build ((items acc) (result tail))
  (if (null? items) result
      (build (cdr items) (cons (car items) result))))
```

### 2. Dot-Notation Applied to Uppercase Identifiers

**File:** `src/compiler/compile.sls` (function `dot-notation?`)
**Commit:** `61337f7`

`CompletionItemKind.Snippet` compiled to `(slot-ref CompletionItemKind 'Snippet)`
instead of staying as a plain identifier. This affected all uppercase dotted
constants throughout the LSP types module (`DiagnosticSeverity.Error`,
`SymbolKind.File`, etc.).

**Root cause:** `dot-notation?` treated any symbol containing a dot as a slot
access expression. It had no way to distinguish `object.field` (instance access)
from `EnumType.Value` (a constant identifier).

**Fix:** Added `char-lower-case?` check on the first character. By Gerbil
convention, instance variables start lowercase; class/enum constants start
uppercase:

```scheme
(define (dot-notation? sym)
  (and (symbol? sym)
       (let ((s (symbol->string sym)))
         (and (> (string-length s) 2)
              (char-lower-case? (string-ref s 0))  ;; only lowercase = slot access
              ...))))
```

### 3. Relative `./foo` Imports Without Source Directory Context

**File:** `src/compiler/compile.sls`
**Commit:** `953fa8d`

`./parser` imported from `lsp/analysis/symbols.ss` resolved to `(lsp parser)`
instead of `(lsp analysis-parser)`. Broke all cross-references within
subdirectories.

**Root cause:** The compiler stripped `./` to get `"parser"`, combined with
`*default-package* = lsp` to produce `(lsp parser)`. It had no knowledge of the
source file's directory (`lsp/analysis/`).

**Fix:** Threaded a `source-dir` parameter through `gerbil-compile-to-library` ->
`compile-library-imports` -> `resolve-import`. Added `resolve-with-context` that
strips the package prefix from the source directory and prepends the subdirectory:

```
source-dir = "lsp/analysis", default-pkg = lsp
-> subdir = "analysis"
-> "./parser" -> "analysis-parser"
-> library name: (lsp analysis-parser)
```

A secondary bug: `rel-path` (a symbol) was passed to `normalize-relative-path`
which expects a string. Fixed with `(if (string? rel-path) rel-path
(symbol->string rel-path))`.

### 4. Keyword Objects in `case` Clause Datums

**File:** `src/compiler/compile.sls` (function `compile-case-clause`)
**Commit:** `be65745`

Gerbil keywords like `package:` used as `case` datums compiled to
`#[keyword-object "package"]` — an internal notation Chez cannot read.

**Root cause:** `gerbil-compile-expression` handled keywords in expression
positions but `case` datums are literal data passed through unchanged.

**Fix:** Map over datums and convert keyword objects to colon-suffixed symbols:

```scheme
(define (compile-case-clause clause)
  (if (eq? (car clause) 'else)
    `(else ,@(map gerbil-compile-expression (cdr clause)))
    (let ((datums (map (lambda (d)
                         (cond
                           ((|##keyword?| d)
                            (string->symbol
                              (string-append (|##keyword->string| d) ":")))
                           (else d)))
                       (car clause))))
      `(,datums ,@(map gerbil-compile-expression (cdr clause))))))
```

## Gerbil <-> Chez Compatibility Issues

### `#:keyword` Syntax

Gerbil's `#:parse-error` keyword literal syntax is not recognized by the Jerboa
reader. Changed to plain symbol `'parse-error`. Note: `'parse-error:` (with
colon suffix) also doesn't work — Chez sees it as a keyword-object literal.

### R6RS Definition Ordering

Gerbil allows `define` anywhere in a body. R6RS requires all definitions before
expressions. Had to reorder code in `completion-data.ss` where a `define`
appeared after `lsp-debug` and `when` calls.

### Binary vs Textual Ports

Chez's `current-input-port` is textual. The LSP transport reads raw bytes via
`read-u8` / `read-subu8vector`. Gambit's `read-u8` works on any port; Chez's
`get-u8` requires a binary port.

Fix: port-type dispatch in `read-u8`:

```scheme
(define (read-u8 port)
  (if (binary-port? port)
    (get-u8 port)
    (let ((c (read-char port)))
      (if (eof-object? c)
        (eof-object)
        (char->integer c)))))
```

### Chez `hashtable` vs Jerboa Runtime Hash Tables

The Jerboa runtime wraps hash tables in its own `gerbil-struct` record type.
Chez has a native `hashtable` type. If a compat module creates hash tables with
Chez primitives (`make-hashtable`), they crash when passed to Jerboa's
`hash-ref` / `hash-put!`.

**All compat modules that create hash tables must use `(runtime hash)`:**
- `(make-hashtable symbol-hash eq?)` -> `(make-hash-table)`
- `(hashtable-set! ht k v)` -> `(hash-put! ht k v)`
- `(hashtable? val)` -> `(hash-table? val)`
- `(hashtable-entries ht)` -> `(hash->list ht)` (returns alist)

### R6RS Import Conflicts

Multiple "multiple definitions" errors when both `(chezscheme)` and a compat
module export the same name. Fixed with `except` clauses:

```scheme
(import
  (except (chezscheme) sort sort! fprintf printf iota path-extension)
  (compat misc)
  (compat sort)
  (compat format)
  ...)
```

Important: don't accidentally exclude `format` from `(chezscheme)` — the compat
format module only provides `fprintf`/`printf`, not `format`.

### `begin-ffi` Is Gambit-Only

The original `main.ss` had a ~100-line `begin-ffi` block for SIGVTALRM spin
detection (a Gambit threading workaround). Removed entirely — Chez doesn't have
this issue.

## Compat Modules: What and Why

| Module | Replaces | Key Functions |
|--------|----------|---------------|
| `json.sls` | `:std/text/json` | `read-json`, `write-json`, `string->json-object`, `json-object->string` |
| `getopt.sls` | `:std/cli/getopt` | `call-with-getopt`, `flag`, `option` |
| `process.sls` | `:std/os/process` | `run-process` with `coprocess:` keyword |
| `format.sls` | `:std/format` | `fprintf`, `printf` (not `format` — Chez has that) |
| `sort.sls` | `:std/sort` | `sort`, `sort!` with Gerbil's comparator convention |
| `misc.sls` | Various `:std/*` | `iota`, `read-line`, `path-extension`, `path-strip-extension`, etc. |
| `sugar.sls` | `:std/sugar` | `try`/`catch`/`finally`, `hash`, `defrule` |
| `gambit.sls` | Gambit builtins | `make-mutex`, `mutex-lock!`, `fork-thread`, `with-output-to-string` |
| `lsp/compat.sls` | `lsp/compat/compat.ss` | Bridges all the above + Gambit internal stubs |

### Gambit Internal Stubs in `lsp/compat.sls`

These Gambit-specific functions had no Chez equivalent and needed stubs:

- `##readenv-current-filepos`, `##filepos-line`, `##filepos-col` — parser error
  line/column extraction (always returns 0; code path never reached since
  `datum-parsing-exception?` returns `#f`)
- `thread-terminate!` — no-op (Chez threads must finish cooperatively)
- `input-port-line`, `input-port-column` — return 1 (Chez doesn't track these)
- `keyword?` — checks if symbol ends with `:` (Jerboa's keyword convention)
- `type-of` — runtime type dispatch returning a symbol

### FFI Stubs in `gambit.sls`

The gambit.sls from jerboa-shell had `foreign-procedure` calls for process and
terminal management (`ffi_do_waitpid`, `ffi_set_raw_mode`, etc.). These required
jerboa-shell's C shared library. Replaced with no-op stubs since the LSP server
doesn't need them.

## Build Infrastructure Decisions

### Module Naming Convention

Nested paths are flattened with hyphens:
- `lsp/analysis/parser.ss` -> library `(lsp analysis-parser)`, file `src/lsp/analysis-parser.sls`
- `lsp/util/log.ss` -> library `(lsp util-log)`, file `src/lsp/util-log.sls`

The top-level directory becomes the R6RS library package. The `*default-package*`
import map key tells the compiler to use `lsp` for all unmapped relative imports.

### 4-Stage Build Pipeline

1. **Jerboa translate** (`.ss` -> `.sls`): `build-jerboa.ss` drives the Jerboa
   compiler, fixes import conflicts, and handles mutable exports
2. **Chez compile** (`.sls` -> `.so`): `build-all.ss` with
   `compile-imported-libraries`
3. **Boot file creation**: `make-boot-file` bundles all `.so` files in dependency
   order
4. **Binary linking**: C main (`lsp-main.c`) embeds boot files as C byte arrays
   via `memfd_create` + `Sregister_boot_file_bytes`

### Compilation Order Matters

Modules must be compiled in dependency order. The build script uses 5 tiers:

1. Compat layer
2. Utilities (no inter-dependencies)
3. Core protocol (types, jsonrpc, transport, state, server)
4. Analysis modules
5. Handlers + main

### Link Flags

The standalone binary needs `-lncurses` because Chez Scheme's `libkernel.a`
contains the expeditor (line editor) which depends on ncurses terminal functions.
Without it, linking fails with undefined references to `cur_term`, `tputs`,
`setupterm`.

### Unused Modules in Boot File

`compile-program` only compiles modules reachable via the import chain. Several
compat modules (`pregexp`, `signal`, `signal-handler`, `fdio`) were listed in the
boot file but never imported. Their `.so` files didn't exist, causing
`make-boot-file` to fail. Removed them from the boot file list.

## Result

- 5.6 MB standalone ELF binary
- Only system library dependencies: libc, libm, libtinfo
- All 53 original `.ss` files preserved (3 with minor modifications)
- 13/15 e2e protocol tests pass
- 4 Jerboa framework bugs fixed upstream
