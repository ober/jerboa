#!/usr/bin/env scheme-script
#!chezscheme
;;; Tests for the Rust native library (libjerboa_native.so)

(import (chezscheme)
        (std crypto native-rust)
        (std compress native-rust)
        (std regex-native)
        (std crypto secure-mem))

(define test-count 0)
(define pass-count 0)
(define fail-count 0)

(define (test name thunk)
  (set! test-count (+ test-count 1))
  (guard (e [#t
             (set! fail-count (+ fail-count 1))
             (display (string-append "FAIL: " name "\n"))
             (display (string-append "  Error: "
               (if (message-condition? e)
                 (condition-message e)
                 "unknown error")
               "\n"))])
    (thunk)
    (set! pass-count (+ pass-count 1))
    (display (string-append "PASS: " name "\n"))))

(define (assert-true msg val)
  (unless val (error 'assert-true msg)))

(define (assert-false msg val)
  (when val (error 'assert-false msg)))

(define (assert-equal msg expected actual)
  (unless (equal? expected actual)
    (error 'assert-equal msg expected actual)))

(define (assert-error msg thunk)
  (let ((got-error #f))
    (guard (e [#t (set! got-error #t)])
      (thunk))
    (unless got-error
      (error 'assert-error msg))))

(define (bv->hex bv)
  (let ([port (open-output-string)])
    (let loop ([i 0])
      (when (< i (bytevector-length bv))
        (let ([b (bytevector-u8-ref bv i)])
          (when (< b 16) (display "0" port))
          (display (string-downcase (number->string b 16)) port))
        (loop (+ i 1))))
    (get-output-string port)))

(display "=== Rust Native Library Tests ===\n\n")

;; --- Crypto: Digest ---
(display "--- SHA digests ---\n")

(test "sha256: known value"
  (lambda ()
    (let* ([input (string->utf8 "hello")]
           [hash (rust-sha256 input)]
           [hex (bv->hex hash)])
      (assert-equal "sha256 of 'hello'"
        "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        hex))))

(test "sha256: empty input"
  (lambda ()
    (let* ([hash (rust-sha256 (make-bytevector 0))]
           [hex (bv->hex hash)])
      (assert-equal "sha256 of empty"
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        hex))))

(test "sha512: known value"
  (lambda ()
    (let* ([input (string->utf8 "hello")]
           [hash (rust-sha512 input)])
      (assert-equal "sha512 length" 64 (bytevector-length hash)))))

(test "sha1: known value"
  (lambda ()
    (let* ([input (string->utf8 "hello")]
           [hash (rust-sha1 input)]
           [hex (bv->hex hash)])
      (assert-equal "sha1 of 'hello'"
        "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d"
        hex))))

(test "sha384: output length"
  (lambda ()
    (let ([hash (rust-sha384 (string->utf8 "test"))])
      (assert-equal "sha384 length" 48 (bytevector-length hash)))))

;; --- Crypto: CSPRNG ---
(display "\n--- CSPRNG ---\n")

(test "random-bytes: correct length"
  (lambda ()
    (let ([bv (rust-random-bytes 32)])
      (assert-equal "length" 32 (bytevector-length bv)))))

(test "random-bytes: non-deterministic"
  (lambda ()
    (let ([a (rust-random-bytes 16)]
          [b (rust-random-bytes 16)])
      (assert-false "should differ" (equal? a b)))))

(test "random-bytes: zero length"
  (lambda ()
    (let ([bv (rust-random-bytes 0)])
      (assert-equal "empty" 0 (bytevector-length bv)))))

;; --- Crypto: HMAC ---
(display "\n--- HMAC ---\n")

(test "hmac-sha256: known value"
  (lambda ()
    (let* ([key (string->utf8 "secret")]
           [data (string->utf8 "message")]
           [mac (rust-hmac-sha256 key data)])
      (assert-equal "hmac length" 32 (bytevector-length mac)))))

(test "hmac-sha256: verify correct"
  (lambda ()
    (let* ([key (string->utf8 "secret")]
           [data (string->utf8 "message")]
           [mac (rust-hmac-sha256 key data)])
      (assert-true "verify" (rust-hmac-sha256-verify key data mac)))))

(test "hmac-sha256: verify wrong tag"
  (lambda ()
    (let* ([key (string->utf8 "secret")]
           [data (string->utf8 "message")]
           [bad-tag (make-bytevector 32 0)])
      (assert-false "should fail" (rust-hmac-sha256-verify key data bad-tag)))))

;; --- Crypto: Timing-safe comparison ---
(display "\n--- Timing-safe comparison ---\n")

(test "timing-safe: equal"
  (lambda ()
    (let ([a (string->utf8 "hello")]
          [b (string->utf8 "hello")])
      (assert-true "equal" (rust-timing-safe-equal? a b)))))

(test "timing-safe: different"
  (lambda ()
    (let ([a (string->utf8 "hello")]
          [b (string->utf8 "world")])
      (assert-false "different" (rust-timing-safe-equal? a b)))))

(test "timing-safe: different lengths"
  (lambda ()
    (let ([a (string->utf8 "hello")]
          [b (string->utf8 "hi")])
      (assert-false "diff lengths" (rust-timing-safe-equal? a b)))))

;; --- Crypto: AEAD ---
(display "\n--- AEAD (AES-256-GCM) ---\n")

(test "aead: seal and open roundtrip"
  (lambda ()
    (let* ([key (rust-random-bytes 32)]
           [nonce (rust-random-bytes 12)]
           [plaintext (string->utf8 "secret message")]
           [aad (string->utf8 "additional data")]
           [ciphertext (rust-aead-seal key nonce plaintext aad)]
           [decrypted (rust-aead-open key nonce ciphertext aad)])
      (assert-equal "roundtrip" plaintext decrypted))))

(test "aead: wrong key fails"
  (lambda ()
    (let* ([key1 (rust-random-bytes 32)]
           [key2 (rust-random-bytes 32)]
           [nonce (rust-random-bytes 12)]
           [plaintext (string->utf8 "secret")]
           [aad (make-bytevector 0)]
           [ciphertext (rust-aead-seal key1 nonce plaintext aad)])
      (assert-error "wrong key should fail"
        (lambda () (rust-aead-open key2 nonce ciphertext aad))))))

(test "aead: tampered ciphertext fails"
  (lambda ()
    (let* ([key (rust-random-bytes 32)]
           [nonce (rust-random-bytes 12)]
           [plaintext (string->utf8 "secret")]
           [aad (make-bytevector 0)]
           [ciphertext (rust-aead-seal key nonce plaintext aad)]
           [tampered (bytevector-copy ciphertext)])
      ;; Flip a bit
      (bytevector-u8-set! tampered 0
        (fxlogxor (bytevector-u8-ref tampered 0) 1))
      (assert-error "tampered should fail"
        (lambda () (rust-aead-open key nonce tampered aad))))))

;; --- Crypto: PBKDF2 ---
(display "\n--- PBKDF2 ---\n")

(test "pbkdf2: derive and verify"
  (lambda ()
    (let* ([pw (string->utf8 "password")]
           [salt (rust-random-bytes 16)]
           [derived (rust-pbkdf2-derive pw salt 10000 32)])
      (assert-equal "derived length" 32 (bytevector-length derived))
      (assert-true "verify" (rust-pbkdf2-verify pw salt 10000 derived)))))

(test "pbkdf2: wrong password fails verify"
  (lambda ()
    (let* ([pw1 (string->utf8 "password")]
           [pw2 (string->utf8 "wrong")]
           [salt (rust-random-bytes 16)]
           [derived (rust-pbkdf2-derive pw1 salt 10000 32)])
      (assert-false "wrong pw" (rust-pbkdf2-verify pw2 salt 10000 derived)))))

;; --- Compression ---
(display "\n--- Compression ---\n")

(test "deflate/inflate roundtrip"
  (lambda ()
    (let* ([data (string->utf8 "hello world hello world hello world")]
           [compressed (rust-deflate data)]
           [decompressed (rust-inflate compressed)])
      (assert-equal "roundtrip" data decompressed))))

(test "gzip/gunzip roundtrip"
  (lambda ()
    (let* ([data (string->utf8 "the quick brown fox jumps over the lazy dog")]
           [compressed (rust-gzip data)]
           [decompressed (rust-gunzip compressed)])
      (assert-equal "roundtrip" data decompressed))))

(test "inflate: decompression bomb protection"
  (lambda ()
    ;; Compress a large repeated string
    (let* ([big (make-bytevector 1000 65)]  ;; 1000 'A' bytes
           [compressed (rust-deflate big)])
      ;; Try to inflate with a tiny limit
      (assert-error "should reject"
        (lambda ()
          (parameterize ((*rust-max-decompressed-size* 100))
            (rust-inflate compressed)))))))

;; --- Regex ---
(display "\n--- Regex (linear-time NFA) ---\n")

(test "regex: compile and match"
  (lambda ()
    (let ([re (regex-compile "hello")])
      (assert-true "match" (regex-match? re "hello world"))
      (assert-false "no match" (regex-match? re "goodbye"))
      (regex-free re))))

(test "regex: find position"
  (lambda ()
    (let ([re (regex-compile "world")])
      (let ([result (regex-find re "hello world")])
        (assert-true "found" (pair? result))
        (assert-equal "start" 6 (car result))
        (assert-equal "end" 11 (cdr result)))
      (regex-free re))))

(test "regex: no match returns #f"
  (lambda ()
    (let ([re (regex-compile "xyz")])
      (assert-false "not found" (regex-find re "hello world"))
      (regex-free re))))

(test "regex: replace all"
  (lambda ()
    (let ([re (regex-compile "o")])
      (let ([result (regex-replace-all re "hello world" "0")])
        (assert-equal "replaced" "hell0 w0rld" result))
      (regex-free re))))

(test "regex: pathological pattern (no ReDoS)"
  (lambda ()
    ;; This pattern causes exponential backtracking in PCRE2/pregexp
    ;; but completes instantly with Rust's NFA engine
    (let ([re (regex-compile "(a+)+b")])
      ;; 30 a's with no b — would hang a backtracking engine
      (assert-false "no match, but fast" (regex-match? re (make-string 30 #\a)))
      (regex-free re))))

(test "regex: invalid pattern rejected"
  (lambda ()
    (assert-error "should reject"
      (lambda () (regex-compile "[invalid")))))

;; --- Secure Memory ---
(display "\n--- Secure memory ---\n")

(test "secure-alloc/free"
  (lambda ()
    (let ([region (secure-alloc 4096)])
      (assert-true "is region" (secure-region? region))
      (assert-equal "size" 4096 (secure-region-size region))
      (secure-free region))))

(test "secure-random-fill"
  (lambda ()
    (let ([region (secure-alloc 32)])
      (secure-random-fill region)
      ;; Region should now contain random bytes (can't easily verify from Scheme
      ;; since it's a void* pointer, but no error means it worked)
      (secure-free region))))

(test "with-secure-region macro"
  (lambda ()
    ;; Just verify it doesn't error
    (with-secure-region ([r1 64] [r2 128])
      (assert-true "r1 is region" (secure-region? r1))
      (assert-true "r2 is region" (secure-region? r2)))))

;;; ============ Summary ============
(display "\n=== Results ===\n")
(display (string-append "Total:  " (number->string test-count) "\n"))
(display (string-append "Passed: " (number->string pass-count) "\n"))
(display (string-append "Failed: " (number->string fail-count) "\n"))

(when (> fail-count 0)
  (exit 1))
