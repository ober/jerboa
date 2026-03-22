# Porting Report: Gerbil Projects to Jerboa

This document captures lessons learned from porting Gerbil projects to Jerboa.

## Completed Ports

### jerboa-es-proxy

**Original:** gerbil-es-proxy (Elasticsearch proxy server)
**Compat shim:** 640 lines
**Status:** Working

**What worked unchanged:**
- HTTP request handling
- JSON parsing/serialization
- Hash table operations
- String manipulation
- Path operations
- Basic error handling

**What required shims:**
- Gambit u8vector operations → bytevector wrappers (now in `(std gambit-compat)`)
- `spawn` / threading → custom thread wrapper (now in `(std misc thread)`)
- HTTP client header format (Gerbil dotted pairs vs Jerboa triples)
- `date->string` (partial reimplementation, now in SRFI-19)
- `(insecure-client-ssl-context)` pattern for dev/testing

**Lessons:**
- Import conflicts were the biggest time sink — dozens of `(except ...)` clauses
- Most runtime behavior was identical once imports were sorted
- The HTTP header format mismatch caused subtle bugs

### jerboa-shell

**Original:** gerbil-shell (Unix shell implementation)
**Compat shim:** 849 lines
**Status:** Working

**What worked unchanged:**
- Core shell parsing
- Command dispatch
- String processing
- Pattern matching

**What required shims:**
- Process management FFI: `waitpid` with WNOHANG, `process-pid`, `process-kill`
  (now in `(std misc process)`)
- Terminal control: `tty?`, `tty-mode-set!` (raw/cooked mode)
- File info: `stat`, `file-mode`, `file-uid`, etc. (8 separate FFI calls)
- Signal handling differences
- `user-info`: getpwuid/getpwnam for `~` expansion
- `spawn`/`spawn/name` threading primitives

**Lessons:**
- System-level code requires the most shimming
- Terminal control is fundamentally FFI — no pure Scheme alternative
- The `(std gambit-compat)` module would have eliminated ~400 lines

## Common Porting Patterns

### 1. Import Translation (Mechanical)

```scheme
;; Before (Gerbil)
(import :std/text/json :std/sort :std/sugar :gerbil/gambit)

;; After (Jerboa)
(import (except (chezscheme) sort sort! format printf fprintf
                make-hash-table hash-table? iota 1+ 1-)
        (jerboa prelude)
        (std gambit-compat))
```

Or with the clean prelude:

```scheme
(import (chezscheme) (jerboa prelude clean) (std gambit-compat))
```

### 2. Threading (Direct Translation)

```scheme
;; Gerbil
(spawn (lambda () (handle-client conn)))
(spawn/name "worker" worker-loop)
(thread-sleep! 0.1)

;; Jerboa — identical after importing (std misc thread)
(spawn (lambda () (handle-client conn)))
(spawn/name "worker" worker-loop)
(thread-sleep! 0.1)
```

### 3. Process Control (Was FFI, Now Stdlib)

```scheme
;; Gerbil
(process-pid proc)
(process-status proc WNOHANG)

;; Jerboa
(import (std misc process))
(process-port-pid proc)
(process-port-status proc)
```

### 4. `match` on Structs (Requires match2)

```scheme
;; Gerbil — works in core match
(match val ((point x y) (+ x y)))

;; Jerboa — need match2
(import (std match2))
(define-match-type point point? point-x point-y)
(match val [(point x y) (+ x y)])
```

## What Cannot Be Ported

1. **Gerbil expander plugins** — Code using `:gerbil/expander` for custom
   syntax transformers. Use Chez `syntax-case` instead.

2. **Gambit C backend features** — `declare` blocks, `c-declare`/`c-initialize`
   with Gambit semantics. Use Chez `foreign-procedure` instead.

3. **`(export #t)`** — Must enumerate exports explicitly in R6RS.

4. **Gerbil's module system** — Dynamic module loading, package manager
   integration. Use Chez library system.

## Performance Observations

- **Startup time:** Comparable (both compile to native code)
- **Hash table operations:** Jerboa slightly faster (Chez's hashtables are highly optimized)
- **String operations:** Comparable
- **FFI overhead:** Lower in Jerboa (Chez's `foreign-procedure` is well-optimized)
- **Thread creation:** Comparable (both use OS threads)

## Recommendations for New Ports

1. Start with `(import (chezscheme) (jerboa prelude clean) (std gambit-compat))`
2. Run the source translator first: `(translate-file "input.ss" "output.ss" (default-transforms))`
3. Fix remaining compilation errors manually (usually import conflicts)
4. Test incrementally — don't try to port everything at once
5. Check `docs/import-conflicts.md` when you hit name collisions
