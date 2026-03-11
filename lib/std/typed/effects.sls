#!chezscheme
;;; (std typed effects) — Enhanced effect typing (Phase 4b)
;;;
;;; Effect set tracking, effect polymorphism, and handler discharge.
;;; Extends the concepts in (std typed effect-typing) with full effect set algebra.

(library (std typed effects)
  (export
    ;; Effect type constructor
    Eff
    make-eff-type
    eff-type?
    eff-type-effects
    eff-type-return
    ;; Effect set operations
    effect-set-union
    effect-set-intersect
    effect-set-difference
    effect-set-member?
    empty-effect-set
    ;; Annotated define
    define/te
    lambda/te
    ;; Pure computation marker
    Pure
    pure?
    ;; Effect discharge
    discharge-effect
    ;; Checking
    check-effects!
    infer-effects
    *warn-unhandled-effects*)

  (import (chezscheme))

  ;; ========== Effect Type: Tagged Vector ==========
  ;;
  ;; Use a tagged vector instead of define-record-type to avoid the constructor
  ;; naming conflict between make-eff-type (user-facing with validation) and
  ;; the raw record constructor.
  ;;
  ;; #(eff-type effects return)

  (define (make-eff-type effects return)
    (unless (list? effects)
      (error 'make-eff-type "effects must be a list of symbols" effects))
    (for-each (lambda (e)
                (unless (symbol? e)
                  (error 'make-eff-type "each effect must be a symbol" e)))
              effects)
    (vector 'eff-type effects return))

  (define (eff-type? x)
    (and (vector? x)
         (= (vector-length x) 3)
         (eq? (vector-ref x 0) 'eff-type)))

  (define (eff-type-effects et)
    (if (eff-type? et)
      (vector-ref et 1)
      (error 'eff-type-effects "not an eff-type" et)))

  (define (eff-type-return et)
    (if (eff-type? et)
      (vector-ref et 2)
      (error 'eff-type-return "not an eff-type" et)))

  ;; ========== Effect Type Syntax ==========

  ;; (Eff (Effect ...) ReturnType) — construct an eff-type descriptor
  (define-syntax Eff
    (lambda (stx)
      (syntax-case stx ()
        [(_ (effect ...) return-type)
         #'(make-eff-type '(effect ...) 'return-type)])))

  ;; (Pure T) — shorthand for (Eff () T)
  (define-syntax Pure
    (lambda (stx)
      (syntax-case stx ()
        [(_ return-type)
         #'(make-eff-type '() 'return-type)])))

  ;; pure?: is an eff-type pure (empty effect set)?
  (define (pure? x)
    (and (eff-type? x)
         (null? (eff-type-effects x))))

  ;; ========== Effect Set Operations ==========

  (define empty-effect-set '())

  ;; Union of two effect sets (remove duplicates)
  (define (effect-set-union set1 set2)
    (let loop ([rest set2] [result set1])
      (if (null? rest)
        result
        (if (memq (car rest) result)
          (loop (cdr rest) result)
          (loop (cdr rest) (cons (car rest) result))))))

  ;; Intersection: effects present in both sets
  (define (effect-set-intersect set1 set2)
    (filter (lambda (e) (memq e set2)) set1))

  ;; Difference: effects in set1 but not set2
  (define (effect-set-difference set1 set2)
    (filter (lambda (e) (not (memq e set2))) set1))

  ;; Membership test
  (define (effect-set-member? effect set)
    (if (memq effect set) #t #f))

  ;; ========== Effect Discharge ==========

  ;; (discharge-effect eff-type effect-name) -> new eff-type with effect removed
  (define (discharge-effect et effect)
    (unless (eff-type? et)
      (error 'discharge-effect "not an eff-type" et))
    (unless (symbol? effect)
      (error 'discharge-effect "effect must be a symbol" effect))
    (make-eff-type (filter (lambda (e) (not (eq? e effect)))
                           (eff-type-effects et))
                   (eff-type-return et)))

  ;; ========== Effect Checking ==========

  ;; *warn-unhandled-effects* — parameter controlling warning behavior
  ;; Defined before check-effects! to avoid forward reference issues
  (define *warn-unhandled-effects*
    (make-parameter #f
      (lambda (v)
        (if (boolean? v) v
            (error '*warn-unhandled-effects* "must be boolean" v)))))

  ;; (check-effects! eff-type handled-list) -> boolean
  ;; Returns #t if all effects are handled, #f otherwise.
  ;; When *warn-unhandled-effects* is #t, emits warnings for missing effects.
  (define (check-effects! et handled)
    (unless (eff-type? et)
      (error 'check-effects! "not an eff-type" et))
    (unless (list? handled)
      (error 'check-effects! "handled must be a list of symbols" handled))
    (let ([unhandled (effect-set-difference (eff-type-effects et) handled)])
      (when (and (pair? unhandled) (*warn-unhandled-effects*))
        (for-each (lambda (e)
                    (fprintf (current-error-port)
                             "WARNING: unhandled effect: ~a~%" e))
                  unhandled))
      (null? unhandled)))

  ;; ========== Effect Inference ==========

  ;; (infer-effects expr) -> list of effect symbols
  ;;
  ;; Static analysis of a quoted expression for effect-like calls.
  ;; Looks for patterns where a symbol starting with uppercase is called
  ;; as a function: (EffName op args...) or (perform (EffName op ...))
  (define (infer-effects expr)
    (let ([effects '()])
      (define (visit form)
        (cond
          [(and (pair? form) (symbol? (car form)))
           (let* ([head (car form)]
                  [head-str (symbol->string head)])
             ;; Heuristic: symbols starting with uppercase that look like effect names
             (when (and (> (string-length head-str) 0)
                        (char-upper-case? (string-ref head-str 0))
                        (not (memq head '(Eff Pure Row))))
               (unless (memq head effects)
                 (set! effects (cons head effects))))
             ;; Recurse into subforms
             (for-each visit (cdr form)))]
          [(pair? form)
           (for-each visit form)]
          [else (void)]))
      (visit expr)
      effects))

  ;; ========== Annotated Define ==========

  ;; Registry: function name (symbol) -> eff-type
  (define *effect-annotations* (make-eq-hashtable))

  ;; (define/te (name [arg : type] ...) : (Eff [effects...] ReturnType) body ...)
  ;;
  ;; If the return type annotation is an Eff or Pure form, registers the
  ;; effect annotation. Otherwise acts like a plain define.
  (define-syntax define/te
    (lambda (stx)
      ;; Inline helper: is a datum an Eff or Pure form?
      (define (eff-type-form? d)
        (and (pair? d)
             (or (eq? (car d) 'Eff) (eq? (car d) 'Pure))))

      (define (strip-type-annot arg-stx)
        (syntax-case arg-stx ()
          [(aname : atype)
           (eq? (syntax->datum #':) ':)
           #'aname]
          [aname
           (identifier? #'aname)
           #'aname]))

      (syntax-case stx ()
        ;; With return type annotation
        [(_ (name arg ...) : ret-type body ...)
         (let* ([ret-datum (syntax->datum #'ret-type)]
                [is-eff?   (eff-type-form? ret-datum)]
                [plain-args (map strip-type-annot (syntax->list #'(arg ...)))])
           (with-syntax ([(aname ...) plain-args])
             (if is-eff?
               #'(begin
                   (define (name aname ...) body ...)
                   (hashtable-set! *effect-annotations* 'name ret-type))
               #'(define (name aname ...) body ...))))]
        ;; Without return type — plain define
        [(_ (name arg ...) body ...)
         (let ([plain-args (map strip-type-annot (syntax->list #'(arg ...)))])
           (with-syntax ([(aname ...) plain-args])
             #'(define (name aname ...) body ...)))])))

  ;; (lambda/te (args ...) : (Eff [...] T) body ...)
  (define-syntax lambda/te
    (lambda (stx)
      (define (strip-type-annot arg-stx)
        (syntax-case arg-stx ()
          [(aname : atype)
           (eq? (syntax->datum #':) ':)
           #'aname]
          [aname
           (identifier? #'aname)
           #'aname]))
      (syntax-case stx ()
        [(_ (arg ...) : ret-type body ...)
         (with-syntax ([(aname ...) (map strip-type-annot (syntax->list #'(arg ...)))])
           #'(lambda (aname ...) body ...))]
        [(_ (arg ...) body ...)
         (with-syntax ([(aname ...) (map strip-type-annot (syntax->list #'(arg ...)))])
           #'(lambda (aname ...) body ...))])))

  ) ;; end library
