#!chezscheme
;;; (jerboa wasm runtime) -- WebAssembly interpreter/runtime
;;;
;;; A stack-based interpreter that executes WASM bytecode.
;;; Supports all MVP opcodes: i32/i64/f32/f64 arithmetic and comparisons,
;;; block/loop/br/br_if control flow, memory load/store, globals,
;;; tables, call_indirect, data/element init, start section, imports.

(library (jerboa wasm runtime)
  (export
    make-wasm-runtime wasm-runtime? wasm-runtime-load wasm-runtime-call
    wasm-runtime-memory-ref wasm-runtime-memory-set!
    wasm-runtime-memory wasm-runtime-memory-size
    wasm-runtime-global-ref wasm-runtime-global-set!
    wasm-runtime-set-fuel! wasm-runtime-set-max-depth!
    wasm-runtime-set-max-stack! wasm-runtime-set-max-memory-pages!
    wasm-runtime-set-max-module-size!
    wasm-runtime-set-import-validator!
    make-wasm-trap wasm-trap? wasm-trap-message
    wasm-instance? wasm-instance-exports
    wasm-decode-module wasm-module-sections wasm-run-start
    wasm-validate-module
    make-wasm-store wasm-store? wasm-store-instantiate
    ;; Post-MVP: GC types
    make-wasm-struct wasm-struct? wasm-struct-type-idx wasm-struct-fields
    make-wasm-array wasm-array? wasm-array-type-idx wasm-array-data
    make-wasm-i31 wasm-i31? wasm-i31-value
    ;; Post-MVP: Exception handling
    make-wasm-tag wasm-tag? wasm-tag-type-idx)

  (import (chezscheme)
          (jerboa wasm format))

  ;;; ========== Trap ==========

  (define-record-type wasm-trap
    (fields message))

  ;;; ========== Branch condition (for block/loop control flow) ==========

  (define-condition-type &wasm-branch &condition
    make-wasm-branch wasm-branch?
    (depth wasm-branch-depth)
    (val   wasm-branch-val))

  ;;; ========== Post-MVP: GC record types ==========

  (define-record-type wasm-struct
    (fields type-idx (mutable fields)))  ; fields = vector

  (define-record-type wasm-array
    (fields type-idx (mutable data)))    ; data = vector

  (define-record-type wasm-i31
    (fields value))                      ; 31-bit signed integer

  ;;; ========== Post-MVP: Exception handling types ==========

  (define-record-type wasm-tag
    (fields type-idx))

  (define-condition-type &wasm-exception &condition
    make-wasm-exception wasm-exception?
    (tag-idx wasm-exception-tag-idx)
    (values  wasm-exception-values))

  ;;; ========== Post-MVP: Tail call condition ==========

  (define-condition-type &wasm-tail-call &condition
    make-wasm-tail-call wasm-tail-call?
    (func-idx wasm-tail-call-func-idx)
    (args     wasm-tail-call-args))

  ;;; ========== Decoded module ==========

  (define-record-type decoded-module
    (fields sections))

  (define (wasm-module-sections mod)
    (decoded-module-sections mod))

  ;;; ========== WASM instance ==========

  (define-record-type wasm-instance
    (fields
      exports        ; alist: name -> (kind idx)
      funcs          ; vector of (param-count code local-count type-idx)
      (mutable memory-box)  ; (vector bytevector) -- boxed for memory.grow
      globals        ; vector
      tables         ; vector of vectors (funcref tables)
      imports        ; vector of import entries (param-count result-count proc type-idx)
      types          ; list of type signatures for call_indirect checking
      (mutable data-segments)  ; vector of bytevectors (for memory.init/data.drop)
      (mutable elem-segments)  ; vector of vectors (for table.init/elem.drop)
      tags))         ; vector of wasm-tag records (for throw/catch)

  ;; Public accessor: returns the raw bytevector
  (define (wasm-instance-memory inst)
    (vector-ref (wasm-instance-memory-box inst) 0))

  ;;; ========== WASM store ==========

  (define-record-type wasm-store
    (fields (mutable instances))
    (protocol (lambda (new) (lambda () (new '())))))

  ;;; ========== WASM runtime ==========

  (define-record-type wasm-runtime
    (fields (mutable instance)
            (mutable fuel)              ; #f or integer (max fuel per call)
            (mutable max-depth)         ; #f or integer (max call depth)
            (mutable max-stack)         ; #f or integer (max value stack depth)
            (mutable max-memory-pages)  ; #f or integer (max memory pages for grow)
            (mutable max-module-size)   ; #f or integer (max bytecode size in bytes)
            (mutable import-validator)) ; #f or (proc module-name func-name args -> args|#f)
    (protocol (lambda (new) (lambda () (new #f #f #f #f #f #f #f)))))

  (define (wasm-runtime-set-fuel! rt n)
    (wasm-runtime-fuel-set! rt n))

  (define (wasm-runtime-set-max-depth! rt n)
    (wasm-runtime-max-depth-set! rt n))

  (define (wasm-runtime-set-max-stack! rt n)
    (wasm-runtime-max-stack-set! rt n))

  (define (wasm-runtime-set-max-memory-pages! rt n)
    (wasm-runtime-max-memory-pages-set! rt n))

  (define (wasm-runtime-set-max-module-size! rt n)
    (wasm-runtime-max-module-size-set! rt n))

  ;; Import validator: a procedure (module-name func-name args) -> args or raise.
  ;; Called before every import function invocation. Use this to integrate with
  ;; capability-based security: check current-capabilities, verify allowed hosts,
  ;; validate file paths, etc. If the validator raises, the WASM trap boundary
  ;; catches it. Set to #f to disable (default).
  (define (wasm-runtime-set-import-validator! rt proc)
    (wasm-runtime-import-validator-set! rt proc))

  ;;; ========== Binary section parsing helpers ==========

  (define (read-u32 bv pos)
    (let* ([r (decode-u32-leb128 bv pos)])
      (cons (car r) (+ pos (cdr r)))))

  (define (read-i32 bv pos)
    (let* ([r (decode-i32-leb128 bv pos)])
      (cons (car r) (+ pos (cdr r)))))

  (define (read-i64 bv pos)
    (let* ([r (decode-i64-leb128 bv pos)])
      (cons (car r) (+ pos (cdr r)))))

  (define (read-string bv pos)
    (let* ([r (decode-string bv pos)])
      (cons (car r) (+ pos (cdr r)))))

  ;;; ========== Binary WASM decoder ==========

  (define (wasm-decode-module bv)
    (let ([len (bytevector-length bv)])
      (unless (and (>= len 8)
                   (= (bytevector-u8-ref bv 0) #x00)
                   (= (bytevector-u8-ref bv 1) #x61)
                   (= (bytevector-u8-ref bv 2) #x73)
                   (= (bytevector-u8-ref bv 3) #x6D))
        (raise (make-wasm-trap "invalid WASM magic")))
      (let loop ([pos 8] [sections '()])
        (if (>= pos len)
          (make-decoded-module (reverse sections))
          (let* ([sid (bytevector-u8-ref bv pos)]
                 [pos1 (+ pos 1)]
                 [sz-result (read-u32 bv pos1)]
                 [sz (car sz-result)]
                 [cstart (cdr sz-result)]
                 [cend (+ cstart sz)]
                 [content (make-bytevector sz)])
            (bytevector-copy! bv cstart content 0 sz)
            (loop cend (cons (cons sid content) sections)))))))

  ;;; ========== Section parsers ==========

  (define (parse-type-section bv)
    (let* ([cr (read-u32 bv 0)] [count (car cr)] [pos (cdr cr)])
      (let loop ([i 0] [pos pos] [acc '()])
        (if (= i count) (reverse acc)
          (let* ([pos1 (+ pos 1)] ; skip 0x60
                 [pcr (read-u32 bv pos1)] [pcount (car pcr)] [pos2 (cdr pcr)]
                 [params+pos
                  (let lp ([j 0] [p pos2] [a '()])
                    (if (= j pcount) (cons (reverse a) p)
                      (lp (+ j 1) (+ p 1) (cons (bytevector-u8-ref bv p) a))))]
                 [params (car params+pos)] [pos3 (cdr params+pos)]
                 [rcr (read-u32 bv pos3)] [rcount (car rcr)] [pos4 (cdr rcr)]
                 [results+pos
                  (let lp ([j 0] [p pos4] [a '()])
                    (if (= j rcount) (cons (reverse a) p)
                      (lp (+ j 1) (+ p 1) (cons (bytevector-u8-ref bv p) a))))]
                 [results (car results+pos)] [pos5 (cdr results+pos)])
            (loop (+ i 1) pos5 (cons (cons params results) acc)))))))

  (define (parse-function-section bv)
    (let* ([cr (read-u32 bv 0)] [count (car cr)] [pos (cdr cr)])
      (let loop ([i 0] [pos pos] [acc '()])
        (if (= i count) (reverse acc)
          (let* ([r (read-u32 bv pos)])
            (loop (+ i 1) (cdr r) (cons (car r) acc)))))))

  (define (parse-export-section bv)
    (let* ([cr (read-u32 bv 0)] [count (car cr)] [pos (cdr cr)])
      (let loop ([i 0] [pos pos] [acc '()])
        (if (= i count) (reverse acc)
          (let* ([nr (read-string bv pos)] [name (car nr)] [pos1 (cdr nr)]
                 [kind (bytevector-u8-ref bv pos1)] [pos2 (+ pos1 1)]
                 [ir (read-u32 bv pos2)] [idx (car ir)] [pos3 (cdr ir)])
            (loop (+ i 1) pos3 (cons (list name kind idx) acc)))))))

  (define (parse-code-section bv)
    (let* ([cr (read-u32 bv 0)] [count (car cr)] [pos (cdr cr)])
      (let loop ([i 0] [pos pos] [acc '()])
        (if (= i count) (reverse acc)
          (let* ([sr (read-u32 bv pos)] [sz (car sr)] [body-start (cdr sr)]
                 [body-end (+ body-start sz)]
                 [lcr (read-u32 bv body-start)]
                 [lcount (car lcr)] [lpos (cdr lcr)]
                 [locals+pos
                  (let lp ([j 0] [p lpos] [a '()])
                    (if (= j lcount) (cons (reverse a) p)
                      (let* ([nr (read-u32 bv p)] [n (car nr)] [p1 (cdr nr)]
                             [t (bytevector-u8-ref bv p1)] [p2 (+ p1 1)])
                        (lp (+ j 1) p2 (append a (make-list n t))))))]
                 [local-types (car locals+pos)]
                 [code-start (cdr locals+pos)]
                 [code-len (- body-end code-start)]
                 [code-bv (make-bytevector code-len)])
            (bytevector-copy! bv code-start code-bv 0 code-len)
            (loop (+ i 1) body-end (cons (cons local-types code-bv) acc)))))))

  (define (parse-import-section bv)
    (let* ([cr (read-u32 bv 0)] [count (car cr)] [pos (cdr cr)])
      (let loop ([i 0] [pos pos] [acc '()])
        (if (= i count) (reverse acc)
          (let* ([mr (read-string bv pos)] [mod-name (car mr)] [pos1 (cdr mr)]
                 [nr (read-string bv pos1)] [name (car nr)] [pos2 (cdr nr)]
                 [kind (bytevector-u8-ref bv pos2)] [pos3 (+ pos2 1)])
            (case kind
              [(0) ;; function import
               (let* ([tr (read-u32 bv pos3)] [tidx (car tr)] [pos4 (cdr tr)])
                 (loop (+ i 1) pos4
                   (cons (list 'func mod-name name tidx) acc)))]
              [(1) ;; table import
               (let* ([etype (bytevector-u8-ref bv pos3)] [pos4 (+ pos3 1)]
                      [lr (parse-limits bv pos4)])
                 (loop (+ i 1) (cdr lr)
                   (cons (list 'table mod-name name etype (car lr)) acc)))]
              [(2) ;; memory import
               (let* ([lr (parse-limits bv pos3)])
                 (loop (+ i 1) (cdr lr)
                   (cons (list 'memory mod-name name (car lr)) acc)))]
              [(3) ;; global import
               (let* ([gtype (bytevector-u8-ref bv pos3)]
                      [gmut (bytevector-u8-ref bv (+ pos3 1))]
                      [pos4 (+ pos3 2)])
                 (loop (+ i 1) pos4
                   (cons (list 'global mod-name name gtype gmut) acc)))]
              [else
               (raise (make-wasm-trap
                 (string-append "unknown import kind: " (number->string kind))))]))))))

  (define (parse-limits bv pos)
    (let ([flag (bytevector-u8-ref bv pos)])
      (if (= flag 0)
        (let* ([r (read-u32 bv (+ pos 1))])
          (cons (cons (car r) #f) (cdr r)))
        (let* ([r1 (read-u32 bv (+ pos 1))]
               [r2 (read-u32 bv (cdr r1))])
          (cons (cons (car r1) (car r2)) (cdr r2))))))

  (define (parse-global-section bv)
    (let* ([cr (read-u32 bv 0)] [count (car cr)] [pos (cdr cr)])
      (let loop ([i 0] [pos pos] [acc '()])
        (if (= i count) (reverse acc)
          (let* ([gtype (bytevector-u8-ref bv pos)]
                 [gmut (bytevector-u8-ref bv (+ pos 1))]
                 [pos2 (+ pos 2)]
                 ;; Evaluate init expression (simplified: single const + end)
                 [init-result (eval-init-expr bv pos2)]
                 [init-val (car init-result)]
                 [pos3 (cdr init-result)])
            (loop (+ i 1) pos3
              (cons (list gtype gmut init-val) acc)))))))

  (define (eval-init-expr bv pos)
    (let ([op (bytevector-u8-ref bv pos)])
      (cond
        [(= op #x41) ; i32.const
         (let* ([r (read-i32 bv (+ pos 1))])
           (let ([end-pos (cdr r)])
             ;; skip 0x0B (end)
             (cons (car r) (+ end-pos 1))))]
        [(= op #x42) ; i64.const
         (let* ([r (read-i64 bv (+ pos 1))])
           (cons (car r) (+ (cdr r) 1)))]
        [(= op #x43) ; f32.const
         (let ([val (decode-f32 bv (+ pos 1))])
           (cons val (+ pos 6)))] ; 1 opcode + 4 bytes + 1 end
        [(= op #x44) ; f64.const
         (let ([val (decode-f64 bv (+ pos 1))])
           (cons val (+ pos 10)))] ; 1 opcode + 8 bytes + 1 end
        [(= op #x23) ; global.get (for global init referencing earlier global)
         (let* ([r (read-u32 bv (+ pos 1))])
           (cons (list 'global.get (car r)) (+ (cdr r) 1)))]
        [else
         (raise (make-wasm-trap
           (string-append "unsupported init expression opcode: 0x"
                          (number->string op 16))))])))

  (define (parse-memory-section bv)
    (let* ([cr (read-u32 bv 0)] [count (car cr)] [pos (cdr cr)])
      (let loop ([i 0] [pos pos] [acc '()])
        (if (= i count) (reverse acc)
          (let* ([lr (parse-limits bv pos)])
            (loop (+ i 1) (cdr lr) (cons (car lr) acc)))))))

  (define (parse-table-section bv)
    (let* ([cr (read-u32 bv 0)] [count (car cr)] [pos (cdr cr)])
      (let loop ([i 0] [pos pos] [acc '()])
        (if (= i count) (reverse acc)
          (let* ([etype (bytevector-u8-ref bv pos)]
                 [lr (parse-limits bv (+ pos 1))])
            (loop (+ i 1) (cdr lr)
              (cons (list etype (car lr)) acc)))))))

  (define (parse-element-section bv)
    (let* ([cr (read-u32 bv 0)] [count (car cr)] [pos (cdr cr)])
      (let loop ([i 0] [pos pos] [acc '()])
        (if (= i count) (reverse acc)
          (let* ([tidx-r (read-u32 bv pos)]
                 [tidx (car tidx-r)]
                 [pos1 (cdr tidx-r)]
                 ;; offset init expr
                 [offset-r (eval-init-expr bv pos1)]
                 [offset (car offset-r)]
                 [pos2 (cdr offset-r)]
                 ;; func indices
                 [fcr (read-u32 bv pos2)]
                 [fcount (car fcr)]
                 [pos3 (cdr fcr)]
                 [fidxs+pos
                  (let lp ([j 0] [p pos3] [a '()])
                    (if (= j fcount) (cons (reverse a) p)
                      (let* ([r (read-u32 bv p)])
                        (lp (+ j 1) (cdr r) (cons (car r) a)))))]
                 [fidxs (car fidxs+pos)]
                 [pos4 (cdr fidxs+pos)])
            (loop (+ i 1) pos4
              (cons (list tidx offset fidxs) acc)))))))

  (define (parse-data-section bv)
    (let* ([cr (read-u32 bv 0)] [count (car cr)] [pos (cdr cr)])
      (let loop ([i 0] [pos pos] [acc '()])
        (if (= i count) (reverse acc)
          (let* ([midx-r (read-u32 bv pos)]
                 [midx (car midx-r)]
                 [pos1 (cdr midx-r)]
                 [offset-r (eval-init-expr bv pos1)]
                 [offset (car offset-r)]
                 [pos2 (cdr offset-r)]
                 [sz-r (read-u32 bv pos2)]
                 [sz (car sz-r)]
                 [pos3 (cdr sz-r)]
                 [data (make-bytevector sz)])
            (bytevector-copy! bv pos3 data 0 sz)
            (loop (+ i 1) (+ pos3 sz)
              (cons (list midx offset data) acc)))))))

  (define (parse-start-section bv)
    (car (read-u32 bv 0)))

  ;;; ========== Instruction skipping ==========

  (define (skip-instr bv pos len)
    (if (>= pos len) pos
      (let ([op (bytevector-u8-ref bv pos)])
        (cond
          ;; No immediates
          [(or (= op #x00) (= op #x01) (= op #x0F) (= op #x1A) (= op #x1B)
               (and (>= op #x45) (<= op #xC4))
               (= op #x0B) (= op #x05)
               (= op #xD1))  ; ref.is_null
           (+ pos 1)]
          ;; One LEB128 immediate
          [(or (= op #x0C) (= op #x0D)  ; br, br_if
               (= op #x10)              ; call
               (= op #x12)              ; return_call
               (= op #x20) (= op #x21) (= op #x22)  ; local ops
               (= op #x23) (= op #x24)               ; global ops
               (= op #x25) (= op #x26)               ; table.get, table.set
               (= op #x08)              ; throw (tag index)
               (= op #x09)              ; rethrow (depth)
               (= op #xD0)              ; ref.null (type)
               (= op #xD2))             ; ref.func (func index)
           (let* ([r (decode-u32-leb128 bv (+ pos 1))])
             (+ pos 1 (cdr r)))]
          ;; i32.const / i64.const (signed LEB128)
          [(= op #x41)
           (let* ([r (decode-i32-leb128 bv (+ pos 1))])
             (+ pos 1 (cdr r)))]
          [(= op #x42)
           (let* ([r (decode-i64-leb128 bv (+ pos 1))])
             (+ pos 1 (cdr r)))]
          ;; f32.const: 4 bytes
          [(= op #x43) (+ pos 5)]
          ;; f64.const: 8 bytes
          [(= op #x44) (+ pos 9)]
          ;; block/loop/try: 1 byte block type
          [(or (= op #x02) (= op #x03) (= op #x06)) (+ pos 2)]
          ;; if: 1 byte block type
          [(= op #x04) (+ pos 2)]
          ;; catch: 1 LEB128 (tag index)
          [(= op #x07)
           (let* ([r (decode-u32-leb128 bv (+ pos 1))])
             (+ pos 1 (cdr r)))]
          ;; delegate: 1 LEB128 (depth)
          [(= op #x18)
           (let* ([r (decode-u32-leb128 bv (+ pos 1))])
             (+ pos 1 (cdr r)))]
          ;; catch_all: no immediates
          [(= op #x19) (+ pos 1)]
          ;; select_t: 1 LEB128 count + count type bytes
          [(= op #x1C)
           (let* ([r (decode-u32-leb128 bv (+ pos 1))]
                  [count (car r)])
             (+ pos 1 (cdr r) count))]
          ;; memory.size, memory.grow: 1 byte (reserved)
          [(or (= op #x3F) (= op #x40)) (+ pos 2)]
          ;; call_indirect / return_call_indirect: 2 LEB128
          [(or (= op #x11) (= op #x13))
           (let* ([r1 (decode-u32-leb128 bv (+ pos 1))]
                  [r2 (decode-u32-leb128 bv (+ pos 1 (cdr r1)))])
             (+ pos 1 (cdr r1) (cdr r2)))]
          ;; br_table: count + labels + default
          [(= op #x0E)
           (let* ([cr (decode-u32-leb128 bv (+ pos 1))]
                  [count (car cr)])
             (let loop ([n (+ count 1)] [p (+ pos 1 (cdr cr))])
               (if (= n 0) p
                 (let* ([r (decode-u32-leb128 bv p)])
                   (loop (- n 1) (+ p (cdr r)))))))]
          ;; memory load/store: 2 LEB128 (align, offset)
          [(and (>= op #x28) (<= op #x3E))
           (let* ([r1 (decode-u32-leb128 bv (+ pos 1))]
                  [r2 (decode-u32-leb128 bv (+ pos 1 (cdr r1)))])
             (+ pos 1 (cdr r1) (cdr r2)))]
          ;; 0xFC prefix: sub-opcode LEB128 + varying immediates
          [(= op #xFC)
           (let* ([r (decode-u32-leb128 bv (+ pos 1))]
                  [sub (car r)]
                  [p (+ pos 1 (cdr r))])
             (cond
               [(<= sub 7) p]  ; sat truncations: no extra immediates
               [(= sub 8)   ; memory.init: data-idx + 0x00
                (let* ([r2 (decode-u32-leb128 bv p)]) (+ p (cdr r2) 1))]
               [(= sub 9)   ; data.drop: data-idx
                (let* ([r2 (decode-u32-leb128 bv p)]) (+ p (cdr r2)))]
               [(= sub 10)  ; memory.copy: 0x00 0x00
                (+ p 2)]
               [(= sub 11)  ; memory.fill: 0x00
                (+ p 1)]
               [(= sub 12)  ; table.init: elem-idx + table-idx
                (let* ([r2 (decode-u32-leb128 bv p)]
                       [r3 (decode-u32-leb128 bv (+ p (cdr r2)))])
                  (+ p (cdr r2) (cdr r3)))]
               [(= sub 13)  ; elem.drop: elem-idx
                (let* ([r2 (decode-u32-leb128 bv p)]) (+ p (cdr r2)))]
               [(= sub 14)  ; table.copy: dst-table + src-table
                (let* ([r2 (decode-u32-leb128 bv p)]
                       [r3 (decode-u32-leb128 bv (+ p (cdr r2)))])
                  (+ p (cdr r2) (cdr r3)))]
               [(= sub 15)  ; table.grow: table-idx
                (let* ([r2 (decode-u32-leb128 bv p)]) (+ p (cdr r2)))]
               [(= sub 16)  ; table.size: table-idx
                (let* ([r2 (decode-u32-leb128 bv p)]) (+ p (cdr r2)))]
               [(= sub 17)  ; table.fill: table-idx
                (let* ([r2 (decode-u32-leb128 bv p)]) (+ p (cdr r2)))]
               [else p]))]
          ;; 0xFB prefix: sub-opcode LEB128 + varying immediates
          [(= op #xFB)
           (let* ([r (decode-u32-leb128 bv (+ pos 1))]
                  [sub (car r)]
                  [p (+ pos 1 (cdr r))])
             (cond
               ;; struct.new, struct.new_default: type-idx
               [(or (= sub #x00) (= sub #x01))
                (let* ([r2 (decode-u32-leb128 bv p)]) (+ p (cdr r2)))]
               ;; struct.get/get_s/get_u/set: type-idx + field-idx
               [(and (>= sub #x02) (<= sub #x05))
                (let* ([r2 (decode-u32-leb128 bv p)]
                       [r3 (decode-u32-leb128 bv (+ p (cdr r2)))])
                  (+ p (cdr r2) (cdr r3)))]
               ;; array.new, array.new_default: type-idx
               [(or (= sub #x06) (= sub #x07))
                (let* ([r2 (decode-u32-leb128 bv p)]) (+ p (cdr r2)))]
               ;; array.new_fixed: type-idx + count
               [(= sub #x08)
                (let* ([r2 (decode-u32-leb128 bv p)]
                       [r3 (decode-u32-leb128 bv (+ p (cdr r2)))])
                  (+ p (cdr r2) (cdr r3)))]
               ;; array.new_data/new_elem: type-idx + data/elem-idx
               [(or (= sub #x09) (= sub #x0A))
                (let* ([r2 (decode-u32-leb128 bv p)]
                       [r3 (decode-u32-leb128 bv (+ p (cdr r2)))])
                  (+ p (cdr r2) (cdr r3)))]
               ;; array.get/get_s/get_u/set: type-idx
               [(and (>= sub #x0B) (<= sub #x0E))
                (let* ([r2 (decode-u32-leb128 bv p)]) (+ p (cdr r2)))]
               ;; array.len: no immediates
               [(= sub #x0F) p]
               ;; array.fill: type-idx
               [(= sub #x10)
                (let* ([r2 (decode-u32-leb128 bv p)]) (+ p (cdr r2)))]
               ;; array.copy: dst-type + src-type
               [(= sub #x11)
                (let* ([r2 (decode-u32-leb128 bv p)]
                       [r3 (decode-u32-leb128 bv (+ p (cdr r2)))])
                  (+ p (cdr r2) (cdr r3)))]
               ;; array.init_data/init_elem: type-idx + seg-idx
               [(or (= sub #x12) (= sub #x13))
                (let* ([r2 (decode-u32-leb128 bv p)]
                       [r3 (decode-u32-leb128 bv (+ p (cdr r2)))])
                  (+ p (cdr r2) (cdr r3)))]
               ;; ref.test/cast/test_null/cast_null: type-idx
               [(and (>= sub #x14) (<= sub #x17))
                (let* ([r2 (decode-u32-leb128 bv p)]) (+ p (cdr r2)))]
               ;; br_on_cast/br_on_cast_fail: flags + label + type1 + type2
               [(or (= sub #x18) (= sub #x19))
                (let* ([flags (+ p 1)]  ; 1 byte flags
                       [r2 (decode-u32-leb128 bv flags)]
                       [r3 (decode-u32-leb128 bv (+ flags (cdr r2)))]
                       [r4 (decode-u32-leb128 bv (+ flags (cdr r2) (cdr r3)))])
                  (+ flags (cdr r2) (cdr r3) (cdr r4)))]
               ;; extern.internalize/externalize: no immediates
               [(or (= sub #x1A) (= sub #x1B)) p]
               ;; ref.i31: no immediates
               [(= sub #x1C) p]
               ;; i31.get_s/get_u: no immediates
               [(or (= sub #x1D) (= sub #x1E)) p]
               [else p]))]
          [else (+ pos 1)]))))

  (define (skip-to-else-or-end bv pos len)
    (let loop ([pos pos] [depth 0])
      (if (>= pos len)
        (raise (make-wasm-trap "unterminated if block"))
        (let ([op (bytevector-u8-ref bv pos)])
          (cond
            [(= op #x0B) ; end
             (if (= depth 0) (cons 'end (+ pos 1))
               (loop (+ pos 1) (- depth 1)))]
            [(= op #x05) ; else
             (if (= depth 0) (cons 'else (+ pos 1))
               (loop (+ pos 1) depth))]
            [(or (= op #x02) (= op #x03) (= op #x04))
             (loop (skip-instr bv pos len) (+ depth 1))]
            [else
             (loop (skip-instr bv pos len) depth)])))))

  (define (skip-to-end bv pos len)
    (let loop ([pos pos] [depth 0])
      (if (>= pos len)
        (raise (make-wasm-trap "unterminated block"))
        (let ([op (bytevector-u8-ref bv pos)])
          (cond
            [(= op #x0B)
             (if (= depth 0) (+ pos 1)
               (loop (+ pos 1) (- depth 1)))]
            [(or (= op #x02) (= op #x03) (= op #x04))
             (loop (skip-instr bv pos len) (+ depth 1))]
            [else
             (loop (skip-instr bv pos len) depth)])))))

  ;;; ========== Numeric helpers ==========

  (define (i32 n)
    (let ([n32 (bitwise-and n #xFFFFFFFF)])
      (if (>= n32 #x80000000) (- n32 #x100000000) n32)))

  (define (u32 n)
    (bitwise-and n #xFFFFFFFF))

  (define (i64 n)
    (let ([n64 (bitwise-and n #xFFFFFFFFFFFFFFFF)])
      (if (>= n64 #x8000000000000000) (- n64 #x10000000000000000) n64)))

  (define (u64 n)
    (bitwise-and n #xFFFFFFFFFFFFFFFF))

  (define (i32-bool b) (if b 1 0))

  ;; Count leading zeros for 32-bit
  (define (clz32 n)
    (let ([n (u32 n)])
      (if (= n 0) 32
        (let loop ([bits 0] [mask #x80000000])
          (if (not (= (bitwise-and n mask) 0)) bits
            (loop (+ bits 1) (bitwise-arithmetic-shift-right mask 1)))))))

  ;; Count trailing zeros for 32-bit
  (define (ctz32 n)
    (let ([n (u32 n)])
      (if (= n 0) 32
        (let loop ([bits 0] [mask 1])
          (if (not (= (bitwise-and n mask) 0)) bits
            (loop (+ bits 1) (bitwise-arithmetic-shift-left mask 1)))))))

  ;; Population count for 32-bit
  (define (popcnt32 n)
    (let ([n (u32 n)])
      (let loop ([n n] [count 0])
        (if (= n 0) count
          (loop (bitwise-arithmetic-shift-right n 1)
                (+ count (bitwise-and n 1)))))))

  ;; Rotate left 32-bit
  (define (rotl32 val k)
    (let ([v (u32 val)] [s (bitwise-and k 31)])
      (i32 (bitwise-ior
             (bitwise-arithmetic-shift-left v s)
             (bitwise-arithmetic-shift-right v (- 32 s))))))

  ;; Rotate right 32-bit
  (define (rotr32 val k)
    (let ([v (u32 val)] [s (bitwise-and k 31)])
      (i32 (bitwise-ior
             (bitwise-arithmetic-shift-right v s)
             (bitwise-arithmetic-shift-left v (- 32 s))))))

  ;; Count leading zeros for 64-bit
  (define (clz64 n)
    (let ([n (u64 n)])
      (if (= n 0) 64
        (let loop ([bits 0] [mask #x8000000000000000])
          (if (not (= (bitwise-and n mask) 0)) bits
            (loop (+ bits 1) (bitwise-arithmetic-shift-right mask 1)))))))

  ;; Count trailing zeros for 64-bit
  (define (ctz64 n)
    (let ([n (u64 n)])
      (if (= n 0) 64
        (let loop ([bits 0] [mask 1])
          (if (not (= (bitwise-and n mask) 0)) bits
            (loop (+ bits 1) (bitwise-arithmetic-shift-left mask 1)))))))

  ;; Population count for 64-bit
  (define (popcnt64 n)
    (let ([n (u64 n)])
      (let loop ([n n] [count 0])
        (if (= n 0) count
          (loop (bitwise-arithmetic-shift-right n 1)
                (+ count (bitwise-and n 1)))))))

  ;; Rotate left 64-bit
  (define (rotl64 val k)
    (let ([v (u64 val)] [s (bitwise-and k 63)])
      (i64 (bitwise-ior
             (bitwise-arithmetic-shift-left v s)
             (bitwise-arithmetic-shift-right v (- 64 s))))))

  ;; Rotate right 64-bit
  (define (rotr64 val k)
    (let ([v (u64 val)] [s (bitwise-and k 63)])
      (i64 (bitwise-ior
             (bitwise-arithmetic-shift-right v s)
             (bitwise-arithmetic-shift-left v (- 64 s))))))

  ;; Unsigned division/remainder for i32
  (define (i32-div-u a b)
    (when (= b 0) (raise (make-wasm-trap "integer divide by zero")))
    (i32 (quotient (u32 a) (u32 b))))

  (define (i32-rem-u a b)
    (when (= b 0) (raise (make-wasm-trap "integer remainder by zero")))
    (i32 (remainder (u32 a) (u32 b))))

  ;; Unsigned comparison helpers for i32
  (define (i32-lt-u a b) (< (u32 a) (u32 b)))
  (define (i32-gt-u a b) (> (u32 a) (u32 b)))
  (define (i32-le-u a b) (<= (u32 a) (u32 b)))
  (define (i32-ge-u a b) (>= (u32 a) (u32 b)))

  ;; f32 min/max per WASM spec (propagates NaN)
  (define (f32-min a b)
    (cond [(nan? a) a] [(nan? b) b]
          [(and (= a 0.0) (= b 0.0)
                (or (fl< a 0.0) (fl< b 0.0)))
           -0.0]
          [else (flmin a b)]))
  (define (f32-max a b)
    (cond [(nan? a) a] [(nan? b) b]
          [(and (= a 0.0) (= b 0.0)
                (or (fl> a 0.0) (fl> b 0.0)))
           +0.0]
          [else (flmax a b)]))
  (define (f64-min a b) (f32-min a b))
  (define (f64-max a b) (f32-max a b))

  ;; copysign
  (define (f-copysign a b)
    (let ([a (flabs a)])
      (if (fl< b 0.0) (fl- a) a)))

  ;; nearest (round to even)
  (define (f-nearest x)
    (let ([r (flround x)])
      ;; WASM nearest rounds ties to even
      (if (and (= (abs (- x r)) 0.5)
               (odd? (exact (fltruncate x))))
        (if (> x 0.0) (- r 1.0) (+ r 1.0))
        r)))

  ;;; ========== Memory access helpers (bounds-checked) ==========

  (define (check-mem-bounds memory addr size)
    (let ([mem-len (bytevector-length memory)])
      (when (or (< addr 0) (> (+ addr size) mem-len))
        (raise (make-wasm-trap
          (string-append "out of bounds memory access at "
                         (number->string addr)
                         " (size " (number->string size)
                         ", memory " (number->string mem-len) ")"))))))

  (define (mem-load-i32 memory addr)
    (check-mem-bounds memory addr 4)
    (let ([b0 (bytevector-u8-ref memory addr)]
          [b1 (bytevector-u8-ref memory (+ addr 1))]
          [b2 (bytevector-u8-ref memory (+ addr 2))]
          [b3 (bytevector-u8-ref memory (+ addr 3))])
      (i32 (bitwise-ior b0 (bitwise-arithmetic-shift-left b1 8)
                         (bitwise-arithmetic-shift-left b2 16)
                         (bitwise-arithmetic-shift-left b3 24)))))

  (define (mem-store-i32 memory addr val)
    (check-mem-bounds memory addr 4)
    (let ([v (u32 val)])
      (bytevector-u8-set! memory addr (bitwise-and v #xFF))
      (bytevector-u8-set! memory (+ addr 1) (bitwise-and (bitwise-arithmetic-shift-right v 8) #xFF))
      (bytevector-u8-set! memory (+ addr 2) (bitwise-and (bitwise-arithmetic-shift-right v 16) #xFF))
      (bytevector-u8-set! memory (+ addr 3) (bitwise-and (bitwise-arithmetic-shift-right v 24) #xFF))))

  (define (mem-load-i64 memory addr)
    (check-mem-bounds memory addr 8)
    (let loop ([i 0] [result 0])
      (if (= i 8) (i64 result)
        (loop (+ i 1)
              (bitwise-ior result
                (bitwise-arithmetic-shift-left
                  (bytevector-u8-ref memory (+ addr i)) (* i 8)))))))

  (define (mem-store-i64 memory addr val)
    (check-mem-bounds memory addr 8)
    (let ([v (u64 val)])
      (let loop ([i 0] [v v])
        (when (< i 8)
          (bytevector-u8-set! memory (+ addr i) (bitwise-and v #xFF))
          (loop (+ i 1) (bitwise-arithmetic-shift-right v 8))))))

  (define (mem-load-f32 memory addr)
    (check-mem-bounds memory addr 4)
    (bytevector-ieee-single-ref memory addr 'little))

  (define (mem-store-f32 memory addr val)
    (check-mem-bounds memory addr 4)
    (bytevector-ieee-single-set! memory addr val 'little))

  (define (mem-load-f64 memory addr)
    (check-mem-bounds memory addr 8)
    (bytevector-ieee-double-ref memory addr 'little))

  (define (mem-store-f64 memory addr val)
    (check-mem-bounds memory addr 8)
    (bytevector-ieee-double-set! memory addr val 'little))

  (define (mem-load-i8-s memory addr)
    (check-mem-bounds memory addr 1)
    (let ([v (bytevector-u8-ref memory addr)])
      (if (>= v 128) (- v 256) v)))

  (define (mem-load-i8-u memory addr)
    (check-mem-bounds memory addr 1)
    (bytevector-u8-ref memory addr))

  (define (mem-load-i16-s memory addr)
    (check-mem-bounds memory addr 2)
    (let ([v (bitwise-ior (bytevector-u8-ref memory addr)
                          (bitwise-arithmetic-shift-left
                            (bytevector-u8-ref memory (+ addr 1)) 8))])
      (if (>= v 32768) (- v 65536) v)))

  (define (mem-load-i16-u memory addr)
    (check-mem-bounds memory addr 2)
    (bitwise-ior (bytevector-u8-ref memory addr)
                 (bitwise-arithmetic-shift-left
                   (bytevector-u8-ref memory (+ addr 1)) 8)))

  (define (mem-store-i8 memory addr val)
    (check-mem-bounds memory addr 1)
    (bytevector-u8-set! memory addr (bitwise-and val #xFF)))

  (define (mem-store-i16 memory addr val)
    (check-mem-bounds memory addr 2)
    (bytevector-u8-set! memory addr (bitwise-and val #xFF))
    (bytevector-u8-set! memory (+ addr 1)
      (bitwise-and (bitwise-arithmetic-shift-right val 8) #xFF)))

  ;;; ========== Interpreter ==========

  ;; limits = (vector fuel max-call-depth max-stack-depth max-memory-pages)
  ;; memory-box = (vector bytevector) -- shared mutable reference
  (define (execute-func code-bv locals-vec all-funcs memory-box globals tables imports limits depth types data-segs elem-segs tags)
    ;; Check call depth
    (let ([max-depth (vector-ref limits 1)])
      (when (> depth max-depth)
        (raise (make-wasm-trap
          (string-append "call depth exceeded (limit "
                         (number->string max-depth) ")")))))

    (let ([stack '()]
          [stack-depth 0]
          [max-stack (vector-ref limits 2)]
          [pos 0]
          [memory (vector-ref memory-box 0)]
          [len (bytevector-length code-bv)])

      (define (push! v)
        (set! stack-depth (+ stack-depth 1))
        (when (> stack-depth max-stack)
          (raise (make-wasm-trap
            (string-append "value stack overflow (limit "
                           (number->string max-stack) ")"))))
        (set! stack (cons v stack)))
      (define (pop!)
        (when (null? stack) (raise (make-wasm-trap "stack underflow")))
        (set! stack-depth (- stack-depth 1))
        (let ([v (car stack)]) (set! stack (cdr stack)) v))
      (define (peek)
        (when (null? stack) (raise (make-wasm-trap "stack underflow")))
        (car stack))

      ;; Safe import function call: validates arity, runs import-validator,
      ;; catches exceptions, validates return type is a WASM-compatible number.
      (define (safe-import-call! imp-entry args)
        (let ([param-count (car imp-entry)]
              [result-count (cadr imp-entry)]
              [proc (caddr imp-entry)]
              [import-validator (and (> (vector-length limits) 4) (vector-ref limits 4))])
          (when proc
            ;; Validate argument count matches declared param count
            (unless (= (length args) param-count)
              (raise (make-wasm-trap
                (string-append "import call: argument count mismatch, expected "
                               (number->string param-count)
                               " got " (number->string (length args))))))
            ;; Run import validator if set (capability integration point)
            (when import-validator
              (import-validator proc args))
            ;; Call with exception boundary
            (let ([result
                   (guard (exn
                            [(wasm-trap? exn) (raise exn)]
                            [else
                             (raise (make-wasm-trap
                               (string-append "import function raised exception: "
                                 (call-with-string-output-port
                                   (lambda (p) (display-condition exn p))))))])
                     (apply proc args))])
              (when (> result-count 0)
                ;; Validate return value is a number (WASM only has numeric types)
                (unless (number? result)
                  (raise (make-wasm-trap
                    (string-append "import function returned non-numeric value: "
                                   (call-with-string-output-port
                                     (lambda (p) (write result p)))))))
                (push! result))))))

      ;; Read a memory address: evaluate offset + addr from stack
      (define (read-memarg)
        (let* ([r1 (decode-u32-leb128 code-bv pos)]
               [align (car r1)]
               [r2 (decode-u32-leb128 code-bv (+ pos (cdr r1)))]
               [offset (car r2)])
          (set! pos (+ pos (cdr r1) (cdr r2)))
          (let* ([base (pop!)]
                 ;; Clamp to u32 range to prevent Scheme bignum addresses
                 [addr (bitwise-and (+ (bitwise-and base #xFFFFFFFF) offset) #xFFFFFFFF)])
            addr)))

      ;; Execute a block body (between current pos and matching end).
      ;; Returns the position past the end opcode.
      ;; block-type: the WASM block type byte
      ;; kind: 'block or 'loop
      (define (execute-block block-type kind)
        (let ([loop-start pos]
              [end-pos (skip-to-end code-bv pos len)])
          (let restart ()
            (guard (exn
              [(and (wasm-branch? exn) (= (wasm-branch-depth exn) 0))
               (cond
                 [(eq? kind 'loop)
                  ;; br 0 to loop = restart
                  (set! pos loop-start)
                  (restart)]
                 [else
                  ;; br 0 to block = exit with value
                  (let ([val (wasm-branch-val exn)])
                    (when (and val (not (= block-type #x40)))
                      (push! val))
                    (set! pos end-pos))])]
              [(wasm-branch? exn)
               ;; Targeting outer block: decrement and re-raise
               (raise (make-wasm-branch (- (wasm-branch-depth exn) 1)
                                        (wasm-branch-val exn)))])
              ;; Normal execution of the block body
              (run-until-end)
              ;; Normal completion: pos is past the 'end'
              ))))

      ;; Run instructions until we hit 'end' at depth 0
      (define (run-until-end)
        (let step ()
          (when (< pos len)
            ;; Fuel check
            (let ([fuel (vector-ref limits 0)])
              (when (<= fuel 0)
                (raise (make-wasm-trap "fuel exhausted")))
              (vector-set! limits 0 (- fuel 1)))
            (let ([op (bytevector-u8-ref code-bv pos)])
              (set! pos (+ pos 1))
              (guard (exn
                [(wasm-trap? exn) (raise exn)]
                [(wasm-branch? exn) (raise exn)]
                [(wasm-tail-call? exn) (raise exn)]
                [(wasm-exception? exn) (raise exn)]
                [(condition? exn)
                 (raise (make-wasm-trap
                   (string-append "type error at opcode 0x"
                     (number->string op 16) ": "
                     (call-with-string-output-port
                       (lambda (p) (display-condition exn p))))))])
              (cond
                ;; ---- end ----
                [(= op #x0B) (void)] ; return from this block level

                ;; ---- nop ----
                [(= op #x01) (step)]

                ;; ---- unreachable ----
                [(= op #x00) (raise (make-wasm-trap "unreachable executed"))]

                ;; ---- block ----
                [(= op #x02)
                 (let ([bt (bytevector-u8-ref code-bv pos)])
                   (set! pos (+ pos 1))
                   (execute-block bt 'block)
                   (step))]

                ;; ---- loop ----
                [(= op #x03)
                 (let ([bt (bytevector-u8-ref code-bv pos)])
                   (set! pos (+ pos 1))
                   (execute-block bt 'loop)
                   (step))]

                ;; ---- if ----
                [(= op #x04)
                 (let ([bt (bytevector-u8-ref code-bv pos)])
                   (set! pos (+ pos 1))
                   (let ([cond-val (pop!)])
                     (if (not (= cond-val 0))
                       ;; True branch
                       (begin
                         (execute-block bt 'block)
                         (step))
                       ;; False: skip to else or end
                       (let* ([r (skip-to-else-or-end code-bv pos len)]
                              [kind (car r)]
                              [new-pos (cdr r)])
                         (set! pos new-pos)
                         (if (eq? kind 'else)
                           (begin
                             (execute-block bt 'block)
                             (step))
                           ;; end with no else
                           (begin
                             (when (not (= bt #x40))
                               (push! 0))
                             (step)))))))]

                ;; ---- else (reached from true branch) ----
                [(= op #x05)
                 (set! pos (skip-to-end code-bv pos len))]

                ;; ---- br ----
                [(= op #x0C)
                 (let* ([r (decode-u32-leb128 code-bv pos)]
                        [depth (car r)])
                   (set! pos (+ pos (cdr r)))
                   (let ([val (if (null? stack) #f (pop!))])
                     (raise (make-wasm-branch depth val))))]

                ;; ---- br_if ----
                [(= op #x0D)
                 (let* ([r (decode-u32-leb128 code-bv pos)]
                        [depth (car r)])
                   (set! pos (+ pos (cdr r)))
                   (let ([c (pop!)])
                     (if (not (= c 0))
                       (let ([val (if (null? stack) #f (pop!))])
                         (raise (make-wasm-branch depth val)))
                       (step))))]

                ;; ---- br_table ----
                [(= op #x0E)
                 (let* ([cr (decode-u32-leb128 code-bv pos)]
                        [count (car cr)]
                        [tbl-start (+ pos (cdr cr))])
                   ;; Read all labels
                   (let loop ([n 0] [p tbl-start] [labels '()])
                     (if (> n count)
                       (let* ([all-labels (reverse labels)]
                              [default-label (car (last-pair all-labels))]
                              [table-labels (reverse (cdr (reverse all-labels)))]
                              [idx (pop!)]
                              [target (if (< idx (length table-labels))
                                        (list-ref table-labels idx)
                                        default-label)])
                         (set! pos p)
                         (let ([val (if (null? stack) #f (pop!))])
                           (raise (make-wasm-branch target val))))
                       (let* ([r (decode-u32-leb128 code-bv p)])
                         (loop (+ n 1) (+ p (cdr r))
                               (cons (car r) labels))))))]

                ;; ---- return ----
                [(= op #x0F)
                 (void)] ; just stop executing; result is on stack

                ;; ---- call ----
                [(= op #x10)
                 (let* ([r (decode-u32-leb128 code-bv pos)])
                   (set! pos (+ pos (cdr r)))
                   (let ([fidx (car r)])
                     (if (< fidx (vector-length imports))
                       ;; Import call: pop args, validate, call proc, push result
                       (let* ([imp-entry (vector-ref imports fidx)]
                              [param-count (car imp-entry)]
                              [args (let lp ([n param-count] [a '()])
                                      (if (= n 0) a (lp (- n 1) (cons (pop!) a))))])
                         (safe-import-call! imp-entry args))
                       ;; Local function call
                       (let* ([local-fidx (- fidx (vector-length imports))]
                              [fi (vector-ref all-funcs local-fidx)]
                              [param-count (car fi)]
                              [code (cadr fi)]
                              [local-count (caddr fi)]
                              [args (let lp ([n param-count] [a '()])
                                      (if (= n 0) a (lp (- n 1) (cons (pop!) a))))]
                              [new-lv (make-vector (+ param-count local-count) 0)])
                         (let lp ([i 0] [args args])
                           (unless (null? args)
                             (vector-set! new-lv i (car args))
                             (lp (+ i 1) (cdr args))))
                         (push! (execute-func code new-lv all-funcs memory-box globals tables imports limits (+ depth 1) types data-segs elem-segs tags)))))
                   (step))]

                ;; ---- call_indirect ----
                [(= op #x11)
                 (let* ([r1 (decode-u32-leb128 code-bv pos)]
                        [type-idx (car r1)]
                        [r2 (decode-u32-leb128 code-bv (+ pos (cdr r1)))]
                        [table-idx (car r2)])
                   (set! pos (+ pos (cdr r1) (cdr r2)))
                   ;; Validate table index
                   (when (>= table-idx (vector-length tables))
                     (raise (make-wasm-trap
                       (string-append "call_indirect: table index out of bounds: "
                                      (number->string table-idx)))))
                   (let* ([elem-idx (pop!)]
                          [table (vector-ref tables table-idx)])
                     ;; Validate element index against table size
                     (when (or (< elem-idx 0) (>= elem-idx (vector-length table)))
                       (raise (make-wasm-trap
                         (string-append "call_indirect: element index out of bounds: "
                                        (number->string elem-idx)
                                        " (table size " (number->string (vector-length table)) ")"))))
                     (let ([fidx (vector-ref table elem-idx)])
                       (when (not fidx)
                         (raise (make-wasm-trap
                           (string-append "call_indirect: null table entry " (number->string elem-idx)))))
                       ;; Validate function index
                       (let ([total-funcs (+ (vector-length imports) (vector-length all-funcs))])
                         (when (or (< fidx 0) (>= fidx total-funcs))
                           (raise (make-wasm-trap
                             (string-append "call_indirect: function index out of bounds: "
                                            (number->string fidx))))))
                       ;; Check callee type signature against expected type
                       (let ([callee-type-idx
                              (if (< fidx (vector-length imports))
                                (cadddr (vector-ref imports fidx))
                                (let ([local-fidx (- fidx (vector-length imports))])
                                  (cadddr (vector-ref all-funcs local-fidx))))])
                         (unless (= callee-type-idx type-idx)
                           (raise (make-wasm-trap
                             (string-append "call_indirect: type mismatch, expected type "
                                            (number->string type-idx)
                                            " but callee has type "
                                            (number->string callee-type-idx))))))
                       ;; Dispatch: import or local function
                       (if (< fidx (vector-length imports))
                         ;; Import call via call_indirect
                         (let* ([imp-entry (vector-ref imports fidx)]
                                [param-count (car imp-entry)]
                                [args (let lp ([n param-count] [a '()])
                                        (if (= n 0) a (lp (- n 1) (cons (pop!) a))))])
                           (safe-import-call! imp-entry args))
                         ;; Local function call
                         (let* ([local-fidx (- fidx (vector-length imports))]
                                [fi (vector-ref all-funcs local-fidx)]
                                [param-count (car fi)]
                                [code (cadr fi)]
                                [local-count (caddr fi)]
                                [args (let lp ([n param-count] [a '()])
                                        (if (= n 0) a (lp (- n 1) (cons (pop!) a))))]
                                [new-lv (make-vector (+ param-count local-count) 0)])
                           (let lp ([i 0] [args args])
                             (unless (null? args)
                               (vector-set! new-lv i (car args))
                               (lp (+ i 1) (cdr args))))
                           (push! (execute-func code new-lv all-funcs memory-box globals tables imports limits (+ depth 1) types data-segs elem-segs tags)))))))
                 (step)]

                ;; ---- drop ----
                [(= op #x1A) (pop!) (step)]

                ;; ---- select ----
                [(= op #x1B)
                 (let* ([c (pop!)] [v2 (pop!)] [v1 (pop!)])
                   (push! (if (not (= c 0)) v1 v2))
                   (step))]

                ;; ---- local.get ----
                [(= op #x20)
                 (let* ([r (decode-u32-leb128 code-bv pos)])
                   (set! pos (+ pos (cdr r)))
                   (push! (vector-ref locals-vec (car r)))
                   (step))]

                ;; ---- local.set ----
                [(= op #x21)
                 (let* ([r (decode-u32-leb128 code-bv pos)])
                   (set! pos (+ pos (cdr r)))
                   (vector-set! locals-vec (car r) (pop!))
                   (step))]

                ;; ---- local.tee ----
                [(= op #x22)
                 (let* ([r (decode-u32-leb128 code-bv pos)])
                   (set! pos (+ pos (cdr r)))
                   (vector-set! locals-vec (car r) (peek))
                   (step))]

                ;; ---- global.get ----
                [(= op #x23)
                 (let* ([r (decode-u32-leb128 code-bv pos)])
                   (set! pos (+ pos (cdr r)))
                   (push! (vector-ref globals (car r)))
                   (step))]

                ;; ---- global.set ----
                [(= op #x24)
                 (let* ([r (decode-u32-leb128 code-bv pos)])
                   (set! pos (+ pos (cdr r)))
                   (vector-set! globals (car r) (pop!))
                   (step))]

                ;; ---- Memory loads ----
                [(= op #x28) (let ([addr (read-memarg)]) (push! (mem-load-i32 memory addr)) (step))]
                [(= op #x29) (let ([addr (read-memarg)]) (push! (mem-load-i64 memory addr)) (step))]
                [(= op #x2A) (let ([addr (read-memarg)]) (push! (mem-load-f32 memory addr)) (step))]
                [(= op #x2B) (let ([addr (read-memarg)]) (push! (mem-load-f64 memory addr)) (step))]
                [(= op #x2C) (let ([addr (read-memarg)]) (push! (mem-load-i8-s memory addr)) (step))]
                [(= op #x2D) (let ([addr (read-memarg)]) (push! (mem-load-i8-u memory addr)) (step))]
                [(= op #x2E) (let ([addr (read-memarg)]) (push! (mem-load-i16-s memory addr)) (step))]
                [(= op #x2F) (let ([addr (read-memarg)]) (push! (mem-load-i16-u memory addr)) (step))]
                ;; i64 sub-word loads
                [(= op #x30) (let ([addr (read-memarg)]) (push! (mem-load-i8-s memory addr)) (step))]
                [(= op #x31) (let ([addr (read-memarg)]) (push! (mem-load-i8-u memory addr)) (step))]
                [(= op #x32) (let ([addr (read-memarg)]) (push! (mem-load-i16-s memory addr)) (step))]
                [(= op #x33) (let ([addr (read-memarg)]) (push! (mem-load-i16-u memory addr)) (step))]
                [(= op #x34) ; i64.load32_s
                 (let ([addr (read-memarg)])
                   (push! (let ([v (mem-load-i32 memory addr)])
                            (if (>= v 0) v (+ v #x100000000))))
                   (step))]
                [(= op #x35) ; i64.load32_u
                 (let ([addr (read-memarg)]) (push! (u32 (mem-load-i32 memory addr))) (step))]

                ;; ---- Memory stores ----
                [(= op #x36) (let ([addr (read-memarg)] [val (pop!)]) (mem-store-i32 memory addr val) (step))]
                [(= op #x37) (let ([addr (read-memarg)] [val (pop!)]) (mem-store-i64 memory addr val) (step))]
                [(= op #x38) (let ([addr (read-memarg)] [val (pop!)]) (mem-store-f32 memory addr val) (step))]
                [(= op #x39) (let ([addr (read-memarg)] [val (pop!)]) (mem-store-f64 memory addr val) (step))]
                [(= op #x3A) (let ([addr (read-memarg)] [val (pop!)]) (mem-store-i8 memory addr val) (step))]
                [(= op #x3B) (let ([addr (read-memarg)] [val (pop!)]) (mem-store-i16 memory addr val) (step))]
                [(= op #x3C) (let ([addr (read-memarg)] [val (pop!)]) (mem-store-i8 memory addr val) (step))]
                [(= op #x3D) (let ([addr (read-memarg)] [val (pop!)]) (mem-store-i16 memory addr val) (step))]
                [(= op #x3E) ; i64.store32
                 (let ([addr (read-memarg)] [val (pop!)]) (mem-store-i32 memory addr (i32 val)) (step))]

                ;; ---- memory.size ----
                [(= op #x3F)
                 (set! pos (+ pos 1)) ; skip reserved byte
                 (push! (quotient (bytevector-length memory) 65536))
                 (step)]

                ;; ---- memory.grow ----
                [(= op #x40)
                 (set! pos (+ pos 1))
                 (let* ([pages (pop!)]
                        [max-pages (vector-ref limits 3)]
                        [old-pages (quotient (bytevector-length memory) 65536)]
                        [new-pages (+ old-pages pages)]
                        [new-size (* new-pages 65536)])
                   (if (or (< pages 0) (> new-pages max-pages))
                     (begin (push! -1) (step))
                     (let ([new-mem (make-bytevector new-size 0)])
                       (bytevector-copy! memory 0 new-mem 0 (bytevector-length memory))
                       ;; Update the mutable local and the shared box
                       (set! memory new-mem)
                       (vector-set! memory-box 0 new-mem)
                       (push! old-pages)
                       (step))))]

                ;; ---- i32.const ----
                [(= op #x41)
                 (let* ([r (decode-i32-leb128 code-bv pos)])
                   (set! pos (+ pos (cdr r)))
                   (push! (i32 (car r)))
                   (step))]

                ;; ---- i64.const ----
                [(= op #x42)
                 (let* ([r (decode-i64-leb128 code-bv pos)])
                   (set! pos (+ pos (cdr r)))
                   (push! (i64 (car r)))
                   (step))]

                ;; ---- f32.const ----
                [(= op #x43)
                 (push! (decode-f32 code-bv pos))
                 (set! pos (+ pos 4))
                 (step)]

                ;; ---- f64.const ----
                [(= op #x44)
                 (push! (decode-f64 code-bv pos))
                 (set! pos (+ pos 8))
                 (step)]

                ;; ---- i32 comparisons ----
                [(= op #x45) (push! (i32-bool (= (pop!) 0))) (step)]               ; eqz
                [(= op #x46) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (= a b))) (step))]     ; eq
                [(= op #x47) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (not (= a b)))) (step))]; ne
                [(= op #x48) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (< a b))) (step))]     ; lt_s
                [(= op #x49) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (i32-lt-u a b))) (step))]; lt_u
                [(= op #x4A) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (> a b))) (step))]     ; gt_s
                [(= op #x4B) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (i32-gt-u a b))) (step))]; gt_u
                [(= op #x4C) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (<= a b))) (step))]    ; le_s
                [(= op #x4D) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (i32-le-u a b))) (step))]; le_u
                [(= op #x4E) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (>= a b))) (step))]    ; ge_s
                [(= op #x4F) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (i32-ge-u a b))) (step))]; ge_u

                ;; ---- i32 arithmetic ----
                [(= op #x67) (push! (clz32 (pop!))) (step)]      ; clz
                [(= op #x68) (push! (ctz32 (pop!))) (step)]      ; ctz
                [(= op #x69) (push! (popcnt32 (pop!))) (step)]   ; popcnt
                [(= op #x6A) (let* ([b (pop!)] [a (pop!)]) (push! (i32 (+ a b))) (step))]   ; add
                [(= op #x6B) (let* ([b (pop!)] [a (pop!)]) (push! (i32 (- a b))) (step))]   ; sub
                [(= op #x6C) (let* ([b (pop!)] [a (pop!)]) (push! (i32 (* a b))) (step))]   ; mul
                [(= op #x6D) ; div_s
                 (let* ([b (pop!)] [a (pop!)])
                   (when (= b 0) (raise (make-wasm-trap "integer divide by zero")))
                   (push! (i32 (truncate (/ a b))))
                   (step))]
                [(= op #x6E) ; div_u
                 (let* ([b (pop!)] [a (pop!)])
                   (push! (i32-div-u a b))
                   (step))]
                [(= op #x6F) ; rem_s
                 (let* ([b (pop!)] [a (pop!)])
                   (when (= b 0) (raise (make-wasm-trap "integer remainder by zero")))
                   (push! (i32 (remainder a b)))
                   (step))]
                [(= op #x70) ; rem_u
                 (let* ([b (pop!)] [a (pop!)])
                   (push! (i32-rem-u a b))
                   (step))]
                [(= op #x71) (let* ([b (pop!)] [a (pop!)]) (push! (i32 (bitwise-and a b))) (step))] ; and
                [(= op #x72) (let* ([b (pop!)] [a (pop!)]) (push! (i32 (bitwise-ior a b))) (step))] ; or
                [(= op #x73) (let* ([b (pop!)] [a (pop!)]) (push! (i32 (bitwise-xor a b))) (step))] ; xor
                [(= op #x74) (let* ([b (pop!)] [a (pop!)]) (push! (i32 (bitwise-arithmetic-shift-left (u32 a) (bitwise-and b 31)))) (step))]  ; shl
                [(= op #x75) ; shr_s
                 (let* ([b (pop!)] [a (pop!)])
                   (push! (i32 (bitwise-arithmetic-shift-right a (bitwise-and b 31))))
                   (step))]
                [(= op #x76) ; shr_u
                 (let* ([b (pop!)] [a (pop!)])
                   (push! (i32 (bitwise-arithmetic-shift-right (u32 a) (bitwise-and b 31))))
                   (step))]
                [(= op #x77) (let* ([b (pop!)] [a (pop!)]) (push! (rotl32 a b)) (step))]  ; rotl
                [(= op #x78) (let* ([b (pop!)] [a (pop!)]) (push! (rotr32 a b)) (step))]  ; rotr

                ;; ---- i64 comparisons ----
                [(= op #x50) (push! (i32-bool (= (pop!) 0))) (step)]               ; eqz
                [(= op #x51) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (= a b))) (step))]
                [(= op #x52) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (not (= a b)))) (step))]
                [(= op #x53) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (< a b))) (step))]
                [(= op #x54) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (< (u64 a) (u64 b)))) (step))]
                [(= op #x55) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (> a b))) (step))]
                [(= op #x56) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (> (u64 a) (u64 b)))) (step))]
                [(= op #x57) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (<= a b))) (step))]
                [(= op #x58) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (<= (u64 a) (u64 b)))) (step))]
                [(= op #x59) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (>= a b))) (step))]
                [(= op #x5A) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (>= (u64 a) (u64 b)))) (step))]

                ;; ---- i64 arithmetic ----
                [(= op #x79) (push! (clz64 (pop!))) (step)]
                [(= op #x7A) (push! (ctz64 (pop!))) (step)]
                [(= op #x7B) (push! (popcnt64 (pop!))) (step)]
                [(= op #x7C) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (+ a b))) (step))]
                [(= op #x7D) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (- a b))) (step))]
                [(= op #x7E) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (* a b))) (step))]
                [(= op #x7F) (let* ([b (pop!)] [a (pop!)])
                   (when (= b 0) (raise (make-wasm-trap "integer divide by zero")))
                   (push! (i64 (truncate (/ a b)))) (step))]
                [(= op #x80) (let* ([b (pop!)] [a (pop!)])
                   (when (= b 0) (raise (make-wasm-trap "integer divide by zero")))
                   (push! (i64 (quotient (u64 a) (u64 b)))) (step))]
                [(= op #x81) (let* ([b (pop!)] [a (pop!)])
                   (when (= b 0) (raise (make-wasm-trap "integer remainder by zero")))
                   (push! (i64 (remainder a b))) (step))]
                [(= op #x82) (let* ([b (pop!)] [a (pop!)])
                   (when (= b 0) (raise (make-wasm-trap "integer remainder by zero")))
                   (push! (i64 (remainder (u64 a) (u64 b)))) (step))]
                [(= op #x83) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (bitwise-and a b))) (step))]
                [(= op #x84) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (bitwise-ior a b))) (step))]
                [(= op #x85) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (bitwise-xor a b))) (step))]
                [(= op #x86) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (bitwise-arithmetic-shift-left a (bitwise-and b 63)))) (step))]
                [(= op #x87) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (bitwise-arithmetic-shift-right a (bitwise-and b 63)))) (step))]
                [(= op #x88) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (bitwise-arithmetic-shift-right (u64 a) (bitwise-and b 63)))) (step))]
                [(= op #x89) (let* ([b (pop!)] [a (pop!)]) (push! (rotl64 a b)) (step))]
                [(= op #x8A) (let* ([b (pop!)] [a (pop!)]) (push! (rotr64 a b)) (step))]

                ;; ---- f32 arithmetic ----
                [(= op #x8B) (push! (flabs (pop!))) (step)]         ; abs
                [(= op #x8C) (push! (fl- (pop!))) (step)]           ; neg
                [(= op #x8D) (push! (flceiling (pop!))) (step)]     ; ceil
                [(= op #x8E) (push! (flfloor (pop!))) (step)]       ; floor
                [(= op #x8F) (push! (fltruncate (pop!))) (step)]    ; trunc
                [(= op #x90) (push! (f-nearest (pop!))) (step)]     ; nearest
                [(= op #x91) (push! (flsqrt (pop!))) (step)]        ; sqrt
                [(= op #x92) (let* ([b (pop!)] [a (pop!)]) (push! (fl+ a b)) (step))]  ; add
                [(= op #x93) (let* ([b (pop!)] [a (pop!)]) (push! (fl- a b)) (step))]  ; sub
                [(= op #x94) (let* ([b (pop!)] [a (pop!)]) (push! (fl* a b)) (step))]  ; mul
                [(= op #x95) (let* ([b (pop!)] [a (pop!)]) (push! (fl/ a b)) (step))]  ; div
                [(= op #x96) (let* ([b (pop!)] [a (pop!)]) (push! (f32-min a b)) (step))]  ; min
                [(= op #x97) (let* ([b (pop!)] [a (pop!)]) (push! (f32-max a b)) (step))]  ; max
                [(= op #x98) (let* ([b (pop!)] [a (pop!)]) (push! (f-copysign a b)) (step))]; copysign

                ;; ---- f64 arithmetic ----
                [(= op #x99) (push! (flabs (pop!))) (step)]
                [(= op #x9A) (push! (fl- (pop!))) (step)]
                [(= op #x9B) (push! (flceiling (pop!))) (step)]
                [(= op #x9C) (push! (flfloor (pop!))) (step)]
                [(= op #x9D) (push! (fltruncate (pop!))) (step)]
                [(= op #x9E) (push! (f-nearest (pop!))) (step)]
                [(= op #x9F) (push! (flsqrt (pop!))) (step)]
                [(= op #xA0) (let* ([b (pop!)] [a (pop!)]) (push! (fl+ a b)) (step))]
                [(= op #xA1) (let* ([b (pop!)] [a (pop!)]) (push! (fl- a b)) (step))]
                [(= op #xA2) (let* ([b (pop!)] [a (pop!)]) (push! (fl* a b)) (step))]
                [(= op #xA3) (let* ([b (pop!)] [a (pop!)]) (push! (fl/ a b)) (step))]
                [(= op #xA4) (let* ([b (pop!)] [a (pop!)]) (push! (f64-min a b)) (step))]
                [(= op #xA5) (let* ([b (pop!)] [a (pop!)]) (push! (f64-max a b)) (step))]
                [(= op #xA6) (let* ([b (pop!)] [a (pop!)]) (push! (f-copysign a b)) (step))]

                ;; ---- f32 comparisons ----
                [(= op #x5B) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (fl= a b))) (step))]
                [(= op #x5C) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (not (fl= a b)))) (step))]
                [(= op #x5D) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (fl< a b))) (step))]
                [(= op #x5E) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (fl> a b))) (step))]
                [(= op #x5F) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (fl<= a b))) (step))]
                [(= op #x60) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (fl>= a b))) (step))]

                ;; ---- f64 comparisons ----
                [(= op #x61) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (fl= a b))) (step))]
                [(= op #x62) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (not (fl= a b)))) (step))]
                [(= op #x63) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (fl< a b))) (step))]
                [(= op #x64) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (fl> a b))) (step))]
                [(= op #x65) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (fl<= a b))) (step))]
                [(= op #x66) (let* ([b (pop!)] [a (pop!)]) (push! (i32-bool (fl>= a b))) (step))]

                ;; ---- Conversions ----
                [(= op #xA7) (push! (i32 (pop!))) (step)]                        ; i32.wrap_i64
                [(= op #xA8) (push! (i32 (exact (fltruncate (pop!))))) (step)]   ; i32.trunc_f32_s
                [(= op #xA9) (push! (u32 (exact (fltruncate (pop!))))) (step)]   ; i32.trunc_f32_u
                [(= op #xAA) (push! (i32 (exact (fltruncate (pop!))))) (step)]   ; i32.trunc_f64_s
                [(= op #xAB) (push! (u32 (exact (fltruncate (pop!))))) (step)]   ; i32.trunc_f64_u
                [(= op #xAC) (push! (i64 (pop!))) (step)]                        ; i64.extend_i32_s
                [(= op #xAD) (push! (u64 (u32 (pop!)))) (step)]                  ; i64.extend_i32_u
                [(= op #xAE) (push! (i64 (exact (fltruncate (pop!))))) (step)]   ; i64.trunc_f32_s
                [(= op #xAF) (push! (u64 (exact (fltruncate (pop!))))) (step)]   ; i64.trunc_f32_u
                [(= op #xB0) (push! (i64 (exact (fltruncate (pop!))))) (step)]   ; i64.trunc_f64_s
                [(= op #xB1) (push! (u64 (exact (fltruncate (pop!))))) (step)]   ; i64.trunc_f64_u
                [(= op #xB2) (push! (exact->inexact (pop!))) (step)]             ; f32.convert_i32_s
                [(= op #xB3) (push! (exact->inexact (u32 (pop!)))) (step)]       ; f32.convert_i32_u
                [(= op #xB4) (push! (exact->inexact (pop!))) (step)]             ; f32.convert_i64_s
                [(= op #xB5) (push! (exact->inexact (u64 (pop!)))) (step)]       ; f32.convert_i64_u
                [(= op #xB6) (push! (pop!)) (step)]                              ; f32.demote_f64
                [(= op #xB7) (push! (exact->inexact (pop!))) (step)]             ; f64.convert_i32_s
                [(= op #xB8) (push! (exact->inexact (u32 (pop!)))) (step)]       ; f64.convert_i32_u
                [(= op #xB9) (push! (exact->inexact (pop!))) (step)]             ; f64.convert_i64_s
                [(= op #xBA) (push! (exact->inexact (u64 (pop!)))) (step)]       ; f64.convert_i64_u
                [(= op #xBB) (push! (pop!)) (step)]                              ; f64.promote_f32

                ;; ---- Reinterpret ----
                [(= op #xBC) ; i32.reinterpret_f32
                 (let* ([bv (make-bytevector 4)] [v (pop!)])
                   (bytevector-ieee-single-set! bv 0 v 'little)
                   (push! (mem-load-i32 bv 0))
                   (step))]
                [(= op #xBD) ; i64.reinterpret_f64
                 (let* ([bv (make-bytevector 8)] [v (pop!)])
                   (bytevector-ieee-double-set! bv 0 v 'little)
                   (push! (mem-load-i64 bv 0))
                   (step))]
                [(= op #xBE) ; f32.reinterpret_i32
                 (let* ([bv (make-bytevector 4)])
                   (mem-store-i32 bv 0 (pop!))
                   (push! (bytevector-ieee-single-ref bv 0 'little))
                   (step))]
                [(= op #xBF) ; f64.reinterpret_i64
                 (let* ([bv (make-bytevector 8)])
                   (mem-store-i64 bv 0 (pop!))
                   (push! (bytevector-ieee-double-ref bv 0 'little))
                   (step))]

                ;; ---- Sign extension ----
                [(= op #xC0) ; i32.extend8_s
                 (let ([v (bitwise-and (pop!) #xFF)])
                   (push! (if (>= v 128) (- v 256) v)) (step))]
                [(= op #xC1) ; i32.extend16_s
                 (let ([v (bitwise-and (pop!) #xFFFF)])
                   (push! (if (>= v 32768) (- v 65536) v)) (step))]
                [(= op #xC2) ; i64.extend8_s
                 (let ([v (bitwise-and (pop!) #xFF)])
                   (push! (if (>= v 128) (- v 256) v)) (step))]
                [(= op #xC3) ; i64.extend16_s
                 (let ([v (bitwise-and (pop!) #xFFFF)])
                   (push! (if (>= v 32768) (- v 65536) v)) (step))]
                [(= op #xC4) ; i64.extend32_s
                 (let ([v (bitwise-and (pop!) #xFFFFFFFF)])
                   (push! (if (>= v #x80000000) (- v #x100000000) v)) (step))]

                ;; =============== POST-MVP OPCODES ===============

                ;; ---- return_call (tail call) ----
                [(= op #x12)
                 (let* ([r (decode-u32-leb128 code-bv pos)])
                   (set! pos (+ pos (cdr r)))
                   (let ([fidx (car r)])
                     (if (< fidx (vector-length imports))
                       ;; Tail call to import: just call normally (no trampoline needed)
                       (let* ([imp-entry (vector-ref imports fidx)]
                              [param-count (car imp-entry)]
                              [args (let lp ([n param-count] [a '()])
                                      (if (= n 0) a (lp (- n 1) (cons (pop!) a))))])
                         (safe-import-call! imp-entry args))
                       ;; Tail call to local: raise tail-call condition
                       (let* ([local-fidx (- fidx (vector-length imports))]
                              [fi (vector-ref all-funcs local-fidx)]
                              [param-count (car fi)]
                              [args (let lp ([n param-count] [a '()])
                                      (if (= n 0) a (lp (- n 1) (cons (pop!) a))))])
                         (raise (make-wasm-tail-call fidx args))))))]

                ;; ---- return_call_indirect (tail call) ----
                [(= op #x13)
                 (let* ([r1 (decode-u32-leb128 code-bv pos)]
                        [type-idx (car r1)]
                        [r2 (decode-u32-leb128 code-bv (+ pos (cdr r1)))]
                        [table-idx (car r2)])
                   (set! pos (+ pos (cdr r1) (cdr r2)))
                   (when (>= table-idx (vector-length tables))
                     (raise (make-wasm-trap "return_call_indirect: table index OOB")))
                   (let* ([elem-idx (pop!)]
                          [table (vector-ref tables table-idx)])
                     (when (or (< elem-idx 0) (>= elem-idx (vector-length table)))
                       (raise (make-wasm-trap "return_call_indirect: element index OOB")))
                     (let ([fidx (vector-ref table elem-idx)])
                       (when (not fidx)
                         (raise (make-wasm-trap "return_call_indirect: null table entry")))
                       (let* ([local-fidx (- fidx (vector-length imports))]
                              [fi (vector-ref all-funcs local-fidx)]
                              [param-count (car fi)]
                              [args (let lp ([n param-count] [a '()])
                                      (if (= n 0) a (lp (- n 1) (cons (pop!) a))))])
                         (raise (make-wasm-tail-call fidx args))))))]

                ;; ---- try (exception handling) ----
                [(= op #x06)
                 (let ([bt (bytevector-u8-ref code-bv pos)])
                   (set! pos (+ pos 1))
                   ;; Execute try body; on wasm-exception, scan for catch/catch_all
                   (guard (exn
                     [(wasm-exception? exn)
                      (let ([tag (wasm-exception-tag-idx exn)]
                            [vals (wasm-exception-values exn)])
                        ;; Skip to matching catch or catch_all
                        (let scan ([p pos] [d 0])
                          (if (>= p len)
                            (raise exn)  ; no handler found, propagate
                            (let ([o (bytevector-u8-ref code-bv p)])
                              (cond
                                [(and (= o #x07) (= d 0))  ; catch
                                 (let* ([r (decode-u32-leb128 code-bv (+ p 1))]
                                        [catch-tag (car r)])
                                   (if (= catch-tag tag)
                                     (begin
                                       (set! pos (+ p 1 (cdr r)))
                                       (for-each (lambda (v) (push! v)) (reverse vals))
                                       (execute-block bt 'block))
                                     (scan (+ p 1 (cdr r)) d)))]
                                [(and (= o #x19) (= d 0))  ; catch_all
                                 (set! pos (+ p 1))
                                 (execute-block bt 'block)]
                                [(or (= o #x02) (= o #x03) (= o #x04) (= o #x06))
                                 (scan (skip-instr code-bv p len) (+ d 1))]
                                [(= o #x0B)
                                 (if (= d 0)
                                   (raise exn)  ; end of try without matching catch
                                   (scan (+ p 1) (- d 1)))]
                                [else (scan (skip-instr code-bv p len) d)])))))])
                     (execute-block bt 'block))
                   (step))]

                ;; ---- throw ----
                [(= op #x08)
                 (let* ([r (decode-u32-leb128 code-bv pos)]
                        [tag-idx (car r)])
                   (set! pos (+ pos (cdr r)))
                   (when (>= tag-idx (vector-length tags))
                     (raise (make-wasm-trap
                       (string-append "throw: tag index OOB: " (number->string tag-idx)))))
                   (let* ([tag (vector-ref tags tag-idx)]
                          [tidx (wasm-tag-type-idx tag)]
                          [type (list-ref types tidx)]
                          [param-count (length (car type))]
                          [vals (let lp ([n param-count] [a '()])
                                  (if (= n 0) a (lp (- n 1) (cons (pop!) a))))])
                     (raise (make-wasm-exception tag-idx vals))))]

                ;; ---- rethrow ----
                [(= op #x09)
                 (let* ([r (decode-u32-leb128 code-bv pos)])
                   (set! pos (+ pos (cdr r)))
                   ;; Rethrow is only valid inside catch; for now trap
                   (raise (make-wasm-trap "rethrow: not inside catch handler")))]

                ;; ---- select_t (typed select) ----
                [(= op #x1C)
                 (let* ([r (decode-u32-leb128 code-bv pos)]
                        [count (car r)]
                        [skip (+ (cdr r) count)])
                   (set! pos (+ pos skip))
                   ;; Same semantics as select, just with type annotation
                   (let* ([c (pop!)] [v2 (pop!)] [v1 (pop!)])
                     (push! (if (not (= c 0)) v1 v2))
                     (step)))]

                ;; ---- table.get ----
                [(= op #x25)
                 (let* ([r (decode-u32-leb128 code-bv pos)]
                        [tidx (car r)])
                   (set! pos (+ pos (cdr r)))
                   (when (>= tidx (vector-length tables))
                     (raise (make-wasm-trap "table.get: table index OOB")))
                   (let* ([idx (pop!)]
                          [table (vector-ref tables tidx)])
                     (when (or (< idx 0) (>= idx (vector-length table)))
                       (raise (make-wasm-trap "table.get: element index OOB")))
                     (let ([val (vector-ref table idx)])
                       (push! (or val 0)))
                     (step)))]

                ;; ---- table.set ----
                [(= op #x26)
                 (let* ([r (decode-u32-leb128 code-bv pos)]
                        [tidx (car r)])
                   (set! pos (+ pos (cdr r)))
                   (when (>= tidx (vector-length tables))
                     (raise (make-wasm-trap "table.set: table index OOB")))
                   (let* ([val (pop!)]
                          [idx (pop!)]
                          [table (vector-ref tables tidx)])
                     (when (or (< idx 0) (>= idx (vector-length table)))
                       (raise (make-wasm-trap "table.set: element index OOB")))
                     (vector-set! table idx val)
                     (step)))]

                ;; ---- ref.null ----
                [(= op #xD0)
                 (let* ([r (decode-u32-leb128 code-bv pos)])
                   (set! pos (+ pos (cdr r)))
                   (push! #f)  ; null reference
                   (step))]

                ;; ---- ref.is_null ----
                [(= op #xD1)
                 (let ([v (pop!)])
                   (push! (if (eq? v #f) 1 0))
                   (step))]

                ;; ---- ref.func ----
                [(= op #xD2)
                 (let* ([r (decode-u32-leb128 code-bv pos)]
                        [fidx (car r)])
                   (set! pos (+ pos (cdr r)))
                   (push! fidx)  ; push function reference as index
                   (step))]

                ;; ---- 0xFC prefix (saturating conversions + bulk memory + table ops) ----
                [(= op #xFC)
                 (let* ([r (decode-u32-leb128 code-bv pos)]
                        [sub (car r)])
                   (set! pos (+ pos (cdr r)))
                   (cond
                     ;; Saturating float-to-int conversions
                     [(= sub 0) ; i32.trunc_sat_f32_s
                      (let ([v (pop!)])
                        (push! (cond [(nan? v) 0]
                                     [(>= v 2147483647.0) 2147483647]
                                     [(<= v -2147483648.0) -2147483648]
                                     [else (i32 (exact (fltruncate v)))]))
                        (step))]
                     [(= sub 1) ; i32.trunc_sat_f32_u
                      (let ([v (pop!)])
                        (push! (cond [(or (nan? v) (fl< v 0.0)) 0]
                                     [(>= v 4294967295.0) 4294967295]
                                     [else (u32 (exact (fltruncate v)))]))
                        (step))]
                     [(= sub 2) ; i32.trunc_sat_f64_s
                      (let ([v (pop!)])
                        (push! (cond [(nan? v) 0]
                                     [(>= v 2147483647.0) 2147483647]
                                     [(<= v -2147483648.0) -2147483648]
                                     [else (i32 (exact (fltruncate v)))]))
                        (step))]
                     [(= sub 3) ; i32.trunc_sat_f64_u
                      (let ([v (pop!)])
                        (push! (cond [(or (nan? v) (fl< v 0.0)) 0]
                                     [(>= v 4294967295.0) 4294967295]
                                     [else (u32 (exact (fltruncate v)))]))
                        (step))]
                     [(= sub 4) ; i64.trunc_sat_f32_s
                      (let ([v (pop!)])
                        (push! (cond [(nan? v) 0]
                                     [(>= v 9223372036854775807.0) 9223372036854775807]
                                     [(<= v -9223372036854775808.0) -9223372036854775808]
                                     [else (i64 (exact (fltruncate v)))]))
                        (step))]
                     [(= sub 5) ; i64.trunc_sat_f32_u
                      (let ([v (pop!)])
                        (push! (cond [(or (nan? v) (fl< v 0.0)) 0]
                                     [(>= v 18446744073709551615.0) 18446744073709551615]
                                     [else (u64 (exact (fltruncate v)))]))
                        (step))]
                     [(= sub 6) ; i64.trunc_sat_f64_s
                      (let ([v (pop!)])
                        (push! (cond [(nan? v) 0]
                                     [(>= v 9223372036854775807.0) 9223372036854775807]
                                     [(<= v -9223372036854775808.0) -9223372036854775808]
                                     [else (i64 (exact (fltruncate v)))]))
                        (step))]
                     [(= sub 7) ; i64.trunc_sat_f64_u
                      (let ([v (pop!)])
                        (push! (cond [(or (nan? v) (fl< v 0.0)) 0]
                                     [(>= v 18446744073709551615.0) 18446744073709551615]
                                     [else (u64 (exact (fltruncate v)))]))
                        (step))]

                     ;; ---- Bulk memory operations ----
                     [(= sub 8) ; memory.init seg-idx 0x00
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [seg-idx (car r2)])
                        (set! pos (+ pos (cdr r2) 1)) ; +1 for reserved byte
                        (let* ([n (pop!)] [s (pop!)] [d (pop!)])
                          (when (>= seg-idx (vector-length data-segs))
                            (raise (make-wasm-trap "memory.init: segment index OOB")))
                          (let ([seg (vector-ref data-segs seg-idx)])
                            (when (not seg)
                              (raise (make-wasm-trap "memory.init: segment dropped")))
                            (when (> (+ s n) (bytevector-length seg))
                              (raise (make-wasm-trap "memory.init: segment bounds exceeded")))
                            (when (> (+ d n) (bytevector-length memory))
                              (raise (make-wasm-trap "memory.init: memory bounds exceeded")))
                            (bytevector-copy! seg s memory d n))
                          (step)))]
                     [(= sub 9) ; data.drop seg-idx
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [seg-idx (car r2)])
                        (set! pos (+ pos (cdr r2)))
                        (when (>= seg-idx (vector-length data-segs))
                          (raise (make-wasm-trap "data.drop: segment index OOB")))
                        (vector-set! data-segs seg-idx #f)
                        (step))]
                     [(= sub 10) ; memory.copy 0x00 0x00
                      (set! pos (+ pos 2)) ; skip 2 reserved bytes
                      (let* ([n (pop!)] [s (pop!)] [d (pop!)])
                        (when (> (+ s n) (bytevector-length memory))
                          (raise (make-wasm-trap "memory.copy: source OOB")))
                        (when (> (+ d n) (bytevector-length memory))
                          (raise (make-wasm-trap "memory.copy: dest OOB")))
                        ;; Use temporary buffer for overlapping copies
                        (let ([tmp (make-bytevector n)])
                          (bytevector-copy! memory s tmp 0 n)
                          (bytevector-copy! tmp 0 memory d n))
                        (step))]
                     [(= sub 11) ; memory.fill 0x00
                      (set! pos (+ pos 1)) ; skip reserved byte
                      (let* ([n (pop!)] [val (pop!)] [d (pop!)])
                        (when (> (+ d n) (bytevector-length memory))
                          (raise (make-wasm-trap "memory.fill: OOB")))
                        (let ([byte (bitwise-and val #xFF)])
                          (let lp ([i 0])
                            (when (< i n)
                              (bytevector-u8-set! memory (+ d i) byte)
                              (lp (+ i 1)))))
                        (step))]

                     ;; ---- Bulk table operations ----
                     [(= sub 12) ; table.init elem-idx table-idx
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [seg-idx (car r2)]
                             [r3 (decode-u32-leb128 code-bv (+ pos (cdr r2)))]
                             [tidx (car r3)])
                        (set! pos (+ pos (cdr r2) (cdr r3)))
                        (let* ([n (pop!)] [s (pop!)] [d (pop!)])
                          (when (>= tidx (vector-length tables))
                            (raise (make-wasm-trap "table.init: table index OOB")))
                          (when (>= seg-idx (vector-length elem-segs))
                            (raise (make-wasm-trap "table.init: segment index OOB")))
                          (let ([seg (vector-ref elem-segs seg-idx)]
                                [table (vector-ref tables tidx)])
                            (when (not seg)
                              (raise (make-wasm-trap "table.init: segment dropped")))
                            (when (> (+ s n) (vector-length seg))
                              (raise (make-wasm-trap "table.init: segment bounds exceeded")))
                            (when (> (+ d n) (vector-length table))
                              (raise (make-wasm-trap "table.init: table bounds exceeded")))
                            (let lp ([i 0])
                              (when (< i n)
                                (vector-set! table (+ d i) (vector-ref seg (+ s i)))
                                (lp (+ i 1)))))
                          (step)))]
                     [(= sub 13) ; elem.drop seg-idx
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [seg-idx (car r2)])
                        (set! pos (+ pos (cdr r2)))
                        (when (>= seg-idx (vector-length elem-segs))
                          (raise (make-wasm-trap "elem.drop: segment index OOB")))
                        (vector-set! elem-segs seg-idx #f)
                        (step))]
                     [(= sub 14) ; table.copy dst-table src-table
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [dst-tidx (car r2)]
                             [r3 (decode-u32-leb128 code-bv (+ pos (cdr r2)))]
                             [src-tidx (car r3)])
                        (set! pos (+ pos (cdr r2) (cdr r3)))
                        (let* ([n (pop!)] [s (pop!)] [d (pop!)])
                          (when (>= dst-tidx (vector-length tables))
                            (raise (make-wasm-trap "table.copy: dst table OOB")))
                          (when (>= src-tidx (vector-length tables))
                            (raise (make-wasm-trap "table.copy: src table OOB")))
                          (let ([dst (vector-ref tables dst-tidx)]
                                [src (vector-ref tables src-tidx)])
                            (when (> (+ s n) (vector-length src))
                              (raise (make-wasm-trap "table.copy: source bounds exceeded")))
                            (when (> (+ d n) (vector-length dst))
                              (raise (make-wasm-trap "table.copy: dest bounds exceeded")))
                            (let lp ([i 0])
                              (when (< i n)
                                (vector-set! dst (+ d i) (vector-ref src (+ s i)))
                                (lp (+ i 1)))))
                          (step)))]
                     [(= sub 15) ; table.grow table-idx
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [tidx (car r2)])
                        (set! pos (+ pos (cdr r2)))
                        (when (>= tidx (vector-length tables))
                          (raise (make-wasm-trap "table.grow: table index OOB")))
                        (let* ([n (pop!)] [init-val (pop!)]
                               [table (vector-ref tables tidx)]
                               [old-size (vector-length table)]
                               [new-size (+ old-size n)])
                          ;; Limit table growth (use same max-pages limit as a heuristic)
                          (if (> new-size 65536)
                            (begin (push! -1) (step))
                            (let ([new-table (make-vector new-size init-val)])
                              (let lp ([i 0])
                                (when (< i old-size)
                                  (vector-set! new-table i (vector-ref table i))
                                  (lp (+ i 1))))
                              (vector-set! tables tidx new-table)
                              (push! old-size)
                              (step)))))]
                     [(= sub 16) ; table.size table-idx
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [tidx (car r2)])
                        (set! pos (+ pos (cdr r2)))
                        (when (>= tidx (vector-length tables))
                          (raise (make-wasm-trap "table.size: table index OOB")))
                        (push! (vector-length (vector-ref tables tidx)))
                        (step))]
                     [(= sub 17) ; table.fill table-idx
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [tidx (car r2)])
                        (set! pos (+ pos (cdr r2)))
                        (when (>= tidx (vector-length tables))
                          (raise (make-wasm-trap "table.fill: table index OOB")))
                        (let* ([n (pop!)] [val (pop!)] [i-start (pop!)]
                               [table (vector-ref tables tidx)])
                          (when (> (+ i-start n) (vector-length table))
                            (raise (make-wasm-trap "table.fill: OOB")))
                          (let lp ([i 0])
                            (when (< i n)
                              (vector-set! table (+ i-start i) val)
                              (lp (+ i 1))))
                          (step)))]
                     [else
                      (raise (make-wasm-trap
                        (string-append "unsupported 0xFC sub-opcode: " (number->string sub))))]))]

                ;; ---- 0xFB prefix (GC proposal) ----
                [(= op #xFB)
                 (let* ([r (decode-u32-leb128 code-bv pos)]
                        [sub (car r)])
                   (set! pos (+ pos (cdr r)))
                   (cond
                     ;; struct.new type-idx
                     [(= sub #x00)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [type-idx (car r2)])
                        (set! pos (+ pos (cdr r2)))
                        ;; Get field count from type section
                        (let* ([type (list-ref types type-idx)]
                               [field-count (length (car type))]
                               [fields (make-vector field-count 0)])
                          ;; Pop fields in reverse order (last field on top)
                          (let lp ([i (- field-count 1)])
                            (when (>= i 0)
                              (vector-set! fields i (pop!))
                              (lp (- i 1))))
                          (push! (make-wasm-struct type-idx fields))
                          (step)))]
                     ;; struct.new_default type-idx
                     [(= sub #x01)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [type-idx (car r2)])
                        (set! pos (+ pos (cdr r2)))
                        (let* ([type (list-ref types type-idx)]
                               [field-count (length (car type))]
                               [fields (make-vector field-count 0)])
                          (push! (make-wasm-struct type-idx fields))
                          (step)))]
                     ;; struct.get type-idx field-idx
                     [(= sub #x02)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [type-idx (car r2)]
                             [r3 (decode-u32-leb128 code-bv (+ pos (cdr r2)))]
                             [field-idx (car r3)])
                        (set! pos (+ pos (cdr r2) (cdr r3)))
                        (let ([s (pop!)])
                          (unless (wasm-struct? s)
                            (raise (make-wasm-trap "struct.get: not a struct")))
                          (when (>= field-idx (vector-length (wasm-struct-fields s)))
                            (raise (make-wasm-trap "struct.get: field index OOB")))
                          (push! (vector-ref (wasm-struct-fields s) field-idx))
                          (step)))]
                     ;; struct.get_s/get_u (same as get for our representation)
                     [(or (= sub #x03) (= sub #x04))
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [type-idx (car r2)]
                             [r3 (decode-u32-leb128 code-bv (+ pos (cdr r2)))]
                             [field-idx (car r3)])
                        (set! pos (+ pos (cdr r2) (cdr r3)))
                        (let ([s (pop!)])
                          (unless (wasm-struct? s)
                            (raise (make-wasm-trap "struct.get_s/u: not a struct")))
                          (push! (vector-ref (wasm-struct-fields s) field-idx))
                          (step)))]
                     ;; struct.set type-idx field-idx
                     [(= sub #x05)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [type-idx (car r2)]
                             [r3 (decode-u32-leb128 code-bv (+ pos (cdr r2)))]
                             [field-idx (car r3)])
                        (set! pos (+ pos (cdr r2) (cdr r3)))
                        (let* ([val (pop!)] [s (pop!)])
                          (unless (wasm-struct? s)
                            (raise (make-wasm-trap "struct.set: not a struct")))
                          (when (>= field-idx (vector-length (wasm-struct-fields s)))
                            (raise (make-wasm-trap "struct.set: field index OOB")))
                          (vector-set! (wasm-struct-fields s) field-idx val)
                          (step)))]
                     ;; array.new type-idx
                     [(= sub #x06)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [type-idx (car r2)])
                        (set! pos (+ pos (cdr r2)))
                        (let* ([n (pop!)] [init (pop!)])
                          (push! (make-wasm-array type-idx (make-vector n init)))
                          (step)))]
                     ;; array.new_default type-idx
                     [(= sub #x07)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [type-idx (car r2)])
                        (set! pos (+ pos (cdr r2)))
                        (let ([n (pop!)])
                          (push! (make-wasm-array type-idx (make-vector n 0)))
                          (step)))]
                     ;; array.new_fixed type-idx count
                     [(= sub #x08)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [type-idx (car r2)]
                             [r3 (decode-u32-leb128 code-bv (+ pos (cdr r2)))]
                             [count (car r3)])
                        (set! pos (+ pos (cdr r2) (cdr r3)))
                        (let ([data (make-vector count 0)])
                          (let lp ([i (- count 1)])
                            (when (>= i 0)
                              (vector-set! data i (pop!))
                              (lp (- i 1))))
                          (push! (make-wasm-array type-idx data))
                          (step)))]
                     ;; array.new_data type-idx data-idx
                     [(= sub #x09)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [type-idx (car r2)]
                             [r3 (decode-u32-leb128 code-bv (+ pos (cdr r2)))]
                             [data-idx (car r3)])
                        (set! pos (+ pos (cdr r2) (cdr r3)))
                        (let* ([n (pop!)] [offset (pop!)])
                          (when (>= data-idx (vector-length data-segs))
                            (raise (make-wasm-trap "array.new_data: segment OOB")))
                          (let ([seg (vector-ref data-segs data-idx)])
                            (when (not seg)
                              (raise (make-wasm-trap "array.new_data: segment dropped")))
                            (when (> (+ offset n) (bytevector-length seg))
                              (raise (make-wasm-trap "array.new_data: segment bounds exceeded")))
                            (let ([data (make-vector n 0)])
                              (let lp ([i 0])
                                (when (< i n)
                                  (vector-set! data i (bytevector-u8-ref seg (+ offset i)))
                                  (lp (+ i 1))))
                              (push! (make-wasm-array type-idx data))
                              (step)))))]
                     ;; array.new_elem type-idx elem-idx
                     [(= sub #x0A)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [type-idx (car r2)]
                             [r3 (decode-u32-leb128 code-bv (+ pos (cdr r2)))]
                             [elem-idx (car r3)])
                        (set! pos (+ pos (cdr r2) (cdr r3)))
                        (let* ([n (pop!)] [offset (pop!)])
                          (when (>= elem-idx (vector-length elem-segs))
                            (raise (make-wasm-trap "array.new_elem: segment OOB")))
                          (let ([seg (vector-ref elem-segs elem-idx)])
                            (when (not seg)
                              (raise (make-wasm-trap "array.new_elem: segment dropped")))
                            (when (> (+ offset n) (vector-length seg))
                              (raise (make-wasm-trap "array.new_elem: bounds exceeded")))
                            (let ([data (make-vector n 0)])
                              (let lp ([i 0])
                                (when (< i n)
                                  (vector-set! data i (vector-ref seg (+ offset i)))
                                  (lp (+ i 1))))
                              (push! (make-wasm-array type-idx data))
                              (step)))))]
                     ;; array.get type-idx
                     [(= sub #x0B)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)])
                        (set! pos (+ pos (cdr r2)))
                        (let* ([idx (pop!)] [arr (pop!)])
                          (unless (wasm-array? arr)
                            (raise (make-wasm-trap "array.get: not an array")))
                          (when (or (< idx 0) (>= idx (vector-length (wasm-array-data arr))))
                            (raise (make-wasm-trap "array.get: index OOB")))
                          (push! (vector-ref (wasm-array-data arr) idx))
                          (step)))]
                     ;; array.get_s/get_u (same for our representation)
                     [(or (= sub #x0C) (= sub #x0D))
                      (let* ([r2 (decode-u32-leb128 code-bv pos)])
                        (set! pos (+ pos (cdr r2)))
                        (let* ([idx (pop!)] [arr (pop!)])
                          (unless (wasm-array? arr)
                            (raise (make-wasm-trap "array.get_s/u: not an array")))
                          (when (or (< idx 0) (>= idx (vector-length (wasm-array-data arr))))
                            (raise (make-wasm-trap "array.get_s/u: index OOB")))
                          (push! (vector-ref (wasm-array-data arr) idx))
                          (step)))]
                     ;; array.set type-idx
                     [(= sub #x0E)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)])
                        (set! pos (+ pos (cdr r2)))
                        (let* ([val (pop!)] [idx (pop!)] [arr (pop!)])
                          (unless (wasm-array? arr)
                            (raise (make-wasm-trap "array.set: not an array")))
                          (when (or (< idx 0) (>= idx (vector-length (wasm-array-data arr))))
                            (raise (make-wasm-trap "array.set: index OOB")))
                          (vector-set! (wasm-array-data arr) idx val)
                          (step)))]
                     ;; array.len
                     [(= sub #x0F)
                      (let ([arr (pop!)])
                        (unless (wasm-array? arr)
                          (raise (make-wasm-trap "array.len: not an array")))
                        (push! (vector-length (wasm-array-data arr)))
                        (step))]
                     ;; array.fill type-idx
                     [(= sub #x10)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)])
                        (set! pos (+ pos (cdr r2)))
                        (let* ([n (pop!)] [val (pop!)] [offset (pop!)] [arr (pop!)])
                          (unless (wasm-array? arr)
                            (raise (make-wasm-trap "array.fill: not an array")))
                          (let ([data (wasm-array-data arr)])
                            (when (> (+ offset n) (vector-length data))
                              (raise (make-wasm-trap "array.fill: OOB")))
                            (let lp ([i 0])
                              (when (< i n)
                                (vector-set! data (+ offset i) val)
                                (lp (+ i 1)))))
                          (step)))]
                     ;; array.copy dst-type src-type
                     [(= sub #x11)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [r3 (decode-u32-leb128 code-bv (+ pos (cdr r2)))])
                        (set! pos (+ pos (cdr r2) (cdr r3)))
                        (let* ([n (pop!)] [src-off (pop!)] [src-arr (pop!)]
                               [dst-off (pop!)] [dst-arr (pop!)])
                          (unless (and (wasm-array? src-arr) (wasm-array? dst-arr))
                            (raise (make-wasm-trap "array.copy: not arrays")))
                          (let ([sd (wasm-array-data src-arr)]
                                [dd (wasm-array-data dst-arr)])
                            (when (> (+ src-off n) (vector-length sd))
                              (raise (make-wasm-trap "array.copy: source OOB")))
                            (when (> (+ dst-off n) (vector-length dd))
                              (raise (make-wasm-trap "array.copy: dest OOB")))
                            (let lp ([i 0])
                              (when (< i n)
                                (vector-set! dd (+ dst-off i) (vector-ref sd (+ src-off i)))
                                (lp (+ i 1)))))
                          (step)))]
                     ;; ref.i31
                     [(= sub #x1C)
                      (let ([v (pop!)])
                        (push! (make-wasm-i31 (bitwise-and v #x7FFFFFFF)))
                        (step))]
                     ;; i31.get_s
                     [(= sub #x1D)
                      (let ([v (pop!)])
                        (unless (wasm-i31? v)
                          (raise (make-wasm-trap "i31.get_s: not an i31ref")))
                        (let ([raw (wasm-i31-value v)])
                          (push! (if (>= raw #x40000000) (- raw #x80000000) raw))
                          (step)))]
                     ;; i31.get_u
                     [(= sub #x1E)
                      (let ([v (pop!)])
                        (unless (wasm-i31? v)
                          (raise (make-wasm-trap "i31.get_u: not an i31ref")))
                        (push! (wasm-i31-value v))
                        (step))]
                     ;; ref.test type-idx
                     [(= sub #x14)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [type-idx (car r2)])
                        (set! pos (+ pos (cdr r2)))
                        (let ([v (pop!)])
                          (push! (i32-bool
                            (cond
                              [(wasm-struct? v) (= (wasm-struct-type-idx v) type-idx)]
                              [(wasm-array? v) (= (wasm-array-type-idx v) type-idx)]
                              [else #f])))
                          (step)))]
                     ;; ref.test_null type-idx (like ref.test but also succeeds on null)
                     [(= sub #x15)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [type-idx (car r2)])
                        (set! pos (+ pos (cdr r2)))
                        (let ([v (pop!)])
                          (push! (i32-bool
                            (or (not v)
                                (and (wasm-struct? v) (= (wasm-struct-type-idx v) type-idx))
                                (and (wasm-array? v) (= (wasm-array-type-idx v) type-idx)))))
                          (step)))]
                     ;; ref.cast type-idx
                     [(= sub #x16)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [type-idx (car r2)])
                        (set! pos (+ pos (cdr r2)))
                        (let ([v (pop!)])
                          (unless (cond
                                    [(wasm-struct? v) (= (wasm-struct-type-idx v) type-idx)]
                                    [(wasm-array? v) (= (wasm-array-type-idx v) type-idx)]
                                    [else #f])
                            (raise (make-wasm-trap "ref.cast: type mismatch")))
                          (push! v)
                          (step)))]
                     ;; ref.cast_null type-idx
                     [(= sub #x17)
                      (let* ([r2 (decode-u32-leb128 code-bv pos)]
                             [type-idx (car r2)])
                        (set! pos (+ pos (cdr r2)))
                        (let ([v (pop!)])
                          (unless (or (not v)
                                      (and (wasm-struct? v) (= (wasm-struct-type-idx v) type-idx))
                                      (and (wasm-array? v) (= (wasm-array-type-idx v) type-idx)))
                            (raise (make-wasm-trap "ref.cast_null: type mismatch")))
                          (push! v)
                          (step)))]
                     ;; extern.internalize (identity for our implementation)
                     [(= sub #x1A) (step)]
                     ;; extern.externalize (identity for our implementation)
                     [(= sub #x1B) (step)]
                     [else
                      (raise (make-wasm-trap
                        (string-append "unsupported 0xFB sub-opcode: 0x"
                                       (number->string sub 16))))]))]

                ;; ---- unknown ----
                [else
                 (raise (make-wasm-trap
                   (string-append "unsupported opcode: 0x" (number->string op 16))))]))))))

      ;; Start execution with tail-call trampoline
      (let trampoline ()
        (guard (exn
          [(wasm-tail-call? exn)
           ;; Tail call: restart execution with new function, same depth
           (let* ([fidx (wasm-tail-call-func-idx exn)]
                  [tc-args (wasm-tail-call-args exn)]
                  [local-fidx (- fidx (vector-length imports))]
                  [fi (vector-ref all-funcs local-fidx)]
                  [param-count (car fi)]
                  [tc-code (cadr fi)]
                  [lc (caddr fi)]
                  [new-lv (make-vector (+ param-count lc) 0)])
             (let lp ([i 0] [args tc-args])
               (unless (null? args)
                 (vector-set! new-lv i (car args))
                 (lp (+ i 1) (cdr args))))
             ;; Reset interpreter state for new function
             (set! code-bv tc-code)
             (set! locals-vec new-lv)
             (set! stack '())
             (set! stack-depth 0)
             (set! pos 0)
             (set! len (bytevector-length tc-code))
             (set! memory (vector-ref memory-box 0))
             (trampoline))])
        (run-until-end)))

      ;; Result is top of stack (or 0 if empty)
      (if (null? stack) 0 (car stack))))

  ;;; ========== Module validation ==========

  (define (wasm-validate-module decoded-mod)
    (let ([secs (decoded-module-sections decoded-mod)])

      ;; 1. Section ordering: non-custom sections must have strictly increasing IDs
      (let ([non-custom (filter (lambda (s) (not (= (car s) 0))) secs)])
        (let loop ([prev -1] [rest non-custom])
          (unless (null? rest)
            (let ([sid (caar rest)])
              (when (<= sid prev)
                (raise (make-wasm-trap
                  (string-append "invalid section order: section "
                                 (number->string sid)
                                 " after section "
                                 (number->string prev)))))
              (loop sid (cdr rest))))))

      ;; Parse sections for cross-validation
      (let* ([type-sec (assv wasm-section-type secs)]
             [func-sec (assv wasm-section-function secs)]
             [code-sec (assv wasm-section-code secs)]
             [mem-sec  (assv wasm-section-memory secs)]
             [table-sec (assv wasm-section-table secs)]
             [import-sec (assv wasm-section-import secs)]
             [start-sec (assv wasm-section-start secs)]
             [types (if type-sec (parse-type-section (cdr type-sec)) '())]
             [tidxs (if func-sec (parse-function-section (cdr func-sec)) '())]
             [codes (if code-sec (parse-code-section (cdr code-sec)) '())]
             [ntype (length types)]
             [imp-list (if import-sec (parse-import-section (cdr import-sec)) '())]
             [nimports (length (filter (lambda (i) (eq? (car i) 'func)) imp-list))]
             [nfuncs (length tidxs)]
             [total-funcs (+ nimports nfuncs)])

        ;; 2. Function/code count must match
        (unless (= (length tidxs) (length codes))
          (raise (make-wasm-trap
            (string-append "function/code section count mismatch: "
                           (number->string (length tidxs)) " vs "
                           (number->string (length codes))))))

        ;; 3. Type indices must be in bounds
        (for-each
          (lambda (ti)
            (when (>= ti ntype)
              (raise (make-wasm-trap
                (string-append "type index out of bounds: "
                               (number->string ti)
                               " (max " (number->string ntype) ")")))))
          tidxs)

        ;; 4. At most one memory (WASM MVP)
        (when mem-sec
          (let ([mems (parse-memory-section (cdr mem-sec))])
            (when (> (length mems) 1)
              (raise (make-wasm-trap "multiple memories not allowed in MVP")))))

        ;; 5. At most one table (WASM MVP)
        (when table-sec
          (let ([tbls (parse-table-section (cdr table-sec))])
            (when (> (length tbls) 1)
              (raise (make-wasm-trap "multiple tables not allowed in MVP")))))

        ;; 6. Start function index must be valid
        (when start-sec
          (let ([start-idx (parse-start-section (cdr start-sec))])
            (when (>= start-idx total-funcs)
              (raise (make-wasm-trap
                (string-append "start function index out of bounds: "
                               (number->string start-idx)))))))

        ;; 7. Bytecode validation: check block nesting and opcode validity
        (let ([func-idx 0])
          (for-each
            (lambda (code-entry)
              (let* ([code-bv (cdr code-entry)]
                     [len (bytevector-length code-bv)])
                (validate-bytecode code-bv len func-idx)
                (set! func-idx (+ func-idx 1))))
            codes)))))

  ;; Validate a function body's bytecode
  (define (validate-bytecode bv len func-idx)
    (let loop ([pos 0] [block-depth 0])
      (when (< pos len)
        (let ([op (bytevector-u8-ref bv pos)])
          (cond
            ;; end: decrements block depth
            [(= op #x0B)
             (when (< block-depth 0)
               (raise (make-wasm-trap
                 (string-append "unbalanced end in function " (number->string func-idx)))))
             (loop (+ pos 1) (- block-depth 1))]
            ;; block, loop, if: increment depth
            [(or (= op #x02) (= op #x03) (= op #x04))
             (if (< (+ pos 1) len)
               (loop (+ pos 2) (+ block-depth 1))
               (raise (make-wasm-trap
                 (string-append "truncated block instruction in function "
                                (number->string func-idx)))))]
            ;; else: valid only inside a block
            [(= op #x05)
             (when (<= block-depth 0)
               (raise (make-wasm-trap
                 (string-append "else outside if block in function "
                                (number->string func-idx)))))
             (loop (+ pos 1) block-depth)]
            ;; All other opcodes: advance using skip-instr
            [else
             (let ([next-pos (skip-instr bv pos len)])
               (when (> next-pos len)
                 (raise (make-wasm-trap
                   (string-append "instruction reads past end of function "
                                  (number->string func-idx)))))
               (loop next-pos block-depth))])))))

  ;;; ========== Instantiation ==========

  (define (wasm-store-instantiate store decoded-mod)
    ;; Validate before instantiation
    (wasm-validate-module decoded-mod)
    (let* ([secs (decoded-module-sections decoded-mod)]
           [type-sec  (assv wasm-section-type secs)]
           [import-sec (assv wasm-section-import secs)]
           [func-sec  (assv wasm-section-function secs)]
           [table-sec (assv wasm-section-table secs)]
           [mem-sec   (assv wasm-section-memory secs)]
           [global-sec (assv wasm-section-global secs)]
           [exp-sec   (assv wasm-section-export secs)]
           [start-sec (assv wasm-section-start secs)]
           [elem-sec  (assv wasm-section-element secs)]
           [code-sec  (assv wasm-section-code secs)]
           [data-sec  (assv wasm-section-data secs)]
           [types     (if type-sec (parse-type-section (cdr type-sec)) '())]
           [imp-list  (if import-sec (parse-import-section (cdr import-sec)) '())]
           [func-imports (filter (lambda (i) (eq? (car i) 'func)) imp-list)]
           [nimports  (length func-imports)]
           [tidxs     (if func-sec (parse-function-section (cdr func-sec)) '())]
           [exports   (if exp-sec  (parse-export-section (cdr exp-sec)) '())]
           [codes     (if code-sec (parse-code-section (cdr code-sec)) '())]
           [nfuncs    (length tidxs)]
           [all-funcs (make-vector nfuncs #f)]
           ;; imports-vec entries: (param-count result-count . proc-or-#f)
           [imports-vec (make-vector nimports #f)])

      ;; Initialize import entries with param counts from type signatures
      (let loop ([i 0] [fi func-imports])
        (when (< i nimports)
          (let* ([imp (car fi)]
                 [tidx (cadddr imp)]
                 [type (list-ref types tidx)]
                 [pc (length (car type))]
                 [rc (length (cdr type))])
            (vector-set! imports-vec i (list pc rc #f tidx))
            (loop (+ i 1) (cdr fi)))))

      ;; Build function table
      (let loop ([i 0] [tidxs tidxs] [codes codes])
        (when (< i nfuncs)
          (let* ([ti (car tidxs)]
                 [type (list-ref types ti)]
                 [pc (length (car type))]
                 [ce (car codes)]
                 [lc (length (car ce))]
                 [cb (cdr ce)])
            (vector-set! all-funcs i (list pc cb lc ti))
            (loop (+ i 1) (cdr tidxs) (cdr codes)))))

      ;; Memory
      (let* ([mem-list (if mem-sec (parse-memory-section (cdr mem-sec)) '())]
             [memory (if (null? mem-list)
                       (make-bytevector 65536 0) ; default 1 page
                       (make-bytevector (* (caar mem-list) 65536) 0))])

        ;; Globals
        (let* ([global-list (if global-sec (parse-global-section (cdr global-sec)) '())]
               [globals (list->vector (map caddr global-list))])

          ;; Tables
          (let* ([table-list (if table-sec (parse-table-section (cdr table-sec)) '())]
                 [tables (list->vector
                           (map (lambda (t)
                                  (let ([min-size (car (cadr t))])
                                    (make-vector min-size #f)))
                                table-list))])

            ;; Initialize data segments (with bounds checking)
            (when data-sec
              (let ([data-segs (parse-data-section (cdr data-sec))])
                (for-each
                  (lambda (seg)
                    (let* ([offset (cadr seg)]
                           [data (caddr seg)]
                           [dlen (bytevector-length data)]
                           [mem-len (bytevector-length memory)])
                      (when (or (< offset 0)
                                (> (+ offset dlen) mem-len))
                        (raise (make-wasm-trap
                          (string-append "data segment out of bounds: offset "
                                         (number->string offset)
                                         " + length " (number->string dlen)
                                         " exceeds memory size " (number->string mem-len)))))
                      (bytevector-copy! data 0 memory offset dlen)))
                  data-segs)))

            ;; Initialize element segments (with bounds checking)
            (when elem-sec
              (let ([elems (parse-element-section (cdr elem-sec))])
                (for-each
                  (lambda (seg)
                    (let ([tidx (car seg)]
                          [offset (cadr seg)]
                          [func-idxs (caddr seg)])
                      (when (>= tidx (vector-length tables))
                        (raise (make-wasm-trap
                          (string-append "element segment table index out of bounds: "
                                         (number->string tidx)))))
                      (let ([table (vector-ref tables tidx)]
                            [nidxs (length func-idxs)])
                        (when (or (< offset 0)
                                  (> (+ offset nidxs) (vector-length table)))
                          (raise (make-wasm-trap
                            (string-append "element segment out of bounds: offset "
                                           (number->string offset)
                                           " + count " (number->string nidxs)
                                           " exceeds table size "
                                           (number->string (vector-length table))))))
                        (let loop ([i 0] [idxs func-idxs])
                          (unless (null? idxs)
                            (vector-set! table (+ offset i) (car idxs))
                            (loop (+ i 1) (cdr idxs)))))))
                  elems)))

            ;; Build memory box (shared mutable reference)
            (let ([memory-box (vector memory)])

              ;; Preserve raw data segments for memory.init/data.drop
              (let ([raw-data-segs
                     (if data-sec
                       (let ([segs (parse-data-section (cdr data-sec))])
                         (list->vector (map (lambda (seg) (caddr seg)) segs)))
                       (make-vector 0))])

                ;; Preserve raw element segments for table.init/elem.drop
                (let ([raw-elem-segs
                       (if elem-sec
                         (let ([segs (parse-element-section (cdr elem-sec))])
                           (list->vector (map (lambda (seg) (list->vector (caddr seg))) segs)))
                         (make-vector 0))])

                  ;; Parse tag section (section 13) for exception handling
                  (let* ([tag-sec (assv wasm-section-tag secs)]
                         [tag-list
                          (if tag-sec
                            (let* ([bv (cdr tag-sec)]
                                   [cr (read-u32 bv 0)]
                                   [count (car cr)]
                                   [pos (cdr cr)])
                              (let loop ([i 0] [p pos] [acc '()])
                                (if (= i count) (reverse acc)
                                  (let* ([attr (bytevector-u8-ref bv p)] ; attribute byte (0 = exception)
                                         [r (read-u32 bv (+ p 1))]
                                         [tidx (car r)])
                                    (loop (+ i 1) (+ p 1 (cdr r))
                                      (cons (make-wasm-tag tidx) acc))))))
                            '())]
                         [tags-vec (list->vector tag-list)])

                    ;; Build exports alist (name -> kind + index only)
                    (let ([exp-alist
                           (map (lambda (e)
                                  (let ([name (car e)] [kind (cadr e)] [idx (caddr e)])
                                    (cons name (list kind idx))))
                                exports)])

                      (let ([inst (make-wasm-instance exp-alist all-funcs memory-box globals tables
                                                       imports-vec types raw-data-segs raw-elem-segs tags-vec)])

                        ;; Run start function if present
                        (when start-sec
                          (let* ([start-idx (parse-start-section (cdr start-sec))]
                                 [local-idx (- start-idx nimports)]
                                 [default-limits (vector 10000000 1000 10000 256)])
                            (when (and (>= local-idx 0) (< local-idx nfuncs))
                              (let* ([fi (vector-ref all-funcs local-idx)]
                                     [code (cadr fi)]
                                     [lc (caddr fi)]
                                     [lv (make-vector lc 0)])
                                (execute-func code lv all-funcs memory-box globals tables imports-vec
                                              default-limits 0 types raw-data-segs raw-elem-segs tags-vec)))))

                        inst)))))))))))

  ;;; ========== Runtime API ==========

  (define (wasm-runtime-load rt bv)
    ;; Enforce module size limit before parsing
    (let ([max-size (or (wasm-runtime-max-module-size rt) (* 16 1024 1024))]) ;; default 16MB
      (when (> (bytevector-length bv) max-size)
        (raise (make-wasm-trap
          (string-append "module too large: " (number->string (bytevector-length bv))
                         " bytes (limit " (number->string max-size) ")")))))
    (let* ([decoded (wasm-decode-module bv)]
           [store (make-wasm-store)]
           [inst (wasm-store-instantiate store decoded)])
      (wasm-runtime-instance-set! rt inst)
      inst))

  (define (wasm-runtime-call rt name . args)
    ;; Exception boundary: catch ALL uncontrolled Chez exceptions and convert
    ;; to wasm-trap. This prevents host exception propagation from interpreter
    ;; bugs, malformed bytecode, or edge cases in Chez arithmetic.
    (guard (exn
             [(wasm-trap? exn) (raise exn)]  ;; re-raise wasm-traps as-is
             [else
              (raise (make-wasm-trap
                (string-append "internal error in WASM execution: "
                  (call-with-string-output-port
                    (lambda (p) (display-condition exn p))))))])
      (let* ([inst (wasm-runtime-instance rt)]
             [exp (assoc name (wasm-instance-exports inst))])
        (unless exp
          (raise (make-wasm-trap (string-append "export not found: " name))))
        (let* ([v (cdr exp)]
               [kind (car v)]
               [idx (cadr v)]
               ;; Read current state from instance (not stale export snapshot)
               [all-funcs (wasm-instance-funcs inst)]
               [memory-box (wasm-instance-memory-box inst)]
               [globals (wasm-instance-globals inst)]
               [tables (wasm-instance-tables inst)]
               [imports (wasm-instance-imports inst)]
               [types (wasm-instance-types inst)]
               [data-segs (wasm-instance-data-segments inst)]
               [elem-segs (wasm-instance-elem-segments inst)]
               [tags (wasm-instance-tags inst)]
               ;; Resource limits
               [fuel (or (wasm-runtime-fuel rt) 10000000)]
               [max-depth (or (wasm-runtime-max-depth rt) 1000)]
               [max-stack (or (wasm-runtime-max-stack rt) 10000)]
               [max-mem-pages (or (wasm-runtime-max-memory-pages rt) 256)]
               [import-val (wasm-runtime-import-validator rt)]
               [limits (vector fuel max-depth max-stack max-mem-pages import-val)])
          (unless (= kind 0)
            (raise (make-wasm-trap (string-append "not a function export: " name))))
          (let* ([fi (vector-ref all-funcs idx)]
                 [pc (car fi)]
                 [code (cadr fi)]
                 [lc (caddr fi)]
                 [lv (make-vector (+ pc lc) 0)])
            (let lp ([i 0] [args args])
              (unless (null? args)
                (vector-set! lv i (car args))
                (lp (+ i 1) (cdr args))))
            (execute-func code lv all-funcs memory-box globals tables imports limits 0 types
                          data-segs elem-segs tags))))))

  (define (wasm-runtime-memory-ref rt offset)
    (let ([mem (wasm-instance-memory (wasm-runtime-instance rt))])
      (when (or (< offset 0) (>= offset (bytevector-length mem)))
        (raise (make-wasm-trap
          (string-append "memory-ref: offset out of bounds: "
                         (number->string offset)
                         " (memory size " (number->string (bytevector-length mem)) ")"))))
      (bytevector-u8-ref mem offset)))

  (define (wasm-runtime-memory-set! rt offset val)
    (let ([mem (wasm-instance-memory (wasm-runtime-instance rt))])
      (when (or (< offset 0) (>= offset (bytevector-length mem)))
        (raise (make-wasm-trap
          (string-append "memory-set!: offset out of bounds: "
                         (number->string offset)
                         " (memory size " (number->string (bytevector-length mem)) ")"))))
      (bytevector-u8-set! mem offset val)))

  (define (wasm-runtime-memory rt)
    (wasm-instance-memory (wasm-runtime-instance rt)))

  (define (wasm-runtime-memory-size rt)
    (bytevector-length (wasm-instance-memory (wasm-runtime-instance rt))))

  (define (wasm-runtime-global-ref rt idx)
    (let ([globals (wasm-instance-globals (wasm-runtime-instance rt))])
      (when (or (< idx 0) (>= idx (vector-length globals)))
        (raise (make-wasm-trap
          (string-append "global-ref: index out of bounds: "
                         (number->string idx)
                         " (globals count " (number->string (vector-length globals)) ")"))))
      (vector-ref globals idx)))

  (define (wasm-runtime-global-set! rt idx val)
    (let ([globals (wasm-instance-globals (wasm-runtime-instance rt))])
      (when (or (< idx 0) (>= idx (vector-length globals)))
        (raise (make-wasm-trap
          (string-append "global-set!: index out of bounds: "
                         (number->string idx)
                         " (globals count " (number->string (vector-length globals)) ")"))))
      (vector-set! globals idx val)))

  (define (wasm-run-start inst) #f)

) ;; end library
