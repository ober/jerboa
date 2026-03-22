#!chezscheme
;;; :std/srfi/151 -- SRFI-151 Bitwise Operations
;;; Wraps Chez Scheme's bitwise operations to provide the SRFI-151 API.
;;; Chez provides most operations under bitwise-* names; this module
;;; re-exports matching ones and adds SRFI-151-specific aliases.

(library (std srfi srfi-151)
  (export
    bitwise-not bitwise-and bitwise-ior bitwise-xor
    bitwise-if
    bit-count integer-length
    bit-set? bit-swap
    any-bit-set? every-bit-set?
    first-set-bit
    bit-field bit-field-any? bit-field-every?
    bit-field-clear bit-field-set bit-field-replace
    bit-field-rotate
    arithmetic-shift
    copy-bit)

  (import (chezscheme))

  ;; bitwise-not, bitwise-and, bitwise-ior, bitwise-xor, bitwise-if,
  ;; integer-length are re-exported directly from Chez.

  ;; bit-count: count of 1-bits (for non-negative) or 0-bits (for negative)
  (define (bit-count n)
    (if (negative? n)
      (bitwise-bit-count (bitwise-not n))
      (bitwise-bit-count n)))

  ;; bit-set?: is bit index set in n?  (SRFI-151 arg order: index, n)
  (define (bit-set? index n)
    (bitwise-bit-set? n index))

  ;; copy-bit: return n with bit index set/cleared based on boolean
  (define (copy-bit index n bit)
    (if bit
      (bitwise-ior n (bitwise-arithmetic-shift-left 1 index))
      (bitwise-and n (bitwise-not (bitwise-arithmetic-shift-left 1 index)))))

  ;; bit-swap: swap bits i and j in n
  (define (bit-swap i j n)
    (let ([bi (bit-set? i n)]
          [bj (bit-set? j n)])
      (copy-bit j (copy-bit i n bj) bi)))

  ;; any-bit-set?: are any of the bits in test-bits set in n?
  (define (any-bit-set? test-bits n)
    (not (zero? (bitwise-and test-bits n))))

  ;; every-bit-set?: are all bits in test-bits set in n?
  (define (every-bit-set? test-bits n)
    (= test-bits (bitwise-and test-bits n)))

  ;; first-set-bit: index of least significant 1-bit, or -1
  (define first-set-bit bitwise-first-bit-set)

  ;; bit-field: extract bits start..end from n
  (define (bit-field n start end)
    (bitwise-bit-field n start end))

  ;; bit-field-any?: any bits set in field start..end of n?
  (define (bit-field-any? n start end)
    (not (zero? (bit-field n start end))))

  ;; bit-field-every?: all bits set in field start..end of n?
  (define (bit-field-every? n start end)
    (let ([width (- end start)])
      (= (bit-field n start end)
         (- (bitwise-arithmetic-shift-left 1 width) 1))))

  ;; bit-field-clear: clear bits start..end of n
  (define (bit-field-clear n start end)
    (bit-field-replace n 0 start end))

  ;; bit-field-set: set all bits in field start..end of n
  (define (bit-field-set n start end)
    (let ([width (- end start)])
      (bit-field-replace n (- (bitwise-arithmetic-shift-left 1 width) 1)
                         start end)))

  ;; bit-field-replace: replace bits start..end of n with low bits of newfield
  (define (bit-field-replace n newfield start end)
    (let* ([width (- end start)]
           [field-mask (- (bitwise-arithmetic-shift-left 1 width) 1)]
           [masked-new (bitwise-and newfield field-mask)]
           [shifted-mask (bitwise-arithmetic-shift-left field-mask start)])
      (bitwise-ior
        (bitwise-and n (bitwise-not shifted-mask))
        (bitwise-arithmetic-shift-left masked-new start))))

  ;; bit-field-rotate: rotate bits start..end of n by count positions
  (define (bit-field-rotate n count start end)
    (let* ([width (- end start)])
      (if (zero? width) n
        (let* ([count (modulo count width)]
               [field (bit-field n start end)]
               [rotated (bitwise-ior
                          (bitwise-and
                            (bitwise-arithmetic-shift-left field count)
                            (- (bitwise-arithmetic-shift-left 1 width) 1))
                          (bitwise-arithmetic-shift-right
                            field (- width count)))])
          (bit-field-replace n rotated start end)))))

  ;; arithmetic-shift
  (define arithmetic-shift bitwise-arithmetic-shift)

) ;; end library
