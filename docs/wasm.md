# WebAssembly on Jerboa

Jerboa includes a complete WASM MVP implementation: a Scheme-to-WASM compiler
and a stack-based interpreter/runtime. WASM modules are compiled from Scheme
source, validated, and executed entirely within the Chez Scheme process — no
native code generation, no JIT, no RWX pages.

## Architecture

```
Scheme source
    |
    v
codegen.sls    -- Scheme -> WASM binary compiler
    |
    v
format.sls     -- WASM binary encoding (opcodes, LEB128, sections)
    |
    v
runtime.sls    -- Decoder, validator, stack-based interpreter
```

- **format.sls** (~500 lines): All MVP opcodes, LEB128 encoding/decoding for
  i32/i64/u32, section IDs, type constants, bytevector builder.
- **codegen.sls** (~1100 lines): Compiles Scheme `define` forms to WASM
  functions. Supports arithmetic, comparisons, conditionals, let/let*,
  recursion, while loops, memory ops, globals, data segments, tables,
  typed parameters (i32/i64/f32/f64), and multi-function programs.
- **runtime.sls** (~1500 lines): Decodes WASM binaries, validates module
  structure and bytecode, instantiates modules, and interprets all MVP opcodes.

## Quick Start

```scheme
(import (except (chezscheme) compile-program)
        (jerboa wasm format)
        (jerboa wasm codegen)
        (jerboa wasm runtime))

;; Compile Scheme to WASM binary
(define bv (compile-program
             '((define (factorial n)
                 (if (= n 0) 1 (* n (factorial (- n 1))))))))

;; Load and run
(define rt (make-wasm-runtime))
(wasm-runtime-load rt bv)
(wasm-runtime-call rt "factorial" 10)  ;; => 3628800
```

## Supported Features

### Numeric Types
- **i32**: Full arithmetic, bitwise ops (and/or/xor/shl/shr/rotl/rotr),
  clz/ctz/popcnt, signed and unsigned comparisons and division
- **i64**: Full arithmetic, bitwise ops, signed and unsigned comparisons
- **f32/f64**: IEEE 754 arithmetic, abs/neg/ceil/floor/trunc/nearest/sqrt,
  min/max/copysign, comparisons

### Control Flow
- `block`, `loop`, `if`/`else`, `br`, `br_if`, `br_table`
- `return`, `unreachable`, `nop`
- `call`, `call_indirect` (function tables)
- `select`, `drop`

### Memory
- Linear memory with configurable initial size (`define-memory`)
- All load/store variants: i32/i64/f32/f64, sub-word (8/16/32-bit)
- `memory.size`, `memory.grow`
- Data segments for initialization

### Globals
- Mutable and immutable globals (`define-global`)
- `global.get`, `global.set`

### Tables and Indirect Calls
- `funcref` tables with element segment initialization
- `call_indirect` for dynamic dispatch

### Conversions
- All MVP conversion opcodes: wrap, extend, trunc, convert, promote,
  demote, reinterpret, sign extension

### Imports and Exports
- Function imports with typed signatures
- Function exports by name

## Resource Limits

All limits are configurable per-runtime and enforced during execution:

```scheme
(define rt (make-wasm-runtime))
(wasm-runtime-set-fuel! rt 1000000)          ;; max instructions (default: 10M)
(wasm-runtime-set-max-depth! rt 500)         ;; max call depth (default: 1000)
(wasm-runtime-set-max-stack! rt 5000)        ;; max value stack entries (default: 10K)
(wasm-runtime-set-max-memory-pages! rt 16)   ;; max memory pages (default: 256 = 16MB)
```

| Limit | Default | What it prevents |
|---|---|---|
| Fuel | 10,000,000 instructions | Infinite loops, CPU exhaustion |
| Call depth | 1,000 | Unbounded recursion |
| Value stack | 10,000 entries | Stack exhaustion |
| Memory pages | 256 (16 MB) | Memory exhaustion via `memory.grow` |

Setting any limit to `#f` uses the default. All violations raise `wasm-trap`.

## Security Model

### Sandboxing Guarantees

| Property | Mechanism |
|---|---|
| **No host escape** | WASM code cannot call Scheme functions, access files, network, or FFI — only exported functions and linear memory are reachable |
| **Memory isolation** | All 15 load/store helpers call `check-mem-bounds`; OOB = `wasm-trap`, not segfault |
| **Deterministic termination** | Fuel counter decremented per instruction; exhaustion = `wasm-trap` |
| **No stack smashing** | Value stack is a Scheme list; overflow = `wasm-trap`, not native stack corruption |
| **No code injection** | Interpreter dispatches known opcodes only; unknown opcode = `wasm-trap` |
| **Address safety** | `read-memarg` clamps base+offset to u32 via `bitwise-and #xFFFFFFFF` to prevent bignum addresses |
| **Consistent error surface** | All 35 error sites in the runtime use `(raise (make-wasm-trap ...))` — zero `(error ...)` calls |

### Module Validation

`wasm-validate-module` runs automatically before instantiation and checks:

1. **Section ordering**: Non-custom sections must have strictly increasing IDs
2. **Function/code count**: Function section and code section entry counts must match
3. **Type index bounds**: All function type indices reference valid type section entries
4. **MVP limits**: At most one memory, at most one table
5. **Start function**: Start section index must reference a valid function
6. **Bytecode integrity**: Block nesting balance and instruction boundary validation

### Threat Model

| Threat | Protected? | Mechanism |
|---|---|---|
| Infinite loop / CPU exhaustion | Yes | Fuel metering |
| Stack overflow / deep recursion | Yes | Call depth + value stack limits |
| Memory corruption / OOB access | Yes | Bounds checks on all memory ops |
| Memory exhaustion via grow | Yes | Configurable page limit |
| Code injection | Yes | Interpreter-only, no JIT |
| Host system access | Yes | No FFI/IO paths from WASM |
| Malformed module crash | Mostly | Validation catches structural issues |
| Integer overflow in addresses | Yes | u32 clamping |

### Known Gaps

| Gap | Severity | Notes |
|---|---|---|
| No type stack validation | Low | A full WASM type checker would verify operand types at validation time (e.g., i32.add expects two i32s). Currently, type mismatches produce Chez conditions rather than wasm-traps at runtime. |
| data/element segment bounds | Medium | Crafted offset values could cause `bytevector-copy!` or `vector-set!` to raise a Chez error rather than a wasm-trap during instantiation. Cannot cause memory corruption. |
| call_indirect type check | Medium | The spec requires checking callee type signature against the call_indirect type index. Currently only checks for null table entries, not type mismatches. |
| i64 clz/ctz/popcnt/rotl/rotr | Low | Return stub values (0). Correctness issue, not security. |

## Runtime API Reference

### Core

```scheme
(make-wasm-runtime)                          ;; create runtime
(wasm-runtime-load rt bytevector)            ;; decode + validate + instantiate
(wasm-runtime-call rt "name" arg ...)        ;; call exported function
```

### Memory Access (Host Side)

```scheme
(wasm-runtime-memory rt)                     ;; raw bytevector
(wasm-runtime-memory-size rt)                ;; byte count
(wasm-runtime-memory-ref rt offset)          ;; read byte
(wasm-runtime-memory-set! rt offset val)     ;; write byte
```

### Global Access (Host Side)

```scheme
(wasm-runtime-global-ref rt index)           ;; read global
(wasm-runtime-global-set! rt index val)      ;; write global
```

### Low-Level

```scheme
(wasm-decode-module bytevector)              ;; decode without instantiation
(wasm-validate-module decoded-module)        ;; explicit validation
(make-wasm-store)                            ;; create store
(wasm-store-instantiate store decoded-mod)   ;; validate + instantiate
```

### Traps

```scheme
(make-wasm-trap "message")                   ;; create trap
(wasm-trap? obj)                             ;; predicate
(wasm-trap-message trap)                     ;; error message string
```

All runtime errors raise `wasm-trap` via `(raise (make-wasm-trap ...))`.
Use `guard` to catch:

```scheme
(guard (exn
  [(wasm-trap? exn)
   (printf "trapped: ~a~%" (wasm-trap-message exn))])
  (wasm-runtime-call rt "dangerous-function"))
```

## Compiler Input Language

The `compile-program` function accepts a list of top-level forms:

```scheme
;; Functions
(define (name params ...) body)
(define (name (param type) ... -> return-type) body)

;; Memory
(define-memory pages)

;; Globals
(define-global name type mutable? init-value)

;; Data segments
(define-data offset "string-data")

;; Tables and elements
(define-table min-size max-size)
(define-elem table-idx offset func-name ...)
```

### Supported Expressions

- Arithmetic: `+`, `-`, `*`, `quotient`, `remainder`
- Comparison: `=`, `<`, `>`, `<=`, `>=`, `!=`
- Logic: `and`, `or`, `not`
- Control: `if`, `cond`, `when`, `unless`, `begin`, `while`
- Binding: `let`, `let*`
- Typed ops: `i32.add`, `i64.mul`, `f64.sqrt`, etc. (all MVP opcodes)
- Memory: `i32.load`, `i32.store`, `memory.size`, `memory.grow`, etc.
- Globals: `global.get`, `global.set`
- Special: `unreachable`, `select`, `return`

## Tests

235 tests across 4 suites:

```
tests/test-wasm-format.ss    --  42 tests (encoding, opcodes, LEB128)
tests/test-wasm-codegen.ss   --  30 tests (compiler structure, code emission)
tests/test-wasm-runtime.ss   --  28 tests (interpreter, store, instantiation)
tests/test-wasm-mvp.ss       -- 135 tests (end-to-end: compile + run + security)
```

Run all:

```sh
scheme --libdirs lib --script tests/test-wasm-format.ss
scheme --libdirs lib --script tests/test-wasm-codegen.ss
scheme --libdirs lib --script tests/test-wasm-runtime.ss
scheme --libdirs lib --script tests/test-wasm-mvp.ss
```
