#!chezscheme
(import (chezscheme)
        (std crypto cipher)
        (std crypto hmac)
        (std crypto pkey)
        (std crypto kdf)
        (std crypto etc))

(define pass-count 0)
(define fail-count 0)

(define-syntax chk
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr] [exp expected])
       (if (equal? result exp) (set! pass-count (+ pass-count 1))
         (begin (set! fail-count (+ fail-count 1))
                (display "FAIL: ") (write 'expr)
                (display " => ") (write result)
                (display " expected ") (write exp) (newline))))]))

;; Random bytes
(let ([bv (random-bytes 16)])
  (chk (= (bytevector-length bv) 16) => #t))

;; HMAC
(let ([h (hmac-sha256 "key" "data")])
  (chk (= (bytevector-length h) 32) => #t))

;; Cipher round-trip
(let* ([key (random-bytes 32)]
       [iv  (random-bytes 16)]
       [plain (string->utf8 "test")]
       [enc (encrypt "aes-256-cbc" key iv plain)]
       [dec (decrypt "aes-256-cbc" key iv enc)])
  (chk (equal? plain dec) => #t))

;; Ed25519
(let-values ([(priv pub) (ed25519-keygen)])
  (let ([sig (ed25519-sign priv "msg")])
    (chk (ed25519-verify pub "msg" sig) => #t)
    (chk (ed25519-verify pub "bad" sig) => #f)))

;; Scrypt
(let ([k (scrypt "pass" "salt" 32)])
  (chk (= (bytevector-length k) 32) => #t))

(display "  crypto: ") (display pass-count) (display " passed")
(when (> fail-count 0) (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
