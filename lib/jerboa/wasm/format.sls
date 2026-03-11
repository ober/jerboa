#!chezscheme
;;; (jerboa wasm format) -- WebAssembly binary format encoding/decoding
;;;
;;; Implements the WebAssembly binary format per the WASM spec:
;;;   - LEB128 integer encoding (unsigned and signed)
;;;   - IEEE 754 float encoding
;;;   - String encoding (LEB128 length + UTF-8)
;;;   - Section IDs, type constants, opcode constants
;;;   - Bytevector builder for accumulating bytes

(library (jerboa wasm format)
  (export
    ;; Module header constants
    wasm-magic wasm-version
    ;; LEB128 encoding
    encode-u32-leb128 decode-u32-leb128
    encode-i32-leb128 encode-i64-leb128
    decode-i32-leb128
    ;; Float encoding
    encode-f32 encode-f64 decode-f32 decode-f64
    ;; String encoding
    encode-string decode-string
    ;; Value types
    wasm-type-i32 wasm-type-i64 wasm-type-f32 wasm-type-f64
    wasm-type-funcref wasm-type-externref
    ;; Section IDs
    wasm-section-custom wasm-section-type wasm-section-import
    wasm-section-function wasm-section-table wasm-section-memory
    wasm-section-global wasm-section-export wasm-section-start
    wasm-section-element wasm-section-code wasm-section-data
    ;; Control flow opcodes
    wasm-opcode-unreachable wasm-opcode-nop
    wasm-opcode-block wasm-opcode-loop wasm-opcode-if wasm-opcode-else wasm-opcode-end
    wasm-opcode-br wasm-opcode-br-if
    wasm-opcode-return wasm-opcode-call wasm-opcode-call-indirect
    wasm-opcode-drop wasm-opcode-select
    ;; Variable opcodes
    wasm-opcode-local-get wasm-opcode-local-set wasm-opcode-local-tee
    wasm-opcode-global-get wasm-opcode-global-set
    ;; Memory opcodes
    wasm-opcode-i32-load wasm-opcode-i64-load wasm-opcode-f32-load wasm-opcode-f64-load
    wasm-opcode-i32-store wasm-opcode-i64-store
    wasm-opcode-memory-size wasm-opcode-memory-grow
    ;; Numeric const opcodes
    wasm-opcode-i32-const wasm-opcode-i64-const
    wasm-opcode-f32-const wasm-opcode-f64-const
    ;; i32 comparison opcodes
    wasm-opcode-i32-eqz wasm-opcode-i32-eq wasm-opcode-i32-ne
    wasm-opcode-i32-lt-s wasm-opcode-i32-lt-u
    wasm-opcode-i32-gt-s wasm-opcode-i32-gt-u
    wasm-opcode-i32-le-s wasm-opcode-i32-ge-s
    ;; i32 arithmetic opcodes
    wasm-opcode-i32-add wasm-opcode-i32-sub wasm-opcode-i32-mul
    wasm-opcode-i32-div-s wasm-opcode-i32-rem-s
    wasm-opcode-i32-and wasm-opcode-i32-or wasm-opcode-i32-xor
    wasm-opcode-i32-shl wasm-opcode-i32-shr-s
    ;; i64 arithmetic opcodes
    wasm-opcode-i64-add wasm-opcode-i64-sub wasm-opcode-i64-mul wasm-opcode-i64-div-s
    ;; f32 arithmetic opcodes
    wasm-opcode-f32-add wasm-opcode-f32-sub wasm-opcode-f32-mul wasm-opcode-f32-div
    ;; f64 arithmetic opcodes
    wasm-opcode-f64-add wasm-opcode-f64-sub wasm-opcode-f64-mul wasm-opcode-f64-div
    ;; Bytevector builder
    make-bytevector-builder
    bytevector-builder-append-u8!
    bytevector-builder-append-bv!
    bytevector-builder-build
    bytevector-builder-length)

  (import (chezscheme))

  ;;; ========== Module header constants ==========

  ;; WASM magic: "\0asm" as bytes
  (define wasm-magic (bytevector #x00 #x61 #x73 #x6D))
  ;; WASM version 1
  (define wasm-version (bytevector #x01 #x00 #x00 #x00))

  ;;; ========== Value types ==========

  (define wasm-type-i32     #x7F)
  (define wasm-type-i64     #x7E)
  (define wasm-type-f32     #x7D)
  (define wasm-type-f64     #x7C)
  (define wasm-type-funcref    #x70)
  (define wasm-type-externref  #x6F)

  ;;; ========== Section IDs ==========

  (define wasm-section-custom   0)
  (define wasm-section-type     1)
  (define wasm-section-import   2)
  (define wasm-section-function 3)
  (define wasm-section-table    4)
  (define wasm-section-memory   5)
  (define wasm-section-global   6)
  (define wasm-section-export   7)
  (define wasm-section-start    8)
  (define wasm-section-element  9)
  (define wasm-section-code    10)
  (define wasm-section-data    11)

  ;;; ========== Opcodes ==========

  ;; Control flow
  (define wasm-opcode-unreachable   #x00)
  (define wasm-opcode-nop           #x01)
  (define wasm-opcode-block         #x02)
  (define wasm-opcode-loop          #x03)
  (define wasm-opcode-if            #x04)
  (define wasm-opcode-else          #x05)
  (define wasm-opcode-end           #x0B)
  (define wasm-opcode-br            #x0C)
  (define wasm-opcode-br-if         #x0D)
  (define wasm-opcode-return        #x0F)
  (define wasm-opcode-call          #x10)
  (define wasm-opcode-call-indirect #x11)
  (define wasm-opcode-drop          #x1A)
  (define wasm-opcode-select        #x1B)

  ;; Variable access
  (define wasm-opcode-local-get     #x20)
  (define wasm-opcode-local-set     #x21)
  (define wasm-opcode-local-tee     #x22)
  (define wasm-opcode-global-get    #x23)
  (define wasm-opcode-global-set    #x24)

  ;; Memory
  (define wasm-opcode-i32-load      #x28)
  (define wasm-opcode-i64-load      #x29)
  (define wasm-opcode-f32-load      #x2A)
  (define wasm-opcode-f64-load      #x2B)
  (define wasm-opcode-i32-store     #x36)
  (define wasm-opcode-i64-store     #x37)
  (define wasm-opcode-memory-size   #x3F)
  (define wasm-opcode-memory-grow   #x40)

  ;; Constants
  (define wasm-opcode-i32-const     #x41)
  (define wasm-opcode-i64-const     #x42)
  (define wasm-opcode-f32-const     #x43)
  (define wasm-opcode-f64-const     #x44)

  ;; i32 comparisons
  (define wasm-opcode-i32-eqz      #x45)
  (define wasm-opcode-i32-eq       #x46)
  (define wasm-opcode-i32-ne       #x47)
  (define wasm-opcode-i32-lt-s     #x48)
  (define wasm-opcode-i32-lt-u     #x49)
  (define wasm-opcode-i32-gt-s     #x4A)
  (define wasm-opcode-i32-gt-u     #x4B)
  (define wasm-opcode-i32-le-s     #x4C)
  (define wasm-opcode-i32-ge-s     #x4E)

  ;; i32 arithmetic
  (define wasm-opcode-i32-add      #x6A)
  (define wasm-opcode-i32-sub      #x6B)
  (define wasm-opcode-i32-mul      #x6C)
  (define wasm-opcode-i32-div-s    #x6D)
  (define wasm-opcode-i32-rem-s    #x6F)
  (define wasm-opcode-i32-and      #x71)
  (define wasm-opcode-i32-or       #x72)
  (define wasm-opcode-i32-xor      #x73)
  (define wasm-opcode-i32-shl      #x74)
  (define wasm-opcode-i32-shr-s    #x75)

  ;; i64 arithmetic
  (define wasm-opcode-i64-add      #x7C)
  (define wasm-opcode-i64-sub      #x7D)
  (define wasm-opcode-i64-mul      #x7E)
  (define wasm-opcode-i64-div-s    #x7F)

  ;; f32 arithmetic
  (define wasm-opcode-f32-add      #x92)
  (define wasm-opcode-f32-sub      #x93)
  (define wasm-opcode-f32-mul      #x94)
  (define wasm-opcode-f32-div      #x95)

  ;; f64 arithmetic
  (define wasm-opcode-f64-add      #xA0)
  (define wasm-opcode-f64-sub      #xA1)
  (define wasm-opcode-f64-mul      #xA2)
  (define wasm-opcode-f64-div      #xA3)

  ;;; ========== Bytevector builder ==========

  ;; A simple accumulator: list of bytevectors in reverse order + total length
  (define-record-type bytevector-builder
    (fields (mutable chunks) (mutable total-length))
    (protocol (lambda (new) (lambda () (new '() 0)))))

  (define (bytevector-builder-append-u8! builder byte)
    (let ([bv (make-bytevector 1 byte)])
      (bytevector-builder-chunks-set! builder
        (cons bv (bytevector-builder-chunks builder)))
      (bytevector-builder-total-length-set! builder
        (+ (bytevector-builder-total-length builder) 1))))

  (define (bytevector-builder-append-bv! builder bv)
    (let ([len (bytevector-length bv)])
      (when (> len 0)
        (bytevector-builder-chunks-set! builder
          (cons bv (bytevector-builder-chunks builder)))
        (bytevector-builder-total-length-set! builder
          (+ (bytevector-builder-total-length builder) len)))))

  (define (bytevector-builder-length builder)
    (bytevector-builder-total-length builder))

  (define (bytevector-builder-build builder)
    (let* ([total (bytevector-builder-total-length builder)]
           [result (make-bytevector total)]
           [chunks (reverse (bytevector-builder-chunks builder))])
      (let loop ([chunks chunks] [offset 0])
        (if (null? chunks)
          result
          (let* ([chunk (car chunks)]
                 [len (bytevector-length chunk)])
            ;; bytevector-copy! in Chez: src src-start dst dst-start count
            (bytevector-copy! chunk 0 result offset len)
            (loop (cdr chunks) (+ offset len)))))))

  ;;; ========== LEB128 encoding ==========

  ;; Unsigned LEB128: encode non-negative integer
  (define (encode-u32-leb128 n)
    (let ([builder (make-bytevector-builder)])
      (let loop ([n n])
        (let ([byte (bitwise-and n #x7F)]
              [rest (bitwise-arithmetic-shift-right n 7)])
          (if (= rest 0)
            (begin
              (bytevector-builder-append-u8! builder byte)
              (bytevector-builder-build builder))
            (begin
              (bytevector-builder-append-u8! builder (bitwise-ior byte #x80))
              (loop rest)))))))

  ;; Decode unsigned LEB128 from bytevector at offset
  ;; Returns (value . bytes-consumed)
  (define (decode-u32-leb128 bv offset)
    (let loop ([result 0] [shift 0] [pos offset])
      (let ([byte (bytevector-u8-ref bv pos)])
        (let ([val (bitwise-ior result
                     (bitwise-arithmetic-shift-left
                       (bitwise-and byte #x7F)
                       shift))])
          (if (= (bitwise-and byte #x80) 0)
            (cons val (- (+ pos 1) offset))
            (loop val (+ shift 7) (+ pos 1)))))))

  ;; Signed LEB128 for i32
  (define (encode-i32-leb128 n)
    (let ([builder (make-bytevector-builder)])
      (let loop ([n n] [more #t])
        (when more
          (let* ([byte (bitwise-and n #x7F)]
                 [n-shifted (bitwise-arithmetic-shift n -7)]
                 [done? (or (and (= n-shifted 0) (= (bitwise-and byte #x40) 0))
                            (and (= n-shifted -1) (not (= (bitwise-and byte #x40) 0))))])
            (bytevector-builder-append-u8! builder
              (if done? byte (bitwise-ior byte #x80)))
            (loop n-shifted (not done?)))))
      (bytevector-builder-build builder)))

  ;; Signed LEB128 for i64 (same algorithm)
  (define (encode-i64-leb128 n)
    (encode-i32-leb128 n))

  ;; Decode signed LEB128 from bytevector at offset
  ;; Returns (value . bytes-consumed)
  (define (decode-i32-leb128 bv offset)
    (let loop ([result 0] [shift 0] [pos offset])
      (let ([byte (bytevector-u8-ref bv pos)])
        (let ([val (bitwise-ior result
                     (bitwise-arithmetic-shift-left
                       (bitwise-and byte #x7F)
                       shift))])
          (if (= (bitwise-and byte #x80) 0)
            ;; Sign extend if high bit of last group is set
            (let ([final-val
                   (if (and (< shift 32)
                            (not (= (bitwise-and byte #x40) 0)))
                     (bitwise-ior val
                       (bitwise-arithmetic-shift-left -1 (+ shift 7)))
                     val)])
              (cons final-val (- (+ pos 1) offset)))
            (loop val (+ shift 7) (+ pos 1)))))))

  ;;; ========== Float encoding ==========

  ;; Encode f32 as 4 bytes little-endian IEEE 754
  (define (encode-f32 val)
    (let ([bv (make-bytevector 4)])
      (bytevector-ieee-single-set! bv 0 val 'little)
      bv))

  ;; Decode f32 from 4 bytes little-endian IEEE 754
  (define (decode-f32 bv offset)
    (bytevector-ieee-single-ref bv offset 'little))

  ;; Encode f64 as 8 bytes little-endian IEEE 754
  (define (encode-f64 val)
    (let ([bv (make-bytevector 8)])
      (bytevector-ieee-double-set! bv 0 val 'little)
      bv))

  ;; Decode f64 from 8 bytes little-endian IEEE 754
  (define (decode-f64 bv offset)
    (bytevector-ieee-double-ref bv offset 'little))

  ;;; ========== String encoding ==========

  ;; Encode string: LEB128 length (in bytes) + UTF-8 bytes
  (define (encode-string s)
    (let* ([utf8 (string->utf8 s)]
           [len (bytevector-length utf8)]
           [len-bv (encode-u32-leb128 len)]
           [result (make-bytevector (+ (bytevector-length len-bv) len))])
      (bytevector-copy! len-bv 0 result 0 (bytevector-length len-bv))
      (bytevector-copy! utf8 0 result (bytevector-length len-bv) len)
      result))

  ;; Decode string from bytevector at offset
  ;; Returns (string . bytes-consumed)
  (define (decode-string bv offset)
    (let* ([len-result (decode-u32-leb128 bv offset)]
           [str-len (car len-result)]
           [len-bytes (cdr len-result)]
           [str-start (+ offset len-bytes)]
           [utf8 (make-bytevector str-len)])
      (bytevector-copy! bv str-start utf8 0 str-len)
      (cons (utf8->string utf8) (+ len-bytes str-len))))

) ;; end library
