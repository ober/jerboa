#!chezscheme
;;; (std typed infer) — Bidirectional type inference engine
;;;
;;; Type representation (symbolic S-expressions, no records):
;;;   Primitive types:  fixnum flonum string boolean symbol pair null void any never
;;;   Function type:    (-> arg-type ... return-type)
;;;   List type:        (list-of element-type)
;;;   Vector type:      (vector-of element-type)
;;;   Union type:       (union type1 type2 ...)
;;;   Refinement type:  (refine base-type pred-symbol)
;;;
;;; API:
;;;   (infer-type expr env)               — infer type of expr; returns type or #f
;;;   (check-type expr expected-type env) — check; collect errors in *type-errors*
;;;   (unify-types t1 t2)                 — unified type or #f
;;;   (subtype? t1 t2)                    — is t1 a subtype of t2?
;;;   (type-error? x)                     — predicate
;;;   (make-type-error msg loc expected actual) — constructor
;;;   (type-error-message te)             — string
;;;   (type-error-location te)            — location info or #f
;;;   (type-error-expected te)            — expected type
;;;   (type-error-actual te)              — actual type
;;;   *type-errors*                       — parameter: current error list
;;;   (reset-type-errors!)                — clear accumulated errors
;;;   (with-type-errors-collected thunk)  — run thunk, return list of errors

(library (std typed infer)
  (export
    infer-type
    check-type
    unify-types
    subtype?
    type-error?
    make-type-error
    type-error-message
    type-error-location
    type-error-expected
    type-error-actual
    *type-errors*
    reset-type-errors!
    with-type-errors-collected)

  (import (chezscheme) (std typed env))

  ;; ========== Type error record ==========

  (define-record-type %type-error
    (fields
      (immutable message)
      (immutable location)
      (immutable expected)
      (immutable actual))
    (sealed #t))

  (define (type-error? x) (%type-error? x))
  (define (make-type-error msg loc expected actual)
    (make-%type-error msg loc expected actual))
  (define (type-error-message te)  (%type-error-message  te))
  (define (type-error-location te) (%type-error-location te))
  (define (type-error-expected te) (%type-error-expected te))
  (define (type-error-actual te)   (%type-error-actual   te))

  ;; ========== Error accumulator ==========

  (define *type-errors*
    (make-parameter '()))

  (define (add-type-error! err)
    (*type-errors* (cons err (*type-errors*))))

  (define (reset-type-errors!)
    (*type-errors* '()))

  ;; Run thunk under a fresh error accumulator; return list of collected errors.
  (define (with-type-errors-collected thunk)
    (parameterize ([*type-errors* '()])
      (thunk)
      (reverse (*type-errors*))))

  ;; ========== Primitive type set ==========

  (define *primitive-types*
    '(fixnum flonum string boolean symbol pair null void any never char
      number integer real procedure bytevector vector list))

  (define (primitive-type? t)
    (and (symbol? t) (memq t *primitive-types*) #t))

  ;; ========== Subtype relation ==========
  ;;
  ;; The relation is intentionally small and conservative.
  ;; Unknown types are treated as 'any (compatible with everything).

  (define (subtype? t1 t2)
    (cond
      ;; Everything is a subtype of 'any
      [(eq? t2 'any)  #t]
      ;; 'never is a subtype of everything
      [(eq? t1 'never) #t]
      ;; Reflexivity
      [(equal? t1 t2) #t]
      ;; Numeric hierarchy
      [(and (eq? t1 'fixnum) (eq? t2 'integer))   #t]
      [(and (eq? t1 'fixnum) (eq? t2 'real))      #t]
      [(and (eq? t1 'fixnum) (eq? t2 'number))    #t]
      [(and (eq? t1 'flonum) (eq? t2 'real))      #t]
      [(and (eq? t1 'flonum) (eq? t2 'number))    #t]
      [(and (eq? t1 'integer) (eq? t2 'real))     #t]
      [(and (eq? t1 'integer) (eq? t2 'number))   #t]
      [(and (eq? t1 'real)    (eq? t2 'number))   #t]
      ;; pair is a subtype of list (non-null list)
      [(and (eq? t1 'pair) (eq? t2 'list))        #t]
      ;; null is a subtype of list
      [(and (eq? t1 'null) (eq? t2 'list))        #t]
      ;; (list-of T) is a subtype of list
      [(and (list-of-type? t1) (eq? t2 'list))    #t]
      ;; (list-of T1) ≤ (list-of T2) when T1 ≤ T2
      [(and (list-of-type? t1) (list-of-type? t2))
       (subtype? (list-of-elem t1) (list-of-elem t2))]
      ;; (vector-of T1) ≤ (vector-of T2) when T1 ≤ T2
      [(and (vector-of-type? t1) (vector-of-type? t2))
       (subtype? (vector-of-elem t1) (vector-of-elem t2))]
      ;; (vector-of T) ≤ vector
      [(and (vector-of-type? t1) (eq? t2 'vector)) #t]
      ;; t1 ≤ (union ...) if t1 ≤ any member
      [(union-type? t2)
       (exists (lambda (member) (subtype? t1 member)) (union-members t2))]
      ;; (union ...) ≤ t2 if every member ≤ t2
      [(union-type? t1)
       (for-all (lambda (member) (subtype? member t2)) (union-members t1))]
      ;; (refine base pred) ≤ base
      [(and (refine-type? t1) (equal? (refine-base t1) t2)) #t]
      ;; (refine base pred) ≤ t2 via base ≤ t2
      [(refine-type? t1) (subtype? (refine-base t1) t2)]
      ;; Function types: contravariant args, covariant return
      [(and (arrow-type? t1) (arrow-type? t2))
       (let ([args1 (arrow-args t1)] [ret1 (arrow-ret t1)]
             [args2 (arrow-args t2)] [ret2 (arrow-ret t2)])
         (and (= (length args1) (length args2))
              (for-all subtype? args2 args1)   ; contravariant
              (subtype? ret1 ret2)))]
      [else #f]))

  ;; ========== Type shape helpers ==========

  (define (list-of-type? t)
    (and (pair? t) (eq? (car t) 'list-of) (= (length t) 2)))
  (define (list-of-elem t) (cadr t))

  (define (vector-of-type? t)
    (and (pair? t) (eq? (car t) 'vector-of) (= (length t) 2)))
  (define (vector-of-elem t) (cadr t))

  (define (union-type? t)
    (and (pair? t) (eq? (car t) 'union) (>= (length t) 2)))
  (define (union-members t) (cdr t))

  (define (refine-type? t)
    (and (pair? t) (eq? (car t) 'refine) (= (length t) 3)))
  (define (refine-base t) (cadr t))
  (define (refine-pred t) (caddr t))

  (define (arrow-type? t)
    (and (pair? t) (eq? (car t) '->) (>= (length t) 2)))
  (define (arrow-args t) (reverse (cdr (reverse (cdr t)))))
  (define (arrow-ret  t) (car (reverse (cdr t))))

  ;; ========== Unification ==========
  ;;
  ;; Returns the most specific type that is a supertype of both t1 and t2,
  ;; or #f if the types are structurally incompatible.

  (define (unify-types t1 t2)
    (cond
      [(equal? t1 t2)      t1]
      [(eq? t1 'any)       t2]
      [(eq? t2 'any)       t1]
      [(eq? t1 'never)     t2]
      [(eq? t2 'never)     t1]
      [(subtype? t1 t2)    t2]
      [(subtype? t2 t1)    t1]
      ;; Numeric widening
      [(and (memq t1 '(fixnum flonum integer real)) (memq t2 '(fixnum flonum integer real)))
       'number]
      ;; Structural: list-of
      [(and (list-of-type? t1) (list-of-type? t2))
       (let ([u (unify-types (list-of-elem t1) (list-of-elem t2))])
         (if u `(list-of ,u) 'list))]
      ;; Structural: vector-of
      [(and (vector-of-type? t1) (vector-of-type? t2))
       (let ([u (unify-types (vector-of-elem t1) (vector-of-elem t2))])
         (if u `(vector-of ,u) 'vector))]
      ;; Create union rather than lose information entirely
      [(union-type? t1)
       (let ([members (union-members t1)])
         (if (exists (lambda (m) (subtype? t2 m)) members)
           t1
           `(union ,@members ,t2)))]
      [(union-type? t2)
       (unify-types t2 t1)]
      ;; Default: form a (union t1 t2)
      [else `(union ,t1 ,t2)]))

  ;; ========== Built-in function type knowledge ==========
  ;;
  ;; A table mapping Scheme procedure names to a type-checking function:
  ;;   (infer-call name arg-types) → return-type or #f

  (define (infer-builtin-call name arg-types)
    (case name
      ;; Arithmetic
      [(+)
       (cond
         [(null? arg-types) 'fixnum]
         [(for-all (lambda (t) (eq? t 'fixnum)) arg-types) 'fixnum]
         [(exists  (lambda (t) (eq? t 'flonum)) arg-types) 'flonum]
         [else 'number])]
      [(-)
       (cond
         [(for-all (lambda (t) (eq? t 'fixnum)) arg-types) 'fixnum]
         [(exists  (lambda (t) (eq? t 'flonum)) arg-types) 'flonum]
         [else 'number])]
      [(*)
       (cond
         [(for-all (lambda (t) (eq? t 'fixnum)) arg-types) 'fixnum]
         [(exists  (lambda (t) (eq? t 'flonum)) arg-types) 'flonum]
         [else 'number])]
      [(/)
       (if (exists (lambda (t) (eq? t 'flonum)) arg-types) 'flonum 'number)]
      ;; String operations
      [(string-append)    'string]
      [(string-length)    'fixnum]
      [(substring)        'string]
      [(string-ref)       'char]
      [(string->number)   '(union fixnum #f)]
      [(number->string)   'string]
      [(string->symbol)   'symbol]
      [(symbol->string)   'string]
      [(string-copy)      'string]
      [(string-upcase string-downcase string-foldcase) 'string]
      ;; Pair / list operations
      [(car)
       (if (and (pair? arg-types) (list-of-type? (car arg-types)))
         (list-of-elem (car arg-types))
         'any)]
      [(cdr)
       (if (and (pair? arg-types) (list-of-type? (car arg-types)))
         `(list-of ,(list-of-elem (car arg-types)))
         'any)]
      [(cons)    'pair]
      [(list)    `(list-of any)]
      [(append)  'list]
      [(reverse) 'list]
      [(length)  'fixnum]
      [(map)     `(list-of any)]
      [(filter)  `(list-of any)]
      [(for-each) 'void]
      ;; Predicates
      [(null? pair? list? string? symbol? number? integer? real?
        fixnum? flonum? boolean? char? vector? procedure? bytevector?
        eq? eqv? equal? zero? positive? negative? odd? even?
        string=? string<? string>? string<=? string>=?
        char=? char<? char>? char<=? char>=?)
       'boolean]
      [(not) 'boolean]
      ;; Comparison
      [(< > <= >= =) 'boolean]
      ;; I/O
      [(display write newline write-char) 'void]
      [(read)        'any]
      [(read-char)   'char]
      ;; Conversions
      [(char->integer)   'fixnum]
      [(integer->char)   'char]
      [(exact->inexact inexact) 'flonum]
      [(inexact->exact exact)   'integer]
      [(floor ceiling truncate round) 'integer]
      [(sqrt exp log sin cos tan asin acos atan) 'flonum]
      [(abs)
       (if (and (pair? arg-types) (eq? (car arg-types) 'fixnum))
         'fixnum
         'number)]
      [(min max)
       (if (for-all (lambda (t) (eq? t 'fixnum)) arg-types)
         'fixnum
         'number)]
      [(expt) 'number]
      ;; Vector operations
      [(make-vector vector) `(vector-of any)]
      [(vector-ref)  'any]
      [(vector-set!) 'void]
      [(vector-length) 'fixnum]
      [(vector-copy)   `(vector-of any)]
      ;; Misc
      [(values) 'any]
      [(apply)  'any]
      [(error)  'never]
      [(void)   'void]
      [(gensym) 'symbol]
      [(make-string) 'string]
      [(make-list)   `(list-of any)]
      [else #f]))

  ;; ========== Argument type checking for builtins ==========

  ;; Emit an error if arg-type is not a subtype of expected.
  ;; Returns #t if OK, #f if mismatch.
  (define (check-arg-type! who idx arg-type expected-type expr)
    (if (subtype? arg-type expected-type)
      #t
      (begin
        (add-type-error!
          (make-type-error
            (format "~a: argument ~a expects ~a, got ~a"
                    who idx expected-type arg-type)
            expr
            expected-type
            arg-type))
        #f)))

  ;; Check argument types for well-known builtins that have specific arg reqs.
  (define (check-builtin-arg-types! name arg-types call-expr)
    (case name
      [(string-length string-copy string-upcase string-downcase string-foldcase
        string->number string->symbol)
       (when (pair? arg-types)
         (check-arg-type! name 1 (car arg-types) 'string call-expr))]
      [(string-append)
       (let loop ([args arg-types] [i 1])
         (when (pair? args)
           (check-arg-type! name i (car args) 'string call-expr)
           (loop (cdr args) (+ i 1))))]
      [(car cdr)
       (when (pair? arg-types)
         (check-arg-type! name 1 (car arg-types) 'pair call-expr))]
      [(vector-ref vector-set!)
       (when (pair? arg-types)
         (check-arg-type! name 1 (car arg-types) 'vector call-expr))
       (when (and (pair? arg-types) (pair? (cdr arg-types)))
         (check-arg-type! name 2 (cadr arg-types) 'fixnum call-expr))]
      [(symbol->string)
       (when (pair? arg-types)
         (check-arg-type! name 1 (car arg-types) 'symbol call-expr))]
      [(char->integer)
       (when (pair? arg-types)
         (check-arg-type! name 1 (car arg-types) 'char call-expr))]
      [(integer->char)
       (when (pair? arg-types)
         (check-arg-type! name 1 (car arg-types) 'fixnum call-expr))]
      [else (void)]))

  ;; ========== Type inference ==========
  ;;
  ;; Bidirectional: infer-type synthesizes a type; check-type checks against
  ;; a given expected type, accumulating errors in *type-errors*.

  ;; Infer the type of expr in env.  Returns a type descriptor or #f.
  (define (infer-type expr env)
    (cond
      ;; Self-evaluating literals
      [(fixnum? expr)   'fixnum]
      [(flonum? expr)   'flonum]
      [(string? expr)   'string]
      [(boolean? expr)  'boolean]
      [(char? expr)     'char]
      [(null? expr)     'null]
      [(symbol? expr)
       ;; Variable reference
       (or (type-env-lookup env expr) 'any)]
      [(pair? expr)
       (infer-pair expr env)]
      [else 'any]))

  ;; Infer the type of a compound (pair) expression.
  (define (infer-pair expr env)
    (let ([head (car expr)]
          [args (cdr expr)])
      (case head
        ;; Special forms
        [(quote)
         (let ([datum (car args)])
           (cond
             [(fixnum? datum)  'fixnum]
             [(flonum? datum)  'flonum]
             [(string? datum)  'string]
             [(boolean? datum) 'boolean]
             [(char? datum)    'char]
             [(null? datum)    'null]
             [(symbol? datum)  'symbol]
             [(pair? datum)    'pair]
             [(vector? datum)  'vector]
             [else 'any]))]
        [(if)
         (let ([_ (car args)]
               [then (cadr args)]
               [else-branch (if (= (length args) 3) (caddr args) #f)])
           (let ([t1 (infer-type then env)]
                 [t2 (if else-branch (infer-type else-branch env) 'void)])
             (unify-types t1 t2)))]
        [(begin)
         (let loop ([forms args] [last 'void])
           (if (null? forms)
             last
             (loop (cdr forms) (infer-type (car forms) env))))]
        [(let)
         (if (symbol? (car args))
           ;; Named let — treat as any
           'any
           (let* ([bindings (car args)]
                  [body     (cdr args)]
                  [binding-types
                   (map (lambda (b)
                          (cons (car b) (infer-type (cadr b) env)))
                        bindings)]
                  [child-env (type-env-extend env binding-types)])
             (infer-body body child-env)))]
        [(let*)
         (let loop ([bindings (car args)] [cur-env env])
           (if (null? bindings)
             (infer-body (cdr args) cur-env)
             (let* ([b    (car bindings)]
                    [name (car b)]
                    [val-type (infer-type (cadr b) cur-env)]
                    [next-env (type-env-extend cur-env (list (cons name val-type)))])
               (loop (cdr bindings) next-env))))]
        [(letrec letrec*)
         ;; Bind all names to 'any in env, then infer body
         (let* ([bindings (car args)]
                [names    (map car bindings)]
                [child-env (type-env-extend env (map (lambda (n) (cons n 'any)) names))])
           (infer-body (cdr args) child-env))]
        [(lambda)
         ;; Return a function type with 'any for all params
         (let* ([params (car args)]
                [arity  (if (list? params) (length params) -1)]
                [arg-types (make-list (max 0 arity) 'any)])
           `(-> ,@arg-types any))]
        [(define)
         ;; Top-level / internal define — result is void
         'void]
        [(set!)
         'void]
        [(cond)
         ;; Infer each branch and unify
         (let loop ([clauses args] [result 'never])
           (if (null? clauses)
             result
             (let* ([clause (car clauses)]
                    [test   (car clause)]
                    [body   (cdr clause)])
               (if (and (symbol? test) (eq? test 'else))
                 (loop (cdr clauses)
                       (unify-types result (infer-body body env)))
                 (loop (cdr clauses)
                       (unify-types result (infer-body body env)))))))]
        [(and)
         (if (null? args)
           'boolean
           (infer-type (car (reverse args)) env))]
        [(or)
         (if (null? args)
           'boolean
           (let ([types (map (lambda (a) (infer-type a env)) args)])
             (fold-right unify-types 'never types)))]
        [(when unless)
         'void]
        [(case)
         'any]
        [(do)
         'any]
        [(guard)
         'any]
        [(values)
         'any]
        [(with-syntax syntax-rules define-syntax let-syntax letrec-syntax)
         'void]
        [else
         ;; Function call: infer callee type then look up builtin knowledge
         (if (symbol? head)
           (let ([arg-types (map (lambda (a) (infer-type a env)) args)])
             ;; Check argument types for known builtins
             (check-builtin-arg-types! head arg-types expr)
             (or (infer-builtin-call head arg-types)
                 ;; Check if head is bound to a function type in env
                 (let ([head-type (type-env-lookup env head)])
                   (if (and head-type (arrow-type? head-type))
                     (arrow-ret head-type)
                     'any))))
           'any)])))

  ;; Infer the type of a body (list of forms); return type of last form.
  (define (infer-body body env)
    (if (null? body)
      'void
      (let loop ([forms body])
        (if (null? (cdr forms))
          (infer-type (car forms) env)
          (begin
            (infer-type (car forms) env)
            (loop (cdr forms)))))))

  ;; ========== Type checking (bidirectional) ==========

  ;; Check that expr has expected-type in env.
  ;; Adds errors to *type-errors* for any mismatches found.
  (define (check-type expr expected-type env)
    (let ([actual (infer-type expr env)])
      (unless (or (eq? expected-type 'any)
                  (eq? actual 'any)
                  (subtype? actual expected-type))
        (add-type-error!
          (make-type-error
            (format "type mismatch: expected ~a, got ~a in ~s"
                    expected-type actual expr)
            expr
            expected-type
            actual)))
      actual))

) ;; end library
