#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc binary-type))

(define test-count 0)
(define pass-count 0)

(define (test name thunk)
  (set! test-count (+ test-count 1))
  (guard (e [#t (display "FAIL: ") (display name) (newline)
              (display "  Error: ") (display (condition-message e)) (newline)])
    (thunk)
    (set! pass-count (+ pass-count 1))
    (display "PASS: ") (display name) (newline)))

(define (assert-equal actual expected msg)
  (unless (equal? actual expected)
    (error 'assert-equal
           (string-append msg ": expected " (format "~s" expected)
                          " got " (format "~s" actual)))))

(define (assert-close actual expected tolerance msg)
  (unless (< (abs (- actual expected)) tolerance)
    (error 'assert-close
           (string-append msg ": expected ~" (format "~s" expected)
                          " got " (format "~s" actual)))))

;; Helper: round-trip through a bytevector port
(define (round-trip-bv type-name val)
  (let ([bv (call-with-bytevector-output-port
              (lambda (out) (binary-write type-name out val)))])
    (let ([in (open-bytevector-input-port bv)])
      (binary-read type-name in))))

;; ============ Primitive type tests ============

(test "uint8 read/write round-trip"
  (lambda ()
    (assert-equal (round-trip-bv 'uint8 0) 0 "zero")
    (assert-equal (round-trip-bv 'uint8 127) 127 "mid")
    (assert-equal (round-trip-bv 'uint8 255) 255 "max")))

(test "int8 read/write round-trip"
  (lambda ()
    (assert-equal (round-trip-bv 'int8 0) 0 "zero")
    (assert-equal (round-trip-bv 'int8 127) 127 "positive max")
    (assert-equal (round-trip-bv 'int8 -128) -128 "negative min")
    (assert-equal (round-trip-bv 'int8 -1) -1 "negative one")))

(test "uint16-be read/write round-trip"
  (lambda ()
    (assert-equal (round-trip-bv 'uint16-be 0) 0 "zero")
    (assert-equal (round-trip-bv 'uint16-be 256) 256 "256")
    (assert-equal (round-trip-bv 'uint16-be 65535) 65535 "max")))

(test "uint16-le read/write round-trip"
  (lambda ()
    (assert-equal (round-trip-bv 'uint16-le 0) 0 "zero")
    (assert-equal (round-trip-bv 'uint16-le 256) 256 "256")
    (assert-equal (round-trip-bv 'uint16-le 65535) 65535 "max")))

(test "uint16 endianness matters"
  (lambda ()
    ;; Write 0x0102 in big-endian: bytes should be 01 02
    (let ([bv (call-with-bytevector-output-port
                (lambda (out) (binary-write 'uint16-be out #x0102)))])
      (assert-equal (bytevector-u8-ref bv 0) #x01 "be high byte")
      (assert-equal (bytevector-u8-ref bv 1) #x02 "be low byte"))
    ;; Write 0x0102 in little-endian: bytes should be 02 01
    (let ([bv (call-with-bytevector-output-port
                (lambda (out) (binary-write 'uint16-le out #x0102)))])
      (assert-equal (bytevector-u8-ref bv 0) #x02 "le low byte")
      (assert-equal (bytevector-u8-ref bv 1) #x01 "le high byte"))))

(test "uint32-be round-trip"
  (lambda ()
    (assert-equal (round-trip-bv 'uint32-be 0) 0 "zero")
    (assert-equal (round-trip-bv 'uint32-be #xDEADBEEF) #xDEADBEEF "deadbeef")))

(test "uint32-le round-trip"
  (lambda ()
    (assert-equal (round-trip-bv 'uint32-le 0) 0 "zero")
    (assert-equal (round-trip-bv 'uint32-le #xCAFEBABE) #xCAFEBABE "cafebabe")))

(test "int16-be round-trip"
  (lambda ()
    (assert-equal (round-trip-bv 'int16-be 0) 0 "zero")
    (assert-equal (round-trip-bv 'int16-be 32767) 32767 "max")
    (assert-equal (round-trip-bv 'int16-be -32768) -32768 "min")
    (assert-equal (round-trip-bv 'int16-be -1) -1 "neg one")))

(test "int16-le round-trip"
  (lambda ()
    (assert-equal (round-trip-bv 'int16-le -1000) -1000 "negative")
    (assert-equal (round-trip-bv 'int16-le 1000) 1000 "positive")))

(test "int32-be round-trip"
  (lambda ()
    (assert-equal (round-trip-bv 'int32-be 0) 0 "zero")
    (assert-equal (round-trip-bv 'int32-be -1) -1 "neg one")
    (assert-equal (round-trip-bv 'int32-be 2147483647) 2147483647 "max")
    (assert-equal (round-trip-bv 'int32-be -2147483648) -2147483648 "min")))

(test "int32-le round-trip"
  (lambda ()
    (assert-equal (round-trip-bv 'int32-le -100000) -100000 "negative")
    (assert-equal (round-trip-bv 'int32-le 100000) 100000 "positive")))

(test "float32-be round-trip"
  (lambda ()
    (assert-close (round-trip-bv 'float32-be 3.14) 3.14 0.001 "pi")
    (assert-equal (round-trip-bv 'float32-be 0.0) 0.0 "zero")))

(test "float64-be round-trip"
  (lambda ()
    (assert-close (round-trip-bv 'float64-be 3.141592653589793) 3.141592653589793 1e-15 "pi")
    (assert-equal (round-trip-bv 'float64-be 0.0) 0.0 "zero")
    (assert-close (round-trip-bv 'float64-be -1.23e10) -1.23e10 1.0 "large neg")))

;; ============ Composite record tests ============

(define-binary-record point
  (x uint16-be)
  (y uint16-be))

(test "binary-record make and accessors"
  (lambda ()
    (let ([p (make-point 100 200)])
      (assert-equal (point-x p) 100 "x")
      (assert-equal (point-y p) 200 "y"))))

(test "binary-record read/write round-trip"
  (lambda ()
    (let* ([p (make-point 300 400)]
           [bv (call-with-bytevector-output-port
                 (lambda (out) (write-point out p)))]
           [in (open-bytevector-input-port bv)]
           [p2 (read-point in)])
      (assert-equal (point-x p2) 300 "x")
      (assert-equal (point-y p2) 400 "y"))))

(test "binary-record via generic binary-read/write"
  (lambda ()
    (let* ([p (make-point 500 600)]
           [bv (call-with-bytevector-output-port
                 (lambda (out) (binary-write 'point out p)))]
           [in (open-bytevector-input-port bv)]
           [p2 (binary-read 'point in)])
      (assert-equal (point-x p2) 500 "x")
      (assert-equal (point-y p2) 600 "y"))))

(test "binary-record byte layout"
  (lambda ()
    ;; point is two uint16-be fields: 4 bytes total
    (let ([bv (call-with-bytevector-output-port
                (lambda (out) (write-point out (make-point #x0102 #x0304))))])
      (assert-equal (bytevector-length bv) 4 "size")
      (assert-equal (bytevector-u8-ref bv 0) #x01 "x high")
      (assert-equal (bytevector-u8-ref bv 1) #x02 "x low")
      (assert-equal (bytevector-u8-ref bv 2) #x03 "y high")
      (assert-equal (bytevector-u8-ref bv 3) #x04 "y low"))))

;; Record with mixed types
(define-binary-record header
  (magic uint32-be)
  (version uint8)
  (flags uint16-le))

(test "binary-record with mixed types"
  (lambda ()
    (let* ([h (make-header #xDEADBEEF 2 #x0100)]
           [bv (call-with-bytevector-output-port
                 (lambda (out) (write-header out h)))]
           [in (open-bytevector-input-port bv)]
           [h2 (read-header in)])
      (assert-equal (header-magic h2) #xDEADBEEF "magic")
      (assert-equal (header-version h2) 2 "version")
      (assert-equal (header-flags h2) #x0100 "flags"))))

;; ============ Nested record tests ============

(define-binary-record rect
  (top-left point)
  (bottom-right point))

(test "nested record round-trip"
  (lambda ()
    (let* ([r (make-rect (make-point 10 20) (make-point 30 40))]
           [bv (call-with-bytevector-output-port
                 (lambda (out) (write-rect out r)))]
           [in (open-bytevector-input-port bv)]
           [r2 (read-rect in)])
      (assert-equal (point-x (rect-top-left r2)) 10 "tl-x")
      (assert-equal (point-y (rect-top-left r2)) 20 "tl-y")
      (assert-equal (point-x (rect-bottom-right r2)) 30 "br-x")
      (assert-equal (point-y (rect-bottom-right r2)) 40 "br-y"))))

(test "nested record byte size"
  (lambda ()
    ;; rect = 2 points = 4 uint16-be = 8 bytes
    (let ([bv (call-with-bytevector-output-port
                (lambda (out) (write-rect out
                  (make-rect (make-point 1 2) (make-point 3 4)))))])
      (assert-equal (bytevector-length bv) 8 "size"))))

;; ============ Array tests ============

(define-binary-array byte-triple uint8 3)

(test "binary-array read/write round-trip"
  (lambda ()
    (let* ([arr (vector 10 20 30)]
           [bv (call-with-bytevector-output-port
                 (lambda (out) (write-byte-triple out arr)))]
           [in (open-bytevector-input-port bv)]
           [arr2 (read-byte-triple in)])
      (assert-equal arr2 (vector 10 20 30) "values"))))

(define-binary-array point-array point 2)

(test "array of records round-trip"
  (lambda ()
    (let* ([arr (vector (make-point 100 200) (make-point 300 400))]
           [bv (call-with-bytevector-output-port
                 (lambda (out) (write-point-array out arr)))]
           [in (open-bytevector-input-port bv)]
           [arr2 (read-point-array in)])
      (assert-equal (point-x (vector-ref arr2 0)) 100 "p0-x")
      (assert-equal (point-y (vector-ref arr2 0)) 200 "p0-y")
      (assert-equal (point-x (vector-ref arr2 1)) 300 "p1-x")
      (assert-equal (point-y (vector-ref arr2 1)) 400 "p1-y"))))

(test "binary-array via generic dispatch"
  (lambda ()
    (let* ([arr (vector 1 2 3)]
           [bv (call-with-bytevector-output-port
                 (lambda (out) (binary-write 'byte-triple out arr)))]
           [in (open-bytevector-input-port bv)]
           [arr2 (binary-read 'byte-triple in)])
      (assert-equal arr2 (vector 1 2 3) "values"))))

(define-binary-array u32-pair uint32-be 2)

(test "array of uint32-be round-trip"
  (lambda ()
    (let* ([arr (vector #xAABBCCDD #x11223344)]
           [bv (call-with-bytevector-output-port
                 (lambda (out) (write-u32-pair out arr)))]
           [in (open-bytevector-input-port bv)]
           [arr2 (read-u32-pair in)])
      (assert-equal (vector-ref arr2 0) #xAABBCCDD "first")
      (assert-equal (vector-ref arr2 1) #x11223344 "second"))))

;; ============ Multiple values sequentially ============

(test "read/write multiple values sequentially"
  (lambda ()
    (let ([bv (call-with-bytevector-output-port
                (lambda (out)
                  (binary-write 'uint8 out 42)
                  (binary-write 'uint32-be out #xCAFEBABE)
                  (binary-write 'int16-be out -1000)))])
      (let ([in (open-bytevector-input-port bv)])
        (assert-equal (binary-read 'uint8 in) 42 "byte")
        (assert-equal (binary-read 'uint32-be in) #xCAFEBABE "u32")
        (assert-equal (binary-read 'int16-be in) -1000 "i16")))))

;; ============ Custom type test ============

(test "define-binary-type custom type"
  (lambda ()
    (define-binary-type bool8
      (reader (lambda (port)
                (let ([b (get-u8 port)])
                  (not (zero? b)))))
      (writer (lambda (port val)
                (put-u8 port (if val 1 0)))))
    (let ([bv (call-with-bytevector-output-port
                (lambda (out)
                  (binary-write 'bool8 out #t)
                  (binary-write 'bool8 out #f)))])
      (let ([in (open-bytevector-input-port bv)])
        (assert-equal (binary-read 'bool8 in) #t "true")
        (assert-equal (binary-read 'bool8 in) #f "false")))))

;; ============ Results ============

(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
