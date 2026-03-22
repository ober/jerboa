#!chezscheme
;;; (std crypto bn) — Big number arithmetic utilities
;;;
;;; Convenience wrappers around Chez Scheme's native arbitrary-precision
;;; integers (bignums).  Provides modular arithmetic, serialization to/from
;;; bytevectors and hex strings, and comparison helpers.

(library (std crypto bn)
  (export
    bn+ bn- bn* bn/ bn-mod
    bn-expt-mod
    bn-gcd
    bn-modinv
    bn->bytevector bytevector->bn
    bn->hex hex->bn
    bn-bit-length
    bn-zero? bn-negative?
    bn-compare)

  (import (chezscheme))

  ;; ========== Basic arithmetic ==========

  (define (bn+ a b) (+ a b))
  (define (bn- a b) (- a b))
  (define (bn* a b) (* a b))
  (define (bn/ a b) (div a b))
  (define (bn-mod a b) (mod a b))

  ;; ========== Modular exponentiation (square-and-multiply) ==========

  (define (bn-expt-mod base exp modulus)
    ;; Compute (base ^ exp) mod modulus efficiently.
    ;; exp must be non-negative, modulus must be positive.
    (when (< exp 0)
      (error 'bn-expt-mod "exponent must be non-negative" exp))
    (when (<= modulus 0)
      (error 'bn-expt-mod "modulus must be positive" modulus))
    (cond
      [(= modulus 1) 0]
      [(= exp 0) 1]
      [else
       (let loop ([b (mod base modulus)]
                  [e exp]
                  [result 1])
         (if (= e 0)
             result
             (let ([result (if (odd? e)
                               (mod (* result b) modulus)
                               result)]
                   [b (mod (* b b) modulus)]
                   [e (bitwise-arithmetic-shift-right e 1)])
               (loop b e result))))]))

  ;; ========== GCD ==========

  (define (bn-gcd a b)
    (let loop ([a (abs a)] [b (abs b)])
      (if (zero? b) a (loop b (mod a b)))))

  ;; ========== Modular inverse (extended Euclidean algorithm) ==========

  (define (bn-modinv a modulus)
    ;; Return x such that (a * x) mod modulus = 1.
    ;; Raises an error if a and modulus are not coprime.
    (when (<= modulus 0)
      (error 'bn-modinv "modulus must be positive" modulus))
    (let loop ([old-r (mod a modulus)] [r modulus]
               [old-s 1]               [s 0])
      (if (zero? r)
          (if (= old-r 1)
              (mod old-s modulus)
              (error 'bn-modinv "no modular inverse; gcd != 1" a modulus))
          (let ([q (div old-r r)])
            (loop r (- old-r (* q r))
                  s (- old-s (* q s)))))))

  ;; ========== Serialization: bytevector (unsigned big-endian) ==========

  (define (bn->bytevector n)
    ;; Convert a non-negative exact integer to a big-endian bytevector.
    ;; Zero produces a single zero byte.
    (when (negative? n)
      (error 'bn->bytevector "expected non-negative integer" n))
    (if (zero? n)
        (make-bytevector 1 0)
        (let* ([bit-len (bitwise-length n)]
               [byte-len (fxdiv (fx+ bit-len 7) 8)]
               [bv (make-bytevector byte-len 0)])
          (let loop ([i (fx- byte-len 1)] [val n])
            (when (>= i 0)
              (bytevector-u8-set! bv i (bitwise-and val #xff))
              (loop (fx- i 1) (bitwise-arithmetic-shift-right val 8))))
          bv)))

  (define (bytevector->bn bv)
    ;; Convert a big-endian unsigned bytevector to an exact non-negative integer.
    (let ([len (bytevector-length bv)])
      (let loop ([i 0] [acc 0])
        (if (fx>= i len)
            acc
            (loop (fx+ i 1)
                  (+ (bitwise-arithmetic-shift-left acc 8)
                     (bytevector-u8-ref bv i)))))))

  ;; ========== Serialization: hex strings ==========

  (define (bn->hex n)
    ;; Convert an exact integer to a lowercase hex string (no prefix).
    ;; Negative numbers get a leading "-".
    (if (zero? n)
        "0"
        (let* ([neg? (negative? n)]
               [val (abs n)])
          (let loop ([v val] [chars '()])
            (if (zero? v)
                (if neg?
                    (list->string (cons #\- chars))
                    (list->string chars))
                (let* ([digit (bitwise-and v #xf)]
                       [ch (string-ref "0123456789abcdef" digit)])
                  (loop (bitwise-arithmetic-shift-right v 4)
                        (cons ch chars))))))))

  (define (hex->bn str)
    ;; Parse a hex string (optional leading "-", no "0x" prefix) to exact integer.
    (when (= (string-length str) 0)
      (error 'hex->bn "empty string"))
    (let* ([neg? (char=? (string-ref str 0) #\-)]
           [start (if neg? 1 0)]
           [len (string-length str)])
      (when (= start len)
        (error 'hex->bn "no digits after sign" str))
      (let loop ([i start] [acc 0])
        (if (fx>= i len)
            (if neg? (- acc) acc)
            (let* ([ch (string-ref str i)]
                   [digit (cond
                            [(and (char>=? ch #\0) (char<=? ch #\9))
                             (fx- (char->integer ch) (char->integer #\0))]
                            [(and (char>=? ch #\a) (char<=? ch #\f))
                             (fx+ 10 (fx- (char->integer ch) (char->integer #\a)))]
                            [(and (char>=? ch #\A) (char<=? ch #\F))
                             (fx+ 10 (fx- (char->integer ch) (char->integer #\A)))]
                            [else (error 'hex->bn "invalid hex character" ch)])])
              (loop (fx+ i 1)
                    (+ (bitwise-arithmetic-shift-left acc 4) digit)))))))

  ;; ========== Bit length ==========

  (define (bn-bit-length n)
    ;; Number of bits needed to represent |n| (0 returns 0).
    (bitwise-length (abs n)))

  ;; ========== Predicates and comparison ==========

  (define (bn-zero? n) (zero? n))
  (define (bn-negative? n) (negative? n))

  (define (bn-compare a b)
    ;; Return -1, 0, or 1.
    (cond [(< a b) -1]
          [(= a b)  0]
          [else      1]))

  ) ;; end library
