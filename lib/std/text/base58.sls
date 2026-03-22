#!chezscheme
;;; :std/text/base58 -- Base58 encoding/decoding (Bitcoin alphabet)

(library (std text base58)
  (export
    base58-encode base58-decode
    base58check-encode base58check-decode)

  (import (chezscheme))

  (define *base58-alphabet*
    "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

  ;; Reverse lookup table: char -> index (or -1)
  (define *base58-decode-table*
    (let ((table (make-vector 256 -1)))
      (do ((i 0 (+ i 1)))
          ((= i 58))
        (vector-set! table
          (char->integer (string-ref *base58-alphabet* i))
          i))
      table))

  ;; Encode a bytevector to a base58 string.
  ;; Algorithm: treat the bytevector as a big-endian integer,
  ;; repeatedly divide by 58, prepend leading '1' for each leading zero byte.
  (define (base58-encode bv)
    (let ((len (bytevector-length bv)))
      (if (zero? len)
        ""
        ;; Count leading zero bytes
        (let ((leading-zeros (count-leading-zeros bv)))
          ;; Convert bytevector to a big integer
          (let ((num (bytevector->bignum bv)))
            ;; Divide by 58 repeatedly to get base58 digits (in reverse)
            (let lp ((n num) (digits '()))
              (if (zero? n)
                ;; Prepend '1' for each leading zero byte
                (let ((prefix (make-string leading-zeros #\1)))
                  (string-append prefix (list->string digits)))
                (let-values (((q r) (div-and-mod n 58)))
                  (lp q (cons (string-ref *base58-alphabet* r) digits))))))))))

  ;; Decode a base58 string to a bytevector.
  (define (base58-decode str)
    (let ((len (string-length str)))
      (if (zero? len)
        (make-bytevector 0)
        ;; Count leading '1' characters (represent zero bytes)
        (let ((leading-ones (count-leading-ones str)))
          ;; Convert base58 digits to big integer
          (let lp ((i 0) (num 0))
            (if (= i len)
              ;; Convert big integer back to bytevector with leading zeros
              (let* ((data-bytes (if (zero? num)
                                   (make-bytevector 0)
                                   (bignum->bytevector num)))
                     (result (make-bytevector (+ leading-ones (bytevector-length data-bytes)))))
                ;; Fill leading zeros
                (do ((j 0 (+ j 1)))
                    ((= j leading-ones))
                  (bytevector-u8-set! result j 0))
                ;; Copy data bytes
                (bytevector-copy! data-bytes 0 result leading-ones
                  (bytevector-length data-bytes))
                result)
              (let ((val (vector-ref *base58-decode-table*
                           (char->integer (string-ref str i)))))
                (when (= val -1)
                  (error 'base58-decode "invalid base58 character"
                    (string-ref str i)))
                (lp (+ i 1) (+ (* num 58) val)))))))))

  ;; base58check encoding uses a 4-byte checksum appended before base58 encoding.
  ;; Full Bitcoin base58check uses double-SHA256 for the checksum.
  ;; Since SHA-256 may not be available, we implement a simple but real
  ;; checksum using a 32-bit FNV-1a hash applied twice (mirroring double-SHA256 structure).
  ;; NOTE: This is NOT compatible with Bitcoin's base58check. For Bitcoin compatibility,
  ;; replace fnv-checksum with double-SHA256.

  (define (base58check-encode bv)
    (let* ((checksum (compute-checksum bv))
           (with-check (make-bytevector (+ (bytevector-length bv) 4))))
      (bytevector-copy! bv 0 with-check 0 (bytevector-length bv))
      (bytevector-u8-set! with-check (bytevector-length bv)
        (bitwise-and (bitwise-arithmetic-shift-right checksum 24) #xFF))
      (bytevector-u8-set! with-check (+ (bytevector-length bv) 1)
        (bitwise-and (bitwise-arithmetic-shift-right checksum 16) #xFF))
      (bytevector-u8-set! with-check (+ (bytevector-length bv) 2)
        (bitwise-and (bitwise-arithmetic-shift-right checksum 8) #xFF))
      (bytevector-u8-set! with-check (+ (bytevector-length bv) 3)
        (bitwise-and checksum #xFF))
      (base58-encode with-check)))

  (define (base58check-decode str)
    (let* ((decoded (base58-decode str))
           (len (bytevector-length decoded)))
      (when (< len 4)
        (error 'base58check-decode "decoded data too short for checksum"))
      (let* ((payload-len (- len 4))
             (payload (make-bytevector payload-len))
             (_ (bytevector-copy! decoded 0 payload 0 payload-len))
             (expected-checksum (compute-checksum payload))
             (actual-checksum
               (bitwise-ior
                 (bitwise-arithmetic-shift-left (bytevector-u8-ref decoded payload-len) 24)
                 (bitwise-arithmetic-shift-left (bytevector-u8-ref decoded (+ payload-len 1)) 16)
                 (bitwise-arithmetic-shift-left (bytevector-u8-ref decoded (+ payload-len 2)) 8)
                 (bytevector-u8-ref decoded (+ payload-len 3)))))
        (unless (= expected-checksum actual-checksum)
          (error 'base58check-decode "checksum mismatch"
            (list 'expected expected-checksum 'got actual-checksum)))
        payload)))

  ;; FNV-1a 32-bit hash, applied twice to mimic double-hash structure.
  ;; Returns a 32-bit unsigned integer.
  (define (compute-checksum bv)
    (let* ((h1 (fnv-1a-32 bv))
           ;; Hash the hash (4 bytes of h1) to get double-hash
           (h1-bv (make-bytevector 4)))
      (bytevector-u8-set! h1-bv 0 (bitwise-and (bitwise-arithmetic-shift-right h1 24) #xFF))
      (bytevector-u8-set! h1-bv 1 (bitwise-and (bitwise-arithmetic-shift-right h1 16) #xFF))
      (bytevector-u8-set! h1-bv 2 (bitwise-and (bitwise-arithmetic-shift-right h1 8) #xFF))
      (bytevector-u8-set! h1-bv 3 (bitwise-and h1 #xFF))
      (fnv-1a-32 h1-bv)))

  (define (fnv-1a-32 bv)
    (let ((offset-basis #x811c9dc5)
          (prime #x01000193))
      (let lp ((i 0) (hash offset-basis))
        (if (= i (bytevector-length bv))
          (bitwise-and hash #xFFFFFFFF)
          (let* ((byte (bytevector-u8-ref bv i))
                 (hash (bitwise-xor hash byte))
                 (hash (bitwise-and (* hash prime) #xFFFFFFFF)))
            (lp (+ i 1) hash))))))

  ;; Helper: count leading zero bytes in a bytevector
  (define (count-leading-zeros bv)
    (let ((len (bytevector-length bv)))
      (let lp ((i 0))
        (if (and (< i len) (zero? (bytevector-u8-ref bv i)))
          (lp (+ i 1))
          i))))

  ;; Helper: count leading '1' characters in a string
  (define (count-leading-ones str)
    (let ((len (string-length str)))
      (let lp ((i 0))
        (if (and (< i len) (char=? (string-ref str i) #\1))
          (lp (+ i 1))
          i))))

  ;; Convert bytevector (big-endian) to a non-negative integer
  (define (bytevector->bignum bv)
    (let ((len (bytevector-length bv)))
      (let lp ((i 0) (num 0))
        (if (= i len)
          num
          (lp (+ i 1)
              (+ (* num 256) (bytevector-u8-ref bv i)))))))

  ;; Convert a non-negative integer to a bytevector (big-endian, minimal length)
  (define (bignum->bytevector num)
    (if (zero? num)
      (make-bytevector 0)
      ;; Count bytes needed
      (let ((byte-count (let lp ((n num) (count 0))
                          (if (zero? n) count
                            (lp (bitwise-arithmetic-shift-right n 8) (+ count 1))))))
        (let ((bv (make-bytevector byte-count)))
          (let lp ((n num) (i (- byte-count 1)))
            (when (>= i 0)
              (bytevector-u8-set! bv i (bitwise-and n #xFF))
              (lp (bitwise-arithmetic-shift-right n 8) (- i 1))))
          bv))))

  ) ;; end library
