#!chezscheme
;;; (jerboa wasm format) -- WebAssembly binary format encoding/decoding
;;;
;;; Implements the WebAssembly binary format per the WASM MVP spec:
;;;   - LEB128 integer encoding (unsigned and signed)
;;;   - IEEE 754 float encoding
;;;   - String encoding (LEB128 length + UTF-8)
;;;   - Section IDs, value types, all MVP opcode constants
;;;   - Bytevector builder for accumulating bytes

(library (jerboa wasm format)
  (export
    ;; Module header constants
    wasm-magic wasm-version

    ;; LEB128 encoding
    encode-u32-leb128 decode-u32-leb128
    encode-i32-leb128 encode-i64-leb128
    decode-i32-leb128 decode-i64-leb128

    ;; Float encoding
    encode-f32 encode-f64 decode-f32 decode-f64

    ;; String encoding
    encode-string decode-string

    ;; Value types
    wasm-type-i32 wasm-type-i64 wasm-type-f32 wasm-type-f64
    wasm-type-funcref wasm-type-externref
    wasm-type-void  ; 0x40 — empty block type

    ;; Section IDs
    wasm-section-custom wasm-section-type wasm-section-import
    wasm-section-function wasm-section-table wasm-section-memory
    wasm-section-global wasm-section-export wasm-section-start
    wasm-section-element wasm-section-code wasm-section-data
    wasm-section-data-count

    ;; ---- Control flow opcodes ----
    wasm-opcode-unreachable wasm-opcode-nop
    wasm-opcode-block wasm-opcode-loop wasm-opcode-if wasm-opcode-else wasm-opcode-end
    wasm-opcode-br wasm-opcode-br-if wasm-opcode-br-table
    wasm-opcode-return wasm-opcode-call wasm-opcode-call-indirect

    ;; ---- Parametric opcodes ----
    wasm-opcode-drop wasm-opcode-select

    ;; ---- Variable opcodes ----
    wasm-opcode-local-get wasm-opcode-local-set wasm-opcode-local-tee
    wasm-opcode-global-get wasm-opcode-global-set

    ;; ---- Memory opcodes ----
    wasm-opcode-i32-load wasm-opcode-i64-load wasm-opcode-f32-load wasm-opcode-f64-load
    wasm-opcode-i32-load8-s wasm-opcode-i32-load8-u
    wasm-opcode-i32-load16-s wasm-opcode-i32-load16-u
    wasm-opcode-i64-load8-s wasm-opcode-i64-load8-u
    wasm-opcode-i64-load16-s wasm-opcode-i64-load16-u
    wasm-opcode-i64-load32-s wasm-opcode-i64-load32-u
    wasm-opcode-i32-store wasm-opcode-i64-store
    wasm-opcode-f32-store wasm-opcode-f64-store
    wasm-opcode-i32-store8 wasm-opcode-i32-store16
    wasm-opcode-i64-store8 wasm-opcode-i64-store16 wasm-opcode-i64-store32
    wasm-opcode-memory-size wasm-opcode-memory-grow

    ;; ---- Numeric constant opcodes ----
    wasm-opcode-i32-const wasm-opcode-i64-const
    wasm-opcode-f32-const wasm-opcode-f64-const

    ;; ---- i32 comparison opcodes ----
    wasm-opcode-i32-eqz wasm-opcode-i32-eq wasm-opcode-i32-ne
    wasm-opcode-i32-lt-s wasm-opcode-i32-lt-u
    wasm-opcode-i32-gt-s wasm-opcode-i32-gt-u
    wasm-opcode-i32-le-s wasm-opcode-i32-le-u
    wasm-opcode-i32-ge-s wasm-opcode-i32-ge-u

    ;; ---- i32 arithmetic opcodes ----
    wasm-opcode-i32-clz wasm-opcode-i32-ctz wasm-opcode-i32-popcnt
    wasm-opcode-i32-add wasm-opcode-i32-sub wasm-opcode-i32-mul
    wasm-opcode-i32-div-s wasm-opcode-i32-div-u
    wasm-opcode-i32-rem-s wasm-opcode-i32-rem-u
    wasm-opcode-i32-and wasm-opcode-i32-or wasm-opcode-i32-xor
    wasm-opcode-i32-shl wasm-opcode-i32-shr-s wasm-opcode-i32-shr-u
    wasm-opcode-i32-rotl wasm-opcode-i32-rotr

    ;; ---- i64 comparison opcodes ----
    wasm-opcode-i64-eqz wasm-opcode-i64-eq wasm-opcode-i64-ne
    wasm-opcode-i64-lt-s wasm-opcode-i64-lt-u
    wasm-opcode-i64-gt-s wasm-opcode-i64-gt-u
    wasm-opcode-i64-le-s wasm-opcode-i64-le-u
    wasm-opcode-i64-ge-s wasm-opcode-i64-ge-u

    ;; ---- i64 arithmetic opcodes ----
    wasm-opcode-i64-clz wasm-opcode-i64-ctz wasm-opcode-i64-popcnt
    wasm-opcode-i64-add wasm-opcode-i64-sub wasm-opcode-i64-mul
    wasm-opcode-i64-div-s wasm-opcode-i64-div-u
    wasm-opcode-i64-rem-s wasm-opcode-i64-rem-u
    wasm-opcode-i64-and wasm-opcode-i64-or wasm-opcode-i64-xor
    wasm-opcode-i64-shl wasm-opcode-i64-shr-s wasm-opcode-i64-shr-u
    wasm-opcode-i64-rotl wasm-opcode-i64-rotr

    ;; ---- f32 comparison opcodes ----
    wasm-opcode-f32-eq wasm-opcode-f32-ne
    wasm-opcode-f32-lt wasm-opcode-f32-gt
    wasm-opcode-f32-le wasm-opcode-f32-ge

    ;; ---- f32 arithmetic opcodes ----
    wasm-opcode-f32-abs wasm-opcode-f32-neg
    wasm-opcode-f32-ceil wasm-opcode-f32-floor
    wasm-opcode-f32-trunc wasm-opcode-f32-nearest wasm-opcode-f32-sqrt
    wasm-opcode-f32-add wasm-opcode-f32-sub wasm-opcode-f32-mul wasm-opcode-f32-div
    wasm-opcode-f32-min wasm-opcode-f32-max wasm-opcode-f32-copysign

    ;; ---- f64 comparison opcodes ----
    wasm-opcode-f64-eq wasm-opcode-f64-ne
    wasm-opcode-f64-lt wasm-opcode-f64-gt
    wasm-opcode-f64-le wasm-opcode-f64-ge

    ;; ---- f64 arithmetic opcodes ----
    wasm-opcode-f64-abs wasm-opcode-f64-neg
    wasm-opcode-f64-ceil wasm-opcode-f64-floor
    wasm-opcode-f64-trunc wasm-opcode-f64-nearest wasm-opcode-f64-sqrt
    wasm-opcode-f64-add wasm-opcode-f64-sub wasm-opcode-f64-mul wasm-opcode-f64-div
    wasm-opcode-f64-min wasm-opcode-f64-max wasm-opcode-f64-copysign

    ;; ---- Conversion opcodes ----
    wasm-opcode-i32-wrap-i64
    wasm-opcode-i32-trunc-f32-s wasm-opcode-i32-trunc-f32-u
    wasm-opcode-i32-trunc-f64-s wasm-opcode-i32-trunc-f64-u
    wasm-opcode-i64-extend-i32-s wasm-opcode-i64-extend-i32-u
    wasm-opcode-i64-trunc-f32-s wasm-opcode-i64-trunc-f32-u
    wasm-opcode-i64-trunc-f64-s wasm-opcode-i64-trunc-f64-u
    wasm-opcode-f32-convert-i32-s wasm-opcode-f32-convert-i32-u
    wasm-opcode-f32-convert-i64-s wasm-opcode-f32-convert-i64-u
    wasm-opcode-f32-demote-f64
    wasm-opcode-f64-convert-i32-s wasm-opcode-f64-convert-i32-u
    wasm-opcode-f64-convert-i64-s wasm-opcode-f64-convert-i64-u
    wasm-opcode-f64-promote-f32
    wasm-opcode-i32-reinterpret-f32 wasm-opcode-i64-reinterpret-f64
    wasm-opcode-f32-reinterpret-i32 wasm-opcode-f64-reinterpret-i64

    ;; ---- Sign extension opcodes ----
    wasm-opcode-i32-extend8-s wasm-opcode-i32-extend16-s
    wasm-opcode-i64-extend8-s wasm-opcode-i64-extend16-s wasm-opcode-i64-extend32-s

    ;; ---- Post-MVP: GC value types ----
    wasm-type-anyref wasm-type-eqref wasm-type-i31ref
    wasm-type-structref wasm-type-arrayref
    wasm-type-nullref wasm-type-nullfuncref wasm-type-nullexternref
    wasm-type-noneref

    ;; ---- Post-MVP: Composite type tags ----
    wasm-composite-func wasm-composite-struct wasm-composite-array
    wasm-type-rec wasm-type-sub wasm-type-sub-final

    ;; ---- Post-MVP: Tag section ----
    wasm-section-tag

    ;; ---- Post-MVP: Prefix bytes ----
    wasm-prefix-fc wasm-prefix-fb

    ;; ---- Post-MVP: Tail call opcodes ----
    wasm-opcode-return-call wasm-opcode-return-call-indirect

    ;; ---- Post-MVP: Exception handling opcodes ----
    wasm-opcode-try wasm-opcode-catch wasm-opcode-throw
    wasm-opcode-rethrow wasm-opcode-delegate wasm-opcode-catch-all
    wasm-opcode-try-table wasm-opcode-throw-ref
    wasm-catch-kind wasm-catch-ref-kind wasm-catch-all-kind wasm-catch-all-ref-kind

    ;; ---- Post-MVP: Typed select ----
    wasm-opcode-select-t

    ;; ---- Post-MVP: Reference opcodes ----
    wasm-opcode-ref-null wasm-opcode-ref-is-null wasm-opcode-ref-func

    ;; ---- Post-MVP: Table opcodes ----
    wasm-opcode-table-get wasm-opcode-table-set

    ;; ---- Post-MVP: 0xFC sub-opcodes ----
    wasm-fc-i32-trunc-sat-f32-s wasm-fc-i32-trunc-sat-f32-u
    wasm-fc-i32-trunc-sat-f64-s wasm-fc-i32-trunc-sat-f64-u
    wasm-fc-i64-trunc-sat-f32-s wasm-fc-i64-trunc-sat-f32-u
    wasm-fc-i64-trunc-sat-f64-s wasm-fc-i64-trunc-sat-f64-u
    wasm-fc-memory-init wasm-fc-data-drop
    wasm-fc-memory-copy wasm-fc-memory-fill
    wasm-fc-table-init wasm-fc-elem-drop wasm-fc-table-copy
    wasm-fc-table-grow wasm-fc-table-size wasm-fc-table-fill

    ;; ---- Post-MVP: 0xFB sub-opcodes (GC proposal) ----
    wasm-fb-struct-new wasm-fb-struct-new-default
    wasm-fb-struct-get wasm-fb-struct-get-s wasm-fb-struct-get-u
    wasm-fb-struct-set
    wasm-fb-array-new wasm-fb-array-new-default
    wasm-fb-array-new-fixed wasm-fb-array-new-data wasm-fb-array-new-elem
    wasm-fb-array-get wasm-fb-array-get-s wasm-fb-array-get-u
    wasm-fb-array-set wasm-fb-array-len
    wasm-fb-array-fill wasm-fb-array-copy
    wasm-fb-array-init-data wasm-fb-array-init-elem
    wasm-fb-ref-test wasm-fb-ref-test-null
    wasm-fb-ref-cast wasm-fb-ref-cast-null
    wasm-fb-br-on-cast wasm-fb-br-on-cast-fail
    wasm-fb-extern-internalize wasm-fb-extern-externalize
    wasm-fb-ref-i31 wasm-fb-i31-get-s wasm-fb-i31-get-u

    ;; Bytevector builder
    make-bytevector-builder
    bytevector-builder-append-u8!
    bytevector-builder-append-bv!
    bytevector-builder-build
    bytevector-builder-length)

  (import (chezscheme))

  ;;; ========== Module header constants ==========

  (define wasm-magic (bytevector #x00 #x61 #x73 #x6D))
  (define wasm-version (bytevector #x01 #x00 #x00 #x00))

  ;;; ========== Value types ==========

  (define wasm-type-i32       #x7F)
  (define wasm-type-i64       #x7E)
  (define wasm-type-f32       #x7D)
  (define wasm-type-f64       #x7C)
  (define wasm-type-funcref   #x70)
  (define wasm-type-externref #x6F)
  (define wasm-type-void      #x40)  ; empty block type

  ;;; ========== Section IDs ==========

  (define wasm-section-custom     0)
  (define wasm-section-type       1)
  (define wasm-section-import     2)
  (define wasm-section-function   3)
  (define wasm-section-table      4)
  (define wasm-section-memory     5)
  (define wasm-section-global     6)
  (define wasm-section-export     7)
  (define wasm-section-start      8)
  (define wasm-section-element    9)
  (define wasm-section-code      10)
  (define wasm-section-data      11)
  (define wasm-section-data-count 12)

  ;;; ========== Opcodes: Control flow ==========

  (define wasm-opcode-unreachable   #x00)
  (define wasm-opcode-nop           #x01)
  (define wasm-opcode-block         #x02)
  (define wasm-opcode-loop          #x03)
  (define wasm-opcode-if            #x04)
  (define wasm-opcode-else          #x05)
  (define wasm-opcode-end           #x0B)
  (define wasm-opcode-br            #x0C)
  (define wasm-opcode-br-if         #x0D)
  (define wasm-opcode-br-table      #x0E)
  (define wasm-opcode-return        #x0F)
  (define wasm-opcode-call          #x10)
  (define wasm-opcode-call-indirect #x11)

  ;;; ========== Opcodes: Parametric ==========

  (define wasm-opcode-drop          #x1A)
  (define wasm-opcode-select        #x1B)

  ;;; ========== Opcodes: Variable access ==========

  (define wasm-opcode-local-get     #x20)
  (define wasm-opcode-local-set     #x21)
  (define wasm-opcode-local-tee     #x22)
  (define wasm-opcode-global-get    #x23)
  (define wasm-opcode-global-set    #x24)

  ;;; ========== Opcodes: Memory ==========

  (define wasm-opcode-i32-load      #x28)
  (define wasm-opcode-i64-load      #x29)
  (define wasm-opcode-f32-load      #x2A)
  (define wasm-opcode-f64-load      #x2B)
  (define wasm-opcode-i32-load8-s   #x2C)
  (define wasm-opcode-i32-load8-u   #x2D)
  (define wasm-opcode-i32-load16-s  #x2E)
  (define wasm-opcode-i32-load16-u  #x2F)
  (define wasm-opcode-i64-load8-s   #x30)
  (define wasm-opcode-i64-load8-u   #x31)
  (define wasm-opcode-i64-load16-s  #x32)
  (define wasm-opcode-i64-load16-u  #x33)
  (define wasm-opcode-i64-load32-s  #x34)
  (define wasm-opcode-i64-load32-u  #x35)
  (define wasm-opcode-i32-store     #x36)
  (define wasm-opcode-i64-store     #x37)
  (define wasm-opcode-f32-store     #x38)
  (define wasm-opcode-f64-store     #x39)
  (define wasm-opcode-i32-store8    #x3A)
  (define wasm-opcode-i32-store16   #x3B)
  (define wasm-opcode-i64-store8    #x3C)
  (define wasm-opcode-i64-store16   #x3D)
  (define wasm-opcode-i64-store32   #x3E)
  (define wasm-opcode-memory-size   #x3F)
  (define wasm-opcode-memory-grow   #x40)

  ;;; ========== Opcodes: Numeric constants ==========

  (define wasm-opcode-i32-const     #x41)
  (define wasm-opcode-i64-const     #x42)
  (define wasm-opcode-f32-const     #x43)
  (define wasm-opcode-f64-const     #x44)

  ;;; ========== Opcodes: i32 comparisons ==========

  (define wasm-opcode-i32-eqz      #x45)
  (define wasm-opcode-i32-eq       #x46)
  (define wasm-opcode-i32-ne       #x47)
  (define wasm-opcode-i32-lt-s     #x48)
  (define wasm-opcode-i32-lt-u     #x49)
  (define wasm-opcode-i32-gt-s     #x4A)
  (define wasm-opcode-i32-gt-u     #x4B)
  (define wasm-opcode-i32-le-s     #x4C)
  (define wasm-opcode-i32-le-u     #x4D)
  (define wasm-opcode-i32-ge-s     #x4E)
  (define wasm-opcode-i32-ge-u     #x4F)

  ;;; ========== Opcodes: i64 comparisons ==========

  (define wasm-opcode-i64-eqz      #x50)
  (define wasm-opcode-i64-eq       #x51)
  (define wasm-opcode-i64-ne       #x52)
  (define wasm-opcode-i64-lt-s     #x53)
  (define wasm-opcode-i64-lt-u     #x54)
  (define wasm-opcode-i64-gt-s     #x55)
  (define wasm-opcode-i64-gt-u     #x56)
  (define wasm-opcode-i64-le-s     #x57)
  (define wasm-opcode-i64-le-u     #x58)
  (define wasm-opcode-i64-ge-s     #x59)
  (define wasm-opcode-i64-ge-u     #x5A)

  ;;; ========== Opcodes: f32 comparisons ==========

  (define wasm-opcode-f32-eq       #x5B)
  (define wasm-opcode-f32-ne       #x5C)
  (define wasm-opcode-f32-lt       #x5D)
  (define wasm-opcode-f32-gt       #x5E)
  (define wasm-opcode-f32-le       #x5F)
  (define wasm-opcode-f32-ge       #x60)

  ;;; ========== Opcodes: f64 comparisons ==========

  (define wasm-opcode-f64-eq       #x61)
  (define wasm-opcode-f64-ne       #x62)
  (define wasm-opcode-f64-lt       #x63)
  (define wasm-opcode-f64-gt       #x64)
  (define wasm-opcode-f64-le       #x65)
  (define wasm-opcode-f64-ge       #x66)

  ;;; ========== Opcodes: i32 arithmetic ==========

  (define wasm-opcode-i32-clz      #x67)
  (define wasm-opcode-i32-ctz      #x68)
  (define wasm-opcode-i32-popcnt   #x69)
  (define wasm-opcode-i32-add      #x6A)
  (define wasm-opcode-i32-sub      #x6B)
  (define wasm-opcode-i32-mul      #x6C)
  (define wasm-opcode-i32-div-s    #x6D)
  (define wasm-opcode-i32-div-u    #x6E)
  (define wasm-opcode-i32-rem-s    #x6F)
  (define wasm-opcode-i32-rem-u    #x70)
  (define wasm-opcode-i32-and      #x71)
  (define wasm-opcode-i32-or       #x72)
  (define wasm-opcode-i32-xor      #x73)
  (define wasm-opcode-i32-shl      #x74)
  (define wasm-opcode-i32-shr-s    #x75)
  (define wasm-opcode-i32-shr-u    #x76)
  (define wasm-opcode-i32-rotl     #x77)
  (define wasm-opcode-i32-rotr     #x78)

  ;;; ========== Opcodes: i64 arithmetic ==========

  (define wasm-opcode-i64-clz      #x79)
  (define wasm-opcode-i64-ctz      #x7A)
  (define wasm-opcode-i64-popcnt   #x7B)
  (define wasm-opcode-i64-add      #x7C)
  (define wasm-opcode-i64-sub      #x7D)
  (define wasm-opcode-i64-mul      #x7E)
  (define wasm-opcode-i64-div-s    #x7F)
  (define wasm-opcode-i64-div-u    #x80)
  (define wasm-opcode-i64-rem-s    #x81)
  (define wasm-opcode-i64-rem-u    #x82)
  (define wasm-opcode-i64-and      #x83)
  (define wasm-opcode-i64-or       #x84)
  (define wasm-opcode-i64-xor      #x85)
  (define wasm-opcode-i64-shl      #x86)
  (define wasm-opcode-i64-shr-s    #x87)
  (define wasm-opcode-i64-shr-u    #x88)
  (define wasm-opcode-i64-rotl     #x89)
  (define wasm-opcode-i64-rotr     #x8A)

  ;;; ========== Opcodes: f32 arithmetic ==========

  (define wasm-opcode-f32-abs      #x8B)
  (define wasm-opcode-f32-neg      #x8C)
  (define wasm-opcode-f32-ceil     #x8D)
  (define wasm-opcode-f32-floor    #x8E)
  (define wasm-opcode-f32-trunc    #x8F)
  (define wasm-opcode-f32-nearest  #x90)
  (define wasm-opcode-f32-sqrt     #x91)
  (define wasm-opcode-f32-add      #x92)
  (define wasm-opcode-f32-sub      #x93)
  (define wasm-opcode-f32-mul      #x94)
  (define wasm-opcode-f32-div      #x95)
  (define wasm-opcode-f32-min      #x96)
  (define wasm-opcode-f32-max      #x97)
  (define wasm-opcode-f32-copysign #x98)

  ;;; ========== Opcodes: f64 arithmetic ==========

  (define wasm-opcode-f64-abs      #x99)
  (define wasm-opcode-f64-neg      #x9A)
  (define wasm-opcode-f64-ceil     #x9B)
  (define wasm-opcode-f64-floor    #x9C)
  (define wasm-opcode-f64-trunc    #x9D)
  (define wasm-opcode-f64-nearest  #x9E)
  (define wasm-opcode-f64-sqrt     #x9F)
  (define wasm-opcode-f64-add      #xA0)
  (define wasm-opcode-f64-sub      #xA1)
  (define wasm-opcode-f64-mul      #xA2)
  (define wasm-opcode-f64-div      #xA3)
  (define wasm-opcode-f64-min      #xA4)
  (define wasm-opcode-f64-max      #xA5)
  (define wasm-opcode-f64-copysign #xA6)

  ;;; ========== Opcodes: Conversions ==========

  (define wasm-opcode-i32-wrap-i64        #xA7)
  (define wasm-opcode-i32-trunc-f32-s     #xA8)
  (define wasm-opcode-i32-trunc-f32-u     #xA9)
  (define wasm-opcode-i32-trunc-f64-s     #xAA)
  (define wasm-opcode-i32-trunc-f64-u     #xAB)
  (define wasm-opcode-i64-extend-i32-s    #xAC)
  (define wasm-opcode-i64-extend-i32-u    #xAD)
  (define wasm-opcode-i64-trunc-f32-s     #xAE)
  (define wasm-opcode-i64-trunc-f32-u     #xAF)
  (define wasm-opcode-i64-trunc-f64-s     #xB0)
  (define wasm-opcode-i64-trunc-f64-u     #xB1)
  (define wasm-opcode-f32-convert-i32-s   #xB2)
  (define wasm-opcode-f32-convert-i32-u   #xB3)
  (define wasm-opcode-f32-convert-i64-s   #xB4)
  (define wasm-opcode-f32-convert-i64-u   #xB5)
  (define wasm-opcode-f32-demote-f64      #xB6)
  (define wasm-opcode-f64-convert-i32-s   #xB7)
  (define wasm-opcode-f64-convert-i32-u   #xB8)
  (define wasm-opcode-f64-convert-i64-s   #xB9)
  (define wasm-opcode-f64-convert-i64-u   #xBA)
  (define wasm-opcode-f64-promote-f32     #xBB)
  (define wasm-opcode-i32-reinterpret-f32 #xBC)
  (define wasm-opcode-i64-reinterpret-f64 #xBD)
  (define wasm-opcode-f32-reinterpret-i32 #xBE)
  (define wasm-opcode-f64-reinterpret-i64 #xBF)

  ;;; ========== Opcodes: Sign extension ==========

  (define wasm-opcode-i32-extend8-s   #xC0)
  (define wasm-opcode-i32-extend16-s  #xC1)
  (define wasm-opcode-i64-extend8-s   #xC2)
  (define wasm-opcode-i64-extend16-s  #xC3)
  (define wasm-opcode-i64-extend32-s  #xC4)

  ;;; ========== Post-MVP: GC value types ==========

  (define wasm-type-anyref         #x6E)
  (define wasm-type-eqref          #x6D)
  (define wasm-type-i31ref         #x6C)
  (define wasm-type-structref      #x6B)
  (define wasm-type-arrayref       #x6A)
  (define wasm-type-nullref        #x69)
  (define wasm-type-nullfuncref    #x68)
  (define wasm-type-nullexternref  #x67)
  (define wasm-type-noneref        #x65)

  ;;; ========== Post-MVP: Composite type tags ==========

  (define wasm-composite-func    #x60)
  (define wasm-composite-struct  #x5F)
  (define wasm-composite-array   #x5E)
  (define wasm-type-rec          #x4E)
  (define wasm-type-sub          #x50)
  (define wasm-type-sub-final    #x4F)

  ;;; ========== Post-MVP: Tag section ==========

  (define wasm-section-tag 13)

  ;;; ========== Post-MVP: Prefix bytes ==========

  (define wasm-prefix-fc #xFC)
  (define wasm-prefix-fb #xFB)

  ;;; ========== Post-MVP: Tail call opcodes ==========

  (define wasm-opcode-return-call          #x12)
  (define wasm-opcode-return-call-indirect #x13)

  ;;; ========== Post-MVP: Exception handling opcodes ==========

  ;; Legacy exception handling (wasmi-era, deprecated)
  (define wasm-opcode-try        #x06)
  (define wasm-opcode-catch      #x07)
  (define wasm-opcode-throw      #x08)
  (define wasm-opcode-rethrow    #x09)
  (define wasm-opcode-delegate   #x18)
  (define wasm-opcode-catch-all  #x19)

  ;; Phase 4 exception handling (try_table + exnref, supported by browsers)
  (define wasm-opcode-try-table  #x1F)
  (define wasm-opcode-throw-ref  #x0A)
  ;; Catch clause opcodes (inside try_table immediates)
  (define wasm-catch-kind        #x00)  ;; catch tag label
  (define wasm-catch-ref-kind    #x01)  ;; catch_ref tag label
  (define wasm-catch-all-kind    #x02)  ;; catch_all label
  (define wasm-catch-all-ref-kind #x03) ;; catch_all_ref label

  ;;; ========== Post-MVP: Typed select ==========

  (define wasm-opcode-select-t   #x1C)

  ;;; ========== Post-MVP: Reference opcodes ==========

  (define wasm-opcode-ref-null    #xD0)
  (define wasm-opcode-ref-is-null #xD1)
  (define wasm-opcode-ref-func    #xD2)

  ;;; ========== Post-MVP: Table opcodes ==========

  (define wasm-opcode-table-get   #x25)
  (define wasm-opcode-table-set   #x26)

  ;;; ========== Post-MVP: 0xFC sub-opcodes ==========

  (define wasm-fc-i32-trunc-sat-f32-s 0)
  (define wasm-fc-i32-trunc-sat-f32-u 1)
  (define wasm-fc-i32-trunc-sat-f64-s 2)
  (define wasm-fc-i32-trunc-sat-f64-u 3)
  (define wasm-fc-i64-trunc-sat-f32-s 4)
  (define wasm-fc-i64-trunc-sat-f32-u 5)
  (define wasm-fc-i64-trunc-sat-f64-s 6)
  (define wasm-fc-i64-trunc-sat-f64-u 7)
  (define wasm-fc-memory-init  8)
  (define wasm-fc-data-drop    9)
  (define wasm-fc-memory-copy 10)
  (define wasm-fc-memory-fill 11)
  (define wasm-fc-table-init  12)
  (define wasm-fc-elem-drop   13)
  (define wasm-fc-table-copy  14)
  (define wasm-fc-table-grow  15)
  (define wasm-fc-table-size  16)
  (define wasm-fc-table-fill  17)

  ;;; ========== Post-MVP: 0xFB sub-opcodes (GC proposal) ==========

  (define wasm-fb-struct-new         #x00)
  (define wasm-fb-struct-new-default #x01)
  (define wasm-fb-struct-get         #x02)
  (define wasm-fb-struct-get-s       #x03)
  (define wasm-fb-struct-get-u       #x04)
  (define wasm-fb-struct-set         #x05)
  (define wasm-fb-array-new          #x06)
  (define wasm-fb-array-new-default  #x07)
  (define wasm-fb-array-new-fixed    #x08)
  (define wasm-fb-array-new-data     #x09)
  (define wasm-fb-array-new-elem     #x0A)
  (define wasm-fb-array-get          #x0B)
  (define wasm-fb-array-get-s        #x0C)
  (define wasm-fb-array-get-u        #x0D)
  (define wasm-fb-array-set          #x0E)
  (define wasm-fb-array-len          #x0F)
  (define wasm-fb-array-fill         #x10)
  (define wasm-fb-array-copy         #x11)
  (define wasm-fb-array-init-data    #x12)
  (define wasm-fb-array-init-elem    #x13)
  (define wasm-fb-ref-test           #x14)
  (define wasm-fb-ref-test-null      #x15)
  (define wasm-fb-ref-cast           #x16)
  (define wasm-fb-ref-cast-null      #x17)
  (define wasm-fb-br-on-cast         #x18)
  (define wasm-fb-br-on-cast-fail    #x19)
  (define wasm-fb-extern-internalize #x1A)
  (define wasm-fb-extern-externalize #x1B)
  (define wasm-fb-ref-i31            #x1C)
  (define wasm-fb-i31-get-s          #x1D)
  (define wasm-fb-i31-get-u          #x1E)

  ;;; ========== Bytevector builder ==========

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
            (bytevector-copy! chunk 0 result offset len)
            (loop (cdr chunks) (+ offset len)))))))

  ;;; ========== LEB128 encoding ==========

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

  (define (decode-u32-leb128 bv offset)
    (let loop ([result 0] [shift 0] [pos offset])
      (let ([byte (bytevector-u8-ref bv pos)])
        (let ([val (bitwise-ior result
                     (bitwise-arithmetic-shift-left
                       (bitwise-and byte #x7F) shift))])
          (if (= (bitwise-and byte #x80) 0)
            (cons val (- (+ pos 1) offset))
            (loop val (+ shift 7) (+ pos 1)))))))

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

  (define (encode-i64-leb128 n)
    (encode-i32-leb128 n))

  (define (decode-i32-leb128 bv offset)
    (let loop ([result 0] [shift 0] [pos offset])
      (let ([byte (bytevector-u8-ref bv pos)])
        (let ([val (bitwise-ior result
                     (bitwise-arithmetic-shift-left
                       (bitwise-and byte #x7F) shift))])
          (if (= (bitwise-and byte #x80) 0)
            (let ([final-val
                   (if (and (< shift 32)
                            (not (= (bitwise-and byte #x40) 0)))
                     (bitwise-ior val
                       (bitwise-arithmetic-shift-left -1 (+ shift 7)))
                     val)])
              (cons final-val (- (+ pos 1) offset)))
            (loop val (+ shift 7) (+ pos 1)))))))

  (define (decode-i64-leb128 bv offset)
    (let loop ([result 0] [shift 0] [pos offset])
      (let ([byte (bytevector-u8-ref bv pos)])
        (let ([val (bitwise-ior result
                     (bitwise-arithmetic-shift-left
                       (bitwise-and byte #x7F) shift))])
          (if (= (bitwise-and byte #x80) 0)
            (let ([final-val
                   (if (and (< shift 64)
                            (not (= (bitwise-and byte #x40) 0)))
                     (bitwise-ior val
                       (bitwise-arithmetic-shift-left -1 (+ shift 7)))
                     val)])
              (cons final-val (- (+ pos 1) offset)))
            (loop val (+ shift 7) (+ pos 1)))))))

  ;;; ========== Float encoding ==========

  (define (encode-f32 val)
    (let ([bv (make-bytevector 4)])
      (bytevector-ieee-single-set! bv 0 val 'little)
      bv))

  (define (decode-f32 bv offset)
    (bytevector-ieee-single-ref bv offset 'little))

  (define (encode-f64 val)
    (let ([bv (make-bytevector 8)])
      (bytevector-ieee-double-set! bv 0 val 'little)
      bv))

  (define (decode-f64 bv offset)
    (bytevector-ieee-double-ref bv offset 'little))

  ;;; ========== String encoding ==========

  (define (encode-string s)
    (let* ([utf8 (string->utf8 s)]
           [len (bytevector-length utf8)]
           [len-bv (encode-u32-leb128 len)]
           [result (make-bytevector (+ (bytevector-length len-bv) len))])
      (bytevector-copy! len-bv 0 result 0 (bytevector-length len-bv))
      (bytevector-copy! utf8 0 result (bytevector-length len-bv) len)
      result))

  (define (decode-string bv offset)
    (let* ([len-result (decode-u32-leb128 bv offset)]
           [str-len (car len-result)]
           [len-bytes (cdr len-result)]
           [str-start (+ offset len-bytes)]
           [utf8 (make-bytevector str-len)])
      (bytevector-copy! bv str-start utf8 0 str-len)
      (cons (utf8->string utf8) (+ len-bytes str-len))))

) ;; end library
