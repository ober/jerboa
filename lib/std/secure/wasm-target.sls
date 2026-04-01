#!chezscheme
;;; (std secure wasm-target) -- Slang-to-WASM compilation target
;;;
;;; Alternative backend for the Slang compiler that produces a WASM binary
;;; instead of a Chez Scheme .wpo file. The WASM binary runs inside a
;;; Rust wasmi interpreter with host-provided I/O imports.
;;;
;;; Pipeline:
;;;   1. Parse and validate Slang source (reuses (std secure compiler))
;;;   2. Lambda-lift closures to top-level functions
;;;   3. Lower Slang forms to compile-program's expression language
;;;   4. Prepend runtime (tagged values, allocator, Scheme primitives)
;;;   5. Add host imports for I/O (WASI-like)
;;;   6. Compile to WASM binary via compile-program
;;;
;;; The output is a .wasm file suitable for:
;;;   - Loading into wasmi (Rust) with fuel metering
;;;   - Loading into the Jerboa WASM runtime for testing
;;;
;;; Architecture:
;;;   Host (Rust/wasmi)          WASM module
;;;   ├─ socket I/O              ├─ DNS parsing
;;;   ├─ event loop              ├─ CDB lookup
;;;   ├─ fd management           ├─ Response building
;;;   └─ OS sandbox              └─ Business logic
;;;
;;; The host calls exported WASM functions (init, process_query, etc.)
;;; and the WASM module calls imported host functions (fd_read, fd_write, etc.).

(library (std secure wasm-target)
  (export
    ;; Main compilation entry points
    slang-compile-wasm      ;; source-path -> bytevector (WASM binary)
    slang-compile-wasm-file ;; source-path output-path -> void

    ;; Pipeline stages (for testing/debugging)
    slang->wasm-forms       ;; slang-module -> list of compile-program forms
    slang-lower-form        ;; single Slang form -> compile-program form(s)

    ;; Host import specifications
    wasi-import-forms       ;; WASI-compatible host imports
    dns-host-import-forms   ;; DNS-specific host imports
    )

  (import (except (chezscheme) compile-program)
          (std secure compiler)
          (jerboa wasm codegen)
          (jerboa wasm values)
          (jerboa wasm gc)
          (jerboa wasm closure))

  ;; ================================================================
  ;; Host import declarations
  ;; ================================================================

  ;; WASI-compatible imports for basic I/O
  (define wasi-import-forms
    '(;; fd_read(fd, iovs_ptr, iovs_len, nread_ptr) -> errno
      (define-import "wasi_snapshot_preview1" fd_read (i32 i32 i32 i32) (i32))
      ;; fd_write(fd, iovs_ptr, iovs_len, nwritten_ptr) -> errno
      (define-import "wasi_snapshot_preview1" fd_write (i32 i32 i32 i32) (i32))
      ;; clock_time_get(clock_id, precision, time_ptr) -> errno
      (define-import "wasi_snapshot_preview1" clock_time_get (i32 i64 i32) (i32))
      ;; random_get(buf_ptr, buf_len) -> errno
      (define-import "wasi_snapshot_preview1" random_get (i32 i32) (i32))
      ;; proc_exit(code) -> noreturn
      (define-import "wasi_snapshot_preview1" proc_exit (i32) ())))

  ;; DNS-specific host imports (for jerboa-dns)
  (define dns-host-import-forms
    '(;; recv_packet(buf_ptr, buf_max) -> packet_len  (-1 on error)
      ;; Host calls recvfrom on the pre-opened UDP socket
      (define-import "dns" recv_packet (i32 i32) (i32))

      ;; send_packet(buf_ptr, buf_len, addr_ptr, addr_len) -> bytes_sent
      ;; Host calls sendto to reply to the querying address
      (define-import "dns" send_packet (i32 i32 i32 i32) (i32))

      ;; cdb_open(path_ptr, path_len) -> cdb_handle  (-1 on error)
      ;; Host opens a CDB file and returns a handle
      (define-import "dns" cdb_open (i32 i32) (i32))

      ;; cdb_find(handle, key_ptr, key_len, val_buf, val_max) -> val_len
      ;; Host performs CDB lookup, writes value to val_buf
      (define-import "dns" cdb_find (i32 i32 i32 i32 i32) (i32))

      ;; cdb_close(handle) -> 0
      (define-import "dns" cdb_close (i32) (i32))

      ;; log_message(level, msg_ptr, msg_len) -> 0
      ;; Host writes log message to stderr/syslog
      (define-import "dns" log_message (i32 i32 i32) (i32))

      ;; get_time_ms() -> milliseconds (i32)
      ;; Host returns current monotonic time
      (define-import "dns" get_time_ms () (i32))))

  ;; ================================================================
  ;; Slang form lowering
  ;; ================================================================

  ;; Lower a single Slang top-level form to compile-program forms.
  ;; Returns a list of forms (may expand to multiple defines).
  (define (slang-lower-form form)
    (cond
      ;; Import declarations — skip (handled separately)
      [(and (pair? form) (eq? (car form) 'import))
       '()]

      ;; slang-module declaration — skip (already parsed)
      [(and (pair? form) (eq? (car form) 'slang-module))
       '()]

      ;; Function definition
      [(and (pair? form) (eq? (car form) 'define) (pair? (cadr form)))
       (let* ([sig (cadr form)]
              [name (car sig)]
              [params (cdr sig)]
              [body (cddr form)])
         ;; Lower the body expressions
         (let* ([lowered-body (map lower-expr body)]
                ;; Optimize self-recursive tail calls to return-call
                [optimized-body (tail-call-optimize name lowered-body)])
           (list `(define (,name ,@(lower-params params)) ,@optimized-body))))]

      ;; Variable definition
      [(and (pair? form) (eq? (car form) 'define) (symbol? (cadr form)))
       (list `(define (,(gensym-init (cadr form)))
                (global.set ,(cadr form) ,(lower-expr (caddr form)))))]

      ;; Top-level expression (wrap in init function)
      [(pair? form)
       (list `(define (,(gensym-init 'top-level))
                ,(lower-expr form)))]

      [else '()]))

  ;; Generate a unique init function name for top-level expressions
  (define init-counter 0)
  (define (gensym-init base)
    (set! init-counter (+ init-counter 1))
    (string->symbol
      (string-append "__init_"
        (symbol->string base) "_"
        (number->string init-counter))))

  ;; Lower parameters: strip type annotations, keep names.
  ;; Handles dotted lists for rest args: (x y . rest) → (x y . rest)
  (define (lower-params params)
    (define (strip-param p)
      (cond
        [(symbol? p) p]
        ;; (name type) -> name
        [(and (pair? p) (symbol? (car p))) (car p)]
        [else p]))
    (let loop ([ps params])
      (cond
        [(null? ps) '()]
        ;; -> return type annotation — stop here
        [(and (pair? ps) (eq? (car ps) '->)) '()]
        ;; Dotted tail (rest arg): (x . rest) where rest is a symbol
        [(symbol? ps) ps]
        ;; Normal parameter
        [(pair? ps)
         (cons (strip-param (car ps)) (loop (cdr ps)))]
        [else ps])))

  ;; ================================================================
  ;; Tail call optimization: self-recursive calls → return-call
  ;; ================================================================

  ;; Transform the last expression in a body: if it's a self-call, emit return-call.
  ;; Walks into if/cond/let/begin to find tail positions.
  (define (tail-call-optimize fname body)
    (if (null? body)
      body
      ;; Only the last expression is in tail position
      (let ([prefix (reverse (cdr (reverse body)))]
            [last-expr (car (reverse body))])
        (append prefix (list (tco-expr fname last-expr))))))

  (define (tco-expr fname expr)
    (cond
      [(not (pair? expr)) expr]
      [else
       (let ([head (car expr)] [args (cdr expr)])
         (cond
           ;; Self-call in tail position → return-call
           [(eq? head fname)
            `(return-call ,fname ,@args)]

           ;; if: both branches are tail positions
           [(eq? head 'if)
            (if (null? (cddr args))
              ;; (if test then) — only then branch
              `(if ,(car args) ,(tco-expr fname (cadr args)))
              ;; (if test then else)
              `(if ,(car args)
                 ,(tco-expr fname (cadr args))
                 ,(tco-expr fname (caddr args))))]

           ;; when: body is tail position
           [(eq? head 'when)
            `(when ,(car args) ,@(tail-call-optimize fname (cdr args)))]

           ;; begin: last expression is tail position
           [(eq? head 'begin)
            `(begin ,@(tail-call-optimize fname args))]

           ;; let/let*: body is tail position
           [(memq head '(let let*))
            (let ([bindings (car args)]
                  [body (cdr args)])
              `(,head ,bindings ,@(tail-call-optimize fname body)))]

           ;; cond: each branch body is tail position
           [(eq? head 'cond)
            `(cond ,@(map (lambda (clause)
                            (if (eq? (car clause) 'else)
                              `(else ,@(tail-call-optimize fname (cdr clause)))
                              (cons (car clause)
                                    (tail-call-optimize fname (cdr clause)))))
                          args))]

           ;; Default: not a tail position we recognize
           [else expr]))]))

  ;; ================================================================
  ;; Expression lowering: Slang -> compile-program subset
  ;; ================================================================

  ;; Lower a Slang expression to compile-program's expression language.
  ;; Key transformations:
  ;;   - Scheme primitives → runtime function calls (scheme-cons, fx+, etc.)
  ;;   - Literal values → tagged constants
  ;;   - Pattern matching → nested if/let
  ;;   - Higher-order calls → call-closure
  (define (lower-expr expr)
    (cond
      ;; Integer literal → tagged fixnum constant
      [(and (integer? expr) (exact? expr))
       (tagged-fixnum expr)]

      ;; Boolean literal → immediate constant
      [(boolean? expr)
       (if expr IMM-TRUE IMM-FALSE)]

      ;; Null literal
      [(null? expr)
       IMM-NIL]

      ;; Char literal → tagged fixnum of char code
      [(char? expr)
       (tagged-fixnum (char->integer expr))]

      ;; Symbol reference — pass through
      [(symbol? expr) expr]

      ;; String literal → will be lowered to static data + string-from-memory
      ;; For now, placeholder: stored in static data segment during compilation
      [(string? expr)
       `(string-from-static ,(string->utf8 expr))]

      ;; Compound form
      [(pair? expr)
       (let ([head (car expr)] [args (cdr expr)])
         (case head
           ;; ---- Binding forms (pass through with lowered bodies) ----
           [(let)
            (let* ([bindings (car args)]
                   [body (cdr args)]
                   [new-bindings (map (lambda (b)
                                        (list (car b) (lower-expr (cadr b))))
                                      bindings)])
              `(let ,new-bindings ,@(map lower-expr body)))]

           [(let*)
            (let* ([bindings (car args)]
                   [body (cdr args)]
                   [new-bindings (map (lambda (b)
                                        (list (car b) (lower-expr (cadr b))))
                                      bindings)])
              `(let* ,new-bindings ,@(map lower-expr body)))]

           ;; ---- Control flow (pass through) ----
           [(if)
            (let ([test (lower-expr (car args))]
                  [then (lower-expr (cadr args))])
              (if (null? (cddr args))
                `(when (is-truthy ,test) ,then)
                `(if (is-truthy ,test)
                   ,then
                   ,(lower-expr (caddr args)))))]

           [(cond)
            (lower-cond args)]

           [(when)
            `(when (is-truthy ,(lower-expr (car args)))
               ,@(map lower-expr (cdr args)))]

           [(unless)
            `(when (not (is-truthy ,(lower-expr (car args))))
               ,@(map lower-expr (cdr args)))]

           [(and)
            (cond
              [(null? args) IMM-TRUE]
              [(null? (cdr args)) (lower-expr (car args))]
              [else
               `(if (is-truthy ,(lower-expr (car args)))
                  ,(lower-expr `(and ,@(cdr args)))
                  ,IMM-FALSE)])]

           [(or)
            (cond
              [(null? args) IMM-FALSE]
              [(null? (cdr args)) (lower-expr (car args))]
              [else
               `(let ([__or_tmp ,(lower-expr (car args))])
                  (if (is-truthy __or_tmp)
                    __or_tmp
                    ,(lower-expr `(or ,@(cdr args)))))])]

           [(begin)
            `(begin ,@(map lower-expr args))]

           [(set!)
            `(set! ,(car args) ,(lower-expr (cadr args)))]

           ;; ---- Scheme primitives → runtime calls ----

           ;; Pair operations
           [(cons)
            `(scheme-cons ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(car)
            `(scheme-car ,(lower-expr (car args)))]
           [(cdr)
            `(scheme-cdr ,(lower-expr (car args)))]
           [(null?)
            `(wasm-bool->scheme (scheme-null? ,(lower-expr (car args))))]
           [(pair?)
            `(wasm-bool->scheme (is-pair ,(lower-expr (car args))))]
           [(list?)
            `(wasm-bool->scheme (scheme-list? ,(lower-expr (car args))))]

           ;; Arithmetic — operands are tagged fixnums
           [(+)
            (if (null? (cdr args))
              (lower-expr (car args))
              `(fx+ ,(lower-expr (car args)) ,(lower-expr (cadr args))))]
           [(-)
            (if (null? (cdr args))
              `(fx-negate ,(lower-expr (car args)))
              `(fx- ,(lower-expr (car args)) ,(lower-expr (cadr args))))]
           [(*)
            `(fx* ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(/)
            `(fx/ ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(modulo remainder)
            `(fx-mod ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(abs)
            `(fx-abs ,(lower-expr (car args)))]

           ;; Bitwise
           [(bitwise-and)
            `(fx-bitwise-and ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(bitwise-or)
            `(fx-bitwise-or ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(bitwise-xor)
            `(fx-bitwise-xor ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(arithmetic-shift ash)
            `(fx-ash ,(lower-expr (car args)) ,(lower-expr (cadr args)))]

           ;; Comparison — return tagged boolean
           [(<)
            `(fx< ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(>)
            `(fx> ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(<=)
            `(fx<= ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(>=)
            `(fx>= ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(= eqv?)
            `(scheme-eqv? ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(eq?)
            `(scheme-eq? ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(equal?)
            `(scheme-equal? ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(zero?)
            `(fx= ,(lower-expr (car args)) ,(tagged-fixnum 0))]
           [(positive?)
            `(fx> ,(lower-expr (car args)) ,(tagged-fixnum 0))]
           [(negative?)
            `(fx< ,(lower-expr (car args)) ,(tagged-fixnum 0))]
           [(not)
            `(if (is-truthy ,(lower-expr (car args))) ,IMM-FALSE ,IMM-TRUE)]

           ;; Type predicates
           [(number? integer?)
            `(wasm-bool->scheme (is-number ,(lower-expr (car args))))]
           [(string?)
            `(wasm-bool->scheme (is-string ,(lower-expr (car args))))]
           [(symbol?)
            `(wasm-bool->scheme (is-symbol ,(lower-expr (car args))))]
           [(boolean?)
            `(wasm-bool->scheme (is-boolean ,(lower-expr (car args))))]
           [(vector?)
            `(wasm-bool->scheme (is-vector ,(lower-expr (car args))))]
           [(bytevector?)
            `(wasm-bool->scheme (is-bytevector ,(lower-expr (car args))))]
           [(eof-object?)
            `(if (is-eof ,(lower-expr (car args))) ,IMM-TRUE ,IMM-FALSE)]

           ;; List operations
           [(length)
            `(scheme-length ,(lower-expr (car args)))]
           [(append)
            (cond
              [(null? args) IMM-NIL]
              [(null? (cdr args)) (lower-expr (car args))]
              [(null? (cddr args))
               `(scheme-append ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
              ;; n-ary: (append a b c ...) → (scheme-append a (append b c ...))
              [else
               `(scheme-append ,(lower-expr (car args))
                               ,(lower-expr `(append ,@(cdr args))))])]
           [(reverse)
            `(scheme-reverse ,(lower-expr (car args)))]
           [(list-ref)
            `(scheme-list-ref ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(assq)
            `(scheme-assq ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(memq)
            `(scheme-memq ,(lower-expr (car args)) ,(lower-expr (cadr args)))]

           ;; list constructor: (list a b c) -> (cons a (cons b (cons c ())))
           [(list)
            (let loop ([elems (reverse args)] [acc IMM-NIL])
              (if (null? elems)
                acc
                (loop (cdr elems)
                      `(scheme-cons ,(lower-expr (car elems)) ,acc))))]

           ;; Bytevector operations
           [(make-bytevector)
            `(scheme-make-bytevector ,(lower-expr (car args)))]
           [(bytevector-length)
            `(scheme-bytevector-length ,(lower-expr (car args)))]
           [(bytevector-u8-ref)
            `(scheme-bytevector-u8-ref ,(lower-expr (car args))
                                        ,(lower-expr (cadr args)))]
           [(bytevector-u8-set!)
            `(scheme-bytevector-u8-set! ,(lower-expr (car args))
                                         ,(lower-expr (cadr args))
                                         ,(lower-expr (caddr args)))]
           [(bytevector-copy!)
            `(scheme-bytevector-copy ,(lower-expr (car args))
                                     ,(lower-expr (cadr args))
                                     ,(lower-expr (caddr args))
                                     ,(lower-expr (cadddr args))
                                     ,(lower-expr (car (cddddr args))))]

           ;; String operations
           [(string-length)
            `(scheme-string-length ,(lower-expr (car args)))]
           [(string-ref)
            `(scheme-string-ref ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(string=?)
            `(scheme-string=? ,(lower-expr (car args)) ,(lower-expr (cadr args)))]

           ;; Vector operations
           [(make-vector)
            `(scheme-make-vector ,(lower-expr (car args))
                                 ,(if (null? (cdr args))
                                    IMM-FALSE
                                    (lower-expr (cadr args))))]
           [(vector-length)
            `(scheme-vector-length ,(lower-expr (car args)))]
           [(vector-ref)
            `(scheme-vector-ref ,(lower-expr (car args)) ,(lower-expr (cadr args)))]
           [(vector-set!)
            `(scheme-vector-set! ,(lower-expr (car args))
                                  ,(lower-expr (cadr args))
                                  ,(lower-expr (caddr args)))]

           ;; ---- Result type operations ----
           [(ok)
            `(scheme-ok ,(lower-expr (car args)))]
           [(err)
            `(scheme-err ,(lower-expr (car args)))]
           [(ok?)
            `(wasm-bool->scheme (scheme-ok? ,(lower-expr (car args))))]
           [(err?)
            `(wasm-bool->scheme (scheme-err? ,(lower-expr (car args))))]
           [(unwrap)
            `(scheme-unwrap ,(lower-expr (car args)))]
           [(unwrap-or)
            `(scheme-unwrap-or ,(lower-expr (car args))
                               ,(lower-expr (cadr args)))]
           [(map-ok)
            ;; (map-ok f result) → if ok, wrap (f value) in ok; else pass err
            (let ([f-expr (lower-expr (car args))]
                  [r-expr (lower-expr (cadr args))])
              `(let ([__mo_r ,r-expr])
                 (if (scheme-ok? __mo_r)
                   (scheme-ok (,f-expr (scheme-result-value __mo_r)))
                   __mo_r)))]
           [(map-err)
            ;; (map-err f result) → if err, wrap (f value) in err; else pass ok
            (let ([f-expr (lower-expr (car args))]
                  [r-expr (lower-expr (cadr args))])
              `(let ([__me_r ,r-expr])
                 (if (scheme-err? __me_r)
                   (scheme-err (,f-expr (scheme-result-value __me_r)))
                   __me_r)))]
           [(and-then)
            ;; (and-then result f) → if ok, (f value); else pass err
            (let ([r-expr (lower-expr (car args))]
                  [f-expr (lower-expr (cadr args))])
              `(let ([__at_r ,r-expr])
                 (if (scheme-ok? __at_r)
                   (,f-expr (scheme-result-value __at_r))
                   __at_r)))]
           [(->?)
            ;; (->? result (f) (g)) → thread through ok values
            ;; (->? init f1 f2 ...) where each fi takes one arg and returns result
            (let loop ([r-expr (lower-expr (car args))]
                       [fns (cdr args)])
              (if (null? fns)
                r-expr
                (let ([f-expr (lower-expr (car fns))])
                  (loop `(let ([__pipe_r ,r-expr])
                           (if (scheme-ok? __pipe_r)
                             (,f-expr (scheme-result-value __pipe_r))
                             __pipe_r))
                        (cdr fns)))))]

           ;; ---- Higher-order list operations (lowered to while loops) ----

           ;; (map f lst) → build result list by calling f on each element
           [(map)
            (let ([f-expr (lower-expr (car args))]
                  [lst-expr (lower-expr (cadr args))])
              `(let ([__map_iter ,lst-expr]
                     [__map_result ,IMM-NIL])
                 (while (is-pair __map_iter)
                   (let ([__map_item (scheme-car __map_iter)])
                     (set! __map_result
                       (scheme-cons (,f-expr __map_item) __map_result))
                     (set! __map_iter (scheme-cdr __map_iter))))
                 (scheme-reverse __map_result)))]

           ;; (filter pred lst) → keep elements where pred returns truthy
           [(filter)
            (let ([pred-expr (lower-expr (car args))]
                  [lst-expr (lower-expr (cadr args))])
              `(let ([__filt_iter ,lst-expr]
                     [__filt_result ,IMM-NIL])
                 (while (is-pair __filt_iter)
                   (let ([__filt_item (scheme-car __filt_iter)])
                     (when (is-truthy (,pred-expr __filt_item))
                       (set! __filt_result
                         (scheme-cons __filt_item __filt_result)))
                     (set! __filt_iter (scheme-cdr __filt_iter))))
                 (scheme-reverse __filt_result)))]

           ;; (for-each f lst) → call f on each element, return void
           [(for-each)
            (let ([f-expr (lower-expr (car args))]
                  [lst-expr (lower-expr (cadr args))])
              `(let ([__fe_iter ,lst-expr])
                 (while (is-pair __fe_iter)
                   (,f-expr (scheme-car __fe_iter))
                   (set! __fe_iter (scheme-cdr __fe_iter)))
                 ,IMM-VOID))]

           ;; (fold-left f init lst) → accumulate via (f acc elem)
           [(fold-left foldl)
            (let ([f-expr (lower-expr (car args))]
                  [init-expr (lower-expr (cadr args))]
                  [lst-expr (lower-expr (caddr args))])
              `(let ([__fl_acc ,init-expr]
                     [__fl_iter ,lst-expr])
                 (while (is-pair __fl_iter)
                   (set! __fl_acc
                     (,f-expr __fl_acc (scheme-car __fl_iter)))
                   (set! __fl_iter (scheme-cdr __fl_iter)))
                 __fl_acc))]

           ;; (fold-right f init lst) → reverse then fold-left with flipped args
           [(fold-right foldr)
            (let ([f-expr (lower-expr (car args))]
                  [init-expr (lower-expr (cadr args))]
                  [lst-expr (lower-expr (caddr args))])
              `(let ([__fr_acc ,init-expr]
                     [__fr_iter (scheme-reverse ,lst-expr)])
                 (while (is-pair __fr_iter)
                   (set! __fr_acc
                     (,f-expr (scheme-car __fr_iter) __fr_acc))
                   (set! __fr_iter (scheme-cdr __fr_iter)))
                 __fr_acc))]

           ;; ---- Iteration forms ----
           [(while)
            `(while (is-truthy ,(lower-expr (car args)))
               ,@(map lower-expr (cdr args)))]

           ;; for/collect lowered to while + cons + reverse
           [(for/collect)
            (lower-for-collect (car args) (cdr args))]

           ;; for/fold lowered to while + accumulator
           [(for/fold)
            (lower-for-fold (car args) (cadr args) (cddr args))]

           ;; ---- Match ----
           [(match)
            (lower-match (car args) (cdr args))]

           ;; ---- Exception handling ----

           ;; (guard (e [test => expr] ...) body ...)
           ;; Lowered to try/catch with tag 0 (general exception tag)
           [(guard)
            (let* ([var-clauses (car args)]
                   [var (car var-clauses)]
                   [clauses (cdr var-clauses)]
                   [body (cdr args)])
              `(try-catch 0
                 (begin ,@(map lower-expr body))
                 ,var
                 ,(lower-guard-clauses var clauses)))]

           ;; (try body (catch (e) handler))
           ;; (try body (catch (pred? e) handler))
           [(try)
            (let* ([body (car args)]
                   [rest (cdr args)]
                   [catch-clause (and (pair? rest)
                                      (pair? (car rest))
                                      (eq? (caar rest) 'catch)
                                      (car rest))]
                   [finally-clause (and (pair? rest)
                                        (or (and (pair? (car rest))
                                                 (eq? (caar rest) 'finally)
                                                 (car rest))
                                            (and (>= (length rest) 2)
                                                 (pair? (cadr rest))
                                                 (eq? (caadr rest) 'finally)
                                                 (cadr rest))))])
              (let ([try-body (lower-expr body)])
                (if catch-clause
                  (let* ([catch-args (cdr catch-clause)]
                         [catch-bindings (car catch-args)]
                         [catch-body (cdr catch-args)]
                         [e-var (if (pair? catch-bindings) (car catch-bindings) catch-bindings)])
                    (if finally-clause
                      `(try-catch 0
                         ,try-body
                         ,e-var
                         (begin ,@(map lower-expr catch-body)))
                      `(try-catch 0
                         ,try-body
                         ,e-var
                         (begin ,@(map lower-expr catch-body)))))
                  try-body)))]

           ;; (assert! expr) or (assert! expr "message")
           [(assert!)
            (let ([test (lower-expr (car args))])
              `(when (not (is-truthy ,test))
                 (throw 0 ,(if (and (pair? (cdr args)) (string? (cadr args)))
                             (lower-expr (cadr args))
                             (tagged-fixnum 0)))))]

           ;; ---- Quote ----
           [(quote)
            (lower-quoted (car args))]

           ;; ---- Quasiquote ----
           [(quasiquote)
            (lower-expr (expand-quasiquote (car args)))]

           ;; ---- Default: function call ----
           [else
            `(,head ,@(map lower-expr args))]))]

      [else expr]))

  ;; Lower guard clauses: (guard (e [test body] ...) ...)
  (define (lower-guard-clauses var clauses)
    (if (null? clauses)
      ;; No matching clause: re-throw
      `(throw 0 ,var)
      (let* ([clause (car clauses)]
             [test (car clause)]
             [body (cdr clause)])
        (if (eq? test 'else)
          `(begin ,@(map lower-expr body))
          `(if (is-truthy ,(lower-expr test))
             (begin ,@(map lower-expr body))
             ,(lower-guard-clauses var (cdr clauses)))))))

  ;; Lower a cond expression
  (define (lower-cond clauses)
    (if (null? clauses)
      IMM-VOID
      (let ([clause (car clauses)])
        (if (eq? (car clause) 'else)
          `(begin ,@(map lower-expr (cdr clause)))
          `(if (is-truthy ,(lower-expr (car clause)))
             (begin ,@(map lower-expr (cdr clause)))
             ,(lower-cond (cdr clauses)))))))

  ;; Lower for/collect to while loop
  (define (lower-for-collect bindings body)
    (let* ([var (caar bindings)]
           [iter-expr (cadar bindings)]
           [lowered-body (map lower-expr body)])
      ;; (for/collect ((x lst)) body) →
      ;; (let ([__iter lst] [__result NIL])
      ;;   (while (is-pair __iter)
      ;;     (let ([x (pair-car __iter)])
      ;;       (set! __result (cons-val <body> __result))
      ;;       (set! __iter (pair-cdr __iter))))
      ;;   (scheme-reverse __result))
      `(let ([__fc_iter ,(lower-expr iter-expr)]
             [__fc_result ,IMM-NIL])
         (while (is-pair __fc_iter)
           (let ([,var (scheme-car __fc_iter)])
             (set! __fc_result (scheme-cons (begin ,@lowered-body) __fc_result))
             (set! __fc_iter (scheme-cdr __fc_iter))))
         (scheme-reverse __fc_result))))

  ;; Lower for/fold to while loop
  (define (lower-for-fold accums bindings body)
    (let* ([acc-name (caar accums)]
           [acc-init (cadar accums)]
           [var (caar bindings)]
           [iter-expr (cadar bindings)]
           [lowered-body (map lower-expr body)])
      `(let ([,acc-name ,(lower-expr acc-init)]
             [__ff_iter ,(lower-expr iter-expr)])
         (while (is-pair __ff_iter)
           (let ([,var (scheme-car __ff_iter)])
             (set! ,acc-name (begin ,@lowered-body))
             (set! __ff_iter (scheme-cdr __ff_iter))))
         ,acc-name)))

  ;; Lower match expression to nested if/let
  (define (lower-match scrutinee clauses)
    (let ([scrut-var '__match_val])
      `(let ([,scrut-var ,(lower-expr scrutinee)])
         ,(lower-match-clauses scrut-var clauses))))

  (define (lower-match-clauses scrut clauses)
    (if (null? clauses)
      `(unreachable)  ;; no match — trap
      (let* ([clause (car clauses)]
             [pattern (car clause)]
             [body (cdr clause)])
        (cond
          ;; Wildcard: always matches
          [(eq? pattern '_)
           `(begin ,@(map lower-expr body))]

          ;; Variable binding: bind and execute body
          [(symbol? pattern)
           `(let ([,pattern ,scrut])
              ,@(map lower-expr body))]

          ;; Literal number
          [(number? pattern)
           `(if (= ,scrut ,(tagged-fixnum pattern))
              (begin ,@(map lower-expr body))
              ,(lower-match-clauses scrut (cdr clauses)))]

          ;; Literal boolean
          [(boolean? pattern)
           `(if (= ,scrut ,(if pattern IMM-TRUE IMM-FALSE))
              (begin ,@(map lower-expr body))
              ,(lower-match-clauses scrut (cdr clauses)))]

          ;; (quote sym) — symbol literal
          [(and (pair? pattern) (eq? (car pattern) 'quote))
           ;; Symbol comparison requires interning; for now use eq?
           `(if (scheme-eq? ,scrut ,(lower-expr pattern))
              (begin ,@(map lower-expr body))
              ,(lower-match-clauses scrut (cdr clauses)))]

          ;; (list p1 p2 ...) — list destructure
          [(and (pair? pattern) (eq? (car pattern) 'list))
           (lower-list-match scrut (cdr pattern) body (cdr clauses))]

          ;; (cons h t) — pair destructure
          [(and (pair? pattern) (eq? (car pattern) 'cons))
           (let ([h (cadr pattern)]
                 [t (caddr pattern)])
             `(if (is-pair ,scrut)
                (let ([,h (scheme-car ,scrut)]
                      [,t (scheme-cdr ,scrut)])
                  ,@(map lower-expr body))
                ,(lower-match-clauses scrut (cdr clauses))))]

          ;; (? pred) or (? pred var) — predicate test
          [(and (pair? pattern) (eq? (car pattern) '?))
           (let ([pred (cadr pattern)]
                 [var (if (>= (length pattern) 3) (caddr pattern) #f)])
             `(if (is-truthy (,(lower-expr pred) ,scrut))
                ,(if var
                   `(let ([,var ,scrut]) ,@(map lower-expr body))
                   `(begin ,@(map lower-expr body)))
                ,(lower-match-clauses scrut (cdr clauses))))]

          ;; Default: skip this pattern (shouldn't happen after validation)
          [else
           (lower-match-clauses scrut (cdr clauses))]))))

  ;; Lower a (list p1 p2 ...) pattern match
  (define (lower-list-match scrut patterns body rest-clauses)
    (if (null? patterns)
      ;; All patterns matched, check for nil tail
      `(if (scheme-null? ,scrut)
         (begin ,@(map lower-expr body))
         ,(lower-match-clauses scrut rest-clauses))
      ;; Check that scrut is a pair, bind car, recurse on cdr
      (let ([p (car patterns)]
            [ps (cdr patterns)]
            [tmp-car (gensym-init 'car)]
            [tmp-cdr (gensym-init 'cdr)])
        `(if (is-pair ,scrut)
           (let ([,tmp-car (scheme-car ,scrut)]
                 [,tmp-cdr (scheme-cdr ,scrut)])
             ,(if (eq? p '_)
                ;; Wildcard: don't bind
                (lower-list-match tmp-cdr ps body rest-clauses)
                (if (symbol? p)
                  ;; Variable: bind
                  `(let ([,p ,tmp-car])
                     ,(lower-list-match tmp-cdr ps body rest-clauses))
                  ;; Nested pattern: match against car, then continue
                  (lower-match-clauses tmp-car
                    (list (list p (lower-list-match tmp-cdr ps body rest-clauses)))))))
           ,(lower-match-clauses scrut rest-clauses)))))

  ;; Lower a quoted literal to a tagged constant or static allocation
  (define (lower-quoted datum)
    (cond
      [(integer? datum) (tagged-fixnum datum)]
      [(boolean? datum) (if datum IMM-TRUE IMM-FALSE)]
      [(null? datum)    IMM-NIL]
      [(char? datum)    (tagged-fixnum (char->integer datum))]
      ;; Lists: build at runtime via cons
      [(pair? datum)
       `(scheme-cons ,(lower-quoted (car datum))
                     ,(lower-quoted (cdr datum)))]
      ;; Symbols/strings need static data (handled during full compilation)
      [(symbol? datum)
       `(intern-symbol ,(symbol->string datum))]
      [(string? datum)
       `(string-from-static ,(string->utf8 datum))]
      [else IMM-VOID]))

  ;; Expand quasiquote to ordinary Scheme expressions.
  ;; `(a ,b ,@c d) → (append (list 'a b) c (list 'd))
  ;; The result is then lowered by lower-expr as usual.
  (define (expand-quasiquote form)
    (cond
      [(pair? form)
       (cond
         ;; ,expr → expr (unquote)
         [(eq? (car form) 'unquote)
          (cadr form)]
         ;; ,@expr inside a list → handled by expand-qq-list
         [(eq? (car form) 'unquote-splicing)
          (error 'expand-quasiquote "unquote-splicing outside of list context")]
         ;; List: process element-by-element, coalescing into append
         [else
          (expand-qq-list form)])]
      ;; Atom: quote it
      [else `(quote ,form)]))

  ;; Expand a quasiquoted list.  Groups consecutive non-splice elements
  ;; into (list ...) segments, and splices ,@expr directly into append.
  (define (expand-qq-list lst)
    (let loop ([rest lst] [segments '()] [current '()])
      (cond
        [(null? rest)
         ;; End of list: flush current segment and build result
         (let ([segs (if (null? current)
                       (reverse segments)
                       (reverse (cons `(list ,@(reverse current)) segments)))])
           (cond
             [(null? segs) '(quote ())]
             [(null? (cdr segs)) (car segs)]
             [else `(append ,@segs)]))]
        [(and (pair? rest) (not (pair? (car rest))))
         ;; Non-pair element: expand and accumulate
         (loop (cdr rest) segments
               (cons (expand-quasiquote (car rest)) current))]
        [(and (pair? rest) (pair? (car rest))
              (eq? (caar rest) 'unquote))
         ;; ,expr: accumulate the unquoted expression
         (loop (cdr rest) segments
               (cons (cadar rest) current))]
        [(and (pair? rest) (pair? (car rest))
              (eq? (caar rest) 'unquote-splicing))
         ;; ,@expr: flush current segment, add splice
         (let ([new-segments (if (null? current)
                               segments
                               (cons `(list ,@(reverse current)) segments))])
           (loop (cdr rest) (cons (cadar rest) new-segments) '()))]
        [(not (pair? rest))
         ;; Dotted tail: (a b . c)
         (let ([new-segments (if (null? current)
                               segments
                               (cons `(list ,@(reverse current)) segments))])
           (let ([segs (reverse (cons (expand-quasiquote rest) new-segments))])
             (cond
               [(null? segs) '(quote ())]
               [(null? (cdr segs)) (car segs)]
               [else `(append ,@segs)])))]
        [else
         ;; Nested list element: recurse
         (loop (cdr rest) segments
               (cons (expand-quasiquote (car rest)) current))])))

  ;; ================================================================
  ;; Full pipeline: Slang module -> compile-program forms
  ;; ================================================================

  (define (slang->wasm-forms mod . opts)
    "Transform a validated slang-module into compile-program forms.
     Returns a list of forms ready for compile-program."
    (let* ([host-imports (if (and (pair? opts) (car opts))
                           (car opts)
                           dns-host-import-forms)]
           [body-forms (slang-module-body mod)]
           ;; Filter out imports and module declaration
           [user-forms (filter (lambda (f)
                                 (not (and (pair? f)
                                           (memq (car f) '(import slang-module)))))
                               body-forms)]
           ;; Lower Slang forms to compile-program subset
           [lowered (apply append (map slang-lower-form user-forms))]
           ;; Lambda lift closures
           [lifted (lambda-lift lowered)]
           ;; Collect static string data for data segments
           [static-strings (collect-static-strings lifted)]
           [string-data-forms (generate-string-data static-strings)]
           ;; Replace (string-from-static #vu8(...)) with (string-from-static offset)
           [lifted (replace-static-strings lifted static-strings)])

      ;; Assemble the complete program
      (append
        ;; 1. Memory and globals
        value-memory-forms
        value-global-forms

        ;; 2. Host imports
        host-imports

        ;; 3. Static data segments (interned strings, constants)
        string-data-forms

        ;; 4. Runtime: tagged values, allocator, Scheme primitives
        value-tag-forms
        value-predicate-forms
        value-accessor-forms
        value-constructor-forms
        gc-all-forms
        (runtime-forms)

        ;; 5. Function table (for closures via call_indirect)
        (if (has-closures? lifted)
          '((define-table 64 256))
          '())

        ;; 6. User program (lifted + lowered)
        lifted)))

  ;; Collect all static string references and assign offsets
  (define (collect-static-strings forms)
    ;; Walk forms looking for (string-from-static #vu8(...))
    (let ([strings '()]
          [offset MEM-STATIC-BASE])
      (define (walk expr)
        (cond
          [(pair? expr)
           (if (and (eq? (car expr) 'string-from-static)
                    (bytevector? (cadr expr)))
             (let ([bv (cadr expr)])
               (unless (assoc bv strings)
                 (set! strings (cons (cons bv offset) strings))
                 (set! offset (+ offset (bytevector-length bv) 4))))  ;; 4 for length prefix
             (for-each walk expr))]
          [else (void)]))
      (for-each walk forms)
      (reverse strings)))

  ;; Generate define-data forms for static strings
  (define (generate-string-data string-table)
    (map (lambda (entry)
           (let* ([bv (car entry)]
                  [offset (cdr entry)]
                  [len (bytevector-length bv)]
                  ;; Prepend 4-byte little-endian length
                  [data (make-bytevector (+ 4 len))])
             (bytevector-u8-set! data 0 (bitwise-and len #xFF))
             (bytevector-u8-set! data 1 (bitwise-and (ash len -8) #xFF))
             (bytevector-u8-set! data 2 (bitwise-and (ash len -16) #xFF))
             (bytevector-u8-set! data 3 (bitwise-and (ash len -24) #xFF))
             (bytevector-copy! bv 0 data 4 len)
             `(define-data ,offset ,data)))
         string-table))

  ;; Replace (string-from-static #vu8(...)) with (string-from-static offset)
  ;; using the offset table produced by collect-static-strings.
  ;; This converts bytevector literals to raw memory addresses so the
  ;; generated WASM calls the runtime string-from-static with an i32.
  (define (replace-static-strings forms string-table)
    (define (replace expr)
      (cond
        [(pair? expr)
         (if (and (eq? (car expr) 'string-from-static)
                  (bytevector? (cadr expr)))
           ;; Replace with the assigned integer offset
           (let ([entry (assoc (cadr expr) string-table)])
             (if entry
               `(string-from-static ,(cdr entry))
               expr))  ;; shouldn't happen if collect was complete
           ;; Otherwise recurse into subforms
           (map replace expr))]
        [else expr]))
    (map replace forms))

  ;; Check if any form references closures
  (define (has-closures? forms)
    (let ([found #f])
      (define (walk expr)
        (when (pair? expr)
          (when (memq (car expr) '(alloc-closure call-closure closure-env-ref))
            (set! found #t))
          (unless found
            (for-each walk expr))))
      (for-each walk forms)
      found))

  ;; Import runtime forms from scheme-runtime module
  (define (runtime-forms)
    ;; These are loaded at compile time from the scheme-runtime module
    ;; We inline them here to avoid a circular dependency
    (let ([rt (with-exception-handler
                (lambda (e) '())
                (lambda ()
                  (let ()
                    (eval '(begin
                             (import (jerboa wasm scheme-runtime))
                             runtime-all-forms)
                          (environment '(chezscheme) '(jerboa wasm scheme-runtime))))
                #:handle-all)])
      (if (pair? rt) rt
        ;; Fallback: minimal runtime if module not available
        '())))

  ;; ================================================================
  ;; Top-level compilation entry points
  ;; ================================================================

  (define (slang-compile-wasm source-path . opts)
    "Compile a Slang source file to a WASM binary (bytevector).

     Parameters:
       source-path - Path to .ss source file

     Keyword options:
       config:      - slang-config record
       host-imports: - list of host import forms (default: dns-host-import-forms)
       verbose:     - Print compilation steps

     Returns: bytevector containing WASM binary"
    (let* ([config (kwarg-wasm 'config: opts (make-slang-config))]
           [verbose? (kwarg-wasm 'verbose: opts #f)]
           [host-imports (kwarg-wasm 'host-imports: opts dns-host-import-forms)]
           ;; Read source
           [forms (call-with-input-file source-path
                    (lambda (p)
                      (let loop ([acc '()])
                        (let ([form (read p)])
                          (if (eof-object? form)
                            (reverse acc)
                            (loop (cons form acc)))))))]
           ;; Parse module declaration
           [mod (parse-slang-module forms)])

      ;; Step 1: Validate
      (when verbose?
        (printf "[slang-wasm] Validating ~a...~n" source-path))

      (let ([errors (slang-validate forms config)])
        (unless (null? errors)
          (when verbose?
            (printf "[slang-wasm] ~a validation error(s):~n" (length errors))
            (for-each
              (lambda (err)
                (printf "  ~a: ~a~n"
                  (slang-error-kind err)
                  (slang-error-message err)))
              errors))
          (raise (car errors))))

      ;; Step 2: Lower, lift, and assemble
      (when verbose?
        (printf "[slang-wasm] Lowering to WASM forms...~n"))

      (let ([wasm-forms (slang->wasm-forms mod host-imports)])

        ;; Step 3: Compile to WASM binary
        (when verbose?
          (printf "[slang-wasm] Compiling ~a forms to WASM...~n"
            (length wasm-forms)))

        (compile-program wasm-forms))))

  (define (slang-compile-wasm-file source-path output-path . opts)
    "Compile a Slang source file and write WASM binary to output-path."
    (let ([wasm-binary (apply slang-compile-wasm source-path opts)])
      (let ([port (open-file-output-port output-path
                    (file-options no-fail)
                    (buffer-mode block)
                    (native-transcoder))])
        (put-bytevector port wasm-binary)
        (close-port port))
      output-path))

  ;; Simple keyword argument helper
  (define (kwarg-wasm key args default)
    (let loop ([rest args])
      (cond
        [(null? rest) default]
        [(null? (cdr rest)) default]
        [(eq? (car rest) key) (cadr rest)]
        [else (loop (cddr rest))])))

) ;; end library
