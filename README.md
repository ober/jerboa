# Jerboa

Gerbil Scheme's syntax and APIs, running on stock Chez Scheme.

Jerboa implements Gerbil's user-facing language — `def`, `defstruct`, `match`, hash tables, `:std/*` libraries — as Chez Scheme macros and native libraries. No Gerbil expander, no Gambit compatibility layer, no patched Chez.

## Quick Start

```scheme
(import (jerboa prelude))

(def (main)
  (defstruct point (x y))
  (let ([p (make-point 3 4)])
    (displayln (point-x p))           ;; 3
    (displayln (sort [5 1 3] <))      ;; (1 3 5)
    (displayln (string-join ["a" "b"] ","))  ;; a,b
    (displayln (json-object->string [1 2 3]))))  ;; [1,2,3]

(main)
```

Run with:
```bash
scheme --libdirs lib --script your-file.ss
```

## Architecture

```
┌──────────────────────────────────────────────┐
│            User's Gerbil-like code           │
│  (def (main) (displayln (sort [3 1 2] <)))  │
└──────────────┬───────────────────────────────┘
               │
┌──────────────▼───────────────────────────────┐
│  Reader: [...] → (list ...), {...} → (~ ..)  │
│  :std/sort → (std sort) module paths         │
├──────────────────────────────────────────────┤
│  Core Macros: def, defstruct, match, try     │
│  All expand to standard Chez Scheme          │
├──────────────────────────────────────────────┤
│  Runtime: hash tables, method dispatch       │
├──────────────────────────────────────────────┤
│  Standard Library: sort, JSON, paths, etc.   │
├──────────────────────────────────────────────┤
│  FFI: c-lambda → foreign-procedure           │
├──────────────────────────────────────────────┤
│  Stock Chez Scheme — no fork, no patches     │
└──────────────────────────────────────────────┘
```

## What's Included

### Core Macros (`(jerboa core)`)
- `def` — functions with optional args, rest args
- `def*` — case-lambda shorthand
- `defstruct` — native Chez records with auto-generated accessors
- `defclass` — records with inheritance
- `defmethod` — method dispatch via `bind-method!`
- `match` — pattern matching (lists, predicates, `and`/`or`/`not`, cons, wildcards)
- `try`/`catch`/`finally` — exception handling
- `defrule`/`defrules` — syntax-rules shortcuts
- `while`/`until` — loop macros
- `hash-literal`/`let-hash` — hash table construction and destructuring

### Runtime (`(jerboa runtime)`)
- Full Gerbil hash table API: `hash-ref`, `hash-put!`, `hash-get`, `hash-keys`, etc.
- Method dispatch: `~`, `bind-method!`, `call-method`
- Keywords: `string->keyword`, `keyword?`, `keyword->string`
- Utilities: `displayln`, `iota`, `1+`, `1-`

### Standard Library
| Module | Provides |
|--------|----------|
| `(std sort)` | `sort`, `stable-sort` |
| `(std format)` | `printf`, `fprintf`, `eprintf` |
| `(std error)` | `Error`, `ContractViolation` |
| `(std sugar)` | `chain`, `chain-and`, `assert!` |
| `(std text json)` | `read-json`, `write-json`, `string->json-object`, `json-object->string` |
| `(std os path)` | `path-join`, `path-directory`, `path-extension`, etc. |
| `(std misc string)` | `string-split`, `string-join`, `string-trim`, `string-contains`, etc. |
| `(std misc list)` | `flatten`, `unique`, `take`, `drop`, `every`, `any`, `filter-map`, `zip` |
| `(std misc alist)` | `agetq`, `pgetq`, `alist->hash-table` |
| `(std misc ports)` | `read-file-string`, `with-output-to-string`, etc. |
| `(std misc channel)` | Thread-safe channels (Chez mutex/condvar) |
| `(std misc thread)` | Gambit-compatible thread API on Chez threads |
| `(std misc process)` | `run-process`, `run-process/batch` |
| `(std misc queue)` | Mutable FIFO queue |
| `(std misc bytes)` | Bytevector bitwise operations |
| `(std misc uuid)` | UUID v4 generation |
| `(std misc repr)` | `repr`, `prn` object printing |
| `(std misc completion)` | Async completion tokens |
| `(std pregexp)` | Portable regex (pregexp) |
| `(std test)` | Test framework (`test-suite`, `test-case`, `check`) |
| `(std logger)` | Logging with levels (error/warn/info/debug) |
| `(std cli getopt)` | CLI argument parsing (options, flags, commands) |
| `(std text base64)` | Base64 encode/decode |
| `(std text hex)` | Hex encode/decode |
| `(std text utf8)` | UTF-8 utilities |
| `(std text csv)` | CSV read/write |
| `(std text xml)` | SXML → XML serialization |
| `(std os env)` | `getenv`, `setenv`, `unsetenv` |
| `(std os temporaries)` | Temporary file creation |
| `(std os signal)` | POSIX signal constants + handlers |
| `(std os fdio)` | File descriptor I/O |
| `(std crypto digest)` | MD5/SHA hashing via openssl |
| `(std srfi srfi-13)` | SRFI-13 string operations |
| `(std srfi srfi-19)` | Date/time handling |

### FFI (`(jerboa ffi)`)
- `c-lambda` → `foreign-procedure` with automatic type translation
- `define-c-lambda` — named FFI bindings
- `begin-ffi`, `c-declare` — compatibility forms
- Full Gambit-to-Chez type mapping

### Reader (`(jerboa reader)`)
- `[1 2 3]` → `(list 1 2 3)`
- `{method obj}` → `(~ obj 'method)`
- `keyword:` → keyword objects
- `:std/sort` → `(std sort)` module paths
- Heredoc strings, datum comments, block comments

### Prelude (`(jerboa prelude)`)
One import for everything:
```scheme
(import (jerboa prelude))
```

## Testing

```bash
make test
```

Runs 213 tests across reader, core macros, runtime, standard library, FFI, and module path mapping.

## Requirements

- [Chez Scheme](https://cisco.github.io/ChezScheme/) 10.x (stock, unmodified)

## Project Structure

```
lib/
  jerboa/
    reader.sls      # Gerbil-compatible reader
    core.sls         # Core syntax macros
    runtime.sls      # Hash tables, method dispatch, keywords
    ffi.sls          # FFI translation macros
    prelude.sls      # All-in-one import
  std/
    sort.sls         # :std/sort
    format.sls       # :std/format
    error.sls        # :std/error
    sugar.sls        # :std/sugar
    text/json.sls    # :std/text/json
    os/path.sls      # :std/os/path
    misc/
      string.sls     # :std/misc/string
      list.sls        # :std/misc/list
      alist.sls       # :std/misc/alist
      ports.sls        # :std/misc/ports
      channel.sls      # :std/misc/channel
tests/
  test-reader.ss     # 65 reader tests
  test-core.ss       # 68 core macro tests
  test-stdlib.ss     # 65 stdlib tests
  test-ffi.ss        # 7 FFI tests
  test-modules.ss    # 8 module path tests
```

## What Gerbil Code Works

Most user-level Gerbil code works unchanged:

```scheme
(import :std/sugar :std/sort :std/format)

(def (run-command cmd env)
  (try
    (let* ([tokens (tokenize cmd)]
           [expanded (expand-aliases tokens env)])
      (match expanded
        ([prog . args] (exec-pipeline prog args env))
        (else (displayln "empty command"))))
    (catch (e) (displayln "error: " (error-message e)))))
```

## What Won't Work

1. **Gerbil expander API** (`:gerbil/expander`) — not applicable
2. **Gambit `##` primitives** — provide needed ones case-by-case
3. **`(export #t)`** — re-export-everything needs explicit exports
4. **Gerbil-specific `syntax-case` binding semantics** — uses Chez R6RS semantics
