#!chezscheme
;;; test-crypto-random.ss -- Tests for (std crypto random)

(import (chezscheme) (std crypto random))

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

;; random-bytes returns correct length
(check (bytevector-length (random-bytes 0)) => 0)
(check (bytevector-length (random-bytes 1)) => 1)
(check (bytevector-length (random-bytes 16)) => 16)
(check (bytevector-length (random-bytes 32)) => 32)
(check (bytevector-length (random-bytes 256)) => 256)

;; random-bytes returns bytevectors
(check (bytevector? (random-bytes 8)) => #t)

;; Two calls produce different results (with overwhelming probability)
(let ([a (random-bytes 32)]
      [b (random-bytes 32)])
  (check (equal? a b) => #f))

;; random-bytes! fills an existing bytevector
(let ([bv (make-bytevector 16 0)])
  (random-bytes! bv)
  ;; At least some bytes should be non-zero (with overwhelming probability)
  (check (for-all zero? (bytevector->u8-list bv)) => #f))

;; random-u64 returns a non-negative exact integer
(let ([n (random-u64)])
  (check (integer? n) => #t)
  (check (exact? n) => #t)
  (check (>= n 0) => #t))

;; Two random-u64 calls produce different results
(let ([a (random-u64)]
      [b (random-u64)])
  (check (= a b) => #f))

;; random-token default is 32 hex chars (16 bytes)
(let ([tok (random-token)])
  (check (string-length tok) => 32)
  ;; All characters are hex
  (check (for-all (lambda (c)
                    (or (char<=? #\0 c #\9)
                        (char<=? #\a c #\f)))
                  (string->list tok))
    => #t))

;; random-token with explicit size
(let ([tok (random-token 8)])
  (check (string-length tok) => 16))

;; random-uuid format: 8-4-4-4-12 = 36 chars
(let ([uuid (random-uuid)])
  (check (string-length uuid) => 36)
  ;; Dashes at correct positions
  (check (char=? (string-ref uuid 8) #\-) => #t)
  (check (char=? (string-ref uuid 13) #\-) => #t)
  (check (char=? (string-ref uuid 18) #\-) => #t)
  (check (char=? (string-ref uuid 23) #\-) => #t)
  ;; Version nibble is 4
  (check (char=? (string-ref uuid 14) #\4) => #t)
  ;; Variant nibble is 8, 9, a, or b
  (check (and (member (string-ref uuid 19) '(#\8 #\9 #\a #\b)) #t) => #t))

;; Two UUIDs are different
(let ([a (random-uuid)]
      [b (random-uuid)])
  (check (string=? a b) => #f))

(display "  crypto-random: ")
(display pass-count) (display " passed")
(when (> fail-count 0)
  (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
