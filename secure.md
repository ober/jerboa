# Jerboa Secure Binary Strategy

## The Problem

Jerboa compiles to Chez Scheme native code. A static musl binary (e.g., jerboa-secmon at 11MB) embeds:

| Component | Size | ROP Gadgets |
|-----------|------|-------------|
| petite.boot | ~1.9MB | None (`.rodata` data) |
| scheme.boot | ~1.0MB | None (data) |
| app.boot | ~2.6MB | None (data) |
| libkernel (Chez runtime) | ~1.0MB | **Thousands** — GC, compiler, thread scheduler, I/O |
| musl libc | ~200KB | Some |
| Rust native lib | ~500KB | Minimal (memory-safe code) |
| ffi-shim + program | ~25KB | Minimal |

The Chez runtime (`libkernel`) is the primary source of ROP gadgets. At ~1MB of native code, it contains thousands of potentially usable gadget sequences. It is heavily interconnected (GC references compiler, compiler references I/O, I/O references threading) so `--gc-sections` removes very little.

Boot files are pure data — zero gadget contribution. The Rust native library contributes minimal gadgets due to memory safety.

---

## Path 1: Harden the Chez Binary

**Effort**: Days. **Impact**: Highest bang for buck.

This doesn't shrink the binary but makes gadgets effectively unusable through hardware and OS enforcement.

### Intel CET (Control-flow Enforcement Technology)

Requires CPU support (`ibt` and `user_shstk` in `/proc/cpuinfo`). Available on Intel 12th gen+ and AMD Zen 4+.

#### Shadow Stack (SHSTK) — Priority: Very High

Hardware maintains a second copy of return addresses on a separate, protected shadow stack. On every `ret`, the CPU cross-checks the return address against the shadow copy. If they differ (because an attacker overwrote the real stack), the CPU faults with `#CP`.

This **directly defeats classical ROP**, which fundamentally relies on corrupted return addresses.

**Chez compatibility**: Likely works without modification. Chez uses standard `call`/`ret` calling conventions. The JIT-generated code uses normal x86_64 function prologues/epilogues. Shadow stack enforcement should be transparent.

**To enable**: Rebuild Chez with `-fcf-protection=return` (SHSTK only) or `-fcf-protection=full` (SHSTK + IBT). The binary must also be linked with CET-aware linker flags.

#### Indirect Branch Tracking (IBT) — Priority: Medium

Every indirect jump/call target must begin with an `ENDBR64` instruction. If control flow arrives at a non-`ENDBR64` instruction via indirect branch, the CPU faults.

**Chez compatibility**: Problematic. Chez's code generator emits native x86_64 code at runtime (during `compile-program` and boot file loading). This JIT-generated code does **not** have `ENDBR64` instructions at function entries. IBT will fault on calls into Chez-compiled code.

**Fix**: Patch Chez's code generator (`compile.ss` and `gc.c`) to emit `ENDBR64` (4 bytes: `f3 0f 1e fa`) at every compiled function entry point. This is a targeted change — feasible but requires understanding Chez internals.

**Alternative**: Enable SHSTK-only mode via `prctl(PR_SET_SHADOW_STACK, ...)` without IBT. Gets return-address protection without the indirect-branch requirement.

### Standard Hardening CFLAGS

Rebuild Chez and all C code with:

```
-fstack-protector-strong    # Stack canaries on functions with arrays/address-taken vars
-fstack-clash-protection    # Probe large stack allocations (prevent guard-page bypass)
-fcf-protection=full        # CET: shadow stack + indirect branch tracking
-D_FORTIFY_SOURCE=2         # Compile-time and runtime buffer overflow checks
-Wl,-z,relro,-z,now         # Full RELRO (read-only GOT/PLT after startup)
-pie                        # Position-independent executable (for ASLR)
```

**Status: DONE in `lib/jerboa/build/musl.sls`** — all of the above are now applied by
default. The `build-musl-binary` and `musl-link-command` functions automatically add these
flags. Pass `no-harden: #t` to disable for debugging. CET flags (`-fcf-protection=full`)
are only added on x86_64 Linux machine types.

**Status: DONE in `jerboa-native-rs/.cargo/config.toml`** — Rust builds now pass
`-Wl,-z,relro,-z,now` for all targets and `-fcf-protection=full` for x86_64 Linux.

**NOT YET DONE — downstream projects**: jerboa-secmon and jerboa-dns have their own
build scripts (`build-secmon-musl.ss`, `build-secmon-musl.sh`, `Dockerfile`) that hardcode
`musl-gcc -c -O2` and `musl-gcc -static` directly instead of using `(jerboa build musl)`.
These need the same flags added manually, or better, ported to use the shared build module.

**NOT YET DONE — Chez Scheme itself (libkernel.a)**: This is the biggest gap. The
Dockerfile builds Chez with `./configure --threads --disable-x11 --static CC=musl-gcc`
and no `CFLAGS` override. The resulting `libkernel.a` — the ~1MB primary source of ROP
gadgets — has **zero hardening**: no stack canaries, no CET, no FORTIFY_SOURCE. Fix by
passing hardening flags when building Chez:

```bash
./configure --threads --disable-x11 --static \
  CC=musl-gcc \
  CFLAGS="-O2 -fstack-protector-strong -fstack-clash-protection -D_FORTIFY_SOURCE=2 -fPIE -fcf-protection=full"
```

This is the single highest-impact change remaining — it hardens the code that contributes
the most ROP gadgets.

### Static PIE

Switch musl build from `-static` to **`-static-pie`**. This enables full ASLR for the entire binary — the base address, stack, heap, and mmap regions are all randomized on each execution.

Static linking actually slightly increases the gadget set (musl code is embedded rather than at a separate randomized address), but static PIE with ASLR makes all gadget addresses unpredictable. An attacker needs an information leak before they can chain gadgets.

**Status: DONE in `lib/jerboa/build/musl.sls`** — `musl-link-command` now uses
`-static-pie` by default instead of `-static`.

### Namespace Isolation

Add Linux namespace isolation to the security cage module (`lib/std/security/cage.sls`). After initialization, call:

```c
unshare(CLONE_NEWPID | CLONE_NEWNS | CLONE_NEWNET)
```

This creates:
- **PID namespace**: Process can't see or signal other processes
- **Mount namespace**: Process sees only an allow-listed filesystem
- **Network namespace**: Process has only its own network stack (or a specific pre-bound socket)

Combined with existing seccomp + Landlock/Capsicum, this creates micro-VM-like isolation without VM overhead.

**Requirement**: `CAP_SYS_ADMIN` or unprivileged user namespaces enabled (`sysctl kernel.unprivileged_userns_clone=1`).

### Hardening Summary

| Technique | Works with Chez JIT? | Effort | ROP Impact |
|-----------|---------------------|--------|------------|
| **SHSTK (shadow stack)** | Likely yes | Low (rebuild Chez) | **Directly defeats ROP** |
| **IBT (indirect branch)** | No (needs Chez patch) | High | Constrains gadgets to function entries |
| Stack canaries | C code only, not JIT | Low (add CFLAG) | Detects stack buffer overflows |
| Static PIE + ASLR | Yes | Low (change linker flag) | Gadget addresses unpredictable |
| `-fstack-clash-protection` | Yes | Trivial | Prevents guard-page bypass |
| seccomp post-init | Yes | **Already done** | Blocks ptrace, process_vm_readv |
| Landlock/Capsicum post-init | Yes | **Already done** | Blocks filesystem escape |
| Anti-debug | Yes | **Already done** | Blocks dynamic analysis |
| Integrity verification | Yes | **Already done** | Detects binary modification |
| Namespace isolation | Yes | Medium | PID/mount/network containment |

### FreeBSD Portability (Path 1)

**Intel CET is not available on any released FreeBSD.** Kernel SHSTK plumbing exists in
15-CURRENT only (Konstantin Belousov's work). IBT enforcement has not been implemented.
Userland CET support (rtld awareness, base compiled with `-fcf-protection`) is incomplete
even in -CURRENT. This means the highest-value ROP mitigation — hardware shadow stacks —
is Linux-only for the foreseeable future.

**What FreeBSD 14.x provides today:**

| Feature | FreeBSD Status | vs Linux |
|---------|---------------|----------|
| ASLR + PIE | On by default since 13.0 | **Lower entropy**: ~14 bits (stack) vs Linux ~22 bits |
| Stack canaries (`-strong`) | Since 12.0 | Comparable |
| `_FORTIFY_SOURCE=2` | Since 14.0 | Linux distros had this since ~2006 |
| Full RELRO + BIND_NOW | Since 12.0 | Comparable |
| Stack clash protection | Since ~13.x (clang) | Comparable |
| Capsicum capability mode | Mature, since 9.0 | No Linux equivalent (seccomp is different) |
| ARM PAC | Since 13.0 (arm64) | Comparable (Linux 5.0+) |
| ARM BTI | Since 14.0 (arm64) | Comparable (Linux 5.10+) |
| W^X opt-in (PROTMAX) | Since 14.0 via `procctl` | Linux has `prctl(SET_MDWE)` since 6.3 |
| SafeStack | Available (clang), not default | Same on Linux |

**The Capsicum vs seccomp gap for ROP containment:**

Capsicum and seccomp solve different problems. Capsicum restricts *which resources* a process
can access (file descriptors, paths). seccomp restricts *which syscalls* a process can make.

For ROP mitigation specifically, seccomp has a critical advantage: it can **block
`mprotect(PROT_EXEC)`** after initialization, preventing a ROP chain from making attacker-
controlled data executable (the typical second stage after gaining control flow). Capsicum
cannot do this — it does not filter memory operations.

FreeBSD's `procctl(PROC_PROTMAX_CTL)` partially addresses this gap: when enabled, the
maximum protection on a mapping is set at `mmap` time and cannot be escalated via `mprotect`.
However, this breaks Chez's JIT pattern (`mmap(RW)` then `mprotect(RX)`) unless all JIT
compilation completes before PROTMAX is enabled. A post-init PROTMAX call — after boot files
are loaded and all code is compiled — could work but requires careful sequencing.

**FreeBSD-specific hardening not available on Linux:**

- **Capsicum**: Process-level capability confinement with per-fd rights limiting. More
  principled than seccomp for resource access control. Already integrated into Jerboa's
  cage module.
- **HardenedBSD**: A FreeBSD fork with PaX-like features (strict W^X via NOEXEC, SEGVGUARD
  for brute-force ASLR defeat prevention, mandatory SafeStack). Tracks FreeBSD 14/15
  branches. Worth considering as a deployment target for maximum hardening.

**Practical implication**: On FreeBSD, the lack of CET makes **Path 2 (WASM sandbox) more
important** than on Linux. Without hardware return-address protection, software isolation of
security-critical parsers becomes the primary ROP defense rather than a defense-in-depth layer.

**ARM64 FreeBSD** (e.g., AWS Graviton) is a notable bright spot: PAC (since 13.0) provides
hardware return-address signing, and BTI (since 14.0) provides landing-pad enforcement. These
are the ARM equivalents of CET SHSTK and IBT respectively, and they are available on released
FreeBSD. For maximum hardware security on FreeBSD, target arm64.

---

## Path 2: WASM Sandbox for Parsers

**Effort**: Weeks. **Impact**: Strongest isolation for the most-attacked code.

### Why WASM Eliminates ROP

WebAssembly is **structurally immune** to classical ROP:

- **Separate code and data spaces**: Linear memory (where attacker-controlled input lives) cannot address the code section. You cannot scan executable pages for gadget sequences because they are in a completely separate address space managed by the runtime.
- **No raw jumps**: All control flow uses `block`/`loop`/`if`/`br`/`br_table`. There is no `ret` instruction that pops an address off the stack.
- **Opaque execution stack**: The WASM call stack is managed by the runtime, invisible to guest code. Buffer overflows in linear memory cannot overwrite return addresses because return addresses don't exist in linear memory.
- **Typed indirect calls**: `call_indirect` validates function type signatures at runtime. You cannot redirect an indirect call to an arbitrary function.

Even with arbitrary write within WASM linear memory, an attacker cannot hijack control flow. The attack surface shifts entirely to bugs in the WASM runtime itself.

### Architecture: Split Design

```
Jerboa binary
├── Chez runtime (orchestration, policy, configuration DSL)
├── Rust native lib (crypto via ring, TLS via rustls)
└── wasmi WASM interpreter (security-critical parsers)
    ├── dns_parser.wasm    (DNS packet parsing)
    ├── http_parser.wasm   (HTTP request parsing)
    └── proto_fsm.wasm     (protocol state machines)
```

Security-critical parsing code is written in Rust, compiled to `.wasm`, and executed inside an interpreter-mode WASM runtime embedded in the Jerboa binary. The Chez/Jerboa layer handles orchestration, policy evaluation, and configuration.

### WASM Runtime Options

| Runtime | Binary overhead | Mode | Gadgets in runtime | Best for |
|---------|----------------|------|-------------------|----------|
| **wasm3** | ~100KB static | Interpreter | Near-zero (tiny loop) | Maximum minimality |
| **WAMR** | ~50-85KB | Interpreter | Near-zero | Embedded/IoT |
| **wasmi** | ~2-3MB as Rust lib | Interpreter | Near-zero | Pure Rust, integrates with jerboa-native-rs |
| **Wasmtime** | ~15-20MB | JIT (Cranelift) | Some (JIT code) | Full WASI, best tooling |

**Key insight**: Interpreter-mode runtimes generate **zero native code at runtime**. The entire attack surface is the statically-compiled interpreter loop. A wasm3 interpreter is ~3,000 lines of C. Compare that to the millions of gadget-contributing instructions in Chez's runtime.

### Integration with jerboa-native-rs

Add wasmi as a dependency in `jerboa-native-rs/Cargo.toml`. Expose FFI functions:

```rust
#[no_mangle]
pub extern "C" fn jerboa_wasm_load(module_bytes: *const u8, len: usize) -> i32;

#[no_mangle]
pub extern "C" fn jerboa_wasm_call(
    func_name: *const u8, name_len: usize,
    input: *const u8, input_len: usize,
    output: *mut u8, output_len: usize,
    actual_len: *mut usize
) -> i32;
```

Scheme code calls through `foreign-procedure`:

```scheme
(define wasm-call
  (foreign-procedure "jerboa_wasm_call" (string int u8* int u8* int void*) int))
```

### Performance

Interpreter-mode WASM is 10-100x slower than native. For a DNS server, the bottleneck is network I/O, not parsing compute. A DNS response parser running in wasm3 at 1/50th native speed still finishes in microseconds — acceptable for security-critical paths.

### Existing WASM Infrastructure

Jerboa already has embryonic WASM support in `lib/jerboa/wasm/`:
- `codegen.sls` — Compile restricted Scheme subset to WASM binary (i32-only, no closures)
- `runtime.sls` — Stack-based WASM interpreter for testing
- `format.sls` — LEB128 encoding, section parsing, binary format primitives

This is currently educational/testing-grade but the format layer is real and could serve as a foundation.

---

## Path 3: Minimal Interpreter Binary

**Effort**: Months. **Impact**: Smallest possible footprint (~500KB).

For tools where binary size and gadget count are the absolute priority, replace the Chez runtime entirely with a minimal Scheme interpreter.

### s7 Scheme

- Single C file, ~35,000 lines. Compiles to **~400KB**.
- Interpreter-only: no JIT means no W+X pages, no dynamically generated gadgets.
- Full access to C hardening flags: `-fcf-protection=full`, `-fstack-protector-strong`, etc.
- R7RS-ish with extensions. Not Chez-compatible.
- ~50-100x slower than Chez for compute-heavy code. Acceptable for I/O-bound servers.

### Architecture

```
Static binary (~500KB-1MB)
├── s7 Scheme interpreter (400KB, fully hardened C)
├── Rust native lib (crypto, TLS, WASM runtime)
└── Application logic in s7 Scheme
```

### Tradeoff

This means **leaving Jerboa** for those specific tools. You'd be writing a different program in a different Scheme dialect. The Jerboa prelude, reader syntax, defstruct/defclass/defmethod, capability system, effects, contracts — none of it carries over.

This path only makes sense if you're willing to write the security tools as standalone projects that don't depend on Jerboa's ecosystem. Jerboa could still be used for development, prototyping, and testing, with the production binary being a separate s7-based build.

---

## Approaches NOT Worth Pursuing

### Scheme-to-Rust Transpilation

Fundamental type system mismatch makes automated translation impossible:
- **Continuations**: Chez's `call/cc` captures the native stack. Rust has no equivalent.
- **Garbage collection**: Scheme values are GC-managed. Rust uses ownership. No mechanical translation exists.
- **Dynamic typing**: Every Scheme value is a tagged pointer. Translating to Rust means `enum Value { Int(i64), String(Rc<String>), ... }` everywhere, losing Rust's type safety benefits.

No tool exists for this. Building one would take years. The few academic efforts (Ribbit Scheme) produce minimal subsets lacking Jerboa's features.

### Alternative Scheme Compilers (Chicken, Gambit)

Chicken compiles Scheme to C via Cheney-on-the-MTA. A minimal program produces a ~400KB binary. Gambit is similar but larger (~1-2MB). Both give full access to C hardening flags.

**What you lose**: Chez's native-code performance (3-10x slower), the entire Jerboa prelude, all MCP tooling, reader syntax extensions, defstruct/defclass/defmethod, the capability system, taint tracking, effects, contracts.

Not worth it unless starting from scratch.

### Full LTO Across Chez + Rust

Not technically feasible. Chez's `libkernel.a` is pre-built; LTO would require recompiling Chez with `-flto`. Even then, cross-language LTO (C + Rust) is not supported by current toolchains for this combination.

---

## Recommended Architecture

### Target: Self-Sandboxing Static PIE Binary

The architecture adapts to platform capabilities. WASM-sandboxed parsing is the
universal constant; OS-level confinement and hardware enforcement vary.

```
+--------------------------------------------------+
|  Static PIE ELF (~8MB)                           |
|  Full ASLR + platform-specific HW enforcement    |
|                                                   |
|  +-----------+  +-----------+  +---------------+ |
|  | Chez      |  | Rust      |  | wasmi WASM    | |
|  | Runtime   |  | Native    |  | Interpreter   | |
|  |           |  | (ring,    |  | (DNS parser   | |
|  |           |  |  rustls)  |  |  in sandboxed | |
|  |           |  |           |  |  WASM module) | |
|  +-----------+  +-----------+  +---------------+ |
|                                                   |
|  Jerboa orchestration layer:                      |
|  - Capability-gated network I/O                   |
|  - Policy evaluation (who queries what)           |
|  - Audit logging (hash-chain)                     |
|  - Configuration via Jerboa DSL                   |
|                                                   |
|  Post-init self-sandbox (platform-dependent):     |
|  +---------------------+------------------------+ |
|  |      Linux          |      FreeBSD           | |
|  +---------------------+------------------------+ |
|  | CET/SHSTK (hw ROP)  | ARM PAC+BTI (arm64)   | |
|  | seccomp (syscall     | Capsicum (resource     | |
|  |   filter, block      |   confinement, block   | |
|  |   mprotect(EXEC))    |   path-based access)   | |
|  | Landlock (fs paths)  | PROTMAX (post-init,    | |
|  | Namespaces (PID,     |   block mprotect       | |
|  |   mount, network)    |   escalation)          | |
|  | Anti-debug (ptrace)  | Anti-debug (ptrace)    | |
|  | Integrity check      | Integrity check        | |
|  +---------------------+------------------------+ |
+--------------------------------------------------+
```

### Defense Layers by Platform

**Linux (x86_64 with CET)** — Six independent layers:

1. **ASLR** (~22 bits entropy) — Information leak to discover gadget addresses
2. **CET/SHSTK** — Hardware bypass to use corrupted return addresses
3. **WASM sandbox** — Runtime bug to escape parser isolation
4. **seccomp** — Kernel exploit to make blocked syscalls (including `mprotect(EXEC)`)
5. **Namespaces** — Kernel exploit to escape PID/mount/network isolation
6. **Landlock** — Kernel exploit to access blocked filesystem paths

**FreeBSD (x86_64)** — Five layers, no hardware ROP protection:

1. **ASLR** (~14 bits entropy) — Information leak (lower bar than Linux)
2. **WASM sandbox** — Runtime bug to escape parser isolation (**primary ROP defense**)
3. **Capsicum** — Kernel exploit to escape capability mode
4. **PROTMAX** — Kernel exploit or pre-PROTMAX timing to escalate memory protections
5. **Anti-debug + integrity** — Bypass tracing detection and hash verification

**FreeBSD (arm64)** — Six layers, with hardware enforcement:

1. **ASLR** — Information leak to discover gadget addresses
2. **ARM PAC** — Hardware bypass to forge signed return addresses
3. **ARM BTI** — Hardware bypass to jump to non-BTI-landing-pad instructions
4. **WASM sandbox** — Runtime bug to escape parser isolation
5. **Capsicum** — Kernel exploit to escape capability mode
6. **PROTMAX** — Kernel exploit to escalate memory protections

**Key insight**: On FreeBSD x86_64, the WASM sandbox is not defense-in-depth — it is the
**primary** control-flow integrity mechanism. This elevates Path 2 from "nice to have" to
"essential" on that platform. On FreeBSD arm64, PAC+BTI restore hardware-level protection,
making it the strongest FreeBSD deployment target.

### Platform Feature Matrix

| Defense | Linux x86_64 | FreeBSD x86_64 | FreeBSD arm64 |
|---------|-------------|----------------|---------------|
| ASLR | High entropy | Low entropy | Low entropy |
| HW return-addr protection | CET/SHSTK | **None** | ARM PAC |
| HW indirect-branch protection | CET/IBT (needs Chez patch) | **None** | ARM BTI |
| Syscall filtering | seccomp-bpf | **None** (Capsicum is resource-based) | **None** |
| Block mprotect(EXEC) | seccomp | PROTMAX (post-init only) | PROTMAX (post-init only) |
| Resource confinement | Landlock | Capsicum | Capsicum |
| Process isolation | Namespaces | **None** (jails require root) | **None** |
| WASM parser sandbox | Yes | Yes | Yes |
| Anti-debug | ptrace self-trace | ptrace self-trace | ptrace self-trace |
| Compiler hardening (CFLAGS) | Full | Full | Full |

### Implementation Priority

Priority is adjusted for cross-platform impact. Items that benefit both Linux and FreeBSD
are ranked higher than Linux-only features.

| Phase | Work | Effort | Linux | FreeBSD | Notes |
|-------|------|--------|-------|---------|-------|
| **1a** | Embed wasmi in jerboa-native-rs | Week | Defense-in-depth | **Primary ROP defense** | Cross-platform, highest priority |
| **1b** | Write DNS parser in Rust → WASM | Week | Defense-in-depth | **Primary ROP defense** | Cross-platform |
| **1c** | Switch musl build to static PIE | Hours | Full ASLR | Full ASLR | Cross-platform |
| **1d** | Rebuild Chez with hardening CFLAGS | Days | All flags | All except CET | Cross-platform (flag subset varies) |
| **2a** | Enable CET/SHSTK in Chez build | Days | **Defeats ROP** | N/A | Linux-only, highest HW impact |
| **2b** | Add namespace isolation to cage | Days | Micro-VM containment | N/A | Linux-only |
| **2c** | Enable PROTMAX post-init on FreeBSD | Days | N/A | Block mprotect escalation | FreeBSD-only, requires post-JIT sequencing |
| **2d** | ARM PAC+BTI build target | Days | N/A | HW ROP defense (arm64) | FreeBSD arm64 only |
| **3a** | Patch Chez codegen for ENDBR64 | Weeks | Full CET (IBT+SHSTK) | N/A | Linux-only, enables IBT |
| **3b** | Encrypted boot files | Weeks | Resist static analysis | Resist static analysis | Cross-platform |
| **3c** | Firecracker deployment wrapper | Weeks | VM-level isolation | N/A (bhyve possible) | Linux-primary |
| **3d** | HardenedBSD deployment target | Days | N/A | Strict W^X, SEGVGUARD | FreeBSD fork, maximum hardening |
