# Binary Hardening Guide

Techniques for producing Jerboa binaries that resist tampering, debugging, and reverse engineering. All techniques target the single-binary ELF described in [single-binary.md](single-binary.md) and leverage the existing Rust native backend (`jerboa-native-rs`).

## Implementation Status

The following Rust modules and Scheme wrappers are **implemented and tested**:

| Module | Rust | Scheme | Tests |
|--------|------|--------|-------|
| Anti-debug (ptrace, TracerPid, LD_PRELOAD, timing) | `antidebug.rs` | `(std os antidebug)` | 4/4 pass |
| seccomp-bpf filtering | `seccomp.rs` | `(std os seccomp)` | 2/2 pass |
| Integrity (SHA-256 self-hash, Ed25519 verify, file hash) | `integrity.rs` | `(std os integrity)` | 13/13 pass |
| Landlock sandboxing | `landlock.rs` | `(std os landlock-native)` | existing |
| Secure memory | `secure_mem.rs` | `(std crypto secure-mem)` | existing |

Sections 7 (Encrypted Boot Files) and 12 (Build Pipeline) are design-only — they require a C main entry point (e.g., `jsh-main.c`) which lives in the consuming project (jerboa-shell), not this repo.

---

## Table of Contents

1. [Threat Model](#1-threat-model)
2. [Ed25519 Code Signing](#2-ed25519-code-signing)
3. [Self-Integrity Check (SHA-256)](#3-self-integrity-check-sha-256)
4. [Anti-Debug: ptrace Self-Trace](#4-anti-debug-ptrace-self-trace)
5. [Anti-Debug: TracerPid and Environment Checks](#5-anti-debug-tracerpid-and-environment-checks)
6. [Anti-Debug: Timing Checks](#6-anti-debug-timing-checks)
7. [Encrypted Boot Files](#7-encrypted-boot-files)
8. [Symbol Stripping and Obfuscation](#8-symbol-stripping-and-obfuscation)
9. [Landlock Self-Sandboxing](#9-landlock-self-sandboxing)
10. [seccomp Post-Init Filter](#10-seccomp-post-init-filter)
11. [Secure Memory for Keys](#11-secure-memory-for-keys)
12. [Build Pipeline Integration](#12-build-pipeline-integration)
13. [Comparison with Other Languages](#13-comparison-with-other-languages)
14. [Limitations and Honest Caveats](#14-limitations-and-honest-caveats)

---

## 1. Threat Model

These protections target:

- **Binary modification**: An attacker patches the ELF to change behavior (bypass auth, remove license checks, inject code).
- **Dynamic analysis**: An attacker attaches gdb/strace/ltrace to inspect runtime state, extract keys, or trace control flow.
- **Static analysis**: An attacker runs `strings`, `objdump`, or Ghidra on the binary to understand the Scheme code embedded in boot files.
- **Library injection**: An attacker uses `LD_PRELOAD` or `LD_LIBRARY_PATH` to intercept function calls.

These protections do NOT target:

- Kernel-level attackers (root with kernel module access).
- Hardware-level attacks (cold boot, bus snooping).
- Side-channel attacks on the crypto itself (ring already handles that).

No userspace binary can fully protect itself from a sufficiently privileged attacker. The goal is to raise the cost of attack above the value of what's protected.

---

## 2. Ed25519 Code Signing

The strongest tamper-detection mechanism. An attacker who modifies the binary cannot forge a valid signature without the private key.

### How It Works

1. Build the binary normally.
2. Hash the ELF (excluding the signature region).
3. Sign the hash with an Ed25519 private key (kept offline).
4. Append or embed the 64-byte signature.
5. At startup, verify the signature using the embedded public key.

### Rust Implementation

Add to `jerboa-native-rs/src/integrity.rs`:

```rust
use ring::signature::{Ed25519KeyPair, UnparsedPublicKey, ED25519};
use std::fs;

/// Verify the binary's Ed25519 signature.
/// Returns 1 if valid, 0 if invalid, -1 on error.
#[no_mangle]
pub extern "C" fn jerboa_verify_self_signature(
    pubkey: *const u8,      // 32-byte Ed25519 public key
    sig_offset: u64,        // byte offset where 64-byte signature lives
) -> i32 {
    // Read /proc/self/exe (always resolves to the real binary)
    let binary = match fs::read("/proc/self/exe") {
        Ok(b) => b,
        Err(_) => return -1,
    };

    let sig_off = sig_offset as usize;
    if sig_off + 64 > binary.len() { return -1; }

    // Extract signature, then zero it for verification
    let signature = binary[sig_off..sig_off + 64].to_vec();
    let mut message = binary;
    // Zero out the signature region (hash what the binary looked like before signing)
    for b in &mut message[sig_off..sig_off + 64] {
        *b = 0;
    }

    let pk = unsafe { std::slice::from_raw_parts(pubkey, 32) };
    let verify_key = UnparsedPublicKey::new(&ED25519, pk);

    match verify_key.verify(&message, &signature) {
        Ok(()) => 1,
        Err(_) => 0,
    }
}
```

### C Main Integration

In `jsh-main.c`, before `Sbuild_heap`:

```c
// Embedded at build time by the signing script
static const unsigned char ed25519_pubkey[32] = { /* ... */ };
#define SIG_OFFSET 0x00000000ULL  // patched by signing script

extern int jerboa_verify_self_signature(const unsigned char *pubkey, uint64_t sig_offset);

int main(int argc, char *argv[]) {
    if (jerboa_verify_self_signature(ed25519_pubkey, SIG_OFFSET) != 1) {
        write(2, "integrity check failed\n", 23);
        _exit(1);
    }
    // ... normal Chez init ...
}
```

### Build-Time Signing Script

```bash
#!/bin/bash
# sign-binary.sh — run after linking jsh
BINARY="$1"
PRIVKEY="$2"  # Ed25519 private key (keep offline)

# 1. Find the signature slot (64 zero bytes at a known symbol)
SIG_OFFSET=$(nm "$BINARY" | grep '__jerboa_signature' | awk '{print "0x"$1}')

# 2. Zero the slot, hash, sign
dd if=/dev/zero of="$BINARY" bs=1 count=64 seek=$((SIG_OFFSET)) conv=notrunc
HASH=$(sha256sum "$BINARY" | awk '{print $1}')

# 3. Sign with Ed25519 (via a small Rust tool or openssl)
SIGNATURE=$(jerboa-sign --key "$PRIVKEY" --hash "$HASH")

# 4. Write signature into the slot
echo -n "$SIGNATURE" | xxd -r -p | dd of="$BINARY" bs=1 count=64 seek=$((SIG_OFFSET)) conv=notrunc
```

### Providing the Signature Slot

In `jsh-main.c`, reserve a known location:

```c
// 64-byte signature slot — zeroed at compile time, filled by signing script
__attribute__((section(".jerboa_sig")))
volatile const unsigned char __jerboa_signature[64] = {0};
```

---

## 3. Self-Integrity Check (SHA-256)

A simpler alternative to full code signing. Less secure (an attacker can recompute the hash), but useful as a quick sanity check or as a complement to signing.

### The Bootstrapping Problem

You cannot embed a SHA-256 hash of a file inside that same file. Three solutions:

**Option A: Hash with exclusion zone**

Hash everything except a known 32-byte region. The build script writes the hash into that region post-link.

```c
// Reserve the hash slot
__attribute__((section(".jerboa_hash")))
volatile const unsigned char __jerboa_expected_hash[32] = {0};

static int check_self_hash(void) {
    // Read /proc/self/exe
    int fd = open("/proc/self/exe", O_RDONLY);
    // ... read entire file into buffer ...

    // Zero out the hash slot before hashing
    memset(buffer + hash_slot_offset, 0, 32);

    // SHA-256 the modified buffer
    unsigned char actual[32];
    jerboa_sha256(buffer, file_size, actual, 32);

    // Compare
    return jerboa_timing_safe_equal(actual, 32,
        (const unsigned char *)__jerboa_expected_hash, 32);
}
```

**Option B: ELF segment hashing**

Hash only `.text` + `.rodata` sections (the code and constant data). This is more robust against tools that modify ELF headers or debug sections.

```c
#include <elf.h>

static int check_code_segments(void) {
    // Parse ELF headers from /proc/self/exe
    // Find PT_LOAD segments with PF_X (executable) flag
    // Hash those segments only
    // Compare against embedded expected hash
}
```

**Option C: Detached signature file**

Store the hash in a separate `jsh.sig` file. Simplest to implement but requires distributing two files.

### Build Script for Option A

```bash
#!/bin/bash
BINARY="$1"
HASH_OFFSET=$(nm "$BINARY" | grep '__jerboa_expected_hash' | awk '{print "0x"$1}')

# Zero the slot
dd if=/dev/zero of="$BINARY" bs=1 count=32 seek=$((HASH_OFFSET)) conv=notrunc

# Hash the binary with zeroed slot
HASH=$(sha256sum "$BINARY" | cut -d' ' -f1)

# Write hash into slot
echo -n "$HASH" | xxd -r -p | dd of="$BINARY" bs=1 count=32 seek=$((HASH_OFFSET)) conv=notrunc
```

---

## 4. Anti-Debug: ptrace Self-Trace

A process can only have one tracer. By tracing yourself, you prevent gdb/strace from attaching.

### Implementation

In `jsh-main.c`, as the very first thing in `main()`:

```c
#include <sys/ptrace.h>

static void anti_debug_ptrace(void) {
    if (ptrace(PTRACE_TRACEME, 0, NULL, NULL) == -1) {
        // PTRACE_TRACEME failed — something is already tracing us
        _exit(1);
    }
}
```

### Hardening the Check

A single ptrace call is trivially patchable (NOP out the branch). Make it harder:

```c
static void anti_debug_ptrace(void) {
    // Call from multiple places with different consequences
    volatile int result = ptrace(PTRACE_TRACEME, 0, NULL, NULL);

    // Don't branch immediately — use the result later
    // to derive a value needed for decryption (see section 7)
    if (result == -1) {
        // Corrupt a key byte — decryption will fail silently later
        // rather than giving an obvious "debugger detected" message
        boot_key[0] ^= 0xFF;
    }
}
```

This ties the anti-debug check to the decryption path. An attacker who patches out the check still gets garbage when decrypting boot files.

---

## 5. Anti-Debug: TracerPid and Environment Checks

Complementary checks that catch different attack vectors than ptrace.

### TracerPid

```c
static int check_tracer_pid(void) {
    FILE *f = fopen("/proc/self/status", "r");
    if (!f) return 0;  // can't check, proceed cautiously

    char line[256];
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "TracerPid:", 10) == 0) {
            long pid = strtol(line + 10, NULL, 10);
            fclose(f);
            return pid != 0;  // nonzero = debugger attached
        }
    }
    fclose(f);
    return 0;
}
```

### LD_PRELOAD Detection

```c
static int check_ld_preload(void) {
    // Check environment
    if (getenv("LD_PRELOAD") != NULL) return 1;

    // Also check /proc/self/environ in case env was cleared after load
    int fd = open("/proc/self/environ", O_RDONLY);
    if (fd < 0) return 0;
    char buf[4096];
    ssize_t n = read(fd, buf, sizeof(buf));
    close(fd);

    // Search for LD_PRELOAD in the raw environ block
    for (ssize_t i = 0; i < n - 10; i++) {
        if (memcmp(buf + i, "LD_PRELOAD", 10) == 0) return 1;
    }
    return 0;
}
```

### Breakpoint Detection

Check for `INT3` (0xCC) instructions at key function entry points:

```c
static int check_breakpoints(void) {
    // Check our own function entry points for software breakpoints
    unsigned char *check_fn = (unsigned char *)&check_self_hash;
    unsigned char *main_fn = (unsigned char *)&main;

    if (*check_fn == 0xCC || *main_fn == 0xCC) return 1;
    return 0;
}
```

---

## 6. Anti-Debug: Timing Checks

Debuggers slow execution. Measure critical sections and abort if they take too long.

```c
#include <time.h>

static void timed_check(void (*fn)(void), long max_ns) {
    struct timespec t1, t2;
    clock_gettime(CLOCK_MONOTONIC, &t1);
    fn();
    clock_gettime(CLOCK_MONOTONIC, &t2);

    long elapsed = (t2.tv_sec - t1.tv_sec) * 1000000000L
                 + (t2.tv_nsec - t1.tv_nsec);

    if (elapsed > max_ns) {
        _exit(1);
    }
}

// Usage: integrity check should complete in <100ms
timed_check(check_self_hash, 100000000L);
```

### Continuous Background Check

After Chez is initialized, spawn a thread that periodically re-checks:

```c
static void *watchdog_thread(void *arg) {
    while (1) {
        usleep(5000000);  // every 5 seconds
        if (check_tracer_pid()) _exit(1);
        if (check_breakpoints()) _exit(1);
    }
    return NULL;
}

// After Sbuild_heap, before Sscheme_script:
pthread_t watchdog;
pthread_create(&watchdog, NULL, watchdog_thread, NULL);
```

---

## 7. Encrypted Boot Files

This is the highest-value technique unique to Jerboa's architecture. Boot files contain all Scheme source in compiled form — encrypting them prevents static analysis.

### Architecture

```
Build time:
  petite.boot ──→ AES-256-GCM encrypt ──→ petite_boot_enc.h (ciphertext + nonce + tag)
  scheme.boot ──→ AES-256-GCM encrypt ──→ scheme_boot_enc.h
  jsh.boot    ──→ AES-256-GCM encrypt ──→ jsh_boot_enc.h

Runtime:
  Read encrypted arrays from .rodata
  ──→ Derive decryption key
  ──→ AES-256-GCM decrypt into mmap'd memory
  ──→ Sregister_boot_file_bytes(decrypted)
  ──→ Wipe decrypted copy after Chez loads it
```

### Key Derivation

The decryption key should not be a single static value (too easy to extract). Combine multiple sources:

```c
static void derive_boot_key(unsigned char key[32]) {
    unsigned char material[128];
    int offset = 0;

    // Component 1: Embedded key fragment (32 bytes, split across functions)
    memcpy(material + offset, key_fragment_1, 16); offset += 16;
    memcpy(material + offset, key_fragment_2, 16); offset += 16;

    // Component 2: Binary's own code hash (ties key to unmodified binary)
    unsigned char code_hash[32];
    hash_text_section(code_hash);
    memcpy(material + offset, code_hash, 32); offset += 32;

    // Component 3: Compile-time constant (changes per build)
    memcpy(material + offset, build_nonce, 16); offset += 16;

    // HKDF-SHA256 to derive final key
    jerboa_sha256(material, offset, key, 32);

    // Wipe intermediates
    explicit_bzero(material, sizeof(material));
    explicit_bzero(code_hash, sizeof(code_hash));
}
```

Component 2 is the critical trick: the key depends on the binary's own `.text` section hash. If an attacker patches the anti-debug checks, the `.text` hash changes, the derived key changes, and decryption fails. This creates a cryptographic binding between the code integrity and the ability to run.

### Decryption at Startup

```c
static void *decrypt_boot(const unsigned char *enc_data, unsigned int enc_size,
                          const unsigned char *nonce, unsigned int *out_size) {
    unsigned char key[32];
    derive_boot_key(key);

    // Allocate via secure memory (mlock'd, no core dump, no fork)
    unsigned char *output = (unsigned char *)jerboa_secure_alloc(enc_size);

    size_t pt_len = 0;
    int rc = jerboa_aead_open(
        key, 32,
        nonce, 12,
        enc_data, enc_size,
        NULL, 0,           // no AAD
        output, enc_size,
        &pt_len
    );

    explicit_bzero(key, 32);

    if (rc != 0) {
        jerboa_secure_free(output, enc_size);
        return NULL;
    }

    *out_size = (unsigned int)pt_len;
    return output;
}
```

### Build-Time Encryption Script

```bash
#!/bin/bash
# encrypt-boots.sh — encrypts boot files into C headers
KEY=$(jerboa-keygen --derive)  # deterministic from signing key + build ID

for BOOT in petite.boot scheme.boot jsh.boot; do
    NAME=$(echo "$BOOT" | tr '.' '_' | tr '-' '_')
    NONCE=$(head -c 12 /dev/urandom | xxd -p)

    # Encrypt with AES-256-GCM
    jerboa-encrypt --key "$KEY" --nonce "$NONCE" --input "$BOOT" --output "${NAME}_enc.h" \
        --array-name "${NAME}_enc_data" --nonce-name "${NAME}_nonce"
done
```

### Wiping After Load

After Chez has loaded the boot files into its heap, wipe the decrypted copies:

```c
Sregister_boot_file_bytes("petite", decrypted_petite, petite_size);
Sregister_boot_file_bytes("scheme", decrypted_scheme, scheme_size);
Sregister_boot_file_bytes("jsh",    decrypted_jsh,    jsh_size);

Sbuild_heap(NULL, NULL);

// Chez has copied what it needs — wipe our copies
jerboa_secure_free(decrypted_petite, petite_alloc_size);
jerboa_secure_free(decrypted_scheme, scheme_alloc_size);
jerboa_secure_free(decrypted_jsh,    jsh_alloc_size);
```

---

## 8. Symbol Stripping and Obfuscation

### Stripping

The Rust backend already strips in release mode (`strip = true` in `Cargo.toml`). For the final ELF:

```makefile
jsh: jsh-main.o ffi-shim.o
	gcc -rdynamic -o $@ $^ -lkernel -llz4 -lz -lm -ldl -lpthread -luuid -lncurses
	strip --strip-all $@
	# Remove section headers (prevents section-based disassembly)
	objcopy --strip-section-headers $@
```

### Chez Symbol Obfuscation

Boot files contain Scheme symbol names as strings. Even encrypted, they'll be visible in memory at runtime. Mitigations:

1. **Obfuscate link files**: Use `gerbil_obfuscate_link_file` to hash symbol names in Gambit-style link files before compilation.
2. **Minimize exports**: Only export what's strictly needed from each module. Unexported symbols can be renamed by the compiler.
3. **String encryption**: For sensitive string literals in the Scheme code, encrypt them and decrypt on first use (a `(define-lazy-string ...)` macro).

### Removing Build Paths

GCC and Chez embed source paths. Strip them:

```makefile
# GCC: use -ffile-prefix-map to replace paths
CFLAGS += -ffile-prefix-map=$(PWD)=.

# Chez: boot files may contain source paths
# Use (generate-inspector-information #f) before compiling
# This removes source location info from compiled code
```

---

## 9. Landlock Self-Sandboxing

Jerboa already has Landlock support via `jerboa-native-rs/src/landlock.rs`. Use it to restrict the binary's own capabilities after initialization.

### Post-Init Lockdown

After the binary has loaded all shared libraries and opened all needed files:

```scheme
;; In the Scheme entry point, after initialization
(landlock-restrict!
  ;; Only allow reading from specific directories
  (list
    (cons "/etc"     LANDLOCK_ACCESS_FS_READ_FILE)
    (cons "/tmp"     (bitwise-ior LANDLOCK_ACCESS_FS_READ_FILE
                                  LANDLOCK_ACCESS_FS_WRITE_FILE))
    (cons user-home  (bitwise-ior LANDLOCK_ACCESS_FS_READ_FILE
                                  LANDLOCK_ACCESS_FS_WRITE_FILE)))
  ;; No LANDLOCK_ACCESS_FS_EXECUTE for any path
  ;; This prevents loading new shared libraries (blocks LD_PRELOAD attacks)
)
```

Key restrictions:

- **No execute access**: Prevents loading new `.so` files after init, blocking `dlopen`-based injection.
- **No write to binary's directory**: Prevents replacing the binary or its libraries.
- **Minimal filesystem surface**: Only directories the application actually needs.

---

## 10. seccomp Post-Init Filter

After initialization, install a BPF filter that blocks dangerous syscalls at the kernel level. Even if all userspace checks are bypassed, seccomp is enforced by the kernel.

### Implementation

Add to `jerboa-native-rs/src/seccomp.rs`:

```rust
use libc::{self, c_int, c_ulong};

// BPF filter that blocks debugging-related syscalls
#[no_mangle]
pub extern "C" fn jerboa_seccomp_lock() -> i32 {
    // Block:
    //   ptrace          (prevents debugger attach)
    //   process_vm_readv/writev (prevents memory inspection)
    //   personality     (prevents READ_IMPLIES_EXEC)
    //   memfd_create    (prevents code injection via memfd)

    // Allow everything else (whitelist would be safer
    // but requires enumerating all needed syscalls)

    // ... BPF program assembly ...
    // Uses prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog)
}
```

### Considerations

- Install seccomp **after** all initialization is complete (library loading, file opens, etc.).
- Use `SECCOMP_FILTER_FLAG_TSYNC` to apply to all threads.
- Be careful not to block syscalls that Chez Scheme's GC or threading needs.
- Test thoroughly — a blocked syscall kills the process with SIGSYS.

---

## 11. Secure Memory for Keys

The Rust backend already provides `jerboa_secure_alloc` / `jerboa_secure_free` in `secure_mem.rs`. Use these for all key material:

- Guard pages on both sides (SIGSEGV on buffer overflow/underflow)
- `mlock` (never swapped to disk)
- `MADV_DONTDUMP` (excluded from core dumps)
- `MADV_DONTFORK` (not inherited by child processes)
- `explicit_bzero` on free (guaranteed not optimized away)

### Usage for Hardening Keys

```c
// Allocate key in secure memory
unsigned char *key = jerboa_secure_alloc(32);
derive_boot_key(key);

// Use key for decryption ...

// Wipe immediately after use
jerboa_secure_free(key, 32);
```

---

## 12. Build Pipeline Integration

The hardened build extends the existing pipeline from [single-binary.md](single-binary.md):

```
Step 1:  gcc -> libjsh-ffi.so
Step 2:  Jerboa -> src/jsh/*.sls
Step 3:  Chez compile-program -> jsh.so
Step 4:  make-boot-file -> jsh.boot (libs-only)
Step 5:  encrypt-boots.sh -> *_enc.h          [NEW]
Step 6:  file->c-header (program .so only)
Step 7:  gcc -> jsh-main.o (with encrypted boot arrays)
Step 8:  gcc -> jsh (link everything)
Step 9:  strip + objcopy                       [NEW]
Step 10: sign-binary.sh -> patch signature     [NEW]
Step 11: verify-binary.sh -> smoke test        [NEW]
```

### Makefile Targets

```makefile
.PHONY: harden sign verify

harden: jsh
	strip --strip-all jsh
	objcopy --strip-section-headers jsh
	@echo "Stripped."

sign: harden
	./scripts/sign-binary.sh jsh $(ED25519_PRIVKEY)
	@echo "Signed."

verify: sign
	./jsh --self-test  # runs internal integrity check
	@echo "Verified."
```

---

## 13. Comparison with Other Languages

| Feature | Go | Rust | .NET NativeAOT | Jerboa |
|---|---|---|---|---|
| Static binary | Yes | Yes | Yes | Yes |
| Code signing | External (cosign) | External | Authenticode | **Ed25519 built-in** |
| Self-hash check | Manual | Manual | Strong-name (limited) | **ring SHA-256** |
| Anti-debug | Manual | Manual | .NET obfuscators | **C main + seccomp** |
| Code encryption | No | No | .NET Reactor (3rd party) | **Encrypted boot files** |
| Obfuscation | garble | None standard | ConfuserEx (3rd party) | Mangled symbols + encryption |
| Sandboxing | None built-in | None built-in | None built-in | **Landlock + seccomp** |
| Secure memory | Manual | zeroize crate | None | **mlock + guard pages** |
| Anti-LD_PRELOAD | Manual | Manual | N/A | **Landlock FS_EXECUTE deny** |

Jerboa's architecture — embedding compiled Scheme in encrypted boot files, loaded via memfd into a self-verifying binary with kernel-enforced sandboxing — provides layered protection that most language runtimes cannot match without third-party tools.

---

## 14. Limitations and Honest Caveats

**What these protections do NOT prevent:**

- **Root attacker**: A root user can bypass ptrace restrictions via `/proc/sys/kernel/yama/ptrace_scope=0`, detach seccomp filters with `PTRACE_SEIZE`, and read process memory directly.
- **Kernel module**: A custom kernel module can read any process memory, intercept any syscall, and modify any page table.
- **Binary patching by a skilled reverse engineer**: All userspace checks can be located and NOPed out. The encrypted boot files raise the cost significantly (the attacker must also extract the key), but a determined attacker with enough time can do it.
- **Memory forensics**: After decryption, boot file contents live in Chez Scheme's heap. A memory dump at the right moment captures them. Secure memory helps for keys but the full Scheme heap is not locked.
- **Emulation**: An attacker can run the binary in QEMU with full introspection.

**The goal is defense in depth**: each layer forces the attacker to solve a different problem. Code signing means they can't just patch bytes. Anti-debug means they can't just attach gdb. Encrypted boot files mean they can't just run `strings`. seccomp means they can't just LD_PRELOAD. No single layer is unbreakable, but together they make the binary significantly harder to tamper with than an unprotected ELF.

**Cost-benefit**: Implement Ed25519 signing and anti-ptrace first (hours of work, blocks casual attackers). Add boot file encryption next (days of work, blocks intermediate attackers). Add seccomp last (needs careful testing, blocks sophisticated attackers).
