#!chezscheme
;;; test-crypto-compare.ss -- Tests for (std crypto compare)

(import (chezscheme) (std crypto compare))

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

;; Equal bytevectors
(check (timing-safe-equal? #vu8(1 2 3) #vu8(1 2 3)) => #t)

;; Different bytevectors (same length)
(check (timing-safe-equal? #vu8(1 2 3) #vu8(1 2 4)) => #f)

;; Different lengths
(check (timing-safe-equal? #vu8(1 2 3) #vu8(1 2)) => #f)
(check (timing-safe-equal? #vu8(1 2) #vu8(1 2 3)) => #f)

;; Empty bytevectors
(check (timing-safe-equal? #vu8() #vu8()) => #t)

;; Single byte
(check (timing-safe-equal? #vu8(0) #vu8(0)) => #t)
(check (timing-safe-equal? #vu8(0) #vu8(1)) => #f)

;; Single-byte difference in long bytevectors
(let ([a (make-bytevector 256 42)]
      [b (make-bytevector 256 42)])
  (check (timing-safe-equal? a b) => #t)
  (bytevector-u8-set! b 255 43)
  (check (timing-safe-equal? a b) => #f))

;; All zeros vs all ones
(check (timing-safe-equal? (make-bytevector 32 0) (make-bytevector 32 255)) => #f)

;; String comparison — equal
(check (timing-safe-string=? "hello" "hello") => #t)

;; String comparison — different
(check (timing-safe-string=? "hello" "world") => #f)

;; String comparison — different lengths
(check (timing-safe-string=? "hi" "hello") => #f)

;; String comparison — empty
(check (timing-safe-string=? "" "") => #t)

;; String comparison — unicode
(check (timing-safe-string=? "caf\x00e9;" "caf\x00e9;") => #t)
(check (timing-safe-string=? "caf\x00e9;" "cafe") => #f)

;; Typical use case: HMAC comparison
(let ([expected (string->utf8 "a3f2b8c9d4e5f6a7")]
      [received (string->utf8 "a3f2b8c9d4e5f6a7")])
  (check (timing-safe-equal? expected received) => #t))

(let ([expected (string->utf8 "a3f2b8c9d4e5f6a7")]
      [received (string->utf8 "a3f2b8c9d4e5f6a8")])
  (check (timing-safe-equal? expected received) => #f))

(display "  crypto-compare: ")
(display pass-count) (display " passed")
(when (> fail-count 0)
  (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
