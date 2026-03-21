#!chezscheme
;;; test-crypto-native.ss -- Tests for (std crypto native) — libcrypto FFI

(import (chezscheme) (std crypto native))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr] [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: ") (write 'expr)
           (display " => ") (write result)
           (display " expected ") (write exp) (newline))))]))

;; === Digest Tests (NIST vectors) ===

(check (native-sha256 "")
  => "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
(check (native-sha256 "hello")
  => "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
(check (native-sha256 "The quick brown fox jumps over the lazy dog")
  => "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")

(check (native-md5 "")
  => "d41d8cd98f00b204e9800998ecf8427e")
(check (native-md5 "hello")
  => "5d41402abc4b2a76b9719d911017c592")

(check (native-sha1 "")
  => "da39a3ee5e6b4b0d3255bfef95601890afd80709")

(check (native-sha384 "")
  => "38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b")

(check (native-sha512 "")
  => "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e")

;; Bytevector input
(check (native-sha256 #vu8(104 101 108 108 111))
  => "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")

;; Raw digest returns bytevector
(let ([bv (native-digest 'sha256 "hello")])
  (check (bytevector? bv) => #t)
  (check (bytevector-length bv) => 32))

(let ([bv (native-digest 'md5 "hello")])
  (check (bytevector-length bv) => 16))

;; === CSPRNG Tests ===

(check (bytevector-length (native-random-bytes 0)) => 0)
(check (bytevector-length (native-random-bytes 16)) => 16)
(check (bytevector-length (native-random-bytes 32)) => 32)
(check (bytevector? (native-random-bytes 8)) => #t)

;; Two calls produce different results
(let ([a (native-random-bytes 32)]
      [b (native-random-bytes 32)])
  (check (equal? a b) => #f))

;; native-random-bytes! fills existing bytevector
(let ([bv (make-bytevector 16 0)])
  (native-random-bytes! bv)
  (check (for-all zero? (bytevector->u8-list bv)) => #f))

;; === HMAC-SHA256 Tests ===

;; Known test vector (RFC 4231 Test Case 2)
(let ([hmac (native-hmac-sha256
              (string->utf8 "Jefe")
              (string->utf8 "what do ya want for nothing?"))])
  (check (bytevector? hmac) => #t)
  (check (bytevector-length hmac) => 32))

;; String convenience
(let ([hmac (native-hmac-sha256 "key" "message")])
  (check (bytevector-length hmac) => 32))

;; Same key+data produces same HMAC
(let ([a (native-hmac-sha256 "key" "data")]
      [b (native-hmac-sha256 "key" "data")])
  (check (equal? a b) => #t))

;; Different key produces different HMAC
(let ([a (native-hmac-sha256 "key1" "data")]
      [b (native-hmac-sha256 "key2" "data")])
  (check (equal? a b) => #f))

;; === Timing-Safe Comparison Tests ===

(check (native-crypto-memcmp #vu8(1 2 3) #vu8(1 2 3)) => #t)
(check (native-crypto-memcmp #vu8(1 2 3) #vu8(1 2 4)) => #f)
(check (native-crypto-memcmp #vu8(1 2) #vu8(1 2 3)) => #f)
(check (native-crypto-memcmp #vu8() #vu8()) => #t)
(check (native-crypto-memcmp "hello" "hello") => #t)
(check (native-crypto-memcmp "hello" "world") => #f)

(display "  crypto-native: ")
(display pass-count) (display " passed")
(when (> fail-count 0)
  (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
