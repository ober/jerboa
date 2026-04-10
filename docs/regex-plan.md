# Unified Regex System for Jerboa — Implementation Plan

**Branch:** `regex`  
**Status:** Planning  
**Goal:** Make regex in Jerboa the best in any Scheme — zero escape hell, composable patterns, smart backend selection, LLM-friendly API.

---

## Table of Contents

1. [Current State](#current-state)
2. [Tier 1: Raw Strings + Unified Facade](#tier-1)
3. [Tier 2: Composable rx Macro + Pattern Library](#tier-2)
4. [Tier 3: PEG Grammar System](#tier-3)
5. [File Map](#file-map)
6. [Testing Plan](#testing-plan)
7. [Makefile Integration](#makefile-integration)
8. [Prelude Integration](#prelude-integration)

---

## Current State

Five backends exist with incompatible APIs. A user must pick one and learn its names:

| Module | Import | Compile fn | Match fn | Replace fn | Split fn | Notes |
|---|---|---|---|---|---|---|
| `(std pregexp)` | manual | `pregexp` | `pregexp-match` | `pregexp-replace` | `pregexp-split` | Backtracking, limited ReDoS protection |
| `(std regex-ct)` | manual | `define-regex` (macro) | `regex-match?` | — | — | DFA at compile-time, no captures |
| `(std regex-native)` | manual | `regex-compile` | `regex-match?` | `regex-replace-all` | — | Rust backend, linear-time, needs `libjerboa_native.so` |
| `(std pcre2)` | manual | `pcre2-compile` | `pcre2-match` | `pcre2-replace-all` | `pcre2-split` | Full PCRE2, needs `libpcre2-8` |
| `(std srfi srfi-115)` | manual | `regexp` | `regexp-matches?` | `regexp-replace` | `regexp-split` | SRE s-expressions, compiles to pregexp |

**Key problems:**
- No raw string syntax → every `\d` requires `\\d` (double escaping)
- No unified API → users must import one of five modules, learn its names
- SRFI-115 (the good SRE syntax) compiles to the *slowest* backend (pregexp)
- No named/composable pattern system
- `regex-native` requires manual `regex-free` for cleanup
- PCRE2 is unavailable in standard builds (requires `chez-pcre2` library)

---

## Tier 1: Raw Strings + Unified Facade {#tier-1}

### 1A. Raw String Reader Syntax: `#r"..."`

**File to modify:** `lib/jerboa/reader.sls`

**What it does:** `#r"foo\nbar"` reads as the literal string `foo\nbar` with no escape processing. Backslashes are passed through verbatim. This eliminates the core pain of regex: writing `"\\d+\\.\\d+"` becomes `#r"\d+\.\d+"`.

**Where to add it:** In `read-hash-impl` (line 328), inside the giant `cond`. Add a new clause **before** the `else` error clause at line 511. Insert after the `#<` heredoc clause (line 458):

```scheme
;; #r"..." raw string — no escape processing
((char=? ch #\r)
 (reader-next! rs)
 (let ((ch2 (reader-peek rs)))
   (unless (and (char? ch2) (char=? ch2 #\"))
     (error 'jerboa-read "expected \" after #r"))
   (reader-next! rs)  ;; consume the opening "
   (annotate rs (read-raw-string rs) loc)))
```

**Add the `read-raw-string` helper** after `read-number-chars` (around line 524):

```scheme
;; read-raw-string: read chars until unescaped closing ", no escape processing.
;; The only thing we handle is \" so you can embed a quote. Everything else
;; (backslashes, newlines, etc.) is passed through verbatim.
(define (read-raw-string rs)
  (let loop ((chars '()))
    (let ((ch (reader-next! rs)))
      (cond
        ((eof-object? ch)
         (error 'jerboa-read "unterminated raw string"))
        ((char=? ch #\")
         (list->string (reverse chars)))
        ((and (char=? ch #\\)
              (let ((next (reader-peek rs)))
                (and (char? next) (char=? next #\"))))
         ;; \" → literal quote inside raw string
         (reader-next! rs)
         (loop (cons #\" chars)))
        (else
         (loop (cons ch chars)))))))
```

**Examples after implementation:**
```scheme
#r"\d+"          ;; → the string "\d+"     (was "\\d+")
#r"\d+\.\d+"     ;; → the string "\d+\.\d+" (was "\\d+\\.\\d+")
#r"^[a-z]+$"     ;; → the string "^[a-z]+$" (was "^[a-z]+$" — no change here, but consistent)
#r"foo\"bar"     ;; → the string "foo\"bar"  (escaped quote inside raw string)
```

**Test:** `tests/test-reader-rawstring.ss` (see Testing Plan).

---

### 1B. Unified Regex Facade: `(std regex)`

**New file:** `lib/std/regex.sls`

This is the main deliverable of Tier 1. One import, one set of names, smart backend selection.

#### API Design

```scheme
(import (std regex))

;; --- Compilation ---
;; Accepts: string pattern, SRE s-expression, or already-compiled re object
;; Returns: an opaque `re` object
(re pat)                           ;; e.g. (re "\\d+") or (re #r"\d+") or (re '(+ digit))

;; --- Predicates ---
(re? x)                            ;; is x a compiled re object?
(re-match? re-or-pat str)          ;; full-string match → #t or #f
(re-search re-or-pat str)          ;; first match anywhere → match object or #f
(re-search re-or-pat str start)    ;; search starting at byte offset

;; --- Extraction ---
(re-find-all re-or-pat str)        ;; all non-overlapping match strings → list of strings
(re-groups re-or-pat str)          ;; all capture groups of first match → list or #f

;; --- Replacement ---
(re-replace re-or-pat str rep)     ;; replace first match
(re-replace-all re-or-pat str rep) ;; replace all matches

;; --- Splitting ---
(re-split re-or-pat str)           ;; split str by pattern → list of strings

;; --- Folding ---
(re-fold re-or-pat kons knil str)  ;; fold over all matches

;; --- Match object access ---
(re-match? obj)                    ;; is obj a match object? (overloaded — see below)
(re-match-full m)                  ;; full matched string
(re-match-group m n)               ;; nth capture group string (0 = full match)
(re-match-groups m)                ;; all groups as list of strings
(re-match-start m)                 ;; start char index of full match
(re-match-end m)                   ;; end char index of full match
```

**Note on `re-match?` overloading:** When called with `(re-match? re str)` it performs a full-string match test. When called with one argument `(re-match? obj)` it tests if `obj` is a match object. Implement with `case-lambda`.

#### Internal Architecture

**Re object record:**
```scheme
(define-record-type re-object
  (fields
    (immutable pattern)    ;; original pattern string or SRE
    (immutable backend)    ;; symbol: 'dfa | 'native | 'pregexp
    (immutable compiled))  ;; backend-specific compiled value
  (sealed #t))
```

**Match object record:**
```scheme
(define-record-type re-match-object
  (fields
    (immutable full)       ;; string: the full matched text
    (immutable groups)     ;; vector of strings or #f (capture groups)
    (immutable start)      ;; integer: start index in original string
    (immutable end))       ;; integer: end index in original string
  (sealed #t))
```

**Backend selection logic** — called inside `(re pat)`:

```
(re pat) →
  if pat is already re-object → return as-is
  if pat is a list (SRE) → sre->string pat → classify string
  if pat is a string →
    classify:
      dfa-compatible? (no backrefs, no lookahead, no \1 etc.)
        AND native-available? → use 'native (Rust, linear-time)
        AND (not native-available?) → use 'dfa (compile-time fallback)
      else → use 'pregexp (backtracking, supports all features)
```

**`dfa-compatible?`** — already implemented in `(std regex-ct)` as `regex-dfa-compatible?`. Re-export or call it.

**`native-available?`** — detect at library load time:
```scheme
(define native-available?
  (guard (exn [#t #f])
    (or (load-shared-object "libjerboa_native.so")
        (load-shared-object "lib/libjerboa_native.so"))
    #t))
```

#### SRE to String Conversion

The `(std srfi srfi-115)` module already implements `sre->pregexp`. **Do not duplicate it.** Import `(std srfi srfi-115)` and use `regexp` + the internal `rx-pattern` accessor to convert SRE → pregexp string, then classify that string for backend selection.

However, since `rx-pattern` is internal to srfi-115 (the record is `rx`, field is `pattern`), we need to expose a conversion helper. **Add one export to `lib/std/srfi/srfi-115.sls`:**

```scheme
;; Add to exports list:
sre->pattern-string

;; Add to body:
(define (sre->pattern-string sre)
  (sre->pregexp sre))  ;; already defined internally
```

Then in `(std regex)`:
```scheme
(import (std srfi srfi-115))
;; use sre->pattern-string to convert SRE to string, then classify
```

#### Native Backend Handle Lifecycle

`regex-native` requires `(regex-free handle)` — users must never see this. Use Chez guardians:

```scheme
(define re-guardian (make-guardian))

;; Call at allocation time:
(define (make-native-re pattern)
  (re-free-garbage)
  (let ([handle (regex-compile pattern)])
    (let ([obj (make-re-object pattern 'native handle)])
      (re-guardian obj)
      obj)))

;; Call before each allocation and in a finalizer thread:
(define (re-free-garbage)
  (let loop ([obj (re-guardian)])
    (when obj
      (when (eq? (re-object-backend obj) 'native)
        (guard (exn [#t #f])
          (regex-free (re-object-compiled obj))))
      (loop (re-guardian)))))
```

#### Full Implementation Skeleton

```scheme
#!chezscheme
;;; (std regex) — Unified regex facade
;;;
;;; One import, one set of names. Automatically selects the best available
;;; backend: Rust regex (linear-time) for DFA-compatible patterns, pregexp
;;; for patterns requiring backreferences or lookahead.
;;;
;;; Usage:
;;;   (import (std regex))
;;;
;;;   (re-match? #r"\d+" "123")         ;; => #t  (raw string, no escaping)
;;;   (re-match? "\\d+" "123")          ;; => #t  (traditional string)
;;;   (re-match? '(+ digit) "123")      ;; => #t  (SRE s-expression)
;;;
;;;   (re-find-all #r"\d+" "a1b22c333") ;; => ("1" "22" "333")
;;;
;;;   (let ([m (re-search #r"(\w+)@(\w+)" "user@host")])
;;;     (re-match-groups m))            ;; => ("user" "host")

(library (std regex)
  (export
    re re?
    re-match? re-search
    re-find-all re-groups
    re-replace re-replace-all
    re-split re-fold
    re-match-full re-match-group re-match-groups
    re-match-start re-match-end)

  (import (chezscheme)
          (std pregexp)
          (std srfi srfi-115)
          (std regex-native))

  ;; ... implementation as described above
  )
```

---

## Tier 2: Composable `rx` Macro + Pattern Library {#tier-2}

### 2A. The `rx` Macro

**New file:** `lib/std/rx.sls`

The `rx` macro allows building regex patterns from named sub-patterns. It is a step beyond SRFI-115: patterns are bound to Scheme variables and reused by name, enabling truly composable, self-documenting regexes.

#### Design

```scheme
(import (std rx))

;; Simple use: rx produces a compiled re object (uses (std regex) backend)
(rx digit)                          ;; compiled re matching [0-9]
(rx (+ digit))                      ;; compiled re matching [0-9]+
(rx (: alpha (* alnum)))            ;; identifier: letter then letters/digits

;; Naming sub-patterns with define-rx
(define-rx octet (** 1 3 digit))
(define-rx ip-addr (: octet "." octet "." octet "." octet))

(re-match? ip-addr "192.168.1.1")   ;; => #t
(re-match? ip-addr "999.x.1.1")     ;; => #f (999 > 255 not checked — regex limitation, noted)

;; Named captures in rx
(rx (=> year (= 4 digit)) "-" (=> month (= 2 digit)) "-" (=> day (= 2 digit)))
;; This compiles to a pattern with named groups year/month/day
;; re-search returns a match object where (re-match-named m 'year) works

;; Inline raw strings inside rx
(rx #r"\d+" "." #r"\d+")            ;; raw strings accepted as literals inside rx
```

#### `rx` macro expansion

`rx` is a macro that expands SRE-like forms to a `(re ...)` call with an SRE argument:

```scheme
(define-syntax rx
  (syntax-rules ()
    [(_ form ...)
     (re '(: form ...))]))

(define-syntax define-rx
  (syntax-rules ()
    [(_ name form ...)
     (define name (rx form ...))]))
```

This is intentionally simple because all the heavy lifting is in the SRE compiler. The key additions over plain SRFI-115 SREs:

1. **`=>`  for named captures:** `(=> name sre)` — compile to a named capture group
2. **Raw string literals inside rx:** detect `#r"..."` (they're already just strings by the time the macro sees them)
3. **Cross-reference to defined patterns:** `(rx (: octet "."))` where `octet` is a prior `define-rx` — this works because `define-rx` produces a `re-object` and `rx` auto-splices it

#### Splicing defined patterns

When a symbol appears inside `rx` and refers to a `re-object`, it should be inlined (its pattern string embedded). This requires a compile-time or runtime lookup:

- **Runtime approach (simpler):** `re` already accepts re-objects and returns them. For string concatenation, extract the pattern string from the re-object and embed it. Add `re-object-pattern-string` accessor.
- **Compile-time approach (optimal):** Use `define-syntax` with `identifier-syntax` or phase-1 eval. This is complex — implement runtime first.

**Runtime splicing implementation:**

```scheme
;; In (std rx):
(define (sre-with-refs->string sre env)
  ;; env: alist of (symbol . re-object) for splicing
  ;; Walk the SRE tree; if a symbol is found in env, splice its pattern string
  ...)
```

#### Named captures: `=>`

Add `=>` handling to the SRE compiler in `(std srfi srfi-115)`. Modify `sre->pregexp`:

```scheme
;; Add to the (case head ...) in sre->pregexp:
[(=>)
 ;; (=> name sre ...) — named capture group
 ;; Compiles to (?P<name>...) for pregexp, or (?<name>...) for PCRE2
 (let ([name (symbol->string (car args))]
       [body (apply string-append (map sre->pregexp (cdr args)))])
   (string-append "(?P<" name ">" body ")"))]
```

Then add `re-match-named` to `(std regex)`:

```scheme
(define (re-match-named m name)
  ;; Only works when backend is pregexp or pcre2
  ;; Extract named group from the match object
  ...)
```

### 2B. Built-in Pattern Library

**New file:** `lib/std/rx/patterns.sls`

Pre-defined `define-rx` patterns for common tasks. Users import this and get battle-tested patterns.

```scheme
(library (std rx patterns)
  (export
    ;; Network
    rx:ipv4 rx:ipv6 rx:mac-address
    rx:url rx:url-http rx:url-https
    rx:domain rx:hostname
    rx:email rx:email-local rx:email-domain

    ;; Identity & tokens
    rx:uuid rx:uuid-v4
    rx:jwt
    rx:hex-color rx:hex-color-short

    ;; Numbers
    rx:integer rx:unsigned-integer rx:float rx:scientific
    rx:positive-float rx:negative-float

    ;; Dates & times
    rx:iso8601-date rx:iso8601-datetime rx:iso8601-full
    rx:date-ymd rx:date-mdy rx:date-dmy
    rx:time-hms rx:time-hm

    ;; Identifiers
    rx:identifier rx:camel-case rx:kebab-case rx:snake-case
    rx:semver

    ;; Text
    rx:word rx:whitespace rx:blank-line
    rx:quoted-string rx:single-quoted-string)

  (import (std rx))

  ;; --- Network ---
  (define-rx rx:ipv4-octet (** 1 3 digit))
  (define-rx rx:ipv4 (: rx:ipv4-octet "." rx:ipv4-octet "."
                          rx:ipv4-octet "." rx:ipv4-octet))

  (define-rx rx:domain-label (: alpha (* (or alnum "-"))))
  (define-rx rx:tld (** 2 10 alpha))
  (define-rx rx:domain (: rx:domain-label (+ (: "." rx:domain-label)) "." rx:tld))

  (define-rx rx:email-local (+ (or alnum (/ #\! #\~))))  ;; simplified
  (define-rx rx:email (: rx:email-local "@" rx:domain))

  (define-rx rx:uuid-segment4 (= 4 hex-digit))
  (define-rx rx:uuid-segment8 (= 8 hex-digit))
  (define-rx rx:uuid-segment12 (= 12 hex-digit))
  (define-rx rx:uuid (: rx:uuid-segment8 "-" rx:uuid-segment4 "-"
                          rx:uuid-segment4 "-" rx:uuid-segment4 "-"
                          rx:uuid-segment12))

  ;; --- Numbers ---
  (define-rx rx:integer (: (? (or "+" "-")) (+ digit)))
  (define-rx rx:float  (: (? (or "+" "-")) (+ digit) "." (* digit)))

  ;; --- Dates ---
  (define-rx rx:iso8601-date (: (= 4 digit) "-" (= 2 digit) "-" (= 2 digit)))
  (define-rx rx:time-hms (: (= 2 digit) ":" (= 2 digit) ":" (= 2 digit)))
  (define-rx rx:iso8601-datetime (: rx:iso8601-date (or "T" " ") rx:time-hms))

  ;; --- Identifiers ---
  (define-rx rx:identifier (: (or alpha "_") (* (or alnum "_"))))
  (define-rx rx:semver (: (+ digit) "." (+ digit) "." (+ digit)
                            (? (: "-" (+ (or alnum "." "-"))))
                            (? (: "+" (+ (or alnum "." "-"))))))

  ;; --- Text ---
  (define-rx rx:quoted-string (: "\"" (* (or (~ "\"\\") (: "\\" any))) "\""))
  (define-rx rx:word (+ (or alpha "_")))
  )
```

**Usage:**
```scheme
(import (std rx patterns))

(re-match? rx:email "user@example.com")     ;; => #t
(re-match? rx:uuid "550e8400-e29b-41d4-a716-446655440000") ;; => #t
(re-match? rx:semver "1.2.3-beta.1+build.42") ;; => #t
(re-find-all rx:ipv4 "hosts: 10.0.0.1 and 192.168.1.1")
;; => ("10.0.0.1" "192.168.1.1")
```

---

## Tier 3: PEG Grammar System {#tier-3}

**New file:** `lib/std/peg.sls`

PEG (Parsing Expression Grammars) go beyond regex: they can match recursive structures, produce ASTs, and handle context-sensitive syntax. They are strictly more powerful than regex for parsing real formats.

### Design

```scheme
(import (std peg))

;; Define a grammar
(define-grammar csv
  (file    (=> rows (+ row)))
  (row     (=> fields (sep-by field ",")) (drop "\n"))
  (field   (or quoted-field plain-field))
  (quoted-field  (drop "\"") (=> value (* (or escaped-char non-quote))) (drop "\""))
  (escaped-char  (drop "\\") any)
  (non-quote     (~ "\""))
  (plain-field   (=> value (* (~ (or "," "\n"))))))

;; Run the grammar against a string
(peg-parse csv:file "name,age\nAlice,30\nBob,25\n")
;; => ((rows ((fields ("name" "age"))
;;            (fields ("Alice" "30"))
;;            (fields ("Bob" "25")))))
```

### PEG Operators

```scheme
;; Sequence: implicit — multiple forms in a rule body are a sequence
;; Ordered choice: (or e1 e2 ...)
;; Zero or more: (* e)
;; One or more: (+ e)
;; Optional: (? e)
;; Not predicate: (! e)    — succeeds without consuming if e fails
;; And predicate: (& e)    — succeeds without consuming if e succeeds
;; Capture:       (=> name e) — bind matched text to name in result alist
;; Drop:          (drop e)   — match but discard from result
;; Any char:      any
;; Literal:       "string"
;; Char class:    (/ #\a #\z)  etc. (SRE char class syntax)
;; Rule ref:      symbol naming another rule in the grammar
;; Counted rep:   (= n e), (** m n e)
;; sep-by:        (sep-by e sep) — e separated by sep, returns list
```

### AST Structure

Each rule returns either:
- A **string** for terminal matches
- An **alist** `((name . value) ...)` for rules with `=>` captures
- A **list** for `+` / `*` over multiple matches

### Internal Implementation Strategy

PEG parsers are implemented as **recursive descent with memoization** (Packrat parsing). Each rule becomes a Scheme procedure `(rule input pos) → (success value new-pos) | (failure)`.

`define-grammar` macro expands to:
1. A set of mutually recursive procedures (one per rule)
2. A memoization table (hash on `(rule-name . position)`)
3. A `grammar-name:rule-name` accessor procedure for each rule

**Macro expansion sketch:**
```scheme
(define-syntax define-grammar
  (syntax-rules ()
    [(_ name (rule-name peg-body ...) ...)
     (begin
       (define memo-table (make-hash-table))
       (define (rule-name input pos) ...) ...
       (define (name:rule-name input)
         (let ([result (rule-name (string->list input) 0)])
           ...))
       ...)]))
```

### Error Reporting

PEG parsers should produce useful error messages. Track the **furthest failure position** (the "error position") and report what was expected there.

```scheme
;; Error object:
(define-record-type peg-error
  (fields position expected input)
  (sealed #t))

;; Usage:
(peg-parse csv:file "name,age\nAlice,\"unclosed")
;; => (peg-error 20 '("\"" or end-of-field) "name,age\nAlice,\"unclosed")
```

### Relationship to `(std regex)` and `(std rx)`

- PEG rules may embed `(std rx)` patterns as terminals: `(rx-term #r"\d+")`
- Simple grammars (no recursion, no `!`/`&`) can be compiled to DFA via `(std regex-ct)` — detect and optimize automatically
- `define-grammar` and `define-rx` may coexist in the same file

---

## File Map {#file-map}

```
lib/
  jerboa/
    reader.sls              MODIFY — add #r"..." raw string dispatch (lines 458–512)

  std/
    regex.sls               CREATE — unified facade (Tier 1B)
    rx.sls                  CREATE — rx macro + define-rx (Tier 2A)
    peg.sls                 CREATE — PEG grammar system (Tier 3)

    rx/
      patterns.sls          CREATE — built-in pattern library (Tier 2B)

    srfi/
      srfi-115.sls          MODIFY — add sre->pattern-string export, add => support

tests/
  test-reader-rawstring.ss  CREATE — #r"..." reader tests
  test-regex.ss             CREATE — unified (std regex) tests
  test-rx.ss                CREATE — rx macro + define-rx tests
  test-rx-patterns.ss       CREATE — pattern library tests
  test-peg.ss               CREATE — PEG grammar tests

docs/
  regex-plan.md             THIS FILE
```

---

## Testing Plan {#testing-plan}

All test files follow the project-standard structure:

```scheme
#!chezscheme
;;; Tests for (std foo) — brief description

(import (chezscheme) (std foo))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(printf "--- Section Name ---~%~%")
;; ... tests ...
(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
```

### `tests/test-reader-rawstring.ss`

```
- #r"abc" reads as "abc"
- #r"\d+" reads as "\\d+" (the actual 3-char string)
- #r"\n" reads as "\\n" (backslash-n, not newline)
- #r"foo\"bar" reads as "foo\"bar" (escaped quote)
- #r"" reads as "" (empty)
- #r applied to non-string char raises read error
- Raw string works as function argument: (string-length #r"\d+") => 3
- Raw string works in define: (define pat #r"\d+")
```

### `tests/test-regex.ss`

```
;; re compilation
- (re? (re "\\d+")) => #t
- (re? (re #r"\d+")) => #t     ;; raw string
- (re? (re '(+ digit))) => #t   ;; SRE
- (re? (re (re "abc"))) => #t   ;; idempotent

;; re-match? — full string
- (re-match? "\\d+" "123") => #t
- (re-match? "\\d+" "abc") => #f
- (re-match? "\\d+" "12abc") => #f    ;; full match only
- (re-match? #r"\d+" "123") => #t
- (re-match? '(+ digit) "123") => #t

;; re-search — partial
- (re-search "\\d+" "abc123def") => match object
- (re-match-full (re-search "\\d+" "abc123def")) => "123"
- (re-search "\\d+" "abc") => #f
- (re-match-start (re-search "\\d+" "abc123")) => 3
- (re-match-end (re-search "\\d+" "abc123")) => 6

;; re-find-all
- (re-find-all "\\d+" "a1b22c333") => ("1" "22" "333")
- (re-find-all "\\d+" "abc") => ()
- (re-find-all #r"\d+" "1 2 3") => ("1" "2" "3")

;; re-replace / re-replace-all
- (re-replace "\\d+" "abc123def" "NUM") => "abcNUMdef"
- (re-replace-all "\\d+" "1a2b3c" "N") => "NaNbNc"

;; re-split
- (re-split "\\s+" "a b  c") => ("a" "b" "c")
- (re-split "," "a,b,c") => ("a" "b" "c")

;; re-groups
- (re-groups "(\\w+)@(\\w+)" "user@host") => ("user" "host")
- (re-groups "\\d+" "123") => ()       ;; no groups
- (re-groups "\\d+" "abc") => #f       ;; no match

;; re-fold
- (re-fold "\\d+" (lambda (i m str acc) (cons (re-match-full m) acc)) '() "a1b2c3")
  => ("3" "2" "1")  ;; reversed by cons

;; SRE round-trip
- (re-match? '(+ digit) "123") => #t
- (re-match? '(: alpha (* alnum)) "hello123") => #t
- (re-match? '(or "cat" "dog") "cat") => #t
- (re-match? '(or "cat" "dog") "fish") => #f

;; Backend safety
- DFA-compatible patterns use non-backtracking backend
- Patterns with backrefs fall back to pregexp
- native-available? check doesn't crash when .so is absent
```

### `tests/test-rx.ss`

```
;; rx macro
- (re? (rx digit)) => #t
- (re-match? (rx (+ digit)) "123") => #t
- (re-match? (rx (: alpha (* alnum))) "hello123") => #t

;; define-rx
- (define-rx my-int (+ digit)) — defines a re-object
- (re? my-int) => #t
- (re-match? my-int "42") => #t
- (re-match? my-int "x") => #f

;; define-rx composition
- (define-rx octet (** 1 3 digit))
- (define-rx ip4 (: octet "." octet "." octet "." octet))
- (re-match? ip4 "192.168.1.1") => #t
- (re-match? ip4 "999.x.y.z") => #f

;; Named captures with =>
- (define-rx dated (: (=> year (= 4 digit)) "-"
                       (=> month (= 2 digit)) "-"
                       (=> day (= 2 digit))))
- (let ([m (re-search dated "2026-04-09")])
    (re-match-named m 'year)) => "2026"
- (let ([m (re-search dated "2026-04-09")])
    (re-match-named m 'month)) => "04"
```

### `tests/test-rx-patterns.ss`

```
(import (std rx patterns))

;; Email
- (re-match? rx:email "user@example.com") => #t
- (re-match? rx:email "bad-email") => #f
- (re-match? rx:email "a@b.co") => #t

;; IPv4
- (re-match? rx:ipv4 "192.168.1.1") => #t
- (re-match? rx:ipv4 "256.0.0.1") => #f   ;; 256 > 255 — pattern can't check value
- (re-match? rx:ipv4 "not-an-ip") => #f

;; UUID
- (re-match? rx:uuid "550e8400-e29b-41d4-a716-446655440000") => #t
- (re-match? rx:uuid "not-a-uuid") => #f

;; Semver
- (re-match? rx:semver "1.2.3") => #t
- (re-match? rx:semver "1.2.3-beta.1") => #t
- (re-match? rx:semver "1.2.3+build.1") => #t
- (re-match? rx:semver "1.2") => #f

;; ISO date
- (re-match? rx:iso8601-date "2026-04-09") => #t
- (re-match? rx:iso8601-date "26-4-9") => #f

;; Identifiers
- (re-match? rx:identifier "hello") => #t
- (re-match? rx:identifier "_private") => #t
- (re-match? rx:identifier "123bad") => #f
```

### `tests/test-peg.ss`

```
(import (std peg))

;; Basic literal matching
;; Sequence matching
;; Ordered choice (or)
;; Repetition (* +)
;; Optional (?)
;; Not predicate (!)
;; Named captures (=>)
;; Drop
;; sep-by
;; Multi-rule grammar
;; CSV grammar (full integration test)
;; Error reporting (peg-error? on failure)
;; Recursive grammar (nested parentheses)
```

---

## Makefile Integration {#makefile-integration}

Add test targets to the existing `Makefile`. Insert in the `test` target dependency list and add individual targets:

```makefile
# Add to main test target dependency list:
test: ... test-regex test-rx test-peg

# Add after existing regex-related targets:
test-rawstring:
	$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-reader-rawstring.ss

test-regex:
	$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-regex.ss

test-rx:
	$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-rx.ss

test-rx-patterns:
	$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-rx-patterns.ss

test-peg:
	$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-peg.ss

# Optional: run all regex-related tests together
test-regex-all: test-rawstring test-regex test-rx test-rx-patterns test-peg
```

Note the pattern for optional-dependency tests (used when `libjerboa_native.so` may be absent):

```makefile
test-regex-native:
	@$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-regex.ss 2>/dev/null \
		|| echo "  regex-native: SKIP (libjerboa_native.so not found)"
```

---

## Prelude Integration {#prelude-integration}

**File to modify:** `lib/jerboa/prelude.sls`

After Tier 1 and 2 are complete, add regex to the prelude so users get it from `(import (jerboa prelude))` without any extra imports.

### Export additions (add after the `string-match?` group, around line 75):

```scheme
    ;; ---- std/regex ----
    re re?
    re-match? re-search
    re-find-all re-groups
    re-replace re-replace-all
    re-split re-fold
    re-match-full re-match-group re-match-groups
    re-match-start re-match-end

    ;; ---- std/rx ----
    rx define-rx
```

### Import additions (add after `(std misc string)` around line 240):

```scheme
    (std regex)
    (std rx)
```

**Note:** `(std rx patterns)` is **not** added to the prelude — it's too large and domain-specific. Users who need patterns import it explicitly.

**Note:** `(std peg)` is **not** added to the prelude either — it's a specialized tool. Import explicitly.

### AI compatibility alias to add

LLMs trained on Racket, Python, or JavaScript will likely try these names. Add them to the AI compatibility aliases section of the prelude:

```scheme
;; In export list (AI compat section):
regex-match regex-search regex-replace  ;; common generic names

;; In body (AI compat definitions):
(define (regex-match pat str)   (re-search pat str))
(define (regex-search pat str)  (re-search pat str))
(define (regex-replace pat str rep) (re-replace pat str rep))
```

---

## Implementation Order

Work through this in strict order — each tier depends on the previous:

1. **`#r"..."` reader** (reader.sls) — no dependencies, enables cleaner code in all subsequent files
2. **`sre->pattern-string` in srfi-115** — needed by the facade
3. **`(std regex)` facade** — the core of Tier 1, depends on pregexp, regex-native, srfi-115
4. **Test: test-reader-rawstring.ss + test-regex.ss** — validate before proceeding
5. **`=>` named captures in srfi-115** — needed by rx macro
6. **`(std rx)` macro** — depends on std/regex
7. **`(std rx/patterns)`** — depends on std/rx
8. **Test: test-rx.ss + test-rx-patterns.ss**
9. **Prelude integration** — add re/rx exports
10. **`(std peg)`** — Tier 3, depends on std/regex for terminal matching
11. **Test: test-peg.ss**

---

## Key Constraints & Gotchas

**Never guess module names** — always use `jerboa_module_exports` before calling a function from any std module.

**SRFI-115 is the bridge** — the SRE s-expression syntax in `(std srfi srfi-115)` is the right abstraction. Extend it rather than reinventing.

**PCRE2 is optional** — `(std pcre2)` requires `chez-pcre2` which is an external library not guaranteed to be installed. Never make it a hard dependency of `(std regex)`. The pregexp fallback must always work.

**`regex-native` requires `libjerboa_native.so`** — detect availability at load time with `guard`. The facade must work without it.

**Reader modification is delicate** — the `read-hash-impl` cond has a fall-through `else` at line 511 that raises an error. Insert the `#r` clause before this `else`. After editing, run `make build` and check for `multiple definitions` or balance errors immediately with `jerboa_check_balance`.

**DFA compilation is for full-match only** — `(std regex-ct)`'s `define-regex` produces a matcher for full strings. For search (partial match), always use pregexp or regex-native. The facade's backend selection must account for this: use DFA only when the caller is doing full-match.

**Guardian cleanup** — `re-free-garbage` must be called before each new native regex compilation. The guardian does not call cleanup automatically — you must drain it.

**Avoid `(std pcre2)` in `(std regex)`** — PCRE2 is unavailable in standard builds. Use pregexp as the backtracking fallback. If PCRE2 is present, it can be added as a higher-priority backend later.

**Test with `make build` before running tests** — Chez compiles `.sls` to `.so` artifacts. After any `.sls` edit, build must succeed before tests will see changes. If edits seem to have no effect, run `jerboa_stale_static` or delete stale `.so` files: `find lib -name "*.so" -delete && make build`.
