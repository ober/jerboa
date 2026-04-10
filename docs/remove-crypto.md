# Remove Last OpenSSL (libcrypto) Dependency

## Status: Implemented

## Goal

Eliminate the last C OpenSSL dependency (`libcrypto.a`) from all jerboa-shell
build targets (musl, macOS, FreeBSD, Android). After this, the only native
code linked is `libjerboa_native.a` (Rust) and platform libc.

## Background

All other C dependencies have already been replaced:

| C Library | Rust Replacement | Status |
|-----------|-----------------|--------|
| libssl (OpenSSL TLS) | rustls | Done |
| libpcre2 | regex crate | Done |
| libz | flate2 | Done |
| libsqlite3 | rusqlite (bundled) | Done |
| **libcrypto (OpenSSL)** | **ring** | **This task** |

The sole remaining consumer is `vault-stage/chez/vault/crypto.sls` in
jerboa-shell, which calls 13 OpenSSL C functions for:

1. **CSPRNG** — `RAND_bytes`
2. **PBKDF2** — `PKCS5_PBKDF2_HMAC` + `EVP_sha256`
3. **AES-256-GCM** — `EVP_CIPHER_CTX_new/free`, `EVP_aes_256_gcm`,
   `EVP_EncryptInit_ex/Update/Final_ex`, `EVP_DecryptInit_ex/Update/Final_ex`,
   `EVP_CIPHER_CTX_ctrl`

## Key Finding: Rust FFI Already Exists

All three operations are already implemented in `jerboa-native-rs/src/crypto.rs`:

| Vault operation | Rust FFI function | ring API |
|-----------------|-------------------|----------|
| `RAND_bytes` | `jerboa_random_bytes(output, len)` → 0 on success | `ring::rand::SystemRandom` |
| `PKCS5_PBKDF2_HMAC` | `jerboa_pbkdf2_derive(pw, pw_len, salt, salt_len, iters, out, out_len)` → 0 on success | `ring::pbkdf2::PBKDF2_HMAC_SHA256` |
| AES-256-GCM seal | `jerboa_aead_seal(key, 32, nonce, 12, pt, pt_len, aad, aad_len, out, out_max, &out_len)` → 0 on success | `ring::aead::AES_256_GCM` |
| AES-256-GCM open | `jerboa_aead_open(key, 32, nonce, 12, ct, ct_len, aad, aad_len, out, out_max, &out_len)` → 0 on success | `ring::aead::AES_256_GCM` |

No new Rust code is needed. This is purely a Scheme rewrite + build cleanup.

## Plan

### Phase 1: Rewrite vault/crypto.sls (jerboa-shell)

Rewrite `vault-stage/chez/vault/crypto.sls` to call the existing Rust FFI
instead of OpenSSL. The public API is unchanged:

```
vault-rand-bytes, vault-pbkdf2, vault-block-key,
vault-encrypt-block, vault-decrypt-block,
vault-encrypt-small, vault-decrypt-small
```

#### Mapping (current → new)

**vault-rand-bytes:**
```scheme
;; OLD: (c-rand-bytes bv n) where c-rand-bytes = foreign-procedure "RAND_bytes"
;; NEW:
(define c-rand-bytes
  (foreign-procedure "jerboa_random_bytes" (u8* size_t) int))

(define (vault-rand-bytes n)
  (let ([bv (make-bytevector n 0)])
    (let ([r (c-rand-bytes bv n)])
      (unless (= r 0) (error 'vault-rand-bytes "jerboa_random_bytes failed"))
      bv)))
;; NOTE: return code changes — RAND_bytes returns 1 on success, jerboa_random_bytes returns 0
```

**vault-pbkdf2:**
```scheme
;; OLD: 3 FFI calls (EVP_sha256 + PKCS5_PBKDF2_HMAC)
;; NEW: 1 FFI call
(define c-pbkdf2
  (foreign-procedure "jerboa_pbkdf2_derive"
    (u8* size_t u8* size_t unsigned-32 u8* size_t) int))

(define (vault-pbkdf2 password-bv salt-bv iterations key-len)
  (let ([out (make-bytevector key-len 0)])
    (let ([r (c-pbkdf2
               password-bv (bytevector-length password-bv)
               salt-bv     (bytevector-length salt-bv)
               iterations
               out key-len)])
      (unless (= r 0) (error 'vault-pbkdf2 "jerboa_pbkdf2_derive failed"))
      out)))
```

**gcm-encrypt / gcm-decrypt:**
```scheme
;; OLD: 7+ FFI calls per operation (CTX_new, init, update, final, ctrl, CTX_free)
;; NEW: 1 FFI call each
(define c-aead-seal
  (foreign-procedure "jerboa_aead_seal"
    (u8* size_t u8* size_t u8* size_t u8* size_t u8* size_t u8*) int))

(define c-aead-open
  (foreign-procedure "jerboa_aead_open"
    (u8* size_t u8* size_t u8* size_t u8* size_t u8* size_t u8*) int))

(define (gcm-encrypt key plaintext-bv)
  (let* ([pt-len  (bytevector-length plaintext-bv)]
         [nonce   (vault-rand-bytes BLOCK-NONCE-LEN)]  ;; 12 bytes
         [out-max (+ pt-len 16)]                        ;; ciphertext + tag
         [out     (make-bytevector out-max 0)]
         [out-len-bv (make-bytevector 8 0)])            ;; size_t output
    (let ([r (c-aead-seal key 32 nonce 12
               plaintext-bv pt-len
               (make-bytevector 0) 0   ;; no AAD
               out out-max out-len-bv)])
      (unless (= r 0) (error 'vault-encrypt "jerboa_aead_seal failed"))
      ;; Reassemble: nonce[12] || ciphertext[N] || tag[16]  (same wire format)
      (let ([result (make-bytevector (+ BLOCK-NONCE-LEN out-max))])
        (bytevector-copy! nonce 0 result 0 BLOCK-NONCE-LEN)
        (bytevector-copy! out 0 result BLOCK-NONCE-LEN out-max)
        result))))

(define (gcm-decrypt key ciphertext-bv)
  (let* ([total  (bytevector-length ciphertext-bv)]
         [ct-len (- total BLOCK-NONCE-LEN)])  ;; nonce is prepended
    (if (< ct-len 16) #f  ;; too short for tag
      (let* ([nonce  (bv-sub ciphertext-bv 0 BLOCK-NONCE-LEN)]
             [ct+tag (bv-sub ciphertext-bv BLOCK-NONCE-LEN ct-len)]
             [out    (make-bytevector ct-len 0)]
             [out-len-bv (make-bytevector 8 0)])
        (let ([r (c-aead-open key 32 nonce 12
                   ct+tag ct-len
                   (make-bytevector 0) 0  ;; no AAD
                   out ct-len out-len-bv)])
          (if (= r 0)
            ;; ring returns plaintext in out[0..pt-len] where pt-len = ct-len - 16
            (bv-sub out 0 (- ct-len 16))
            #f))))))
```

**Wire format compatibility:** The nonce||ciphertext||tag layout stays
identical. Existing vault data decrypts without migration.

**Critical detail:** `jerboa_aead_seal` outputs ciphertext||tag (no nonce).
The Scheme layer prepends the nonce, matching the current format exactly.
`jerboa_aead_open` expects ciphertext||tag as input (nonce separate),
matching how we strip the nonce before calling it.

### Phase 2: Update build scripts — remove libcrypto

Remove all OpenSSL/libcrypto references from the 4 build scripts.

#### 2a. Remove OpenSSL symbol whitelists

Each build script registers 13 OpenSSL symbols for the Chez FFI. Remove them:

| File | Lines | What |
|------|-------|------|
| `build-jsh-musl.ss` | ~1285-1292 | `vault-crypto-symbols` inline list |
| `build-jsh-macos.ss` | ~1114-1120 | `vault-crypto-symbols` define |
| `build-jsh-freebsd.ss` | ~1077-1083 | `vault-crypto-symbols` define |

The Rust functions (`jerboa_random_bytes`, `jerboa_pbkdf2_derive`,
`jerboa_aead_seal`, `jerboa_aead_open`) are already exported by
`libjerboa_native.a` and already in the jerboa-native symbol whitelists.
Verify this for each platform.

#### 2b. Remove libcrypto.a from linker flags

| File | Lines | Current | Change |
|------|-------|---------|--------|
| `build-jsh-musl.ss` | ~1501-1518 | Finds and links `/usr/lib/.../libcrypto.a` | Remove libcrypto from link list |
| `build-jsh-macos.ss` | ~1585-1591 | Links `brew-ssl-prefix/lib/libcrypto.a` | Remove libcrypto from link list |
| `build-jsh-freebsd.ss` | ~1454-1456 | Links `/usr/lib/libcrypto.a` | Remove libcrypto from link list |
| `build-jsh-android.sh` | ~195, 265 | References `libcrypto.so` for vault | Remove libcrypto from staging |

#### 2c. Remove glibc-compat shim (musl only)

`build-jsh-musl.ss` lines ~1423-1465 generate a `glibc-compat.c` shim that
stubs out glibc symbols referenced by `libcrypto.a` (`__stack_chk_fail_local`,
`__fprintf_chk`, OSSL_ASYNC stubs, ARM64 `getauxval`/`__environ`). Delete the
entire shim generation — it exists solely for libcrypto.

#### 2d. Remove `openssl-include-dir` (macOS only)

`build-jsh-macos.ss` lines ~222-224 locate Homebrew OpenSSL include paths,
used when compiling the (now-deleted) chez-ssl shim. If no other code
references this, remove it.

#### 2e. Remove load-shared-object exclusion (Android)

`build-jsh-android.sh` line ~270 excludes `vault/crypto.sls` from the
load-shared-object patching pass because it loads `libcrypto.so`. After the
rewrite, vault/crypto.sls no longer calls `load-shared-object`, so this
exclusion can be removed.

### Phase 3: Clean up Dockerfiles

| File | Line | Current | Change |
|------|------|---------|--------|
| `Dockerfile` | 28 | `libssl-dev \` | Remove (check no other consumer first) |
| `Dockerfile.android` | 28 | `libssl-dev \` | Remove (check no other consumer first) |

**Caution:** `libssl-dev` pulls in both `libssl` and `libcrypto` headers +
static libs. Verify that nothing else in the Docker build needs them. The
`openssl` CLI tool (used in `Makefile:162` for cert generation) comes from
the `openssl` package, not `libssl-dev`, so check if `openssl` needs to be
added separately if `libssl-dev` is removed.

### Phase 4: Clean up remaining references

- `jerboa/README.md:108` — update `(std crypto digest)` description to say
  "via ring" instead of "via openssl"
- `jerboa/docs/native-rust.md:49-50` — update status table to show libcrypto
  as fully replaced
- `jerboa/docs/security-reference.md:352` — update to say "Via Rust ring
  (recommended)" and remove "(legacy)" qualifier from OpenSSL mention
- `jerboa-shell/android.md:38` — remove `libcrypto.so` from linked
  libraries list

### Phase 5: Test

1. **Roundtrip test:** Create a vault, write data, read it back — verify
   encrypt/decrypt works with the Rust backend
2. **Cross-compatibility test:** Encrypt data with old (OpenSSL) binary,
   decrypt with new (ring) binary — verify wire format compatibility
3. **Build all platforms:** `make jsh-musl`, `make macos`, `make jsh-freebsd`,
   `make android` — verify no unresolved symbols
4. **Binary size check:** Confirm binary shrinks (libcrypto.a is ~3-5 MB)
5. **Run existing vault tests** if any exist

## Risks

1. **Wire format mismatch** — Low risk. Both OpenSSL and ring use standard
   AES-256-GCM with 12-byte nonce and 16-byte tag. The Scheme layer controls
   the nonce||ciphertext||tag layout, which is preserved.

2. **PBKDF2 output difference** — No risk. PBKDF2-HMAC-SHA256 is a
   deterministic standard (RFC 2898). Same inputs produce same outputs
   regardless of implementation.

3. **size_t ABI** — The Rust FFI uses `size_t` (Chez `size_t` or `unsigned-64`
   on 64-bit). Verify the `foreign-procedure` declarations match the C ABI
   on all platforms (LP64 Linux/macOS/FreeBSD and Android aarch64).

4. **out-len parameter** — `jerboa_aead_seal/open` write the output length
   to a `*mut usize` pointer. In Scheme, this needs a bytevector large enough
   for a `size_t` (8 bytes on 64-bit). Use `bytevector-u64-native-ref` to
   read it back if needed, or ignore it when the length is deterministic
   (pt_len + 16 for seal, ct_len - 16 for open).

## Files Modified (Summary)

### jerboa-shell (the main work)
- `vault-stage/chez/vault/crypto.sls` — rewrite to use Rust FFI
- `build-jsh-musl.ss` — remove OpenSSL symbols, libcrypto link, glibc-compat shim
- `build-jsh-macos.ss` — remove OpenSSL symbols, libcrypto link, openssl-include-dir
- `build-jsh-freebsd.ss` — remove OpenSSL symbols, libcrypto link
- `build-jsh-android.sh` — remove libcrypto references, vault exclusion
- `build-jsh-android.ss` — remove libcrypto from link
- `Dockerfile` — remove libssl-dev
- `Dockerfile.android` — remove libssl-dev
- `android.md` — update linked libraries list

### jerboa (docs only)
- `README.md` — update crypto digest description
- `docs/native-rust.md` — mark libcrypto as fully replaced
- `docs/security-reference.md` — update crypto backend description

### No changes needed
- `jerboa-native-rs/` — all required Rust FFI functions already exist
- `Cargo.toml` — ring is already a dependency
- `test-mux-tcp.sh` — uses `openssl` CLI for test cert generation (unrelated to libcrypto linkage)
- `Makefile:162` — uses `openssl` CLI for embedded cert generation (unrelated)
