#!chezscheme
;;; Tests for (jerboa wasm format) -- WebAssembly binary format

(import (chezscheme)
        (jerboa wasm format))

(define pass 0)
(define fail 0)

;; Chez Scheme does not have bytevector->list; provide it
(define (bytevector->list bv)
  (map (lambda (i) (bytevector-u8-ref bv i))
       (iota (bytevector-length bv))))

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(printf "--- Phase 3e: WASM Format ---~%~%")

;;; ======== Module header constants ========

(test "wasm-magic bytes"
  (bytevector->list wasm-magic)
  '(#x00 #x61 #x73 #x6D))

(test "wasm-version bytes"
  (bytevector->list wasm-version)
  '(#x01 #x00 #x00 #x00))

;;; ======== LEB128 unsigned encoding ========

(test "encode-u32 zero"
  (bytevector->list (encode-u32-leb128 0))
  '(#x00))

(test "encode-u32 small (1)"
  (bytevector->list (encode-u32-leb128 1))
  '(#x01))

(test "encode-u32 127"
  (bytevector->list (encode-u32-leb128 127))
  '(#x7F))

(test "encode-u32 128 (two bytes)"
  (bytevector->list (encode-u32-leb128 128))
  '(#x80 #x01))

(test "encode-u32 300"
  (bytevector->list (encode-u32-leb128 300))
  '(#xAC #x02))

(test "encode-u32 624485"
  (bytevector->list (encode-u32-leb128 624485))
  '(#xE5 #x8E #x26))

;;; ======== LEB128 unsigned decoding ========

(test "decode-u32 zero"
  (decode-u32-leb128 (bytevector #x00) 0)
  '(0 . 1))

(test "decode-u32 one"
  (decode-u32-leb128 (bytevector #x01) 0)
  '(1 . 1))

(test "decode-u32 127"
  (decode-u32-leb128 (bytevector #x7F) 0)
  '(127 . 1))

(test "decode-u32 128"
  (decode-u32-leb128 (bytevector #x80 #x01) 0)
  '(128 . 2))

(test "decode-u32 300"
  (decode-u32-leb128 (bytevector #xAC #x02) 0)
  '(300 . 2))

(test "decode-u32 624485"
  (decode-u32-leb128 (bytevector #xE5 #x8E #x26) 0)
  '(624485 . 3))

;;; ======== Round-trip u32 LEB128 ========

(test "round-trip u32 0"
  (car (decode-u32-leb128 (encode-u32-leb128 0) 0))
  0)

(test "round-trip u32 65535"
  (car (decode-u32-leb128 (encode-u32-leb128 65535) 0))
  65535)

(test "round-trip u32 1000000"
  (car (decode-u32-leb128 (encode-u32-leb128 1000000) 0))
  1000000)

;;; ======== LEB128 signed encoding ========

(test "encode-i32 zero"
  (bytevector->list (encode-i32-leb128 0))
  '(#x00))

(test "encode-i32 positive 42"
  (bytevector->list (encode-i32-leb128 42))
  '(#x2A))

(test "encode-i32 negative -1"
  (bytevector->list (encode-i32-leb128 -1))
  '(#x7F))

(test "encode-i32 negative -128"
  (bytevector->list (encode-i32-leb128 -128))
  '(#x80 #x7F))

;;; ======== Round-trip i32 LEB128 ========

(test "round-trip i32 -1"
  (car (decode-i32-leb128 (encode-i32-leb128 -1) 0))
  -1)

(test "round-trip i32 -1000"
  (car (decode-i32-leb128 (encode-i32-leb128 -1000) 0))
  -1000)

(test "round-trip i32 1000"
  (car (decode-i32-leb128 (encode-i32-leb128 1000) 0))
  1000)

;;; ======== Float encoding ========

(test "encode-f32 0.0 length"
  (bytevector-length (encode-f32 0.0))
  4)

(test "decode-f32 round-trip 1.0"
  (decode-f32 (encode-f32 1.0) 0)
  1.0)

(test "decode-f32 round-trip -2.5"
  (decode-f32 (encode-f32 -2.5) 0)
  -2.5)

(test "encode-f64 0.0 length"
  (bytevector-length (encode-f64 0.0))
  8)

(test "decode-f64 round-trip 3.14"
  (let ([v (decode-f64 (encode-f64 3.14) 0)])
    (< (abs (- v 3.14)) 1e-15))
  #t)

;;; ======== String encoding ========

(test "encode-string empty"
  (bytevector->list (encode-string ""))
  '(#x00))

(test "encode-string 'hi'"
  (bytevector->list (encode-string "hi"))
  '(#x02 #x68 #x69))

(test "decode-string 'hi'"
  (decode-string (bytevector #x02 #x68 #x69) 0)
  '("hi" . 3))

(test "string round-trip 'hello'"
  (car (decode-string (encode-string "hello") 0))
  "hello")

;;; ======== Section and type constants ========

(test "section-type id"
  wasm-section-type
  1)

(test "section-code id"
  wasm-section-code
  10)

(test "type-i32"
  wasm-type-i32
  #x7F)

(test "opcode-i32-add"
  wasm-opcode-i32-add
  #x6A)

(test "opcode-end"
  wasm-opcode-end
  #x0B)

;;; ======== Bytevector builder ========

(test "builder empty"
  (bytevector-length (bytevector-builder-build (make-bytevector-builder)))
  0)

(test "builder append u8"
  (let ([b (make-bytevector-builder)])
    (bytevector-builder-append-u8! b 42)
    (bytevector-builder-append-u8! b 99)
    (bytevector->list (bytevector-builder-build b)))
  '(42 99))

(test "builder append bv"
  (let ([b (make-bytevector-builder)])
    (bytevector-builder-append-bv! b (bytevector 1 2 3))
    (bytevector-builder-append-bv! b (bytevector 4 5))
    (bytevector->list (bytevector-builder-build b)))
  '(1 2 3 4 5))

(test "builder length"
  (let ([b (make-bytevector-builder)])
    (bytevector-builder-append-u8! b 1)
    (bytevector-builder-append-bv! b (bytevector 2 3 4))
    (bytevector-builder-length b))
  4)

;;; Summary

(printf "~%WASM Format: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
