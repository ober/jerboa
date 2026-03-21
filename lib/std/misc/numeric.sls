#!chezscheme
;;; (std misc numeric) — Numeric utilities
;;;
;;; Common numeric operations for protocol implementations and formatting.

(library (std misc numeric)
  (export clamp lerp in-range?
          integer->bytevector bytevector->integer
          number->padded-string
          divmod)

  (import (chezscheme))

  ;; Clamp value to [lo, hi]
  (define (clamp val lo hi)
    (max lo (min hi val)))

  ;; Linear interpolation: lerp(a, b, t) = a + t*(b-a)
  (define (lerp a b t)
    (+ a (* t (- b a))))

  ;; Range check: lo <= val < hi (or lo <= val <= hi with inclusive? #t)
  (define in-range?
    (case-lambda
      [(val lo hi) (and (>= val lo) (< val hi))]
      [(val lo hi inclusive?)
       (if inclusive?
           (and (>= val lo) (<= val hi))
           (and (>= val lo) (< val hi)))]))

  ;; Integer to bytevector (big-endian, n bytes)
  (define (integer->bytevector n size)
    (let ([bv (make-bytevector size 0)])
      (let loop ([i (- size 1)] [val n])
        (when (>= i 0)
          (bytevector-u8-set! bv i (fxlogand val #xff))
          (loop (- i 1) (fxsrl val 8))))
      bv))

  ;; Bytevector to integer (big-endian)
  (define (bytevector->integer bv)
    (let ([len (bytevector-length bv)])
      (let loop ([i 0] [acc 0])
        (if (= i len) acc
            (loop (+ i 1)
                  (+ (fxsll acc 8) (bytevector-u8-ref bv i)))))))

  ;; Format number with zero-padding to given width
  (define number->padded-string
    (case-lambda
      [(n width) (number->padded-string n width #\0)]
      [(n width pad-char)
       (let* ([s (number->string n)]
              [len (string-length s)])
         (if (>= len width)
             s
             (string-append (make-string (- width len) pad-char) s)))]))

  ;; Simultaneous quotient and remainder
  (define (divmod a b)
    (values (quotient a b) (remainder a b)))

) ;; end library
