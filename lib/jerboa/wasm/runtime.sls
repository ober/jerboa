#!chezscheme
;;; (jerboa wasm runtime) -- WebAssembly interpreter/runtime
;;;
;;; A stack-based interpreter that executes WASM bytecode.
;;; Supports i32 arithmetic, comparisons, locals, if/else, function calls.
;;; Not a JIT -- pure interpreter for testing codegen correctness.

(library (jerboa wasm runtime)
  (export
    make-wasm-runtime wasm-runtime? wasm-runtime-load wasm-runtime-call
    wasm-runtime-memory-ref wasm-runtime-memory-set!
    wasm-runtime-global-ref wasm-runtime-global-set!
    make-wasm-trap wasm-trap? wasm-trap-message
    wasm-instance? wasm-instance-exports
    wasm-decode-module wasm-module-sections wasm-run-start
    make-wasm-store wasm-store? wasm-store-instantiate)

  (import (chezscheme)
          (jerboa wasm format))

  ;;; ========== Trap ==========

  (define-record-type wasm-trap
    (fields message))

  ;;; ========== Decoded module ==========

  (define-record-type decoded-module
    (fields sections))

  (define (wasm-module-sections mod)
    (decoded-module-sections mod))

  ;;; ========== WASM instance ==========

  (define-record-type wasm-instance
    (fields
      exports
      funcs
      memory
      globals))

  ;;; ========== WASM store ==========

  (define-record-type wasm-store
    (fields (mutable instances))
    (protocol (lambda (new) (lambda () (new '())))))

  ;;; ========== WASM runtime ==========

  (define-record-type wasm-runtime
    (fields (mutable instance))
    (protocol (lambda (new) (lambda () (new #f)))))

  ;;; ========== Binary section parsing helpers ==========

  (define (read-u32 bv pos)
    (let* ([r (decode-u32-leb128 bv pos)])
      (cons (car r) (+ pos (cdr r)))))

  (define (read-i32 bv pos)
    (let* ([r (decode-i32-leb128 bv pos)])
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
    (let* ([cr (read-u32 bv 0)]
           [count (car cr)]
           [pos (cdr cr)])
      (let loop ([i 0] [pos pos] [acc '()])
        (if (= i count)
          (reverse acc)
          (let* ([pos1 (+ pos 1)] ; skip 0x60
                 [pcr (read-u32 bv pos1)]
                 [pcount (car pcr)]
                 [pos2 (cdr pcr)]
                 [params+pos
                  (let lp ([j 0] [p pos2] [a '()])
                    (if (= j pcount)
                      (cons (reverse a) p)
                      (lp (+ j 1) (+ p 1) (cons (bytevector-u8-ref bv p) a))))]
                 [params (car params+pos)]
                 [pos3 (cdr params+pos)]
                 [rcr (read-u32 bv pos3)]
                 [rcount (car rcr)]
                 [pos4 (cdr rcr)]
                 [results+pos
                  (let lp ([j 0] [p pos4] [a '()])
                    (if (= j rcount)
                      (cons (reverse a) p)
                      (lp (+ j 1) (+ p 1) (cons (bytevector-u8-ref bv p) a))))]
                 [results (car results+pos)]
                 [pos5 (cdr results+pos)])
            (loop (+ i 1) pos5 (cons (cons params results) acc)))))))

  (define (parse-function-section bv)
    (let* ([cr (read-u32 bv 0)]
           [count (car cr)]
           [pos (cdr cr)])
      (let loop ([i 0] [pos pos] [acc '()])
        (if (= i count)
          (reverse acc)
          (let* ([r (read-u32 bv pos)])
            (loop (+ i 1) (cdr r) (cons (car r) acc)))))))

  (define (parse-export-section bv)
    (let* ([cr (read-u32 bv 0)]
           [count (car cr)]
           [pos (cdr cr)])
      (let loop ([i 0] [pos pos] [acc '()])
        (if (= i count)
          (reverse acc)
          (let* ([nr (read-string bv pos)]
                 [name (car nr)]
                 [pos1 (cdr nr)]
                 [kind (bytevector-u8-ref bv pos1)]
                 [pos2 (+ pos1 1)]
                 [ir (read-u32 bv pos2)]
                 [idx (car ir)]
                 [pos3 (cdr ir)])
            (loop (+ i 1) pos3 (cons (list name kind idx) acc)))))))

  (define (parse-code-section bv)
    (let* ([cr (read-u32 bv 0)]
           [count (car cr)]
           [pos (cdr cr)])
      (let loop ([i 0] [pos pos] [acc '()])
        (if (= i count)
          (reverse acc)
          (let* ([sr (read-u32 bv pos)]
                 [sz (car sr)]
                 [body-start (cdr sr)]
                 [body-end (+ body-start sz)]
                 [lcr (read-u32 bv body-start)]
                 [lcount (car lcr)]
                 [lpos (cdr lcr)]
                 [locals+pos
                  (let lp ([j 0] [p lpos] [a '()])
                    (if (= j lcount)
                      (cons (reverse a) p)
                      (let* ([nr (read-u32 bv p)]
                             [n (car nr)]
                             [p1 (cdr nr)]
                             [t (bytevector-u8-ref bv p1)]
                             [p2 (+ p1 1)])
                        (lp (+ j 1) p2
                            (append a (make-list n t))))))]
                 [local-types (car locals+pos)]
                 [code-start (cdr locals+pos)]
                 [code-len (- body-end code-start)]
                 [code-bv (make-bytevector code-len)])
            (bytevector-copy! bv code-start code-bv 0 code-len)
            (loop (+ i 1) body-end (cons (cons local-types code-bv) acc)))))))

  ;;; ========== Instruction skipping (for branch handling) ==========

  (define (skip-instr bv pos len)
    (if (>= pos len)
      pos
      (let ([op (bytevector-u8-ref bv pos)])
        (cond
          ;; No immediates
          [(or (= op #x00) (= op #x01) (= op #x0F) (= op #x1A) (= op #x1B)
               (= op #x45)
               (= op #x46) (= op #x47) (= op #x48) (= op #x49)
               (= op #x4A) (= op #x4B) (= op #x4C) (= op #x4E)
               (= op #x6A) (= op #x6B) (= op #x6C) (= op #x6D) (= op #x6F)
               (= op #x71) (= op #x72) (= op #x73) (= op #x74) (= op #x75)
               (= op #x7C) (= op #x7D) (= op #x7E) (= op #x7F)
               (= op #x92) (= op #x93) (= op #x94) (= op #x95)
               (= op #xA0) (= op #xA1) (= op #xA2) (= op #xA3))
           (+ pos 1)]
          ;; One LEB128 immediate
          [(or (= op #x41) (= op #x42)   ; i32/i64.const
               (= op #x20) (= op #x21) (= op #x22) ; local.get/set/tee
               (= op #x23) (= op #x24)   ; global.get/set
               (= op #x10)               ; call
               (= op #x0C) (= op #x0D))  ; br, br_if
           (let* ([r (decode-u32-leb128 bv (+ pos 1))])
             (+ pos 1 (cdr r)))]
          ;; f32.const: 4 bytes
          [(= op #x43) (+ pos 5)]
          ;; f64.const: 8 bytes
          [(= op #x44) (+ pos 9)]
          ;; block/loop: 1 byte block type
          [(or (= op #x02) (= op #x03)) (+ pos 2)]
          ;; memory.size, memory.grow: 1 byte (reserved)
          [(or (= op #x3F) (= op #x40)) (+ pos 2)]
          ;; call_indirect: 2 LEB128
          [(= op #x11)
           (let* ([r1 (decode-u32-leb128 bv (+ pos 1))]
                  [r2 (decode-u32-leb128 bv (+ pos 1 (cdr r1)))])
             (+ pos 1 (cdr r1) (cdr r2)))]
          ;; memory load/store: 2 LEB128 (align, offset)
          [(or (= op #x28) (= op #x29) (= op #x2A) (= op #x2B)
               (= op #x36) (= op #x37))
           (let* ([r1 (decode-u32-leb128 bv (+ pos 1))]
                  [r2 (decode-u32-leb128 bv (+ pos 1 (cdr r1)))])
             (+ pos 1 (cdr r1) (cdr r2)))]
          [else (+ pos 1)]))))

  ;; Skip from pos to the matching else or end at this nesting level
  ;; Returns new pos pointing PAST the else/end byte
  (define (skip-to-else-or-end bv pos len)
    (let loop ([pos pos] [depth 0])
      (if (>= pos len)
        (error 'execute-func "unterminated if block")
        (let ([op (bytevector-u8-ref bv pos)])
          (cond
            [(= op #x0B) ; end
             (if (= depth 0)
               (cons 'end (+ pos 1))
               (loop (+ pos 1) (- depth 1)))]
            [(= op #x05) ; else
             (if (= depth 0)
               (cons 'else (+ pos 1))
               (loop (+ pos 1) depth))]
            [(or (= op #x02) (= op #x03) (= op #x04)) ; block/loop/if
             (loop (+ pos 2) (+ depth 1))]
            [else
             (loop (skip-instr bv pos len) depth)])))))

  ;; Skip from current pos to matching end (past else branch)
  (define (skip-to-end bv pos len)
    (let loop ([pos pos] [depth 0])
      (if (>= pos len)
        (error 'execute-func "unterminated block")
        (let ([op (bytevector-u8-ref bv pos)])
          (cond
            [(= op #x0B) ; end
             (if (= depth 0)
               (+ pos 1)
               (loop (+ pos 1) (- depth 1)))]
            [(or (= op #x02) (= op #x03) (= op #x04)) ; block/loop/if
             (loop (+ pos 2) (+ depth 1))]
            [else
             (loop (skip-instr bv pos len) depth)])))))

  ;;; ========== Interpreter ==========

  (define (i32 n)
    (let ([n32 (bitwise-and n #xFFFFFFFF)])
      (if (>= n32 #x80000000)
        (- n32 #x100000000)
        n32)))

  (define (execute-func code-bv locals-vec all-funcs memory globals)
    (let ([stack '()]
          [pos 0]
          [len (bytevector-length code-bv)]
          [result 0]
          [done #f])

      (define (push! v) (set! stack (cons v stack)))
      (define (pop!)
        (when (null? stack)
          (error 'execute-func "stack underflow"))
        (let ([v (car stack)])
          (set! stack (cdr stack))
          v))
      (define (peek)
        (when (null? stack)
          (error 'execute-func "stack underflow"))
        (car stack))

      (let step ()
        (when (and (not done) (< pos len))
          (let ([op (bytevector-u8-ref code-bv pos)])
            (set! pos (+ pos 1))
            (cond
              ;; nop
              [(= op #x01) (step)]

              ;; end (of function)
              [(= op #x0B)
               (set! result (if (null? stack) 0 (pop!)))
               (set! done #t)]

              ;; unreachable
              [(= op #x00)
               (error 'execute-func "unreachable")]

              ;; i32.const
              [(= op #x41)
               (let* ([r (decode-i32-leb128 code-bv pos)])
                 (set! pos (+ pos (cdr r)))
                 (push! (i32 (car r)))
                 (step))]

              ;; local.get
              [(= op #x20)
               (let* ([r (decode-u32-leb128 code-bv pos)])
                 (set! pos (+ pos (cdr r)))
                 (push! (vector-ref locals-vec (car r)))
                 (step))]

              ;; local.set
              [(= op #x21)
               (let* ([r (decode-u32-leb128 code-bv pos)])
                 (set! pos (+ pos (cdr r)))
                 (vector-set! locals-vec (car r) (pop!))
                 (step))]

              ;; local.tee
              [(= op #x22)
               (let* ([r (decode-u32-leb128 code-bv pos)])
                 (set! pos (+ pos (cdr r)))
                 (vector-set! locals-vec (car r) (peek))
                 (step))]

              ;; if
              [(= op #x04)
               ;; read block type (skip it)
               (set! pos (+ pos 1))
               (let ([cond-val (pop!)])
                 (if (not (= cond-val 0))
                   ;; true: execute then-branch, skip else-branch at end
                   (begin
                     ;; We just continue executing; at the 'else' opcode we skip to end
                     (step)
                     ;; After step returns (recursive), we're past the if/else/end
                     )
                   ;; false: skip to else or end
                   (let* ([r (skip-to-else-or-end code-bv pos len)]
                          [kind (car r)]
                          [new-pos (cdr r)])
                     (set! pos new-pos)
                     (if (eq? kind 'else)
                       (step)  ; execute else-branch
                       ;; kind = 'end, nothing left to do for this if
                       (begin
                         (push! 0)  ; default value (shouldn't happen in well-formed code)
                         (step))))
                   ))]

              ;; else (we get here only when in the true branch)
              [(= op #x05)
               ;; Skip to matching end
               (set! pos (skip-to-end code-bv pos len))
               (step)]

              ;; drop
              [(= op #x1A)
               (pop!)
               (step)]

              ;; i32 arithmetic
              [(= op #x6A) ; i32.add
               (let* ([b (pop!)] [a (pop!)])
                 (push! (i32 (+ a b)))
                 (step))]
              [(= op #x6B) ; i32.sub
               (let* ([b (pop!)] [a (pop!)])
                 (push! (i32 (- a b)))
                 (step))]
              [(= op #x6C) ; i32.mul
               (let* ([b (pop!)] [a (pop!)])
                 (push! (i32 (* a b)))
                 (step))]
              [(= op #x6D) ; i32.div_s
               (let* ([b (pop!)] [a (pop!)])
                 (when (= b 0)
                   (error 'execute-func "integer divide by zero"))
                 (push! (i32 (truncate (/ a b))))
                 (step))]
              [(= op #x6F) ; i32.rem_s
               (let* ([b (pop!)] [a (pop!)])
                 (when (= b 0)
                   (error 'execute-func "remainder by zero"))
                 (push! (i32 (remainder a b)))
                 (step))]

              ;; i32 comparisons
              [(= op #x46) ; i32.eq
               (let* ([b (pop!)] [a (pop!)])
                 (push! (if (= a b) 1 0))
                 (step))]
              [(= op #x47) ; i32.ne
               (let* ([b (pop!)] [a (pop!)])
                 (push! (if (= a b) 0 1))
                 (step))]
              [(= op #x48) ; i32.lt_s
               (let* ([b (pop!)] [a (pop!)])
                 (push! (if (< a b) 1 0))
                 (step))]
              [(= op #x4A) ; i32.gt_s
               (let* ([b (pop!)] [a (pop!)])
                 (push! (if (> a b) 1 0))
                 (step))]
              [(= op #x4C) ; i32.le_s
               (let* ([b (pop!)] [a (pop!)])
                 (push! (if (<= a b) 1 0))
                 (step))]
              [(= op #x4E) ; i32.ge_s
               (let* ([b (pop!)] [a (pop!)])
                 (push! (if (>= a b) 1 0))
                 (step))]
              [(= op #x45) ; i32.eqz
               (let ([a (pop!)])
                 (push! (if (= a 0) 1 0))
                 (step))]

              ;; call
              [(= op #x10)
               (let* ([r (decode-u32-leb128 code-bv pos)])
                 (set! pos (+ pos (cdr r)))
                 (let* ([fidx (car r)]
                        [fi (vector-ref all-funcs fidx)]
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
                   (push! (execute-func code new-lv all-funcs memory globals))
                   (step)))]

              ;; return
              [(= op #x0F)
               (set! result (if (null? stack) 0 (pop!)))
               (set! done #t)]

              ;; global.get
              [(= op #x23)
               (let* ([r (decode-u32-leb128 code-bv pos)])
                 (set! pos (+ pos (cdr r)))
                 (push! (vector-ref globals (car r)))
                 (step))]

              ;; global.set
              [(= op #x24)
               (let* ([r (decode-u32-leb128 code-bv pos)])
                 (set! pos (+ pos (cdr r)))
                 (vector-set! globals (car r) (pop!))
                 (step))]

              ;; unknown
              [else
               (error 'execute-func
                      (string-append "unsupported opcode: 0x"
                                     (number->string op 16)))]))))

      result))

  ;;; ========== Instantiation ==========

  (define (wasm-store-instantiate store decoded-mod)
    (let* ([secs (decoded-module-sections decoded-mod)]
           [type-sec  (assv wasm-section-type secs)]
           [func-sec  (assv wasm-section-function secs)]
           [exp-sec   (assv wasm-section-export secs)]
           [code-sec  (assv wasm-section-code secs)]
           [types     (if type-sec (parse-type-section (cdr type-sec)) '())]
           [tidxs     (if func-sec (parse-function-section (cdr func-sec)) '())]
           [exports   (if exp-sec  (parse-export-section (cdr exp-sec)) '())]
           [codes     (if code-sec (parse-code-section (cdr code-sec)) '())]
           [nfuncs    (length tidxs)]
           [all-funcs (make-vector nfuncs #f)])

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

      (let* ([memory  (make-bytevector 65536 0)]
             [globals (make-vector 0)]
             [exp-alist
              (map (lambda (e)
                     (let ([name (car e)] [kind (cadr e)] [idx (caddr e)])
                       (cons name (list kind idx all-funcs memory globals))))
                   exports)])

        (make-wasm-instance exp-alist all-funcs memory globals))))

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
             [all-funcs (caddr v)]
             [memory (cadddr v)]
             [globals (car (cddddr v))])
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
          (execute-func code lv all-funcs memory globals)))))

  (define (wasm-runtime-memory-ref rt offset)
    (bytevector-u8-ref (wasm-instance-memory (wasm-runtime-instance rt)) offset))

  (define (wasm-runtime-memory-set! rt offset val)
    (bytevector-u8-set! (wasm-instance-memory (wasm-runtime-instance rt)) offset val))

  (define (wasm-runtime-global-ref rt idx)
    (vector-ref (wasm-instance-globals (wasm-runtime-instance rt)) idx))

  (define (wasm-runtime-global-set! rt idx val)
    (vector-set! (wasm-instance-globals (wasm-runtime-instance rt)) idx val))

  (define (wasm-run-start inst) #f)

) ;; end library
