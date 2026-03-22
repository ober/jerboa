# Hardening Jerboa Binaries Against Reverse Engineering

Practical guide for reducing information leakage from statically-linked Chez
Scheme binaries. Based on reverse engineering `jsh`, reviewing Chez Scheme's
compiler source (`s/strip.ss`, `s/compile.ss`, `s/fasl.ss`, `s/syntax.ss`),
and mapping every finding to Jerboa's build pipeline.

---

## What Leaks Today

A stock `jsh` build (20 MB, unstripped) exposes:

| Category | Count | Source |
|----------|-------|--------|
| Home directory paths | 412 | Chez SFDs, Rust panics, C `__FILE__` |
| Sibling project paths | ~30 | gherkin, cargo registry |
| ELF symbols | 21,948 | `.symtab` (not stripped) |
| DWARF debug sections | 13 | `.debug_*` |
| Scheme symbol names | ~8,700 | FASL interned symbols |
| FFI function names | 77+ | `Sforeign_symbol` registration strings |
| Compiler versions | 4 | `.comment` section |
| Crate versions | ~20 | Rust panic paths |
| OpenSSL/SQLite symbols | ~2,500 | Static library globals |

After `strip -s`: ELF symbols drop to 0, debug sections gone, but **388 of
412 path leaks survive** (baked into `.rodata` / FASL data). Stripping alone
solves ~15% of the problem.

---

## Chez Scheme's Built-In Defenses

Chez provides more obfuscation surface than most people realize. These are
the relevant APIs, grouped by what they eliminate.

### Source Path Elimination

Chez records source file paths in **Source File Descriptors** (SFDs), which
are created by the reader via `make-source-file-descriptor` and embedded in
annotations. Three independent mechanisms suppress them:

**1. `generate-procedure-source-information`** (compile-time parameter)

```scheme
(generate-procedure-source-information #f)
```

Prevents source file/line annotations from being attached to procedure
objects at compilation time. This is the most direct control — the data is
never generated.

**2. `current-make-source-object`** (reader-level hook)

```scheme
(current-make-source-object (lambda (sfd bfp efp) #f))
```

The reader calls this hook to create source objects during parsing. Setting
it to return `#f` suppresses source tracking at the earliest possible point
— before any compilation happens. Alternative: return source objects with
sanitized SFDs:

```scheme
(current-make-source-object
  (lambda (sfd bfp efp)
    (make-source-object
      (make-source-file-descriptor "<jerboa>" (source-file-descriptor-checksum sfd))
      bfp efp)))
```

This replaces real paths with `"<jerboa>"` while preserving source positions
(useful for stack traces with line numbers but no file paths).

**3. `strip-fasl-file` with `source-annotations`** (post-compilation)

```scheme
(strip-fasl-file "input.so" "output.so"
  (fasl-strip-options source-annotations))
```

Strips all annotation records from compiled FASL files. This catches anything
that slipped through the compile-time settings.

**4. `compile-to-port` with `sfd #f`** (lowest-level control)

```scheme
(compile-to-port expr output-port #f)  ; third arg = sfd
```

When using the programmatic compilation API, passing `#f` for the SFD
parameter compiles with no source file information at all.

### Debug Metadata Elimination

**5. `generate-inspector-information`**

```scheme
(generate-inspector-information #f)
```

Prevents procedure names, argument names, and free variable names from being
embedded in code objects. Already used in `build-binary` when `release?: #t`
and in `build-musl-binary`. This is the single most impactful parameter for
reducing FASL metadata.

**6. `enable-error-source-expression`**

```scheme
(enable-error-source-expression #f)
```

When `#t` (the default), runtime error messages include the actual source
expression that caused the error. This means source code fragments are
embedded in compiled output for error reporting. Setting to `#f` prevents
this — errors still report the location but not the source text.

**7. `debug-level`**

```scheme
(debug-level 0)
```

Controls how much debug information is retained in continuation frames.
Level 0 = maximum optimization, minimum debug metadata. Level 3 = maximum
debuggability. For release builds, 0.

**8. `strip-fasl-file` with `inspector-source` and `profile-source`**

```scheme
(strip-fasl-file "input.so" "output.so"
  (fasl-strip-options inspector-source profile-source))
```

Post-compilation removal of inspector metadata and profiling source info.

### Compile-Time Information Elimination

**9. `strip-fasl-file` with `compile-time-information`**

```scheme
(strip-fasl-file "input.so" "output.so"
  (fasl-strip-options compile-time-information))
```

Strips visit-time (expand-time) code — macro definitions, syntax
transformers, and cross-library optimization info. Only safe on the **final
boot file** after all compilation is done. Applying this to `.so` files that
other libraries import at expand-time will break compilation.

### Structural Flattening

**10. `compile-whole-program`**

```scheme
(parameterize ([generate-wpo-files #t])
  (compile-program "jsh.ss" "jsh.so"))
(compile-whole-program "jsh.wpo" "jsh-opt.so" #f)
;                                               ^-- libs-visible? = #f
```

Merges all libraries into a single compilation unit. Dead code elimination
removes unused functions. Cross-library inlining merges code across module
boundaries. The `libs-visible?` parameter (third argument) controls whether
library names remain visible — set to `#f` to hide them.

**Caveat**: May break `identifier-syntax` mutable export cells (see
`docs/single-binary.md` section 13). The `docs/optimization.md` benchmarks
show it working in some configurations. Test thoroughly.

**11. `optimize-level 3` + `commonization-level 5`**

```scheme
(optimize-level 3)           ; aggressive inlining, no type checks
(commonization-level 5)      ; merge structurally similar lambdas
(cp0-effort-limit 500)       ; deeper inlining analysis
(cp0-score-limit 50)         ; allow more code growth per inline
```

Level 3 inlines aggressively, removing intermediate procedure boundaries.
Commonization merges similar lambdas into shared templates with different
leaf parameters — this significantly obscures the original program structure.

### FASL Compression

**12. `fasl-compressed`**

```scheme
(fasl-compressed #t)  ; default is #t for compile-file
```

Compressed FASL is not directly readable by `strings`. This is not
encryption — Chez itself can decompress it trivially — but it defeats the
casual `strings binary | grep` analysis that accounts for most real-world
reconnaissance.

### What Chez Does NOT Provide

**Symbol name obfuscation.** Every `define`, `export`, `import`, record-type
name, and library name is stored as a plain interned symbol string in the
FASL. There is no built-in mechanism to rename these. After applying
everything above, the remaining leaks are symbol name strings like
`parse-pipeline`, `execute-redirect`, `(jsh builtins)`.

Closing this gap requires work at the Jerboa level (see below).

---

## Integration with Jerboa's Build Pipeline

The existing `(jerboa build)` and `(jerboa build musl)` libraries already
have hooks for most of these. Here's where each change goes.

### Changes to `build-binary` (lib/jerboa/build.sls)

The current `build-binary` already sets `generate-inspector-information` to
`#f` when `release?` is true. Add the remaining parameters:

```scheme
(define (build-binary source-path output-path . options)
  (let* ([release? (kwarg 'release: options)]
         [harden?  (kwarg 'harden: options)]  ; NEW: full obfuscation mode
         ...)
    (parameterize ([optimize-level (if release? 3 opt-level)]
                   [compile-imported-libraries #t]
                   [generate-inspector-information (not release?)]
                   ;; NEW parameters for hardened builds:
                   [generate-procedure-source-information (not (or release? harden?))]
                   [enable-error-source-expression (not (or release? harden?))]
                   [debug-level (if (or release? harden?) 0 1)]
                   [commonization-level (if harden? 5 0)])
      ...)))
```

### Changes to `build-musl-binary` (lib/jerboa/build/musl.sls)

Same parameter additions in the `parameterize` block at Step 1:

```scheme
(parameterize ([optimize-level opt-level]
               [compile-imported-libraries #t]
               [generate-inspector-information #f]
               ;; NEW:
               [generate-procedure-source-information #f]
               [enable-error-source-expression #f]
               [debug-level 0])
  (compile-program source-path so-path))
```

### New: FASL Stripping Step

Add a post-compilation stripping step between `make-boot-file` and
`file->c-array` in both build functions:

```scheme
(define (strip-for-release fasl-path)
  "Strip all metadata from a compiled FASL file in place."
  (let ([tmp (string-append fasl-path ".stripped")])
    (strip-fasl-file fasl-path tmp
      (fasl-strip-options inspector-source
                          profile-source
                          source-annotations
                          compile-time-information))
    (rename-file tmp fasl-path)))
```

Insert after `make-boot-file`:

```scheme
;; Step 2.5: Strip FASL metadata from boot file
(when (or release? harden?)
  (strip-for-release app-boot))
```

For maximum effect, also strip the individual `.so` files before they go
into the boot file (but omit `compile-time-information` since other modules
may need it during compilation):

```scheme
(when harden?
  (for-each
    (lambda (so-file)
      (let ([tmp (string-append so-file ".stripped")])
        (strip-fasl-file so-file tmp
          (fasl-strip-options inspector-source
                              profile-source
                              source-annotations))
        (rename-file tmp so-file)))
    all-compiled-so-files))
```

### New: Source Path Hook

Install the source-object suppression hook before any compilation begins.
Add to the top of the release build path:

```scheme
(when harden?
  ;; Suppress source file paths at the reader level
  (current-make-source-object (lambda (sfd bfp efp) #f)))
```

Or for stack traces with line numbers but no paths:

```scheme
(when harden?
  (let ([fake-sfd (make-source-file-descriptor "<j>" 0)])
    (current-make-source-object
      (lambda (sfd bfp efp)
        (make-source-object fake-sfd bfp efp)))))
```

### New: C Compiler Flags

In `musl-link-command` and the gcc invocations, add path sanitization:

```scheme
(define (hardened-cflags build-dir)
  (format "-ffile-prefix-map=~a=. -fmacro-prefix-map=~a=."
          build-dir build-dir))
```

And add `objcopy --remove-section=.comment` as a post-link step.

### New: Rust Build Configuration

In `jerboa-native-rs/Cargo.toml`, add a hardened release profile:

```toml
[profile.release]
strip = "symbols"
lto = true
codegen-units = 1
panic = "abort"

[profile.release.build-override]
opt-level = "s"
```

In `jerboa-native-rs/.cargo/config.toml`:

```toml
[build]
rustflags = ["--remap-path-prefix=/home/=."]
```

### New: Linker Version Script

Create `support/hide-symbols.map`:

```
{
  global:
    main;
    static_boot_init;
  local:
    *;
};
```

Add to the link command:

```scheme
(define (hardened-link-flags)
  "-Wl,--version-script=support/hide-symbols.map")
```

This hides all OpenSSL (~2,269), SQLite (~277), FFI (~77), and internal
symbols from the dynamic symbol table. Only `main` and `static_boot_init`
remain visible.

### New: ELF Post-Processing

Add a post-link hardening step:

```scheme
(define (harden-elf binary-path)
  "Post-link binary hardening: strip + remove metadata sections."
  (system (format "strip -s '~a'" binary-path))
  (system (format "objcopy --remove-section=.comment \
                           --remove-section=.note.GNU-stack \
                           --remove-section=.note.gnu.build-id \
                           '~a'" binary-path)))
```

---

## Symbol Name Obfuscation (The Hard Problem)

After applying everything above, the remaining leaks are interned symbol
names in the FASL. These require a source-to-source transformation before
compilation. This is a Jerboa-level feature, not a Chez feature.

### Approach: Pre-Compilation Renaming Pass

Jerboa already has a compilation pipeline that transforms `.ss` files to
`.sls` R6RS libraries (see `docs/single-binary.md` section 6). The
obfuscation pass would slot in between Jerboa compilation and Chez
compilation:

```
.ss files
  → Jerboa compiler → .sls files
  → [NEW] obfuscation pass → .sls files with renamed symbols
  → Chez compile-program → .so files
  → make-boot-file → .boot
  → strip-fasl-file → stripped .boot
  → file->c-array → C byte arrays
  → gcc link → binary
```

### What to Rename

```scheme
(define *chez-builtins*
  ;; ~300 core symbols that must NOT be renamed
  '(car cdr cons list vector lambda define let let* letrec
    if cond case when unless begin set! quote quasiquote
    import export library ...))

(define *ffi-names*
  ;; C ABI names used with foreign-procedure — must match C side
  '("ffi_fork_exec" "ffi_do_waitpid" "jerboa_aead_seal" ...))

(define (should-rename? sym)
  (and (not (memq sym *chez-builtins*))
       (not (member (symbol->string sym) *ffi-names*))))
```

### What to Rename Into

Use deterministic hashing (not random) so builds are reproducible:

```scheme
(define (obfuscate-symbol sym salt)
  "Deterministic symbol obfuscation via HMAC-like hash."
  (let* ([name (symbol->string sym)]
         [hash (fnv1a-hash (string-append salt name))]
         [short (substring (number->string hash 36) 0 8)])
    (string->symbol (string-append "z" short))))

;; parse-pipeline → z1k4m7n2
;; execute-redirect → zq8x3p5w
```

### What Must Be Handled

1. **Top-level `define` names** — straightforward rename
2. **`export` lists** — rename to match
3. **`import` references** — rename to match
4. **Library names** — `(jsh pipeline)` → `(z a3)` everywhere
5. **Record type names** — `defstruct` generates accessor names from the
   type name; the renamer must know this pattern
6. **Macro definitions** — `defrule`/`defsyntax` template variables must
   be renamed consistently in the macro body
7. **`syntax-case` templates** — template references to renamed bindings
8. **String-to-symbol reflection** — any `(string->symbol "parse-pipeline")`
   breaks; these must be found and updated or wrapped

### What Cannot Be Renamed

- Chez/R6RS built-in names (~300 symbols)
- FFI C function name strings (they're ABI contracts)
- Record field names accessed via string-based APIs
- Symbols used in `eval` with user input (the interaction environment)

### Estimated Effort

This is a 2-4 week project. The hard parts are:
- Macro template variable tracking (syntax-case is complex)
- Record type accessor naming conventions
- Testing that the renamed program behaves identically
- Building the whole-program rename map across 30+ modules

### Alternative: FFI Name Obfuscation

Independently of Scheme symbol renaming, the C FFI names can be obfuscated
more easily. Instead of:

```c
void ffi_fork_exec(const char *cmd) { ... }
// registered as:
Sforeign_symbol("ffi_fork_exec", (void*)ffi_fork_exec);
```

Use:

```c
static void impl_0x7a3f(const char *cmd) { ... }
Sforeign_symbol("z7a3f", (void*)impl_0x7a3f);
```

And on the Scheme side:

```scheme
(define fork-exec (foreign-procedure "z7a3f" (string) void))
```

The `Sforeign_symbol` registration string is what appears in the binary.
Making the C functions `static` prevents them from appearing in the ELF
symbol table (even before `strip`). Combined with the linker version script,
this is effective and low-effort.

---

## String Literal Encryption

User-visible strings (error messages, help text, command names) can be
encrypted at compile time. This is a Jerboa-level macro:

```scheme
(define-syntax obscured
  (lambda (stx)
    (syntax-case stx ()
      [(_ str)
       (string? (syntax->datum #'str))
       (let* ([plain (string->utf8 (syntax->datum #'str))]
              [key (random 256)]
              [cipher (bytevector-map
                        (lambda (b) (fxlogxor b key))
                        plain)])
         #`(utf8->string
             (bytevector-map
               (lambda (b) (fxlogxor b #,key))
               #,(datum->syntax #'str cipher))))])))

;; Usage:
(error (obscured "pipeline: broken pipe"))
```

The XOR key is embedded in the code object (not as a separate string), so
`strings` won't find either the key or the plaintext. A disassembler would,
but the bar is significantly higher.

For the build pipeline, this would be a source-to-source pass that wraps
all string literals in `(obscured ...)` before compilation.

---

## FASL Encryption (Boot File Level)

The existing `embed_encrypt`/`embed_decrypt` infrastructure in the binary
suggests this is partially implemented. The full approach:

### Build Time

```scheme
;; After strip-fasl-file, before file->c-array:
(define (encrypt-boot-file boot-path key)
  (let* ([data (get-bytevector-all (open-file-input-port boot-path))]
         [encrypted (aes256-gcm-encrypt data key)])
    (call-with-port (open-file-output-port boot-path '(replace))
      (lambda (p) (put-bytevector p encrypted)))))
```

### Runtime (C main)

```c
// Decrypt before Chez sees it
unsigned char key[32];
derive_key_from_somewhere(key);
size_t plain_len;
void *plain = aes256_gcm_decrypt(encrypted_boot, encrypted_len, key, &plain_len);
Sregister_boot_file_bytes("app", plain, plain_len);
Sbuild_heap(NULL, NULL);

// Wipe decrypted copy after Chez loads it
explicit_bzero(plain, plain_len);
munmap(plain, plain_len);  // or free + MADV_DONTNEED
```

### Key Management

The key must come from somewhere. Options for Jerboa:

| Method | Implementation | Against `strings` | Against debugger |
|--------|---------------|-------------------|-----------------|
| XOR with binary section hash | Hash `.text` at startup | Effective | Weak |
| PBKDF2 of binary path + size | `embed_pbkdf2_sha256` | Effective | Weak |
| Environment variable | `getenv("JSH_KEY")` | Effective | Medium |
| Passphrase at startup | `embed_read_passphrase` | Effective | Strong |
| TPM2 sealed key | `tpm2_unseal` | Effective | Strong |

For a shell that needs to start without user interaction, the self-derived
key (hash of `.text` section or binary metadata) is the practical choice.
It defeats static analysis (`strings`, `hexdump`) while accepting that a
debugger can intercept the key at runtime.

---

## Complete Hardened Build Pipeline

Putting it all together, the hardened build adds five steps to the existing
pipeline from `docs/single-binary.md`:

```
Existing Pipeline:                    Hardened Additions:
─────────────────                     ────────────────────

Step 1: .ss → .sls (Jerboa)

                                      Step 1.5: Symbol renaming pass
                                        rename all user symbols in .sls files
                                        (optional, 2-4 week implementation)

Step 2: Chez compile-program          + NEW compile-time parameters:
  .sls → .so                            (generate-procedure-source-information #f)
                                         (enable-error-source-expression #f)
                                         (debug-level 0)
                                         (commonization-level 5)
                                       + Install current-make-source-object hook

Step 3: make-boot-file                (unchanged)
  .so files → .boot

                                      Step 3.5: strip-fasl-file
                                        (fasl-strip-options
                                          inspector-source
                                          profile-source
                                          source-annotations
                                          compile-time-information)

                                      Step 3.6: Encrypt boot file (optional)
                                        AES-256-GCM with derived key

Step 4: file->c-array                 (unchanged)
  .boot → C byte arrays

Step 5: gcc compile + link            + -ffile-prefix-map=...
  C → .o → ELF                        + -Wl,--version-script=hide-symbols.map

                                      Step 5.5: Rust native build
                                        strip=symbols, lto=true, panic=abort
                                        --remap-path-prefix

                                      Step 6: Post-link hardening
                                        strip -s
                                        objcopy --remove-section=.comment
                                        objcopy --remove-section=.note.*
```

---

## What Each Layer Eliminates

| Information Leak | Layer 0 (strip) | Layer 1 (compile params) | Layer 2 (FASL strip) | Layer 3 (paths) | Layer 4 (symbols) | Layer 5 (encrypt) |
|-----------------|:---:|:---:|:---:|:---:|:---:|:---:|
| ELF symbols | X | | | | | |
| DWARF debug | X | | | | | |
| `.comment` | X | | | | | |
| Procedure names | | X | X | | | |
| Source expressions | | X | | | | |
| Source file paths | | X | X | X | | |
| Source line numbers | | X | X | | | |
| Macro definitions | | | X | | | |
| Home directory paths | | | | X | | |
| Cargo/Rust paths | | | | X | | |
| GCC versions | X | | | X | | |
| Scheme symbol names | | | | | X | |
| Library names | | | | | X | |
| FFI function names | | | | | X | |
| String literals | | | | | | X |
| Error messages | | | | | | X |
| Boot file content | | | | | | X |
| OpenSSL/SQLite syms | X* | | | | | |

*Only with linker version script.

---

## Hard Limits

No amount of obfuscation changes these:

1. **Symbol interning is fundamental.** Chez's runtime needs interned symbols
   to function. After the boot file is loaded into the Chez heap, all symbols
   exist in cleartext in process memory. A memory dump at runtime always
   reveals them. Mitigation ceiling: rename symbols so the cleartext names
   are meaningless.

2. **The FASL format is open source.** Anyone with the Chez source can parse
   FASL files. It's version-specific but not obfuscated. Mitigation ceiling:
   encrypt the FASL before embedding.

3. **The runtime can always be dumped.** `/proc/PID/mem`,
   `process_vm_readv`, debuggers. `prctl(PR_SET_DUMPABLE, 0)` prevents
   non-root access. Root wins.

4. **GC metadata reveals object layout.** Type tags and size information for
   every heap object survive in the binary. Even with obfuscated names, the
   *shape* of the data is visible.

5. **Chez's error messages identify it.** `"variable ~s is not bound"`,
   `"incorrect number of arguments"` are in `petite.boot`. Removing them
   requires rebuilding Chez from source with modified error strings.

6. **petite.boot and scheme.boot are standard.** An attacker can diff your
   binary's boot files against a stock Chez installation to isolate your
   application code. Mitigation: encrypt the boot files.

---

## Recommended Implementation Order

### Phase 1: Zero-effort wins (1 day)

1. Add `strip -s` + `objcopy --remove-section=.comment` as post-link step
2. Add `(generate-procedure-source-information #f)` to release builds
3. Add `(enable-error-source-expression #f)` to release builds
4. Add `(debug-level 0)` to release builds

### Phase 2: Build infrastructure (2-3 days)

5. Add `strip-for-release` function, call it on boot files before embedding
6. Add linker version script (`support/hide-symbols.map`)
7. Add `-ffile-prefix-map` to all gcc invocations
8. Configure Rust release profile with `strip`, `lto`, `--remap-path-prefix`
9. Set up container-based build (Dockerfile with `/build` workdir)

### Phase 3: Deep Chez integration (1 week)

10. Install `current-make-source-object` hook for hardened builds
11. Add `(commonization-level 5)` option
12. Investigate `compile-whole-program` with `libs-visible? #f`
13. Implement boot file encryption with self-derived key
14. Add `harden:` keyword to `build-binary` and `build-musl-binary`

### Phase 4: Symbol obfuscation (2-4 weeks)

15. Build whole-program rename map from `.sls` exports/imports
16. Implement source-to-source renaming pass
17. Handle macro templates and record type accessors
18. Obfuscate FFI registration names (C side + Scheme side)
19. Add string literal encryption macro
