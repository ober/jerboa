#!chezscheme
;;; (std crypto random) — Cryptographically secure random number generation
;;;
;;; Reads from /dev/urandom for all random values. Never uses Chez's
;;; (random N) for security-relevant operations.

(library (std crypto random)
  (export
    ;; Core
    random-bytes random-bytes!
    ;; Convenience
    random-u64 random-token random-uuid)

  (import (chezscheme))

  ;; ========== Core: /dev/urandom ==========

  (define (random-bytes n)
    ;; Return a fresh bytevector of N cryptographically random bytes.
    (let ([bv (make-bytevector n)])
      (when (> n 0)
        (random-bytes! bv))
      bv))

  (define (random-bytes! bv)
    ;; Fill BV with cryptographically random bytes from /dev/urandom.
    (let ([len (bytevector-length bv)])
      (when (> len 0)
        (let ([port (open-file-input-port "/dev/urandom"
                      (file-options)
                      (buffer-mode block))])
          (dynamic-wind
            (lambda () (void))
            (lambda ()
              (let loop ([offset 0])
                (when (< offset len)
                  (let ([got (get-bytevector-n! port bv offset (- len offset))])
                    (when (eof-object? got)
                      (error 'random-bytes! "unexpected EOF from /dev/urandom"))
                    (loop (+ offset got))))))
            (lambda () (close-port port)))))))

  ;; ========== Convenience ==========

  (define (random-u64)
    ;; Return a random exact non-negative integer in [0, 2^64).
    (let ([bv (random-bytes 8)])
      (bytevector-u64-ref bv 0 (endianness little))))

  (define (random-token . args)
    ;; Return a hex-encoded random string. Default 16 bytes = 32 hex chars.
    (let* ([n (if (pair? args) (car args) 16)]
           [bv (random-bytes n)])
      (bytevector->hex-string bv)))

  (define (random-uuid)
    ;; Return a RFC 4122 version 4 UUID string.
    (let ([bv (random-bytes 16)])
      ;; Set version: byte 6, high nibble = 0100 (version 4)
      (bytevector-u8-set! bv 6
        (bitwise-ior #x40 (bitwise-and (bytevector-u8-ref bv 6) #x0f)))
      ;; Set variant: byte 8, high 2 bits = 10 (RFC 4122)
      (bytevector-u8-set! bv 8
        (bitwise-ior #x80 (bitwise-and (bytevector-u8-ref bv 8) #x3f)))
      (format-uuid bv)))

  ;; ========== Helpers ==========

  (define hex-chars "0123456789abcdef")

  (define (bytevector->hex-string bv)
    (let* ([len (bytevector-length bv)]
           [out (make-string (* len 2))])
      (do ([i 0 (+ i 1)])
          ((= i len) out)
        (let ([b (bytevector-u8-ref bv i)])
          (string-set! out (* i 2)
            (string-ref hex-chars (bitwise-arithmetic-shift-right b 4)))
          (string-set! out (+ (* i 2) 1)
            (string-ref hex-chars (bitwise-and b #xf)))))))

  (define (format-uuid bv)
    ;; Format 16-byte bytevector as 8-4-4-4-12 UUID string.
    (let ([hex (bytevector->hex-string bv)])
      (string-append
        (substring hex 0 8) "-"
        (substring hex 8 12) "-"
        (substring hex 12 16) "-"
        (substring hex 16 20) "-"
        (substring hex 20 32))))

  ) ;; end library
