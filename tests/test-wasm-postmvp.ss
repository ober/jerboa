#!chezscheme
;;; Tests for post-MVP WASM features in (jerboa wasm runtime)
;;; Tests: saturating conversions, bulk memory, reference types,
;;;        table operations, tail calls, exception handling, GC proposal

(import (except (chezscheme) compile-program)
        (jerboa wasm format)
        (jerboa wasm runtime))

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
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(define (string-contains-substr? hay needle)
  (let ([hlen (string-length hay)]
        [nlen (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nlen) hlen) #f]
        [(string=? needle (substring hay i (+ i nlen))) #t]
        [else (loop (+ i 1))]))))

(define-syntax test-trap
  (syntax-rules ()
    [(_ name expr needle)
     (guard (exn
       [(and (wasm-trap? exn)
             (string-contains-substr? (wasm-trap-message exn) needle))
        (set! pass (+ pass 1))
        (printf "  ok ~a (trapped: ~a)~%" name (wasm-trap-message exn))]
       [#t (set! fail (+ fail 1))
           (printf "FAIL ~a: unexpected error: ~a~%" name
             (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (set! fail (+ fail 1))
         (printf "FAIL ~a: expected trap but got ~s~%" name got)))]))

(printf "--- Post-MVP WASM Features ---~%~%")

;;; ========== Helper: build raw WASM modules ==========

;; Concatenate bytevectors
(define (bv-cat . bvs)
  (let* ([total (apply + (map bytevector-length bvs))]
         [result (make-bytevector total 0)])
    (let loop ([bvs bvs] [pos 0])
      (unless (null? bvs)
        (let ([bv (car bvs)])
          (bytevector-copy! bv 0 result pos (bytevector-length bv))
          (loop (cdr bvs) (+ pos (bytevector-length bv))))))
    result))

;; Encode a section: section-id + LEB128(length) + content
(define (make-section id content-bv)
  (bv-cat (bytevector id)
          (encode-u32-leb128 (bytevector-length content-bv))
          content-bv))

;; Build a minimal WASM module with given sections
(define (build-wasm-module . sections)
  (apply bv-cat wasm-magic wasm-version sections))

;; Encode a type section with given function signatures
;; Each sig is ((param-types ...) . (result-types ...))
(define (make-type-section sigs)
  (let ([content
         (apply bv-cat
           (encode-u32-leb128 (length sigs))
           (map (lambda (sig)
                  (let ([params (car sig)]
                        [results (cdr sig)])
                    (bv-cat (bytevector #x60)  ; func type
                            (encode-u32-leb128 (length params))
                            (apply bytevector params)
                            (encode-u32-leb128 (length results))
                            (apply bytevector results))))
                sigs))])
    (make-section wasm-section-type content)))

;; Encode function section (list of type indices)
(define (make-func-section type-idxs)
  (let ([content (apply bv-cat
                   (encode-u32-leb128 (length type-idxs))
                   (map encode-u32-leb128 type-idxs))])
    (make-section wasm-section-function content)))

;; Encode export section - list of (name kind idx)
(define (make-export-section exports)
  (let ([content
         (apply bv-cat
           (encode-u32-leb128 (length exports))
           (map (lambda (exp)
                  (let ([name (car exp)]
                        [kind (cadr exp)]
                        [idx (caddr exp)])
                    (bv-cat (encode-string name)
                            (bytevector kind)
                            (encode-u32-leb128 idx))))
                exports))])
    (make-section wasm-section-export content)))

;; Encode a single code body: locals + bytecode + end opcode
;; locals is list of (count type) pairs
(define (make-code-body locals code-bv)
  (let* ([locals-bv (apply bv-cat
                      (encode-u32-leb128 (length locals))
                      (map (lambda (l)
                             (bv-cat (encode-u32-leb128 (car l))
                                     (bytevector (cadr l))))
                           locals))]
         [body (bv-cat locals-bv code-bv (bytevector #x0B))]  ; 0x0B = end
         [body-with-size (bv-cat (encode-u32-leb128 (bytevector-length body)) body)])
    body-with-size))

;; Encode code section with list of code bodies
(define (make-code-section bodies)
  (let ([content (apply bv-cat
                   (encode-u32-leb128 (length bodies))
                   bodies)])
    (make-section wasm-section-code content)))

;; Memory section with one memory (min pages, no max)
(define (make-memory-section min-pages)
  (let ([content (bv-cat (encode-u32-leb128 1)     ; 1 memory
                         (bytevector #x00)           ; flags: no max
                         (encode-u32-leb128 min-pages))])
    (make-section wasm-section-memory content)))

;; Table section with one table (funcref, min size)
(define (make-table-section min-size)
  (let ([content (bv-cat (encode-u32-leb128 1)      ; 1 table
                         (bytevector #x70)            ; funcref
                         (bytevector #x00)            ; flags: no max
                         (encode-u32-leb128 min-size))])
    (make-section wasm-section-table content)))

;; Data section with passive data segments
;; Each segment is (mem-idx offset-value data-bytevector)
(define (make-data-section segments)
  (let ([content
         (apply bv-cat
           (encode-u32-leb128 (length segments))
           (map (lambda (seg)
                  (let ([mem-idx (car seg)]
                        [offset (cadr seg)]
                        [data (caddr seg)])
                    (bv-cat (encode-u32-leb128 mem-idx)
                            ;; init expr: i32.const offset, end
                            (bytevector wasm-opcode-i32-const)
                            (encode-i32-leb128 offset)
                            (bytevector #x0B)
                            (encode-u32-leb128 (bytevector-length data))
                            data)))
                segments))])
    (make-section wasm-section-data content)))

;; Element section with segments: (table-idx offset func-idxs)
(define (make-elem-section segments)
  (let ([content
         (apply bv-cat
           (encode-u32-leb128 (length segments))
           (map (lambda (seg)
                  (let ([tidx (car seg)]
                        [offset (cadr seg)]
                        [func-idxs (caddr seg)])
                    (bv-cat (encode-u32-leb128 tidx)
                            (bytevector wasm-opcode-i32-const)
                            (encode-i32-leb128 offset)
                            (bytevector #x0B)
                            (encode-u32-leb128 (length func-idxs))
                            (apply bv-cat (map encode-u32-leb128 func-idxs)))))
                segments))])
    (make-section wasm-section-element content)))

;; Tag section (section 13): list of type-idx for exception tags
(define (make-tag-section type-idxs)
  (let ([content
         (apply bv-cat
           (encode-u32-leb128 (length type-idxs))
           (map (lambda (tidx)
                  (bv-cat (bytevector #x00)  ; attribute: exception
                          (encode-u32-leb128 tidx)))
                type-idxs))])
    (make-section wasm-section-tag content)))

;; Helper to build and run a single-function module
(define (run-single-func type-sig locals code-bv . args)
  (let* ([mod (build-wasm-module
                (make-type-section (list type-sig))
                (make-func-section '(0))
                (make-export-section '(("test" 0 0)))
                (make-code-section (list (make-code-body locals code-bv))))]
         [decoded (wasm-decode-module mod)]
         [store (make-wasm-store)]
         [inst (wasm-store-instantiate store decoded)]
         [rt (make-wasm-runtime)])
    (wasm-runtime-load rt mod)
    (apply wasm-runtime-call rt "test" args)))


;;; ========== 1. Saturating Float-to-Int Conversions ==========

(printf "~%= Saturating conversions =~%")

;; i32.trunc_sat_f32_s: push f32, then 0xFC 0x00
(test "i32.trunc_sat_f32_s: normal"
  (run-single-func
    '((#x7D) . (#x7F))     ; f32 -> i32
    '()
    (bv-cat (bytevector #x20 #x00)        ; local.get 0
            (bytevector #xFC)              ; prefix
            (encode-u32-leb128 0))         ; sub-opcode 0
    3.7)
  3)

(test "i32.trunc_sat_f32_s: NaN -> 0"
  (run-single-func
    '((#x7D) . (#x7F))
    '()
    (bv-cat (bytevector #x20 #x00)
            (bytevector #xFC)
            (encode-u32-leb128 0))
    +nan.0)
  0)

(test "i32.trunc_sat_f32_u: normal"
  (run-single-func
    '((#x7D) . (#x7F))
    '()
    (bv-cat (bytevector #x20 #x00)
            (bytevector #xFC)
            (encode-u32-leb128 1))
    42.9)
  42)

(test "i32.trunc_sat_f32_u: negative -> 0"
  (run-single-func
    '((#x7D) . (#x7F))
    '()
    (bv-cat (bytevector #x20 #x00)
            (bytevector #xFC)
            (encode-u32-leb128 1))
    -5.0)
  0)

(test "i32.trunc_sat_f64_s: normal"
  (run-single-func
    '((#x7C) . (#x7F))     ; f64 -> i32
    '()
    (bv-cat (bytevector #x20 #x00)
            (bytevector #xFC)
            (encode-u32-leb128 2))
    -7.8)
  -7)

(test "i32.trunc_sat_f64_u: normal"
  (run-single-func
    '((#x7C) . (#x7F))
    '()
    (bv-cat (bytevector #x20 #x00)
            (bytevector #xFC)
            (encode-u32-leb128 3))
    100.5)
  100)

(test "i64.trunc_sat_f64_s: normal"
  (run-single-func
    '((#x7C) . (#x7E))     ; f64 -> i64
    '()
    (bv-cat (bytevector #x20 #x00)
            (bytevector #xFC)
            (encode-u32-leb128 6))
    -42.7)
  -42)

(test "i64.trunc_sat_f64_u: NaN -> 0"
  (run-single-func
    '((#x7C) . (#x7E))
    '()
    (bv-cat (bytevector #x20 #x00)
            (bytevector #xFC)
            (encode-u32-leb128 7))
    +nan.0)
  0)


;;; ========== 2. Select with Type ==========

(printf "~%= Select with type =~%")

;; select_t: pop c, v2, v1 -> push (if c != 0 then v1 else v2)
(test "select_t: condition true"
  (run-single-func
    '((#x7F #x7F #x7F) . (#x7F))     ; (i32 i32 i32) -> i32
    '()
    (bv-cat (bytevector #x20 #x00)        ; local.get 0 (v1)
            (bytevector #x20 #x01)        ; local.get 1 (v2)
            (bytevector #x20 #x02)        ; local.get 2 (condition)
            (bytevector #x1C)              ; select_t
            (encode-u32-leb128 1)          ; 1 type
            (bytevector #x7F))             ; i32
    10 20 1)
  10)

(test "select_t: condition false"
  (run-single-func
    '((#x7F #x7F #x7F) . (#x7F))
    '()
    (bv-cat (bytevector #x20 #x00)
            (bytevector #x20 #x01)
            (bytevector #x20 #x02)
            (bytevector #x1C)
            (encode-u32-leb128 1)
            (bytevector #x7F))
    10 20 0)
  20)


;;; ========== 3. Reference Types ==========

(printf "~%= Reference types =~%")

;; ref.null funcref -> ref.is_null
(test "ref.null + ref.is_null: null is null"
  (run-single-func
    '(() . (#x7F))          ; () -> i32
    '()
    (bv-cat (bytevector #xD0)              ; ref.null
            (encode-u32-leb128 #x70)       ; funcref type
            (bytevector #xD1))             ; ref.is_null
    )
  1)

;; ref.func + ref.is_null: func ref is not null
(test "ref.func + ref.is_null: func ref not null"
  (run-single-func
    '(() . (#x7F))
    '()
    (bv-cat (bytevector #xD2)              ; ref.func
            (encode-u32-leb128 0)          ; func index 0 (itself)
            (bytevector #xD1))             ; ref.is_null
    )
  0)


;;; ========== 4. Table Operations ==========

(printf "~%= Table operations =~%")

;; Build module with table + elem segment for table.get/table.set
(let ()
  (define (run-table-test code-bv . args)
    (let* ([mod (build-wasm-module
                  (make-type-section '(((#x7F) . (#x7F))))  ; i32 -> i32
                  (make-func-section '(0))
                  (make-table-section 10)
                  (make-export-section '(("test" 0 0)))
                  (make-code-section (list (make-code-body '() code-bv))))]
           [decoded (wasm-decode-module mod)]
           [store (make-wasm-store)]
           [inst (wasm-store-instantiate store decoded)]
           [rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (apply wasm-runtime-call rt "test" args)))

  ;; table.set + table.get
  (test "table.set + table.get"
    (run-table-test
      (bv-cat
        ;; table.set: table[0] = 42
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 0)   ; idx
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 42)  ; val
        (bytevector #x26) (encode-u32-leb128 0)                    ; table.set table 0
        ;; table.get table[0]
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 0)   ; idx
        (bytevector #x25) (encode-u32-leb128 0))                   ; table.get table 0
      99)  ; argument (unused)
    42)

  ;; table.size via 0xFC prefix
  (test "table.size"
    (run-table-test
      (bv-cat
        (bytevector #xFC) (encode-u32-leb128 16)          ; table.size
        (encode-u32-leb128 0))                              ; table idx 0
      0)
    10)
)


;;; ========== 5. Bulk Memory Operations ==========

(printf "~%= Bulk memory operations =~%")

;; memory.fill: fill memory[0..3] with value 0xAA, then load memory[2]
(let ()
  (define (run-mem-test code-bv . args)
    (let* ([mod (build-wasm-module
                  (make-type-section '(((#x7F) . (#x7F))))   ; i32 -> i32
                  (make-func-section '(0))
                  (make-memory-section 1)                     ; 1 page
                  (make-export-section '(("test" 0 0)))
                  (make-code-section (list (make-code-body '() code-bv))))]
           [decoded (wasm-decode-module mod)]
           [store (make-wasm-store)]
           [inst (wasm-store-instantiate store decoded)]
           [rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (apply wasm-runtime-call rt "test" args)))

  (test "memory.fill: fill range"
    (run-mem-test
      (bv-cat
        ;; memory.fill: dest=0, val=0xAB, count=4
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 0)      ; dest
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 #xAB)   ; value
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 4)      ; count
        (bytevector #xFC) (encode-u32-leb128 11)                      ; memory.fill
        (bytevector #x00)                                              ; reserved
        ;; i32.load8_u memory[2]
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 2)
        (bytevector #x2D #x00 #x00))                                  ; i32.load8_u align=0 offset=0
      0)
    #xAB)

  (test "memory.copy: copy range"
    (run-mem-test
      (bv-cat
        ;; First fill dest area with known values using memory.fill
        ;; memory[10] = 0x55 (4 bytes)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 10)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 #x55)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 4)
        (bytevector #xFC) (encode-u32-leb128 11) (bytevector #x00)    ; memory.fill

        ;; memory.copy: dest=20, src=10, count=4
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 20)     ; dest
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 10)     ; src
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 4)      ; count
        (bytevector #xFC) (encode-u32-leb128 10)                      ; memory.copy
        (bytevector #x00 #x00)                                         ; reserved bytes

        ;; Load memory[22] to verify copy
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 22)
        (bytevector #x2D #x00 #x00))                                  ; i32.load8_u
      0)
    #x55)
)


;;; ========== 6. Tail Calls ==========

(printf "~%= Tail calls =~%")

;; Build module with 2 functions: func0 is identity, func1 does return_call to func0
(let ()
  ;; Type: i32 -> i32
  (define type-sec (make-type-section '(((#x7F) . (#x7F)))))

  ;; Two functions, both type 0
  (define func-sec (make-func-section '(0 0)))

  ;; Export func1 as "test"
  (define export-sec (make-export-section '(("test" 0 1))))

  ;; func0: just return local 0 (identity)
  (define func0-body
    (make-code-body '()
      (bytevector #x20 #x00)))  ; local.get 0

  ;; func1: push arg, return_call func0
  (define func1-body
    (make-code-body '()
      (bv-cat (bytevector #x20 #x00)               ; local.get 0
              (bytevector #x12)                      ; return_call
              (encode-u32-leb128 0))))               ; func idx 0

  (define mod (build-wasm-module
                type-sec func-sec export-sec
                (make-code-section (list func0-body func1-body))))

  (test "return_call: tail call to identity"
    (let ([rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (wasm-runtime-call rt "test" 77))
    77)
)


;;; ========== 7. Exception Handling ==========

(printf "~%= Exception handling =~%")

;; Build module with tag and try/catch
;; Type 0: () -> i32 (result)
;; Type 1: (i32) -> () (tag type - takes an i32 parameter)
;; Tag 0: uses type 1

(let ()
  ;; Type 0: () -> i32
  ;; Type 1: (i32) -> ()
  (define type-sec (make-type-section '((() . (#x7F)) ((#x7F) . ()))))

  (define func-sec (make-func-section '(0)))

  (define export-sec (make-export-section '(("test" 0 0))))

  ;; Tag section must come after global (6) and before export (7)...
  ;; Actually tag section has ID 13 which is after code(10)/data(11).
  ;; The validator checks increasing order of section IDs.
  ;; Sections: type(1), function(3), tag(13 -- but must come in order)
  ;; Wait, tag section 13 comes after data(11), so ordering is:
  ;; type(1), function(3), export(7), code(10), tag(13)
  ;; But tag needs to be parsed before code execution... let me check
  ;; the runtime - it uses assv to find sections by ID, so order only
  ;; matters for the validator.

  ;; Actually the validator requires increasing section IDs.
  ;; So tag(13) goes after code(10) and data(11).

  ;; Code body: try (throw tag 0 with value 42) catch tag 0 -> return caught value
  ;; Bytecode:
  ;;   try blocktype=i32 (#x06 #x7F)
  ;;     i32.const 42
  ;;     throw 0
  ;;   catch 0 (#x07 0x00)
  ;;     ;; value from throw is on stack
  ;;   end (#x0B)
  (define code-body
    (make-code-body '()
      (bv-cat
        (bytevector #x06)               ; try
        (bytevector #x7F)               ; blocktype: i32
        (bytevector wasm-opcode-i32-const)
        (encode-i32-leb128 42)
        (bytevector #x08)               ; throw
        (encode-u32-leb128 0)           ; tag index 0
        (bytevector #x07)               ; catch
        (encode-u32-leb128 0)           ; tag index 0
        ;; caught value is on stack, just fall through to end
        )))                              ; end added by make-code-body

  (define tag-sec (make-tag-section '(1)))  ; tag 0 uses type 1

  (define mod (build-wasm-module
                type-sec
                func-sec
                export-sec
                (make-code-section (list code-body))
                tag-sec))

  (test "try/catch: catch thrown value"
    (let ([rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (wasm-runtime-call rt "test"))
    42)
)

;; Test catch_all
(let ()
  (define type-sec (make-type-section '((() . (#x7F)) ((#x7F) . ()))))
  (define func-sec (make-func-section '(0)))
  (define export-sec (make-export-section '(("test" 0 0))))

  ;; try { throw 0 (99) } catch_all { i32.const 77 }
  (define code-body
    (make-code-body '()
      (bv-cat
        (bytevector #x06 #x7F)           ; try blocktype i32
        (bytevector wasm-opcode-i32-const)
        (encode-i32-leb128 99)
        (bytevector #x08)                 ; throw
        (encode-u32-leb128 0)             ; tag 0
        (bytevector #x19)                 ; catch_all
        (bytevector wasm-opcode-i32-const)
        (encode-i32-leb128 77))))

  (define tag-sec (make-tag-section '(1)))
  (define mod (build-wasm-module
                type-sec func-sec export-sec
                (make-code-section (list code-body))
                tag-sec))

  (test "try/catch_all: catch any exception"
    (let ([rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (wasm-runtime-call rt "test"))
    77)
)


;;; ========== 8. GC Proposal: Record Types ==========

(printf "~%= GC record types =~%")

(test "make-wasm-struct and accessors"
  (let ([s (make-wasm-struct 0 (vector 10 20 30))])
    (list (wasm-struct? s)
          (wasm-struct-type-idx s)
          (vector-ref (wasm-struct-fields s) 1)))
  '(#t 0 20))

(test "make-wasm-array and accessors"
  (let ([a (make-wasm-array 0 (vector 1 2 3 4 5))])
    (list (wasm-array? a)
          (wasm-array-type-idx a)
          (vector-length (wasm-array-data a))))
  '(#t 0 5))

(test "make-wasm-i31 and accessor"
  (let ([v (make-wasm-i31 42)])
    (list (wasm-i31? v)
          (wasm-i31-value v)))
  '(#t 42))

(test "make-wasm-tag and accessor"
  (let ([t (make-wasm-tag 3)])
    (list (wasm-tag? t)
          (wasm-tag-type-idx t)))
  '(#t 3))


;;; ========== 9. GC Bytecode: struct.new / struct.get / struct.set ==========

(printf "~%= GC bytecode =~%")

;; struct.new type_idx: pop N fields, create struct
;; struct.get type_idx field_idx: get field from struct
;; For GC opcodes, we need type section with struct types
;; Type 0: func () -> i32 (for the test function)
;; Type 1: struct with 2 i32 fields (but runtime uses list-based types, not real GC encoding)

;; The GC struct.new implementation uses (list-ref types type-idx) to get field count.
;; The type is (params . results), and struct "type" uses (car type) for field list.
;; So we encode a type that has 2 "params" (representing struct fields).

(let ()
  ;; Type 0: () -> i32   -- function signature
  ;; Type 1: (i32 i32) -> ()  -- "struct" type: 2 fields of i32
  (define type-sec (make-type-section '((() . (#x7F)) ((#x7F #x7F) . ()))))
  (define func-sec (make-func-section '(0)))
  (define export-sec (make-export-section '(("test" 0 0))))

  ;; Code: push 10, push 20, struct.new 1 -> struct, struct.get 1 0 -> field 0
  (define code-body
    (make-code-body '()
      (bv-cat
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 10)   ; field 0
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 20)   ; field 1
        (bytevector #xFB) (encode-u32-leb128 #x00)                  ; struct.new
        (encode-u32-leb128 1)                                        ; type_idx 1
        (bytevector #xFB) (encode-u32-leb128 #x02)                  ; struct.get
        (encode-u32-leb128 1)                                        ; type_idx 1
        (encode-u32-leb128 0))))                                     ; field_idx 0

  (define mod (build-wasm-module
                type-sec func-sec export-sec
                (make-code-section (list code-body))))

  (test "struct.new + struct.get field 0"
    (let ([rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (wasm-runtime-call rt "test"))
    10)
)

;; struct.get field 1
(let ()
  (define type-sec (make-type-section '((() . (#x7F)) ((#x7F #x7F) . ()))))
  (define func-sec (make-func-section '(0)))
  (define export-sec (make-export-section '(("test" 0 0))))

  (define code-body
    (make-code-body '()
      (bv-cat
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 10)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 20)
        (bytevector #xFB) (encode-u32-leb128 #x00)
        (encode-u32-leb128 1)
        (bytevector #xFB) (encode-u32-leb128 #x02)
        (encode-u32-leb128 1)
        (encode-u32-leb128 1))))  ; field_idx 1

  (define mod (build-wasm-module
                type-sec func-sec export-sec
                (make-code-section (list code-body))))

  (test "struct.new + struct.get field 1"
    (let ([rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (wasm-runtime-call rt "test"))
    20)
)

;; struct.set: create struct, set field 0 to 99, get it back
(let ()
  (define type-sec (make-type-section '((() . (#x7F)) ((#x7F #x7F) . ()))))
  (define func-sec (make-func-section '(0)))
  (define export-sec (make-export-section '(("test" 0 0))))

  ;; Need a local to store the struct ref
  (define code-body
    (make-code-body
      '((1 #x6F))   ; 1 local of anyref (externref placeholder)
      (bv-cat
        ;; Create struct
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 10)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 20)
        (bytevector #xFB) (encode-u32-leb128 #x00)
        (encode-u32-leb128 1)
        ;; Store in local 0
        (bytevector #x21 #x00)        ; local.set 0
        ;; struct.set: set field 0 to 99
        (bytevector #x20 #x00)        ; local.get 0
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 99)
        (bytevector #xFB) (encode-u32-leb128 #x05)   ; struct.set
        (encode-u32-leb128 1)                          ; type_idx 1
        (encode-u32-leb128 0)                          ; field_idx 0
        ;; struct.get: get field 0
        (bytevector #x20 #x00)        ; local.get 0
        (bytevector #xFB) (encode-u32-leb128 #x02)   ; struct.get
        (encode-u32-leb128 1)
        (encode-u32-leb128 0))))

  (define mod (build-wasm-module
                type-sec func-sec export-sec
                (make-code-section (list code-body))))

  (test "struct.set + struct.get"
    (let ([rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (wasm-runtime-call rt "test"))
    99)
)


;;; ========== 10. GC: array.new_fixed / array.get / array.set / array.len ==========

(printf "~%= GC array operations =~%")

;; array.new_fixed type_idx count: pop count values, create array
(let ()
  ;; Type 0: () -> i32
  ;; Type 1: (i32) -> ()  -- array element type (1 "field")
  (define type-sec (make-type-section '((() . (#x7F)) ((#x7F) . ()))))
  (define func-sec (make-func-section '(0)))
  (define export-sec (make-export-section '(("test" 0 0))))

  ;; Push 3 values, array.new_fixed 1 3, array.get 1 at index 1
  (define code-body
    (make-code-body '()
      (bv-cat
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 100)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 200)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 300)
        (bytevector #xFB) (encode-u32-leb128 #x08)        ; array.new_fixed
        (encode-u32-leb128 1)                               ; type_idx
        (encode-u32-leb128 3)                               ; count
        ;; array.get at index 1
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 1)
        (bytevector #xFB) (encode-u32-leb128 #x0B)        ; array.get
        (encode-u32-leb128 1))))                            ; type_idx

  (define mod (build-wasm-module
                type-sec func-sec export-sec
                (make-code-section (list code-body))))

  (test "array.new_fixed + array.get"
    (let ([rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (wasm-runtime-call rt "test"))
    200)
)

;; array.len
(let ()
  (define type-sec (make-type-section '((() . (#x7F)) ((#x7F) . ()))))
  (define func-sec (make-func-section '(0)))
  (define export-sec (make-export-section '(("test" 0 0))))

  (define code-body
    (make-code-body '()
      (bv-cat
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 0)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 0)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 0)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 0)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 0)
        (bytevector #xFB) (encode-u32-leb128 #x08)
        (encode-u32-leb128 1) (encode-u32-leb128 5)         ; array.new_fixed type=1 count=5
        (bytevector #xFB) (encode-u32-leb128 #x0F))))       ; array.len

  (define mod (build-wasm-module
                type-sec func-sec export-sec
                (make-code-section (list code-body))))

  (test "array.len"
    (let ([rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (wasm-runtime-call rt "test"))
    5)
)

;; array.set
(let ()
  (define type-sec (make-type-section '((() . (#x7F)) ((#x7F) . ()))))
  (define func-sec (make-func-section '(0)))
  (define export-sec (make-export-section '(("test" 0 0))))

  (define code-body
    (make-code-body
      '((1 #x6F))  ; 1 local for array ref
      (bv-cat
        ;; Create array of 3 zeros
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 0)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 0)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 0)
        (bytevector #xFB) (encode-u32-leb128 #x08)
        (encode-u32-leb128 1) (encode-u32-leb128 3)
        ;; Store in local
        (bytevector #x21 #x00)
        ;; array.set: arr[2] = 555
        (bytevector #x20 #x00)    ; local.get 0 (array)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 2)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 555)
        (bytevector #xFB) (encode-u32-leb128 #x0E)   ; array.set
        (encode-u32-leb128 1)                          ; type_idx
        ;; array.get arr[2]
        (bytevector #x20 #x00)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 2)
        (bytevector #xFB) (encode-u32-leb128 #x0B)
        (encode-u32-leb128 1))))

  (define mod (build-wasm-module
                type-sec func-sec export-sec
                (make-code-section (list code-body))))

  (test "array.set + array.get"
    (let ([rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (wasm-runtime-call rt "test"))
    555)
)


;;; ========== 11. GC: i31 operations ==========

(printf "~%= GC i31 =~%")

;; ref.i31: wrap an i32 into i31ref
;; i31.get_s: unwrap signed
(let ()
  (define type-sec (make-type-section '(((#x7F) . (#x7F)))))
  (define func-sec (make-func-section '(0)))
  (define export-sec (make-export-section '(("test" 0 0))))

  (define code-body
    (make-code-body '()
      (bv-cat
        (bytevector #x20 #x00)                            ; local.get 0
        (bytevector #xFB) (encode-u32-leb128 #x1C)        ; ref.i31
        (bytevector #xFB) (encode-u32-leb128 #x1D))))     ; i31.get_s

  (define mod (build-wasm-module
                type-sec func-sec export-sec
                (make-code-section (list code-body))))

  (test "ref.i31 + i31.get_s"
    (let ([rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (wasm-runtime-call rt "test" 42))
    42)

  (test "ref.i31 + i31.get_s negative"
    (let ([rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (let ([result (wasm-runtime-call rt "test" -10)])
        ;; The i31 stores 31-bit signed, so -10 should round-trip
        result))
    -10)
)

;; i31.get_u
(let ()
  (define type-sec (make-type-section '(((#x7F) . (#x7F)))))
  (define func-sec (make-func-section '(0)))
  (define export-sec (make-export-section '(("test" 0 0))))

  (define code-body
    (make-code-body '()
      (bv-cat
        (bytevector #x20 #x00)
        (bytevector #xFB) (encode-u32-leb128 #x1C)
        (bytevector #xFB) (encode-u32-leb128 #x1E))))     ; i31.get_u

  (define mod (build-wasm-module
                type-sec func-sec export-sec
                (make-code-section (list code-body))))

  (test "ref.i31 + i31.get_u"
    (let ([rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (wasm-runtime-call rt "test" 100))
    100)
)


;;; ========== 12. Trap tests for OOB operations ==========

(printf "~%= OOB traps =~%")

;; table.get OOB tested via table module
(let ()
  (define (run-table-trap code-bv . args)
    (let* ([mod (build-wasm-module
                  (make-type-section '(((#x7F) . (#x7F))))
                  (make-func-section '(0))
                  (make-table-section 4)
                  (make-export-section '(("test" 0 0)))
                  (make-code-section (list (make-code-body '() code-bv))))]
           [rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (apply wasm-runtime-call rt "test" args)))

  (test-trap "table.get OOB"
    (run-table-trap
      (bv-cat
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 99)  ; idx 99
        (bytevector #x25) (encode-u32-leb128 0))                   ; table.get 0
      0)
    "OOB")
)

;; Test memory.fill OOB
(let ()
  (define (run-mem-test-oob code-bv)
    (let* ([mod (build-wasm-module
                  (make-type-section '((() . (#x7F))))
                  (make-func-section '(0))
                  (make-memory-section 1)   ; 1 page = 65536 bytes
                  (make-export-section '(("test" 0 0)))
                  (make-code-section (list (make-code-body '() code-bv))))]
           [rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (wasm-runtime-call rt "test")))

  (test-trap "memory.fill OOB"
    (run-mem-test-oob
      (bv-cat
        ;; Fill starting at 65530, count 100 -> exceeds 65536
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 65530)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 0)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 100)
        (bytevector #xFC) (encode-u32-leb128 11)
        (bytevector #x00)))
    "OOB")
)


;;; ========== 13. GC: ref.test / ref.cast ==========

(printf "~%= GC ref.test / ref.cast =~%")

;; ref.test: test if value is of given type
(let ()
  (define type-sec (make-type-section '((() . (#x7F)) ((#x7F #x7F) . ()))))
  (define func-sec (make-func-section '(0)))
  (define export-sec (make-export-section '(("test" 0 0))))

  ;; Create a struct, ref.test against its type
  (define code-body
    (make-code-body '()
      (bv-cat
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 1)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 2)
        (bytevector #xFB) (encode-u32-leb128 #x00)     ; struct.new
        (encode-u32-leb128 1)                            ; type 1
        (bytevector #xFB) (encode-u32-leb128 #x14)     ; ref.test
        (encode-u32-leb128 1))))                         ; type 1

  (define mod (build-wasm-module
                type-sec func-sec export-sec
                (make-code-section (list code-body))))

  (test "ref.test: struct matches its type"
    (let ([rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (wasm-runtime-call rt "test"))
    1)
)

;; ref.test: wrong type -> 0
(let ()
  (define type-sec (make-type-section '((() . (#x7F)) ((#x7F #x7F) . ()) ((#x7F) . ()))))
  (define func-sec (make-func-section '(0)))
  (define export-sec (make-export-section '(("test" 0 0))))

  ;; Create struct type 1, test against type 2
  (define code-body
    (make-code-body '()
      (bv-cat
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 1)
        (bytevector wasm-opcode-i32-const) (encode-i32-leb128 2)
        (bytevector #xFB) (encode-u32-leb128 #x00)
        (encode-u32-leb128 1)
        (bytevector #xFB) (encode-u32-leb128 #x14)     ; ref.test
        (encode-u32-leb128 2))))                         ; type 2 (different)

  (define mod (build-wasm-module
                type-sec func-sec export-sec
                (make-code-section (list code-body))))

  (test "ref.test: struct wrong type -> 0"
    (let ([rt (make-wasm-runtime)])
      (wasm-runtime-load rt mod)
      (wasm-runtime-call rt "test"))
    0)
)


;;; ========== Summary ==========

(printf "~%Post-MVP WASM: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
