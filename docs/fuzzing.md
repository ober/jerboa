# Jerboa Fuzzing Strategy

A comprehensive plan for discovering crashes, hangs, memory exhaustion, and logic bugs across Jerboa's parsing, networking, and security surfaces.

---

## Table of Contents

1. [What Fuzzing Finds](#what-fuzzing-finds)
2. [Fuzzing Architecture for Chez Scheme](#fuzzing-architecture-for-chez-scheme)
3. [Target Inventory](#target-inventory)
4. [Target Details](#target-details)
5. [Seed Corpus Strategy](#seed-corpus-strategy)
6. [Harness Design](#harness-design)
7. [Bug Oracles](#bug-oracles)
8. [Infrastructure](#infrastructure)
9. [Triage and Regression](#triage-and-regression)
10. [Implementation Roadmap](#implementation-roadmap)

---

## What Fuzzing Finds

Fuzzing is uniquely effective at finding bugs that humans and code review miss — the weird corner cases that only emerge from millions of random inputs. In Jerboa specifically, fuzzing targets these bug classes:

### Crashes and Unhandled Exceptions

| Bug Class | Where It Hides in Jerboa | Example |
|-----------|--------------------------|---------|
| **Stack overflow from unbounded recursion** | Reader (nested lists/comments), JSON (nested objects/arrays), DNS (compression pointer loops) | `((((((((...1000 deep...))))))))` overflows the Chez stack |
| **Bytevector out-of-bounds** | HTTP/2 frame decode, WebSocket frame decode, DNS response parsing | Frame header says 100 bytes of payload but only 50 bytes exist |
| **Invalid character conversions** | JSON `\uXXXX` escapes, UTF-8 decoder, Hex decoder | `\uDEAD` (lone surrogate) crashes `integer->char` |
| **Assertion failures in parsing state machines** | Reader hash dispatch, CSV quote handling, regex compilation | `#u8(not-a-number)` hits an unguarded branch |
| **Division by zero / arithmetic errors** | Format string processing, HTTP/2 HPACK integer decoding | Format directive with zero-width field |

### Denial of Service (Hangs and Resource Exhaustion)

| Bug Class | Where It Hides in Jerboa | Example |
|-----------|--------------------------|---------|
| **Infinite loops** | DNS compression pointers (cycle), regex backtracking (ReDoS), reader block comments | DNS name at offset X with compression pointer back to X |
| **Memory exhaustion via allocation** | HTTP/2 frame with 16MB length field, WebSocket with 2^63 payload length, JSON with million-element arrays | `ws-frame-decode` reads 8-byte length, calls `make-bytevector` with 2^63 |
| **CPU exhaustion via backtracking** | Pregexp engine on pathological patterns, deeply nested schema validation | `(a+)+$` matched against `"aaaaaaaaaaaaaaaaaaaab"` |
| **File descriptor / resource leaks** | Parsers that open ports but don't close on malformed input | `read-json` on a port where the first byte is invalid — does the port get closed? |

### Logic Bugs and Silent Data Corruption

| Bug Class | Where It Hides in Jerboa | Example |
|-----------|--------------------------|---------|
| **Silent wrong output** | Base64 decoder accepting invalid characters (returns -1, used as value), hex decoder silently dropping odd final byte | `base64-decode "aGVsbG8@@@"` produces garbage instead of raising an error |
| **Truncated parse without error** | CSV parser dropping the last field when quote is unterminated, JSON accepting trailing garbage | `{"a":1}GARBAGE` parses as `{"a":1}` — no error |
| **Type confusion at boundaries** | FFI layer accepting wrong Scheme types, config system accepting non-string keys | `sqlite-exec` with a bytevector where a string is expected |
| **Differential bugs** | Reader producing different ASTs than Gerbil's reader for the same input | `#;(foo) bar` — does Jerboa handle datum comments identically to Gerbil? |

### Security-Specific Bugs

| Bug Class | Where It Hides in Jerboa | Example |
|-----------|--------------------------|---------|
| **Sandbox escape** | `restricted-eval` with crafted syntax objects, continuation capture across sandbox boundary | `(call/cc (lambda (k) k))` captured inside sandbox, invoked outside |
| **Capability forgery** | Currently vectors — any code can construct one (V2 in security.md) | `(vector 'capability 999 'filesystem '((read . #t)))` |
| **Injection via format strings** | `format` called with user-controlled first argument | User input containing `~a` or `~s` directives |
| **Path traversal** | Router parameter extraction, config file paths, sanitize-path edge cases | `:id` param set to `../../etc/passwd` |
| **Integer overflow in size calculations** | HTTP/2 payload length, WebSocket frame length, buffer allocation | Length fields that overflow fixnum range |

---

## Existing Hardening

Before fuzzing, it's important to know what defenses already exist. These limits are parameterized and can be tested by fuzzing with both default and extreme values.

| Module | Defense | Parameter | Default |
|--------|---------|-----------|---------|
| `jerboa/reader` | Read depth limit | `*max-read-depth*` | 1000 |
| `jerboa/reader` | Block comment nesting limit | `*max-block-comment-depth*` | 1000 |
| `std/text/json` | JSON nesting depth limit | `*json-max-depth*` | 512 |
| `std/text/json` | Max string length | `*json-max-string-length*` | 10MB |
| `std/net/http2` | Max frame payload size | `*http2-max-frame-size*` | 1MB |
| `std/net/websocket` | Max payload size | `*ws-max-payload-size*` | 16MB |
| `std/net/dns` | Compression pointer hop limit | hardcoded | 32 hops |
| `std/text/csv` | Max field length | `*csv-max-field-length*` | 1MB |
| `std/security/restrict` | Allowlist-only bindings | `safe-bindings` | ~113 bindings |
| `std/format` | Safe format variants | `safe-printf` / `safe-fprintf` | N/A |

Fuzzing should test both the happy path (limits hold) and the bypass path (can the limit be circumvented?).

---

## Fuzzing Architecture for Chez Scheme

Chez Scheme is garbage-collected and memory-safe in pure Scheme code, so traditional C fuzzing tools (AFL, libFuzzer) don't directly apply. We need a hybrid approach.

### Approach 1: Scheme-Level Property-Based Fuzzing (Primary)

Write Scheme harnesses that generate random inputs and feed them to parsing functions. This catches the majority of bugs: unhandled exceptions, infinite loops, memory bombs, and logic errors.

**Important**: Chez Scheme does not have a built-in `with-time-limit`. We implement timeout detection using `(engine)` — Chez's preemptive evaluation mechanism that counts "ticks" (reductions). This catches infinite loops and excessive computation but measures work done, not wall-clock time.

```scheme
;; Generic fuzzing harness pattern
;; Uses Chez Scheme's engine mechanism for timeout detection
(import (jerboa prelude)
        (std test))

(define (fuzz-with-timeout thunk fuel)
  ;; Returns: 'ok, 'timeout, or 'exception
  ;; fuel = approximate number of reductions before timeout
  (let ([eng (make-engine thunk)])
    (eng fuel
      (lambda (remaining result) 'ok)        ;; completed
      (lambda (new-engine) 'timeout))))       ;; ran out of fuel

(define (fuzz-target parse-fn input-generator iterations)
  (let loop ([i 0])
    (when (< i iterations)
      (let ([input (input-generator)])
        (guard (exn [#t (void)])  ;; any exception is OK — crashes are not
          (fuzz-with-timeout
            (lambda () (parse-fn input))
            1000000))  ;; ~1M reductions ≈ a few seconds
        (loop (+ i 1))))))
```

**Generators needed:**
- Random bytevectors (uniform random bytes)
- Mutated valid inputs (bit flips, byte insertions/deletions, boundary values)
- Grammar-based generators (structurally valid but semantically broken)

### Approach 2: C-Level Fuzzing for FFI Code (Secondary)

For modules that call C via FFI (YAML via libyaml, crypto via libcrypto, SQLite, PCRE2), fuzz the C functions directly using AFL++ or libFuzzer with the C shared libraries.

```c
// Example: fuzz libyaml through chez-yaml's entry point
#include <yaml.h>
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    yaml_parser_t parser;
    yaml_event_t event;
    yaml_parser_initialize(&parser);
    yaml_parser_set_input_string(&parser, data, size);
    while (yaml_parser_parse(&parser, &event)) {
        yaml_event_delete(&event);
        if (event.type == YAML_STREAM_END_EVENT) break;
    }
    yaml_parser_delete(&parser);
    return 0;
}
```

### Approach 3: Differential Fuzzing (Targeted)

Compare Jerboa's output against Gerbil's output for the same input. Any divergence is a bug in one or both.

```scheme
;; Compare reader output
(let ([input (generate-random-sexp-string)])
  (let ([jerboa-result (guard (e [#t 'error]) (jerboa-read-string input))]
        [gerbil-result (guard (e [#t 'error]) (gerbil-read-string input))])  ;; via subprocess
    (unless (equal? jerboa-result gerbil-result)
      (report-differential-bug input jerboa-result gerbil-result))))
```

---

## Target Inventory

Targets ordered by priority — a product of attack surface exposure and bug likelihood.

| Priority | Module | Entry Point | Input Source | Bug Types Expected |
|----------|--------|-------------|-------------|-------------------|
| **P0** | `jerboa/reader` | `jerboa-read`, `jerboa-read-string` | Source files, REPL, `eval` | Stack overflow, hangs, wrong AST |
| **P0** | `std/text/json` | `read-json`, `string->json-object` | HTTP bodies, config files, APIs | Stack overflow, memory, invalid Unicode |
| **P0** | `std/net/http2` | `http2-frame-decode` | Network (untrusted) | Memory exhaustion, OOB, frame confusion |
| **P0** | `std/net/websocket` | `ws-frame-decode` | Network (untrusted) | Memory exhaustion, OOB |
| **P0** | `std/net/dns` | `dns-decode-response` | Network (untrusted) | Infinite loop, OOB, truncation |
| **P1** | `std/pregexp` | `pregexp`, `pregexp-match` | User-provided patterns | ReDoS, stack overflow, invalid escapes |
| **P1** | `std/text/csv` | `read-csv`, `parse-csv-line` | Uploaded files | Unterminated quotes, field explosion |
| **P1** | `std/text/base64` | `base64-decode` | HTTP headers, encoded payloads | Silent wrong output, malformed padding |
| **P1** | `std/text/xml` | `xml-read`, `sxml-parse` | API responses, config | XXE (if entity expansion), recursion |
| **P1** | `std/security/restrict` | `restricted-eval`, `restricted-eval-string` | User-submitted code | Sandbox escape |
| **P2** | `std/text/hex` | `hex-decode` | Encoded data | Odd-length, invalid chars |
| **P2** | `std/text/yaml` | `yaml-load`, `yaml-load-string` | Config files | C library bugs, billion laughs |
| **P2** | `std/format` | `format` | User-controlled format strings | Format injection, arity mismatch |
| **P2** | `std/net/router` | `router-match`, `parse-pattern` | HTTP request paths | Path traversal, segment explosion |
| **P2** | `std/schema` | `validate` | Untrusted input shapes | Recursion bomb, type confusion |
| **P2** | `std/net/uri` | `uri-parse`, `uri-decode` | HTTP requests, redirects | Malformed URLs, injection, encoding |
| **P2** | `std/text/ini` | INI parsing | Config files | Nesting, unterminated values |
| **P2** | `std/text/json-schema` | `validate` | Untrusted input shapes | Recursion bomb, type confusion |
| **P2** | `std/config` | `load-config`, `ht-path-get` | Config files | Nesting bomb, env injection |
| **P3** | `std/text/utf8` | `utf8-decode` | Any text processing | Invalid sequences, bounds |
| **P3** | `std/crypto/digest` | `md5`, `sha256` | Any data | Shell injection (V1 — pre-fix) |
| **P3** | `std/db/sqlite` | `sqlite-exec`, `sqlite-query` | User queries | SQL injection (if not parameterized) |
| **P3** | `std/actor/transport` | message deserialization | Network (inter-node) | Forgery, replay, type confusion |
| **P3** | `jerbuild.ss` | compiler pipeline | Malicious `.ss` files | Compiler crash, infinite expansion |

---

## Target Details

### T1. Gerbil Reader — `jerboa/reader.sls`

**Why it's P0**: The reader processes every piece of Scheme source code. If it crashes on malformed input, it affects the REPL, the compiler, `eval`, and any system that reads user-provided S-expressions.

**Attack surface**:
- `jerboa-read-string` — primary entry for string input
- `jerboa-read` — port-based, used by file loading
- `jerboa-read-all` — reads multiple forms (loops over `jerboa-read`)

**Specific fuzz vectors**:

| Vector | What It Tests | Expected Bug |
|--------|--------------|-------------|
| `((((...1000+...))))` | Nested list recursion depth in `read-list` | Stack overflow — no depth limit |
| `#\| #\| #\| ... #\| nested 1000+ ... \|# \|# \|#` | Block comment nesting in `skip-block-comment!` | Stack overflow |
| `#u8(not numbers here)` | Hash dispatch for bytevector literals | Unhandled parse error |
| `"unterminated string` | EOF inside string literal | Graceful error vs crash |
| `[{(]})` | Mismatched delimiters | Delimiter tracking correctness |
| `#;#;#;#;(((form)))` | Datum comment chaining | Correct skip behavior |
| `#!eof #!void #!bwp` | Chez-specific hash-bang tokens | Handled or rejected cleanly |
| `1/0`, `+nan.0`, `+inf.0` | Special numeric literals | Parsed correctly |
| `\x0;\x1;\x7f;` in identifiers | Control characters | Reader behavior |
| `:keyword`, `key:` | Gerbil keyword syntax | Correct keyword/symbol distinction |
| `"""heredoc\n...\n"""` | Heredoc string syntax | Delimiter matching, EOF handling |

**Oracle**: Compare against `(read (open-input-string input))` from Chez and against Gerbil's reader for differential testing.

### T2. JSON Parser — `std/text/json.sls`

**Why it's P0**: JSON is the primary data interchange format. Any server accepting JSON from the network will hit this parser with untrusted input.

**Specific fuzz vectors**:

| Vector | What It Tests | Expected Bug |
|--------|--------------|-------------|
| `{"a":{"b":{"c":...}}}` 10000 deep | Object recursion | Stack overflow |
| `[[[[...]]]]` 10000 deep | Array recursion | Stack overflow |
| `"\uD800"` | Lone high surrogate | `integer->char` crash |
| `"\uDFFF"` | Lone low surrogate | `integer->char` crash |
| `"\uD800\uDC00"` | Surrogate pair | Correct UTF-16 decoding? |
| `1e999999999` | Number overflow | Bignum or inf? |
| `0.0000...0001` (1000 zeros) | Precision exhaustion | Hang or memory |
| `{"a":1}{"b":2}` | Multiple root values | Trailing garbage accepted? |
| `[1,2,3,]` | Trailing comma | Error or silent accept |
| `"\/"`, `"\b"`, `"\f"` | All JSON escapes | Correct character |
| `"\u0000"` | Null byte in string | Embedded NUL handling |
| 100MB string value | Memory | Allocation limit |

**Oracle**: Compare output against Python's `json.loads()` or jq. Any parse success/failure disagreement is a bug.

### T3. HTTP/2 Frame Decoder — `std/net/http2.sls`

**Why it's P0**: HTTP/2 frames come directly from the network. An attacker controls every byte.

**Specific fuzz vectors**:

| Vector | What It Tests | Expected Bug |
|--------|--------------|-------------|
| Bytevector < 9 bytes | Minimum frame header size | OOB `bytevector-u8-ref` |
| Length field = 0xFFFFFF (16MB) | Max payload allocation | Memory exhaustion |
| Length field > actual bytes | Payload/header mismatch | OOB read or short read |
| Frame type = 0xFF | Unknown frame type | Silent accept or clean error |
| Stream ID with reserved bit set | Bit 0 of stream ID | Masking correctness |
| HPACK index > 61 | Static table bounds | OOB in static table lookup |
| HPACK integer overflow | Multi-byte integer encoding | Arithmetic overflow |
| CONTINUATION frame without HEADERS | Frame sequencing | State machine correctness |
| SETTINGS frame with unknown IDs | Settings parsing | Ignored or crash |
| DATA frame with PADDED flag + pad length > payload | Padding arithmetic | Negative/underflow |

### T4. WebSocket Frame Decoder — `std/net/websocket.sls`

**Specific fuzz vectors**:

| Vector | What It Tests | Expected Bug |
|--------|--------------|-------------|
| Bytevector of 0 bytes | Minimum size | OOB |
| Bytevector of 1 byte | Only FIN/opcode, no length | OOB on length byte |
| Length = 126, bytevector = 3 bytes | Extended 16-bit length undersize | OOB |
| Length = 127, bytevector = 5 bytes | Extended 64-bit length undersize | OOB |
| 64-bit length = 2^63 - 1 | Maximum payload | Memory exhaustion |
| 64-bit length = 2^63 (MSB set) | Negative length in signed interpretation | Signedness bug |
| Mask bit set, data too short for mask key | Mask key read | OOB |
| Mask XOR with payload shorter than claimed | Unmasking loop | OOB |
| RSV bits set | Reserved extension bits | Ignored or error |

### T5. DNS Wire Format Parser — `std/net/dns.sls`

**Specific fuzz vectors**:

| Vector | What It Tests | Expected Bug |
|--------|--------------|-------------|
| Bytevector < 12 bytes | Minimum DNS header | OOB |
| Compression pointer to self | `offset → offset` | Infinite loop |
| Compression pointer cycle | `A → B → A` | Infinite loop |
| Compression pointer past end of message | Out-of-bounds offset | OOB |
| Label length = 255 (max) | Name length limit | Allocation |
| QDCOUNT = 65535, no question data | Count/data mismatch | OOB or hang |
| A record with RDLENGTH = 3 (needs 4) | Short record data | OOB |
| AAAA record with RDLENGTH = 0 | Zero-length IPv6 | OOB |
| TXT record with length > RDLENGTH | Internal length mismatch | OOB |
| All-zero message | Minimal valid? | Behavior check |

### T6. Regex Engine — `std/pregexp.sls`

**Specific fuzz vectors**:

| Vector | What It Tests | Expected Bug |
|--------|--------------|-------------|
| `(a+)+$` vs `"aaa...ab"` | Catastrophic backtracking (ReDoS) | CPU exhaustion |
| `(a\|a)*$` vs `"aaa...ab"` | Exponential matching | CPU exhaustion |
| `(.+)*$` | Nested quantifiers | CPU exhaustion |
| `[[:nonexistent:]]` | Invalid POSIX class | Error handling |
| `\99` | Non-existent backreference | OOB or error |
| `(?:` (unterminated) | Incomplete group | Error handling |
| 100KB pattern string | Pattern compilation | Memory/time |
| `[^]` | Empty negated class | Behavior |
| `\p{Lu}` | Unicode property (if supported) | Feature support |

### T7. URI Parser — `std/net/uri.sls`

**Why it's P2**: The URI parser processes every HTTP request URL and redirect target. Malformed URIs can cause incorrect routing or injection.

**Specific fuzz vectors**:

| Vector | What It Tests | Expected Bug |
|--------|--------------|-------------|
| `://` (no scheme) | Minimal URI | Graceful error |
| `http://user:pass@host:99999/path?q=v#f` | Full URI | Correct parsing |
| `http://[::1]:8080/` | IPv6 host | Bracket handling |
| `http://host/../../etc/passwd` | Path traversal | Normalization |
| `http://host/path?a=1&a=2&a=3...x10000` | Query explosion | Memory |
| `%ZZ` in path/query | Invalid percent-encoding | Error vs silent |
| `%00` null byte | Embedded NUL | Truncation bug |
| `http://host\@evil.com/` | Backslash in authority | Parser confusion |
| Empty string | Zero-length input | Graceful error |
| 1MB URL | Large input | Memory/hang |

**Oracle**: Roundtrip — `uri->string(uri-parse(input))` should be semantically equivalent for valid URIs.

### T8. Sandbox — `std/security/restrict.sls`

**Specific fuzz vectors**:

| Vector | What It Tests | Expected Bug |
|--------|--------------|-------------|
| `(eval '(open-input-file "/etc/passwd"))` | Blocked binding access | Escape |
| `(call/cc (lambda (k) k))` | Continuation capture | Escape via continuation |
| `(interaction-environment)` | Environment access | Escape to full env |
| `(compile '(system "id"))` | Compile + eval | Bypass via compilation |
| `(record-type-descriptor ...)` | RTD access | Internal access |
| `(with-exception-handler ...)` chains | Exception handler manipulation | Control flow escape |
| `(parameterize ...)` with internal params | Parameter mutation | State escape |
| `(define-syntax ...)` with `syntax-case` | Macro that references blocked bindings | Indirect access |
| `(load "malicious.ss")` | File loading | Should be blocked |
| `(foreign-procedure ...)` | Direct FFI | Should be blocked |

---

## Seed Corpus Strategy

Every fuzzer is only as good as its starting corpus. For each target:

### Reader
- All files in `tests/` — valid Gerbil source
- Gerbil's own test suite reader tests
- Edge case files: empty, single character, BOM, all-whitespace
- Files from popular Gerbil projects

### JSON
- RFC 8259 test vectors
- JSONTestSuite (github.com/nst/JSONTestSuite — 300+ edge cases)
- Valid JSON from real APIs (GitHub, etc.)
- json.org examples

### Network Protocols (HTTP/2, WebSocket, DNS)
- Captured pcap data decoded to raw frames
- RFC test vectors where available
- Wireshark-generated malformed frames
- h2spec test frames for HTTP/2

### Regex
- Patterns from real codebases
- ReDoS pattern databases (e.g., from snyk advisory DB)
- POSIX regex test suites

### Sandbox
- Known Chez Scheme sandbox escape techniques
- CTF challenge solutions for Scheme sandboxes
- Gerbil's own restricted-eval tests as baseline

---

## Harness Design

### Standard Harness Template

Each fuzz target gets a harness file in `tests/fuzz/harness/fuzz-<target>.ss`:

```scheme
(import (jerboa prelude)
        (std test))

;; Configuration
;; Note: Chez has no getenv-number — parse manually
(define (getenv-int name default)
  (let ([v (getenv name)])
    (if v (or (string->number v) default) default)))

(define *iterations* (getenv-int "FUZZ_ITERATIONS" 100000))
(define *max-input-size* (getenv-int "FUZZ_MAX_SIZE" 65536))
(define *timeout-fuel* 1000000)  ;; engine ticks, not seconds

;; Input generation
(define (random-bytes n)
  (let ([bv (make-bytevector n)])
    (do ([i 0 (+ i 1)])
        ((= i n) bv)
      (bytevector-u8-set! bv i (random 256)))))

(define (random-input)
  (let ([size (+ 1 (random *max-input-size*))])
    (utf8->string (random-bytes size))))  ;; will produce invalid UTF-8 — that's intentional

;; Mutator: flip random bits in a valid input
(define (mutate-string s)
  (let* ([bv (string->utf8 s)]
         [pos (random (bytevector-length bv))]
         [bit (random 8)])
    (bytevector-u8-set! bv pos
      (fxlogxor (bytevector-u8-ref bv pos) (fxsll 1 bit)))
    (guard (e [#t s])  ;; if invalid UTF-8, return original
      (utf8->string bv))))

;; Timeout via Chez engine (measures reductions, not wall-clock)
(define (fuzz-with-timeout thunk fuel)
  (let ([eng (make-engine thunk)])
    (eng fuel
      (lambda (remaining result) result)
      (lambda (new-engine) 'timeout))))

;; Harness
(define (fuzz-once parse-fn input)
  (guard (exn [#t (void)])  ;; any Scheme exception is acceptable
    (fuzz-with-timeout
      (lambda () (parse-fn input))
      *timeout-fuel*)))

(define (run-fuzz name parse-fn gen-fn)
  (display (format "Fuzzing ~a for ~a iterations...\n" name *iterations*))
  (let loop ([i 0] [crashes 0])
    (if (>= i *iterations*)
      (begin
        (display (format "Done. ~a iterations, ~a timeouts/crashes\n" i crashes))
        crashes)
      (let ([input (gen-fn)])
        (let ([ok? (fuzz-once parse-fn input)])
          (loop (+ i 1) (if (eq? ok? (void)) crashes (+ crashes 1))))))))
```

### Bytevector Harness (for network protocols)

```scheme
;; For HTTP/2, WebSocket, DNS — input is raw bytes, not strings
(define (random-bytevector max-size)
  (random-bytes (+ 1 (random max-size))))

(define (mutate-bytevector bv)
  (let* ([copy (bytevector-copy bv)]
         [pos (random (bytevector-length copy))])
    ;; Random mutation: flip, insert, delete, or set to boundary value
    (case (random 4)
      [(0) (bytevector-u8-set! copy pos (fxlogxor (bytevector-u8-ref copy pos) (fxsll 1 (random 8))))]
      [(1) (bytevector-u8-set! copy pos 0)]        ;; null
      [(2) (bytevector-u8-set! copy pos 255)]       ;; max byte
      [(3) (bytevector-u8-set! copy pos (random 256))])  ;; random
    copy))
```

### Sandbox Harness (special — measures escape, not crash)

```scheme
;; The oracle is different: success means the sandbox HELD.
;; A "bug" is when sandboxed code accesses something it shouldn't.

(define (fuzz-sandbox input-expr)
  (let ([result (guard (e [#t 'exception])
                  (restricted-eval input-expr))])
    ;; Check for signs of escape
    (when (and (not (eq? result 'exception))
               (or (port? result)
                   (procedure? result)  ;; might be a captured continuation
                   (and (string? result)
                        (string-contains result "/etc/"))))
      (report-sandbox-escape input-expr result))))
```

---

## Bug Oracles

A fuzzer that only checks "did it crash?" misses half the bugs. Each target needs specific oracles.

### Crash Oracle (all targets)
Any uncaught exception that isn't a well-formed condition with a message is a bug. Chez `&assertion` with a clear message is fine. Segfault is always a bug.

### Hang Oracle (all targets)
Time limit per input. Reader, JSON, DNS, and regex are the highest-risk targets. Default: 5 seconds per input for parsers, 30 seconds for regex (backtracking is inherently slow).

### Memory Oracle (network parsers)
Track `(current-memory-bytes)` before and after. A single input that causes >100MB allocation is a memory bomb bug.

### Differential Oracle (reader, JSON)
Compare output against a reference implementation. Divergence on well-formed input is always a bug. Divergence on malformed input should be logged and triaged.

### Roundtrip Oracle (JSON, base64, hex)
`decode(encode(x))` should equal `x`. `encode(decode(valid-input))` should equal the canonical form of `valid-input`.

### Idempotence Oracle (reader)
`read(write(read(input)))` should equal `read(input)` for valid inputs.

### Sandbox Escape Oracle
Any capability gained that isn't in the 29-binding safe set is a critical security bug.

---

## Infrastructure

### Directory Layout

```
tests/fuzz/
├── harness/
│   ├── fuzz-reader.ss
│   ├── fuzz-json.ss
│   ├── fuzz-http2.ss
│   ├── fuzz-websocket.ss
│   ├── fuzz-dns.ss
│   ├── fuzz-csv.ss
│   ├── fuzz-base64.ss
│   ├── fuzz-pregexp.ss
│   ├── fuzz-sandbox.ss
│   └── fuzz-all.ss           ;; runs all harnesses
├── corpus/
│   ├── reader/               ;; seed inputs per target
│   ├── json/
│   ├── http2/
│   ├── websocket/
│   ├── dns/
│   └── pregexp/
├── crashes/                   ;; reproducer inputs that triggered bugs
│   └── <target>-<hash>.input
├── coverage/                  ;; coverage data (if Chez supports it)
└── README.md                  ;; how to run
```

### Makefile Targets

```makefile
# Run all fuzzers with default iterations
fuzz: fuzz-reader fuzz-json fuzz-http2 fuzz-websocket fuzz-dns

# Individual targets
fuzz-reader:
	FUZZ_ITERATIONS=100000 $(SCHEME) --libdirs lib --script tests/fuzz/harness/fuzz-reader.ss

fuzz-json:
	FUZZ_ITERATIONS=100000 $(SCHEME) --libdirs lib --script tests/fuzz/harness/fuzz-json.ss

# Quick smoke test (CI)
fuzz-smoke:
	FUZZ_ITERATIONS=1000 $(SCHEME) --libdirs lib --script tests/fuzz/harness/fuzz-all.ss

# Long-running (overnight / dedicated machine)
fuzz-deep:
	FUZZ_ITERATIONS=10000000 FUZZ_MAX_SIZE=1048576 \
	  $(SCHEME) --libdirs lib --script tests/fuzz/harness/fuzz-all.ss
```

### CI Integration

Run `fuzz-smoke` (1,000 iterations per target) on every PR. This catches regressions in ~30 seconds. The full `fuzz-deep` runs nightly on a dedicated machine.

---

## Triage and Regression

### Crash Triage Process

1. **Minimize**: Reduce the crashing input to the smallest reproducer. For string inputs, binary-search on length. For bytevectors, delta-debugging.
2. **Classify**: Stack overflow? OOB? Infinite loop? Memory? Use the bug class table from section 1.
3. **Deduplicate**: Hash the stack trace. Same trace = same bug.
4. **Severity**:
   - **Critical**: Sandbox escape, memory corruption (FFI), crashes on inputs reachable from network
   - **High**: Infinite loops on network-reachable parsers, memory exhaustion < 1MB input
   - **Medium**: Crashes on locally-controlled input (reader, config), silent wrong output
   - **Low**: Crashes on intentionally malformed input that would never occur naturally
5. **Fix**: Patch the parser, add the minimized input as a regression test.

### Regression Test Integration

Every crash found by fuzzing becomes a test case in `tests/test-fuzz-regressions.ss`:

```scheme
(check-exception  ;; should raise an error, NOT crash
  (jerboa-read-string "((((((((((((((...1000 deep...)))))))))))))))")
  => &read-error)

(check-exception
  (read-json "{\"a\":{\"b\":{\"c\":...10000 deep...}}}")
  => &json-parse-error)

(check-exception
  (dns-decode-response #vu8(0 0 0 0 0 0 0 0 0 0 0 0 192 0))  ;; compression pointer to self
  => &dns-parse-error)
```

---

## Implementation Roadmap

### Phase 1: Core Harnesses (Week 1)

| Task | Target | Deliverable |
|------|--------|-------------|
| Reader harness | `jerboa/reader` | `fuzz-reader.ss` with random + mutated valid inputs |
| JSON harness | `std/text/json` | `fuzz-json.ss` with JSONTestSuite seeds |
| Seed corpus | Reader + JSON | Curated seed directories |
| Makefile integration | All | `make fuzz-smoke` target |

### Phase 2: Network Protocol Harnesses (Week 2)

| Task | Target | Deliverable |
|------|--------|-------------|
| HTTP/2 harness | `std/net/http2` | `fuzz-http2.ss` with frame mutation |
| WebSocket harness | `std/net/websocket` | `fuzz-websocket.ss` |
| DNS harness | `std/net/dns` | `fuzz-dns.ss` with compression pointer focus |
| Memory oracle | All network | Per-input memory tracking |

### Phase 3: Security and Text Harnesses (Week 3)

| Task | Target | Deliverable |
|------|--------|-------------|
| Sandbox harness | `std/security/restrict` | `fuzz-sandbox.ss` with escape detection |
| Regex harness | `std/pregexp` | `fuzz-pregexp.ss` with ReDoS patterns |
| CSV + Base64 + Hex | Text parsers | Roundtrip + crash oracles |
| Differential reader | `jerboa/reader` vs Gerbil | Comparison harness |

### Phase 4: CI and Long-Running (Week 4)

| Task | Deliverable |
|------|-------------|
| CI smoke tests | `fuzz-smoke` in PR pipeline, <30s |
| Nightly deep fuzz | Cron job, 10M iterations |
| Crash database | `tests/fuzz/crashes/` with dedup |
| Regression suite | `test-fuzz-regressions.ss` |
| Coverage tracking | Identify under-fuzzed code paths |

### Phase 5: Advanced Techniques (Ongoing)

| Task | Deliverable |
|------|-------------|
| Grammar-based generation | Structure-aware fuzzers for JSON, reader, DNS |
| C-level fuzzing | AFL++ harnesses for chez-yaml, chez-sqlite, libcrypto |
| Differential fuzzing | Reader vs Gerbil, JSON vs jq, base64 vs coreutils |
| Property-based testing | QuickCheck-style shrinking for minimized reproducers |

---

## Appendix: Known Issues to Verify

These are bugs identified by code review that fuzzing should confirm:

| Module | Issue | Severity |
|--------|-------|----------|
| `std/text/json` | `\uD800` (lone surrogate) calls `integer->char` which crashes on surrogates in Chez | High |
| `std/text/json` | `\uD800\uDC00` surrogate pair not handled — each half parsed independently | Medium |
| `std/net/http2` | HPACK `hpack-decode-string` doesn't bounds-check `len` against bytevector length | High |
| `std/net/dns` | No bounds check before reading answer RR fields (type, class, ttl, rdlength) at `pos+0..pos+9` | High |
| `std/text/base64` | Padding logic with `saw-non-pad?` flag set but never checked | Low |

---

## Appendix: Expected Bug Yield Estimates

Based on experience fuzzing similar parsers in other projects:

| Target | Expected Bugs (first 1M iterations) | Confidence |
|--------|--------------------------------------|-----------|
| Reader (recursion depth) | 1-3 stack overflows | High |
| JSON (recursion + Unicode) | 2-5 crashes/hangs | High |
| HTTP/2 (bounds checking) | 3-8 OOB/memory bugs | High |
| WebSocket (bounds) | 2-5 OOB bugs | High |
| DNS (compression loops) | 1-2 infinite loops, 2-4 OOB | High |
| Pregexp (ReDoS) | 1-3 CPU exhaustion patterns | Medium |
| Base64 (silent errors) | 1-2 logic bugs | Medium |
| CSV (quote handling) | 1-2 edge cases | Medium |
| Sandbox (escape) | 0-1 escapes | Low (but critical if found) |
| YAML (C library) | 0-2 via C fuzzing | Unknown |

Total expected: **15-35 bugs** from the first serious fuzzing campaign, of which 5-10 are likely security-relevant.
