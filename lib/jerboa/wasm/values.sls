#!chezscheme
;;; (jerboa wasm values) -- Tagged value representation for WASM linear memory
;;;
;;; Defines the bit-tagging scheme for representing Scheme values as i32
;;; in WASM linear memory. All Scheme values (fixnums, booleans, pairs,
;;; strings, closures, etc.) are encoded as 32-bit words.
;;;
;;; Tagging scheme:
;;;   bit 0 = 1  →  fixnum (value >> 1 gives the integer, range ±2^30)
;;;   bits 1:0 = 00, value >= HEAP-BASE  →  heap pointer (4-byte aligned)
;;;   small even values < HEAP-BASE  →  immediates (#f, #t, (), void, eof)
;;;
;;; Heap object layout:
;;;   word 0: header = (type << 24) | (gc-mark << 23) | size-in-bytes
;;;   word 1+: type-specific payload
;;;
;;; Type tags (stored in header bits 31:24):
;;;   0=pair, 1=string, 2=bytevector, 3=vector, 4=symbol,
;;;   5=closure, 6=record, 7=flonum, 8=hashtable

(library (jerboa wasm values)
  (export
    ;; Fixnum tagging
    FIXNUM-TAG FIXNUM-MASK
    FIXNUM-MIN FIXNUM-MAX

    ;; Immediate constants (pre-tagged values)
    IMM-FALSE IMM-TRUE IMM-NIL IMM-VOID IMM-EOF

    ;; Heap pointer
    HEAP-BASE HEAP-ALIGN

    ;; Heap object type tags (header byte)
    TYPE-PAIR TYPE-STRING TYPE-BYTEVECTOR TYPE-VECTOR
    TYPE-SYMBOL TYPE-CLOSURE TYPE-RECORD TYPE-FLONUM TYPE-HASHTABLE

    ;; Header layout constants
    HEADER-TYPE-SHIFT HEADER-TYPE-MASK
    HEADER-GC-BIT
    HEADER-SIZE-MASK

    ;; Object sizes (in bytes, excluding header)
    PAIR-PAYLOAD-SIZE          ;; 8: car + cdr
    CLOSURE-HEADER-PAYLOAD     ;; 8: func-idx + env-size, then env slots
    VECTOR-HEADER-PAYLOAD      ;; 4: length, then elements
    STRING-HEADER-PAYLOAD      ;; 4: byte-length, then UTF-8 bytes
    BYTEVECTOR-HEADER-PAYLOAD  ;; 4: byte-length, then raw bytes
    SYMBOL-HEADER-PAYLOAD      ;; 4: string-ptr (interned)
    FLONUM-PAYLOAD-SIZE        ;; 8: f64 bits stored as two i32
    HASHTABLE-HEADER-PAYLOAD   ;; 12: count + capacity + buckets-ptr

    ;; Memory layout constants
    MEM-ROOT-STACK-BASE MEM-ROOT-STACK-SIZE
    MEM-STATIC-BASE MEM-STATIC-SIZE
    MEM-IO-BASE MEM-IO-SIZE
    MEM-HEAP-START

    ;; Root stack globals (indices)
    GLOBAL-HEAP-PTR    ;; bump pointer
    GLOBAL-HEAP-END    ;; end of usable heap
    GLOBAL-ROOT-SP     ;; root stack pointer (for GC)
    GLOBAL-ARENA-BASE  ;; arena reset target
    GLOBAL-SYMBOL-TABLE ;; interned symbol table pointer

    ;; WASM source forms for runtime
    value-tag-forms        ;; list of (define ...) for tagging/untagging
    value-predicate-forms  ;; list of (define ...) for type predicates
    value-accessor-forms   ;; list of (define ...) for field access
    value-constructor-forms ;; list of (define ...) for object construction
    value-global-forms     ;; list of (define-global ...) declarations
    value-memory-forms     ;; list of (define-memory ...) declarations

    ;; Scheme-side helpers for code generation
    make-fixnum-const      ;; number -> WASM i32 constant (tagged)
    make-imm-const         ;; symbol -> WASM i32 constant
    tagged-fixnum          ;; number -> tagged integer value
    )

  (import (chezscheme))

  ;; ================================================================
  ;; Tag constants
  ;; ================================================================

  ;; Fixnum: bit 0 = 1, value in bits 31:1
  (define FIXNUM-TAG 1)
  (define FIXNUM-MASK 1)     ;; mask to test bit 0
  (define FIXNUM-MIN (- (expt 2 30)))  ;; -1073741824
  (define FIXNUM-MAX (- (expt 2 30) 1)) ;; 1073741823

  ;; Immediate values: small even numbers (bit 0 = 0, below HEAP-BASE)
  (define IMM-FALSE  0)   ;; #f = 0
  (define IMM-TRUE   2)   ;; #t = 2
  (define IMM-NIL    4)   ;; () = 4
  (define IMM-VOID   6)   ;; void = 6
  (define IMM-EOF    8)   ;; eof-object = 8

  ;; Heap pointers: even, >= HEAP-BASE, 4-byte aligned
  (define HEAP-BASE  1024)  ;; below this, even values are immediates
  (define HEAP-ALIGN 4)     ;; all heap objects are 4-byte aligned

  ;; ================================================================
  ;; Heap object type tags
  ;; ================================================================

  (define TYPE-PAIR        0)
  (define TYPE-STRING      1)
  (define TYPE-BYTEVECTOR  2)
  (define TYPE-VECTOR      3)
  (define TYPE-SYMBOL      4)
  (define TYPE-CLOSURE     5)
  (define TYPE-RECORD      6)
  (define TYPE-FLONUM      7)
  (define TYPE-HASHTABLE   8)

  ;; ================================================================
  ;; Header layout: [type:8 | gc-mark:1 | size:23]
  ;; ================================================================

  (define HEADER-TYPE-SHIFT 24)
  (define HEADER-TYPE-MASK  #xFF000000)
  (define HEADER-GC-BIT     #x00800000)   ;; bit 23
  (define HEADER-SIZE-MASK  #x007FFFFF)   ;; bits 22:0 = max 8MB object

  ;; ================================================================
  ;; Payload sizes (bytes, not counting the 4-byte header)
  ;; ================================================================

  (define PAIR-PAYLOAD-SIZE         8)   ;; car(4) + cdr(4)
  (define CLOSURE-HEADER-PAYLOAD    8)   ;; func-idx(4) + env-count(4)
  (define VECTOR-HEADER-PAYLOAD     4)   ;; length(4), then length*4 elements
  (define STRING-HEADER-PAYLOAD     4)   ;; byte-length(4), then bytes
  (define BYTEVECTOR-HEADER-PAYLOAD 4)   ;; byte-length(4), then bytes
  (define SYMBOL-HEADER-PAYLOAD     4)   ;; string-ptr(4)
  (define FLONUM-PAYLOAD-SIZE       8)   ;; lo-bits(4) + hi-bits(4)
  (define HASHTABLE-HEADER-PAYLOAD 12)   ;; count(4) + capacity(4) + buckets-ptr(4)

  ;; ================================================================
  ;; Memory layout (linear memory regions)
  ;; ================================================================
  ;;
  ;; Page 0 (0-65535):
  ;;   0-255:      Reserved (null trap zone)
  ;;   256-1023:   Root stack (192 entries = 768 bytes)
  ;;   1024-4095:  Static data (strings, symbol table init)
  ;;   4096-8191:  I/O buffers (DNS packet in/out)
  ;;   8192+:      Heap (bump-allocated, grows upward)
  ;;
  ;; Globals track heap state.

  (define MEM-ROOT-STACK-BASE  256)
  (define MEM-ROOT-STACK-SIZE  768)   ;; 192 root entries
  (define MEM-STATIC-BASE     1024)
  (define MEM-STATIC-SIZE     3072)   ;; 3KB for static data
  (define MEM-IO-BASE         4096)
  (define MEM-IO-SIZE         4096)   ;; 4KB I/O buffer
  (define MEM-HEAP-START      8192)   ;; heap begins here

  ;; ================================================================
  ;; Global variable indices (for define-global)
  ;; ================================================================

  (define GLOBAL-HEAP-PTR     0)   ;; current bump pointer
  (define GLOBAL-HEAP-END     1)   ;; end of allocated heap
  (define GLOBAL-ROOT-SP      2)   ;; root stack pointer
  (define GLOBAL-ARENA-BASE   3)   ;; arena reset target
  (define GLOBAL-SYMBOL-TABLE 4)   ;; interned symbol table

  ;; ================================================================
  ;; Scheme-side helpers
  ;; ================================================================

  ;; Convert a Scheme integer to its tagged fixnum i32 representation
  (define (tagged-fixnum n)
    (bitwise-ior (bitwise-arithmetic-shift-left n 1) FIXNUM-TAG))

  ;; Generate a WASM i32 constant form for a tagged fixnum
  (define (make-fixnum-const n)
    (tagged-fixnum n))

  ;; Generate a WASM i32 constant for an immediate value
  (define (make-imm-const sym)
    (case sym
      [(false #f)   IMM-FALSE]
      [(true #t)    IMM-TRUE]
      [(nil null ()) IMM-NIL]
      [(void)       IMM-VOID]
      [(eof)        IMM-EOF]
      [else (error 'make-imm-const "unknown immediate" sym)]))

  ;; ================================================================
  ;; WASM source forms: memory and globals
  ;; ================================================================

  (define value-memory-forms
    '(;; 2 pages = 128KB initial, 16 pages = 1MB max
      (define-memory 2 16)))

  (define value-global-forms
    `((define-global heap-ptr    i32 #t ,MEM-HEAP-START)
      (define-global heap-end    i32 #t 131072)  ;; 2 pages = 128KB
      (define-global root-sp     i32 #t ,MEM-ROOT-STACK-BASE)
      (define-global arena-base  i32 #t ,MEM-HEAP-START)
      (define-global symbol-tab  i32 #t 0)))

  ;; ================================================================
  ;; WASM source forms: tagging/untagging primitives
  ;; ================================================================

  (define value-tag-forms
    '(
      ;; Tag a raw integer as a fixnum: (n << 1) | 1
      (define (tag-fixnum n)
        (bitwise-or (shl n 1) 1))

      ;; Untag a fixnum to get the raw integer: val >> 1 (arithmetic)
      (define (untag-fixnum val)
        (shr val 1))

      ;; Check if a value is a fixnum (bit 0 = 1)
      (define (is-fixnum val)
        (bitwise-and val 1))

      ;; Check if a value is a heap pointer (even, >= HEAP-BASE)
      (define (is-heap-ptr val)
        (and (not (bitwise-and val 1))
             (>= val 1024)))

      ;; Check if a value is an immediate (even, < HEAP-BASE)
      (define (is-immediate val)
        (and (not (bitwise-and val 1))
             (< val 1024)))

      ;; Read the type tag from a heap object header
      (define (heap-type-tag ptr)
        (shr-u (i32.load ptr) 24))

      ;; Read the size field from a heap object header
      (define (heap-obj-size ptr)
        (bitwise-and (i32.load ptr) 8388607))  ;; 0x7FFFFF

      ;; Write a heap object header
      (define (write-header ptr type-tag size)
        (i32.store ptr (bitwise-or (shl type-tag 24) size)))
      ))

  ;; ================================================================
  ;; WASM source forms: type predicates
  ;; ================================================================

  (define value-predicate-forms
    '(
      ;; #f is 0 — same as C false
      (define (is-false val)
        (= val 0))

      ;; #t is 2
      (define (is-true val)
        (= val 2))

      ;; () is 4
      (define (is-nil val)
        (= val 4))

      ;; void is 6
      (define (is-void val)
        (= val 6))

      ;; eof is 8
      (define (is-eof val)
        (= val 8))

      ;; Boolean: #f or #t
      (define (is-boolean val)
        (or (= val 0) (= val 2)))

      ;; Truthy: anything except #f (0)
      (define (is-truthy val)
        (!= val 0))

      ;; Pair: heap pointer with type tag 0
      (define (is-pair val)
        (if (is-heap-ptr val)
          (= (heap-type-tag val) 0)
          0))

      ;; String: heap pointer with type tag 1
      (define (is-string val)
        (if (is-heap-ptr val)
          (= (heap-type-tag val) 1)
          0))

      ;; Bytevector: heap pointer with type tag 2
      (define (is-bytevector val)
        (if (is-heap-ptr val)
          (= (heap-type-tag val) 2)
          0))

      ;; Vector: heap pointer with type tag 3
      (define (is-vector val)
        (if (is-heap-ptr val)
          (= (heap-type-tag val) 3)
          0))

      ;; Symbol: heap pointer with type tag 4
      (define (is-symbol val)
        (if (is-heap-ptr val)
          (= (heap-type-tag val) 4)
          0))

      ;; Closure: heap pointer with type tag 5
      (define (is-closure val)
        (if (is-heap-ptr val)
          (= (heap-type-tag val) 5)
          0))

      ;; Record: heap pointer with type tag 6
      (define (is-record val)
        (if (is-heap-ptr val)
          (= (heap-type-tag val) 6)
          0))

      ;; Flonum: heap pointer with type tag 7
      (define (is-flonum val)
        (if (is-heap-ptr val)
          (= (heap-type-tag val) 7)
          0))

      ;; Hashtable: heap pointer with type tag 8
      (define (is-hashtable val)
        (if (is-heap-ptr val)
          (= (heap-type-tag val) 8)
          0))

      ;; Number: fixnum or flonum
      (define (is-number val)
        (or (is-fixnum val) (is-flonum val)))
      ))

  ;; ================================================================
  ;; WASM source forms: field accessors
  ;; ================================================================

  (define value-accessor-forms
    '(
      ;; ---- Pairs ----
      ;; Layout: [header(4)] [car(4)] [cdr(4)]
      (define (pair-car p)
        (i32.load (+ p 4)))

      (define (pair-cdr p)
        (i32.load (+ p 8)))

      (define (pair-set-car! p val)
        (i32.store (+ p 4) val))

      (define (pair-set-cdr! p val)
        (i32.store (+ p 8) val))

      ;; ---- Strings ----
      ;; Layout: [header(4)] [byte-length(4)] [utf8-bytes...]
      (define (string-length-bytes s)
        (i32.load (+ s 4)))

      (define (string-byte-ref s idx)
        (i32.load8_u (+ (+ s 8) idx)))

      (define (string-byte-set! s idx val)
        (i32.store8 (+ (+ s 8) idx) val))

      ;; ---- Bytevectors ----
      ;; Layout: [header(4)] [byte-length(4)] [raw-bytes...]
      (define (bytevector-length-val bv)
        (i32.load (+ bv 4)))

      (define (bytevector-u8-ref-val bv idx)
        (i32.load8_u (+ (+ bv 8) idx)))

      (define (bytevector-u8-set-val! bv idx val)
        (i32.store8 (+ (+ bv 8) idx) val))

      ;; ---- Vectors ----
      ;; Layout: [header(4)] [length(4)] [elem0(4)] [elem1(4)] ...
      (define (vector-length-val v)
        (i32.load (+ v 4)))

      (define (vector-ref-val v idx)
        (i32.load (+ (+ v 8) (shl idx 2))))

      (define (vector-set-val! v idx val)
        (i32.store (+ (+ v 8) (shl idx 2)) val))

      ;; ---- Symbols ----
      ;; Layout: [header(4)] [string-ptr(4)]
      (define (symbol-string sym)
        (i32.load (+ sym 4)))

      ;; ---- Closures ----
      ;; Layout: [header(4)] [func-idx(4)] [env-count(4)] [env0(4)] ...
      (define (closure-func-idx clos)
        (i32.load (+ clos 4)))

      (define (closure-env-count clos)
        (i32.load (+ clos 8)))

      (define (closure-env-ref clos idx)
        (i32.load (+ (+ clos 12) (shl idx 2))))

      ;; ---- Flonums ----
      ;; Layout: [header(4)] [f64-lo(4)] [f64-hi(4)]
      ;; Stored as two i32 words (WASM linear memory is little-endian)
      (define (flonum-lo fl)
        (i32.load (+ fl 4)))

      (define (flonum-hi fl)
        (i32.load (+ fl 8)))

      ;; ---- Hashtables ----
      ;; Layout: [header(4)] [count(4)] [capacity(4)] [buckets-ptr(4)]
      ;; Buckets: array of (key, value) pairs in linear memory
      (define (hashtable-count ht)
        (i32.load (+ ht 4)))

      (define (hashtable-capacity ht)
        (i32.load (+ ht 8)))

      (define (hashtable-buckets ht)
        (i32.load (+ ht 12)))

      (define (hashtable-set-count! ht n)
        (i32.store (+ ht 4) n))

      ;; ---- Records ----
      ;; Layout: [header(4)] [type-id(4)] [field0(4)] [field1(4)] ...
      (define (record-type-id rec)
        (i32.load (+ rec 4)))

      (define (record-field-ref rec idx)
        (i32.load (+ (+ rec 8) (shl idx 2))))

      (define (record-field-set! rec idx val)
        (i32.store (+ (+ rec 8) (shl idx 2)) val))
      ))

  ;; ================================================================
  ;; WASM source forms: constructors (allocate + initialize)
  ;; These depend on the allocator from gc.sls, so they call `alloc`.
  ;; ================================================================

  (define value-constructor-forms
    '(
      ;; Allocate a pair (cons cell)
      (define (cons-val car-val cdr-val)
        (let ([ptr (alloc 12)])  ;; header(4) + car(4) + cdr(4)
          (write-header ptr 0 12)    ;; type=pair, size=12
          (i32.store (+ ptr 4) car-val)
          (i32.store (+ ptr 8) cdr-val)
          ptr))

      ;; Allocate a string from byte length (caller fills bytes)
      (define (alloc-string byte-len)
        (let ([total (+ 8 byte-len)]              ;; header + length + bytes
              [aligned (bitwise-and (+ (+ 8 byte-len) 3) -4)])  ;; 4-byte align
          (let ([ptr (alloc aligned)])
            (write-header ptr 1 aligned)           ;; type=string
            (i32.store (+ ptr 4) byte-len)
            ptr)))

      ;; Allocate a bytevector (caller fills bytes)
      (define (alloc-bytevector byte-len)
        (let ([aligned (bitwise-and (+ (+ 8 byte-len) 3) -4)])
          (let ([ptr (alloc aligned)])
            (write-header ptr 2 aligned)           ;; type=bytevector
            (i32.store (+ ptr 4) byte-len)
            ptr)))

      ;; Allocate a vector of given length
      (define (alloc-vector len)
        (let ([total (+ 8 (shl len 2))])  ;; header + length + len*4
          (let ([ptr (alloc total)])
            (write-header ptr 3 total)     ;; type=vector
            (i32.store (+ ptr 4) len)
            ;; Initialize all elements to #f (0)
            (let ([i 0])
              (while (< i len)
                (i32.store (+ (+ ptr 8) (shl i 2)) 0)
                (set! i (+ i 1))))
            ptr)))

      ;; Allocate a symbol (points to an interned string)
      (define (alloc-symbol str-ptr)
        (let ([ptr (alloc 8)])   ;; header(4) + string-ptr(4)
          (write-header ptr 4 8)  ;; type=symbol
          (i32.store (+ ptr 4) str-ptr)
          ptr))

      ;; Allocate a closure
      (define (alloc-closure func-idx env-count)
        (let ([total (+ 12 (shl env-count 2))])  ;; header + fidx + ecount + env slots
          (let ([ptr (alloc total)])
            (write-header ptr 5 total)     ;; type=closure
            (i32.store (+ ptr 4) func-idx)
            (i32.store (+ ptr 8) env-count)
            ptr)))

      ;; Set a closure environment slot
      (define (closure-env-set! clos idx val)
        (i32.store (+ (+ clos 12) (shl idx 2)) val))

      ;; Allocate a record with a type-id and n fields
      (define (alloc-record type-id n-fields)
        (let ([total (+ 8 (shl n-fields 2))])  ;; header + type-id + fields
          (let ([ptr (alloc total)])
            (write-header ptr 6 total)     ;; type=record
            (i32.store (+ ptr 4) type-id)
            ;; Initialize fields to #f (0)
            (let ([i 0])
              (while (< i n-fields)
                (i32.store (+ (+ ptr 8) (shl i 2)) 0)
                (set! i (+ i 1))))
            ptr)))

      ;; Allocate a flonum (store f64 as two i32 words)
      ;; Caller provides lo and hi 32-bit halves
      (define (alloc-flonum lo hi)
        (let ([ptr (alloc 12)])  ;; header(4) + lo(4) + hi(4)
          (write-header ptr 7 12)  ;; type=flonum
          (i32.store (+ ptr 4) lo)
          (i32.store (+ ptr 8) hi)
          ptr))

      ;; Allocate a hashtable
      (define (alloc-hashtable initial-capacity)
        (let ([buckets-size (shl (* initial-capacity 2) 2)]) ;; cap * 2 entries * 4 bytes
          (let ([buckets (alloc buckets-size)]
                [ht-ptr (alloc 16)])  ;; header(4) + count(4) + cap(4) + buckets(4)
            ;; Zero-fill buckets (0 = #f = empty)
            (let ([i 0])
              (while (< i buckets-size)
                (i32.store8 (+ buckets i) 0)
                (set! i (+ i 1))))
            (write-header ht-ptr 8 16)  ;; type=hashtable
            (i32.store (+ ht-ptr 4) 0)  ;; count = 0
            (i32.store (+ ht-ptr 8) initial-capacity)
            (i32.store (+ ht-ptr 12) buckets)
            ht-ptr)))
      ))

) ;; end library
