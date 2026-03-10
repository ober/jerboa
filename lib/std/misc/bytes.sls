#!chezscheme
;;; :std/misc/bytes -- Byte/bytevector manipulation utilities

(library (std misc bytes)
  (export
    u8vector-xor
    u8vector-xor!
    u8vector-and
    u8vector-ior
    u8vector-zero!
    u8vector->uint
    uint->u8vector)

  (import (chezscheme))

  (define (u8vector-xor bv1 bv2)
    (let* ((len (min (bytevector-length bv1) (bytevector-length bv2)))
           (result (make-bytevector len)))
      (let lp ((i 0))
        (when (< i len)
          (bytevector-u8-set! result i
            (fxlogxor (bytevector-u8-ref bv1 i)
                      (bytevector-u8-ref bv2 i)))
          (lp (+ i 1))))
      result))

  (define (u8vector-xor! bv1 bv2)
    (let ((len (min (bytevector-length bv1) (bytevector-length bv2))))
      (let lp ((i 0))
        (when (< i len)
          (bytevector-u8-set! bv1 i
            (fxlogxor (bytevector-u8-ref bv1 i)
                      (bytevector-u8-ref bv2 i)))
          (lp (+ i 1))))))

  (define (u8vector-and bv1 bv2)
    (let* ((len (min (bytevector-length bv1) (bytevector-length bv2)))
           (result (make-bytevector len)))
      (let lp ((i 0))
        (when (< i len)
          (bytevector-u8-set! result i
            (fxlogand (bytevector-u8-ref bv1 i)
                      (bytevector-u8-ref bv2 i)))
          (lp (+ i 1))))
      result))

  (define (u8vector-ior bv1 bv2)
    (let* ((len (min (bytevector-length bv1) (bytevector-length bv2)))
           (result (make-bytevector len)))
      (let lp ((i 0))
        (when (< i len)
          (bytevector-u8-set! result i
            (fxlogor (bytevector-u8-ref bv1 i)
                     (bytevector-u8-ref bv2 i)))
          (lp (+ i 1))))
      result))

  (define (u8vector-zero! bv)
    (bytevector-fill! bv 0))

  (define (u8vector->uint bv)
    ;; Big-endian bytevector to unsigned integer
    (let ((len (bytevector-length bv)))
      (let lp ((i 0) (result 0))
        (if (>= i len) result
          (lp (+ i 1)
              (+ (bitwise-arithmetic-shift-left result 8)
                 (bytevector-u8-ref bv i)))))))

  (define (uint->u8vector n . rest)
    ;; Unsigned integer to big-endian bytevector
    (let ((len (if (pair? rest) (car rest)
                 (max 1 (quotient (+ (bitwise-length n) 7) 8)))))
      (let ((bv (make-bytevector len 0)))
        (let lp ((i (- len 1)) (n n))
          (when (and (>= i 0) (> n 0))
            (bytevector-u8-set! bv i (bitwise-and n #xff))
            (lp (- i 1) (bitwise-arithmetic-shift-right n 8))))
        bv)))

  ) ;; end library
