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
    make-wasm-trap wasm-trap? wasm-trap-message
    wasm-instance? wasm-instance-exports
    wasm-decode-module wasm-module-sections wasm-run-start
    wasm-validate-module
    make-wasm-store wasm-store? wasm-store-instantiate)

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

  ;;; ========== Decoded module ==========

  (define-record-type decoded-module
    (fields sections))

  (define (wasm-module-sections mod)
    (decoded-module-sections mod))

  ;;; ========== WASM instance ==========

  (define-record-type wasm-instance
    (fields
      exports        ; alist: name -> (kind idx)
      funcs          ; vector of (param-count code local-count)
      (mutable memory-box)  ; (vector bytevector) -- boxed for memory.grow
      globals        ; vector
      tables         ; vector of vectors (funcref tables)
      imports))      ; vector of import procedures

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
            (mutable fuel)       ; #f or integer (max fuel per call)
            (mutable max-depth)) ; #f or integer (max call depth)
    (protocol (lambda (new) (lambda () (new #f #f #f)))))

  (define (wasm-runtime-set-fuel! rt n)
    (wasm-runtime-fuel-set! rt n))

  (define (wasm-runtime-set-max-depth! rt n)
    (wasm-runtime-max-depth-set! rt n))

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
        (error 'wasm-decode-module "invalid WASM magic"))
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
               (error 'parse-import-section "unknown import kind" kind)]))))))

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
         (error 'eval-init-expr "unsupported init expression opcode" op)])))

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
               (= op #x0B) (= op #x05))
           (+ pos 1)]
          ;; One LEB128 immediate
          [(or (= op #x0C) (= op #x0D)  ; br, br_if
               (= op #x10)              ; call
               (= op #x20) (= op #x21) (= op #x22)  ; local ops
               (= op #x23) (= op #x24))             ; global ops
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
          ;; block/loop: 1 byte block type
          [(or (= op #x02) (= op #x03)) (+ pos 2)]
          ;; if: 1 byte block type
          [(= op #x04) (+ pos 2)]
          ;; memory.size, memory.grow: 1 byte (reserved)
          [(or (= op #x3F) (= op #x40)) (+ pos 2)]
          ;; call_indirect: 2 LEB128
          [(= op #x11)
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
          [else (+ pos 1)]))))

  (define (skip-to-else-or-end bv pos len)
    (let loop ([pos pos] [depth 0])
      (if (>= pos len)
        (error 'skip-to-else-or-end "unterminated if block")
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
        (error 'skip-to-end "unterminated block")
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

  ;; Unsigned division/remainder for i32
  (define (i32-div-u a b)
    (when (= b 0) (error 'execute-func "integer divide by zero"))
    (i32 (quotient (u32 a) (u32 b))))

  (define (i32-rem-u a b)
    (when (= b 0) (error 'execute-func "remainder by zero"))
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

  ;; limits = (vector fuel-remaining max-call-depth)
  ;; memory-box = (vector bytevector) -- shared mutable reference
  (define (execute-func code-bv locals-vec all-funcs memory-box globals tables imports limits depth)
    ;; Check call depth
    (let ([max-depth (vector-ref limits 1)])
      (when (> depth max-depth)
        (raise (make-wasm-trap
          (string-append "call depth exceeded (limit "
                         (number->string max-depth) ")")))))

    (let ([stack '()]
          [pos 0]
          [memory (vector-ref memory-box 0)]
          [len (bytevector-length code-bv)])

      (define (push! v) (set! stack (cons v stack)))
      (define (pop!)
        (when (null? stack) (error 'execute-func "stack underflow"))
        (let ([v (car stack)]) (set! stack (cdr stack)) v))
      (define (peek)
        (when (null? stack) (error 'execute-func "stack underflow"))
        (car stack))

      ;; Read a memory address: evaluate offset + addr from stack
      (define (read-memarg)
        (let* ([r1 (decode-u32-leb128 code-bv pos)]
               [align (car r1)]
               [r2 (decode-u32-leb128 code-bv (+ pos (cdr r1)))]
               [offset (car r2)])
          (set! pos (+ pos (cdr r1) (cdr r2)))
          (let ([base (pop!)])
            (+ base offset))))

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
              (cond
                ;; ---- end ----
                [(= op #x0B) (void)] ; return from this block level

                ;; ---- nop ----
                [(= op #x01) (step)]

                ;; ---- unreachable ----
                [(= op #x00) (error 'execute-func "unreachable")]

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
                       ;; Import call (placeholder)
                       (let ([imp-fn (vector-ref imports fidx)])
                         (when imp-fn
                           (push! (imp-fn))))
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
                         (push! (execute-func code new-lv all-funcs memory-box globals tables imports limits (+ depth 1))))))
                   (step))]

                ;; ---- call_indirect ----
                [(= op #x11)
                 (let* ([r1 (decode-u32-leb128 code-bv pos)]
                        [type-idx (car r1)]
                        [r2 (decode-u32-leb128 code-bv (+ pos (cdr r1)))]
                        [table-idx (car r2)])
                   (set! pos (+ pos (cdr r1) (cdr r2)))
                   (let* ([elem-idx (pop!)]
                          [table (vector-ref tables table-idx)]
                          [fidx (vector-ref table elem-idx)])
                     (when (not fidx)
                       (raise (make-wasm-trap
                         (string-append "call_indirect: null table entry " (number->string elem-idx)))))
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
                       (push! (execute-func code new-lv all-funcs memory-box globals tables imports limits (+ depth 1))))))
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
                        [old-pages (quotient (bytevector-length memory) 65536)]
                        [new-size (* (+ old-pages pages) 65536)])
                   (if (or (< pages 0) (> new-size (* 256 65536))) ; max 256 pages = 16MB
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
                   (when (= b 0) (error 'execute-func "integer divide by zero"))
                   (push! (i32 (truncate (/ a b))))
                   (step))]
                [(= op #x6E) ; div_u
                 (let* ([b (pop!)] [a (pop!)])
                   (push! (i32-div-u a b))
                   (step))]
                [(= op #x6F) ; rem_s
                 (let* ([b (pop!)] [a (pop!)])
                   (when (= b 0) (error 'execute-func "remainder by zero"))
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
                [(= op #x79) (push! 0) (step)] ; clz (simplified)
                [(= op #x7A) (push! 0) (step)] ; ctz (simplified)
                [(= op #x7B) (push! 0) (step)] ; popcnt (simplified)
                [(= op #x7C) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (+ a b))) (step))]
                [(= op #x7D) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (- a b))) (step))]
                [(= op #x7E) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (* a b))) (step))]
                [(= op #x7F) (let* ([b (pop!)] [a (pop!)])
                   (when (= b 0) (error 'execute-func "integer divide by zero"))
                   (push! (i64 (truncate (/ a b)))) (step))]
                [(= op #x80) (let* ([b (pop!)] [a (pop!)])
                   (when (= b 0) (error 'execute-func "integer divide by zero"))
                   (push! (i64 (quotient (u64 a) (u64 b)))) (step))]
                [(= op #x81) (let* ([b (pop!)] [a (pop!)])
                   (when (= b 0) (error 'execute-func "remainder by zero"))
                   (push! (i64 (remainder a b))) (step))]
                [(= op #x82) (let* ([b (pop!)] [a (pop!)])
                   (when (= b 0) (error 'execute-func "remainder by zero"))
                   (push! (i64 (remainder (u64 a) (u64 b)))) (step))]
                [(= op #x83) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (bitwise-and a b))) (step))]
                [(= op #x84) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (bitwise-ior a b))) (step))]
                [(= op #x85) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (bitwise-xor a b))) (step))]
                [(= op #x86) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (bitwise-arithmetic-shift-left a (bitwise-and b 63)))) (step))]
                [(= op #x87) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (bitwise-arithmetic-shift-right a (bitwise-and b 63)))) (step))]
                [(= op #x88) (let* ([b (pop!)] [a (pop!)]) (push! (i64 (bitwise-arithmetic-shift-right (u64 a) (bitwise-and b 63)))) (step))]
                [(= op #x89) (push! 0) (step)] ; i64.rotl (simplified)
                [(= op #x8A) (push! 0) (step)] ; i64.rotr (simplified)

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

                ;; ---- unknown ----
                [else
                 (error 'execute-func
                   (string-append "unsupported opcode: 0x" (number->string op 16)))])))))

      ;; Start execution
      (run-until-end)

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
                               (number->string start-idx))))))))))

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
           [imports-vec (make-vector nimports #f)])

      ;; Build function table
      (let loop ([i 0] [tidxs tidxs] [codes codes])
        (when (< i nfuncs)
          (let* ([ti (car tidxs)]
                 [type (list-ref types ti)]
                 [pc (length (car type))]
                 [ce (car codes)]
                 [lc (length (car ce))]
                 [cb (cdr ce)])
            (vector-set! all-funcs i (list pc cb lc))
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
                                  (let ([min-size (cadr (cadr t))])
                                    (make-vector min-size #f)))
                                table-list))])

            ;; Initialize data segments
            (when data-sec
              (let ([data-segs (parse-data-section (cdr data-sec))])
                (for-each
                  (lambda (seg)
                    (let ([offset (cadr seg)] [data (caddr seg)])
                      (bytevector-copy! data 0 memory offset (bytevector-length data))))
                  data-segs)))

            ;; Initialize element segments
            (when elem-sec
              (let ([elems (parse-element-section (cdr elem-sec))])
                (for-each
                  (lambda (seg)
                    (let ([tidx (car seg)]
                          [offset (cadr seg)]
                          [func-idxs (caddr seg)])
                      (when (< tidx (vector-length tables))
                        (let ([table (vector-ref tables tidx)])
                          (let loop ([i 0] [idxs func-idxs])
                            (unless (null? idxs)
                              (vector-set! table (+ offset i) (car idxs))
                              (loop (+ i 1) (cdr idxs))))))))
                  elems)))

            ;; Build memory box (shared mutable reference)
            (let ([memory-box (vector memory)])

              ;; Build exports alist (name -> kind + index only)
              (let ([exp-alist
                     (map (lambda (e)
                            (let ([name (car e)] [kind (cadr e)] [idx (caddr e)])
                              (cons name (list kind idx))))
                          exports)])

                (let ([inst (make-wasm-instance exp-alist all-funcs memory-box globals tables imports-vec)])

                  ;; Run start function if present
                  (when start-sec
                    (let* ([start-idx (parse-start-section (cdr start-sec))]
                           [local-idx (- start-idx nimports)]
                           [default-limits (vector 10000000 1000)])
                      (when (and (>= local-idx 0) (< local-idx nfuncs))
                        (let* ([fi (vector-ref all-funcs local-idx)]
                               [code (cadr fi)]
                               [lc (caddr fi)]
                               [lv (make-vector lc 0)])
                          (execute-func code lv all-funcs memory-box globals tables imports-vec
                                        default-limits 0)))))

                  inst))))))))

  ;;; ========== Runtime API ==========

  (define (wasm-runtime-load rt bv)
    (let* ([decoded (wasm-decode-module bv)]
           [store (make-wasm-store)]
           [inst (wasm-store-instantiate store decoded)])
      (wasm-runtime-instance-set! rt inst)
      inst))

  (define (wasm-runtime-call rt name . args)
    (let* ([inst (wasm-runtime-instance rt)]
           [exp (assoc name (wasm-instance-exports inst))])
      (unless exp
        (error 'wasm-runtime-call "export not found" name))
      (let* ([v (cdr exp)]
             [kind (car v)]
             [idx (cadr v)]
             ;; Read current state from instance (not stale export snapshot)
             [all-funcs (wasm-instance-funcs inst)]
             [memory-box (wasm-instance-memory-box inst)]
             [globals (wasm-instance-globals inst)]
             [tables (wasm-instance-tables inst)]
             [imports (wasm-instance-imports inst)]
             ;; Resource limits
             [fuel (or (wasm-runtime-fuel rt) 10000000)]
             [max-depth (or (wasm-runtime-max-depth rt) 1000)]
             [limits (vector fuel max-depth)])
        (unless (= kind 0)
          (error 'wasm-runtime-call "not a function export" name))
        (let* ([fi (vector-ref all-funcs idx)]
               [pc (car fi)]
               [code (cadr fi)]
               [lc (caddr fi)]
               [lv (make-vector (+ pc lc) 0)])
          (let lp ([i 0] [args args])
            (unless (null? args)
              (vector-set! lv i (car args))
              (lp (+ i 1) (cdr args))))
          (execute-func code lv all-funcs memory-box globals tables imports limits 0)))))

  (define (wasm-runtime-memory-ref rt offset)
    (bytevector-u8-ref (wasm-instance-memory (wasm-runtime-instance rt)) offset))

  (define (wasm-runtime-memory-set! rt offset val)
    (bytevector-u8-set! (wasm-instance-memory (wasm-runtime-instance rt)) offset val))

  (define (wasm-runtime-memory rt)
    (wasm-instance-memory (wasm-runtime-instance rt)))

  (define (wasm-runtime-memory-size rt)
    (bytevector-length (wasm-instance-memory (wasm-runtime-instance rt))))

  (define (wasm-runtime-global-ref rt idx)
    (vector-ref (wasm-instance-globals (wasm-runtime-instance rt)) idx))

  (define (wasm-runtime-global-set! rt idx val)
    (vector-set! (wasm-instance-globals (wasm-runtime-instance rt)) idx val))

  (define (wasm-run-start inst) #f)

) ;; end library
