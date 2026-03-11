#!chezscheme
;;; Tests for (std binary) — Structured binary data

(import (chezscheme) (std binary))

(define pass 0)
(define fail 0)

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
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define-syntax test-pred
  (syntax-rules ()
    [(_ name expr pred)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (pred got)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: value ~s failed predicate~%" name got)))))]))

(printf "--- (std binary) tests ---~%")

;; ========== Byte order parameter ==========

(test "byte-order/default is little"
  (*byte-order*)
  'little)

(test "byte-order/with-byte-order changes it"
  (with-byte-order 'big
    (*byte-order*))
  'big)

(test "byte-order/restored after with-byte-order"
  (begin
    (with-byte-order 'big (void))
    (*byte-order*))
  'little)

;; ========== Low-level bv-u8 ==========

(test "bv-u8/set and get"
  (let ([bv (make-bytevector 4 0)])
    (bv-u8-set! bv 2 255)
    (bv-u8-ref bv 2))
  255)

(test "bv-s8/set and get negative"
  (let ([bv (make-bytevector 4 0)])
    (bv-s8-set! bv 0 -1)
    (bv-s8-ref bv 0))
  -1)

;; ========== Low-level bv-u16 ==========

(test "bv-u16/little-endian round-trip"
  (with-byte-order 'little
    (let ([bv (make-bytevector 4 0)])
      (bv-u16-set! bv 0 1000)
      (bv-u16-ref bv 0)))
  1000)

(test "bv-u16/big-endian round-trip"
  (with-byte-order 'big
    (let ([bv (make-bytevector 4 0)])
      (bv-u16-set! bv 0 1000)
      (bv-u16-ref bv 0)))
  1000)

(test "bv-s16/negative round-trip"
  (with-byte-order 'little
    (let ([bv (make-bytevector 4 0)])
      (bv-s16-set! bv 0 -500)
      (bv-s16-ref bv 0)))
  -500)

;; ========== Low-level bv-u32 ==========

(test "bv-u32/round-trip"
  (let ([bv (make-bytevector 8 0)])
    (bv-u32-set! bv 0 #xDEADBEEF)
    (bv-u32-ref bv 0))
  #xDEADBEEF)

(test "bv-s32/negative round-trip"
  (let ([bv (make-bytevector 8 0)])
    (bv-s32-set! bv 0 -100000)
    (bv-s32-ref bv 0))
  -100000)

;; ========== Low-level bv-u64 ==========

(test "bv-u64/round-trip"
  (let ([bv (make-bytevector 8 0)])
    (bv-u64-set! bv 0 #xCAFEBABEDEADBEEF)
    (bv-u64-ref bv 0))
  #xCAFEBABEDEADBEEF)

;; ========== Low-level bv-f32 / bv-f64 ==========

(test-pred "bv-f32/round-trip"
  (let ([bv (make-bytevector 8 0)])
    (bv-f32-set! bv 0 3.14)
    (bv-f32-ref bv 0))
  (lambda (v) (< (abs (- v 3.14)) 0.001)))

(test-pred "bv-f64/round-trip"
  (let ([bv (make-bytevector 8 0)])
    (bv-f64-set! bv 0 3.141592653589793)
    (bv-f64-ref bv 0))
  (lambda (v) (< (abs (- v 3.141592653589793)) 1e-10)))

;; ========== define-binary-struct ==========

(define-binary-struct Point2D
  (x f32)
  (y f32))

(test "struct/Point2D size is 8"
  ;; pack-Point2D generates an 8-byte bytevector (2 x f32 = 2 x 4)
  (bytevector-length (pack-Point2D 0.0 0.0))
  8)

(test "struct/pack-Point2D produces bytevector"
  (bytevector? (pack-Point2D 1.0 2.0))
  #t)

(test "struct/pack-Point2D correct size"
  (bytevector-length (pack-Point2D 1.5 2.5))
  8)

(test "struct/unpack-Point2D round-trips"
  (let-values ([(x y) (unpack-Point2D (pack-Point2D 3.0 4.0))])
    (list (< (abs (- x 3.0)) 0.001)
          (< (abs (- y 4.0)) 0.001)))
  '(#t #t))

(define-binary-struct Header
  (magic   u32)
  (version u16)
  (flags   u8)
  (count   u32))

(test "struct/Header pack size"
  (bytevector-length (pack-Header 0 0 0 0))
  11)

(test "struct/Header round-trip via pack/unpack"
  (let-values ([(magic ver flags cnt) (unpack-Header (pack-Header #xDEAD 3 7 42))])
    (list magic ver flags cnt))
  (list #xDEAD 3 7 42))

;; ========== binary-pack ==========

(test "binary-pack/Point2D"
  (bytevector? (binary-pack 'Point2D 0.0 0.0))
  #t)

;; ========== binary-unpack ==========

(test "binary-unpack/Point2D with offset"
  (let* ([bv (make-bytevector 16 0)]
         [inner (pack-Point2D 5.0 6.0)])
    ;; Copy inner at offset 4
    (bytevector-copy! inner 0 bv 4 8)
    (let-values ([(x y) (unpack-Point2D bv 4)])
      (list (< (abs (- x 5.0)) 0.001)
            (< (abs (- y 6.0)) 0.001))))
  '(#t #t))

;; ========== binary-read / binary-write! ==========

(define-binary-struct Pixel
  (r u8)
  (g u8)
  (b u8)
  (a u8))

(test "read-write/Pixel round-trip"
  (let* ([bv     (make-bytevector 8 0)]
         [packed (pack-Pixel 255 128 64 32)])
    (bytevector-copy! packed 0 bv 0 4)
    (let ([rec (read-Pixel bv 0)])
      ;; rec is tagged alist: (Pixel (r . 255) ...)
      (list (cdr (assq 'r (cdr rec)))
            (cdr (assq 'g (cdr rec)))
            (cdr (assq 'b (cdr rec)))
            (cdr (assq 'a (cdr rec))))))
  '(255 128 64 32))

;; ========== bytes and cstring field types ==========

(define-binary-struct Message
  (id   u16)
  (data (bytes 8)))

(test "bytes-field/pack produces correct size"
  (bytevector-length (pack-Message 42 (make-bytevector 8 0)))
  10)

(test "bytes-field/round-trip"
  (let* ([payload (bytevector 1 2 3 4 5 6 7 8)]
         [bv      (pack-Message 99 payload)])
    (let-values ([(id data) (unpack-Message bv)])
      (equal? data payload)))
  #t)

(define-binary-struct Named
  (id   u8)
  (name (cstring 16)))

(test "cstring-field/pack size"
  (bytevector-length (pack-Named 1 "hello"))
  17)

(test "cstring-field/round-trip"
  (let-values ([(id name) (unpack-Named (pack-Named 7 "test"))])
    (list id name))
  '(7 "test"))

;; ========== big-endian byte order ==========

(test "big-endian/u16 bytes differ from little"
  (let ([le-bv (with-byte-order 'little (let ([b (make-bytevector 2 0)])
                                          (bv-u16-set! b 0 256) b))]
        [be-bv (with-byte-order 'big    (let ([b (make-bytevector 2 0)])
                                          (bv-u16-set! b 0 256) b))])
    ;; 256 = 0x0100: little-endian: [0 1], big-endian: [1 0]
    (and (= (bytevector-u8-ref le-bv 0) 0)
         (= (bytevector-u8-ref be-bv 0) 1)))
  #t)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
