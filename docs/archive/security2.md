# Jerboa Security Hardening — Parser Robustness and Input Safety

Companion to `security.md`. That document covers the security model (capabilities, sandbox, crypto, auth, taint tracking, OS enforcement). This document covers the bug classes that GC doesn't prevent and that `security.md` doesn't address: parser crashes, resource exhaustion, silent data corruption, and input handling defects.

## Implementation Status

| Phase | Status | Details |
|-------|--------|---------|
| Phase 1: Network-Facing Parsers | **DONE** | HTTP/2 frame size cap, WebSocket bounds checks + payload cap, DNS bounds checks + hop limit |
| Phase 2: Data Interchange Parsers | **DONE** | JSON depth + string length limits, Base64 strict validation, Hex odd-length rejection, CSV strict quotes |
| Phase 3: Reader and Core | **DONE** | Reader depth limit, block comment depth limit, schema validation depth, XML/SXML depth limit |
| Phase 4: RegEx and FFI | **DONE** | Pregexp backtracking budget, safe-printf/safe-fprintf/safe-eprintf, zlib decompression limit, YAML input size limit |
| Phase 5: FFI Audit | Not started | Null return checks, type validation, SQL injection lint rule |

All fixes from Phases 1-4 are tested in `tests/test-security2-parsers.ss` (42 tests).

These bugs are exploitable by anyone who can send a malformed network packet, upload a crafted file, or provide unexpected input to an API. They don't require bypassing any security layer — they attack the parsers themselves.

---

## Table of Contents

1. [Design Principle: Parse, Don't Crash](#design-principle-parse-dont-crash)
2. [Unbounded Recursion — Stack Overflow](#unbounded-recursion--stack-overflow)
3. [Unbounded Allocation — Memory Exhaustion](#unbounded-allocation--memory-exhaustion)
4. [Missing Bounds Checks — Bytevector OOB](#missing-bounds-checks--bytevector-oob)
5. [Infinite Loops — CPU Exhaustion](#infinite-loops--cpu-exhaustion)
6. [Silent Data Corruption](#silent-data-corruption)
7. [Format String Injection](#format-string-injection)
8. [ReDoS — Regular Expression Denial of Service](#redos--regular-expression-denial-of-service)
9. [FFI Boundary Safety](#ffi-boundary-safety)
10. [Defensive Parsing Standards](#defensive-parsing-standards)
11. [Implementation Roadmap](#implementation-roadmap)

---

## Design Principle: Parse, Don't Crash

Every parser in Jerboa that accepts external input must satisfy this contract:

1. **Never crash** — no input, no matter how malformed, causes a segfault, stack overflow, or unhandled exception. Every failure path raises a structured condition.
2. **Never hang** — processing any input completes in bounded time proportional to input size. No exponential backtracking, no infinite loops.
3. **Never exhaust memory** — allocation is bounded by a configurable maximum, not by attacker-controlled length fields.
4. **Never silently corrupt** — invalid input is rejected with an error, never silently decoded to wrong output.
5. **Fail closed** — a parser that cannot determine validity rejects the input.

Chez Scheme's GC prevents memory corruption (buffer overflows, use-after-free). But GC does nothing to prevent stack overflow, memory exhaustion, hangs, or logic bugs. Those require explicit defensive coding in every parser.

---

## Unbounded Recursion — Stack Overflow

### The Problem

Seven modules use recursive descent with no depth limit. An attacker can exhaust the Chez Scheme stack with a single crafted input.

| Module | Function | Line(s) | Trigger |
|--------|----------|---------|---------|
| `jerboa/reader` | `read-list` | 227-266 | `((((...` 1000+ deep |
| `jerboa/reader` | `skip-block-comment!` | 117-134 | `#\| #\| #\| ...` 1000+ nested |
| `std/text/json` | `json-read-value` → `json-read-object` | 36-96 | `{"a":{"b":{"c":...}}}` 1000+ deep |
| `std/text/json` | `json-read-value` → `json-read-array` | 36-110 | `[[[[...]]]]` 1000+ deep |
| `std/text/xml` | `write-sxml-node` | 96-175 | SXML tree 1000+ levels deep |
| `std/schema` | `schema-validate` (via `s:list`, `s:hash`, `s:union`) | 96-170 | Nested schema structures |
| `std/net/dns` | `dns-decode-name` | 104-124 | Compression pointer chains (also an infinite loop risk — see below) |

### The Fix: Global Depth Counter

Add a `max-depth` parameter (or thread parameter) that every recursive parser checks before recursing:

```scheme
;; Reader
(define *max-read-depth* (make-parameter 1000))

(define (read-datum port depth)
  (when (> depth (*max-read-depth*))
    (read-error port "maximum nesting depth exceeded"))
  ;; ... existing logic, passing (+ depth 1) to recursive calls
  )
```

```scheme
;; JSON
(define *json-max-depth* (make-parameter 512))

(define (json-read-value port depth)
  (when (> depth (*json-max-depth*))
    (json-error "maximum nesting depth exceeded"))
  (let ([c (json-peek-char port)])
    (cond
      [(char=? c #\{) (json-read-object port (+ depth 1))]
      [(char=? c #\[) (json-read-array port (+ depth 1))]
      ;; ... rest unchanged
      )))
```

**Recommended limits**:

| Parser | Default Max Depth | Rationale |
|--------|------------------|-----------|
| Reader | 1000 | Matches most Scheme implementations; deeply nested code is pathological |
| JSON | 512 | RFC 7159 recommends implementations set limits; 512 covers all real-world JSON |
| XML/SXML | 512 | XML 1.0 has no depth limit but real documents are shallow |
| Schema | 128 | Schemas are structural; 128 levels of nesting is absurd |
| DNS | 32 | RFC 1035 names are max 255 bytes; 32 pointer hops is generous |

### Effort: Small

Each fix is mechanical: add a depth parameter, increment on recursive call, check against max at entry. No architectural change.

---

## Unbounded Allocation — Memory Exhaustion

### The Problem

Several parsers allocate memory based on attacker-controlled values with no upper bound.

| Module | Function | Line(s) | Trigger | Allocation |
|--------|----------|---------|---------|------------|
| `std/net/http2` | `http2-frame-decode` | 92-93 | 3-byte length field in frame header | `make-bytevector` up to 16,777,215 bytes (16MB) |
| `std/net/websocket` | `ws-frame-decode` | 162-168 | 8-byte length field | `make-bytevector` up to 2^63 - 1 bytes |
| `std/text/json` | `json-read-string` | 50-74 | Unlimited string length | List accumulation, then `list->string` |
| `std/text/json` | `json-read-number` | 121-130 | `1e999999999` | Bignum promotion via `string->number` |
| `std/text/csv` | `parse-csv-line` | 37-64 | Unlimited field length | List accumulation |

### The Fix: Allocation Caps

**Network protocol parsers** — reject frames with payload sizes exceeding a configurable maximum:

```scheme
;; HTTP/2
(define *http2-max-frame-size* (make-parameter (* 1 1024 1024)))  ;; 1MB default

(define (http2-frame-decode bv)
  (let ([plen (+ (fxsll (bytevector-u8-ref bv 0) 16)
                 (fxsll (bytevector-u8-ref bv 1) 8)
                 (bytevector-u8-ref bv 2))])
    (when (> plen (*http2-max-frame-size*))
      (error 'http2-frame-decode "frame payload exceeds maximum size"
             plen (*http2-max-frame-size*)))
    ;; ... proceed with allocation
    ))
```

```scheme
;; WebSocket
(define *ws-max-payload-size* (make-parameter (* 16 1024 1024)))  ;; 16MB default

(define (ws-frame-decode bv)
  ;; ... read payload length ...
  (when (> plen (*ws-max-payload-size*))
    (error 'ws-frame-decode "payload exceeds maximum size"
           plen (*ws-max-payload-size*)))
  ;; ... proceed
  )
```

**Text parsers** — limit total input consumption:

```scheme
;; JSON
(define *json-max-string-length* (make-parameter (* 10 1024 1024)))  ;; 10MB default

(define (json-read-string port)
  (let loop ([chars '()] [len 0])
    (when (> len (*json-max-string-length*))
      (json-error "string exceeds maximum length"))
    ;; ... read next char, loop with (+ len 1)
    ))
```

**Recommended limits**:

| Parser | What to Limit | Default | Rationale |
|--------|--------------|---------|-----------|
| HTTP/2 frames | Payload size | 1MB | HTTP/2 spec default is 16KB; 1MB is generous |
| WebSocket frames | Payload size | 16MB | Covers large file transfers; reject >16MB |
| JSON strings | String length | 10MB | No legitimate JSON string is 10MB |
| JSON numbers | Exponent magnitude | 1000 | `1e1000` is already absurd; reject larger |
| CSV fields | Field length | 1MB | CSV fields should be short |
| DNS names | Total name length | 255 bytes | Per RFC 1035 |

### Effort: Small to Medium

Network parsers need a check before `make-bytevector`. Text parsers need a counter in their accumulation loops.

---

## Missing Bounds Checks — Bytevector OOB

### The Problem

Network protocol decoders read from bytevectors at offsets derived from the frame header — without first checking that the bytevector is large enough. Any truncated or malformed frame causes an out-of-bounds exception.

While Chez Scheme does bounds-check `bytevector-u8-ref` (raising `&assertion` rather than reading garbage), the exceptions are unstructured and crash the connection handler instead of producing a clean protocol error.

| Module | Function | Line(s) | Missing Check |
|--------|----------|---------|--------------|
| `std/net/http2` | `http2-frame-decode` | 79-83 | `bv` length >= 9 (frame header) |
| `std/net/http2` | `http2-frame-decode` | 92-93 | `bv` length >= 9 + plen (header + payload) |
| `std/net/websocket` | `ws-frame-decode` | 143-144 | `bv` length >= 2 (minimum frame) |
| `std/net/websocket` | `ws-frame-decode` | 157-158 | `bv` length >= 4 when extended 16-bit length |
| `std/net/websocket` | `ws-frame-decode` | 162-168 | `bv` length >= 10 when extended 64-bit length |
| `std/net/websocket` | `ws-frame-decode` | 173-175 | `bv` length >= data-offset + 4 when masked |
| `std/net/websocket` | `ws-frame-decode` | 179 | `bv` length >= data-offset + plen |
| `std/net/dns` | `dns-decode-response` | 192+ | `bv` length >= 12 (DNS header) |
| `std/net/dns` | `dns-decode-name` | 104-124 | Compression pointer offset < `bv` length |
| `std/net/dns` | answer record decoding | 210-249 | RDLENGTH + offset <= `bv` length |

### The Fix: Validate Before Read

Every bytevector access in a network parser should be preceded by a length check. The pattern:

```scheme
(define (http2-frame-decode bv)
  ;; Check minimum frame header size
  (unless (>= (bytevector-length bv) 9)
    (error 'http2-frame-decode "bytevector too short for frame header"
           (bytevector-length bv)))

  (let* ([plen (+ (fxsll (bytevector-u8-ref bv 0) 16)
                  (fxsll (bytevector-u8-ref bv 1) 8)
                  (bytevector-u8-ref bv 2))]
         [total-needed (+ 9 plen)])

    ;; Check payload fits in bytevector
    (unless (>= (bytevector-length bv) total-needed)
      (error 'http2-frame-decode "bytevector too short for payload"
             (bytevector-length bv) total-needed))

    ;; Now safe to read
    ...))
```

```scheme
(define (ws-frame-decode bv)
  (let ([bvlen (bytevector-length bv)])

    (unless (>= bvlen 2)
      (error 'ws-frame-decode "bytevector too short for frame header"))

    (let* ([b0 (bytevector-u8-ref bv 0)]
           [b1 (bytevector-u8-ref bv 1)]
           [len7 (fxlogand b1 #x7F)]
           [masked? (fxbit-set? b1 7)])

      ;; Determine actual payload length and validate
      (let-values ([(plen header-size)
                    (cond
                      [(< len7 126)
                       (values len7 2)]
                      [(= len7 126)
                       (unless (>= bvlen 4)
                         (error 'ws-frame-decode "too short for 16-bit length"))
                       (values (+ (fxsll (bytevector-u8-ref bv 2) 8)
                                  (bytevector-u8-ref bv 3))
                               4)]
                      [else  ;; 127
                       (unless (>= bvlen 10)
                         (error 'ws-frame-decode "too short for 64-bit length"))
                       ;; ... read 8 bytes ...
                       ])])

        (let ([data-offset (+ header-size (if masked? 4 0))])
          (unless (>= bvlen (+ data-offset plen))
            (error 'ws-frame-decode "bytevector too short for payload"
                   bvlen (+ data-offset plen)))
          ;; Now safe to read
          ...)))))
```

**DNS compression pointer bounds check**:

```scheme
(define (dns-decode-name bv offset)
  (let ([bvlen (bytevector-length bv)])
    (let loop ([pos offset] [labels '()] [compressed? #f] [end-pos #f] [hops 0])
      ;; Prevent compression pointer loops
      (when (> hops 32)
        (error 'dns-decode-name "compression pointer loop detected"))
      (unless (< pos bvlen)
        (error 'dns-decode-name "offset out of bounds" pos bvlen))
      ;; ... existing logic with (+ hops 1) on pointer follow
      )))
```

### Effort: Medium

Each network parser needs a careful audit of every `bytevector-u8-ref` call. The fixes are mechanical but must be thorough — missing even one check leaves a crash path.

---

## Infinite Loops — CPU Exhaustion

### The Problem

Two parsers can be made to loop forever by crafted input.

| Module | Function | Line(s) | Trigger | Mechanism |
|--------|----------|---------|---------|-----------|
| `std/net/dns` | `dns-decode-name` | 113-118 | Compression pointer cycle: offset A → offset B → offset A | No visited-set or hop counter |
| `std/pregexp` | `pregexp-match-positions-aux` | 429-597 | Pathological patterns like `(a+)+b` against `"aaaa...b"` | Exponential backtracking (covered in [ReDoS section](#redos)) |

### The Fix: Hop Limits and Visited Sets

**DNS compression pointers**: Add a hop counter (shown above in bounds check section). 32 hops is more than any legitimate DNS name requires. Additionally, track visited offsets to detect exact cycles:

```scheme
(define (dns-decode-name bv offset)
  (let ([bvlen (bytevector-length bv)]
        [visited (make-hashtable fx= values)])  ;; offset → #t
    (let loop ([pos offset] [labels '()] [compressed? #f] [end-pos #f])
      (when (hashtable-ref visited pos #f)
        (error 'dns-decode-name "compression pointer cycle at offset" pos))
      (hashtable-set! visited pos #t)
      ;; ... existing logic
      )))
```

### Effort: Small

The DNS fix is a single hop counter (3 lines). ReDoS is more complex — see dedicated section below.

---

## Silent Data Corruption

### The Problem

Three parsers accept invalid input without error, producing wrong output.

| Module | Function | Line(s) | Invalid Input | Behavior |
|--------|----------|---------|--------------|----------|
| `std/text/base64` | `base64-string->u8vector` | 55-98 | Characters not in base64 alphabet (e.g., `@`, `#`, `!`) | Decode table returns -1; -1 is used in bitwise operations, producing garbage bytes |
| `std/text/base64` | `base64-string->u8vector` | 55-98 | Malformed padding (`====`, `=` in middle) | Padding stripped without position validation |
| `std/text/csv` | `parse-csv-line` | 48-49 | Unterminated quoted field (`"hello`) | Silently accepts the field without the closing quote |
| `std/text/hex` | `hex-decode` | 37-47 | Odd-length input (`"abc"`) | Last character silently dropped |

### The Fix: Validate and Reject

**Base64** — check every decoded value:

```scheme
(define (base64-decode-char c)
  (let ([val (vector-ref *base64-decode-table* (char->integer c))])
    (when (= val -1)
      (error 'base64-decode "invalid base64 character" c))
    val))
```

Also validate padding:
- `=` may only appear at positions `n-1` and `n-2` of the input
- After stripping whitespace, length must be divisible by 4

**CSV** — error on unterminated quotes:

```scheme
;; In parse-csv-line, when j >= len inside a quoted field:
((>= j len)
 (error 'parse-csv-line "unterminated quoted field"))
```

Or, for fault-tolerant parsing, provide both behaviors behind a parameter:

```scheme
(define *csv-strict-quotes* (make-parameter #t))

((>= j len)
 (if (*csv-strict-quotes*)
   (error 'parse-csv-line "unterminated quoted field")
   (reverse (cons (list->string (reverse chars)) fields))))
```

**Hex** — reject odd-length input:

```scheme
(define (hex-decode s)
  (unless (even? (string-length s))
    (error 'hex-decode "odd-length hex string" (string-length s)))
  ;; ... existing logic
  )
```

### Effort: Small

Each fix is 2-5 lines. The base64 fix is the most important since silent corruption is worse than a crash — the caller has no way to know the output is wrong.

---

## Format String Injection

### The Problem

`lib/std/format.sls` (lines 10-19) exports `printf`, `fprintf`, and `eprintf` as thin wrappers around Chez's `format`. If user-controlled data is passed as the format string (first argument), format directives like `~a`, `~s`, `~%` are interpreted.

```scheme
;; VULNERABLE: user-input is the format string
(printf user-input)

;; SAFE: user-input is an argument to a fixed format string
(printf "User said: ~a\n" user-input)
```

In Chez Scheme, `format` with more directives than arguments raises an exception rather than reading memory (unlike C's `printf`). So this is not a memory safety issue, but it is:

- **An information disclosure risk** if `~s` dumps an internal object
- **A crash vector** if the format string has more directives than arguments
- **A log injection vector** if `~%` injects newlines into structured log output

### The Fix: Safe Formatting Functions

Add `safe-printf` variants that treat the first argument as a literal (no directive processing):

```scheme
;; Safe: always treats message as literal text
(define (safe-printf msg . args)
  (display msg)
  (for-each display args))

;; Or: escape tildes in the message before passing to format
(define (safe-format port msg . args)
  (let ([escaped (string-replace-all msg "~" "~~")])
    (apply format port escaped args)))
```

Also: add a lint rule to flag `(printf <variable>)` where the first argument is not a string literal.

### Effort: Small

The safe functions are trivial. The lint rule is the higher-value fix — it catches the pattern at development time.

---

## ReDoS — Regular Expression Denial of Service

### The Problem

`lib/std/pregexp.sls` implements a backtracking regex engine (continuation-passing style, lines 429-597). The `:between` quantifier (lines 556-592) has no backtracking budget. Pathological patterns cause exponential CPU consumption:

| Pattern | Input | Time Complexity |
|---------|-------|----------------|
| `(a+)+$` | `"aaa...ab"` (n a's) | O(2^n) |
| `(a\|a)*$` | `"aaa...ab"` (n a's) | O(2^n) |
| `(.+)*$` | `"aaa...ab"` (n a's) | O(2^n) |
| `(a*)*$` | `"aaa...ab"` (n a's) | O(2^n) |

With n=30, these take seconds. With n=50, they take years.

### The Fix: Backtracking Budget

Add a step counter to the matching engine that limits total backtracking steps:

```scheme
(define *pregexp-max-steps* (make-parameter 1000000))

;; Inside the matching engine, decrement a step counter on every
;; recursive call. When it reaches zero, the match fails (not errors —
;; treating it as "no match" is safer than crashing).

(define (pregexp-match-positions-aux pattern input start end)
  (let ([steps (box (*pregexp-max-steps*))])
    (define (tick!)
      (let ([n (unbox steps)])
        (when (<= n 0)
          (error 'pregexp-match "backtracking limit exceeded"))
        (set-box! steps (- n 1))))
    ;; Pass tick! into the matching engine; call it on every branch point
    ...))
```

**Alternative**: Use PCRE2 (which Jerboa already wraps via `std/pcre2`) for untrusted patterns. PCRE2 has JIT compilation and built-in match limits. Reserve pregexp for trusted patterns only.

**Recommended policy**:

```scheme
;; For untrusted patterns (user-provided regex):
(pcre2-match pattern input)  ;; uses PCRE2 with JIT and match limits

;; For trusted patterns (hardcoded in source):
(pregexp-match pattern input)  ;; pregexp is fine for known-safe patterns
```

### Effort: Medium

Adding a step counter to pregexp requires threading it through the continuation-passing matcher — not trivial but not a rewrite. The PCRE2 policy change is zero code, just documentation and convention.

---

## FFI Boundary Safety

### The Problem

GC protects pure Scheme code. FFI calls cross into C where anything can happen. Jerboa wraps 11 external C libraries:

| Library | Module | Risk |
|---------|--------|------|
| libyaml | `std/text/yaml` | C parser — all YAML parsing bugs apply |
| libsqlite3 | `std/db/sqlite` | SQL injection if queries aren't parameterized |
| libpq | `std/db/postgresql` | Same |
| libssl | `std/net/ssl` | TLS implementation bugs |
| libcrypto | `std/crypto/*` | Covered by security.md V1/C1 |
| libpcre2 | `std/pcre2` | Regex engine bugs in C |
| libz | `std/compress/zlib` | Decompression bombs |
| libleveldb | `std/db/leveldb` | Key/value store corruption |
| libepoll | `std/os/epoll` | File descriptor management |
| libinotify | `std/os/inotify` | File watching |
| landlock-shim.c | `support/` | Syscall interface |

### What's Not Covered by security.md

Security.md addresses crypto FFI (C1) and process execution (V6). It does not address:

1. **YAML decompression/parsing bugs** — libyaml has had CVEs (e.g., CVE-2014-9130, CVE-2018-20573). Jerboa passes user input directly through.

2. **Zlib decompression bombs** — a 45-byte gzip file can expand to 4.5 petabytes. No decompression size limit is visible.

3. **SQLite/PostgreSQL query safety** — the modules provide both raw `exec` (vulnerable) and parameterized `query` (safe), but nothing prevents callers from using the unsafe path.

4. **Null pointer dereference in C** — if a C function returns NULL (allocation failure, not found), the Scheme wrapper may pass it to another C function that dereferences it.

5. **Type confusion at FFI boundary** — Chez's `foreign-procedure` does minimal type checking. Passing a string where C expects an integer, or a bytevector where C expects a pointer, can corrupt memory.

### The Fix: Defensive FFI Wrappers

**Principle**: Every FFI wrapper should validate inputs on the Scheme side before calling C, and validate outputs from C before returning to Scheme.

```scheme
;; Example: safe SQLite wrapper
(define (sqlite-safe-query db sql params)
  ;; Validate types on Scheme side
  (assert (sqlite-db? db))
  (assert (string? sql))
  (assert (list? params))
  ;; Use parameterized query — never string interpolation
  (sqlite-prepare-and-bind db sql params))

;; Example: zlib with decompression limit
(define *zlib-max-decompressed-size* (make-parameter (* 100 1024 1024)))  ;; 100MB

(define (safe-inflate input)
  (let ([result (zlib-inflate input)])
    (when (> (bytevector-length result) (*zlib-max-decompressed-size*))
      (error 'safe-inflate "decompressed size exceeds limit"))
    result))
```

**Lint rule**: Flag any use of `sqlite-exec` or `postgresql-exec` with string interpolation (format, string-append) in the SQL argument.

### Effort: Medium to Large

Auditing all 11 FFI wrappers and adding defensive checks is substantial but important. Priority: YAML (most complex C parser), zlib (decompression bombs), SQLite/PostgreSQL (injection).

---

## Defensive Parsing Standards

All parsers in Jerboa should adhere to these standards. New parsers must satisfy them before merge; existing parsers should be retrofitted per the roadmap below.

### Standard 1: Depth Limits

Every recursive-descent parser must accept a `max-depth` parameter (or use a thread parameter). Default values per parser type:

| Parser Type | Default Max Depth |
|-------------|------------------|
| Source code (reader) | 1000 |
| Data interchange (JSON, XML, YAML) | 512 |
| Schema/validation | 128 |
| Network protocols (DNS, HTTP/2) | 32 |

### Standard 2: Size Limits

Every parser must have configurable limits on:
- **Total input size** — reject before parsing starts
- **Individual element size** — strings, fields, labels
- **Output allocation size** — based on validated input, not raw length fields

### Standard 3: Bounds Checking

Every `bytevector-u8-ref` in a network protocol parser must be preceded by a length check against the bytevector's actual size. No exceptions.

### Standard 4: Strict by Default

Parsers must reject invalid input by default. A `strict: #f` or `permissive: #t` parameter may be provided for fault-tolerant parsing, but the default is strict.

| Parser | Strict Behavior | Permissive Behavior |
|--------|----------------|-------------------|
| Base64 | Error on non-alphabet characters | Skip invalid characters (current behavior — wrong) |
| CSV | Error on unterminated quotes | Accept truncated field (current behavior — wrong) |
| Hex | Error on odd-length input | Pad with zero (explicit) |
| JSON | Error on trailing content | Ignore trailing bytes |

### Standard 5: Structured Error Conditions

Every parser must raise a specific condition type, not generic `error`:

```scheme
;; Define per-parser condition types
(define-condition-type &json-parse-error &condition
  make-json-parse-error json-parse-error?
  (line json-parse-error-line)
  (column json-parse-error-column)
  (message json-parse-error-message))

(define-condition-type &http2-frame-error &condition
  make-http2-frame-error http2-frame-error?
  (frame-type http2-frame-error-type)
  (message http2-frame-error-message))

(define-condition-type &dns-parse-error &condition
  make-dns-parse-error dns-parse-error?
  (offset dns-parse-error-offset)
  (message dns-parse-error-message))
```

This allows callers to handle parse errors distinctly from other exceptions, and prevents internal details from leaking through generic error messages.

### Standard 6: Timeout Integration

Parsers invoked on network input should support a timeout parameter or cooperate with Jerboa's structured concurrency (`with-task-scope` + cancellation):

```scheme
;; Pattern: parse with timeout
(with-time-limit 5000  ;; milliseconds
  (read-json network-port))
```

This is defense-in-depth against any hang that escapes the other limits.

---

## Implementation Roadmap

### Phase 1: Critical — Network-Facing Parsers — DONE

These are directly exposed to attacker-controlled input over the network.

| Task | Module | Fix | Status |
|------|--------|-----|--------|
| Bytevector bounds checks | `std/net/http2` | Validate bv length before every read | **FIXED** |
| Bytevector bounds checks | `std/net/websocket` | Validate bv length before every read | **FIXED** |
| Bytevector bounds checks + hop limit | `std/net/dns` | Bounds checks + 32-hop limit on compression pointers | **FIXED** |
| Allocation caps | `std/net/http2` | Max frame payload size parameter (`*http2-max-frame-size*`) | **FIXED** |
| Allocation caps | `std/net/websocket` | Max payload size parameter (`*ws-max-payload-size*`) | **FIXED** |
| Structured error conditions | All three network parsers | Define condition types, replace `error` calls | Deferred |

### Phase 2: High — Data Interchange Parsers — DONE

These process files and API responses that may contain attacker-controlled content.

| Task | Module | Fix | Status |
|------|--------|-----|--------|
| Recursion depth limit | `std/text/json` | `*json-max-depth*` parameter (default 512) | **FIXED** |
| Max string size | `std/text/json` | `*json-max-string-length*` parameter (default 10MB) | **FIXED** |
| Base64 strict validation | `std/text/base64` | Error on invalid characters and malformed padding | **FIXED** |
| Hex strict validation | `std/text/hex` | Error on odd-length input | **FIXED** |
| CSV strict quotes | `std/text/csv` | `*csv-strict-quotes*` + `*csv-max-field-length*` parameters | **FIXED** |
| Structured error conditions | All text parsers | Condition types per parser | Deferred |

### Phase 3: High — Reader and Core — DONE

The reader affects the REPL, compiler, and `eval`. Lower priority than network parsers because the reader typically processes trusted source code, but a compromised dependency or plugin changes that assumption.

| Task | Module | Fix | Status |
|------|--------|-----|--------|
| Recursion depth limit | `jerboa/reader` | `*max-read-depth*` parameter (default 1000) via `case-lambda` dispatch | **FIXED** |
| Block comment depth limit | `jerboa/reader` | `*max-block-comment-depth*` parameter (default 1000) | **FIXED** |
| Schema validation depth | `std/schema` | `*schema-max-depth*` parameter (default 128) | **FIXED** |
| XML/SXML depth limit | `std/text/xml` | `*sxml-max-depth*` parameter (default 512) | **FIXED** |

### Phase 4: Medium — RegEx and FFI — DONE

| Task | Module | Fix | Status |
|------|--------|-----|--------|
| Backtracking budget | `std/pregexp` | `*pregexp-max-steps*` parameter (default 1M), step counter via mutable box | **FIXED** |
| Safe format functions | `std/format` | `safe-printf`, `safe-fprintf`, `safe-eprintf` (literal text, no directives) | **FIXED** |
| Zlib decompression limit | `std/compress/zlib` | `safe-gunzip-bytevector`, `safe-inflate-bytevector` with `*zlib-max-decompressed-size*` (100MB) | **FIXED** |
| YAML input size limit | `std/text/yaml` | `safe-yaml-load-string` with `*yaml-max-input-size*` (10MB) | **FIXED** |
| ReDoS policy documentation | All | Document: use PCRE2 for untrusted patterns | Deferred |
| Format string lint rule | `std/format` | Flag `(printf <variable>)` in linter | Deferred |

### Phase 5: Ongoing — FFI Audit

| Task | Module | Fix | Effort |
|------|--------|-----|--------|
| Null return checks | All FFI wrappers | Check C return values before use | 2 days |
| Type validation | All FFI wrappers | Assert Scheme types before `foreign-procedure` calls | 2 days |
| SQL injection lint rule | `std/db/sqlite`, `std/db/postgresql` | Flag string interpolation in SQL arguments | 1 day |

---

## Summary

| Category | # of Bugs to Fix | Severity | Covered by security.md? |
|----------|-----------------|----------|------------------------|
| Unbounded recursion | 7 locations | High | No |
| Unbounded allocation | 5 locations | High | No |
| Missing bounds checks | 10+ locations | High | No |
| Infinite loops | 2 locations | High | No |
| Silent data corruption | 4 locations | Medium | No |
| Format string injection | 1 pattern | Medium | No |
| ReDoS | 1 engine | High | No |
| FFI boundary gaps | 11 libraries | Medium-High | Partially (crypto only) |

Total: ~30 specific fixes across 5 phases. The first two phases (network + data parsers) cover the highest-risk surface and can be completed in 2-3 weeks. Every fix is backward-compatible — adding limits and validation never breaks correct callers.
