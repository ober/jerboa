#!chezscheme
;;; Tests for (std text msgpack) — MessagePack serialization

(import (chezscheme) (std text msgpack))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn
              [#t (set! fail (+ fail 1))
                  (printf "FAIL ~a: exception ~a~%" name
                    (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1))
                  (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

;; Helper: round-trip through pack/unpack
(define (roundtrip val)
  (msgpack-unpack (msgpack-pack val)))

;; Helper: test that a value round-trips with a custom comparison
(define-syntax test-rt
  (syntax-rules ()
    [(_ name val)
     (test name (roundtrip val) val)]))

(printf "--- (std text msgpack) tests ---~%")

;; === nil ===
(printf "~%nil:~%")
(test "nil/void round-trip"
  (eq? (roundtrip (void)) (void)) #t)
(test "nil encodes to #xc0"
  (msgpack-pack (void)) #vu8(#xc0))
(test "null list encodes to nil"
  (msgpack-pack '()) #vu8(#xc0))

;; === Booleans ===
(printf "~%booleans:~%")
(test-rt "true" #t)
(test-rt "false" #f)
(test "true encodes to #xc3" (msgpack-pack #t) #vu8(#xc3))
(test "false encodes to #xc2" (msgpack-pack #f) #vu8(#xc2))

;; === Positive fixint (0-127) ===
(printf "~%positive fixint:~%")
(test-rt "zero" 0)
(test-rt "one" 1)
(test-rt "127" 127)
(test "0 encodes to single byte" (msgpack-pack 0) #vu8(0))
(test "127 encodes to single byte" (msgpack-pack 127) #vu8(127))
(test "42 encodes to single byte" (msgpack-pack 42) #vu8(42))

;; === Negative fixint (-32 to -1) ===
(printf "~%negative fixint:~%")
(test-rt "-1" -1)
(test-rt "-32" -32)
(test "-1 encodes to #xff" (msgpack-pack -1) #vu8(#xff))
(test "-32 encodes to #xe0" (msgpack-pack -32) #vu8(#xe0))

;; === uint 8 (128-255) ===
(printf "~%uint8:~%")
(test-rt "128" 128)
(test-rt "255" 255)
(test "128 uses uint8 prefix" (bytevector-u8-ref (msgpack-pack 128) 0) #xcc)
(test "255 uses uint8 prefix" (bytevector-u8-ref (msgpack-pack 255) 0) #xcc)

;; === uint 16 (256-65535) ===
(printf "~%uint16:~%")
(test-rt "256" 256)
(test-rt "65535" 65535)
(test "256 uses uint16 prefix" (bytevector-u8-ref (msgpack-pack 256) 0) #xcd)
(test "1000 big-endian encoding"
  (msgpack-pack 1000) #vu8(#xcd #x03 #xe8))

;; === uint 32 ===
(printf "~%uint32:~%")
(test-rt "65536" 65536)
(test-rt "max-uint32" #xffffffff)
(test "65536 uses uint32 prefix" (bytevector-u8-ref (msgpack-pack 65536) 0) #xce)

;; === uint 64 ===
(printf "~%uint64:~%")
(test-rt "large uint64" #x100000000)
(test-rt "max-uint64" #xffffffffffffffff)
(test "uint64 prefix" (bytevector-u8-ref (msgpack-pack #x100000000) 0) #xcf)

;; === int 8 (-128 to -33) ===
(printf "~%int8:~%")
(test-rt "-33" -33)
(test-rt "-128" -128)
(test "-33 uses int8 prefix" (bytevector-u8-ref (msgpack-pack -33) 0) #xd0)
(test "-128 uses int8 prefix" (bytevector-u8-ref (msgpack-pack -128) 0) #xd0)

;; === int 16 (-32768 to -129) ===
(printf "~%int16:~%")
(test-rt "-129" -129)
(test-rt "-32768" -32768)
(test "-129 uses int16 prefix" (bytevector-u8-ref (msgpack-pack -129) 0) #xd1)

;; === int 32 ===
(printf "~%int32:~%")
(test-rt "-32769" -32769)
(test-rt "min-int32" (- (expt 2 31)))
(test "-32769 uses int32 prefix" (bytevector-u8-ref (msgpack-pack -32769) 0) #xd2)

;; === int 64 ===
(printf "~%int64:~%")
(test-rt "large negative" (- (expt 2 31) 1))  ;; this fits in int32+, but test boundary
(let ([v (- (+ (expt 2 31) 1))])
  (test-rt "int64 negative" v))
(test-rt "min-int64" (- (expt 2 63)))

;; === float 64 ===
(printf "~%float64:~%")
(test-rt "pi" 3.14159265358979)
(test-rt "negative float" -2.5)
(test-rt "zero float" 0.0)
(test "float uses #xcb prefix" (bytevector-u8-ref (msgpack-pack 1.0) 0) #xcb)

;; Float special values
(test "positive infinity"
  (fl= (roundtrip +inf.0) +inf.0) #t)
(test "negative infinity"
  (fl= (roundtrip -inf.0) -inf.0) #t)
(test "NaN round-trips to NaN"
  (flnan? (roundtrip +nan.0)) #t)

;; === fixstr (0-31 bytes) ===
(printf "~%strings:~%")
(test-rt "empty string" "")
(test-rt "hello" "hello")
(test-rt "31-byte string" (make-string 31 #\a))
(test "empty string encoding" (msgpack-pack "") #vu8(#xa0))
(test "fixstr prefix for 'hi'"
  (bytevector-u8-ref (msgpack-pack "hi") 0) #xa2)

;; === str 8 (32-255 bytes) ===
(test-rt "32-char string" (make-string 32 #\x))
(test "str8 prefix"
  (bytevector-u8-ref (msgpack-pack (make-string 32 #\x)) 0) #xd9)

;; === str 16 (256-65535 bytes) ===
(test-rt "300-char string" (make-string 300 #\y))
(test "str16 prefix"
  (bytevector-u8-ref (msgpack-pack (make-string 300 #\y)) 0) #xda)

;; === UTF-8 strings ===
(test-rt "UTF-8 multibyte" "\x3BB;")  ;; lambda
(test-rt "UTF-8 emoji" "\x1F600;")    ;; grinning face

;; === bin (bytevectors) ===
(printf "~%binary:~%")
(test-rt "empty bytevector" #vu8())
(test-rt "small bytevector" #vu8(1 2 3 4 5))
(test "bin8 prefix"
  (bytevector-u8-ref (msgpack-pack #vu8(1 2 3)) 0) #xc4)
;; 256-byte bin → bin16
(let ([bv (make-bytevector 256 #xab)])
  (test-rt "256-byte bytevector" bv)
  (test "bin16 prefix"
    (bytevector-u8-ref (msgpack-pack bv) 0) #xc5))

;; === fixarray (vectors, 0-15 elements) ===
(printf "~%arrays (vectors):~%")
(test-rt "empty vector" (vector))
(test-rt "single element" (vector 42))
(test-rt "mixed vector" (vector 1 "two" 3))
(test "fixarray prefix for [1,2,3]"
  (bytevector-u8-ref (msgpack-pack (vector 1 2 3)) 0) #x93)

;; === array 16 ===
(let ([vec (make-vector 16 0)])
  (test-rt "16-element vector" vec)
  (test "array16 prefix"
    (bytevector-u8-ref (msgpack-pack vec) 0) #xdc))

;; === Nested arrays ===
(test-rt "nested vectors" (vector (vector 1 2) (vector 3 4)))

;; === fixmap (alists, 0-15 pairs) ===
(printf "~%maps (alists):~%")
(test-rt "single-entry map" '(("a" . 1)))
(test "fixmap prefix"
  (bitwise-and (bytevector-u8-ref (msgpack-pack '(("a" . 1))) 0) #xf0) #x80)

;; Multi-entry map
(let* ([input '(("x" . 10) ("y" . 20) ("z" . 30))]
       [result (roundtrip input)])
  ;; Alist order should be preserved
  (test "multi-entry map round-trip" result input))

;; Nested map
(let* ([input '(("inner" . (("a" . 1))))]
       [result (roundtrip input)])
  (test "nested map round-trip" result input))

;; Map with various value types
(let* ([input (list (cons "int" 42) (cons "str" "hello") (cons "bool" #t) (cons "vec" (vector 1 2)))]
       [result (roundtrip input)])
  (test "map with mixed values" result input))

;; === Port-based API ===
(printf "~%port API:~%")
(let-values ([(out extract) (open-bytevector-output-port)])
  (msgpack-pack-port 42 out)
  (msgpack-pack-port "hello" out)
  (let* ([bv (extract)]
         [in (open-bytevector-input-port bv)]
         [v1 (msgpack-unpack-port in)]
         [v2 (msgpack-unpack-port in)])
    (test "port: first value" v1 42)
    (test "port: second value" v2 "hello")))

;; Multiple values via port
(let-values ([(out extract) (open-bytevector-output-port)])
  (msgpack-pack-port (vector 1 2 3) out)
  (msgpack-pack-port '(("key" . "val")) out)
  (let* ([bv (extract)]
         [in (open-bytevector-input-port bv)]
         [v1 (msgpack-unpack-port in)]
         [v2 (msgpack-unpack-port in)])
    (test "port: vector" v1 (vector 1 2 3))
    (test "port: map" v2 '(("key" . "val")))))

;; === Compact encoding verification ===
(printf "~%compact encoding:~%")
;; Verify integers use minimal encoding
(test "0 is 1 byte" (bytevector-length (msgpack-pack 0)) 1)
(test "127 is 1 byte" (bytevector-length (msgpack-pack 127)) 1)
(test "-1 is 1 byte" (bytevector-length (msgpack-pack -1)) 1)
(test "-32 is 1 byte" (bytevector-length (msgpack-pack -32)) 1)
(test "128 is 2 bytes" (bytevector-length (msgpack-pack 128)) 2)
(test "255 is 2 bytes" (bytevector-length (msgpack-pack 255)) 2)
(test "256 is 3 bytes" (bytevector-length (msgpack-pack 256)) 3)
(test "-33 is 2 bytes" (bytevector-length (msgpack-pack -33)) 2)

;; === Decode known byte sequences (cross-implementation compatibility) ===
(printf "~%known encodings:~%")
;; These are well-known msgpack encodings
(test "decode nil" (eq? (msgpack-unpack #vu8(#xc0)) (void)) #t)
(test "decode true" (msgpack-unpack #vu8(#xc3)) #t)
(test "decode false" (msgpack-unpack #vu8(#xc2)) #f)
(test "decode fixint 0" (msgpack-unpack #vu8(#x00)) 0)
(test "decode fixint 127" (msgpack-unpack #vu8(#x7f)) 127)
(test "decode neg fixint -1" (msgpack-unpack #vu8(#xff)) -1)
(test "decode neg fixint -32" (msgpack-unpack #vu8(#xe0)) -32)
(test "decode empty fixstr" (msgpack-unpack #vu8(#xa0)) "")
(test "decode fixstr 'AB'"
  (msgpack-unpack #vu8(#xa2 #x41 #x42)) "AB")
(test "decode empty fixarray" (msgpack-unpack #vu8(#x90)) (vector))
(test "decode fixarray [1,2,3]"
  (msgpack-unpack #vu8(#x93 1 2 3)) (vector 1 2 3))
(test "decode empty fixmap" (msgpack-unpack #vu8(#x80)) '())
(test "decode uint8 200"
  (msgpack-unpack #vu8(#xcc #xc8)) 200)
(test "decode int8 -100"
  (msgpack-unpack #vu8(#xd0 #x9c)) -100)

;; Float32 decoding
(let ([bv (make-bytevector 5)])
  (bytevector-u8-set! bv 0 #xca)
  (bytevector-ieee-single-set! bv 1 1.5 (endianness big))
  (test "decode float32" (msgpack-unpack bv) 1.5))

;; === Edge cases ===
(printf "~%edge cases:~%")
;; Empty structures
(test-rt "empty vector" (vector))
(test-rt "empty bytevector" #vu8())
(test-rt "empty string" "")

;; Max values for each integer type
(test-rt "max positive fixint" 127)
(test-rt "max uint8" 255)
(test-rt "max uint16" 65535)
(test-rt "max uint32" #xffffffff)
(test-rt "max uint64" #xffffffffffffffff)
(test-rt "min negative fixint" -32)
(test-rt "min int8" -128)
(test-rt "min int16" -32768)
(test-rt "min int32" (- (expt 2 31)))
(test-rt "min int64" (- (expt 2 63)))

;; Deeply nested structure
(test-rt "nested structure"
  (vector (vector (vector "deep"))))

;; Map with integer keys
(test-rt "map with int keys" '((1 . "one") (2 . "two")))

;; Vector containing maps
(test-rt "vector of maps"
  (vector '(("a" . 1)) '(("b" . 2))))

;; === Summary ===
(printf "~%--- Results: ~a passed, ~a failed ---~%" pass fail)
(when (> fail 0) (exit 1))
