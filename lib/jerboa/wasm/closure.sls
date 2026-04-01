#!chezscheme
;;; (jerboa wasm closure) -- Lambda lifting for Slang-to-WASM compilation
;;;
;;; Transforms Slang source code by hoisting all lambda expressions to
;;; top-level `define` forms with explicit environment parameters.
;;;
;;; Slang's restrictions make this simpler than general Scheme:
;;;   - No call/cc: no upward continuations
;;;   - No set! on captured variables: environments are immutable (copy-on-capture)
;;;   - No eval: all lambdas are visible at compile time
;;;
;;; Transformation:
;;;   (define (f x)
;;;     (let ([g (lambda (y) (+ x y))])
;;;       (g 10)))
;;; →
;;;   (define (__lifted_f_g env y)
;;;     (+ (closure-env-ref env 0) y))
;;;   (define (f x)
;;;     (let ([g (alloc-closure <idx-of-__lifted_f_g> 1)])
;;;       (closure-env-set! g 0 x)
;;;       (call-closure g 10)))
;;;
;;; Higher-order calls (map, filter, etc.) go through call_indirect
;;; using the closure's func-idx field and the function table.

(library (jerboa wasm closure)
  (export
    lambda-lift           ;; (list of forms) -> (list of forms)
    free-variables        ;; (expr bound-set) -> (list of symbols)
    )

  (import (chezscheme))

  ;; ================================================================
  ;; Free variable analysis
  ;; ================================================================

  ;; Return a list of free variables in `expr` that are not in `bound`.
  ;; `bound` is a list of symbols currently in scope.
  (define (free-variables expr bound)
    (unique (fv expr bound)))

  (define (unique lst)
    (let loop ([l lst] [seen '()] [out '()])
      (if (null? l)
        (reverse out)
        (if (memq (car l) seen)
          (loop (cdr l) seen out)
          (loop (cdr l) (cons (car l) seen) (cons (car l) out))))))

  (define (fv expr bound)
    (cond
      ;; Literal: no free variables
      [(or (number? expr) (boolean? expr) (string? expr) (char? expr))
       '()]

      ;; Symbol: free if not bound
      [(symbol? expr)
       (if (memq expr bound) '() (list expr))]

      ;; Compound form
      [(pair? expr)
       (let ([head (car expr)] [args (cdr expr)])
         (case head
           ;; Quote: no free variables
           [(quote) '()]

           ;; Lambda: parameters become bound
           [(lambda)
            (let* ([params (lambda-params (car args))]
                   [body (cdr args)]
                   [new-bound (append params bound)])
              (fv-body body new-bound))]

           ;; Let: binding names are sequential
           [(let)
            (let* ([bindings (car args)]
                   [body (cdr args)]
                   [bind-names (map car bindings)]
                   [bind-exprs (map cadr bindings)]
                   ;; Binding RHS sees outer scope
                   [bind-fvs (apply append (map (lambda (e) (fv e bound)) bind-exprs))]
                   ;; Body sees bindings
                   [body-fvs (fv-body body (append bind-names bound))])
              (append bind-fvs body-fvs))]

           ;; Let*: sequential binding
           [(let*)
            (if (null? (car args))
              (fv-body (cdr args) bound)
              (let* ([bindings (car args)]
                     [body (cdr args)]
                     [first-name (caar bindings)]
                     [first-expr (cadar bindings)]
                     [first-fvs (fv first-expr bound)]
                     [rest-fvs (fv `(let* ,(cdr bindings) ,@body)
                                   (cons first-name bound))])
                (append first-fvs rest-fvs)))]

           ;; Define (in body context): name is bound for body
           [(define)
            (if (pair? (cadr expr))
              ;; (define (name params...) body...)
              (let* ([sig (cadr expr)]
                     [name (car sig)]
                     [params (lambda-params (cdr sig))]
                     [body (cddr expr)]
                     [new-bound (append params (cons name bound))])
                (fv-body body new-bound))
              ;; (define name expr)
              (fv (caddr expr) bound))]

           ;; If/when/unless/and/or/begin: recurse into subexpressions
           [(if)
            (append (fv (car args) bound)
                    (fv (cadr args) bound)
                    (if (null? (cddr args)) '()
                      (fv (caddr args) bound)))]

           [(when unless)
            (append (fv (car args) bound)
                    (fv-body (cdr args) bound))]

           [(and or begin)
            (fv-body args bound)]

           [(cond)
            (apply append
              (map (lambda (clause)
                     (if (eq? (car clause) 'else)
                       (fv-body (cdr clause) bound)
                       (append (fv (car clause) bound)
                               (fv-body (cdr clause) bound))))
                   args))]

           ;; While/set!
           [(while)
            (append (fv (car args) bound)
                    (fv-body (cdr args) bound))]

           [(set!)
            (append (if (memq (car args) bound) '() (list (car args)))
                    (fv (cadr args) bound))]

           ;; Match: simplified — treat patterns as binding
           [(match)
            (let ([scrutinee-fvs (fv (car args) bound)])
              (apply append scrutinee-fvs
                (map (lambda (clause)
                       (let* ([pat (car clause)]
                              [pat-binds (pattern-bindings pat)]
                              [body (cdr clause)])
                         (fv-body body (append pat-binds bound))))
                     (cdr args))))]

           ;; For/collect, for/fold: iterator bindings
           [(for/collect for for/fold)
            ;; Simplified: treat all binding forms as introducing vars
            (let* ([binding-clauses (car args)]
                   [bind-names (map car binding-clauses)]
                   [iter-fvs (apply append
                               (map (lambda (bc) (fv (cadr bc) bound))
                                    binding-clauses))]
                   [body-fvs (fv-body (cdr args) (append bind-names bound))])
              (append iter-fvs body-fvs))]

           ;; Default: function call — recurse into all subexpressions
           [else
            (apply append (map (lambda (e) (fv e bound)) expr))]))]

      [else '()]))

  ;; Free variables in a body (list of expressions)
  (define (fv-body exprs bound)
    (apply append (map (lambda (e) (fv e bound)) exprs)))

  ;; Extract parameter names from a lambda formals list
  (define (lambda-params formals)
    (cond
      [(null? formals) '()]
      [(symbol? formals) (list formals)]  ;; rest arg
      [(pair? formals)
       (let ([p (car formals)])
         (cons (if (pair? p) (car p) p)  ;; handle (name type) params
               (lambda-params (cdr formals))))]
      [else '()]))

  ;; Extract binding names from a match pattern (approximate)
  (define (pattern-bindings pat)
    (cond
      [(symbol? pat)
       (if (eq? pat '_) '() (list pat))]
      [(pair? pat)
       (case (car pat)
         [(quote) '()]
         [(list cons vector)
          (apply append (map pattern-bindings (cdr pat)))]
         [(? =>)
          (if (>= (length pat) 3)
            (pattern-bindings (caddr pat))
            '())]
         [else (apply append (map pattern-bindings (cdr pat)))])]
      [else '()]))

  ;; ================================================================
  ;; Lambda lifting transformation
  ;; ================================================================

  ;; Global counter for generating unique lifted function names
  (define lift-counter 0)

  (define (fresh-lifted-name parent-name)
    (set! lift-counter (+ lift-counter 1))
    (string->symbol
      (string-append "__lifted_"
        (symbol->string parent-name) "_"
        (number->string lift-counter))))

  ;; Main entry point: transform a list of top-level forms.
  ;; Returns a new list of forms with all lambdas hoisted to top-level.
  (define (lambda-lift forms)
    (set! lift-counter 0)
    (let ([lifted '()]     ;; accumulated lifted function definitions
          [result '()])    ;; transformed top-level forms
      ;; Process each top-level form
      (for-each
        (lambda (form)
          (if (and (pair? form) (eq? (car form) 'define) (pair? (cadr form)))
            ;; (define (name params...) body...)
            (let* ([sig (cadr form)]
                   [name (car sig)]
                   [params (cdr sig)]
                   [body (cddr form)]
                   [param-names (map (lambda (p) (if (pair? p) (car p) p)) params)]
                   [toplevel-names (collect-toplevel-names forms)]
                   [ctx (make-lift-context name param-names toplevel-names)])
              (let-values ([(new-body new-lifted) (lift-body body ctx)])
                (set! lifted (append lifted new-lifted))
                (set! result (cons `(define ,sig ,@new-body) result))))
            ;; Non-define forms pass through unchanged
            (set! result (cons form result))))
        forms)
      ;; Return: lifted functions first, then original (transformed) forms
      (append (reverse lifted) (reverse result))))

  ;; Collect all top-level define names (for excluding from free variables)
  (define (collect-toplevel-names forms)
    (let loop ([fs forms] [names '()])
      (if (null? fs)
        names
        (let ([f (car fs)])
          (if (and (pair? f) (eq? (car f) 'define))
            (let ([sig (cadr f)])
              (loop (cdr fs)
                    (cons (if (pair? sig) (car sig) sig) names)))
            (loop (cdr fs) names))))))

  ;; Lift context: tracks scope for lambda lifting
  (define-record-type lift-context
    (fields
      parent-name     ;; symbol: enclosing function name
      bound-vars      ;; list of symbols: locally bound variables
      toplevel-names) ;; list of symbols: top-level function names
    (protocol (lambda (new)
      (lambda (parent bound toplevel)
        (new parent bound toplevel)))))

  ;; Extend context with additional bound variables
  (define (ctx-extend ctx new-vars)
    (make-lift-context
      (lift-context-parent-name ctx)
      (append new-vars (lift-context-bound-vars ctx))
      (lift-context-toplevel-names ctx)))

  ;; Lift lambdas in a body (list of expressions)
  ;; Returns (values new-body lifted-defines)
  (define (lift-body body ctx)
    (let loop ([exprs body] [new-body '()] [lifted '()])
      (if (null? exprs)
        (values (reverse new-body) lifted)
        (let-values ([(new-expr new-lifted) (lift-expr (car exprs) ctx)])
          (loop (cdr exprs)
                (cons new-expr new-body)
                (append lifted new-lifted))))))

  ;; Lift lambdas in a single expression.
  ;; Returns (values new-expr lifted-defines)
  (define (lift-expr expr ctx)
    (cond
      ;; Atoms pass through
      [(or (number? expr) (boolean? expr) (string? expr)
           (char? expr) (symbol? expr))
       (values expr '())]

      [(pair? expr)
       (let ([head (car expr)] [args (cdr expr)])
         (case head
           ;; Lambda: the core transformation
           [(lambda)
            (lift-lambda expr ctx)]

           ;; Let: process bindings and body
           [(let)
            (let* ([bindings (car args)]
                   [body (cdr args)]
                   [bind-names (map car bindings)])
              (let loop ([bs bindings] [new-bs '()] [lifted '()])
                (if (null? bs)
                  (let ([inner-ctx (ctx-extend ctx bind-names)])
                    (let-values ([(new-body body-lifted) (lift-body body inner-ctx)])
                      (values `(let ,(reverse new-bs) ,@new-body)
                              (append lifted body-lifted))))
                  (let-values ([(new-val val-lifted) (lift-expr (cadar bs) ctx)])
                    (loop (cdr bs)
                          (cons (list (caar bs) new-val) new-bs)
                          (append lifted val-lifted))))))]

           ;; Let*: similar to let but sequential
           [(let*)
            (let* ([bindings (car args)]
                   [body (cdr args)])
              (let loop ([bs bindings] [new-bs '()] [cur-ctx ctx] [lifted '()])
                (if (null? bs)
                  (let-values ([(new-body body-lifted) (lift-body body cur-ctx)])
                    (values `(let* ,(reverse new-bs) ,@new-body)
                            (append lifted body-lifted)))
                  (let-values ([(new-val val-lifted) (lift-expr (cadar bs) cur-ctx)])
                    (loop (cdr bs)
                          (cons (list (caar bs) new-val) new-bs)
                          (ctx-extend cur-ctx (list (caar bs)))
                          (append lifted val-lifted))))))]

           ;; If
           [(if)
            (let-values ([(new-test test-l) (lift-expr (car args) ctx)]
                         [(new-then then-l) (lift-expr (cadr args) ctx)])
              (if (null? (cddr args))
                (values `(if ,new-test ,new-then)
                        (append test-l then-l))
                (let-values ([(new-else else-l) (lift-expr (caddr args) ctx)])
                  (values `(if ,new-test ,new-then ,new-else)
                          (append test-l then-l else-l)))))]

           ;; When/unless
           [(when unless)
            (let-values ([(new-test test-l) (lift-expr (car args) ctx)])
              (let-values ([(new-body body-l) (lift-body (cdr args) ctx)])
                (values `(,head ,new-test ,@new-body)
                        (append test-l body-l))))]

           ;; Begin
           [(begin)
            (let-values ([(new-body body-l) (lift-body args ctx)])
              (values `(begin ,@new-body) body-l))]

           ;; While
           [(while)
            (let-values ([(new-test test-l) (lift-expr (car args) ctx)]
                         [(new-body body-l) (lift-body (cdr args) ctx)])
              (values `(while ,new-test ,@new-body)
                      (append test-l body-l)))]

           ;; Set!
           [(set!)
            (let-values ([(new-val val-l) (lift-expr (cadr args) ctx)])
              (values `(set! ,(car args) ,new-val) val-l))]

           ;; And/or
           [(and or)
            (let-values ([(new-args args-l) (lift-args args ctx)])
              (values `(,head ,@new-args) args-l))]

           ;; Cond
           [(cond)
            (let loop ([clauses args] [new-clauses '()] [lifted '()])
              (if (null? clauses)
                (values `(cond ,@(reverse new-clauses)) lifted)
                (let* ([clause (car clauses)]
                       [test (car clause)]
                       [body (cdr clause)])
                  (if (eq? test 'else)
                    (let-values ([(new-body body-l) (lift-body body ctx)])
                      (loop (cdr clauses)
                            (cons `(else ,@new-body) new-clauses)
                            (append lifted body-l)))
                    (let-values ([(new-test test-l) (lift-expr test ctx)]
                                 [(new-body body-l) (lift-body body ctx)])
                      (loop (cdr clauses)
                            (cons `(,new-test ,@new-body) new-clauses)
                            (append lifted test-l body-l)))))))]

           ;; Quote
           [(quote) (values expr '())]

           ;; Default: function call or other form
           [else
            (let-values ([(new-args args-l) (lift-args args ctx)])
              ;; Also lift the head if it could be an expression
              (if (symbol? head)
                (values `(,head ,@new-args) args-l)
                (let-values ([(new-head head-l) (lift-expr head ctx)])
                  (values `(,new-head ,@new-args)
                          (append head-l args-l)))))]))]

      [else (values expr '())]))

  ;; Lift lambdas in a list of argument expressions
  (define (lift-args args ctx)
    (let loop ([as args] [new-as '()] [lifted '()])
      (if (null? as)
        (values (reverse new-as) lifted)
        (let-values ([(new-a a-l) (lift-expr (car as) ctx)])
          (loop (cdr as) (cons new-a new-as) (append lifted a-l))))))

  ;; ================================================================
  ;; Lambda lifting core: transform a lambda into a closure allocation
  ;; ================================================================

  (define (lift-lambda expr ctx)
    (let* ([formals (cadr expr)]
           [body (cddr expr)]
           [param-names (lambda-params formals)]
           ;; Compute free variables (exclude top-level names and built-ins)
           [all-bound (append param-names
                             (lift-context-bound-vars ctx)
                             (lift-context-toplevel-names ctx))]
           ;; Also exclude known runtime functions
           [runtime-names '(alloc alloc-closure closure-env-set! closure-env-ref
                            closure-func-idx call-closure
                            cons-val pair-car pair-cdr
                            tag-fixnum untag-fixnum is-fixnum is-heap-ptr
                            write-header heap-type-tag heap-obj-size
                            is-pair is-string is-bytevector is-vector
                            is-symbol is-closure is-nil is-true is-false
                            scheme-cons scheme-car scheme-cdr
                            alloc-string alloc-bytevector alloc-vector
                            alloc-symbol alloc-record alloc-flonum
                            string-length-bytes string-byte-ref string-byte-set!
                            bytevector-length-val bytevector-u8-ref-val
                            bytevector-u8-set-val! vector-length-val
                            vector-ref-val vector-set-val!
                            arena-reset arena-mark
                            root-push root-pop root-peek
                            grow-memory
                            fx+ fx- fx* fx/ fx-mod
                            fx< fx> fx<= fx>= fx=
                            scheme-eq? scheme-eqv? scheme-equal?
                            io-read-u16be io-write-u16be
                            io-read-u32be io-write-u32be
                            mem-copy mem-zero
                            scheme-length scheme-append scheme-reverse
                            scheme-null? scheme-list?
                            scheme-string=? scheme-string-compare
                            scheme-make-bytevector scheme-bytevector-length
                            scheme-bytevector-u8-ref scheme-bytevector-u8-set!
                            scheme-make-vector scheme-vector-length
                            scheme-vector-ref scheme-vector-set!
                            scheme-string-length scheme-string-byte-length
                            scheme-string-ref
                            is-truthy is-number is-string is-symbol
                            is-boolean is-vector is-bytevector is-eof is-nil
                            wasm-bool->scheme
                            fx-negate fx-abs fx-bitwise-and fx-bitwise-or
                            fx-bitwise-xor fx-ash
                            fx< fx> fx<= fx>= fx= fx-mod
                            scheme-list-ref scheme-assq scheme-memq
                            scheme-bytevector-copy
                            intern-symbol string-from-static
                            to-bool scheme-bool->wasm)]
           [bound-with-runtime (append runtime-names all-bound)]
           [free-vars (free-variables `(begin ,@body) bound-with-runtime)]
           ;; Generate lifted function name
           [lifted-name (fresh-lifted-name (lift-context-parent-name ctx))]
           ;; New formals: env parameter + original params
           [env-param 'env]
           [new-formals (cons env-param formals)])

      ;; Transform body: replace free variable references with
      ;; (closure-env-ref env <index>)
      (let* ([env-map (let loop ([vars free-vars] [i 0])
                        (if (null? vars) '()
                          (cons (cons (car vars) i)
                                (loop (cdr vars) (+ i 1)))))]
             ;; Transform body to use env references
             [new-body (map (lambda (e) (subst-free-vars e env-map env-param))
                           body)]
             ;; The lifted function definition
             [lifted-def `(define (,lifted-name ,@new-formals) ,@new-body)]
             ;; The closure allocation expression
             [n-free (length free-vars)]
             ;; Build the closure allocation + env filling
             [closure-expr
              (if (= n-free 0)
                ;; No free variables: still create a closure for uniformity
                `(alloc-closure 0 0)  ;; func-idx filled in later by wasm-target
                `(let ([__clos (alloc-closure 0 ,n-free)])
                   ,@(map (lambda (var)
                            (let ([idx (cdr (assq var env-map))])
                              `(closure-env-set! __clos ,idx ,var)))
                          free-vars)
                   __clos))])

        ;; Also recursively lift any lambdas inside the lifted body
        (let ([inner-ctx (make-lift-context lifted-name
                           (cons env-param param-names)
                           (lift-context-toplevel-names ctx))])
          (let-values ([(final-body inner-lifted) (lift-body new-body inner-ctx)])
            (let ([final-def `(define (,lifted-name ,@new-formals) ,@final-body)])
              (values closure-expr
                      (append inner-lifted (list final-def)))))))))

  ;; Substitute free variable references with closure-env-ref calls
  (define (subst-free-vars expr env-map env-param)
    (cond
      [(symbol? expr)
       (let ([entry (assq expr env-map)])
         (if entry
           `(closure-env-ref ,env-param ,(cdr entry))
           expr))]

      [(pair? expr)
       (let ([head (car expr)])
         (case head
           [(quote) expr]
           [(lambda)
            ;; Don't substitute inside lambda params, only body
            (let ([formals (cadr expr)]
                  [body (cddr expr)]
                  [param-names (lambda-params (cadr expr))])
              ;; Remove params from env-map (they shadow captures)
              (let ([inner-map (filter (lambda (e)
                                         (not (memq (car e) param-names)))
                                       env-map)])
                `(lambda ,formals
                   ,@(map (lambda (e) (subst-free-vars e inner-map env-param))
                          body))))]
           [(let)
            (let* ([bindings (cadr expr)]
                   [body (cddr expr)]
                   [new-bindings
                    (map (lambda (b)
                           (list (car b) (subst-free-vars (cadr b) env-map env-param)))
                         bindings)]
                   [bind-names (map car bindings)]
                   [inner-map (filter (lambda (e)
                                        (not (memq (car e) bind-names)))
                                      env-map)])
              `(let ,new-bindings
                 ,@(map (lambda (e) (subst-free-vars e inner-map env-param))
                        body)))]
           [(let*)
            (let* ([bindings (cadr expr)]
                   [body (cddr expr)])
              ;; Process bindings sequentially, removing names as we go
              (let loop ([bs bindings] [new-bs '()] [cur-map env-map])
                (if (null? bs)
                  `(let* ,(reverse new-bs)
                     ,@(map (lambda (e) (subst-free-vars e cur-map env-param))
                            body))
                  (let ([name (caar bs)]
                        [val (subst-free-vars (cadar bs) cur-map env-param)])
                    (loop (cdr bs)
                          (cons (list name val) new-bs)
                          (filter (lambda (e) (not (eq? (car e) name)))
                                  cur-map))))))]
           [(set!)
            `(set! ,(cadr expr)
                   ,(subst-free-vars (caddr expr) env-map env-param))]
           [else
            (map (lambda (e) (subst-free-vars e env-map env-param)) expr)]))]

      [else expr]))

) ;; end library
