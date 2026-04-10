# Regular Expressions, Composable Patterns, and PEG Grammars

Jerboa provides a three-tier text matching system: a unified regex API for everyday use, composable named patterns for building complex matchers, and a PEG grammar system for structured parsing.

---

## Quick Start

```scheme
(import (jerboa prelude))

;; Simple matching — available from the prelude, no extra imports
(re-match? "\\d+" "42")           ;; => #t (pregexp string)
(re-match? '(+ digit) "42")      ;; => #t (SRE s-expression)
(re-match? (rx (+ digit)) "42")  ;; => #t (rx macro)
```

---

## Tier 1: Unified Regex API — `(std regex)`

**Import:** Available from `(jerboa prelude)`. Also importable directly as `(std regex)`.

The `re` function compiles any pattern representation to an internal re-object. All API functions accept either compiled re-objects or inline patterns (strings, SRE lists, SRE symbols).

### Compilation

```scheme
(re "\\d+")           ;; from pregexp string
(re '(+ digit))       ;; from SRE list
(re 'digit)           ;; from SRE symbol
(re (re "\\d+"))      ;; idempotent — returns same object
(re? obj)             ;; #t if obj is a compiled re-object
```

### Full-String Match

```scheme
(re-match? pat str)   ;; #t if pat matches the entire string
(re-match? obj)       ;; 1-arg: #t if obj is a match result
```

### Search (First Match)

```scheme
(re-search pat str)          ;; first match anywhere, or #f
(re-search pat str start)    ;; search from offset

;; Inspecting match results:
(re-match-full  m)    ;; matched text
(re-match-start m)    ;; start index
(re-match-end   m)    ;; end index (exclusive)
(re-match-group m n)  ;; nth capture group (0 = full match)
(re-match-groups m)   ;; list of all capture groups
```

### Find All

```scheme
(re-find-all pat str)   ;; list of all non-overlapping match strings
```

### Named Captures

Named captures require SRE syntax with `(=> name ...)`:

```scheme
(define dated (re '(: (=> year  (= 4 digit)) "-"
                       (=> month (= 2 digit)) "-"
                       (=> day   (= 2 digit)))))
(let ([m (re-search dated "Event: 2026-04-09")])
  (re-match-named m 'year)    ;; => "2026"
  (re-match-named m 'month)   ;; => "04"
  (re-match-named m 'day))    ;; => "09"
```

### Numbered Captures (String Patterns)

```scheme
(re-groups "(\\w+)@(\\w+)" "user@host")   ;; => ("user" "host")
```

### Replace

```scheme
(re-replace     pat str replacement)   ;; replace first match
(re-replace-all pat str replacement)   ;; replace all matches
;; Backreferences: \\1, \\2 etc.
(re-replace "(\\w+)@(\\w+)" "user@host" "\\2@\\1")  ;; => "host@user"
```

### Split

```scheme
(re-split "\\s+" "a b  c")                    ;; => ("a" "b" "c")
(re-split '(+ space) "one two three")         ;; => ("one" "two" "three")
```

### Fold

```scheme
(re-fold pat kons knil str)
;; kons receives: (match-index match-object subject accumulator)

(re-fold "\\d+" (lambda (i m str acc)
                  (cons (re-match-full m) acc))
         '() "a1b2c3")
;; => ("3" "2" "1")
```

### Backend Selection

The facade automatically selects the best available backend:

- **Rust native** (`libjerboa_native.so`): Used for `re-match?` when available. Linear-time, no ReDoS risk.
- **pregexp**: Used for all capture-requiring operations and as fallback. Backtracking, but sufficient for most patterns.

No user action needed — backend selection is transparent.

---

## Tier 2: Composable Patterns — `(std rx)`

**Import:** `rx` and `define-rx` are available from `(jerboa prelude)`.  
Pre-built patterns require: `(import (std rx patterns))`

### The `rx` Macro

Compiles SRE forms at expansion time:

```scheme
(rx digit)                    ;; single SRE form
(rx (+ digit))                ;; compound form
(rx alpha digit alpha)        ;; multiple forms = implicit sequence (: ...)
```

### `define-rx` — Named, Composable Patterns

```scheme
(define-rx octet  (** 1 3 digit))
(define-rx ip4    (: octet "." octet "." octet "." octet))

(re-match? ip4 "192.168.1.1")     ;; => #t
(re-find-all ip4 "10.0.0.1 and 172.16.0.1")
;; => ("10.0.0.1" "172.16.0.1")
```

Patterns defined with `define-rx` are registered globally. Later `rx` or `define-rx` forms can reference them by name — the compiled pattern is spliced directly, avoiding re-compilation.

SRE keywords (`digit`, `alpha`, `alnum`, `space`, `word`, etc.) cannot be shadowed by `define-rx` — they are protected by a reserved-symbols whitelist.

### Pre-Built Pattern Library — `(std rx patterns)`

```scheme
(import (std rx patterns))
```

| Pattern | Matches |
|---------|---------|
| `rx:ipv4-octet` | 1-3 digits (structural, not semantic 0-255) |
| `rx:ipv4` | `192.168.1.1` |
| `rx:mac-address` | `AA:BB:CC:DD:EE:FF` |
| `rx:hostname` | `sub.example` |
| `rx:domain` | `sub.example.com` |
| `rx:email` | `user@example.com` |
| `rx:uuid` | `550e8400-e29b-41d4-a716-446655440000` |
| `rx:semver` | `1.2.3-beta.1+build.42` |
| `rx:iso8601-date` | `2026-04-09` |
| `rx:iso8601-datetime` | `2026-04-09T12:30:00Z` |
| `rx:time-hms` | `12:30:00` |
| `rx:identifier` | `_foo123` (C/Scheme style) |
| `rx:camel-case` | `myVarName` |
| `rx:kebab-case` | `my-var-name` |
| `rx:snake-case` | `my_var_name` |
| `rx:integer` | `42`, `-42`, `+42` |
| `rx:float` | `3.14`, `-0.5` |
| `rx:scientific` | `1.5e10`, `-2.0E-3` |
| `rx:hex-color` | `#FF8800`, `#FF8800CC` |
| `rx:hex-color-short` | `#F80` |
| `rx:quoted-string` | `"hello \"world\""` |
| `rx:single-quoted-string` | `'hello'` |
| `rx:blank-line` | Empty or whitespace-only line |
| `rx:jwt` | JSON Web Token (three base64url segments) |
| `rx:url` | `https://example.com/path?q=1` |

---

## Tier 3: PEG Grammar System — `(std peg)`

**Import:** `(import (std peg))`

PEG (Parsing Expression Grammar) with packrat memoization for O(n) parsing per rule. Suitable for structured data like CSV, config files, and simple DSLs.

### Defining Grammars

```scheme
(define-grammar csv
  (file    (sep-by row "\n"))
  (row     (sep-by field ","))
  (field   (or quoted bare))
  (quoted  (: (drop "\"") (* (~ "\"")) (drop "\"")))
  (bare    (* (~ (or "," "\n")))))

(csv:file "name,age\nAlice,30\nBob,25")
;; => (("name" "age") ("Alice" "30") ("Bob" "25"))
```

Each rule in a `define-grammar` becomes a public entry point: `grammar-name:rule-name`.

### PEG Operators

| Form | Meaning |
|------|---------|
| `"str"` | Literal string match |
| `(: e1 e2 ...)` | Sequence |
| `(or e1 e2 ...)` | Ordered choice (first match wins) |
| `(* e)` | Zero or more |
| `(+ e)` | One or more |
| `(? e)` | Optional |
| `(= n e)` | Exactly n repetitions |
| `(** m n e)` | Between m and n repetitions |
| `(>= n e)` | At least n repetitions |
| `(! e)` | Negative lookahead (consumes nothing) |
| `(& e)` | Positive lookahead (consumes nothing) |
| `(=> name e)` | Named capture → alist entry |
| `(drop e)` | Match and discard (not in result) |
| `(~ e)` | Complement: any single char NOT matching e |
| `(/ lo hi)` | Character range |
| `(sep-by e sep)` | Zero or more e separated by sep |
| `(sep-by1 e sep)` | One or more e separated by sep |
| `any` | Any single character |
| `epsilon` | Empty string (always succeeds) |
| `eof` | End of input |

### Named Captures

```scheme
(define-grammar date-parser
  (date  (: (=> year  (= 4 (/ "0" "9")))
             "-"
             (=> month (= 2 (/ "0" "9")))
             "-"
             (=> day   (= 2 (/ "0" "9")))))
  (digit (/ "0" "9")))

(date-parser:date "2026-04-09")
;; => (("year" . "2026") ("month" . "04") ("day" . "09"))
```

### Value Semantics

- **Strings**: Sequences of string matches are concatenated → `"abc"`
- **Named captures (=>)**: Produce alist entries → `(("name" . "value"))`
- **Mixed**: Alists are merged; plain strings become `("_" . "str")` entries
- **Repetition**: Collected into lists
- **`(drop ...)`**: Matched text is discarded, produces empty string (filtered from sequences)

### Error Reporting

Parse failures return a `peg-error` record with the farthest position reached, which helps identify where parsing went wrong.

### Limitations

- **No left-recursion**: PEG grammars must be right-recursive. Left-recursive rules silently fail (standard PEG behavior).
- **Full match required**: `peg-run` enforces that the input is consumed completely. Partial matches are treated as errors.

---

## Raw String Reader Syntax — `#r"..."`

The Jerboa reader (not Chez's built-in reader) supports raw strings:

```scheme
#r"\d+"           ;; → the 3-char string: backslash, d, plus
#r"[a-z]\w+"      ;; no double-escaping needed
#r"C:\Users\foo"  ;; Windows paths without escape hell
```

- All backslashes are literal — no escape processing
- `\"` is the only escape (produces a literal double-quote)
- Available in the Jerboa REPL and when reading files with the Jerboa reader
- **Not available** in files run with `scheme --script` (which uses Chez's built-in reader)

---

## SRE Quick Reference

S-expression Regular Expressions (SRFI-115 extended):

| SRE Form | Pregexp Equivalent | Meaning |
|----------|-------------------|---------|
| `digit` | `[0-9]` | One digit |
| `alpha` | `[a-zA-Z]` | One letter |
| `alnum` | `[a-zA-Z0-9]` | Letter or digit |
| `word` | `[a-zA-Z0-9_]` | Word character |
| `space` | `\s` | Whitespace |
| `upper` / `lower` | `[A-Z]` / `[a-z]` | Case |
| `any` | `.` | Any character |
| `(: e1 e2)` | `(?:e1e2)` | Sequence |
| `(or e1 e2)` | `(?:e1\|e2)` | Alternation |
| `(* e)` | `(?:e)*` | Zero or more |
| `(+ e)` | `(?:e)+` | One or more |
| `(? e)` | `(?:e)?` | Optional |
| `(= n e)` | `(?:e){n}` | Exactly n |
| `(** m n e)` | `(?:e){m,n}` | Between m and n |
| `(=> name e)` | `(e)` + name tracking | Named capture |
| `(~ e)` | `[^e]` | Complement (char class) |
| `(/ lo hi)` | `[lo-hi]` | Character range |
| `(w/nocase e)` | `(?i:e)` | Case-insensitive |
| `"str"` | `\Qstr\E` | Literal string (auto-quoted) |
