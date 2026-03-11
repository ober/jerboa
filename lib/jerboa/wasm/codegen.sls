#!chezscheme
;;; (jerboa wasm codegen) -- WebAssembly code generation
;;;
;;; Compiles a restricted subset of Scheme to WASM binary format.
;;; Supported subset: i32-only, no closures, no heap allocation.
;;;
;;; (define (name args...) body)  -> WASM function
;;; (let ([x e] ...) body)        -> locals
;;; (if test then else)           -> WASM if/else
;;; (+ a b), (- a b), etc.        -> i32 arithmetic
;;; (= a b), (< a b), (> a b)    -> i32 comparisons
;;; integer literals               -> i32.const
;;; variable references            -> local.get
;;; (begin e1 ... en)              -> sequential, result is last

(library (jerboa wasm codegen)
  (export
    ;; WASM module structure
    make-wasm-module wasm-module? wasm-module-encode
    wasm-module-types wasm-module-imports wasm-module-functions
    wasm-module-exports wasm-module-memories wasm-module-globals
    wasm-module-add-type! wasm-module-add-import!
    wasm-module-add-function! wasm-module-add-export!
    wasm-module-add-memory! wasm-module-add-global!
    ;; WASM function
    make-wasm-func wasm-func? wasm-func-locals wasm-func-body
    ;; WASM type (function signature)
    make-wasm-type wasm-type-params wasm-type-results
    ;; WASM import descriptor
    make-wasm-import wasm-import-module wasm-import-name wasm-import-desc
    ;; WASM export descriptor
    make-wasm-export wasm-export-name wasm-export-kind wasm-export-index
    wasm-export-func wasm-export-memory
    ;; Compilation
    compile-expr compile-program scheme->wasm-type
    ;; Compile context
    make-compile-context context-add-local! context-local-index
    context-add-func! context-func-index)

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

  ;;; ========== WASM function ==========

  (define-record-type wasm-func
    (fields locals body))

  ;;; ========== WASM module ==========

  (define-record-type wasm-module
    (fields
      (mutable types)      ; list of wasm-type
      (mutable imports)    ; list of wasm-import
      (mutable functions)  ; list of (type-index . wasm-func)
      (mutable exports)    ; list of wasm-export
      (mutable memories)   ; list of (min . max-or-#f)
      (mutable globals))   ; list of (type mut? init-expr)
    (protocol (lambda (new)
      (lambda () (new '() '() '() '() '() '())))))

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

  ;;; ========== Binary encoding helpers ==========

  ;; Concatenate list of bytevectors
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
    (apply bv-concat lst))

  ;; Encode a vector (list of items) with count prefix
  (define (encode-vec items encode-item)
    (let ([encoded (map encode-item items)])
      (bv-concat
        (encode-u32-leb128 (length items))
        (bv-concat-list encoded))))

  ;; Encode a WASM section: section-id + length + content
  (define (encode-section id content)
    (let ([len-bv (encode-u32-leb128 (bytevector-length content))])
      (bv-concat
        (bytevector id)
        len-bv
        content)))

  ;;; ========== Type section encoding ==========

  (define (encode-wasm-type type)
    ;; func type: 0x60 params results
    (bv-concat
      (bytevector #x60)
      (encode-vec (wasm-type-params type) (lambda (t) (bytevector t)))
      (encode-vec (wasm-type-results type) (lambda (t) (bytevector t)))))

  (define (encode-type-section types)
    (if (null? types)
      (bytevector)
      (encode-section wasm-section-type
        (encode-vec types encode-wasm-type))))

  ;;; ========== Import section encoding ==========

  (define (encode-wasm-import imp)
    (let ([desc (wasm-import-desc imp)])
      (bv-concat
        (encode-string (wasm-import-module imp))
        (encode-string (wasm-import-name imp))
        (cond
          [(and (pair? desc) (= (car desc) 0))
           (bv-concat (bytevector #x00) (encode-u32-leb128 (cdr desc)))]
          [else
           (error 'encode-wasm-import "unsupported import descriptor" desc)]))))

  (define (encode-import-section imports)
    (if (null? imports)
      (bytevector)
      (encode-section wasm-section-import
        (encode-vec imports encode-wasm-import))))

  ;;; ========== Function section encoding ==========

  (define (encode-function-section functions)
    (if (null? functions)
      (bytevector)
      (encode-section wasm-section-function
        (encode-vec functions
          (lambda (f) (encode-u32-leb128 (car f)))))))

  ;;; ========== Memory section encoding ==========

  (define (encode-memory-section memories)
    (if (null? memories)
      (bytevector)
      (encode-section wasm-section-memory
        (encode-vec memories
          (lambda (m)
            (let ([min (car m)] [max (cdr m)])
              (if max
                (bv-concat (bytevector #x01)
                           (encode-u32-leb128 min)
                           (encode-u32-leb128 max))
                (bv-concat (bytevector #x00)
                           (encode-u32-leb128 min)))))))))

  ;;; ========== Global section encoding ==========

  (define (encode-global-section globals)
    (if (null? globals)
      (bytevector)
      (encode-section wasm-section-global
        (encode-vec globals
          (lambda (g)
            (let ([type (car g)] [mut? (cadr g)] [init (caddr g)])
              (bv-concat
                (bytevector type (if mut? 1 0))
                init
                (bytevector wasm-opcode-end))))))))

  ;;; ========== Export section encoding ==========

  (define (encode-wasm-export exp)
    (bv-concat
      (encode-string (wasm-export-name exp))
      (bytevector (wasm-export-kind exp))
      (encode-u32-leb128 (wasm-export-index exp))))

  (define (encode-export-section exports)
    (if (null? exports)
      (bytevector)
      (encode-section wasm-section-export
        (encode-vec exports encode-wasm-export))))

  ;;; ========== Code section encoding ==========

  (define (encode-locals locals)
    (if (null? locals)
      (encode-u32-leb128 0)
      (let loop ([locals locals] [groups '()] [cur-type (car locals)] [count 0])
        (cond
          [(null? locals)
           (let ([final-groups (reverse (cons (cons count cur-type) groups))])
             (encode-vec final-groups
               (lambda (g)
                 (bv-concat (encode-u32-leb128 (car g))
                            (bytevector (cdr g))))))]
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
    (if (null? functions)
      (bytevector)
      (encode-section wasm-section-code
        (encode-vec functions
          (lambda (f) (encode-func-body (cdr f)))))))

  ;;; ========== Module encoding ==========

  (define (wasm-module-encode mod)
    (bv-concat
      wasm-magic
      wasm-version
      (encode-type-section (wasm-module-types mod))
      (encode-import-section (wasm-module-imports mod))
      (encode-function-section (wasm-module-functions mod))
      (encode-memory-section (wasm-module-memories mod))
      (encode-global-section (wasm-module-globals mod))
      (encode-export-section (wasm-module-exports mod))
      (encode-code-section (wasm-module-functions mod))))

  ;;; ========== Type conversion ==========

  (define (scheme->wasm-type sym)
    (case sym
      [(i32 integer fixnum) wasm-type-i32]
      [(i64) wasm-type-i64]
      [(f32 float single) wasm-type-f32]
      [(f64 double) wasm-type-f64]
      [else wasm-type-i32]))

  ;;; ========== Compile context ==========

  (define-record-type compile-context
    (fields
      (mutable locals)
      (mutable local-count)
      (mutable funcs))
    (protocol (lambda (new)
      (lambda () (new '() 0 '())))))

  (define (context-add-local! ctx name)
    (let ([idx (compile-context-local-count ctx)])
      (compile-context-locals-set! ctx
        (cons (cons name idx) (compile-context-locals ctx)))
      (compile-context-local-count-set! ctx (+ idx 1))
      idx))

  (define (context-local-index ctx name)
    (let ([entry (assq name (compile-context-locals ctx))])
      (if entry
        (cdr entry)
        (error 'context-local-index "unbound variable" name))))

  (define (context-add-func! ctx name)
    (let ([idx (length (compile-context-funcs ctx))])
      (compile-context-funcs-set! ctx
        (cons (cons name idx) (compile-context-funcs ctx)))
      idx))

  (define (context-func-index ctx name)
    (let ([entry (assq name (compile-context-funcs ctx))])
      (if entry
        (cdr entry)
        (error 'context-func-index "unbound function" name))))

  ;;; ========== Expression compiler ==========

  ;; Compile a let binding sequence into the given context
  (define (compile-let bindings body ctx)
    (let* ([names (map car bindings)]
           [exprs (map cadr bindings)])
      ;; Evaluate each expr then store in new local
      (let ([binding-code
             (bv-concat-list
               (map (lambda (name expr)
                      (let ([eval-bv (compile-expr expr ctx)]
                            [idx (context-add-local! ctx name)])
                        (bv-concat
                          eval-bv
                          (bytevector wasm-opcode-local-set)
                          (encode-u32-leb128 idx))))
                    names exprs))])
        (bv-concat
          binding-code
          (bv-concat-list (map (lambda (e) (compile-expr e ctx)) body))))))

  ;; Binary operation: compile both operands and emit opcode
  (define (compile-binop args ctx opcode)
    (bv-concat
      (compile-expr (car args) ctx)
      (compile-expr (cadr args) ctx)
      (bytevector opcode)))

  ;; compile-expr: Scheme expression -> bytevector of WASM instructions
  (define (compile-expr expr ctx)
    (cond
      ;; Integer literal -> i32.const
      [(integer? expr)
       (bv-concat
         (bytevector wasm-opcode-i32-const)
         (encode-i32-leb128 expr))]

      ;; Symbol -> local.get
      [(symbol? expr)
       (bv-concat
         (bytevector wasm-opcode-local-get)
         (encode-u32-leb128 (context-local-index ctx expr)))]

      ;; Compound forms
      [(pair? expr)
       (let ([head (car expr)] [args (cdr expr)])
         (case head
           ;; (begin e1 ... en)
           [(begin)
            (if (null? args)
              (bytevector wasm-opcode-nop)
              (bv-concat-list (map (lambda (e) (compile-expr e ctx)) args)))]

           ;; (if test then else)
           [(if)
            (let ([test (car args)]
                  [then (cadr args)]
                  [else-part (if (null? (cddr args)) 0 (caddr args))])
              (bv-concat
                (compile-expr test ctx)
                (bytevector wasm-opcode-if wasm-type-i32)
                (compile-expr then ctx)
                (bytevector wasm-opcode-else)
                (compile-expr else-part ctx)
                (bytevector wasm-opcode-end)))]

           ;; (let ([x e] ...) body)
           [(let)
            (compile-let (car args) (cdr args) ctx)]

           ;; Arithmetic
           [(+)        (compile-binop args ctx wasm-opcode-i32-add)]
           [(-)        (compile-binop args ctx wasm-opcode-i32-sub)]
           [(*)        (compile-binop args ctx wasm-opcode-i32-mul)]
           [(quotient) (compile-binop args ctx wasm-opcode-i32-div-s)]
           [(remainder)(compile-binop args ctx wasm-opcode-i32-rem-s)]

           ;; Comparisons
           [(=)  (compile-binop args ctx wasm-opcode-i32-eq)]
           [(<)  (compile-binop args ctx wasm-opcode-i32-lt-s)]
           [(>)  (compile-binop args ctx wasm-opcode-i32-gt-s)]
           [(<=) (compile-binop args ctx wasm-opcode-i32-le-s)]
           [(>=) (compile-binop args ctx wasm-opcode-i32-ge-s)]

           ;; Function call (symbol in head position)
           [else
            (if (symbol? head)
              (let ([fidx (context-func-index ctx head)])
                (bv-concat
                  (bv-concat-list (map (lambda (a) (compile-expr a ctx)) args))
                  (bytevector wasm-opcode-call)
                  (encode-u32-leb128 fidx)))
              (error 'compile-expr "unknown form" expr))]))]

      [else (error 'compile-expr "unsupported expression" expr)]))

  ;;; ========== Program compiler ==========

  ;; compile-program: list of top-level (define ...) forms -> binary WASM bytevector
  ;; All values are i32 (integer-only subset).
  (define (compile-program forms)
    (let ([mod (make-wasm-module)]
          [global-ctx (make-compile-context)])

      ;; First pass: register all function names (so mutual calls work)
      (for-each
        (lambda (form)
          (when (and (pair? form) (eq? (car form) 'define))
            (let ([sig (cadr form)])
              (when (pair? sig)
                (context-add-func! global-ctx (car sig))))))
        forms)

      ;; Second pass: compile each define into a WASM function
      (for-each
        (lambda (form)
          (when (and (pair? form) (eq? (car form) 'define))
            (let* ([sig (cadr form)]
                   [body-forms (cddr form)])
              (when (pair? sig)
                (let* ([name (car sig)]
                       [params (cdr sig)]
                       ;; Create per-function context with all function names
                       [ctx (make-compile-context)]
                       [_ (compile-context-funcs-set! ctx
                            (compile-context-funcs global-ctx))]
                       ;; Add params as locals (indices 0..n-1)
                       [_ (for-each (lambda (p) (context-add-local! ctx p)) params)]
                       ;; Compile body (multiple forms -> begin)
                       [body-bv (if (= (length body-forms) 1)
                                  (compile-expr (car body-forms) ctx)
                                  (bv-concat-list
                                    (map (lambda (e) (compile-expr e ctx)) body-forms)))]
                       ;; Append end opcode
                       [full-body (bv-concat body-bv (bytevector wasm-opcode-end))]
                       ;; Collect let-bound locals (index >= param count)
                       [all-locals (compile-context-locals ctx)]
                       [let-locals
                        (filter (lambda (pair) (>= (cdr pair) (length params)))
                                all-locals)]
                       [local-types (map (lambda (_) wasm-type-i32) let-locals)]
                       [func (make-wasm-func local-types full-body)]
                       ;; Type signature: all i32 params, i32 result
                       [param-types (map (lambda (_) wasm-type-i32) params)]
                       [type-idx (length (wasm-module-types mod))]
                       [type (make-wasm-type param-types (list wasm-type-i32))])

                  (wasm-module-add-type! mod type)
                  (wasm-module-add-function! mod type-idx func))))))
        forms)

      ;; Add exports for all registered functions
      ;; The global-ctx funcs list is in reverse order of registration
      ;; (context-add-func! prepends, so first func is at end of list)
      (let ([funcs (reverse (compile-context-funcs global-ctx))])
        (for-each
          (lambda (pair)
            (wasm-module-add-export! mod
              (wasm-export-func (symbol->string (car pair)) (cdr pair))))
          funcs))

      (wasm-module-encode mod)))

) ;; end library
