#!chezscheme
;;; (std crypto native-rust) — Crypto bindings backed by Rust ring library
;;;
;;; Drop-in replacement for (std crypto native) OpenSSL bindings.
;;; Uses libjerboa_native.so (Rust) instead of libcrypto.so (C/OpenSSL).

(library (std crypto native-rust)
  (export
    ;; Digest
    rust-sha1 rust-sha256 rust-sha384 rust-sha512
    ;; CSPRNG
    rust-random-bytes
    ;; HMAC
    rust-hmac-sha256 rust-hmac-sha256-verify
    ;; Timing-safe comparison
    rust-timing-safe-equal?
    ;; AEAD (AES-256-GCM)
    rust-aead-seal rust-aead-open
    ;; AEAD (ChaCha20-Poly1305)
    rust-chacha20-seal rust-chacha20-open
    ;; Scrypt KDF
    rust-scrypt
    ;; PBKDF2
    rust-pbkdf2-derive rust-pbkdf2-verify
    ;; Argon2id
    rust-argon2id-hash rust-argon2id-verify
    ;; Error
    rust-last-error)

  (import (chezscheme))

  ;; Load the Rust native library (for dynamic builds).
  ;; In static builds, symbols are pre-registered via Sforeign_symbol — skip loading.
  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        #t))

  ;; Helper: extract sub-bytevector (avoids Chez extension warning)
  (define (bv-sub bv start len)
    (let ([out (make-bytevector len)])
      (bytevector-copy! bv start out 0 len)
      out))

  ;; --- Error retrieval ---

  (define c-jerboa-last-error
    (foreign-procedure "jerboa_last_error" (u8* size_t) size_t))

  (define (rust-last-error)
    (let ([buf (make-bytevector 1024)])
      (let ([len (c-jerboa-last-error buf 1024)])
        (if (> len 0)
          (utf8->string (bv-sub buf 0 (min len 1023)))
          ""))))

  ;; --- Digest ---

  (define c-jerboa-sha1
    (foreign-procedure "jerboa_sha1" (u8* size_t u8* size_t) int))

  (define (rust-sha1 bv)
    (let ([out (make-bytevector 20)])
      (let ([rc (c-jerboa-sha1 bv (bytevector-length bv) out 20)])
        (when (< rc 0) (error 'rust-sha1 "hash failed" (rust-last-error)))
        out)))

  (define c-jerboa-sha256
    (foreign-procedure "jerboa_sha256" (u8* size_t u8* size_t) int))

  (define (rust-sha256 bv)
    (let ([out (make-bytevector 32)])
      (let ([rc (c-jerboa-sha256 bv (bytevector-length bv) out 32)])
        (when (< rc 0) (error 'rust-sha256 "hash failed" (rust-last-error)))
        out)))

  (define c-jerboa-sha384
    (foreign-procedure "jerboa_sha384" (u8* size_t u8* size_t) int))

  (define (rust-sha384 bv)
    (let ([out (make-bytevector 48)])
      (let ([rc (c-jerboa-sha384 bv (bytevector-length bv) out 48)])
        (when (< rc 0) (error 'rust-sha384 "hash failed" (rust-last-error)))
        out)))

  (define c-jerboa-sha512
    (foreign-procedure "jerboa_sha512" (u8* size_t u8* size_t) int))

  (define (rust-sha512 bv)
    (let ([out (make-bytevector 64)])
      (let ([rc (c-jerboa-sha512 bv (bytevector-length bv) out 64)])
        (when (< rc 0) (error 'rust-sha512 "hash failed" (rust-last-error)))
        out)))

  ;; --- CSPRNG ---

  (define c-jerboa-random-bytes
    (foreign-procedure "jerboa_random_bytes" (u8* size_t) int))

  (define (rust-random-bytes n)
    (let ([bv (make-bytevector n)])
      (let ([rc (c-jerboa-random-bytes bv n)])
        (when (< rc 0) (error 'rust-random-bytes "CSPRNG failed" (rust-last-error)))
        bv)))

  ;; --- HMAC ---

  (define c-jerboa-hmac-sha256
    (foreign-procedure "jerboa_hmac_sha256" (u8* size_t u8* size_t u8* size_t) int))

  (define (rust-hmac-sha256 key data)
    (let ([out (make-bytevector 32)])
      (let ([rc (c-jerboa-hmac-sha256 key (bytevector-length key)
                                       data (bytevector-length data)
                                       out 32)])
        (when (< rc 0) (error 'rust-hmac-sha256 "HMAC failed" (rust-last-error)))
        out)))

  (define c-jerboa-hmac-sha256-verify
    (foreign-procedure "jerboa_hmac_sha256_verify" (u8* size_t u8* size_t u8* size_t) int))

  (define (rust-hmac-sha256-verify key data tag)
    (let ([rc (c-jerboa-hmac-sha256-verify key (bytevector-length key)
                                            data (bytevector-length data)
                                            tag (bytevector-length tag))])
      (= rc 1)))

  ;; --- Timing-safe comparison ---

  (define c-jerboa-timing-safe-equal
    (foreign-procedure "jerboa_timing_safe_equal" (u8* size_t u8* size_t) int))

  (define (rust-timing-safe-equal? a b)
    (= 1 (c-jerboa-timing-safe-equal a (bytevector-length a)
                                      b (bytevector-length b))))

  ;; --- AEAD (AES-256-GCM) ---

  (define c-jerboa-aead-seal
    (foreign-procedure "jerboa_aead_seal"
      (u8* size_t u8* size_t u8* size_t u8* size_t u8* size_t u8*) int))

  (define (rust-aead-seal key nonce plaintext aad)
    (let* ([pt-len (bytevector-length plaintext)]
           [out-max (+ pt-len 16)]
           [out (make-bytevector out-max)]
           [len-buf (make-bytevector 8)])
      (let ([rc (c-jerboa-aead-seal key (bytevector-length key)
                                     nonce (bytevector-length nonce)
                                     plaintext pt-len
                                     aad (bytevector-length aad)
                                     out out-max
                                     len-buf)])
        (when (< rc 0) (error 'rust-aead-seal "seal failed" (rust-last-error)))
        (let ([actual-len (bytevector-u64-native-ref len-buf 0)])
          (if (= actual-len out-max)
            out
            (bv-sub out 0 actual-len))))))

  (define c-jerboa-aead-open
    (foreign-procedure "jerboa_aead_open"
      (u8* size_t u8* size_t u8* size_t u8* size_t u8* size_t u8*) int))

  (define (rust-aead-open key nonce ciphertext aad)
    (let* ([ct-len (bytevector-length ciphertext)]
           [out-max ct-len]
           [out (make-bytevector out-max)]
           [len-buf (make-bytevector 8)])
      (let ([rc (c-jerboa-aead-open key (bytevector-length key)
                                     nonce (bytevector-length nonce)
                                     ciphertext ct-len
                                     aad (bytevector-length aad)
                                     out out-max
                                     len-buf)])
        (when (< rc 0) (error 'rust-aead-open "open failed" (rust-last-error)))
        (let ([actual-len (bytevector-u64-native-ref len-buf 0)])
          (bv-sub out 0 actual-len)))))

  ;; --- AEAD (ChaCha20-Poly1305) ---

  (define c-jerboa-chacha20-seal
    (foreign-procedure "jerboa_chacha20_seal"
      (u8* size_t u8* size_t u8* size_t u8* size_t u8* size_t u8*) int))

  ;; Encrypt with ChaCha20-Poly1305. Returns ciphertext||tag bytevector.
  (define (rust-chacha20-seal key nonce plaintext aad)
    (let* ([pt-len (bytevector-length plaintext)]
           [out-max (+ pt-len 16)]
           [out (make-bytevector out-max)]
           [len-buf (make-bytevector 8)])
      (let ([rc (c-jerboa-chacha20-seal key (bytevector-length key)
                                         nonce (bytevector-length nonce)
                                         plaintext pt-len
                                         aad (bytevector-length aad)
                                         out out-max
                                         len-buf)])
        (when (< rc 0) (error 'rust-chacha20-seal "seal failed" (rust-last-error)))
        (let ([actual-len (bytevector-u64-native-ref len-buf 0)])
          (if (= actual-len out-max)
            out
            (bv-sub out 0 actual-len))))))

  (define c-jerboa-chacha20-open
    (foreign-procedure "jerboa_chacha20_open"
      (u8* size_t u8* size_t u8* size_t u8* size_t u8* size_t u8*) int))

  ;; Decrypt with ChaCha20-Poly1305. Returns plaintext or raises error.
  (define (rust-chacha20-open key nonce ciphertext aad)
    (let* ([ct-len (bytevector-length ciphertext)]
           [out-max ct-len]
           [out (make-bytevector out-max)]
           [len-buf (make-bytevector 8)])
      (let ([rc (c-jerboa-chacha20-open key (bytevector-length key)
                                         nonce (bytevector-length nonce)
                                         ciphertext ct-len
                                         aad (bytevector-length aad)
                                         out out-max
                                         len-buf)])
        (when (< rc 0) (error 'rust-chacha20-open "open failed" (rust-last-error)))
        (let ([actual-len (bytevector-u64-native-ref len-buf 0)])
          (bv-sub out 0 actual-len)))))

  ;; --- Scrypt KDF ---

  (define c-jerboa-scrypt
    (foreign-procedure "jerboa_scrypt"
      (u8* size_t u8* size_t unsigned-8 unsigned-32 unsigned-32 u8* size_t) int))

  ;; Derive key using scrypt. Takes N (power of 2, e.g. 16384), r, p.
  ;; Converts N to log2(N) for the Rust API.
  (define (rust-scrypt password salt output-len n r p)
    (let* ([pw (if (string? password) (string->utf8 password) password)]
           [s (if (string? password) (string->utf8 salt) salt)]
           [log-n (bitwise-length (- n 1))]  ;; log2(16384) = 14
           [out (make-bytevector output-len)])
      (let ([rc (c-jerboa-scrypt pw (bytevector-length pw)
                                  s (bytevector-length s)
                                  log-n r p
                                  out output-len)])
        (when (< rc 0) (error 'rust-scrypt "scrypt failed" (rust-last-error)))
        out)))

  ;; --- PBKDF2 ---

  (define c-jerboa-pbkdf2-derive
    (foreign-procedure "jerboa_pbkdf2_derive"
      (u8* size_t u8* size_t unsigned-32 u8* size_t) int))

  (define (rust-pbkdf2-derive password salt iterations output-len)
    (let ([out (make-bytevector output-len)]
          [pw (if (string? password) (string->utf8 password) password)]
          [s (if (string? password) (string->utf8 salt) salt)])
      (let ([rc (c-jerboa-pbkdf2-derive pw (bytevector-length pw)
                                         s (bytevector-length s)
                                         iterations
                                         out output-len)])
        (when (< rc 0) (error 'rust-pbkdf2-derive "derivation failed" (rust-last-error)))
        out)))

  (define c-jerboa-pbkdf2-verify
    (foreign-procedure "jerboa_pbkdf2_verify"
      (u8* size_t u8* size_t unsigned-32 u8* size_t) int))

  (define (rust-pbkdf2-verify password salt iterations expected)
    (let ([pw (if (string? password) (string->utf8 password) password)]
          [s (if (string? password) (string->utf8 salt) salt)])
      (let ([rc (c-jerboa-pbkdf2-verify pw (bytevector-length pw)
                                         s (bytevector-length s)
                                         iterations
                                         expected (bytevector-length expected))])
        (= rc 1))))

  ;; --- Argon2id ---

  (define c-jerboa-argon2id-hash
    (foreign-procedure "jerboa_argon2id_hash"
      (u8* size_t u8* size_t unsigned-32 unsigned-32 unsigned-32 u8* size_t) int))

  ;; Derive key using Argon2id.
  ;; m-cost: memory in KiB (e.g. 65536 = 64 MB)
  ;; t-cost: time cost (iterations, e.g. 3)
  ;; p-cost: parallelism (e.g. 4)
  ;; OWASP 2023 recommended minimum: m=19456 (19 MiB), t=2, p=1
  (define (rust-argon2id-hash password salt output-len m-cost t-cost p-cost)
    (let ([out (make-bytevector output-len)]
          [pw (if (string? password) (string->utf8 password) password)]
          [s  (if (string? salt) (string->utf8 salt) salt)])
      (let ([rc (c-jerboa-argon2id-hash pw (bytevector-length pw)
                                         s (bytevector-length s)
                                         m-cost t-cost p-cost
                                         out output-len)])
        (when (< rc 0) (error 'rust-argon2id-hash "hash failed" (rust-last-error)))
        out)))

  (define c-jerboa-argon2id-verify
    (foreign-procedure "jerboa_argon2id_verify"
      (u8* size_t u8* size_t unsigned-32 unsigned-32 unsigned-32 u8* size_t) int))

  ;; Verify password against Argon2id hash. Returns #t if match, #f otherwise.
  (define (rust-argon2id-verify password salt expected m-cost t-cost p-cost)
    (let ([pw (if (string? password) (string->utf8 password) password)]
          [s  (if (string? salt) (string->utf8 salt) salt)])
      (let ([rc (c-jerboa-argon2id-verify pw (bytevector-length pw)
                                           s (bytevector-length s)
                                           m-cost t-cost p-cost
                                           expected (bytevector-length expected))])
        (= rc 1))))

  ) ;; end library
