#!chezscheme
;;; (std typed advanced) — Advanced type system features
;;;
;;; Step 14: Occurrence typing — type narrowing in branches
;;; Step 15: Row polymorphism — structural subtyping for records
;;; Step 16: Refinement types — types with predicates
;;; Step 17: Type-directed compilation — emit specialized ops from types
;;;
;;; API:
;;;   ;; Step 14: Occurrence typing
;;;   (cond/t ([test body ...] ...) — narrowing cond
;;;   (if/t test then else)         — narrowing if
;;;   (when/t test body ...)        — narrowing when
;;;
;;;   ;; Step 15: Row polymorphism
;;;   (defrow Name (field : Type) ...)   — define a row type
;;;   (row-check obj (field : Type) ...) — check fields exist and have types
;;;   (Row field: Type ...)              — row type specifier
;;;
;;;   ;; Step 16: Refinement types
;;;   (Refine Type pred)             — type + predicate specifier
;;;   (refine-check val type pred)   — runtime refinement check
;;;
;;;   ;; Step 17: Type-directed compilation
;;;   (define/tc (name [arg : type] ...) : ret-type body ...)
;;;     — like define/t but emits specialized ops based on known types

(library (std typed advanced)
  (export
    ;; Step 14: Occurrence typing
    cond/t
    if/t
    when/t
    unless/t

    ;; Step 15: Row polymorphism
    defrow
    row?
    row-check
    row-type?

    ;; Step 16: Refinement types
    make-refinement-type
    refinement-type?
    refinement-type-base
    refinement-type-pred
    check-refinement!
    assert-refined

    ;; Step 17: Type-directed compilation
    define/tc
    lambda/tc

    ;; Type specs
    Union
    Intersection)

  (import (chezscheme) (std typed))

  ;; ========== Step 14: Occurrence Typing ==========
  ;;
  ;; After (string? x) in a test, x is narrowed to String in the branch.
  ;; We implement this via macro expansion that annotates the branch body.
  ;;
  ;; Supported predicate → type narrowings:
  ;;   string?   → string     fixnum?   → fixnum     flonum? → flonum
  ;;   pair?     → pair       list?     → list        null?   → null
  ;;   vector?   → vector     symbol?   → symbol      char?   → char
  ;;   boolean?  → boolean    number?   → number      procedure? → procedure

  (meta define *predicate->type*
    '((string?    . string)
      (fixnum?    . fixnum)
      (flonum?    . flonum)
      (number?    . number)
      (integer?   . integer)
      (real?      . real)
      (pair?      . pair)
      (list?      . list)
      (null?      . null)
      (vector?    . vector)
      (symbol?    . symbol)
      (char?      . char)
      (boolean?   . boolean)
      (procedure? . procedure)
      (bytevector? . bytevector)
      (hashtable? . hashtable)))

  ;; Extract narrowed type from a predicate applied to a variable.
  ;; Returns (var-sym . type-sym) or #f.
  (meta define (extract-narrowing test-datum)
    (and (pair? test-datum)
         (= (length test-datum) 2)
         (let ([pred (car test-datum)]
               [arg  (cadr test-datum)])
           (and (symbol? arg)
                (assq pred *predicate->type*)
                (cons arg (cdr (assq pred *predicate->type*)))))))

  ;; (if/t test then else)
  ;; Emits type assertions in the branches based on the test predicate.
  (define-syntax if/t
    (lambda (stx)
      (syntax-case stx ()
        [(k test then else)
         (let ([narrowing (extract-narrowing (syntax->datum #'test))])
           (if narrowing
             (let ([var-sym (car narrowing)]
                   [type-sym (cdr narrowing)])
               (with-syntax ([var (datum->syntax #'k var-sym)]
                             [type (datum->syntax #'k type-sym)])
                 #'(if test
                     (let ([var (begin (assert-type var type) var)])
                       then)
                     else)))
             #'(if test then else)))])))

  ;; (when/t test body ...)
  (define-syntax when/t
    (lambda (stx)
      (syntax-case stx ()
        [(k test body ...)
         (let ([narrowing (extract-narrowing (syntax->datum #'test))])
           (if narrowing
             (let ([var-sym (car narrowing)]
                   [type-sym (cdr narrowing)])
               (with-syntax ([var (datum->syntax #'k var-sym)]
                             [type (datum->syntax #'k type-sym)])
                 #'(when test
                     (let ([var (begin (assert-type var type) var)])
                       body ...))))
             #'(when test body ...)))])))

  ;; (unless/t test body ...)
  (define-syntax unless/t
    (lambda (stx)
      (syntax-case stx ()
        [(k test body ...)
         #'(when/t (not test) body ...)])))

  ;; (cond/t ([test body ...] ...) [else body ...])
  ;; Narrows in each branch based on the test predicate.
  ;; Uses pattern-variable decomposition to preserve use-site lexical scope.
  (define-syntax cond/t
    (lambda (stx)
      (syntax-case stx (else)
        [(k [else body ...])
         #'(begin body ...)]
        ;; Test is a 2-element predicate application (pred var-ref)
        [(k [(pred var-ref) body ...] rest ...)
         (let* ([pred-sym (syntax->datum #'pred)]
                [type-entry (assq pred-sym *predicate->type*)])
           (if (and type-entry (identifier? #'var-ref))
             (with-syntax ([type (datum->syntax #'k (cdr type-entry))])
               ;; var-ref is the actual use-site syntax object for the variable
               ;; Using it as both the let binding name and in body preserves scope
               #'(if (pred var-ref)
                   (let ([var-ref (begin (assert-type var-ref type) var-ref)])
                     body ...)
                   (cond/t rest ...)))
             #'(if (pred var-ref) (begin body ...) (cond/t rest ...))))]
        ;; Fallback: test is not a simple predicate application
        [(k [test body ...] rest ...)
         #'(if test (begin body ...) (cond/t rest ...))]
        [(k) #'(void)])))

  ;; ========== Step 15: Row Polymorphism ==========
  ;;
  ;; A row type matches "any object with at least these fields".
  ;; At runtime: checks that the object has the required accessors.
  ;;
  ;; (defrow Printable
  ;;   (to-string : procedure))
  ;;
  ;; (row-check obj Printable)  -- verifies obj satisfies Printable row

  ;; Row type descriptor
  (define-record-type row-type
    (fields
      (immutable name)
      (immutable fields))   ;; list of (field-name . type-spec)
    (sealed #t))

  ;; Registry of defined row types
  (define *row-types* (make-eq-hashtable))

  (define (row? name)
    (hashtable-ref *row-types* name #f))

  ;; (defrow Name (field : Type) ...)
  ;; Defines a row type and a checker predicate.
  (define-syntax defrow
    (lambda (stx)
      (syntax-case stx ()
        [(_ name (field-name colon field-type) ...)
         (and (identifier? #'name)
              (for-all (lambda (c) (eq? (syntax->datum c) ':))
                       (syntax->list #'(colon ...))))
         (with-syntax ([checker-name
                        (datum->syntax #'name
                          (string->symbol
                            (string-append
                              (symbol->string (syntax->datum #'name))
                              "?")))]
                       [check-name
                        (datum->syntax #'name
                          (string->symbol
                            (string-append
                              "check-"
                              (symbol->string (syntax->datum #'name))
                              "!")))])
           #'(begin
               ;; Register row type
               (define %row-type%
                 (make-row-type 'name
                   '((field-name . field-type) ...)))
               (hashtable-set! *row-types* 'name %row-type%)
               ;; Predicate: checks field existence via accessor naming
               (define (checker-name obj)
                 (row-satisfies? obj '((field-name . field-type) ...)))
               ;; Check function: raises on failure
               (define (check-name obj)
                 (unless (checker-name obj)
                   (error 'check-name
                     (format "object does not satisfy row ~a" 'name)
                     obj)))))])))

  ;; Check if obj satisfies a row spec (field-name . type-spec) ...
  ;; Uses Jerboa's struct-field-ref to check field accessibility.
  (define (row-satisfies? obj fields)
    (for-all
      (lambda (field-spec)
        (let* ([fname (symbol->string (car field-spec))]
               [accessor-sym (string->symbol fname)])
          ;; Try to access the field; if it works, the row is satisfied
          (guard (exn [#t #f])
            (let ([accessor (eval accessor-sym (interaction-environment))])
              (if (procedure? accessor)
                (begin (accessor obj) #t)
                #f)))))
      fields))

  ;; (row-check obj (field : Type) ...)
  ;; Runtime check that obj satisfies a row type.
  (define-syntax row-check
    (lambda (stx)
      (syntax-case stx ()
        [(_ obj-expr row-name)
         #'(let ([obj obj-expr])
             (let ([row (hashtable-ref *row-types* 'row-name #f)])
               (if row
                 (row-satisfies? obj (row-type-fields row))
                 (error 'row-check "unknown row type" 'row-name))))]
        [(_ obj-expr (field-name colon field-type) ...)
         (for-all (lambda (c) (eq? (syntax->datum c) ':))
                  (syntax->list #'(colon ...)))
         #'(row-satisfies? obj-expr '((field-name . field-type) ...))])))

  ;; ========== Step 16: Refinement Types ==========
  ;;
  ;; (Refine Type pred) — type + predicate
  ;; (assert-refined val type pred) — check base type then predicate

  (define-record-type refinement-type
    (fields
      (immutable base)    ;; base type name (symbol)
      (immutable pred))   ;; predicate (procedure or symbol)
    (sealed #t))

  (define (check-refinement! who name val base pred-spec)
    (when (eq? (*typed-mode*) 'debug)
      ;; Check base type
      (let ([base-pred (type-predicate base)])
        (when (and base-pred (not (eq? base 'any)))
          (unless (base-pred val)
            (error who
              (format "~a: expected ~a, got ~a" name base val)
              val))))
      ;; Check refinement predicate
      (let ([pred (if (procedure? pred-spec)
                    pred-spec
                    (eval pred-spec (interaction-environment)))])
        (unless (pred val)
          (error who
            (format "~a: refinement predicate failed for ~a" name val)
            val)))))

  ;; (assert-refined expr base pred)
  (define-syntax assert-refined
    (lambda (stx)
      (syntax-case stx ()
        [(_ expr base-type pred-expr)
         #'(let ([v expr])
             (check-refinement! 'assert-refined 'expr v 'base-type pred-expr)
             v)])))

  ;; Extend type-predicate to handle Refine types.
  ;; (Refine base pred) — both checked at runtime
  ;; We handle this in define/tc below by recognizing the Refine form.

  ;; ========== Step 17: Type-Directed Compilation ==========
  ;;
  ;; (define/tc (name [arg : type] ...) : ret-type body ...)
  ;;
  ;; Like define/t but additionally:
  ;; - If arg type is fixnum/flonum, wraps body in with-fixnum-ops/with-flonum-ops
  ;; - If a type is (Refine base pred), checks the refinement in debug mode
  ;; - If return type is fixnum/flonum, the body is wrapped accordingly
  ;;
  ;; Type-directed specialization rules:
  ;;   all-fixnum args + fixnum return → wrap body in (with-fixnum-ops ...)
  ;;   all-flonum  args + flonum  return → wrap body in (with-flonum-ops ...)
  ;;   mixed → no specialization (generic ops)

  (define-syntax define/tc
    (lambda (stx)
      (define (parse-typed-args args)
        (let loop ([rest (syntax->list args)] [result '()])
          (if (null? rest)
            (reverse result)
            (let ([item (car rest)])
              (syntax-case item ()
                [(arg-name sep type-name)
                 (eq? (syntax->datum #'sep) ':)
                 (loop (cdr rest)
                       (cons (list #'arg-name #'type-name) result))]
                [arg-name
                 (identifier? #'arg-name)
                 (loop (cdr rest)
                       (cons (list #'arg-name (datum->syntax #'arg-name 'any)) result))])))))

      (define (all-type? parsed type-sym)
        (for-all (lambda (p)
                   (eq? (syntax->datum (cadr p)) type-sym))
                 parsed))

      (define (is-refine? type-stx)
        (let ([d (syntax->datum type-stx)])
          (and (pair? d) (eq? (car d) 'Refine))))

      (define (emit-arg-checks who-stx parsed)
        ;; For each arg, emit a check (handling Refine specially).
        ;; who-stx must be a syntax object (e.g. #'name) to avoid raw-symbol errors.
        (map (lambda (p)
               (let ([arg (car p)]
                     [type (cadr p)])
                 (let ([td (syntax->datum type)])
                   (cond
                     [(and (pair? td) (eq? (car td) 'Refine))
                      ;; (Refine base pred) — use who-stx (an identifier) as datum->syntax ctx
                      (let ([base (datum->syntax who-stx (cadr td))]
                            [pred (datum->syntax who-stx (caddr td))])
                        #`(check-refinement! '#,who-stx '#,arg #,arg '#,base #,pred))]
                     [else
                      #`(check-type! '#,who-stx '#,arg #,arg '#,type)]))))
             parsed))

      (syntax-case stx ()
        ;; With return type
        [(k (name typed-arg ...) colon ret-type body ...)
         (eq? (syntax->datum #'colon) ':)
         (let* ([parsed (parse-typed-args #'(typed-arg ...))]
                [args (map car parsed)]
                [all-fix? (and (all-type? parsed 'fixnum)
                               (eq? (syntax->datum #'ret-type) 'fixnum))]
                [all-flo? (and (all-type? parsed 'flonum)
                               (eq? (syntax->datum #'ret-type) 'flonum))]
                [arg-checks (emit-arg-checks #'name parsed)])
           (with-syntax ([(arg ...) args]
                         [(check ...) arg-checks])
             (cond
               [all-fix?
                #'(define (name arg ...)
                    (when (eq? (*typed-mode*) 'debug) check ...)
                    (with-fixnum-ops body ...))]
               [all-flo?
                #'(define (name arg ...)
                    (when (eq? (*typed-mode*) 'debug) check ...)
                    (with-flonum-ops body ...))]
               [else
                #'(define (name arg ...)
                    (when (eq? (*typed-mode*) 'debug) check ...)
                    (let ([result (begin body ...)])
                      (check-return-type! 'name result 'ret-type)
                      result))])))]
        ;; Without return type
        [(k (name typed-arg ...) body ...)
         (let* ([parsed (parse-typed-args #'(typed-arg ...))]
                [args (map car parsed)]
                [arg-checks (emit-arg-checks #'name parsed)])
           (with-syntax ([(arg ...) args]
                         [(check ...) arg-checks])
             #'(define (name arg ...)
                 (when (eq? (*typed-mode*) 'debug) check ...)
                 body ...)))])))

  ;; lambda/tc: like define/tc but for lambdas
  (define-syntax lambda/tc
    (lambda (stx)
      (define (parse-typed-args args)
        (let loop ([rest (syntax->list args)] [result '()])
          (if (null? rest)
            (reverse result)
            (let ([item (car rest)])
              (syntax-case item ()
                [(arg-name sep type-name)
                 (eq? (syntax->datum #'sep) ':)
                 (loop (cdr rest)
                       (cons (list #'arg-name #'type-name) result))]
                [arg-name
                 (identifier? #'arg-name)
                 (loop (cdr rest)
                       (cons (list #'arg-name (datum->syntax #'arg-name 'any)) result))])))))

      (define (all-type? parsed type-sym)
        (for-all (lambda (p) (eq? (syntax->datum (cadr p)) type-sym)) parsed))

      (syntax-case stx ()
        [(k (typed-arg ...) colon ret-type body ...)
         (eq? (syntax->datum #'colon) ':)
         (let* ([parsed (parse-typed-args #'(typed-arg ...))]
                [args (map car parsed)]
                [all-fix? (and (all-type? parsed 'fixnum)
                               (eq? (syntax->datum #'ret-type) 'fixnum))]
                [all-flo? (and (all-type? parsed 'flonum)
                               (eq? (syntax->datum #'ret-type) 'flonum))])
           (with-syntax ([(arg ...) args]
                         [((aname atype) ...) parsed])
             (cond
               [all-fix?
                #'(lambda (arg ...)
                    (when (eq? (*typed-mode*) 'debug)
                      (check-type! 'lambda 'aname arg 'atype) ...)
                    (with-fixnum-ops body ...))]
               [all-flo?
                #'(lambda (arg ...)
                    (when (eq? (*typed-mode*) 'debug)
                      (check-type! 'lambda 'aname arg 'atype) ...)
                    (with-flonum-ops body ...))]
               [else
                #'(lambda/t (typed-arg ...) : ret-type body ...)])))]
        [(k (typed-arg ...) body ...)
         #'(lambda/t (typed-arg ...) body ...)])))

  ;; ========== Union / Intersection type specs ==========
  ;; These are type spec constructors for use in type annotations.
  ;; Runtime checking: Union checks any, Intersection checks all.

  ;; (Union T1 T2 ...) — value satisfies at least one type
  ;; Used in type-predicate lookup via register-type-predicate!
  (define-syntax Union
    (lambda (stx)
      (syntax-case stx ()
        [(_ type ...)
         #'(let ([preds (filter values (map type-predicate '(type ...)))])
             (lambda (x)
               (any (lambda (p) (p x)) preds)))])))

  ;; (Intersection T1 T2 ...) — value satisfies all types
  (define-syntax Intersection
    (lambda (stx)
      (syntax-case stx ()
        [(_ type ...)
         #'(let ([preds (filter values (map type-predicate '(type ...)))])
             (lambda (x)
               (for-all (lambda (p) (p x)) preds)))])))

  ;; Helper: any (like SRFI-1 any)
  (define (any pred lst)
    (and (not (null? lst))
         (or (pred (car lst))
             (any pred (cdr lst)))))

  ) ;; end library
