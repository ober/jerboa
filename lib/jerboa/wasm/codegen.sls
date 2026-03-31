#!chezscheme
;;; (jerboa wasm codegen) -- WebAssembly code generation
;;;
;;; Compiles a Scheme subset to WASM binary format.
;;; Supports all four numeric types (i32, i64, f32, f64), structured control
;;; flow (block, loop, br, br_if, while), memory operations, globals,
;;; tables, data/element/start sections, and import function calls.
;;;
;;; Source language forms:
;;;   (define (name params...) body...)           -> function (default i32)
;;;   (define (name (p type)...) -> rtype body..) -> typed function
;;;   (define-global name type mut? init)         -> global variable
;;;   (define-memory min [max])                   -> linear memory
;;;   (define-table min [max])                    -> function table
;;;   (define-import mod name (ptypes) (rtypes))  -> import
;;;   (define-data offset bytes)                  -> data segment
;;;   (define-element offset funcs)               -> element segment
;;;   (start name)                                -> start function
;;;
;;; Expression forms:
;;;   42, 3.14                -> numeric constants (int→i32, float→f64)
;;;   (i32 n), (i64 n)       -> explicit int const
;;;   (f32 x), (f64 x)       -> explicit float const
;;;   symbol                  -> local.get
;;;   (set! sym val)          -> local.set
;;;   (+ a b), etc.           -> i32 arithmetic (default)
;;;   (i64.add a b), etc.     -> typed arithmetic
;;;   (if test then else)     -> if/else
;;;   (cond cls... [else e])  -> nested ifs
;;;   (when test body...)     -> if without else
;;;   (unless test body...)   -> negated when
;;;   (and a b), (or a b)     -> short-circuit
;;;   (not a)                 -> i32.eqz
;;;   (begin e1 ... en)       -> sequential
;;;   (let ([x e]...) body)   -> locals
;;;   (block body...)         -> WASM block
;;;   (loop body...)          -> WASM loop
;;;   (br depth)              -> branch
;;;   (br-if cond depth)      -> conditional branch
;;;   (while test body...)    -> loop with br_if
;;;   (return val)            -> return
;;;   (i32.load addr)         -> memory load (also i64/f32/f64 variants)
;;;   (i32.store addr val)    -> memory store
;;;   (memory.size)           -> current pages
;;;   (memory.grow n)         -> grow memory
;;;   (global.get idx)        -> read global
;;;   (global.set idx val)    -> write global
;;;   (select a b cond)       -> conditional select
;;;   (drop expr)             -> evaluate and discard
;;;   (call name args...)     -> direct call by name
;;;   (call-indirect ti args) -> indirect call via table
;;;
;;; Post-MVP:
;;;   (i32.trunc_sat_f32_s v) -> saturating float-to-int (8 variants)
;;;   (memory.fill d v n)     -> fill memory range
;;;   (memory.copy d s n)     -> copy memory range
;;;   (memory.init seg d s n) -> init from data segment
;;;   (data.drop seg)         -> drop data segment
;;;   (table.get ti idx)      -> get table element
;;;   (table.set ti idx val)  -> set table element
;;;   (table.size ti)         -> table size
;;;   (table.grow ti init n)  -> grow table
;;;   (table.fill ti i v n)   -> fill table range
;;;   (ref.null type)         -> push null reference
;;;   (ref.is_null expr)      -> test for null
;;;   (ref.func idx)          -> push function reference
;;;   (return-call f args...) -> tail call
;;;   (throw tag args...)     -> throw exception
;;;   (struct.new ti flds...) -> create GC struct
;;;   (struct.get ti fi ref)  -> read struct field
;;;   (struct.set ti fi r v)  -> write struct field
;;;   (array.new ti init n)   -> create GC array
;;;   (array.new_fixed ti ..) -> fixed-size array
;;;   (array.get ti arr idx)  -> read array element
;;;   (array.set ti a i v)    -> write array element
;;;   (array.len arr)         -> array length
;;;   (ref.i31 v)             -> wrap to i31ref
;;;   (i31.get_s v)           -> unwrap i31 signed
;;;   (i31.get_u v)           -> unwrap i31 unsigned
;;;   (ref.test ti expr)      -> type test
;;;   (ref.cast ti expr)      -> type cast
;;;
;;; Module declarations:
;;;   (define-tag type-idx)   -> exception tag

(library (jerboa wasm codegen)
  (export
    ;; WASM module structure
    make-wasm-module wasm-module? wasm-module-encode
    wasm-module-types wasm-module-imports wasm-module-functions
    wasm-module-exports wasm-module-memories wasm-module-globals
    wasm-module-tables wasm-module-data-segments wasm-module-elements
    wasm-module-start
    wasm-module-add-type! wasm-module-add-import!
    wasm-module-add-function! wasm-module-add-export!
    wasm-module-add-memory! wasm-module-add-global!
    wasm-module-add-table! wasm-module-add-data!
    wasm-module-add-element! wasm-module-set-start!
    wasm-module-add-tag! wasm-module-tags
    ;; WASM function
    make-wasm-func wasm-func? wasm-func-locals wasm-func-body
    ;; WASM type (function signature)
    make-wasm-type wasm-type-params wasm-type-results
    ;; WASM import descriptor
    make-wasm-import wasm-import-module wasm-import-name wasm-import-desc
    ;; WASM export descriptor
    make-wasm-export wasm-export-name wasm-export-kind wasm-export-index
    wasm-export-func wasm-export-memory wasm-export-table wasm-export-global
    ;; Compilation
    compile-expr compile-program scheme->wasm-type
    ;; Compile context
    make-compile-context context-add-local! context-local-index
    context-add-func! context-func-index
    context-block-depth context-push-block! context-pop-block!)

  (import (except (chezscheme) compile-program)
          (jerboa wasm format))

  ;;; ========== WASM type (function signature) ==========

  (define-record-type wasm-type
    (fields params results)
    (protocol (lambda (new)
      (lambda (params results) (new params results)))))

  ;;; ========== WASM import ==========

  (define-record-type wasm-import
    (fields module name desc))

  ;;; ========== WASM export ==========

  (define-record-type wasm-export
    (fields name kind index))

  (define (wasm-export-func name index)
    (make-wasm-export name 0 index))  ; kind 0 = function

  (define (wasm-export-memory name index)
    (make-wasm-export name 2 index))  ; kind 2 = memory

  (define (wasm-export-table name index)
    (make-wasm-export name 1 index))  ; kind 1 = table

  (define (wasm-export-global name index)
    (make-wasm-export name 3 index))  ; kind 3 = global

  ;;; ========== WASM function ==========

  (define-record-type wasm-func
    (fields locals body))

  ;;; ========== WASM module ==========

  (define-record-type wasm-module
    (fields
      (mutable types)          ; list of wasm-type
      (mutable imports)        ; list of wasm-import
      (mutable functions)      ; list of (type-index . wasm-func)
      (mutable exports)        ; list of wasm-export
      (mutable memories)       ; list of (min . max-or-#f)
      (mutable globals)        ; list of (type mut? init-expr)
      (mutable tables)         ; list of (type min . max-or-#f)
      (mutable data-segments)  ; list of (mem-idx offset-expr bytes)
      (mutable elements)       ; list of (table-idx offset-expr func-indices)
      (mutable start)          ; #f or function index
      (mutable tags))          ; list of type-idx (exception tag types)
    (protocol (lambda (new)
      (lambda () (new '() '() '() '() '() '() '() '() '() #f '())))))

  (define (wasm-module-add-type! mod type)
    (wasm-module-types-set! mod (append (wasm-module-types mod) (list type))))

  (define (wasm-module-add-import! mod imp)
    (wasm-module-imports-set! mod (append (wasm-module-imports mod) (list imp))))

  (define (wasm-module-add-function! mod type-idx func)
    (wasm-module-functions-set! mod
      (append (wasm-module-functions mod) (list (cons type-idx func)))))

  (define (wasm-module-add-export! mod exp)
    (wasm-module-exports-set! mod (append (wasm-module-exports mod) (list exp))))

  (define (wasm-module-add-memory! mod min-pages max-pages)
    (wasm-module-memories-set! mod
      (append (wasm-module-memories mod) (list (cons min-pages max-pages)))))

  (define (wasm-module-add-global! mod type mut? init-bv)
    (wasm-module-globals-set! mod
      (append (wasm-module-globals mod) (list (list type mut? init-bv)))))

  (define (wasm-module-add-table! mod elem-type min-elems max-elems)
    (wasm-module-tables-set! mod
      (append (wasm-module-tables mod) (list (list elem-type min-elems max-elems)))))

  (define (wasm-module-add-data! mod mem-idx offset-bv data-bv)
    (wasm-module-data-segments-set! mod
      (append (wasm-module-data-segments mod) (list (list mem-idx offset-bv data-bv)))))

  (define (wasm-module-add-element! mod table-idx offset-bv func-indices)
    (wasm-module-elements-set! mod
      (append (wasm-module-elements mod)
              (list (list table-idx offset-bv func-indices)))))

  (define (wasm-module-set-start! mod func-idx)
    (wasm-module-start-set! mod func-idx))

  (define (wasm-module-add-tag! mod type-idx)
    (wasm-module-tags-set! mod (append (wasm-module-tags mod) (list type-idx))))

  ;;; ========== Binary encoding helpers ==========

  (define (bv-concat . bvs)
    (let ([total (apply + (map bytevector-length bvs))])
      (let ([result (make-bytevector total)])
        (let loop ([bvs bvs] [offset 0])
          (if (null? bvs)
            result
            (let* ([bv (car bvs)]
                   [len (bytevector-length bv)])
              (bytevector-copy! bv 0 result offset len)
              (loop (cdr bvs) (+ offset len))))))))

  (define (bv-concat-list lst)
    (if (null? lst) (bytevector) (apply bv-concat lst)))

  (define (encode-vec items encode-item)
    (let ([encoded (map encode-item items)])
      (bv-concat (encode-u32-leb128 (length items))
                 (bv-concat-list encoded))))

  (define (encode-section id content)
    (let ([len-bv (encode-u32-leb128 (bytevector-length content))])
      (bv-concat (bytevector id) len-bv content)))

  ;;; ========== Section encoding ==========

  (define (encode-wasm-type type)
    (bv-concat
      (bytevector #x60)
      (encode-vec (wasm-type-params type) (lambda (t) (bytevector t)))
      (encode-vec (wasm-type-results type) (lambda (t) (bytevector t)))))

  (define (encode-type-section types)
    (if (null? types) (bytevector)
      (encode-section wasm-section-type (encode-vec types encode-wasm-type))))

  (define (encode-wasm-import imp)
    (let ([desc (wasm-import-desc imp)])
      (bv-concat
        (encode-string (wasm-import-module imp))
        (encode-string (wasm-import-name imp))
        (cond
          [(and (pair? desc) (= (car desc) 0))
           (bv-concat (bytevector #x00) (encode-u32-leb128 (cdr desc)))]
          [(and (pair? desc) (= (car desc) 1))
           ;; table import: type + limits
           (let ([tbl (cdr desc)])
             (bv-concat (bytevector #x01 (car tbl))
                        (encode-limits (cadr tbl) (caddr tbl))))]
          [(and (pair? desc) (= (car desc) 2))
           ;; memory import: limits
           (let ([mem (cdr desc)])
             (bv-concat (bytevector #x02) (encode-limits (car mem) (cadr mem))))]
          [(and (pair? desc) (= (car desc) 3))
           ;; global import: type + mut
           (let ([gl (cdr desc)])
             (bv-concat (bytevector #x03) (bytevector (car gl) (if (cadr gl) 1 0))))]
          [else
           (error 'encode-wasm-import "unsupported import descriptor" desc)]))))

  (define (encode-limits min max)
    (if max
      (bv-concat (bytevector #x01) (encode-u32-leb128 min) (encode-u32-leb128 max))
      (bv-concat (bytevector #x00) (encode-u32-leb128 min))))

  (define (encode-import-section imports)
    (if (null? imports) (bytevector)
      (encode-section wasm-section-import (encode-vec imports encode-wasm-import))))

  (define (encode-function-section functions)
    (if (null? functions) (bytevector)
      (encode-section wasm-section-function
        (encode-vec functions (lambda (f) (encode-u32-leb128 (car f)))))))

  (define (encode-table-section tables)
    (if (null? tables) (bytevector)
      (encode-section wasm-section-table
        (encode-vec tables
          (lambda (t)
            (let ([elem-type (car t)] [min (cadr t)] [max (caddr t)])
              (bv-concat (bytevector elem-type) (encode-limits min max))))))))

  (define (encode-memory-section memories)
    (if (null? memories) (bytevector)
      (encode-section wasm-section-memory
        (encode-vec memories
          (lambda (m) (encode-limits (car m) (cdr m)))))))

  (define (encode-global-section globals)
    (if (null? globals) (bytevector)
      (encode-section wasm-section-global
        (encode-vec globals
          (lambda (g)
            (let ([type (car g)] [mut? (cadr g)] [init (caddr g)])
              (bv-concat (bytevector type (if mut? 1 0))
                         init
                         (bytevector wasm-opcode-end))))))))

  (define (encode-wasm-export exp)
    (bv-concat
      (encode-string (wasm-export-name exp))
      (bytevector (wasm-export-kind exp))
      (encode-u32-leb128 (wasm-export-index exp))))

  (define (encode-export-section exports)
    (if (null? exports) (bytevector)
      (encode-section wasm-section-export (encode-vec exports encode-wasm-export))))

  (define (encode-start-section start-idx)
    (if (not start-idx) (bytevector)
      (encode-section wasm-section-start (encode-u32-leb128 start-idx))))

  (define (encode-element-section elements)
    (if (null? elements) (bytevector)
      (encode-section wasm-section-element
        (encode-vec elements
          (lambda (e)
            (let ([tidx (car e)] [offset-bv (cadr e)] [func-idxs (caddr e)])
              (bv-concat
                (encode-u32-leb128 tidx)
                offset-bv
                (bytevector wasm-opcode-end)
                (encode-vec func-idxs
                  (lambda (fi) (encode-u32-leb128 fi))))))))))

  (define (encode-locals locals)
    (if (null? locals)
      (encode-u32-leb128 0)
      (let loop ([locals locals] [groups '()] [cur-type (car locals)] [count 0])
        (cond
          [(null? locals)
           (let ([final-groups (reverse (cons (cons count cur-type) groups))])
             (encode-vec final-groups
               (lambda (g)
                 (bv-concat (encode-u32-leb128 (car g)) (bytevector (cdr g))))))]
          [(= (car locals) cur-type)
           (loop (cdr locals) groups cur-type (+ count 1))]
          [else
           (loop (cdr locals)
                 (cons (cons count cur-type) groups)
                 (car locals)
                 1)]))))

  (define (encode-func-body func)
    (let* ([locals-bv (encode-locals (wasm-func-locals func))]
           [body-bv (wasm-func-body func)]
           [content (bv-concat locals-bv body-bv)]
           [size-bv (encode-u32-leb128 (bytevector-length content))])
      (bv-concat size-bv content)))

  (define (encode-code-section functions)
    (if (null? functions) (bytevector)
      (encode-section wasm-section-code
        (encode-vec functions (lambda (f) (encode-func-body (cdr f)))))))

  (define (encode-data-section data-segments)
    (if (null? data-segments) (bytevector)
      (encode-section wasm-section-data
        (encode-vec data-segments
          (lambda (d)
            (let ([midx (car d)] [offset-bv (cadr d)] [data (caddr d)])
              (bv-concat
                (encode-u32-leb128 midx)
                offset-bv
                (bytevector wasm-opcode-end)
                (encode-u32-leb128 (bytevector-length data))
                data)))))))

  ;;; ========== Module encoding ==========

  ;; Encode tag section (section 13) for exception handling
  (define (encode-tag-section tags)
    (if (null? tags)
      (bytevector)
      (let ([content
             (bv-concat
               (encode-u32-leb128 (length tags))
               (bv-concat-list
                 (map (lambda (tidx)
                        (bv-concat (bytevector #x00)  ; attribute: exception
                                   (encode-u32-leb128 tidx)))
                      tags)))])
        (bv-concat (bytevector wasm-section-tag)
                   (encode-u32-leb128 (bytevector-length content))
                   content))))

  (define (wasm-module-encode mod)
    (bv-concat
      wasm-magic
      wasm-version
      (encode-type-section (wasm-module-types mod))
      (encode-import-section (wasm-module-imports mod))
      (encode-function-section (wasm-module-functions mod))
      (encode-table-section (wasm-module-tables mod))
      (encode-memory-section (wasm-module-memories mod))
      (encode-global-section (wasm-module-globals mod))
      (encode-export-section (wasm-module-exports mod))
      (encode-start-section (wasm-module-start mod))
      (encode-element-section (wasm-module-elements mod))
      (encode-code-section (wasm-module-functions mod))
      (encode-data-section (wasm-module-data-segments mod))
      (encode-tag-section (wasm-module-tags mod))))

  ;;; ========== Type conversion ==========

  (define (scheme->wasm-type sym)
    (case sym
      [(i32 integer fixnum) wasm-type-i32]
      [(i64 long)           wasm-type-i64]
      [(f32 float single)   wasm-type-f32]
      [(f64 double)         wasm-type-f64]
      [(void)               wasm-type-void]
      [else wasm-type-i32]))

  ;;; ========== Compile context ==========

  (define-record-type compile-context
    (fields
      (mutable locals)       ; alist: (name . (index . type))
      (mutable local-count)
      (mutable funcs)        ; alist: (name . index)
      (mutable blocks)       ; list of block-kind symbols for br depth
      (mutable return-type)) ; wasm-type for current function
    (protocol (lambda (new)
      (lambda () (new '() 0 '() '() wasm-type-i32)))))

  (define (context-add-local! ctx name . type-args)
    (let ([type (if (null? type-args) wasm-type-i32 (car type-args))]
          [idx (compile-context-local-count ctx)])
      (compile-context-locals-set! ctx
        (cons (cons name (cons idx type)) (compile-context-locals ctx)))
      (compile-context-local-count-set! ctx (+ idx 1))
      idx))

  (define (context-local-index ctx name)
    (let ([entry (assq name (compile-context-locals ctx))])
      (if entry (cadr entry)
        (error 'context-local-index "unbound variable" name))))

  (define (context-local-type ctx name)
    (let ([entry (assq name (compile-context-locals ctx))])
      (if entry (cddr entry) wasm-type-i32)))

  (define (context-add-func! ctx name)
    (let ([idx (length (compile-context-funcs ctx))])
      (compile-context-funcs-set! ctx
        (cons (cons name idx) (compile-context-funcs ctx)))
      idx))

  (define (context-func-index ctx name)
    (let ([entry (assq name (compile-context-funcs ctx))])
      (if entry (cdr entry)
        (error 'context-func-index "unbound function" name))))

  (define (context-block-depth ctx)
    (length (compile-context-blocks ctx)))

  (define (context-push-block! ctx kind)
    (compile-context-blocks-set! ctx
      (cons kind (compile-context-blocks ctx))))

  (define (context-pop-block! ctx)
    (compile-context-blocks-set! ctx
      (cdr (compile-context-blocks ctx))))

  ;;; ========== Expression compiler ==========

  ;; Compile let bindings
  ;; NOTE: Must process bindings left-to-right with explicit sequencing.
  ;; Chez's map does not guarantee evaluation order, so we use a loop.
  (define (compile-let bindings body ctx)
    (let ([binding-code
           (let loop ([bs bindings] [acc '()])
             (if (null? bs)
               (bv-concat-list (reverse acc))
               (let* ([name (caar bs)]
                      [expr (cadar bs)]
                      [eval-bv (compile-expr expr ctx)]
                      [idx (context-add-local! ctx name)]
                      [code (bv-concat eval-bv
                              (bytevector wasm-opcode-local-set)
                              (encode-u32-leb128 idx))])
                 (loop (cdr bs) (cons code acc)))))])
      (bv-concat binding-code
        (compile-body body ctx))))

  ;; Does the expression produce no value on the stack (void)?
  (define (void-expr? expr)
    (and (pair? expr)
         (or (memq (car expr)
                   '(set! while when unless i32.store i64.store f32.store f64.store
                     i32.store8 i32.store16 global.set drop
                     memory.fill memory.copy memory.init data.drop
                     table.set table.fill struct.set array.set throw))
             ;; let/let*/begin whose last body expr is void
             (and (memq (car expr) '(let let* begin))
                  (let ([body (case (car expr)
                                [(begin) (cdr expr)]
                                [(let let*) (cddr expr)])])
                    (and (pair? body)
                         (void-expr? (car (last-pair body))))))
             ;; if/else where both branches are void
             (and (eq? (car expr) 'if)
                  (>= (length (cdr expr)) 3)
                  (void-expr? (caddr expr))
                  (void-expr? (cadddr expr))))))

  ;; Compile a body (list of expressions, result is last)
  (define (compile-body exprs ctx)
    (cond
      [(null? exprs) (bytevector wasm-opcode-nop)]
      [(null? (cdr exprs)) (compile-expr (car exprs) ctx)]
      [else
       (bv-concat-list
         (let loop ([es exprs])
           (if (null? (cdr es))
             (list (compile-expr (car es) ctx))
             (cons (let ([code (compile-expr (car es) ctx)])
                     (if (void-expr? (car es))
                       code
                       (bv-concat code (bytevector wasm-opcode-drop))))
                   (loop (cdr es))))))]))

  ;; Binary operation
  (define (compile-binop args ctx opcode)
    (bv-concat
      (compile-expr (car args) ctx)
      (compile-expr (cadr args) ctx)
      (bytevector opcode)))

  ;; Unary operation
  (define (compile-unop args ctx opcode)
    (bv-concat
      (compile-expr (car args) ctx)
      (bytevector opcode)))

  ;; Memory load: (type.load addr) or (type.load offset align addr)
  (define (compile-mem-load args ctx opcode)
    (let ([align 2] [offset 0] [addr-expr (car args)])
      (bv-concat
        (compile-expr addr-expr ctx)
        (bytevector opcode)
        (encode-u32-leb128 align)
        (encode-u32-leb128 offset))))

  ;; Memory store: (type.store addr val)
  (define (compile-mem-store args ctx opcode)
    (let ([align 2] [offset 0])
      (bv-concat
        (compile-expr (car args) ctx)
        (compile-expr (cadr args) ctx)
        (bytevector opcode)
        (encode-u32-leb128 align)
        (encode-u32-leb128 offset))))

  ;; compile-expr: Scheme expression -> bytevector of WASM instructions
  (define (compile-expr expr ctx)
    (cond
      ;; Integer literal -> i32.const
      [(and (integer? expr) (exact? expr))
       (bv-concat (bytevector wasm-opcode-i32-const)
                  (encode-i32-leb128 expr))]

      ;; Float literal -> f64.const
      [(flonum? expr)
       (bv-concat (bytevector wasm-opcode-f64-const)
                  (encode-f64 expr))]

      ;; Boolean -> i32.const 0/1
      [(boolean? expr)
       (bv-concat (bytevector wasm-opcode-i32-const)
                  (encode-i32-leb128 (if expr 1 0)))]

      ;; Symbol -> local.get
      [(symbol? expr)
       (bv-concat (bytevector wasm-opcode-local-get)
                  (encode-u32-leb128 (context-local-index ctx expr)))]

      ;; Compound forms
      [(pair? expr)
       (let ([head (car expr)] [args (cdr expr)])
         (case head
           ;; -- Explicit typed constants --
           [(i32)
            (bv-concat (bytevector wasm-opcode-i32-const)
                       (encode-i32-leb128 (car args)))]
           [(i64)
            (bv-concat (bytevector wasm-opcode-i64-const)
                       (encode-i64-leb128 (car args)))]
           [(f32)
            (bv-concat (bytevector wasm-opcode-f32-const)
                       (encode-f32 (exact->inexact (car args))))]
           [(f64)
            (bv-concat (bytevector wasm-opcode-f64-const)
                       (encode-f64 (exact->inexact (car args))))]

           ;; -- Control flow --
           [(begin)
            (if (null? args)
              (bytevector wasm-opcode-nop)
              (compile-body args ctx))]

           [(if)
            (let ([test (car args)]
                  [then (cadr args)]
                  [else-part (if (null? (cddr args)) #f (caddr args))])
              (if else-part
                ;; if/else: void when both branches are void, i32 otherwise
                (let ([block-type (if (and (void-expr? then) (void-expr? else-part))
                                    wasm-type-void
                                    wasm-type-i32)])
                  (bv-concat
                    (compile-expr test ctx)
                    (bytevector wasm-opcode-if block-type)
                    (compile-expr then ctx)
                    (bytevector wasm-opcode-else)
                    (compile-expr else-part ctx)
                    (bytevector wasm-opcode-end)))
                ;; No else: void block type
                (bv-concat
                  (compile-expr test ctx)
                  (bytevector wasm-opcode-if wasm-type-void)
                  (compile-expr then ctx)
                  (bytevector wasm-opcode-end))))]

           [(cond)
            (compile-cond args ctx)]

           [(when)
            (bv-concat
              (compile-expr (car args) ctx)
              (bytevector wasm-opcode-if wasm-type-void)
              (compile-body (cdr args) ctx)
              (bytevector wasm-opcode-end))]

           [(unless)
            (bv-concat
              (compile-expr (car args) ctx)
              (bytevector wasm-opcode-i32-eqz)
              (bytevector wasm-opcode-if wasm-type-void)
              (compile-body (cdr args) ctx)
              (bytevector wasm-opcode-end))]

           [(and)
            (if (null? args)
              (bv-concat (bytevector wasm-opcode-i32-const)
                         (encode-i32-leb128 1))
              (if (null? (cdr args))
                (compile-expr (car args) ctx)
                ;; (and a b) → (if a b 0)
                (bv-concat
                  (compile-expr (car args) ctx)
                  (bytevector wasm-opcode-if wasm-type-i32)
                  (compile-expr (cons 'and (cdr args)) ctx)
                  (bytevector wasm-opcode-else)
                  (bytevector wasm-opcode-i32-const) (encode-i32-leb128 0)
                  (bytevector wasm-opcode-end))))]

           [(or)
            (if (null? args)
              (bv-concat (bytevector wasm-opcode-i32-const)
                         (encode-i32-leb128 0))
              (if (null? (cdr args))
                (compile-expr (car args) ctx)
                ;; (or a b) → (if a 1 b)
                (bv-concat
                  (compile-expr (car args) ctx)
                  (bytevector wasm-opcode-if wasm-type-i32)
                  (bytevector wasm-opcode-i32-const) (encode-i32-leb128 1)
                  (bytevector wasm-opcode-else)
                  (compile-expr (cons 'or (cdr args)) ctx)
                  (bytevector wasm-opcode-end))))]

           [(not zero?)
            (compile-unop args ctx wasm-opcode-i32-eqz)]

           ;; -- Let bindings --
           [(let)  (compile-let (car args) (cdr args) ctx)]
           [(let*)
            (if (null? (car args))
              (compile-body (cdr args) ctx)
              (compile-let (list (caar args))
                (list (cons 'let* (cons (cdar args) (cdr args)))) ctx))]

           ;; -- Set! --
           [(set!)
            (let ([name (car args)] [val (cadr args)])
              (bv-concat (compile-expr val ctx)
                (bytevector wasm-opcode-local-set)
                (encode-u32-leb128 (context-local-index ctx name))))]

           ;; -- Structured control --
           [(block)
            (context-push-block! ctx 'block)
            (let ([body-bv (compile-body args ctx)])
              (context-pop-block! ctx)
              (bv-concat
                (bytevector wasm-opcode-block wasm-type-void)
                body-bv
                (bytevector wasm-opcode-end)))]

           [(loop)
            (context-push-block! ctx 'loop)
            (let ([body-bv (compile-body args ctx)])
              (context-pop-block! ctx)
              (bv-concat
                (bytevector wasm-opcode-loop wasm-type-void)
                body-bv
                (bytevector wasm-opcode-end)))]

           [(br)
            (bv-concat
              (bytevector wasm-opcode-br)
              (encode-u32-leb128 (car args)))]

           [(br-if)
            (bv-concat
              (compile-expr (car args) ctx)
              (bytevector wasm-opcode-br-if)
              (encode-u32-leb128 (cadr args)))]

           [(while)
            ;; (while test body...) →
            ;; (block (loop (br_if (eqz test) 1) body... (br 0)))
            (context-push-block! ctx 'block)
            (context-push-block! ctx 'loop)
            (let ([test-bv (compile-expr (car args) ctx)]
                  [body-bv (compile-body (cdr args) ctx)])
              (context-pop-block! ctx)
              (context-pop-block! ctx)
              (bv-concat
                (bytevector wasm-opcode-block wasm-type-void)
                (bytevector wasm-opcode-loop wasm-type-void)
                ;; Test: if false, break outer block
                test-bv
                (bytevector wasm-opcode-i32-eqz)
                (bytevector wasm-opcode-br-if)
                (encode-u32-leb128 1)  ; br 1 = exit outer block
                ;; Body
                body-bv
                ;; Continue loop
                (bytevector wasm-opcode-br)
                (encode-u32-leb128 0)  ; br 0 = continue loop
                (bytevector wasm-opcode-end)   ; end loop
                (bytevector wasm-opcode-end)))] ; end block

           [(return)
            (if (null? args)
              (bytevector wasm-opcode-return)
              (bv-concat (compile-expr (car args) ctx)
                         (bytevector wasm-opcode-return)))]

           [(unreachable)
            (bytevector wasm-opcode-unreachable)]

           ;; -- i32 arithmetic (default for Scheme ops) --
           [(+)        (compile-binop args ctx wasm-opcode-i32-add)]
           [(-)
            (if (null? (cdr args))
              ;; Unary minus: (- x) → (0 - x)
              (bv-concat
                (bytevector wasm-opcode-i32-const) (encode-i32-leb128 0)
                (compile-expr (car args) ctx)
                (bytevector wasm-opcode-i32-sub))
              (compile-binop args ctx wasm-opcode-i32-sub))]
           [(*)        (compile-binop args ctx wasm-opcode-i32-mul)]
           [(quotient) (compile-binop args ctx wasm-opcode-i32-div-s)]
           [(remainder)(compile-binop args ctx wasm-opcode-i32-rem-s)]

           ;; -- i32 bitwise --
           [(bitwise-and logand)  (compile-binop args ctx wasm-opcode-i32-and)]
           [(bitwise-or  logor)   (compile-binop args ctx wasm-opcode-i32-or)]
           [(bitwise-xor logxor)  (compile-binop args ctx wasm-opcode-i32-xor)]
           [(shl)                  (compile-binop args ctx wasm-opcode-i32-shl)]
           [(shr)                  (compile-binop args ctx wasm-opcode-i32-shr-s)]
           [(shr-u)                (compile-binop args ctx wasm-opcode-i32-shr-u)]
           [(rotl)                 (compile-binop args ctx wasm-opcode-i32-rotl)]
           [(rotr)                 (compile-binop args ctx wasm-opcode-i32-rotr)]
           [(clz)                  (compile-unop args ctx wasm-opcode-i32-clz)]
           [(ctz)                  (compile-unop args ctx wasm-opcode-i32-ctz)]
           [(popcnt)               (compile-unop args ctx wasm-opcode-i32-popcnt)]

           ;; -- i32 comparisons --
           [(=  i32.eq)  (compile-binop args ctx wasm-opcode-i32-eq)]
           [(!= i32.ne)  (compile-binop args ctx wasm-opcode-i32-ne)]
           [(<)          (compile-binop args ctx wasm-opcode-i32-lt-s)]
           [(>)          (compile-binop args ctx wasm-opcode-i32-gt-s)]
           [(<=)         (compile-binop args ctx wasm-opcode-i32-le-s)]
           [(>=)         (compile-binop args ctx wasm-opcode-i32-ge-s)]

           ;; -- Explicit typed i32 ops --
           [(i32.add)    (compile-binop args ctx wasm-opcode-i32-add)]
           [(i32.sub)    (compile-binop args ctx wasm-opcode-i32-sub)]
           [(i32.mul)    (compile-binop args ctx wasm-opcode-i32-mul)]
           [(i32.div_s)  (compile-binop args ctx wasm-opcode-i32-div-s)]
           [(i32.div_u)  (compile-binop args ctx wasm-opcode-i32-div-u)]
           [(i32.rem_s)  (compile-binop args ctx wasm-opcode-i32-rem-s)]
           [(i32.rem_u)  (compile-binop args ctx wasm-opcode-i32-rem-u)]
           [(i32.and)    (compile-binop args ctx wasm-opcode-i32-and)]
           [(i32.or)     (compile-binop args ctx wasm-opcode-i32-or)]
           [(i32.xor)    (compile-binop args ctx wasm-opcode-i32-xor)]
           [(i32.shl)    (compile-binop args ctx wasm-opcode-i32-shl)]
           [(i32.shr_s)  (compile-binop args ctx wasm-opcode-i32-shr-s)]
           [(i32.shr_u)  (compile-binop args ctx wasm-opcode-i32-shr-u)]
           [(i32.rotl)   (compile-binop args ctx wasm-opcode-i32-rotl)]
           [(i32.rotr)   (compile-binop args ctx wasm-opcode-i32-rotr)]
           [(i32.clz)    (compile-unop args ctx wasm-opcode-i32-clz)]
           [(i32.ctz)    (compile-unop args ctx wasm-opcode-i32-ctz)]
           [(i32.popcnt) (compile-unop args ctx wasm-opcode-i32-popcnt)]
           [(i32.eqz)    (compile-unop args ctx wasm-opcode-i32-eqz)]
           [(i32.lt_s)   (compile-binop args ctx wasm-opcode-i32-lt-s)]
           [(i32.lt_u)   (compile-binop args ctx wasm-opcode-i32-lt-u)]
           [(i32.gt_s)   (compile-binop args ctx wasm-opcode-i32-gt-s)]
           [(i32.gt_u)   (compile-binop args ctx wasm-opcode-i32-gt-u)]
           [(i32.le_s)   (compile-binop args ctx wasm-opcode-i32-le-s)]
           [(i32.le_u)   (compile-binop args ctx wasm-opcode-i32-le-u)]
           [(i32.ge_s)   (compile-binop args ctx wasm-opcode-i32-ge-s)]
           [(i32.ge_u)   (compile-binop args ctx wasm-opcode-i32-ge-u)]
           [(i32.wrap_i64)    (compile-unop args ctx wasm-opcode-i32-wrap-i64)]

           ;; -- i64 ops --
           [(i64.add)    (compile-binop args ctx wasm-opcode-i64-add)]
           [(i64.sub)    (compile-binop args ctx wasm-opcode-i64-sub)]
           [(i64.mul)    (compile-binop args ctx wasm-opcode-i64-mul)]
           [(i64.div_s)  (compile-binop args ctx wasm-opcode-i64-div-s)]
           [(i64.div_u)  (compile-binop args ctx wasm-opcode-i64-div-u)]
           [(i64.rem_s)  (compile-binop args ctx wasm-opcode-i64-rem-s)]
           [(i64.rem_u)  (compile-binop args ctx wasm-opcode-i64-rem-u)]
           [(i64.and)    (compile-binop args ctx wasm-opcode-i64-and)]
           [(i64.or)     (compile-binop args ctx wasm-opcode-i64-or)]
           [(i64.xor)    (compile-binop args ctx wasm-opcode-i64-xor)]
           [(i64.shl)    (compile-binop args ctx wasm-opcode-i64-shl)]
           [(i64.shr_s)  (compile-binop args ctx wasm-opcode-i64-shr-s)]
           [(i64.shr_u)  (compile-binop args ctx wasm-opcode-i64-shr-u)]
           [(i64.rotl)   (compile-binop args ctx wasm-opcode-i64-rotl)]
           [(i64.rotr)   (compile-binop args ctx wasm-opcode-i64-rotr)]
           [(i64.clz)    (compile-unop args ctx wasm-opcode-i64-clz)]
           [(i64.ctz)    (compile-unop args ctx wasm-opcode-i64-ctz)]
           [(i64.popcnt) (compile-unop args ctx wasm-opcode-i64-popcnt)]
           [(i64.eqz)    (compile-unop args ctx wasm-opcode-i64-eqz)]
           [(i64.eq)     (compile-binop args ctx wasm-opcode-i64-eq)]
           [(i64.ne)     (compile-binop args ctx wasm-opcode-i64-ne)]
           [(i64.lt_s)   (compile-binop args ctx wasm-opcode-i64-lt-s)]
           [(i64.lt_u)   (compile-binop args ctx wasm-opcode-i64-lt-u)]
           [(i64.gt_s)   (compile-binop args ctx wasm-opcode-i64-gt-s)]
           [(i64.gt_u)   (compile-binop args ctx wasm-opcode-i64-gt-u)]
           [(i64.le_s)   (compile-binop args ctx wasm-opcode-i64-le-s)]
           [(i64.le_u)   (compile-binop args ctx wasm-opcode-i64-le-u)]
           [(i64.ge_s)   (compile-binop args ctx wasm-opcode-i64-ge-s)]
           [(i64.ge_u)   (compile-binop args ctx wasm-opcode-i64-ge-u)]
           [(i64.extend_i32_s) (compile-unop args ctx wasm-opcode-i64-extend-i32-s)]
           [(i64.extend_i32_u) (compile-unop args ctx wasm-opcode-i64-extend-i32-u)]

           ;; -- f32 ops --
           [(f32.add)    (compile-binop args ctx wasm-opcode-f32-add)]
           [(f32.sub)    (compile-binop args ctx wasm-opcode-f32-sub)]
           [(f32.mul)    (compile-binop args ctx wasm-opcode-f32-mul)]
           [(f32.div)    (compile-binop args ctx wasm-opcode-f32-div)]
           [(f32.min)    (compile-binop args ctx wasm-opcode-f32-min)]
           [(f32.max)    (compile-binop args ctx wasm-opcode-f32-max)]
           [(f32.abs)    (compile-unop args ctx wasm-opcode-f32-abs)]
           [(f32.neg)    (compile-unop args ctx wasm-opcode-f32-neg)]
           [(f32.sqrt)   (compile-unop args ctx wasm-opcode-f32-sqrt)]
           [(f32.ceil)   (compile-unop args ctx wasm-opcode-f32-ceil)]
           [(f32.floor)  (compile-unop args ctx wasm-opcode-f32-floor)]
           [(f32.trunc)  (compile-unop args ctx wasm-opcode-f32-trunc)]
           [(f32.nearest)(compile-unop args ctx wasm-opcode-f32-nearest)]
           [(f32.copysign)(compile-binop args ctx wasm-opcode-f32-copysign)]
           [(f32.eq)     (compile-binop args ctx wasm-opcode-f32-eq)]
           [(f32.ne)     (compile-binop args ctx wasm-opcode-f32-ne)]
           [(f32.lt)     (compile-binop args ctx wasm-opcode-f32-lt)]
           [(f32.gt)     (compile-binop args ctx wasm-opcode-f32-gt)]
           [(f32.le)     (compile-binop args ctx wasm-opcode-f32-le)]
           [(f32.ge)     (compile-binop args ctx wasm-opcode-f32-ge)]
           [(f32.demote_f64)     (compile-unop args ctx wasm-opcode-f32-demote-f64)]
           [(f32.convert_i32_s)  (compile-unop args ctx wasm-opcode-f32-convert-i32-s)]
           [(f32.convert_i32_u)  (compile-unop args ctx wasm-opcode-f32-convert-i32-u)]
           [(f32.convert_i64_s)  (compile-unop args ctx wasm-opcode-f32-convert-i64-s)]
           [(f32.convert_i64_u)  (compile-unop args ctx wasm-opcode-f32-convert-i64-u)]

           ;; -- f64 ops --
           [(f64.add)    (compile-binop args ctx wasm-opcode-f64-add)]
           [(f64.sub)    (compile-binop args ctx wasm-opcode-f64-sub)]
           [(f64.mul)    (compile-binop args ctx wasm-opcode-f64-mul)]
           [(f64.div)    (compile-binop args ctx wasm-opcode-f64-div)]
           [(f64.min)    (compile-binop args ctx wasm-opcode-f64-min)]
           [(f64.max)    (compile-binop args ctx wasm-opcode-f64-max)]
           [(f64.abs)    (compile-unop args ctx wasm-opcode-f64-abs)]
           [(f64.neg)    (compile-unop args ctx wasm-opcode-f64-neg)]
           [(f64.sqrt)   (compile-unop args ctx wasm-opcode-f64-sqrt)]
           [(f64.ceil)   (compile-unop args ctx wasm-opcode-f64-ceil)]
           [(f64.floor)  (compile-unop args ctx wasm-opcode-f64-floor)]
           [(f64.trunc)  (compile-unop args ctx wasm-opcode-f64-trunc)]
           [(f64.nearest)(compile-unop args ctx wasm-opcode-f64-nearest)]
           [(f64.copysign)(compile-binop args ctx wasm-opcode-f64-copysign)]
           [(f64.eq)     (compile-binop args ctx wasm-opcode-f64-eq)]
           [(f64.ne)     (compile-binop args ctx wasm-opcode-f64-ne)]
           [(f64.lt)     (compile-binop args ctx wasm-opcode-f64-lt)]
           [(f64.gt)     (compile-binop args ctx wasm-opcode-f64-gt)]
           [(f64.le)     (compile-binop args ctx wasm-opcode-f64-le)]
           [(f64.ge)     (compile-binop args ctx wasm-opcode-f64-ge)]
           [(f64.promote_f32)    (compile-unop args ctx wasm-opcode-f64-promote-f32)]
           [(f64.convert_i32_s)  (compile-unop args ctx wasm-opcode-f64-convert-i32-s)]
           [(f64.convert_i32_u)  (compile-unop args ctx wasm-opcode-f64-convert-i32-u)]
           [(f64.convert_i64_s)  (compile-unop args ctx wasm-opcode-f64-convert-i64-s)]
           [(f64.convert_i64_u)  (compile-unop args ctx wasm-opcode-f64-convert-i64-u)]

           ;; -- Reinterpret --
           [(i32.reinterpret_f32) (compile-unop args ctx wasm-opcode-i32-reinterpret-f32)]
           [(i64.reinterpret_f64) (compile-unop args ctx wasm-opcode-i64-reinterpret-f64)]
           [(f32.reinterpret_i32) (compile-unop args ctx wasm-opcode-f32-reinterpret-i32)]
           [(f64.reinterpret_i64) (compile-unop args ctx wasm-opcode-f64-reinterpret-i64)]

           ;; -- Truncation --
           [(i32.trunc_f32_s) (compile-unop args ctx wasm-opcode-i32-trunc-f32-s)]
           [(i32.trunc_f32_u) (compile-unop args ctx wasm-opcode-i32-trunc-f32-u)]
           [(i32.trunc_f64_s) (compile-unop args ctx wasm-opcode-i32-trunc-f64-s)]
           [(i32.trunc_f64_u) (compile-unop args ctx wasm-opcode-i32-trunc-f64-u)]
           [(i64.trunc_f32_s) (compile-unop args ctx wasm-opcode-i64-trunc-f32-s)]
           [(i64.trunc_f32_u) (compile-unop args ctx wasm-opcode-i64-trunc-f32-u)]
           [(i64.trunc_f64_s) (compile-unop args ctx wasm-opcode-i64-trunc-f64-s)]
           [(i64.trunc_f64_u) (compile-unop args ctx wasm-opcode-i64-trunc-f64-u)]

           ;; -- Memory operations --
           [(i32.load)   (compile-mem-load args ctx wasm-opcode-i32-load)]
           [(i64.load)   (compile-mem-load args ctx wasm-opcode-i64-load)]
           [(f32.load)   (compile-mem-load args ctx wasm-opcode-f32-load)]
           [(f64.load)   (compile-mem-load args ctx wasm-opcode-f64-load)]
           [(i32.load8_s)  (compile-mem-load args ctx wasm-opcode-i32-load8-s)]
           [(i32.load8_u)  (compile-mem-load args ctx wasm-opcode-i32-load8-u)]
           [(i32.load16_s) (compile-mem-load args ctx wasm-opcode-i32-load16-s)]
           [(i32.load16_u) (compile-mem-load args ctx wasm-opcode-i32-load16-u)]
           [(i32.store)  (compile-mem-store args ctx wasm-opcode-i32-store)]
           [(i64.store)  (compile-mem-store args ctx wasm-opcode-i64-store)]
           [(f32.store)  (compile-mem-store args ctx wasm-opcode-f32-store)]
           [(f64.store)  (compile-mem-store args ctx wasm-opcode-f64-store)]
           [(i32.store8)  (compile-mem-store args ctx wasm-opcode-i32-store8)]
           [(i32.store16) (compile-mem-store args ctx wasm-opcode-i32-store16)]

           [(memory.size)
            (bv-concat (bytevector wasm-opcode-memory-size) (bytevector #x00))]
           [(memory.grow)
            (bv-concat (compile-expr (car args) ctx)
                       (bytevector wasm-opcode-memory-grow) (bytevector #x00))]

           ;; -- Global access --
           [(global.get)
            (bv-concat (bytevector wasm-opcode-global-get)
                       (encode-u32-leb128 (car args)))]
           [(global.set)
            (bv-concat (compile-expr (cadr args) ctx)
                       (bytevector wasm-opcode-global-set)
                       (encode-u32-leb128 (car args)))]

           ;; -- Parametric --
           [(select)
            (bv-concat
              (compile-expr (car args) ctx)    ; val1
              (compile-expr (cadr args) ctx)   ; val2
              (compile-expr (caddr args) ctx)  ; condition
              (bytevector wasm-opcode-select))]

           [(drop)
            (bv-concat (compile-expr (car args) ctx)
                       (bytevector wasm-opcode-drop))]

           ;; =============== POST-MVP EXPRESSION FORMS ===============

           ;; -- Saturating float-to-int conversions --
           ;; (i32.trunc_sat_f32_s expr) etc.
           [(i32.trunc_sat_f32_s)
            (bv-concat (compile-expr (car args) ctx) (bytevector wasm-prefix-fc) (encode-u32-leb128 0))]
           [(i32.trunc_sat_f32_u)
            (bv-concat (compile-expr (car args) ctx) (bytevector wasm-prefix-fc) (encode-u32-leb128 1))]
           [(i32.trunc_sat_f64_s)
            (bv-concat (compile-expr (car args) ctx) (bytevector wasm-prefix-fc) (encode-u32-leb128 2))]
           [(i32.trunc_sat_f64_u)
            (bv-concat (compile-expr (car args) ctx) (bytevector wasm-prefix-fc) (encode-u32-leb128 3))]
           [(i64.trunc_sat_f32_s)
            (bv-concat (compile-expr (car args) ctx) (bytevector wasm-prefix-fc) (encode-u32-leb128 4))]
           [(i64.trunc_sat_f32_u)
            (bv-concat (compile-expr (car args) ctx) (bytevector wasm-prefix-fc) (encode-u32-leb128 5))]
           [(i64.trunc_sat_f64_s)
            (bv-concat (compile-expr (car args) ctx) (bytevector wasm-prefix-fc) (encode-u32-leb128 6))]
           [(i64.trunc_sat_f64_u)
            (bv-concat (compile-expr (car args) ctx) (bytevector wasm-prefix-fc) (encode-u32-leb128 7))]

           ;; -- Bulk memory operations --
           ;; (memory.fill dest val count)
           [(memory.fill)
            (bv-concat (compile-expr (car args) ctx)
                       (compile-expr (cadr args) ctx)
                       (compile-expr (caddr args) ctx)
                       (bytevector wasm-prefix-fc) (encode-u32-leb128 11)
                       (bytevector #x00))]  ; reserved byte
           ;; (memory.copy dest src count)
           [(memory.copy)
            (bv-concat (compile-expr (car args) ctx)
                       (compile-expr (cadr args) ctx)
                       (compile-expr (caddr args) ctx)
                       (bytevector wasm-prefix-fc) (encode-u32-leb128 10)
                       (bytevector #x00 #x00))]  ; 2 reserved bytes
           ;; (memory.init seg-idx dest src count)
           [(memory.init)
            (bv-concat (compile-expr (cadr args) ctx)     ; dest
                       (compile-expr (caddr args) ctx)    ; src
                       (compile-expr (cadddr args) ctx)   ; count
                       (bytevector wasm-prefix-fc) (encode-u32-leb128 8)
                       (encode-u32-leb128 (car args))     ; seg-idx
                       (bytevector #x00))]                 ; reserved
           ;; (data.drop seg-idx)
           [(data.drop)
            (bv-concat (bytevector wasm-prefix-fc) (encode-u32-leb128 9)
                       (encode-u32-leb128 (car args)))]

           ;; -- Table operations --
           ;; (table.get table-idx idx-expr)
           [(table.get)
            (bv-concat (compile-expr (cadr args) ctx)
                       (bytevector wasm-opcode-table-get) (encode-u32-leb128 (car args)))]
           ;; (table.set table-idx idx-expr val-expr)
           [(table.set)
            (bv-concat (compile-expr (cadr args) ctx)
                       (compile-expr (caddr args) ctx)
                       (bytevector wasm-opcode-table-set) (encode-u32-leb128 (car args)))]
           ;; (table.size table-idx)
           [(table.size)
            (bv-concat (bytevector wasm-prefix-fc) (encode-u32-leb128 16)
                       (encode-u32-leb128 (car args)))]
           ;; (table.grow table-idx init-expr count-expr)
           [(table.grow)
            (bv-concat (compile-expr (cadr args) ctx)
                       (compile-expr (caddr args) ctx)
                       (bytevector wasm-prefix-fc) (encode-u32-leb128 15)
                       (encode-u32-leb128 (car args)))]
           ;; (table.fill table-idx start-expr val-expr count-expr)
           [(table.fill)
            (bv-concat (compile-expr (cadr args) ctx)
                       (compile-expr (caddr args) ctx)
                       (compile-expr (cadddr args) ctx)
                       (bytevector wasm-prefix-fc) (encode-u32-leb128 17)
                       (encode-u32-leb128 (car args)))]

           ;; -- Reference types --
           ;; (ref.null type)  -- type is a numeric type code
           [(ref.null)
            (bv-concat (bytevector wasm-opcode-ref-null) (encode-u32-leb128 (car args)))]
           ;; (ref.is_null expr)
           [(ref.is_null)
            (bv-concat (compile-expr (car args) ctx) (bytevector wasm-opcode-ref-is-null))]
           ;; (ref.func func-idx)
           [(ref.func)
            (bv-concat (bytevector wasm-opcode-ref-func) (encode-u32-leb128 (car args)))]

           ;; -- Tail calls --
           ;; (return-call name args...)
           [(return-call)
            (let ([fidx (context-func-index ctx (car args))])
              (bv-concat
                (bv-concat-list (map (lambda (a) (compile-expr a ctx)) (cdr args)))
                (bytevector wasm-opcode-return-call)
                (encode-u32-leb128 fidx)))]
           ;; (return-call-indirect type-idx args... table-idx-expr)
           [(return-call-indirect)
            (let ([type-idx (car args)]
                  [call-args (cdr args)])
              (bv-concat
                (bv-concat-list (map (lambda (a) (compile-expr a ctx)) call-args))
                (bytevector wasm-opcode-return-call-indirect)
                (encode-u32-leb128 type-idx)
                (encode-u32-leb128 0)))]  ; table 0

           ;; -- Exception handling --
           ;; (throw tag-idx args...)
           [(throw)
            (bv-concat
              (bv-concat-list (map (lambda (a) (compile-expr a ctx)) (cdr args)))
              (bytevector wasm-opcode-throw) (encode-u32-leb128 (car args)))]

           ;; -- GC: struct operations --
           ;; (struct.new type-idx field-exprs...)
           [(struct.new)
            (bv-concat
              (bv-concat-list (map (lambda (a) (compile-expr a ctx)) (cdr args)))
              (bytevector wasm-prefix-fb) (encode-u32-leb128 wasm-fb-struct-new)
              (encode-u32-leb128 (car args)))]
           ;; (struct.new_default type-idx)
           [(struct.new_default)
            (bv-concat (bytevector wasm-prefix-fb) (encode-u32-leb128 wasm-fb-struct-new-default)
                       (encode-u32-leb128 (car args)))]
           ;; (struct.get type-idx field-idx ref-expr)
           [(struct.get)
            (bv-concat (compile-expr (caddr args) ctx)
                       (bytevector wasm-prefix-fb) (encode-u32-leb128 wasm-fb-struct-get)
                       (encode-u32-leb128 (car args)) (encode-u32-leb128 (cadr args)))]
           ;; (struct.set type-idx field-idx ref-expr val-expr)
           [(struct.set)
            (bv-concat (compile-expr (caddr args) ctx)
                       (compile-expr (cadddr args) ctx)
                       (bytevector wasm-prefix-fb) (encode-u32-leb128 wasm-fb-struct-set)
                       (encode-u32-leb128 (car args)) (encode-u32-leb128 (cadr args)))]

           ;; -- GC: array operations --
           ;; (array.new type-idx init-expr count-expr)
           [(array.new)
            (bv-concat (compile-expr (cadr args) ctx)
                       (compile-expr (caddr args) ctx)
                       (bytevector wasm-prefix-fb) (encode-u32-leb128 wasm-fb-array-new)
                       (encode-u32-leb128 (car args)))]
           ;; (array.new_default type-idx count-expr)
           [(array.new_default)
            (bv-concat (compile-expr (cadr args) ctx)
                       (bytevector wasm-prefix-fb) (encode-u32-leb128 wasm-fb-array-new-default)
                       (encode-u32-leb128 (car args)))]
           ;; (array.new_fixed type-idx elem-exprs...)
           [(array.new_fixed)
            (let ([elems (cdr args)])
              (bv-concat
                (bv-concat-list (map (lambda (a) (compile-expr a ctx)) elems))
                (bytevector wasm-prefix-fb) (encode-u32-leb128 wasm-fb-array-new-fixed)
                (encode-u32-leb128 (car args)) (encode-u32-leb128 (length elems))))]
           ;; (array.get type-idx arr-expr idx-expr)
           [(array.get)
            (bv-concat (compile-expr (cadr args) ctx)
                       (compile-expr (caddr args) ctx)
                       (bytevector wasm-prefix-fb) (encode-u32-leb128 wasm-fb-array-get)
                       (encode-u32-leb128 (car args)))]
           ;; (array.set type-idx arr-expr idx-expr val-expr)
           [(array.set)
            (bv-concat (compile-expr (cadr args) ctx)
                       (compile-expr (caddr args) ctx)
                       (compile-expr (cadddr args) ctx)
                       (bytevector wasm-prefix-fb) (encode-u32-leb128 wasm-fb-array-set)
                       (encode-u32-leb128 (car args)))]
           ;; (array.len arr-expr)
           [(array.len)
            (bv-concat (compile-expr (car args) ctx)
                       (bytevector wasm-prefix-fb) (encode-u32-leb128 wasm-fb-array-len))]

           ;; -- GC: i31 operations --
           ;; (ref.i31 expr)
           [(ref.i31)
            (bv-concat (compile-expr (car args) ctx)
                       (bytevector wasm-prefix-fb) (encode-u32-leb128 wasm-fb-ref-i31))]
           ;; (i31.get_s expr)
           [(i31.get_s)
            (bv-concat (compile-expr (car args) ctx)
                       (bytevector wasm-prefix-fb) (encode-u32-leb128 wasm-fb-i31-get-s))]
           ;; (i31.get_u expr)
           [(i31.get_u)
            (bv-concat (compile-expr (car args) ctx)
                       (bytevector wasm-prefix-fb) (encode-u32-leb128 wasm-fb-i31-get-u))]

           ;; -- GC: ref.test / ref.cast --
           ;; (ref.test type-idx expr)
           [(ref.test)
            (bv-concat (compile-expr (cadr args) ctx)
                       (bytevector wasm-prefix-fb) (encode-u32-leb128 wasm-fb-ref-test)
                       (encode-u32-leb128 (car args)))]
           ;; (ref.cast type-idx expr)
           [(ref.cast)
            (bv-concat (compile-expr (cadr args) ctx)
                       (bytevector wasm-prefix-fb) (encode-u32-leb128 wasm-fb-ref-cast)
                       (encode-u32-leb128 (car args)))]

           ;; -- Indirect call --
           [(call-indirect)
            ;; (call-indirect type-idx arg1 ... argn table-idx-expr)
            (let ([type-idx (car args)]
                  [call-args (cdr args)])
              (bv-concat
                (bv-concat-list (map (lambda (a) (compile-expr a ctx)) call-args))
                (bytevector wasm-opcode-call-indirect)
                (encode-u32-leb128 type-idx)
                (encode-u32-leb128 0)))] ; table 0

           ;; -- Function call (symbol in head position) --
           [else
            (if (symbol? head)
              (let ([fidx (context-func-index ctx head)])
                (bv-concat
                  (bv-concat-list (map (lambda (a) (compile-expr a ctx)) args))
                  (bytevector wasm-opcode-call)
                  (encode-u32-leb128 fidx)))
              (error 'compile-expr "unknown form" expr))]))]

      [else (error 'compile-expr "unsupported expression" expr)]))

  ;; Compile a cond form
  (define (compile-cond clauses ctx)
    (cond
      [(null? clauses)
       ;; No matching clause → 0
       (bv-concat (bytevector wasm-opcode-i32-const) (encode-i32-leb128 0))]
      [(and (pair? (car clauses)) (eq? (caar clauses) 'else))
       (compile-body (cdar clauses) ctx)]
      [else
       (let ([test (caar clauses)]
             [body (cdar clauses)])
         (bv-concat
           (compile-expr test ctx)
           (bytevector wasm-opcode-if wasm-type-i32)
           (compile-body body ctx)
           (bytevector wasm-opcode-else)
           (compile-cond (cdr clauses) ctx)
           (bytevector wasm-opcode-end)))]))

  ;;; ========== Program compiler ==========

  ;; Parse a function parameter: symbol or (name type)
  (define (parse-param p)
    (if (pair? p)
      (cons (car p) (scheme->wasm-type (cadr p)))
      (cons p wasm-type-i32)))

  ;; Parse return type from define signature
  ;; Returns (values return-type body-forms)
  (define (parse-return-type body)
    (if (and (pair? body) (pair? (car body)) (eq? (caar body) '->))
      (values (scheme->wasm-type (cadar body)) (cdr body))
      (values wasm-type-i32 body)))

  ;; compile-program: list of top-level forms -> binary WASM bytevector
  (define (compile-program forms)
    (let ([mod (make-wasm-module)]
          [global-ctx (make-compile-context)]
          [import-count 0]
          [func-names '()]
          [func-sigs '()])

      ;; Pass 0: Process imports, memory, table, global declarations
      (for-each
        (lambda (form)
          (when (pair? form)
            (case (car form)
              [(define-import)
               ;; (define-import mod name (param-types) (result-types))
               (let* ([mod-name (cadr form)]
                      [fn-name (caddr form)]
                      [ptypes (map scheme->wasm-type (cadddr form))]
                      [rtypes (map scheme->wasm-type (car (cddddr form)))]
                      [type (make-wasm-type ptypes rtypes)]
                      [type-idx (length (wasm-module-types mod))])
                 (wasm-module-add-type! mod type)
                 (wasm-module-add-import! mod
                   (make-wasm-import mod-name (symbol->string fn-name)
                     (cons 0 type-idx)))
                 (context-add-func! global-ctx fn-name)
                 (set! import-count (+ import-count 1)))]
              [(define-memory)
               (let ([min (cadr form)]
                     [max (if (null? (cddr form)) #f (caddr form))])
                 (wasm-module-add-memory! mod min max))]
              [(define-table)
               (let ([min (cadr form)]
                     [max (if (null? (cddr form)) #f (caddr form))])
                 (wasm-module-add-table! mod wasm-type-funcref min max))]
              [(define-global)
               ;; (define-global name type mut? init)
               (let* ([gname (cadr form)]
                      [gtype (scheme->wasm-type (caddr form))]
                      [mut? (cadddr form)]
                      [init-val (car (cddddr form))]
                      [init-bv (case gtype
                                 [(#x7F) (bv-concat (bytevector wasm-opcode-i32-const)
                                                    (encode-i32-leb128 init-val))]
                                 [(#x7E) (bv-concat (bytevector wasm-opcode-i64-const)
                                                    (encode-i64-leb128 init-val))]
                                 [(#x7D) (bv-concat (bytevector wasm-opcode-f32-const)
                                                    (encode-f32 (exact->inexact init-val)))]
                                 [(#x7C) (bv-concat (bytevector wasm-opcode-f64-const)
                                                    (encode-f64 (exact->inexact init-val)))]
                                 [else (error 'compile-program "unsupported global type" gtype)])])
                 (wasm-module-add-global! mod gtype mut? init-bv))]
              [(define-tag)
               ;; (define-tag type-idx)
               (wasm-module-add-tag! mod (cadr form))]
              [else (void)])))
        forms)

      ;; Pass 1: Register function names (for mutual recursion)
      (for-each
        (lambda (form)
          (when (and (pair? form) (eq? (car form) 'define))
            (let ([sig (cadr form)])
              (when (pair? sig)
                (let* ([name (car sig)]
                       [raw-params (cdr sig)]
                       [body-forms (cddr form)]
                       ;; Filter out -> return type annotation from params
                       [params (let loop ([ps raw-params])
                                 (cond [(null? ps) '()]
                                       [(eq? (car ps) '->) '()]
                                       [else (cons (parse-param (car ps))
                                                   (loop (cdr ps)))]))]
                       ;; Check both param list and body forms for -> rtype
                       [rtype (let loop ([ps raw-params])
                                (cond [(null? ps)
                                       ;; Not in params — check body forms
                                       (if (and (pair? body-forms) (eq? (car body-forms) '->))
                                         (scheme->wasm-type (cadr body-forms))
                                         wasm-type-i32)]
                                      [(eq? (car ps) '->) (scheme->wasm-type (cadr ps))]
                                      [else (loop (cdr ps))]))])
                  (context-add-func! global-ctx name)
                  (set! func-names (cons name func-names))
                  (set! func-sigs (cons (cons params rtype) func-sigs)))))))
        forms)
      (set! func-names (reverse func-names))
      (set! func-sigs (reverse func-sigs))

      ;; Pass 2: Compile function bodies
      (for-each
        (lambda (form)
          (when (and (pair? form) (eq? (car form) 'define))
            (let* ([sig (cadr form)]
                   [raw-body (cddr form)]
                   ;; Strip -> return type annotation from body forms
                   [body-forms (if (and (pair? raw-body) (eq? (car raw-body) '->))
                                 (cddr raw-body)  ; skip -> and type
                                 raw-body)])
              (when (pair? sig)
                (let* ([name (car sig)]
                       [sig-entry (let loop ([ns func-names] [ss func-sigs])
                                    (if (eq? (car ns) name) (car ss)
                                      (loop (cdr ns) (cdr ss))))]
                       [params (car sig-entry)]
                       [rtype (cdr sig-entry)]
                       ;; Create per-function context
                       [ctx (make-compile-context)]
                       [_ (compile-context-funcs-set! ctx
                            (compile-context-funcs global-ctx))]
                       [_ (compile-context-return-type-set! ctx rtype)]
                       ;; Add params as locals
                       [_ (for-each
                            (lambda (p) (context-add-local! ctx (car p) (cdr p)))
                            params)]
                       ;; Compile body
                       [body-bv (compile-body body-forms ctx)]
                       [full-body (bv-concat body-bv (bytevector wasm-opcode-end))]
                       ;; Collect extra locals (beyond params)
                       [all-locals (compile-context-locals ctx)]
                       [let-locals
                        (filter (lambda (entry)
                                  (>= (cadr entry) (length params)))
                                all-locals)]
                       [local-types (map cddr let-locals)]
                       [func (make-wasm-func local-types full-body)]
                       ;; Type signature
                       [param-types (map cdr params)]
                       [result-types (if (= rtype wasm-type-void) '() (list rtype))]
                       [type-idx (length (wasm-module-types mod))]
                       [type (make-wasm-type param-types result-types)])

                  (wasm-module-add-type! mod type)
                  (wasm-module-add-function! mod type-idx func))))))
        forms)

      ;; Add exports for all user-defined functions
      (let ([funcs (reverse (compile-context-funcs global-ctx))])
        (for-each
          (lambda (pair)
            (let ([idx (cdr pair)])
              (when (>= idx import-count)
                (wasm-module-add-export! mod
                  (wasm-export-func (symbol->string (car pair)) idx)))))
          funcs))

      ;; Auto-export memory as "memory" (WASM convention for host access)
      (unless (null? (wasm-module-memories mod))
        (wasm-module-add-export! mod (wasm-export-memory "memory" 0)))

      ;; Process data segments
      (for-each
        (lambda (form)
          (when (and (pair? form) (eq? (car form) 'define-data))
            (let* ([offset (cadr form)]
                   [data (caddr form)]
                   [offset-bv (bv-concat (bytevector wasm-opcode-i32-const)
                                         (encode-i32-leb128 offset))]
                   [data-bv (cond
                              [(bytevector? data) data]
                              [(string? data) (string->utf8 data)]
                              [else (error 'compile-program
                                      "data must be bytevector or string" data)])])
              (wasm-module-add-data! mod 0 offset-bv data-bv))))
        forms)

      ;; Process element segments
      (for-each
        (lambda (form)
          (when (and (pair? form) (eq? (car form) 'define-element))
            (let* ([offset (cadr form)]
                   [func-names-list (caddr form)]
                   [offset-bv (bv-concat (bytevector wasm-opcode-i32-const)
                                         (encode-i32-leb128 offset))]
                   [func-idxs (map (lambda (n) (context-func-index global-ctx n))
                                   func-names-list)])
              (wasm-module-add-element! mod 0 offset-bv func-idxs))))
        forms)

      ;; Process start section
      (for-each
        (lambda (form)
          (when (and (pair? form) (eq? (car form) 'start))
            (wasm-module-set-start! mod
              (context-func-index global-ctx (cadr form)))))
        forms)

      (wasm-module-encode mod)))

) ;; end library
