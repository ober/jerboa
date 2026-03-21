#!chezscheme
;;; :std/text/base64 -- Base64 encoding/decoding

(library (std text base64)
  (export
    base64-encode base64-decode
    u8vector->base64-string base64-string->u8vector)

  (import (chezscheme))

  (define *base64-chars*
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")

  (define *base64-decode-table*
    (let ((table (make-vector 256 -1)))
      (do ((i 0 (+ i 1)))
          ((= i 64))
        (vector-set! table (char->integer (string-ref *base64-chars* i)) i))
      table))

  (define (base64-encode bv)
    (u8vector->base64-string bv))

  (define (base64-decode str)
    (base64-string->u8vector str))

  (define (u8vector->base64-string bv)
    (let* ((len (bytevector-length bv))
           (out-len (* 4 (quotient (+ len 2) 3)))
           (result (make-string out-len)))
      (let lp ((i 0) (j 0))
        (when (< i len)
          (let* ((b0 (bytevector-u8-ref bv i))
                 (b1 (if (< (+ i 1) len) (bytevector-u8-ref bv (+ i 1)) 0))
                 (b2 (if (< (+ i 2) len) (bytevector-u8-ref bv (+ i 2)) 0))
                 (triple (bitwise-ior
                           (bitwise-arithmetic-shift-left b0 16)
                           (bitwise-arithmetic-shift-left b1 8)
                           b2)))
            (string-set! result j
              (string-ref *base64-chars* (bitwise-and (bitwise-arithmetic-shift-right triple 18) #x3f)))
            (string-set! result (+ j 1)
              (string-ref *base64-chars* (bitwise-and (bitwise-arithmetic-shift-right triple 12) #x3f)))
            (string-set! result (+ j 2)
              (if (< (+ i 1) len)
                (string-ref *base64-chars* (bitwise-and (bitwise-arithmetic-shift-right triple 6) #x3f))
                #\=))
            (string-set! result (+ j 3)
              (if (< (+ i 2) len)
                (string-ref *base64-chars* (bitwise-and triple #x3f))
                #\=))
            (lp (+ i 3) (+ j 4)))))
      result))

  (define (base64-validate-char c)
    (let ([val (vector-ref *base64-decode-table* (char->integer c))])
      (when (= val -1)
        (error 'base64-decode "invalid base64 character" c))
      val))

  (define (base64-string->u8vector str)
    ;; Strip whitespace and validate padding position
    (let* ((slen (string-length str))
           ;; Validate: '=' only at end, after stripping whitespace
           (clean (let lp ((i 0) (chars '()) (pad-count 0) (saw-non-pad? #f))
                    (if (>= i slen)
                      (list->string (reverse chars))
                      (let ((c (string-ref str i)))
                        (cond
                          [(char-whitespace? c)
                           (lp (+ i 1) chars pad-count saw-non-pad?)]
                          [(char=? c #\=)
                           (when saw-non-pad?
                             ;; = after non-pad means we're in the padding zone
                             #f)
                           (lp (+ i 1) chars (+ pad-count 1) #f)]
                          [else
                           (when (> pad-count 0)
                             (error 'base64-decode "invalid padding: '=' in middle of data"))
                           (lp (+ i 1) (cons c chars) 0 #t)])))))
           (clen (string-length clean))
           (out-len (quotient (* clen 3) 4))
           (result (make-bytevector out-len)))
      (let lp ((i 0) (j 0))
        (when (< i clen)
          (let* ((v0 (base64-validate-char (string-ref clean i)))
                 (v1 (if (< (+ i 1) clen)
                       (base64-validate-char (string-ref clean (+ i 1)))
                       0))
                 (v2 (if (< (+ i 2) clen)
                       (base64-validate-char (string-ref clean (+ i 2)))
                       0))
                 (v3 (if (< (+ i 3) clen)
                       (base64-validate-char (string-ref clean (+ i 3)))
                       0)))
            (when (< j out-len)
              (bytevector-u8-set! result j
                (bitwise-and (bitwise-ior
                               (bitwise-arithmetic-shift-left v0 2)
                               (bitwise-arithmetic-shift-right v1 4))
                             #xff)))
            (when (< (+ j 1) out-len)
              (bytevector-u8-set! result (+ j 1)
                (bitwise-and (bitwise-ior
                               (bitwise-arithmetic-shift-left (bitwise-and v1 #xf) 4)
                               (bitwise-arithmetic-shift-right v2 2))
                             #xff)))
            (when (< (+ j 2) out-len)
              (bytevector-u8-set! result (+ j 2)
                (bitwise-and (bitwise-ior
                               (bitwise-arithmetic-shift-left (bitwise-and v2 3) 6)
                               v3)
                             #xff)))
            (lp (+ i 4) (+ j 3)))))
      result))

  ) ;; end library
