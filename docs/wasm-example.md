# WASM Practical Examples

This guide shows how to write real programs using Jerboa's WASM pipeline:
compile Scheme to WASM bytecode, run it in the Rust wasmi sandbox, and
integrate with jsh (Jerboa Shell).

For architecture and API reference, see [wasm.md](wasm.md).

## Table of Contents

- [Prerequisites](#prerequisites)
- [Example 1: Numeric Computation](#example-1-numeric-computation)
- [Example 2: Memory-Based Data Processing](#example-2-memory-based-data-processing)
- [Example 3: A Byte-Level Tokenizer](#example-3-a-byte-level-tokenizer)
- [Example 4: Parser with Import Callbacks](#example-4-parser-with-import-callbacks)
- [Example 5: State Machine Protocol Parser](#example-5-state-machine-protocol-parser)
- [Compiling to .wasm Files](#compiling-to-wasm-files)
- [String I/O Conventions](#string-io-conventions)
- [What Works Well in WASM](#what-works-well-in-wasm)
- [Current Limitations](#current-limitations)
- [jsh Integration Roadmap](#jsh-integration-roadmap)

## Prerequisites

```scheme
(import (except (chezscheme) compile-program)
        (jerboa wasm format)
        (jerboa wasm codegen)
        (jerboa wasm runtime))

;; For Rust wasmi sandbox (optional — provides ROP isolation):
(import (std wasm sandbox))
```

Two execution modes:

| Mode | Module | Runs in | Use case |
|------|--------|---------|----------|
| **Interpreter** | `(jerboa wasm runtime)` | Chez Scheme process | Development, debugging |
| **Sandbox** | `(std wasm sandbox)` | Rust wasmi (separate address space) | Production, untrusted code |

Both accept the same bytecode from `compile-program`.

---

## Example 1: Numeric Computation

Pure functions on i32/i64/f32/f64 — the simplest case.

```scheme
(define bv (compile-program
  '((define (factorial (n i32) -> i32)
      (if (= n 0) 1 (* n (factorial (- n 1)))))

    (define (fibonacci (n i32) -> i32)
      (if (<= n 1) n
        (+ (fibonacci (- n 1)) (fibonacci (- n 2)))))

    (define (gcd (a i32) (b i32) -> i32)
      (if (= b 0) a (gcd b (remainder a b))))

    (define (is-prime (n i32) -> i32)
      (if (<= n 1) 0
        (let ((i 2) (limit (+ 1 (i32.trunc_f64_s (f64.sqrt (f64.convert_i32_s n))))))
          (while (and (<= i limit) (!= (remainder n i) 0))
            (set! i (+ i 1)))
          (if (> i limit) 1 0)))))))

;; Run in interpreter
(define rt (make-wasm-runtime))
(wasm-runtime-load rt bv)
(wasm-runtime-call rt "factorial" 12)   ;; => 479001600
(wasm-runtime-call rt "fibonacci" 20)   ;; => 6765
(wasm-runtime-call rt "gcd" 48 18)      ;; => 6
(wasm-runtime-call rt "is-prime" 997)   ;; => 1

;; Run in Rust wasmi sandbox (identical bytecode)
(define mod-h (wasm-sandbox-load bv))
(define inst (wasm-sandbox-instantiate mod-h))
(wasm-sandbox-call inst "factorial" 12) ;; => 479001600
(wasm-sandbox-free inst)
(wasm-sandbox-free-module mod-h)
```

---

## Example 2: Memory-Based Data Processing

WASM linear memory is a flat byte array. Use it for arrays, buffers, and
structured data.

```scheme
(define bv (compile-program
  '((define-memory 1)  ;; 1 page = 64 KiB

    ;; Sum an array of i32 values at [base, base + count*4)
    (define (sum-array (base i32) (count i32) -> i32)
      (let ((total 0) (i 0))
        (while (< i count)
          (set! total (+ total (i32.load (+ base (* i 4)))))
          (set! i (+ i 1)))
        total))

    ;; Find maximum in an i32 array
    (define (max-array (base i32) (count i32) -> i32)
      (let ((best (i32.load base)) (i 1))
        (while (< i count)
          (let ((val (i32.load (+ base (* i 4)))))
            (when (> val best)
              (set! best val)))
          (set! i (+ i 1)))
        best))

    ;; In-place bubble sort on an i32 array
    (define (sort-array (base i32) (count i32) -> i32)
      (let ((i 0))
        (while (< i (- count 1))
          (let ((j 0))
            (while (< j (- count i 1))
              (let ((addr-j (+ base (* j 4)))
                    (addr-j1 (+ base (* (+ j 1) 4))))
                (let ((a (i32.load addr-j))
                      (b (i32.load addr-j1)))
                  (when (> a b)
                    (i32.store addr-j b)
                    (i32.store addr-j1 a))))
              (set! j (+ j 1))))
          (set! i (+ i 1)))
        0)))))

;; Use from host
(define mod-h (wasm-sandbox-load bv))
(define inst (wasm-sandbox-instantiate mod-h))

;; Write [30, 10, 50, 20, 40] at offset 0 as little-endian i32s
(wasm-sandbox-memory-write inst 0
  (u8-list->bytevector
    '(30 0 0 0  10 0 0 0  50 0 0 0  20 0 0 0  40 0 0 0)))

(wasm-sandbox-call inst "sum-array" 0 5)   ;; => 150
(wasm-sandbox-call inst "max-array" 0 5)   ;; => 50
(wasm-sandbox-call inst "sort-array" 0 5)  ;; => 0 (in-place)

;; Read sorted result back
(wasm-sandbox-memory-read inst 0 20)
;; => #vu8(10 0 0 0 20 0 0 0 30 0 0 0 40 0 0 0 50 0 0 0)

(wasm-sandbox-free inst)
(wasm-sandbox-free-module mod-h)
```

---

## Example 3: A Byte-Level Tokenizer

This is the core use case: write a lexer in Jerboa's WASM dialect, compile it,
run it on untrusted input in the sandbox. The host writes UTF-8 bytes into WASM
memory, the WASM tokenizer scans them, and writes token descriptors to a
separate memory region that the host reads back.

### Memory layout convention

```
Offset 0x0000 .. 0x0FFF  (4 KiB)   Input buffer (host writes here)
Offset 0x1000 .. 0x2FFF  (8 KiB)   Token output: (type:i32, start:i32, end:i32) × N
```

### The tokenizer

```scheme
(define tokenizer-bytecode
  (compile-program
    '((define-memory 1)

      ;; Token output pointer (starts at 0x1000)
      (define-global out-ptr i32 #t 4096)
      ;; Token count
      (define-global token-count i32 #t 0)

      ;; --- Character classes ---

      (define (is-space (c i32) -> i32)
        (or (= c 32) (= c 9) (= c 10) (= c 13)))

      (define (is-digit (c i32) -> i32)
        (and (>= c 48) (<= c 57)))

      (define (is-alpha (c i32) -> i32)
        (or (and (>= c 65) (<= c 90))    ;; A-Z
            (and (>= c 97) (<= c 122))   ;; a-z
            (= c 95)))                     ;; _

      (define (is-alnum (c i32) -> i32)
        (or (is-alpha c) (is-digit c)))

      ;; --- Token emitter ---
      ;; Token types: 0=EOF, 1=NUMBER, 2=WORD, 3=STRING, 4=OPERATOR, 5=NEWLINE

      (define (emit (typ i32) (start i32) (end i32) -> i32)
        (let ((p (global.get 0)))
          (i32.store p typ)
          (i32.store (+ p 4) start)
          (i32.store (+ p 8) end)
          (global.set 0 (+ p 12))
          (global.set 1 (+ (global.get 1) 1))
          0))

      ;; --- Main tokenizer ---
      ;; Input: bytes at offset 0, length passed as argument.
      ;; Returns: number of tokens emitted.

      (define (tokenize (input-len i32) -> i32)
        ;; Reset output state
        (global.set 0 4096)
        (global.set 1 0)
        (let ((pos 0))
          (while (< pos input-len)
            (let ((ch (i32.load8_u pos)))
              (if (= ch 10)
                ;; Newline token
                (begin (emit 5 pos (+ pos 1))
                       (set! pos (+ pos 1)))
                (if (is-space ch)
                  ;; Skip whitespace
                  (set! pos (+ pos 1))
                  (if (is-digit ch)
                    ;; Number: scan digits
                    (let ((start pos))
                      (while (and (< pos input-len)
                                  (is-digit (i32.load8_u pos)))
                        (set! pos (+ pos 1)))
                      (emit 1 start pos))
                    (if (is-alpha ch)
                      ;; Word: scan alphanumeric
                      (let ((start pos))
                        (while (and (< pos input-len)
                                    (is-alnum (i32.load8_u pos)))
                          (set! pos (+ pos 1)))
                        (emit 2 start pos))
                      (if (= ch 34)
                        ;; Double-quoted string: scan to closing quote
                        (let ((start pos))
                          (set! pos (+ pos 1))
                          (while (and (< pos input-len)
                                      (!= (i32.load8_u pos) 34))
                            (set! pos (+ pos 1)))
                          (when (< pos input-len)
                            (set! pos (+ pos 1)))  ;; skip closing "
                          (emit 3 start pos))
                        ;; Operator: single character
                        (begin
                          (emit 4 pos (+ pos 1))
                          (set! pos (+ pos 1))))))))))
          ;; Emit EOF
          (emit 0 pos pos)
          (global.get 1))))))
```

### Running the tokenizer

```scheme
(define mod-h (wasm-sandbox-load tokenizer-bytecode))
(define inst (wasm-sandbox-instantiate mod-h 'fuel: 5000000))

;; Write input
(define input (string->utf8 "count = 42 + x\n"))
(wasm-sandbox-memory-write inst 0 input)

;; Tokenize
(define n-tokens (wasm-sandbox-call inst "tokenize" (bytevector-length input)))
;; => 6 (WORD, OPERATOR, NUMBER, OPERATOR, WORD, NEWLINE) + EOF = 7

;; Read token table (each token = 12 bytes: type, start, end)
(define token-data (wasm-sandbox-memory-read inst #x1000 (* n-tokens 12)))

;; Decode tokens back into Scheme
(define (decode-tokens bv input-bv count)
  (let loop ((i 0) (tokens '()))
    (if (= i count) (reverse tokens)
      (let* ((base (* i 12))
             (type (bytevector-u32-ref bv base 'little))
             (start (bytevector-u32-ref bv (+ base 4) 'little))
             (end (bytevector-u32-ref bv (+ base 8) 'little))
             (text (utf8->string
                     (bytevector-copy input-bv start end))))
        (loop (+ i 1)
              (cons (list (vector-ref '#(EOF NUMBER WORD STRING OPERATOR NEWLINE)
                                      type)
                          text)
                    tokens))))))

(decode-tokens token-data input n-tokens)
;; => ((WORD "count") (OPERATOR "=") (NUMBER "42")
;;     (OPERATOR "+") (WORD "x") (NEWLINE "\n") (EOF ""))

(wasm-sandbox-free inst)
(wasm-sandbox-free-module mod-h)
```

---

## Example 4: Parser with Import Callbacks

Instead of writing tokens to memory, the WASM parser calls an imported host
function for each token. This is cleaner for streaming parsers and avoids
output-buffer sizing.

```scheme
;; The WASM program imports an "emit" function from the host
(define parser-bytecode
  (compile-program
    '((define-memory 1)

      ;; Import: host-side token handler
      ;; Args: token_type, start_offset, end_offset
      (define-import "env" "emit_token" (i32 i32 i32) ())

      (define (is-space (c i32) -> i32)
        (or (= c 32) (= c 9)))

      (define (is-digit (c i32) -> i32)
        (and (>= c 48) (<= c 57)))

      ;; Tokenize: scan digits and words, call emit_token for each
      (define (parse (len i32) -> i32)
        (let ((pos 0) (count 0))
          (while (< pos len)
            (let ((ch (i32.load8_u pos)))
              (if (is-space ch)
                (set! pos (+ pos 1))
                (if (is-digit ch)
                  (let ((start pos))
                    (while (and (< pos len)
                                (is-digit (i32.load8_u pos)))
                      (set! pos (+ pos 1)))
                    (emit_token 1 start pos)
                    (set! count (+ count 1)))
                  (let ((start pos))
                    (set! pos (+ pos 1))
                    (emit_token 2 start pos)
                    (set! count (+ count 1)))))))
          count)))))
```

To run this with the **interpreter** (which supports host import functions):

```scheme
(define rt (make-wasm-runtime))

;; Collected tokens
(define tokens '())

;; Register import — the host function called by WASM
(wasm-runtime-load rt parser-bytecode
  `(("env" . (("emit_token" . ,(lambda (type start end)
                                  (set! tokens
                                    (cons (list type start end) tokens))
                                  0))))))

;; Write input and run
(define input (string->utf8 "42 + 7"))
(wasm-runtime-memory-set! rt 0 input)
(wasm-runtime-call rt "parse" (bytevector-length input))

(reverse tokens)
;; => ((1 0 2) (2 3 4) (1 5 6))
;; Token type 1 = number at "42", type 2 = operator at "+", type 1 = number at "7"
```

**Note**: Import callbacks currently work with the Scheme interpreter runtime.
The Rust wasmi sandbox does not yet expose host function registration (the WASM
module must be self-contained). This is a planned enhancement.

---

## Example 5: State Machine Protocol Parser

Parse a simple key=value protocol (like HTTP headers or .env files) entirely
in WASM.

```scheme
(define kv-parser-bytecode
  (compile-program
    '((define-memory 1)

      ;; Memory layout:
      ;;   0x0000 .. 0x1FFF  Input (8 KiB)
      ;;   0x2000 .. 0x3FFF  Output: pairs as (key_start, key_end, val_start, val_end) × N
      (define-global out-ptr i32 #t 8192)
      (define-global pair-count i32 #t 0)

      (define (emit-pair (ks i32) (ke i32) (vs i32) (ve i32) -> i32)
        (let ((p (global.get 0)))
          (i32.store p ks)
          (i32.store (+ p 4) ke)
          (i32.store (+ p 8) vs)
          (i32.store (+ p 12) ve)
          (global.set 0 (+ p 16))
          (global.set 1 (+ (global.get 1) 1))
          0))

      ;; States: 0=start-of-line, 1=in-key, 2=after-eq, 3=in-value
      (define (parse-kv (len i32) -> i32)
        (global.set 0 8192)
        (global.set 1 0)
        (let ((pos 0) (state 0) (mark 0) (key-start 0) (key-end 0))
          (while (< pos len)
            (let ((ch (i32.load8_u pos)))
              (if (= state 0)
                ;; Start of line: skip whitespace, begin key
                (if (or (= ch 10) (= ch 13) (= ch 32))
                  (set! pos (+ pos 1))
                  (if (= ch 35)
                    ;; Comment: skip to end of line
                    (begin
                      (while (and (< pos len) (!= (i32.load8_u pos) 10))
                        (set! pos (+ pos 1)))
                      (set! pos (+ pos 1)))
                    (begin
                      (set! key-start pos)
                      (set! state 1)
                      (set! pos (+ pos 1)))))
                (if (= state 1)
                  ;; In key: scan to '='
                  (if (= ch 61)
                    (begin
                      (set! key-end pos)
                      (set! state 2)
                      (set! pos (+ pos 1)))
                    (set! pos (+ pos 1)))
                  (if (= state 2)
                    ;; After '=': start value
                    (begin
                      (set! mark pos)
                      (set! state 3)
                      (set! pos (+ pos 1)))
                    ;; In value: scan to newline
                    (if (= ch 10)
                      (begin
                        (emit-pair key-start key-end mark pos)
                        (set! state 0)
                        (set! pos (+ pos 1)))
                      (set! pos (+ pos 1))))))))
          ;; Handle final value without trailing newline
          (when (= state 3)
            (emit-pair key-start key-end mark pos))
          (global.get 1))))))
```

Usage:

```scheme
(define mod-h (wasm-sandbox-load kv-parser-bytecode))
(define inst (wasm-sandbox-instantiate mod-h))

(define input (string->utf8
  "HOST=localhost\nPORT=8080\n# comment\nDEBUG=true\n"))
(wasm-sandbox-memory-write inst 0 input)

(define n-pairs (wasm-sandbox-call inst "parse-kv" (bytevector-length input)))
;; => 3

;; Read key-value pairs (16 bytes each)
(define pair-data (wasm-sandbox-memory-read inst #x2000 (* n-pairs 16)))

(define (decode-kv-pairs bv input-bv count)
  (let loop ((i 0) (pairs '()))
    (if (= i count) (reverse pairs)
      (let* ((base (* i 16))
             (ks (bytevector-u32-ref bv base 'little))
             (ke (bytevector-u32-ref bv (+ base 4) 'little))
             (vs (bytevector-u32-ref bv (+ base 8) 'little))
             (ve (bytevector-u32-ref bv (+ base 12) 'little)))
        (loop (+ i 1)
              (cons (cons (utf8->string (bytevector-copy input-bv ks ke))
                          (utf8->string (bytevector-copy input-bv vs ve)))
                    pairs))))))

(decode-kv-pairs pair-data input n-pairs)
;; => (("HOST" . "localhost") ("PORT" . "8080") ("DEBUG" . "true"))

(wasm-sandbox-free inst)
(wasm-sandbox-free-module mod-h)
```

---

## Compiling to .wasm Files

Save compiled bytecode to disk for later loading:

```scheme
;; Build step: compile and save
(define bv (compile-program '((define (add (a i32) (b i32) -> i32) (+ a b)))))
(call-with-output-file "add.wasm"
  (lambda (p) (put-bytevector p bv))
  '(binary))

;; Runtime: load from file
(define bv2 (call-with-input-file "add.wasm"
              (lambda (p) (get-bytevector-all p))
              '(binary)))
(define mod-h (wasm-sandbox-load bv2))
```

This separates compilation (build time) from execution (runtime). The `.wasm`
file is a standard WebAssembly binary — you can inspect it with `wasm-objdump`
or `wasm2wat` from the WABT toolkit.

---

## String I/O Conventions

WASM has no string type. Two conventions for passing strings between host and
WASM:

### Convention A: Memory Buffer (recommended)

Host writes UTF-8 bytes to WASM memory, passes offset and length as arguments.
WASM writes results to a separate memory region. Host reads results back.

```
Host                          WASM
 |                              |
 |-- write UTF-8 to [0..N) --->|
 |-- call parse(N) ----------->|
 |                              |-- scan bytes, write tokens to [0x1000..]
 |<-- return token_count -------|
 |-- read tokens from [0x1000] -|
```

Pros: Simple, predictable, no imports needed.
Cons: Output buffer must be pre-sized; host must decode the output format.

### Convention B: Import Callbacks (streaming)

WASM calls an imported host function for each output item. The host function
can read the relevant bytes from WASM memory using the offsets provided.

```
Host                          WASM
 |                              |
 |-- write UTF-8 to [0..N) --->|
 |-- call parse(N) ----------->|
 |                              |-- scan bytes...
 |<-- emit_token(type,s,e) ----|  (host reads bytes [s..e) from WASM memory)
 |<-- emit_token(type,s,e) ----|
 |<-- return token_count -------|
```

Pros: No output buffer sizing, streaming-friendly, host builds native objects.
Cons: Requires import function registration (interpreter mode only, currently).

---

## What Works Well in WASM

| Category | Examples |
|----------|----------|
| **Byte-level lexers** | Tokenizers, CSV parsers, line splitters |
| **State machines** | Protocol parsers, regex DFAs, format validators |
| **Numeric algorithms** | Crypto primitives, hashing, checksums |
| **Array processing** | Sorting, searching, filtering on i32/f64 arrays |
| **Fixed-format parsers** | Binary protocols, TLV, DNS packets |
| **Recursive descent** | Expression parsers, JSON number/bool parsing |
| **Pattern matchers** | Glob matching, simple regex engines |

---

## Current Limitations

### No heap allocation
WASM linear memory is flat. There's no `malloc`/`free`. For tree-building
parsers, you'd need to implement a bump allocator in WASM:

```scheme
;; Simple bump allocator pattern
(define-global heap-ptr i32 #t 16384)  ;; start allocating at 16 KiB

(define (alloc (size i32) -> i32)
  (let ((ptr (global.get heap-ptr)))
    (global.set heap-ptr (+ ptr size))
    ptr))
```

### No closures or higher-order functions
Functions can't capture variables. All data passes through arguments, globals,
or memory.

### No string operations
No `string-append`, `substring`, etc. Strings are raw bytes in memory. The
host must handle any string construction.

### No exceptions
WASM has no try/catch. Use return codes (0 = success, negative = error type).

### Numeric types only
Function parameters and return values must be i32, i64, f32, or f64.
Compound results go through memory.

### No garbage collection
Allocated memory stays allocated. Use a bump allocator that resets between
calls, or implement a free list.

---

## jsh Integration Roadmap

The goal: write a parser in Jerboa's WASM dialect, compile it to a `.wasm`
file, and invoke it from inside jsh as a shell command or pipeline stage.

### Phase 1: `wasm` builtin command

A jsh builtin that loads and calls WASM modules:

```bash
# Load a .wasm file and call an exported function
wasm call parser.wasm tokenize "hello world 42"

# Use in a pipeline — stdin flows into WASM memory
echo "HOST=localhost" | wasm pipe kv-parser.wasm parse-kv

# Persistent module (load once, call many times)
wasm load parser parser.wasm
wasm invoke parser tokenize "input text"
wasm unload parser
```

### Phase 2: `(jsh wasm)` module

Scheme-level API for jsh scripts and meta-commands:

```scheme
;; In jsh meta-command mode (,expr)
,use "parser.wasm"
,(wasm-call "parser.wasm" 'tokenize "count = 42")
```

### Phase 3: Pipeline integration

WASM modules as pipeline stages with stdin/stdout:

```bash
# WASM tokenizer as a filter
cat source.txt | wasm pipe tokenizer.wasm tokenize | grep NUMBER

# Chain WASM stages
cat input.env | wasm pipe kv-parser.wasm parse-kv | wasm pipe validator.wasm check
```

### Security model

All jsh WASM execution inherits the full security stack:

- **Fuel metering**: Deterministic termination (no infinite loops)
- **Memory isolation**: WASM can't read/write jsh process memory
- **ROP defense**: Rust wasmi keeps WASM execution off the Chez Scheme stack
- **Import validation**: Capability-gated host function access
- **Exception boundary**: WASM errors can't leak Chez runtime internals
- **Module size limits**: Reject oversized `.wasm` files before parsing
- **Sandbox composition**: jsh's Landlock/seccomp/pledge layers apply on top
