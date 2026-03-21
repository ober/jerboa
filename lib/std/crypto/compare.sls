#!chezscheme
;;; (std crypto compare) — Timing-safe comparison for secret material
;;;
;;; string=? and equal? short-circuit on first difference, leaking
;;; information via timing side channels. These functions always examine
;;; every byte, preventing timing attacks on password hashes, HMAC
;;; verification, API keys, and session tokens.

(library (std crypto compare)
  (export timing-safe-equal? timing-safe-string=?)

  (import (chezscheme))

  (define (timing-safe-equal? a b)
    ;; Constant-time bytevector comparison.
    ;; Returns #t iff A and B have the same length and contents.
    ;; Always examines every byte — no early exit on mismatch.
    (let ([alen (bytevector-length a)]
          [blen (bytevector-length b)])
      (if (not (= alen blen))
        #f
        (let loop ([i 0] [acc 0])
          (if (>= i alen)
            (zero? acc)
            (loop (+ i 1)
                  (bitwise-ior acc
                    (bitwise-xor (bytevector-u8-ref a i)
                                 (bytevector-u8-ref b i)))))))))

  (define (timing-safe-string=? a b)
    ;; Constant-time string comparison via UTF-8 encoding.
    (timing-safe-equal? (string->utf8 a) (string->utf8 b)))

  ) ;; end library
