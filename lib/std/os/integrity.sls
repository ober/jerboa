#!chezscheme
;;; (std os integrity) — Binary integrity verification via Rust/ring
;;;
;;; SHA-256 self-hashing and Ed25519 signature verification for
;;; tamper detection in compiled binaries.

(library (std os integrity)
  (export
    ;; Self-hashing
    integrity-hash-self
    integrity-verify-hash
    ;; Code signing
    integrity-verify-signature
    ;; File hashing
    integrity-hash-file
    integrity-hash-region
    ;; Condition type
    &integrity-error make-integrity-error integrity-error?
    integrity-error-reason)

  (import (chezscheme))

  ;; Load native library
  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "./lib/libjerboa_native.so") #t)
        (error 'std/os/integrity "libjerboa_native.so not found")))

  ;; Condition type
  (define-condition-type &integrity-error &error
    make-integrity-error integrity-error?
    (reason integrity-error-reason))

  ;; Helper: extract sub-bytevector
  (define (bv-sub bv start len)
    (let ([out (make-bytevector len)])
      (bytevector-copy! bv start out 0 len)
      out))

  ;; Error retrieval
  (define c-last-error
    (foreign-procedure "jerboa_last_error" (u8* size_t) size_t))

  (define (native-last-error)
    (let ([buf (make-bytevector 1024)])
      (let ([len (c-last-error buf 1024)])
        (if (> len 0)
          (utf8->string (bv-sub buf 0 (min len 1023)))
          ""))))

  ;; FFI bindings
  (define c-hash-self
    (foreign-procedure "jerboa_integrity_hash_self" (u8* size_t) int))
  (define c-verify-hash
    (foreign-procedure "jerboa_integrity_verify_hash" (u8* size_t) int))
  (define c-sign-verify
    (foreign-procedure "jerboa_integrity_sign_verify"
      (u8* size_t u8* size_t unsigned-64 unsigned-64) int))
  (define c-hash-region
    (foreign-procedure "jerboa_integrity_hash_region"
      (u8* size_t unsigned-64 unsigned-64 u8* size_t) int))
  (define c-hash-file
    (foreign-procedure "jerboa_integrity_hash_file"
      (u8* size_t u8* size_t) int))

  ;; --- Public API ---

  ;; Compute the SHA-256 hash of the currently running binary (/proc/self/exe).
  ;; Returns a 32-byte bytevector.
  (define (integrity-hash-self)
    (let ([out (make-bytevector 32)])
      (let ([rc (c-hash-self out 32)])
        (when (< rc 0)
          (raise (condition
            (make-integrity-error "self-hash failed")
            (make-message-condition (native-last-error)))))
        out)))

  ;; Verify that the running binary's SHA-256 hash matches expected-hash.
  ;; expected-hash: 32-byte bytevector.
  ;; Returns #t if match, #f if mismatch. Uses constant-time comparison.
  (define (integrity-verify-hash expected-hash)
    (unless (and (bytevector? expected-hash)
                 (= 32 (bytevector-length expected-hash)))
      (raise (condition
        (make-integrity-error "invalid hash")
        (make-message-condition "expected-hash must be a 32-byte bytevector"))))
    (let ([rc (c-verify-hash expected-hash 32)])
      (cond
        [(= rc 1) #t]
        [(= rc 0) #f]
        [else
         (raise (condition
           (make-integrity-error "hash verification failed")
           (make-message-condition (native-last-error))))])))

  ;; Verify an Ed25519 signature over the running binary.
  ;; pubkey: 32-byte Ed25519 public key bytevector.
  ;; signature: 64-byte Ed25519 signature bytevector.
  ;; exclude-offset, exclude-len: byte range to zero before verification
  ;;   (the region where the signature is embedded in the binary).
  ;;   Pass 0, 0 if the signature is not embedded in the binary.
  ;; Returns #t if valid, #f if invalid.
  (define (integrity-verify-signature pubkey signature exclude-offset exclude-len)
    (unless (and (bytevector? pubkey) (= 32 (bytevector-length pubkey)))
      (raise (condition
        (make-integrity-error "invalid public key")
        (make-message-condition "pubkey must be a 32-byte bytevector"))))
    (unless (and (bytevector? signature) (= 64 (bytevector-length signature)))
      (raise (condition
        (make-integrity-error "invalid signature")
        (make-message-condition "signature must be a 64-byte bytevector"))))
    (let ([rc (c-sign-verify pubkey 32 signature 64 exclude-offset exclude-len)])
      (cond
        [(= rc 1) #t]
        [(= rc 0) #f]
        [else
         (raise (condition
           (make-integrity-error "signature verification failed")
           (make-message-condition (native-last-error))))])))

  ;; Compute SHA-256 hash of an entire file.
  ;; path: string file path.
  ;; Returns a 32-byte bytevector.
  (define (integrity-hash-file path)
    (let ([out (make-bytevector 32)]
          [bv (string->utf8 path)])
      (let ([rc (c-hash-file bv (bytevector-length bv) out 32)])
        (when (< rc 0)
          (raise (condition
            (make-integrity-error "file hash failed")
            (make-message-condition (native-last-error)))))
        out)))

  ;; Compute SHA-256 hash of a specific region of a file.
  ;; path: string file path.
  ;; offset: byte offset to start reading.
  ;; length: number of bytes to hash (0 = from offset to end).
  ;; Returns a 32-byte bytevector.
  (define (integrity-hash-region path offset length)
    (let ([out (make-bytevector 32)]
          [bv (string->utf8 path)])
      (let ([rc (c-hash-region bv (bytevector-length bv) offset length out 32)])
        (when (< rc 0)
          (raise (condition
            (make-integrity-error "region hash failed")
            (make-message-condition (native-last-error)))))
        out)))

  ) ;; end library
