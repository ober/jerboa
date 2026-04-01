#!chezscheme
;;; (jerboa wasm scheme-runtime) -- Scheme runtime library compiled to WASM
;;;
;;; Provides WASM source forms (for compile-program) implementing the
;;; essential Scheme runtime operations. Built on top of the tagged value
;;; representation (values.sls) and allocator (gc.sls).
;;;
;;; Operations provided:
;;;   - List operations: cons, car, cdr, length, append, reverse, map, etc.
;;;   - Type checks: pair?, string?, number?, etc. (wrapped predicates)
;;;   - Bytevector operations: make-bytevector, bv-ref, bv-set!, bv-copy
;;;   - String operations: string-length, string-ref, string comparison
;;;   - Vector operations: make-vector, vector-ref, vector-set!
;;;   - Fixnum arithmetic with overflow to tagged values
;;;   - Equality: eq?, equal?
;;;   - Comparison: <, >, <=, >=
;;;
;;; All functions operate on tagged values (i32) and return tagged values.
;;; The caller passes tagged fixnums (not raw ints) for numeric arguments.

(library (jerboa wasm scheme-runtime)
  (export
    runtime-list-forms
    runtime-bytevector-forms
    runtime-string-forms
    runtime-vector-forms
    runtime-arithmetic-forms
    runtime-comparison-forms
    runtime-equality-forms
    runtime-conversion-forms
    runtime-io-forms
    runtime-result-forms
    runtime-all-forms
    )

  (import (chezscheme)
          (jerboa wasm values))

  ;; ================================================================
  ;; List operations (on tagged values)
  ;; ================================================================

  (define runtime-list-forms
    '(
      ;; Scheme `cons` — allocate pair from tagged values
      (define (scheme-cons a d)
        (cons-val a d))

      ;; Scheme `car` — extract car from tagged pair
      (define (scheme-car p)
        (pair-car p))

      ;; Scheme `cdr` — extract cdr from tagged pair
      (define (scheme-cdr p)
        (pair-cdr p))

      ;; Scheme `null?` — check if value is ()
      (define (scheme-null? v)
        (= v 4))   ;; IMM-NIL = 4

      ;; Scheme `list?` — proper list ending in ()
      (define (scheme-list? v)
        (if (= v 4)
          1   ;; () is a list
          (if (is-pair v)
            (scheme-list? (pair-cdr v))
            0)))

      ;; Scheme `length` — count elements in a proper list
      ;; Returns a tagged fixnum
      (define (scheme-length lst)
        (let ([count 0]
              [p lst])
          (while (is-pair p)
            (set! count (+ count 1))
            (set! p (pair-cdr p)))
          (tag-fixnum count)))

      ;; Scheme `append` — append two lists
      ;; Copies the spine of lst1, shares lst2
      (define (scheme-append lst1 lst2)
        (if (= lst1 4)
          lst2
          (cons-val (pair-car lst1)
                    (scheme-append (pair-cdr lst1) lst2))))

      ;; Scheme `reverse` — reverse a list
      (define (scheme-reverse lst)
        (let ([result 4]    ;; NIL
              [p lst])
          (while (is-pair p)
            (set! result (cons-val (pair-car p) result))
            (set! p (pair-cdr p)))
          result))

      ;; Scheme `list-ref` — get nth element (n is tagged fixnum)
      (define (scheme-list-ref lst n)
        (let ([idx (untag-fixnum n)]
              [p lst])
          (while (> idx 0)
            (set! p (pair-cdr p))
            (set! idx (- idx 1)))
          (pair-car p)))

      ;; Build a list from values in a vector (helper for apply)
      (define (vector->list-range vec start end)
        (let ([result 4]    ;; NIL
              [i (- end 1)])
          (while (>= i start)
            (set! result (cons-val (vector-ref-val vec i) result))
            (set! i (- i 1)))
          result))

      ;; Scheme `assq` — find pair by key using eq?
      (define (scheme-assq key alist)
        (let ([p alist]
              [found 0])   ;; #f
          (while (and (is-pair p) (= found 0))
            (let ([entry (pair-car p)])
              (if (= (pair-car entry) key)
                (set! found entry)
                (set! p (pair-cdr p)))))
          found))

      ;; Scheme `memq` — find element by eq?
      (define (scheme-memq key lst)
        (let ([p lst]
              [found 0])
          (while (and (is-pair p) (= found 0))
            (if (= (pair-car p) key)
              (set! found p)
              (set! p (pair-cdr p))))
          found))
      ))

  ;; ================================================================
  ;; Bytevector operations
  ;; ================================================================

  (define runtime-bytevector-forms
    '(
      ;; make-bytevector: allocate and zero-fill
      ;; len is a tagged fixnum
      (define (scheme-make-bytevector len)
        (let ([n (untag-fixnum len)])
          (let ([bv (alloc-bytevector n)])
            ;; Zero-fill
            (let ([i 0])
              (while (< i n)
                (bytevector-u8-set-val! bv i 0)
                (set! i (+ i 1))))
            bv)))

      ;; bytevector-length: returns tagged fixnum
      (define (scheme-bytevector-length bv)
        (tag-fixnum (bytevector-length-val bv)))

      ;; bytevector-u8-ref: returns tagged fixnum
      ;; idx is tagged fixnum
      (define (scheme-bytevector-u8-ref bv idx)
        (tag-fixnum (bytevector-u8-ref-val bv (untag-fixnum idx))))

      ;; bytevector-u8-set!: val is tagged fixnum
      (define (scheme-bytevector-u8-set! bv idx val)
        (bytevector-u8-set-val! bv (untag-fixnum idx) (untag-fixnum val)))

      ;; bytevector-copy: copy range from src to dst
      ;; All indices are tagged fixnums
      (define (scheme-bytevector-copy src src-start dst dst-start count)
        (let ([ss (untag-fixnum src-start)]
              [ds (untag-fixnum dst-start)]
              [n (untag-fixnum count)]
              [i 0])
          (while (< i n)
            (bytevector-u8-set-val! dst (+ ds i)
              (bytevector-u8-ref-val src (+ ss i)))
            (set! i (+ i 1)))))

      ;; Copy raw bytes from linear memory offset to a bytevector
      ;; mem-offset and len are raw i32 (not tagged)
      (define (bytevector-from-memory mem-offset len)
        (let ([bv (alloc-bytevector len)]
              [i 0])
          (while (< i len)
            (bytevector-u8-set-val! bv i (i32.load8_u (+ mem-offset i)))
            (set! i (+ i 1)))
          bv))

      ;; Copy bytevector contents to linear memory offset
      ;; mem-offset is raw i32
      (define (bytevector-to-memory bv mem-offset)
        (let ([n (bytevector-length-val bv)]
              [i 0])
          (while (< i n)
            (i32.store8 (+ mem-offset i) (bytevector-u8-ref-val bv i))
            (set! i (+ i 1)))))
      ))

  ;; ================================================================
  ;; String operations
  ;; ================================================================

  (define runtime-string-forms
    '(
      ;; string-length: returns tagged fixnum of UTF-8 codepoint count.
      ;; Counts non-continuation bytes: a byte is a continuation byte
      ;; if (byte & 0xC0) == 0x80.  Everything else starts a codepoint.
      (define (scheme-string-length s)
        (let ([len (string-length-bytes s)]
              [count 0]
              [i 0])
          (while (< i len)
            (when (!= (bitwise-and (string-byte-ref s i) 192) 128)
              (set! count (+ count 1)))
            (set! i (+ i 1)))
          (tag-fixnum count)))

      ;; string-length-bytes-tagged: returns tagged fixnum of byte length
      ;; (kept for code that needs raw byte counts, e.g. bytevector interop)
      (define (scheme-string-byte-length s)
        (tag-fixnum (string-length-bytes s)))

      ;; string-ref: returns tagged fixnum (byte value)
      ;; idx is tagged fixnum
      (define (scheme-string-ref s idx)
        (tag-fixnum (string-byte-ref s (untag-fixnum idx))))

      ;; String equality: byte-by-byte comparison
      (define (scheme-string=? a b)
        (let ([alen (string-length-bytes a)]
              [blen (string-length-bytes b)])
          (if (!= alen blen)
            0   ;; #f — different lengths
            (let ([i 0]
                  [eq 1])
              (while (and (< i alen) eq)
                (when (!= (string-byte-ref a i) (string-byte-ref b i))
                  (set! eq 0))
                (set! i (+ i 1)))
              (if eq 2 0)))))  ;; return #t (2) or #f (0)

      ;; String lexicographic comparison: returns -1, 0, or 1 as tagged fixnum
      (define (scheme-string-compare a b)
        (let ([alen (string-length-bytes a)]
              [blen (string-length-bytes b)]
              [minlen (if (< alen blen) alen blen)]
              [result 0]
              [i 0])
          (while (and (< i minlen) (= result 0))
            (let ([ab (string-byte-ref a i)]
                  [bb (string-byte-ref b i)])
              (when (< ab bb) (set! result -1))
              (when (> ab bb) (set! result 1)))
            (set! i (+ i 1)))
          (when (= result 0)
            (when (< alen blen) (set! result -1))
            (when (> alen blen) (set! result 1)))
          (tag-fixnum result)))

      ;; Allocate a string from I/O buffer contents
      ;; offset and len are raw i32
      (define (string-from-memory offset len)
        (let ([s (alloc-string len)]
              [i 0])
          (while (< i len)
            (string-byte-set! s i (i32.load8_u (+ offset i)))
            (set! i (+ i 1)))
          s))

      ;; Load a string from the static data segment.
      ;; The data segment stores strings as: [4-byte LE length][UTF-8 bytes].
      ;; offset is the raw i32 address of the length prefix.
      (define (string-from-static offset)
        (let ([len (i32.load offset)])
          (string-from-memory (+ offset 4) len)))

      ;; Intern a symbol by wrapping a string pointer.
      ;; Simple MVP: symbol identity is by string equality (not pointer equality).
      ;; Full symbol table interning can be added later.
      (define (intern-symbol str-ptr)
        (alloc-symbol str-ptr))
      ))

  ;; ================================================================
  ;; Vector operations
  ;; ================================================================

  (define runtime-vector-forms
    '(
      ;; make-vector: len is tagged fixnum, fill is tagged value
      (define (scheme-make-vector len fill)
        (let ([n (untag-fixnum len)])
          (let ([v (alloc-vector n)]
                [i 0])
            (while (< i n)
              (vector-set-val! v i fill)
              (set! i (+ i 1)))
            v)))

      ;; vector-length: returns tagged fixnum
      (define (scheme-vector-length v)
        (tag-fixnum (vector-length-val v)))

      ;; vector-ref: idx is tagged fixnum, returns tagged value
      (define (scheme-vector-ref v idx)
        (vector-ref-val v (untag-fixnum idx)))

      ;; vector-set!: idx is tagged fixnum, val is tagged value
      (define (scheme-vector-set! v idx val)
        (vector-set-val! v (untag-fixnum idx) val))
      ))

  ;; ================================================================
  ;; Arithmetic on tagged fixnums
  ;; ================================================================

  (define runtime-arithmetic-forms
    '(
      ;; Add two tagged fixnums → tagged fixnum
      ;; (tag(a) + tag(b) - 1) gives correct tagged result
      (define (fx+ a b)
        (- (+ a b) 1))

      ;; Subtract: tag(a) - tag(b) + 1
      (define (fx- a b)
        (+ (- a b) 1))

      ;; Multiply: untag both, multiply, retag
      (define (fx* a b)
        (tag-fixnum (* (untag-fixnum a) (untag-fixnum b))))

      ;; Integer division: untag both, divide, retag
      (define (fx/ a b)
        (tag-fixnum (quotient (untag-fixnum a) (untag-fixnum b))))

      ;; Modulo
      (define (fx-mod a b)
        (tag-fixnum (remainder (untag-fixnum a) (untag-fixnum b))))

      ;; Negate
      (define (fx-negate a)
        (tag-fixnum (- 0 (untag-fixnum a))))

      ;; Absolute value
      (define (fx-abs a)
        (let ([n (untag-fixnum a)])
          (tag-fixnum (if (< n 0) (- 0 n) n))))

      ;; Bitwise AND on fixnums (untag, op, retag)
      (define (fx-bitwise-and a b)
        (tag-fixnum (bitwise-and (untag-fixnum a) (untag-fixnum b))))

      ;; Bitwise OR on fixnums
      (define (fx-bitwise-or a b)
        (tag-fixnum (bitwise-or (untag-fixnum a) (untag-fixnum b))))

      ;; Bitwise XOR on fixnums
      (define (fx-bitwise-xor a b)
        (tag-fixnum (bitwise-xor (untag-fixnum a) (untag-fixnum b))))

      ;; Arithmetic shift left
      (define (fx-ash a n)
        (tag-fixnum (shl (untag-fixnum a) (untag-fixnum n))))

      ;; Arithmetic shift right
      (define (fx-rsh a n)
        (tag-fixnum (shr (untag-fixnum a) (untag-fixnum n))))
      ))

  ;; ================================================================
  ;; Comparison on tagged fixnums (return tagged boolean)
  ;; ================================================================

  (define runtime-comparison-forms
    '(
      ;; Fixnum <: comparing tagged values directly works because
      ;; tag bit is the same for both, so relative order is preserved.
      ;; But we need to return tagged boolean (#t=2, #f=0).
      (define (fx< a b)
        (if (< a b) 2 0))

      (define (fx> a b)
        (if (> a b) 2 0))

      (define (fx<= a b)
        (if (<= a b) 2 0))

      (define (fx>= a b)
        (if (>= a b) 2 0))

      (define (fx= a b)
        (if (= a b) 2 0))
      ))

  ;; ================================================================
  ;; Equality
  ;; ================================================================

  (define runtime-equality-forms
    '(
      ;; eq?: pointer/immediate equality
      (define (scheme-eq? a b)
        (if (= a b) 2 0))  ;; #t=2, #f=0

      ;; eqv?: eq? plus numeric equality for flonums
      (define (scheme-eqv? a b)
        (if (= a b)
          2   ;; same pointer/immediate → #t
          ;; Both flonums? Compare bits
          (if (and (is-flonum a) (is-flonum b))
            (if (and (= (flonum-lo a) (flonum-lo b))
                     (= (flonum-hi a) (flonum-hi b)))
              2 0)
            0)))

      ;; equal?: structural equality (recursive)
      ;; Bounded recursion to prevent stack overflow on cyclic structures
      (define (scheme-equal? a b)
        (equal-bounded a b 1000))

      (define (equal-bounded a b depth)
        (if (= depth 0)
          0   ;; recursion limit → not equal
          (if (= a b)
            2  ;; eq? → equal
            (if (and (is-pair a) (is-pair b))
              ;; Compare car and cdr
              (if (is-truthy (equal-bounded (pair-car a) (pair-car b) (- depth 1)))
                (equal-bounded (pair-cdr a) (pair-cdr b) (- depth 1))
                0)
              (if (and (is-string a) (is-string b))
                (scheme-string=? a b)
                (if (and (is-bytevector a) (is-bytevector b))
                  ;; Compare bytevectors byte by byte
                  (let ([alen (bytevector-length-val a)]
                        [blen (bytevector-length-val b)])
                    (if (!= alen blen)
                      0
                      (let ([i 0] [eq 1])
                        (while (and (< i alen) eq)
                          (when (!= (bytevector-u8-ref-val a i)
                                    (bytevector-u8-ref-val b i))
                            (set! eq 0))
                          (set! i (+ i 1)))
                        (if eq 2 0))))
                  (if (and (is-vector a) (is-vector b))
                    (let ([alen (vector-length-val a)]
                          [blen (vector-length-val b)])
                      (if (!= alen blen)
                        0
                        (let ([i 0] [eq 1])
                          (while (and (< i alen) eq)
                            (unless (is-truthy
                                      (equal-bounded
                                        (vector-ref-val a i)
                                        (vector-ref-val b i)
                                        (- depth 1)))
                              (set! eq 0))
                            (set! i (+ i 1)))
                          (if eq 2 0))))
                    ;; Flonums
                    (scheme-eqv? a b))))))))
      ))

  ;; ================================================================
  ;; Conversion helpers
  ;; ================================================================

  (define runtime-conversion-forms
    '(
      ;; Convert a tagged value to boolean:
      ;; #f (0) → 0, anything else → 1
      (define (to-bool val)
        (if (= val 0) 0 1))

      ;; Convert a Scheme boolean (#t=2, #f=0) to WASM boolean (1/0)
      (define (scheme-bool->wasm val)
        (if (= val 2) 1 (if (= val 0) 0 1)))

      ;; Convert WASM boolean (nonzero=true) to Scheme boolean (#t=2, #f=0)
      (define (wasm-bool->scheme val)
        (if val 2 0))
      ))

  ;; ================================================================
  ;; I/O buffer helpers (for DNS packet processing)
  ;; ================================================================

  (define runtime-io-forms
    '(
      ;; Read a big-endian u16 from I/O buffer at raw offset
      (define (io-read-u16be offset)
        (bitwise-or
          (shl (i32.load8_u offset) 8)
          (i32.load8_u (+ offset 1))))

      ;; Write a big-endian u16 to I/O buffer
      (define (io-write-u16be offset val)
        (i32.store8 offset (shr-u val 8))
        (i32.store8 (+ offset 1) (bitwise-and val 255)))

      ;; Read a big-endian u32 from buffer
      (define (io-read-u32be offset)
        (bitwise-or
          (bitwise-or
            (shl (i32.load8_u offset) 24)
            (shl (i32.load8_u (+ offset 1)) 16))
          (bitwise-or
            (shl (i32.load8_u (+ offset 2)) 8)
            (i32.load8_u (+ offset 3)))))

      ;; Write a big-endian u32 to buffer
      (define (io-write-u32be offset val)
        (i32.store8 offset (shr-u val 24))
        (i32.store8 (+ offset 1) (bitwise-and (shr-u val 16) 255))
        (i32.store8 (+ offset 2) (bitwise-and (shr-u val 8) 255))
        (i32.store8 (+ offset 3) (bitwise-and val 255)))

      ;; Copy n bytes from src to dst in linear memory
      ;; Uses bulk memory.copy when available (post-MVP), falls back to loop
      (define (mem-copy dst src n)
        (memory.copy dst src n))

      ;; Zero-fill n bytes starting at dst
      ;; Uses bulk memory.fill (post-MVP)
      (define (mem-zero dst n)
        (memory.fill dst 0 n))
      ))

  ;; ================================================================
  ;; Result type operations (ok/err)
  ;; ================================================================

  ;; Results are represented as pairs:
  ;;   (ok x)  → pair where car = tagged fixnum 1, cdr = x
  ;;   (err x) → pair where car = tagged fixnum 0, cdr = x
  ;; This gives us O(1) construction and access.

  (define RESULT-OK-TAG  (bitwise-ior (bitwise-arithmetic-shift-left 1 2) 1))  ;; tagged fixnum 1 = 5
  (define RESULT-ERR-TAG (bitwise-ior (bitwise-arithmetic-shift-left 0 2) 1))  ;; tagged fixnum 0 = 1

  (define runtime-result-forms
    `(
      ;; Construct an ok result
      (define (scheme-ok val)
        (cons-val ,RESULT-OK-TAG val))

      ;; Construct an err result
      (define (scheme-err val)
        (cons-val ,RESULT-ERR-TAG val))

      ;; Check if result is ok (car == tagged 1)
      (define (scheme-ok? r)
        (if (is-pair r)
          (if (= (pair-car r) ,RESULT-OK-TAG) 2 0)   ;; 2=#t, 0=#f
          0))

      ;; Check if result is err (car == tagged 0)
      (define (scheme-err? r)
        (if (is-pair r)
          (if (= (pair-car r) ,RESULT-ERR-TAG) 2 0)
          0))

      ;; Unwrap an ok result (returns value or traps)
      (define (scheme-unwrap r)
        (if (= (pair-car r) ,RESULT-OK-TAG)
          (pair-cdr r)
          (unreachable)))

      ;; Unwrap with default: return value if ok, default if err
      (define (scheme-unwrap-or r default-val)
        (if (= (pair-car r) ,RESULT-OK-TAG)
          (pair-cdr r)
          default-val))

      ;; Map over ok value: (map-ok f result)
      ;; If ok, apply f to the value; if err, pass through
      (define (scheme-map-ok f-result r)
        ;; f-result is the result of applying f — caller must inline the call
        ;; This version is for the lowered form where the call is already done
        r)

      ;; Extract ok value (for lowering; callers guard with ok?)
      (define (scheme-result-value r)
        (pair-cdr r))
      ))

  ;; ================================================================
  ;; Combined: all runtime forms
  ;; ================================================================

  (define runtime-all-forms
    (append runtime-list-forms
            runtime-bytevector-forms
            runtime-string-forms
            runtime-vector-forms
            runtime-arithmetic-forms
            runtime-comparison-forms
            runtime-equality-forms
            runtime-conversion-forms
            runtime-io-forms
            runtime-result-forms))

) ;; end library
