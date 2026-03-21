#!chezscheme
;;; test-crypto-digest.ss -- Tests for (std crypto digest)

(import (chezscheme) (std crypto digest))

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

;; Known test vectors (from NIST / RFC / openssl dgst)

;; MD5
(check (md5 "")
  => "d41d8cd98f00b204e9800998ecf8427e")
(check (md5 "hello")
  => "5d41402abc4b2a76b9719d911017c592")
(check (md5 "The quick brown fox jumps over the lazy dog")
  => "9e107d9d372bb6826bd81d3542a419d6")

;; SHA-1
(check (sha1 "")
  => "da39a3ee5e6b4b0d3255bfef95601890afd80709")
(check (sha1 "hello")
  => "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d")

;; SHA-256
(check (sha256 "")
  => "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
(check (sha256 "hello")
  => "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
(check (sha256 "The quick brown fox jumps over the lazy dog")
  => "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592")

;; SHA-384
(check (sha384 "")
  => "38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b")

;; SHA-512
(check (sha512 "")
  => "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e")
(check (sha512 "hello")
  => "9b71d224bd62f3785d96d46ad3ea3d73319bfbc2890caadae2dff72519673ca72323c3d99ba5c11d7c7acc6e14b8c5da0c4663475c2e5c3adef46f73bcdec043")

;; Bytevector input
(check (sha256 #vu8(104 101 108 108 111))  ;; "hello" as bytes
  => "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")

;; digest->hex-string is identity
(check (digest->hex-string (sha256 "test"))
  => (sha256 "test"))

;; digest->u8vector returns correct bytevector
(let ([bv (digest->u8vector (md5 "hello"))])
  (check (bytevector? bv) => #t)
  (check (bytevector-length bv) => 16))

(let ([bv (digest->u8vector (sha256 "hello"))])
  (check (bytevector-length bv) => 32))

;; No temp files created (check /tmp for leftover jerboa-digest-* files)
(let ([before (length (filter (lambda (f) (let ([len (string-length f)])
                                            (and (> len 14)
                                                 (string=? (substring f 0 14) "jerboa-digest-"))))
                              (directory-list "/tmp")))])
  (sha256 "test-no-temp-files")
  (let ([after (length (filter (lambda (f) (let ([len (string-length f)])
                                             (and (> len 14)
                                                  (string=? (substring f 0 14) "jerboa-digest-"))))
                               (directory-list "/tmp")))])
    (check (= before after) => #t)))

(display "  crypto-digest: ")
(display pass-count) (display " passed")
(when (> fail-count 0)
  (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
