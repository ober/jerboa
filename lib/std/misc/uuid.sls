#!chezscheme
;;; :std/misc/uuid -- UUID generation (v4 random)

(library (std misc uuid)
  (export
    uuid-string
    make-uuid)

  (import (chezscheme))

  (define (uuid-string)
    ;; Generate a UUID v4 string
    (let ((bytes (make-bytevector 16)))
      ;; Fill with random bytes
      (let lp ((i 0))
        (when (< i 16)
          (bytevector-u8-set! bytes i (random 256))
          (lp (+ i 1))))
      ;; Set version (4) and variant (10xx)
      (bytevector-u8-set! bytes 6
        (fxlogor #x40 (fxlogand (bytevector-u8-ref bytes 6) #x0f)))
      (bytevector-u8-set! bytes 8
        (fxlogor #x80 (fxlogand (bytevector-u8-ref bytes 8) #x3f)))
      ;; Format as string
      (format "~2,'0x~2,'0x~2,'0x~2,'0x-~2,'0x~2,'0x-~2,'0x~2,'0x-~2,'0x~2,'0x-~2,'0x~2,'0x~2,'0x~2,'0x~2,'0x~2,'0x"
        (bytevector-u8-ref bytes 0) (bytevector-u8-ref bytes 1)
        (bytevector-u8-ref bytes 2) (bytevector-u8-ref bytes 3)
        (bytevector-u8-ref bytes 4) (bytevector-u8-ref bytes 5)
        (bytevector-u8-ref bytes 6) (bytevector-u8-ref bytes 7)
        (bytevector-u8-ref bytes 8) (bytevector-u8-ref bytes 9)
        (bytevector-u8-ref bytes 10) (bytevector-u8-ref bytes 11)
        (bytevector-u8-ref bytes 12) (bytevector-u8-ref bytes 13)
        (bytevector-u8-ref bytes 14) (bytevector-u8-ref bytes 15))))

  (define (make-uuid)
    (uuid-string))

  ) ;; end library
