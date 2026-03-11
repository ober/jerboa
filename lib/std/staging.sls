#!chezscheme
;;; (std staging) — Metaprogramming and Staging
;;;
;;; Step 25: Compile-Time Computation
;;;   at-compile-time  — evaluate expression at expand time, splice result as datum
;;;   define/ct        — define a compile-time constant
;;;
;;; Step 26: Code Generation DSL
;;;   format-id        — create a syntax identifier by string formatting
;;;   struct-fields    — introspect registered struct field names (runtime)
;;;   derive-serializer — generate type-directed serializer at compile time
;;;   derive-printer   — generate pretty-printer at compile time
;;;   quasigen         — quasiquote-based code generation helper
;;;   with-gensyms     — bind fresh gensyms for macro hygiene
;;;
;;; Step 27: Syntax-Rules Extensions
;;;   defrule/guard    — syntax-rules with (where guard) clause filtering
;;;   defrule/rec      — recursive template transformer for tree rewriting
;;;   syntax-walk      — walk a syntax tree applying a transformer

(library (std staging)
  (export
    ;; Step 25
    at-compile-time
    define/ct

    ;; Step 26
    format-id
    struct-fields
    define-staging-type
    derive-serializer
    derive-printer
    quasigen
    with-gensyms

    ;; Step 27
    defrule/guard
    defrule/rec
    syntax-walk)

  (import (chezscheme))

  ;; ========== Step 25: Compile-Time Computation ==========

  ;; (at-compile-time expr)
  ;; Evaluates expr at macro-expansion time using eval.
  ;; The result is spliced in as a quoted datum.
  ;;
  ;; Example:
  ;;   (define pi (at-compile-time (acos -1.0)))
  ;;   ;; expands to: (define pi 3.141592653589793)
  (define-syntax at-compile-time
    (lambda (stx)
      (syntax-case stx ()
        [(_ expr)
         (let* ([kw     (car (syntax->list stx))]  ;; identifier for datum->syntax context
                [result (eval (syntax->datum #'expr)
                              (environment '(chezscheme)))])
           (datum->syntax kw (list 'quote result)))])))

  ;; (define/ct name expr)
  ;; Defines a constant whose value is computed at expand time.
  ;; The runtime definition holds the pre-computed quoted value.
  ;;
  ;; Example:
  ;;   (define/ct max-ports 65535)
  ;;   (define/ct factor (* 6 7))  => defines factor as 42
  (define-syntax define/ct
    (lambda (stx)
      (syntax-case stx ()
        [(_ name expr)
         (let* ([datum-expr (syntax->datum #'expr)]
                [val        (eval datum-expr (environment '(chezscheme)))]
                [quoted-val (list 'quote val)])
           #`(define name #,(datum->syntax #'name quoted-val)))])))

  ;; ========== Step 26: Code Generation DSL ==========

  ;; (format-id context-id fmt arg ...)
  ;; Creates a new syntax identifier by formatting a string, using
  ;; context-id for source location and lexical context.
  ;; Each arg is converted: identifiers → their symbol string, others → format ~a.
  ;;
  ;; Example (use inside a macro transformer):
  ;;   (format-id #'point "~a-x" #'point) => #'point-x identifier
  (define (format-id ctx fmt . args)
    (let* ([str-args (map (lambda (a)
                            (if (identifier? a)
                              (symbol->string (syntax->datum a))
                              (if (string? a) a (format "~a" a))))
                          args)]
           [name (string->symbol (apply format fmt str-args))])
      (datum->syntax ctx name)))

  ;; Runtime struct type registry: sym → (pred fields accessors)
  (define *staging-struct-types* (make-eq-hashtable))

  ;; (define-staging-type name pred (field ...) (acc ...))
  ;; Registers a struct type for runtime introspection via struct-fields.
  (define-syntax define-staging-type
    (syntax-rules ()
      [(_ type-name pred-fn (field ...) (acc ...))
       (hashtable-set! *staging-struct-types* 'type-name
         (list pred-fn '(field ...) (list acc ...)))]))

  ;; (struct-fields name)
  ;; Returns the list of field name symbols for a struct registered with
  ;; define-staging-type. Returns '() if not registered.
  (define (struct-fields name)
    (let ([entry (hashtable-ref *staging-struct-types* name #f)])
      (if entry (cadr entry) '())))

  ;; (derive-serializer struct-name (field ...) (acc ...))
  ;; Generates a serializer procedure at compile time.
  ;; Fields and accessors are given explicitly to avoid phasing issues.
  ;;
  ;; Generated: (define (serialize-<name> obj port) ...)
  ;; For each field f: writes (f . value) cons pair to port.
  ;;
  ;; Example:
  ;;   (derive-serializer point (x y) (point-x point-y))
  ;;   (serialize-point (make-point 3 4) out-port)
  ;;   ;; writes (x . 3) then (y . 4) to out-port
  (define-syntax derive-serializer
    (lambda (stx)
      (syntax-case stx ()
        [(_ struct-name (field ...) (acc ...))
         (let* ([name   (syntax->datum #'struct-name)]
                [fields (syntax->datum #'(field ...))]
                [accs   (syntax->datum #'(acc ...))]
                [ser-id (datum->syntax #'struct-name
                          (string->symbol
                            (string-append "serialize-" (symbol->string name))))])
           (let ([field-writes
                  (map (lambda (f a)
                         (let ([f-stx (datum->syntax #'struct-name f)]
                               [a-stx (datum->syntax #'struct-name a)])
                           #`(write (cons '#,f-stx (#,a-stx obj)) port)))
                       fields accs)])
             #`(define (#,ser-id obj port)
                 #,@field-writes)))])))

  ;; (derive-printer struct-name (field ...) (acc ...))
  ;; Generates a pretty-printer that formats as "#<name field=val ...>".
  ;;
  ;; Example:
  ;;   (derive-printer point (x y) (point-x point-y))
  ;;   (print-point (make-point 3 4)) => "#<point x=3 y=4>"
  (define-syntax derive-printer
    (lambda (stx)
      (syntax-case stx ()
        [(_ struct-name (field ...) (acc ...))
         (let* ([name     (syntax->datum #'struct-name)]
                [fields   (syntax->datum #'(field ...))]
                [accs     (syntax->datum #'(acc ...))]
                [print-id (datum->syntax #'struct-name
                            (string->symbol
                              (string-append "print-" (symbol->string name))))]
                [name-str (symbol->string name)])
           (let ([field-parts
                  (let loop ([fs fields] [as accs] [acc '()])
                    (if (null? fs)
                      (reverse acc)
                      (let ([a-stx (datum->syntax #'struct-name (car as))]
                            [f-str (symbol->string (car fs))])
                        (loop (cdr fs) (cdr as)
                          (cons #`(string-append " " #,f-str "=" (format "~a" (#,a-stx obj)))
                                acc)))))])
             #`(define (#,print-id obj)
                 (string-append "#<" #,name-str
                   #,@field-parts
                   ">"))))])))

  ;; (quasigen ctx-id body ...)
  ;; Returns a lambda that accepts a context identifier and generates
  ;; syntax using the body expressions. Useful for parameterized code generators.
  ;;
  ;; Example:
  ;;   (define gen-adder
  ;;     (quasigen ctx
  ;;       #`(define (#,(format-id ctx "add-~a" ctx) a b) (+ a b))))
  ;;   ;; Then: (gen-adder #'nums) => expands to (define (add-nums a b) (+ a b))
  (define-syntax quasigen
    (syntax-rules ()
      [(_ ctx-id body ...)
       (lambda (ctx-id) body ...)]))

  ;; (with-gensyms (id ...) body ...)
  ;; Binds each id to a fresh generated syntax temp, for use in
  ;; macro transformers to create hygienic temporaries.
  ;;
  ;; Example:
  ;;   (with-gensyms (tmp result)
  ;;     #`(let ([#,tmp (expensive)])
  ;;         (let ([#,result (process #,tmp)])
  ;;           #,result)))
  (define-syntax with-gensyms
    (syntax-rules ()
      [(_ (id ...) body ...)
       (let ([id (car (generate-temporaries (list 'id)))] ...)
         body ...)]))

  ;; ========== Step 27: Syntax-Rules Extensions ==========

  ;; (defrule/guard (name pat ...) (where guard-expr) template)
  ;; (defrule/guard (name pat ...) template)
  ;;
  ;; Defines a macro with an optional compile-time guard.
  ;; If guard-expr evaluates to #f at expand time, the rule doesn't apply.
  ;;
  ;; NOTE: guard-expr runs at compile time via eval; it cannot reference
  ;; runtime bindings. It CAN reference pattern variables as syntax objects.
  ;;
  ;; Example:
  ;;   (defrule/guard (my-add a b) template)  ;; simple, no guard
  (define-syntax defrule/guard
    (lambda (stx)
      (syntax-case stx (where)
        ;; With (where guard-expr)
        [(_ (name . pats) (where guard-expr) template)
         #'(define-syntax name
             (lambda (s)
               (syntax-case s ()
                 [(_ . pats)
                  (eval (syntax->datum #'guard-expr) (environment '(chezscheme)))
                  #'template]
                 [_ (syntax-error s "invalid syntax or guard failed")])))]
        ;; Without guard
        [(_ (name . pats) template)
         #'(define-syntax name
             (syntax-rules ()
               [(_ . pats) template]))])))

  ;; (defrule/rec name transformer-proc)
  ;; Defines a macro that recursively rewrites its argument using transformer-proc.
  ;; transformer-proc: stx → stx | #f
  ;;   - If it returns a syntax object, that replaces the node.
  ;;   - If it returns #f, the node is descended into (for list nodes).
  ;;
  ;; Usage: (name expr) → recursively-transformed-expr
  (define-syntax defrule/rec
    (syntax-rules ()
      [(_ name transformer-proc)
       (define-syntax name
         (lambda (stx)
           (syntax-case stx ()
             [(_ expr)
              (syntax-walk #'expr transformer-proc)])))]))

  ;; (syntax-walk stx proc)
  ;; Walk a syntax tree depth-first, applying proc to each node.
  ;; proc: stx → stx | #f
  ;; Returns a new syntax tree with all proc-returning-non-#f nodes replaced.
  (define (syntax-walk stx proc)
    (let ([result (proc stx)])
      (if result
        result
        (let ([d (syntax->datum stx)])
          (cond
            [(pair? d)
             ;; datum->syntax needs an identifier for context; use first element
             (let* ([parts      (syntax->list stx)]
                    [walked     (map (lambda (sub) (syntax-walk sub proc)) parts)]
                    [ctx-id     (car parts)])  ;; first element as context identifier
               (datum->syntax ctx-id
                 (map syntax->datum walked)))]
            [else stx])))))

  ) ;; end library
