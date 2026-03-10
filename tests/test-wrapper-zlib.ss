#!chezscheme
(import (chezscheme) (std compress zlib))

(define pass-count 0)
(define fail-count 0)

(define-syntax chk
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr] [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin (set! fail-count (+ fail-count 1))
                (display "FAIL: ") (write 'expr)
                (display " => ") (write result)
                (display " expected ") (write exp) (newline))))]))

(let* ([original (string->utf8 "Hello, Jerboa! Compression test.")]
       [compressed (gzip-bytevector original)]
       [decompressed (gunzip-bytevector compressed)])
  (chk (equal? original decompressed) => #t)
  (chk (gzip-data? compressed) => #t)
  (chk (gzip-data? original) => #f))

;; Deflate round-trip
(let* ([original (string->utf8 "deflate test data")]
       [compressed (deflate-bytevector original)]
       [decompressed (inflate-bytevector compressed)])
  (chk (equal? original decompressed) => #t))

(display "  zlib: ") (display pass-count) (display " passed")
(when (> fail-count 0) (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
