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
(wasm-runtime-set-max-module-size! rt 65536) ;; max bytecode size (default: 16MB)
```

| Limit | Default | What it prevents |
|---|---|---|
| Fuel | 10,000,000 instructions | Infinite loops, CPU exhaustion |
| Call depth | 1,000 | Unbounded recursion |
| Value stack | 10,000 entries | Stack exhaustion |
| Memory pages | 256 (16 MB) | Memory exhaustion via `memory.grow` |
| Module size | 16 MB | Memory exhaustion during parsing |

Setting any limit to `#f` uses the default. All violations raise `wasm-trap`.

## Security Model

### Sandboxing Guarantees

| Property | Mechanism |
|---|---|
| **No host escape** | WASM code cannot call Scheme functions, access files, network, or FFI — only exported functions and linear memory are reachable |
| **Memory isolation** | All 15 load/store helpers call `check-mem-bounds`; OOB = `wasm-trap`, not segfault |
| **Host API isolation** | `wasm-runtime-memory-ref/set!` and `global-ref/set!` are bounds-checked; OOB = `wasm-trap` |
| **Deterministic termination** | Fuel counter decremented per instruction; exhaustion = `wasm-trap` |
| **No stack smashing** | Value stack is a Scheme list; overflow = `wasm-trap`, not native stack corruption |
| **No code injection** | Interpreter dispatches known opcodes only; unknown opcode = `wasm-trap` |
| **Address safety** | `read-memarg` clamps base+offset to u32 via `bitwise-and #xFFFFFFFF` to prevent bignum addresses |
| **Segment bounds** | Data and element segment initialization validates offset+length against memory/table size; OOB = `wasm-trap` |
| **Indirect call safety** | `call_indirect` validates table index, element index, function index, and type signature — all OOB/mismatch = `wasm-trap` |
| **Exception boundary** | `wasm-runtime-call` catches all Chez exceptions and converts to `wasm-trap` — no uncontrolled error propagation |
| **Import validation** | Import function calls are arity-checked, exception-guarded, and return-type validated (must be numeric) |
| **Module size limit** | Oversized bytecode rejected before parsing (default 16MB, configurable) |
| **Import policy hooks** | `wasm-runtime-set-import-validator!` allows capability-based gating of import calls |

### Module Validation

`wasm-validate-module` runs automatically before instantiation and checks:

1. **Section ordering**: Non-custom sections must have strictly increasing IDs
2. **Function/code count**: Function section and code section entry counts must match
3. **Type index bounds**: All function type indices reference valid type section entries
4. **MVP limits**: At most one memory, at most one table
5. **Start function**: Start section index must reference a valid function
6. **Bytecode integrity**: Block nesting balance and instruction boundary validation
7. **Module size**: Rejected before parsing if exceeds configurable limit

### Threat Model

| Threat | Protected? | Mechanism |
|---|---|---|
| Infinite loop / CPU exhaustion | Yes | Fuel metering |
| Stack overflow / deep recursion | Yes | Call depth + value stack limits |
| Memory corruption / OOB access | Yes | Bounds checks on all memory ops + host API |
| Memory exhaustion via grow | Yes | Configurable page limit |
| Memory exhaustion via parsing | Yes | Module size limit (default 16MB) |
| Code injection | Yes | Interpreter-only, no JIT |
| Host system access | Yes | No FFI/IO paths from WASM |
| Malformed module crash | Yes | Validation + bounds-checked segment init + type error conversion |
| Integer overflow in addresses | Yes | u32 clamping |
| call_indirect table OOB | Yes | Table index, element index, function index all bounds-checked |
| Uncontrolled host exceptions | Yes | Exception boundary converts all Chez errors to wasm-trap |
| Malicious import functions | Yes | Arity check, exception guard, return-type validation, optional policy hook |
| Oversized module DoS | Yes | Module size limit enforced before parsing |

### Import Security

Import functions bridge WASM and the host. Three layers of protection:

1. **Arity validation**: Argument count must match declared parameter count
2. **Exception isolation**: Import exceptions are caught and converted to `wasm-trap`
3. **Return type validation**: Import must return a number (WASM only has numeric types)
4. **Policy hooks**: Optional import validator for capability integration:

```scheme
;; Example: restrict imports to pure computation (no I/O)
(wasm-runtime-set-import-validator! rt
  (lambda (proc args)
    (check-capability! 'wasm 'execute "import call")))
```

### Resolved Gaps

All previously identified gaps have been resolved:

- **call_indirect bounds**: Table index, element index, and function index are all bounds-checked before access.
- **Host API bounds**: `memory-ref/set!` and `global-ref/set!` validate indices; OOB raises `wasm-trap`.
- **Exception boundary**: All Chez Scheme exceptions during execution are caught at `wasm-runtime-call` and converted to `wasm-trap`.
- **Import safety**: Arity checked, exceptions caught, return types validated, optional policy hook.
- **Module size limit**: Configurable maximum bytecode size (default 16MB) enforced before parsing.
- **data/element segment bounds**: Bounds-checked during instantiation; OOB raises `wasm-trap`.
- **call_indirect type check**: Callee type signature verified against expected type index; mismatches raise `wasm-trap`.
- **i64 clz/ctz/popcnt/rotl/rotr**: Fully implemented with correct 64-bit semantics.
- **Type error surface**: Chez Scheme type conditions during execution are caught and re-raised as `wasm-trap` with opcode context.

## Runtime API Reference

### Core

```scheme
(make-wasm-runtime)                          ;; create runtime
(wasm-runtime-load rt bytevector)            ;; decode + validate + instantiate
(wasm-runtime-call rt "name" arg ...)        ;; call exported function (exception-safe)
(wasm-runtime-set-max-module-size! rt n)     ;; max bytecode bytes (default 16MB)
(wasm-runtime-set-import-validator! rt proc) ;; policy hook for import calls
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

270 tests across 4 suites:

```
tests/test-wasm-format.ss    --  42 tests (encoding, opcodes, LEB128)
tests/test-wasm-codegen.ss   --  30 tests (compiler structure, code emission)
tests/test-wasm-runtime.ss   --  28 tests (interpreter, store, instantiation)
tests/test-wasm-mvp.ss       -- 170 tests (end-to-end: compile + run + security)
```

Run all:

```sh
scheme --libdirs lib --script tests/test-wasm-format.ss
scheme --libdirs lib --script tests/test-wasm-codegen.ss
scheme --libdirs lib --script tests/test-wasm-runtime.ss
scheme --libdirs lib --script tests/test-wasm-mvp.ss
```
