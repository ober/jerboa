# Jerboa Reader Syntax

_Source of truth: `lib/jerboa/reader.sls`. Last audited 2026-04-22._

Jerboa extends Chez's reader with Gerbil-style and Clojure-style surface
syntax. **Which reader runs matters**:

| Entry path                                 | Reader used        | `[...]` means          |
|--------------------------------------------|--------------------|------------------------|
| `scheme --libdirs lib --script file.ss`    | Chez built-in      | same as `(...)`        |
| Code read via `(jerboa-read port)` / embed | Jerboa custom      | `(list ...)` wrapper   |
| `.ss` file starting with `#!cloj`          | Jerboa, cloj mode  | `(list ...)` wrapper   |

**If you are writing everyday `.ss` files and running them with `scheme
--script`, brackets are just parens** — use them as block delimiters
exactly like Gerbil. The Clojure-vector interpretation only activates
through the explicit `jerboa-read` entry point (used by sandboxed embed
and tooling that re-reads source).

The table below lists every extension the Jerboa reader adds on top of
Chez. All of these are available when `jerboa-read` is active. A "mode"
column shows `default` (always), `cloj` (only after `#!cloj` or
`(reader-cloj-mode #t)`), or `both`.

## Extensions

| Syntax                 | Desugars to                                    | Mode    | Example                                          |
|------------------------|------------------------------------------------|---------|--------------------------------------------------|
| `[a b c]`              | `(list a b c)`                                 | both†   | `[1 2 3]` → `(list 1 2 3)`                       |
| `{m obj a ...}`        | `(~ obj 'm a ...)`                             | default | `{push! stk 1}` → `(~ stk 'push! 1)`             |
| `{k v k v ...}`        | `(plist->hash-table (list k v ...))`           | cloj    | `{:a 1 :b 2}` → hash-map literal                 |
| `{}` (empty)           | `(make-hash-table)`                            | cloj    | empty hash map                                   |
| `:pkg/mod`             | `(pkg mod)`                                    | default | `:std/sort` → `(std sort)`                       |
| `:pkg/sub/mod`         | `(pkg sub mod)`                                | default | `:std/text/json` → `(std text json)`             |
| `:name`                | keyword `#:name`                               | cloj    | `:foo` → keyword                                 |
| `name:`                | keyword `#:name`                               | both    | `port: 8080` → `#:port 8080`                     |
| `#{a b c}`             | `(hash-set a b c)`                             | both    | `#{1 2 3}` → set literal                         |
| `#(a b c)`             | vector `#(a b c)`                              | default | standard vector                                  |
| `#(+ % 1)`             | `(fn-literal (+ % 1))`                         | cloj    | anonymous fn — `%` / `%1` / `%2` are args        |
| `#<<END\n...\nEND`     | string literal (heredoc)                       | both    | multi-line raw text, newlines preserved          |
| `#r"a\b"`              | string `"a\\b"` (raw — only `\"` escapes)      | both    | useful for regex patterns                        |
| `@expr`                | `(deref expr)`                                 | both    | `@atom` → `(deref atom)`                         |
| `'x` `` `x `` `,x` `,@x` | quote / quasiquote / unquote / -splicing     | both    | standard Scheme                                  |
| `#!cloj` (top of file) | activates Clojure reader mode for the file     | marker  | affects remaining reads                          |
| `nil`                  | `#f`                                           | cloj    | literal identifier becomes false                 |
| `true` / `false`       | `#t` / `#f`                                    | cloj    | literal identifiers                              |

† Brackets are parens (`=` `(...)`) under Chez's built-in reader, which
is what runs `.ss` scripts invoked with `scheme --script`. Only the
Jerboa custom reader wraps brackets with `list`.

## What the reader does **not** provide

The following look like they could be reader syntax but are **plain
identifiers** provided by the prelude — they are NOT reader rewrites:

- `->` `->>` `as->` `some->` `cond->` — threading macros (syntactic
  forms, handled by the expander not the reader)
- `p.x` dot-access — handled by the `using` form, not the reader
- `:expr pred?` type casts — a two-argument form `(: e p)` expanded by
  the prelude; `:` is a normal identifier

Because these are expander/macro features, you can rebind or shadow
them; reader-level syntax cannot be shadowed.

## Safety limits

The Jerboa reader enforces resource ceilings (configurable via
parameters in `(jerboa reader)`):

- `(*max-nesting-depth*)` — how deep forms can nest
- `(*max-list-length*)` — elements per list
- `(*max-symbol-length*)` — chars per symbol
- `(*max-comment-nesting*)` — depth of `#| ... |#` block comments

These prevent untrusted input from exhausting resources during parse.
Chez's built-in reader has no such limits, so any `.ss` file loaded
through stock `scheme` bypasses them.

## Quick reference for LLMs

If you are generating Jerboa code:

1. **Default assumption**: the user runs code with `scheme --script`,
   so brackets behave as parens. Write `(let ([x 1]) body)` freely.
2. **Method dispatch**: `{m obj arg ...}` always means `(~ obj 'm
   arg ...)`. Use when you know `obj` has a method `m`.
3. **Module paths**: prefer the explicit `(import (std text json))`
   form in examples; `:std/text/json` is correct but looks unusual
   outside of Gerbil-style code.
4. **Heredocs**: `#<<END\nmulti\nline\nEND` is the only way to embed
   a string containing unescaped quotes and newlines.
5. **Never** write `(fn-literal ...)` or `(deref ...)` directly —
   prefer `(lambda (...) ...)` and `(@ atom)` spellings for clarity
   unless you're targeting Clojure-mode code.
