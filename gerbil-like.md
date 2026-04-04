# Gerbil-Like Language on Chez Scheme

## The Core Realization

What makes code "Gerbil" to the person writing it? It's not the expander, not Gambit's `##` primitives, not the internal MOP representation. It's:

1. **Syntax**: `def`, `defstruct`, `defmethod`, `match`, `[]`, `try`/`catch`, `keyword:` args
2. **Standard library API**: `hash-ref`, `string-split`, `sort`, channels, JSON
3. **Module paths**: `(import :std/sort :mypackage/module)`
4. **FFI**: `(c-lambda (int) int "close")`

Everything else is implementation detail the user never sees. All of those user-facing features are implementable as Chez macros + a runtime library. No Gerbil expander needed.

## The Architecture: A Chez Macro Library

```
┌──────────────────────────────────────────────┐
│            User's Gerbil-like code           │
│  (def (main) (displayln (sort [3 1 2] <)))  │
└──────────────┬───────────────────────────────┘
               │ (import :gerbil/core)
┌──────────────▼───────────────────────────────┐
│  Layer 1: Syntax Macros  (~500 lines)        │
│  def, defstruct, defclass, defmethod,        │
│  match, try/catch, defrules, using, with     │
└──────────────┬───────────────────────────────┘
               │ expands to
┌──────────────▼───────────────────────────────┐
│  Layer 2: Runtime  (~1500 lines)             │
│  MOP, hash tables, keywords, errors          │
│  All built on Chez records + hashtables      │
└──────────────┬───────────────────────────────┘
               │ uses
┌──────────────▼───────────────────────────────┐
│  Layer 3: Standard Library  (~3000 lines)    │
│  :std/sort, :std/text/json, :std/misc/*      │
│  Native Chez implementations, Gerbil API     │
└──────────────┬───────────────────────────────┘
               │ uses
┌──────────────▼───────────────────────────────┐
│  Stock Chez Scheme — no fork, no patches     │
└──────────────────────────────────────────────┘
```

No Gerbil expander. No gambit-compat.sls. No 1790 lines of `##` primitive shims. Just macros expanding to clean Chez code.

## Layer by Layer

### Layer 0: The Reader

Handles:
- `[...]` → plain parentheses (interchangeable with `(...)`, same as Gerbil and Chez)
- `{method obj}` → method dispatch
- `keyword:` → keyword objects
- `#!void`, `#!eof` → special values

```scheme
[x 1]         → (x 1)          ; brackets = parens, use freely in let/match/cond
{method obj}  → (~ obj method) ; ~ is the dispatch operator
foo:          → (quote #:foo)  ; or a keyword record
```

Brackets are **not** list constructors — they are ordinary delimiters, matching Gerbil and stock Chez behavior.

### Layer 1: Syntax Macros

Every user-facing form becomes a `define-syntax` in Chez. Here's the complete list with how they expand:

**`def`** — the big one. Handles 5 patterns:

```scheme
;; Simple binding
(def x 42)
→ (define x 42)

;; Function
(def (f x y) body ...)
→ (define (f x y) body ...)

;; Optional args
(def (f x (y 0) (z 1)) body ...)
→ (define f
    (case-lambda
      [(x) (f x 0 1)]
      [(x y) (f x y 1)]
      [(x y z) body ...]))

;; Keyword args
(def (f x key: (k 0)) body ...)
→ (define f
    (make-keyword-procedure
      (lambda (x k) body ...)
      '((k: . 0))))

;; Rest args
(def (f x . rest) body ...)
→ (define (f x . rest) body ...)
```

**`defstruct`** — maps to Chez records, which are faster than gerbil-struct simulation:

```scheme
(defstruct point (x y))
→ (begin
    (define-record-type point
      (fields (mutable x) (mutable y)))
    (define point::t (record-type-descriptor point))
    (define make-point (record-constructor (record-constructor-descriptor point)))
    (define point? (record-predicate point::t))
    (define point-x (record-accessor point::t 0))
    (define point-y (record-accessor point::t 1))
    (define point-x-set! (record-mutator point::t 0))
    (define point-y-set! (record-mutator point::t 1)))
```

This is **native Chez speed** — no MOP indirection, no `##structure-ref` shims. Chez records are as fast as C structs.

**`defclass`** — for classes with inheritance and methods, uses Chez's record inheritance:

```scheme
(defclass (colored-point point) (color))
→ (begin
    (define-record-type colored-point
      (parent point)
      (fields (mutable color)))
    ;; + method table registration
    (register-class! colored-point::t '(point::t) '(color)))
```

**`defmethod`** — method dispatch via hashtable lookup:

```scheme
(defmethod {draw self}
  (displayln "drawing at " (point-x self)))
→ (bind-method! point::t 'draw
    (lambda (self) (displayln "drawing at " (point-x self))))
```

**`match`** — ~150 lines as a `syntax-case` macro:

```scheme
(match expr
  ([a b c] body1)
  ((? string? s) body2)
  (else body3))
→ (let ([tmp expr])
    (cond
      [(and (pair? tmp) (pair? (cdr tmp)) (pair? (cddr tmp)) (null? (cdddr tmp)))
       (let ([a (car tmp)] [b (cadr tmp)] [c (caddr tmp)]) body1)]
      [(string? tmp) (let ([s tmp]) body2)]
      [else body3]))
```

**`try`/`catch`** — maps to Chez's `guard`:

```scheme
(try
  (risky-operation)
  (catch (e) (handle e))
  (finally (cleanup)))
→ (dynamic-wind
    (lambda () (void))
    (lambda ()
      (guard (e [#t (handle e)])
        (risky-operation)))
    (lambda () (cleanup)))
```

**Complete macro list** (~500 lines total):

| Macro | Expands to | Lines |
|-------|-----------|-------|
| `def` | `define` / `case-lambda` | ~60 |
| `defstruct` | `define-record-type` | ~50 |
| `defclass` | `define-record-type` + parent + MOP | ~80 |
| `defmethod` | `bind-method!` | ~15 |
| `defrules` | `define-syntax` + `syntax-rules` | ~30 |
| `match` | `cond` + destructuring | ~150 |
| `try`/`catch`/`finally` | `guard` + `dynamic-wind` | ~40 |
| `when`/`unless` | `if`/`begin` | ~5 |
| `using` | `let` + accessors | ~20 |
| `with` | resource management | ~20 |
| `while`/`until` | named `let` loop | ~10 |
| `hash` / `hash-eq` | hashtable constructor | ~10 |
| `let-hash` | hash destructuring | ~15 |

### Layer 2: Runtime Library

This is the stuff macros expand into — not user-facing, but needed.

**MOP** (~200 lines) — simplified because Chez records do the heavy lifting:

```scheme
;; Method dispatch table: type-descriptor → (symbol → procedure) hashtable
(define *method-tables* (make-eq-hashtable))

(define (bind-method! type name proc)
  (let ([table (or (hashtable-ref *method-tables* type #f)
                   (let ([t (make-eq-hashtable)])
                     (hashtable-set! *method-tables* type t)
                     t))])
    (hashtable-set! table name proc)))

(define (call-method obj name . args)
  (let ([type (record-rtd obj)])
    (let loop ([t type])
      (cond
        [(and t (hashtable-ref (hashtable-ref *method-tables* t
                  (make-eq-hashtable)) name #f))
         => (lambda (method) (apply method obj args))]
        [(record-type-parent t) => loop]
        [else (error 'call-method "no method" name type)]))))
```

That's the entire method dispatch. ~30 lines vs hundreds in the current MOP because Chez records already handle inheritance, field access, and type checking natively.

**Hash tables** (~100 lines) — Gerbil API on Chez hashtables:

```scheme
(define (hash-ref ht key (default absent))
  (let ([v (hashtable-ref ht key absent)])
    (if (eq? v absent) (error "key not found" key) v)))

(define hash-put! hashtable-set!)
(define hash-remove! hashtable-delete!)

(define (hash-for-each proc ht)
  (vector-for-each
    (lambda (k) (proc k (hashtable-ref ht k #f)))
    (hashtable-keys ht)))
```

**Keywords** (~30 lines) — tagged symbols:

```scheme
(define-record-type keyword (fields name))
(define (keyword->string kw) (keyword-name kw))
(define (string->keyword s) (make-keyword s))
```

**Error types** (~50 lines) — Gerbil errors as Chez conditions:

```scheme
(define-condition-type &gerbil-error &error
  make-gerbil-error gerbil-error?
  (irritants gerbil-error-irritants)
  (trace gerbil-error-trace))
```

Using Chez conditions instead of simulated Gambit error structs means `(guard ...)` works natively, the debugger understands them, and `display-condition` prints them properly.

### Layer 3: Standard Library

**Native implementations with Gerbil's API.** Not loaded through the expander, not compiled from Gerbil source — written directly in Chez with Gerbil-compatible exports:

```scheme
;; :std/sort — 10 lines
(library (std sort)
  (export sort sort! stable-sort stable-sort!)
  (import (chezscheme))
  (define (sort lst less?) (list-sort less? lst))
  (define (sort! lst less?) (list-sort less? lst))
  (define stable-sort sort)
  (define stable-sort! sort!))
```

```scheme
;; :std/text/json — ~200 lines
(library (std text json)
  (export read-json write-json json-object->string string->json-object)
  (import (chezscheme) (gerbil core))
  ;; Native implementation using Chez ports
  ...)
```

```scheme
;; :std/misc/channel — ~100 lines (Chez-native, not shimmed Gambit)
(library (std misc channel)
  (export make-channel channel-put channel-get channel-try-get channel-close)
  (import (chezscheme))

  (define-record-type channel
    (fields (mutable queue) (immutable mutex) (immutable condvar) (mutable closed?)))

  (define (make-channel . args)
    (make-channel '() (make-mutex) (make-condition) #f))

  (define (channel-put ch val)
    (with-mutex (channel-mutex ch)
      (channel-queue-set! ch (append (channel-queue ch) (list val)))
      (condition-signal (channel-condvar ch))))

  (define (channel-get ch)
    (with-mutex (channel-mutex ch)
      (let loop ()
        (if (null? (channel-queue ch))
          (begin (condition-wait (channel-condvar ch) (channel-mutex ch)) (loop))
          (let ([val (car (channel-queue ch))])
            (channel-queue-set! ch (cdr (channel-queue ch)))
            val))))))
```

That channel implementation is ~20 lines and uses Chez's native mutex + condition variables. Real SMP. No Gambit shim.

### Layer 4: FFI

Translate Gerbil's FFI syntax to Chez's at macro-expansion time:

```scheme
(define-syntax begin-ffi
  (syntax-rules ()
    [(_ (export-name ...) body ...)
     (begin (ffi-compile-c-blocks body ...) ...)]))

(define-syntax c-lambda
  (syntax-rules ()
    [(_ (arg-type ...) ret-type c-name)
     (foreign-procedure c-name
       (ffi-translate-type arg-type) ...
       (ffi-translate-type ret-type))]))
```

The `c-declare` blocks need a compile-time step: extract C code, compile to `.so`, emit `load-shared-object`. This can be a build-system step rather than a macro — the `gherkin build` command handles it.

FFI type mapping:

| Gambit type | Chez type |
|-------------|-----------|
| `char-string` | `string` |
| `int` | `int` |
| `unsigned-int` | `unsigned` |
| `int64` | `integer-64` |
| `double` | `double` |
| `bool` | `boolean` |
| `scheme-object` | `scheme-object` |
| `void` | `void` |
| `(pointer void)` | `void*` |
| `nonnull-char-string` | `string` |

### Layer 5: Module System

Map Gerbil's `:package/module` paths to R6RS library paths:

```scheme
(import :std/sort)          → (import (std sort))
(import :std/text/json)     → (import (std text json))
(import :myapp/core)        → (import (myapp core))
(export func1 func2)        → (export func1 func2)
(export #t)                 → ;; re-export everything (needs macro support)
```

This is a reader-level transformation. When the reader sees `(import :std/sort)`, it emits `(import (std sort))`. Chez's library system handles compilation, caching, and dependency tracking natively. You get Chez's incremental compilation for free.

## What This Means for Real Projects

Here's what gerbil-shell code looks like today:

```scheme
(import :std/sugar :std/sort :std/format :std/foreign
        :gsh/lib :gsh/environment)

(export start-shell run-command)

(def (run-command cmd env)
  (try
    (let* ([tokens (tokenize cmd)]
           [expanded (expand-aliases tokens env)])
      (match expanded
        (["cd" dir] (chdir dir))
        ([prog . args] (exec-pipeline prog args env))
        (else (displayln "empty command"))))
    (catch (e) (displayln "error: " (error-message e)))))
```

**This code would work unchanged.** Every form in it (`def`, `try`, `match`, `import`, `export`) is handled by the macro library. The `:std/*` imports resolve to native Chez libraries. The FFI imports compile to `foreign-procedure`.

## What Changes vs Current Gherkin

| Aspect | Current Gherkin | New approach |
|--------|----------------|--------------|
| Gerbil's expander | Loaded and run on Chez | Not needed |
| gambit-compat.sls | 1790 lines | Deleted |
| MOP | 800+ lines simulating Gambit structs | ~200 lines on Chez records |
| `defstruct` | → gerbil-struct → fields vector | → Chez `define-record-type` (native speed) |
| Method dispatch `{}` | Runtime `call-method` injection | Reader expands to `(~ obj method)` |
| Module loading | Custom loader + `/tmp` cache | Chez's native library system |
| Compilation | Pattern-match compiler (1100 lines) | Macros (~500 lines) |
| std library | Load Gerbil's source through expander | Native Chez reimplementation |
| FFI | Not implemented | `c-lambda` → `foreign-procedure` macro |
| Bootstrap | Load expander + compiler + core + runtime | `(import (gerbil core))` |

The total codebase shrinks from ~50 files / 20K+ lines to roughly:

| Component | Lines |
|-----------|-------|
| Reader | ~600 (keep existing, simplify) |
| Core macros | ~500 |
| Runtime (MOP, hash, keywords, errors) | ~800 |
| Standard library modules | ~3000 |
| FFI translation | ~200 |
| Module path mapping | ~100 |
| **Total** | **~5200** |

vs. the current gherkin at ~20K+ lines across 50+ files.

## What Gerbil Code Won't Work

Being honest about what breaks:

1. **Code using `syntax-case` with Gerbil's binding semantics** — rare in user code, common in Gerbil's own macro system. The macros would use Chez's `syntax-case` which is R6RS-standard.

2. **Code using Gerbil's expander API directly** (`:gerbil/expander`) — gemacs uses this for its REPL. Solution: the REPL evaluates via Chez's `eval` with the macro library loaded.

3. **Code using `##` Gambit primitives** — gsh uses `##cpu-count`, `##set-parallelism-level!`. Solution: provide the 10-15 primitives that real projects actually use, not all 90+.

4. **`(export #t)`** — Gerbil's "re-export everything" convention. Needs a custom macro that tracks imports and re-exports them. Doable but ~50 lines of `syntax-case`.

5. **Phase separation** (`for-syntax`, `begin-syntax`) — needed for advanced macros. Chez supports this natively via R6RS phases, but the syntax differs. Needs a translation macro.

For gerbil-shell and gerbil-emacs specifically, items 1-2 affect maybe 5 lines of code total. Items 3-5 are straightforward to handle.

## Summary

Stop porting Gerbil. **Reimplement its surface** — the syntax and APIs users actually write — as a Chez library. You keep 95%+ source compatibility with real Gerbil projects while getting:

- Native Chez record speed (no MOP indirection for structs)
- Native Chez threads (real SMP)
- Native Chez compilation (incremental, cached, fast)
- Native Chez FFI (zero overhead)
- Native Chez debugging (conditions, inspector)
- Stock Chez (no fork)
- ~5K lines instead of ~20K

The user writes Gerbil. The machine runs Chez. Nothing in between pretends to be Gambit.
