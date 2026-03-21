#!chezscheme
;;; :std/text/hex -- Hex encoding/decoding

(library (std text hex)
  (export
    hex-encode hex-decode
    u8vector->hex-string hex-string->u8vector)

  (import (chezscheme))

  (define *hex-chars* "0123456789abcdef")

  (define (hex-encode bv)
    (u8vector->hex-string bv))

  (define (hex-decode str)
    (hex-string->u8vector str))

  (define (u8vector->hex-string bv)
    (let* ((len (bytevector-length bv))
           (result (make-string (* len 2))))
      (do ((i 0 (+ i 1)))
          ((= i len) result)
        (let ((b (bytevector-u8-ref bv i)))
          (string-set! result (* i 2)
            (string-ref *hex-chars* (bitwise-arithmetic-shift-right b 4)))
          (string-set! result (+ (* i 2) 1)
            (string-ref *hex-chars* (bitwise-and b #xf)))))))

  (define (hex-char->int c)
    (cond
      ((char<=? #\0 c #\9) (- (char->integer c) (char->integer #\0)))
      ((char<=? #\a c #\f) (+ 10 (- (char->integer c) (char->integer #\a))))
      ((char<=? #\A c #\F) (+ 10 (- (char->integer c) (char->integer #\A))))
      (else (error 'hex-decode "invalid hex character" c))))

  (define (hex-string->u8vector str)
    (let* ((len (string-length str)))
      (unless (even? len)
        (error 'hex-decode "odd-length hex string" len))
      (let* ((out-len (quotient len 2))
             (result (make-bytevector out-len)))
      (do ((i 0 (+ i 2))
           (j 0 (+ j 1)))
          ((>= i len) result)
        (let ((hi (hex-char->int (string-ref str i)))
              (lo (hex-char->int (string-ref str (+ i 1)))))
          (bytevector-u8-set! result j
            (bitwise-ior (bitwise-arithmetic-shift-left hi 4) lo)))))))

  ) ;; end library
