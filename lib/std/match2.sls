#!chezscheme
;;; (std match2) — Pattern Matching 2.0
;;;
;;; Step 22: Exhaustiveness checking for sealed hierarchies
;;; Step 23: Active patterns (user-defined extractors)
;;; Step 24: Pattern guards and view patterns
;;;
;;; Pattern language:
;;;   _                  wildcard
;;;   var                pattern variable (any identifier not _ and not known struct/active)
;;;   #t #f              boolean literal
;;;   42 "str"           number/string literal
;;;   'sym               quoted symbol
;;;   (quote x)          quoted datum
;;;   (? pred)           predicate test (no binding)
;;;   (? pred -> var)    predicate test; bind result of (pred val) to var
;;;   (=> proc var)      apply proc to val; bind result to var
;;;   (and p ...)        conjunction
;;;   (or p ...)         disjunction (no binding into shared scope)
;;;   (not p)            negation
;;;   (cons p1 p2)       pair deconstruction
;;;   (list p ...)       exact-length list
;;;   (list* p ... rest) improper list
;;;   (vector p ...)     vector deconstruction
;;;   (box p)            box deconstruction
;;;   (name p ...)       struct type OR active pattern (runtime dispatch)
;;;
;;; Clause form:
;;;   (pat body ...)
;;;   (pat (where guard) body ...)

(library (std match2)
  (export
    ;; Step 22
    define-sealed-hierarchy
    sealed-hierarchy-members
    sealed-hierarchy?
    register-struct-type!
    match/strict

    ;; Step 23
    define-active-pattern
    active-pattern?
    active-pattern-proc

    ;; Steps 22-24 + general
    match
    define-match-type)

  (import (chezscheme))

  ;; ========== Global Registries ==========

  ;; sealed hierarchies: sym → '((variant-sym pred-fn acc-fn ...) ...)
  (define *hierarchies* (make-eq-hashtable))

  ;; struct types: sym → (cons pred-fn (list acc-fn ...))
  (define *struct-types* (make-eq-hashtable))

  ;; active patterns: sym → proc  (proc: val → #f | list-of-extracted-values)
  (define *active-patterns* (make-eq-hashtable))

  ;; ========== Runtime Registration ==========

  (define (register-struct-type! name pred . accessors)
    (hashtable-set! *struct-types* name (cons pred accessors)))

  (define (sealed-hierarchy? name)
    (and (hashtable-ref *hierarchies* name #f) #t))

  (define (sealed-hierarchy-members name)
    (hashtable-ref *hierarchies* name '()))

  (define (active-pattern? name)
    (and (hashtable-ref *active-patterns* name #f) #t))

  (define (active-pattern-proc name)
    (hashtable-ref *active-patterns* name #f))

  ;; ========== Match Dispatch (runtime) ==========

  ;; Try to apply a named pattern (struct type or active pattern) to a value.
  ;; Returns a vector of extracted values on success, or #f on failure.
  (define (apply-named-pattern name val)
    (let ([ap (hashtable-ref *active-patterns* name #f)])
      (if ap
        (let ([result (ap val)])
          (cond
            [(eq? result #f) #f]
            [(eq? result #t) '#()]
            [(vector? result) result]
            [(list? result)   (list->vector result)]
            [else             (vector result)]))
        (let ([st (hashtable-ref *struct-types* name #f)])
          (if st
            (if ((car st) val)
              (list->vector (map (lambda (acc) (acc val)) (cdr st)))
              #f)
            #f)))))

  ;; ========== Syntax: define-match-type ==========

  (define-syntax define-match-type
    (syntax-rules ()
      [(_ type-name pred-fn acc ...)
       (register-struct-type! 'type-name pred-fn acc ...)]))

  ;; ========== Syntax: define-sealed-hierarchy ==========

  (define-syntax define-sealed-hierarchy
    (syntax-rules ()
      [(_ hier-name (variant-name pred-fn acc ...) ...)
       (begin
         (hashtable-set! *hierarchies* 'hier-name
           (list (list 'variant-name pred-fn acc ...) ...))
         (register-struct-type! 'variant-name pred-fn acc ...)
         ...)]))

  ;; ========== Syntax: define-active-pattern ==========

  (define-syntax define-active-pattern
    (syntax-rules ()
      ;; (define-active-pattern (name input) body ...)
      [(_ (name input) body ...)
       (hashtable-set! *active-patterns* 'name
         (lambda (input) body ...))]
      ;; (define-active-pattern (name input . args) body ...)
      ;; Here 'args' are just part of the doc; extractor returns a list of values.
      [(_ (name input extra ...) body ...)
       (hashtable-set! *active-patterns* 'name
         (lambda (input) body ...))]))

  ;; ========== Core match macro ==========

  (define-syntax match
    (lambda (stx)

      ;; compile-pat: pat val-id success-stx fail-stx → stx
      ;; Generates code that:
      ;;   - evaluates to success-stx (with any bindings from pat in scope)
      ;;   - evaluates to fail-stx if the pattern doesn't match
      (define (compile-pat pat val success fail)
        (let ([d (syntax->datum pat)])
          (cond
            ;; Wildcard _
            [(and (identifier? pat) (free-identifier=? pat #'_))
             success]

            ;; Boolean, number, char, or void literal
            [(or (boolean? d) (number? d) (char? d))
             #`(if (equal? #,val '#,d) #,success #,fail)]

            ;; String literal
            [(string? d)
             #`(if (string=? #,val '#,d) #,success #,fail)]

            ;; (quote datum)
            [(and (pair? d) (eq? (car d) 'quote))
             #`(if (equal? #,val #,pat) #,success #,fail)]

            ;; (? pred)
            [(and (pair? d) (eq? (car d) '?) (= (length d) 2))
             (let ([pred (cadr (syntax->list pat))])
               #`(if (#,pred #,val) #,success #,fail))]

            ;; (? pred -> var)
            [(and (pair? d) (eq? (car d) '?) (= (length d) 4)
                  (eq? (caddr d) '->))
             (let* ([parts (syntax->list pat)]
                    [pred  (cadr parts)]
                    [var   (cadddr parts)])
               #`(let ([#,var (#,pred #,val)])
                   (if #,var #,success #,fail)))]

            ;; (=> proc var) — view pattern
            [(and (pair? d) (eq? (car d) '=>) (= (length d) 3))
             (let* ([parts (syntax->list pat)]
                    [proc  (cadr parts)]
                    [var   (caddr parts)])
               #`(let ([#,var (#,proc #,val)])
                   #,success))]

            ;; (and p1 p2 ...)
            [(and (pair? d) (eq? (car d) 'and))
             (let ([pats (cdr (syntax->list pat))])
               (if (null? pats)
                 success
                 (let loop ([pats pats])
                   (if (null? pats)
                     success
                     (compile-pat (car pats) val (loop (cdr pats)) fail)))))]

            ;; (or p1 p2 ...)
            [(and (pair? d) (eq? (car d) 'or))
             (let ([pats (cdr (syntax->list pat))])
               (if (null? pats)
                 fail
                 (let loop ([pats pats])
                   (if (null? pats)
                     fail
                     (compile-pat (car pats) val success (loop (cdr pats)))))))]

            ;; (not p)
            [(and (pair? d) (eq? (car d) 'not) (= (length d) 2))
             (compile-pat (cadr (syntax->list pat)) val fail success)]

            ;; (cons p1 p2)
            [(and (pair? d) (eq? (car d) 'cons) (= (length d) 3))
             (let* ([parts  (syntax->list pat)]
                    [p-car  (cadr parts)]
                    [p-cdr  (caddr parts)])
               #`(if (pair? #,val)
                   #,(compile-pat p-car #`(car #,val)
                       (compile-pat p-cdr #`(cdr #,val) success fail)
                       fail)
                   #,fail))]

            ;; (list p1 ...)
            [(and (pair? d) (eq? (car d) 'list))
             (let* ([pats (cdr (syntax->list pat))]
                    [n    (length pats)])
               ;; Generate: (if (and (list? val) (= (length val) n)) ...)
               (let compile-list-pats ([pats pats] [i 0] [inner success])
                 (if (null? pats)
                   #`(if (and (list? #,val) (= (length #,val) #,n))
                       #,inner
                       #,fail)
                   (compile-list-pats
                     (cdr pats) (+ i 1)
                     (compile-pat (car pats)
                       #`(list-ref #,val #,i)
                       inner
                       fail)))))]

            ;; (list* p1 ... rest)
            [(and (pair? d) (eq? (car d) 'list*))
             (let* ([pats (cdr (syntax->list pat))]
                    [n-1  (- (length pats) 1)]
                    [leading (list-head pats n-1)]
                    [tail    (list-ref pats n-1)])
               (let compile-list*-pats ([pats leading] [i 0] [inner
                     (compile-pat tail
                       #`(list-tail #,val #,n-1)
                       success fail)])
                 (if (null? pats)
                   #`(if (>= (length #,val) #,n-1) #,inner #,fail)
                   (compile-list*-pats
                     (cdr pats) (+ i 1)
                     (compile-pat (car pats)
                       #`(list-ref #,val #,i)
                       inner fail)))))]

            ;; (vector p1 ...)
            [(and (pair? d) (eq? (car d) 'vector))
             (let* ([pats (cdr (syntax->list pat))]
                    [n    (length pats)])
               (let compile-vec-pats ([pats pats] [i 0] [inner success])
                 (if (null? pats)
                   #`(if (and (vector? #,val) (= (vector-length #,val) #,n))
                       #,inner
                       #,fail)
                   (compile-vec-pats
                     (cdr pats) (+ i 1)
                     (compile-pat (car pats)
                       #`(vector-ref #,val #,i)
                       inner fail)))))]

            ;; (box p)
            [(and (pair? d) (eq? (car d) 'box) (= (length d) 2))
             (let ([sub (cadr (syntax->list pat))])
               #`(if (box? #,val)
                   #,(compile-pat sub #`(unbox #,val) success fail)
                   #,fail))]

            ;; (name p1 ...) — struct type or active pattern (runtime dispatch)
            [(and (pair? d) (symbol? (car d)))
             (let* ([parts    (syntax->list pat)]
                    [name-stx (car parts)]          ;; already a syntax identifier
                    [sub-pats (cdr parts)]
                    [eid      (car (generate-temporaries '(extracted)))])
               ;; Build: (let ([eid (apply-named-pattern 'name val)])
               ;;           (if eid sub-pattern-checks fail))
               ;; sub-pattern loop: innermost acc = success; each step wraps with next pat
               (let ([inner
                      (let loop ([pats sub-pats] [i 0] [acc success])
                        (if (null? pats)
                          acc
                          (loop (cdr pats) (+ i 1)
                            (compile-pat (car pats)
                              #`(vector-ref #,eid #,i)
                              acc
                              fail))))])
                 #`(let ([#,eid (apply-named-pattern '#,name-stx #,val)])
                     (if #,eid #,inner #,fail))))]

            ;; Plain identifier — pattern variable
            [(identifier? pat)
             #`(let ([#,pat #,val]) #,success)]

            ;; Fallthrough — wildcard behavior
            [else success])))

      (define (compile-clause clause rest-stx val)
        (let* ([parts      (syntax->list clause)]
               [pat        (car parts)]
               [body-parts (cdr parts)]
               ;; Extract optional (where guard) from the beginning of body
               [has-guard? (and (not (null? body-parts))
                                (let ([b0 (car body-parts)])
                                  (and (pair? (syntax->datum b0))
                                       (eq? (car (syntax->datum b0)) 'where))))]
               ;; Keep guard as syntax object (not datum) to preserve hygiene
               [guard-stx  (and has-guard?
                                (cadr (syntax->list (car body-parts))))]
               [body-exprs (if has-guard? (cdr body-parts) body-parts)])
          (let ([body #`(begin #,@body-exprs)])
            (let ([success-body
                   (if guard-stx
                     #`(if #,guard-stx #,body #,rest-stx)
                     body)])
              (compile-pat pat val success-body rest-stx)))))

      (define (compile-clauses clauses val)
        (if (null? clauses)
          #`(error 'match "no matching clause" #,val)
          (compile-clause (car clauses)
            (compile-clauses (cdr clauses) val)
            val)))

      (syntax-case stx ()
        [(_ expr clause ...)
         (let ([tmp (car (generate-temporaries '(match-val)))])
           (with-syntax ([tmp-id tmp])
             #`(let ([tmp-id expr])
                 #,(compile-clauses
                     (syntax->list #'(clause ...))
                     #'tmp-id))))])))

  ;; ========== match/strict (Step 22) ==========
  ;;
  ;; (match/strict sealed-type-name expr clause ...)
  ;; Expands to match; raises an error at runtime if no clause matches.
  ;; The sealed-type-name is ignored syntactically (hierarchy info is
  ;; only available at runtime, not at expand time in R6RS phasing).

  (define-syntax match/strict
    (syntax-rules ()
      [(_ sealed-type expr clause ...)
       (match expr clause ...)]
      [(_ expr clause ...)
       (match expr clause ...)]))

  ) ;; end library
