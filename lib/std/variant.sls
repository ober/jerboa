#!chezscheme
;;; (std variant) — Exhaustive variant matching (Zig/Rust-inspired)
;;;
;;; Provides `defvariant` for declaring closed sum types (tagged unions)
;;; with compile-time exhaustiveness checking via `match-variant`.
;;;
;;; Example:
;;;   (defvariant shape
;;;     (circle radius)
;;;     (rect width height)
;;;     (triangle base height))
;;;
;;; Generates:
;;;   - shape/circle, shape/rect, shape/triangle — constructors
;;;   - shape/circle?, shape/rect?, shape/triangle? — predicates
;;;   - shape/circle-radius, shape/rect-width, etc. — accessors
;;;   - shape? — variant-wide predicate (any variant)
;;;   - shape/variants — '(circle rect triangle) — the closed tag set
;;;
;;; Usage:
;;;   (match-variant shape val
;;;     [(circle r) (* pi r r)]
;;;     [(rect w h) (* w h)])
;;;   ;; ERROR at expand time: unhandled variant: triangle
;;;
;;; Use `_` or `else` to explicitly opt out of exhaustiveness checking.

(library (std variant)
  (export
    defvariant
    match-variant
    variant-tags
    variant?
    *variant-registry*)

  (import (chezscheme))

  ;; --- Runtime registry for variant types ---
  ;; Maps variant-name → list of (tag-sym field-count pred acc ...)
  ;; where pred/acc are actual procedure references
  (define *variant-registry* (make-eq-hashtable))

  ;; --- Compile-time registry (meta phase) ---
  ;; Maps variant-name → list of (tag-sym field-count pred-name acc-name ...)
  ;; where pred-name/acc-name are symbols
  (meta define *ct-variant-registry* (make-eq-hashtable))

  ;; variant-tags: get the list of tag symbols for a variant type
  (define (variant-tags name)
    (let ([info (hashtable-ref *variant-registry* name #f)])
      (if info
        (map car info)
        (error 'variant-tags "unknown variant type" name))))

  ;; variant?: check if a value is an instance of any variant of the named type
  (define (variant? name val)
    (let ([info (hashtable-ref *variant-registry* name #f)])
      (if info
        (exists (lambda (entry)
                  (let ([pred (caddr entry)])
                    (pred val)))
                info)
        (error 'variant? "unknown variant type" name))))

  ;; --- Helper macro for generating a single variant case record ---
  ;; Uses syntax-rules to avoid Chez define-record-type expansion issues.
  ;; Generates:
  ;;   - An internal record type with Chez-standard naming
  ;;   - Public aliases for constructor, predicate, and accessors
  (define-syntax %define-variant-case
    (syntax-rules ()
      ;; No fields case
      [(_ ctor-name pred-name ())
       (begin
         (define-record-type ctor-name (fields)))]
      ;; With fields: (field acc) ...
      [(_ ctor-name pred-name ((field acc) ...))
       (begin
         (define-record-type ctor-name
           (fields (immutable field acc) ...)))]))

  ;; --- Compile-time helpers (meta) ---

  ;; Parse a variant case: (tag field ...)
  ;; Returns: (tag-sym (field ...) ctor-name pred-name (acc-name ...))
  (meta define (parse-variant-case var-name case-stx)
    (syntax-case case-stx ()
      [(tag field ...)
       (let* ([tag-sym (syntax->datum #'tag)]
              [fields (syntax->list #'(field ...))]
              [field-syms (map syntax->datum fields)]
              [var-str (symbol->string var-name)]
              [tag-str (symbol->string tag-sym)])
         (list tag-sym
               field-syms
               ;; constructor: var-name/tag
               (string->symbol (format "~a/~a" var-str tag-str))
               ;; predicate: var-name/tag?
               (string->symbol (format "~a/~a?" var-str tag-str))
               ;; accessors: var-name/tag-field for each field
               (map (lambda (f)
                      (string->symbol
                        (format "~a/~a-~a" var-str tag-str (symbol->string f))))
                    field-syms)))]))

  ;; --- defvariant macro ---
  ;;
  ;; (defvariant name (tag1 field ...) (tag2 field ...) ...)
  ;;
  ;; Two-phase expansion:
  ;; 1. At compile time: register type info in *ct-variant-registry* for match-variant
  ;; 2. At runtime: define records, predicates, accessors, and register in *variant-registry*

  (define-syntax defvariant
    (lambda (stx)
      (syntax-case stx ()
        [(_ name case ...)
         (identifier? #'name)
         (let* ([var-name (syntax->datum #'name)]
                [var-str (symbol->string var-name)]
                [cases (map (lambda (c) (parse-variant-case var-name c))
                            (syntax->list #'(case ...)))]
                ;; Generate names
                [any-pred (string->symbol (format "~a?" var-str))]
                [variants-list (string->symbol (format "~a/variants" var-str))]
                ;; Build compile-time registry entry:
                ;; Each case: (tag-sym field-count pred-name acc-names...)
                [ct-entry (map (lambda (c)
                                 (cons (car c)              ; tag
                                   (cons (length (cadr c))  ; field-count
                                     (cons (cadddr c)       ; pred-name
                                       (car (cddddr c)))))) ; acc-names
                               cases)])

           ;; Register at compile time for match-variant
           (hashtable-set! *ct-variant-registry* var-name ct-entry)

           (with-syntax
             ([any-pred-id (datum->syntax #'name any-pred)]
              [variants-id (datum->syntax #'name variants-list)]
              [name-sym (datum->syntax #'name `',var-name)]
              [(tag-sym ...) (datum->syntax #'name
                               (map car cases))]
              ;; Generate record definitions for each case using the helper macro
              [(record-def ...)
               (map (lambda (c)
                      (let ([fields (cadr c)]
                            [ctor (caddr c)]
                            [accs (car (cddddr c))])
                        (with-syntax ([ctor-id (datum->syntax #'name ctor)]
                                      [pred-id (datum->syntax #'name (cadddr c))]
                                      ;; Build ((field acc) ...) pairs
                                      [(field-acc ...)
                                       (map (lambda (f a)
                                              (datum->syntax #'name (list f a)))
                                            fields accs)])
                          #'(%define-variant-case ctor-id pred-id (field-acc ...)))))
                    cases)]
              ;; Generate constructor aliases: (define ctor-name make-ctor-name)
              [(ctor-alias ...)
               (map (lambda (c)
                      (let ([ctor (caddr c)])
                        (with-syntax ([ctor-id (datum->syntax #'name ctor)]
                                      [make-ctor-id (datum->syntax #'name
                                                      (string->symbol
                                                        (format "make-~a" ctor)))])
                          #'(define ctor-id make-ctor-id))))
                    cases)]
              ;; Predicate names for the any-pred check
              [(pred-name ...) (map (lambda (c) (datum->syntax #'name (cadddr c)))
                                    cases)]
              ;; Runtime registry entry: holds actual procedures
              [registry-expr
               (datum->syntax #'name
                 `(list
                    ,@(map (lambda (c)
                             `(list ',(car c)
                                    ,(length (cadr c))
                                    ,(cadddr c)           ; pred proc
                                    ,@(car (cddddr c))))  ; acc procs
                           cases)))])
             #'(begin
                 record-def ...
                 ctor-alias ...
                 (define (any-pred-id x)
                   (or (pred-name x) ...))
                 (define variants-id '(tag-sym ...))
                 (hashtable-set! *variant-registry* name-sym registry-expr))))])))

  ;; --- match-variant macro ---
  ;;
  ;; (match-variant type-name expr clause ...)
  ;;
  ;; Where clause is: [(tag var ...) body ...]
  ;;                  [_ body ...]       ; explicit wildcard, suppresses check
  ;;                  [else body ...]    ; explicit else, suppresses check
  ;;
  ;; At expand time: checks that all variants are covered (unless _ or else present)
  ;; using the compile-time registry.

  (define-syntax match-variant
    (lambda (stx)
      ;; Helper: extract tag names from clauses
      (define (clause-tags clauses)
        (let loop ([cls clauses] [tags '()] [has-wild? #f])
          (if (null? cls)
            (cons (reverse tags) has-wild?)
            (let* ([clause (car cls)]
                   [pat (car (syntax->list clause))]
                   [pat-d (syntax->datum pat)])
              (cond
                [(eq? pat-d '_) (loop (cdr cls) tags #t)]
                [(eq? pat-d 'else) (loop (cdr cls) tags #t)]
                [(and (pair? pat-d) (symbol? (car pat-d)))
                 (loop (cdr cls) (cons (car pat-d) tags) has-wild?)]
                [else (loop (cdr cls) tags has-wild?)])))))

      ;; Helper: compile a single clause to match code
      ;; type-info is from compile-time registry: ((tag field-count pred-name acc-name ...) ...)
      (define (compile-clause tmp-stx clause type-info fail-stx)
        (let* ([parts (syntax->list clause)]
               [pat (car parts)]
               [pat-d (syntax->datum pat)]
               [body-stx (cdr parts)])
          (cond
            ;; Wildcard _
            [(eq? pat-d '_)
             #`(begin #,@body-stx)]
            ;; else clause
            [(eq? pat-d 'else)
             #`(begin #,@body-stx)]
            ;; Variant case: (tag var ...)
            [(pair? pat-d)
             (let* ([pat-list (syntax->list pat)]
                    [tag-stx (car pat-list)]
                    [tag-sym (syntax->datum tag-stx)]
                    [entry (assq tag-sym type-info)])
               (if (not entry)
                 (syntax-violation 'match-variant
                   (format "unknown variant tag: ~a" tag-sym) pat)
                 (let* ([pred-name (caddr entry)]
                        [acc-names (cdddr entry)]
                        [var-stxs (cdr pat-list)]
                        [n-vars (length var-stxs)]
                        [n-accs (length acc-names)])
                   (unless (= n-vars n-accs)
                     (syntax-violation 'match-variant
                       (format "wrong number of bindings for ~a: expected ~a, got ~a"
                               tag-sym n-accs n-vars)
                       clause))
                   (with-syntax ([pred-id (datum->syntax tag-stx pred-name)]
                                 [(acc-id ...) (datum->syntax tag-stx acc-names)]
                                 [(var-id ...) var-stxs]
                                 [tmp tmp-stx]
                                 [fail fail-stx]
                                 [(body-expr ...) body-stx])
                     #'(if (pred-id tmp)
                         (let ([var-id (acc-id tmp)] ...)
                           body-expr ...)
                         fail)))))]
            [else
             (syntax-violation 'match-variant
               "invalid match clause" clause)])))

      ;; Compile all clauses into nested if
      (define (compile-clauses tmp-stx clauses type-info)
        (if (null? clauses)
          #`(error 'match-variant "no matching clause" #,tmp-stx)
          (let ([clause (car clauses)]
                [rest (cdr clauses)])
            (compile-clause tmp-stx clause type-info
              (compile-clauses tmp-stx rest type-info)))))

      (syntax-case stx ()
        [(_ type-name expr clause ...)
         (identifier? #'type-name)
         (let* ([type-sym (syntax->datum #'type-name)]
                ;; Use compile-time registry
                [type-info (hashtable-ref *ct-variant-registry* type-sym #f)])
           ;; Check if type is registered
           (unless type-info
             (syntax-violation 'match-variant
               (format "unknown variant type: ~a (hint: defvariant must appear before match-variant in the same compilation unit)" type-sym)
               #'type-name))

           ;; Check exhaustiveness
           (let* ([clauses (syntax->list #'(clause ...))]
                  [result (clause-tags clauses)]
                  [covered-tags (car result)]
                  [has-wildcard? (cdr result)]
                  [all-tags (map car type-info)]
                  [missing (filter (lambda (t) (not (memq t covered-tags))) all-tags)])
             ;; Only error if no wildcard and there are missing tags
             (when (and (not has-wildcard?) (not (null? missing)))
               (syntax-violation 'match-variant
                 (format "unhandled variant(s): ~a" missing)
                 stx))

             ;; Generate match code
             (let ([tmp (car (generate-temporaries '(val)))])
               (with-syntax ([tmp-id tmp]
                             [match-body (compile-clauses tmp clauses type-info)])
                 #'(let ([tmp-id expr])
                     match-body)))))])))

  ) ;; end library
