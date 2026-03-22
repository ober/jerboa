# Migrating from Gerbil to Jerboa

This guide covers porting Gerbil Scheme code to Jerboa (stock Chez Scheme).

## What Works Unchanged

Most Gerbil user-level code runs on Jerboa with only import changes:

- `def`, `def*` with optional, keyword, and rest arguments
- `defstruct`, `defclass`, `defmethod`
- `match` (lists, cons, predicates, guards, `and`/`or`/`not`)
- `try`/`catch`/`finally`
- `while`, `until`, `when`, `unless`
- `defrule`, `defrules`
- Hash tables: `hash-ref`, `hash-put!`, `hash-get`, `hash-keys`, etc.
- Method dispatch: `{method obj}` or `(~ obj 'method)`
- `chain`, `chain-and`, `assert!`
- `displayln`, `iota`, `1+`, `1-`
- JSON: `read-json`, `write-json`
- Path ops: `path-expand`, `path-join`, `path-directory`
- String ops: `string-split`, `string-join`, `string-trim`
- List ops: `take`, `drop`, `any`, `every`, `filter-map`

## Import Translation

### Module Paths

Gerbil's `:std/foo` becomes Jerboa's `(std foo)`:

```scheme
;; Gerbil
(import :std/text/json :std/sort :std/misc/string)

;; Jerboa
(import (std text json) (std sort) (std misc string))
```

Or use the prelude for the most common modules:

```scheme
;; Gerbil
(import :std/sugar :std/sort :std/format :std/text/json
        :std/misc/string :std/misc/list :std/misc/alist :std/misc/ports)

;; Jerboa — all of the above in one import
(import (jerboa prelude))
```

### Gambit Compatibility

For code that uses Gambit primitives (`##` namespace, u8vector ops, etc.):

```scheme
;; Gerbil
(import :gerbil/gambit)

;; Jerboa
(import (std gambit-compat))
```

This provides 150+ compatibility symbols including `u8vector` ops, `void?`,
`call-with-input-string`, `cpu-count`, and more.

### Import Conflicts

The #1 friction point. Chez Scheme and Jerboa define some of the same names
with different semantics. See [import-conflicts.md](import-conflicts.md) for
the full matrix.

**Quick solution — use `(jerboa prelude clean)`:**

```scheme
;; No conflicts — prelude/clean excludes names that collide with (chezscheme)
(import (chezscheme) (jerboa prelude clean))
```

**Manual solution — use `except`:**

```scheme
(import (except (chezscheme)
          make-hash-table hash-table?
          sort sort! format printf fprintf
          iota 1+ 1-
          path-extension path-absolute?
          with-input-from-string with-output-to-string)
        (jerboa prelude))
```

## Mechanical Transformations

### Keyword Arguments

Gerbil uses `#:keyword` syntax; Jerboa uses quoted symbols:

```scheme
;; Gerbil
(http-get url headers: my-headers timeout: 30)

;; Jerboa
(http-get url headers: my-headers timeout: 30)
;; Jerboa's `def` macro supports keyword: syntax natively
```

### `spawn` and Threading

```scheme
;; Gerbil
(import :std/sugar)
(spawn (lambda () (displayln "hello")))
(spawn/name "worker" (lambda () (work)))

;; Jerboa
(import (std misc thread))
(spawn (lambda () (displayln "hello")))
(spawn/name "worker" (lambda () (work)))
```

### Channels

```scheme
;; Gerbil
(import :std/misc/channel)
(def ch (make-channel))
(channel-put ch 42)
(channel-get ch)

;; Jerboa
(import (std misc channel))
(def ch (make-channel))
(channel-put ch 42)
(channel-get ch)
```

### Iterators

```scheme
;; Gerbil
(import :std/iter)
(for/collect ((x (in-range 10))) (* x x))

;; Jerboa
(import (std iter))
(for/collect ((x (in-range 10))) (* x x))
```

### Actors

```scheme
;; Gerbil
(import :std/actor)
(defproto myproto (greeting name))

;; Jerboa
(import (std actor))
(defprotocol myproto (greeting name))
```

## What Needs Redesign

### Gerbil Expander API

Code that uses `:gerbil/expander` (custom syntax transformers, module
introspection) has no Jerboa equivalent. This is internal Gerbil machinery,
not user-facing API. Alternatives:

- Use Chez's `syntax-case` directly for macro work
- Use `(std doc)` for module introspection

### `##` Gambit Primitives

Most `##` primitives are covered by `(std gambit-compat)`. For the rest,
check `(chezscheme)` for native equivalents:

| Gambit | Chez Scheme |
|--------|-------------|
| `##sys-clock` | `(cpu-time)` |
| `##gc` | `(collect)` |
| `##void` | `(void)` |
| `##fixnum?` | `(fixnum? x)` |
| `##car` | `(car x)` (Chez already inlines) |

### `(export #t)` — Re-export All

Gerbil's `(export #t)` re-exports everything. Chez R6RS requires explicit
exports. You must list all exported symbols in the library form.

### `parameterize` Thread Locality

Gerbil's `parameterize` is not thread-local. Chez's `parameterize` IS
thread-local (each thread gets its own parameter cell). This usually doesn't
matter, but if your code relies on one thread's `parameterize` being visible
to another, you need explicit communication (channels, shared state).

## The Source Translator

For bulk porting, Jerboa includes a source translator:

```scheme
(import (jerboa translator))

;; Translate a Gerbil source file
(translate-file "input.ss" "output.ss" (default-transforms))
```

This handles:
- `#:keyword` syntax normalization
- `[x y]` bracket form translation
- `##gambit-primitive` replacement
- `defstruct` → R6RS record expansion
- `let-hash` / `using` expansion
- Import path translation
- `try`/`catch` normalization

## Common Pitfalls

1. **Forgetting import exclusions** — If you get "duplicate import" errors,
   check [import-conflicts.md](import-conflicts.md).

2. **`match` on structs** — Core `match` doesn't destructure structs.
   Import `(std match2)` for struct patterns with `define-match-type`.

3. **`format` differences** — Jerboa's `format` returns a string (like
   Gerbil). Chez's `format` writes to a port. If you import both, exclude
   one.

4. **`sort` stability** — Jerboa's `sort` is NOT guaranteed stable. Use
   `stable-sort` when order of equal elements matters.

5. **Thread primitives** — Chez's `fork-thread` works but Gerbil's `spawn`
   API (with names, groups) is in `(std misc thread)`.
