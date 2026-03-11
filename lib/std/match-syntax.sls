#!chezscheme
;;; (std match-syntax) — Syntax-Level Pattern Matching
;;;
;;; Pattern matching on syntax objects (ASTs) represented as plain Scheme data.
;;; Designed for macro writers who want to analyze and transform code structurally.
;;; Works with plain lists/symbols (code-as-data), not Chez syntax objects.

(library (std match-syntax)
  (export
    ;; Core matching
    match-pattern
    syntax-match
    syntax-match*
    ;; AST predicates
    stx-identifier?
    stx-literal?
    stx-list?
    stx-pair?
    stx-null?
    stx-application?
    stx-lambda?
    stx-if?
    stx-let?
    stx-define?
    stx-begin?
    stx-quote?
    ;; Destructuring
    stx-app-fn
    stx-app-args
    stx-lambda-formals
    stx-lambda-body
    stx-if-test
    stx-if-then
    stx-if-else
    stx-let-bindings
    stx-let-body
    stx-define-name
    stx-define-value
    stx-begin-exprs
    stx-identifier-symbol
    ;; Code walking
    walk-syntax
    fold-syntax
    free-identifiers
    ;; Building syntax
    build-let
    build-lambda
    build-if
    build-begin
    build-app)

  (import (chezscheme))

  ;; ========== AST Predicates ==========
  ;;
  ;; All predicates work on plain Scheme data (lists/symbols/etc.)

  ;; Is this a symbol (identifier)?
  (define (stx-identifier? stx)
    (symbol? stx))

  ;; Is this a literal (number, string, boolean, char)?
  (define (stx-literal? stx)
    (or (number? stx)
        (string? stx)
        (boolean? stx)
        (char? stx)))

  ;; Is this a proper list?
  (define (stx-list? stx)
    (and (list? stx) (not (null? stx))))

  ;; Is this a pair (but may be improper)?
  (define (stx-pair? stx)
    (pair? stx))

  ;; Is this null / empty list?
  (define (stx-null? stx)
    (null? stx))

  ;; Is this an application (non-empty list, not a special form)?
  (define (stx-application? stx)
    (and (pair? stx)
         (not (memq (car stx) '(quote lambda if let let* letrec letrec*
                                define begin and or cond case do
                                syntax-rules define-syntax let-syntax
                                letrec-syntax)))))

  (define (stx-lambda? stx)
    (and (pair? stx) (eq? (car stx) 'lambda)))

  (define (stx-if? stx)
    (and (pair? stx) (eq? (car stx) 'if)
         (>= (length stx) 3)))

  (define (stx-let? stx)
    (and (pair? stx) (eq? (car stx) 'let)
         (pair? (cdr stx))
         ;; named let has symbol after 'let; skip that case for basic stx-let?
         (list? (cadr stx))))

  (define (stx-define? stx)
    (and (pair? stx) (eq? (car stx) 'define)
         (>= (length stx) 2)))

  (define (stx-begin? stx)
    (and (pair? stx) (eq? (car stx) 'begin)))

  (define (stx-quote? stx)
    (and (pair? stx) (eq? (car stx) 'quote)
         (= (length stx) 2)))

  ;; ========== Destructuring Accessors ==========

  (define (stx-app-fn stx)
    (car stx))

  (define (stx-app-args stx)
    (cdr stx))

  (define (stx-lambda-formals stx)
    (cadr stx))

  (define (stx-lambda-body stx)
    (cddr stx))

  (define (stx-if-test stx)
    (cadr stx))

  (define (stx-if-then stx)
    (caddr stx))

  (define (stx-if-else stx)
    (if (= (length stx) 4)
      (cadddr stx)
      #f))

  (define (stx-let-bindings stx)
    (cadr stx))

  (define (stx-let-body stx)
    (cddr stx))

  ;; (define name val) -> name; (define (name args...) body...) -> name
  (define (stx-define-name stx)
    (let ([second (cadr stx)])
      (if (pair? second)
        (car second)  ;; (define (name args) body) form
        second)))     ;; (define name val) form

  ;; (define name val) -> val; (define (name args) body) -> (lambda (args) body...)
  (define (stx-define-value stx)
    (let ([second (cadr stx)])
      (if (pair? second)
        ;; Function shorthand form
        (cons 'lambda (cons (cdr second) (cddr stx)))
        ;; Simple form
        (if (= (length stx) 3)
          (caddr stx)
          #f))))

  (define (stx-begin-exprs stx)
    (cdr stx))

  (define (stx-identifier-symbol stx)
    (if (symbol? stx)
      stx
      (error 'stx-identifier-symbol "not an identifier" stx)))

  ;; ========== Pattern Matching Core ==========
  ;;
  ;; Pattern language:
  ;;   _                    — wildcard (matches anything)
  ;;   (quote datum)        — matches exactly datum (via equal?)
  ;;   (? pred)             — matches if (pred stx) is true
  ;;   (? pred var)         — matches and binds to var
  ;;   (list pat ...)       — matches a proper list with matching elements
  ;;   (pair pat1 pat2)     — matches a pair (car/cdr)
  ;;   (app fn-pat arg-pat ...) — like (list ...) but for applications
  ;;   sym                  — binds stx to sym in env (variable pattern)
  ;;
  ;; Returns: either an alist of bindings, or #f on failure.

  (define (match-pattern pat stx)
    ;; Returns #f on failure, or an alist of (sym . val) bindings
    (cond
      ;; Wildcard
      [(and (symbol? pat) (eq? pat '_))
       '()]
      ;; Variable binding (symbol not starting with special prefixes)
      [(symbol? pat)
       (list (cons pat stx))]
      ;; Quoted literal
      [(and (pair? pat) (eq? (car pat) 'quote))
       (if (equal? stx (cadr pat))
         '()
         #f)]
      ;; Predicate pattern (? pred) or (? pred var)
      ;; pred may be a procedure or a symbol to look up in (chezscheme)
      [(and (pair? pat) (eq? (car pat) '?))
       (let* ([raw-pred (cadr pat)]
              [pred     (if (procedure? raw-pred)
                          raw-pred
                          (eval raw-pred (environment '(chezscheme))))]
              [maybe-var (if (= (length pat) 3) (caddr pat) #f)])
         (if (pred stx)
           (if maybe-var (list (cons maybe-var stx)) '())
           #f))]
      ;; List pattern: (list pat ...)
      [(and (pair? pat) (eq? (car pat) 'list))
       (let ([pats (cdr pat)])
         (if (and (list? stx) (= (length stx) (length pats)))
           (match-list pats stx)
           #f))]
      ;; Pair pattern: (pair pat1 pat2)
      [(and (pair? pat) (eq? (car pat) 'pair))
       (if (pair? stx)
         (let ([b1 (match-pattern (cadr pat) (car stx))])
           (if b1
             (let ([b2 (match-pattern (caddr pat) (cdr stx))])
               (if b2 (append b1 b2) #f))
             #f))
         #f)]
      ;; Application pattern: (app fn-pat arg-pat ...)
      [(and (pair? pat) (eq? (car pat) 'app))
       (let ([pats (cdr pat)])
         (if (and (list? stx) (= (length stx) (length pats)))
           (match-list pats stx)
           #f))]
      ;; Fallback: pair patterns treated as list patterns for convenience
      [(pair? pat)
       (if (and (pair? stx) (= (length stx) (length pat)))
         (match-list pat stx)
         #f)]
      ;; Literal numbers/strings/booleans in pattern position
      [(or (number? pat) (string? pat) (boolean? pat) (char? pat))
       (if (equal? pat stx) '() #f)]
      [else #f]))

  (define (match-list pats stxs)
    ;; Match each pattern against corresponding stx; accumulate bindings
    (let loop ([ps pats] [ss stxs] [bindings '()])
      (cond
        [(and (null? ps) (null? ss)) bindings]
        [(or (null? ps) (null? ss)) #f]
        [else
         (let ([b (match-pattern (car ps) (car ss))])
           (if b
             (loop (cdr ps) (cdr ss) (append bindings b))
             #f))])))

  ;; Apply bindings to a template expression
  (define (instantiate-template template bindings)
    (cond
      [(symbol? template)
       (let ([b (assq template bindings)])
         (if b (cdr b) template))]
      [(not (pair? template)) template]
      [else
       (map (lambda (t) (instantiate-template t bindings)) template)]))

  ;; (syntax-match stx clause ...) -> result of first matching clause, or #f
  ;; Each clause: (pattern result-expr) or (pattern => proc)
  ;; Pattern variables are bound in result-expr.
  (define-syntax syntax-match
    (lambda (stx)
      ;; Local helper: extract pattern variable names from a datum pattern.
      ;; Defined inside the transformer to be available at expand time.
      (define (extract-vars pat)
        (cond
          [(and (symbol? pat) (not (eq? pat '_))) (list pat)]
          [(not (pair? pat)) '()]
          [(eq? (car pat) 'quote) '()]
          [(eq? (car pat) '?)
           (if (= (length pat) 3) (list (caddr pat)) '())]
          [(memq (car pat) '(list pair app))
           (apply append (map extract-vars (cdr pat)))]
          [else
           (apply append (map extract-vars pat))]))
      (syntax-case stx (=>)
        [(_ expr)
         #'#f]
        [(_ expr (pat => proc) rest ...)
         #'(let ([__sm-stx expr])
             (let ([__sm-b (match-pattern 'pat __sm-stx)])
               (if __sm-b
                 (proc __sm-b)
                 (syntax-match __sm-stx rest ...))))]
        [(_ expr (pat body ...) rest ...)
         (let* ([pat-datum (syntax->datum #'pat)]
                [vars      (extract-vars pat-datum)]
                ;; Use the whole stx as datum->syntax context identifier
                [ctx-id   (car (syntax->list stx))]  ;; 'syntax-match' identifier
                [var-stxs  (map (lambda (v) (datum->syntax ctx-id v)) vars)])
           (with-syntax ([(var ...) var-stxs])
             #'(let ([__sm-stx expr])
                 (let ([__sm-b (match-pattern 'pat __sm-stx)])
                   (if __sm-b
                     ;; Bind each pattern variable from the alist
                     (let ([var (let ([found (assq 'var __sm-b)])
                                  (if found (cdr found) #f))]
                           ...)
                       body ...)
                     (syntax-match __sm-stx rest ...))))))])))

  ;; Procedural version for runtime use
  (define (syntax-match-proc stx clauses)
    (let loop ([cs clauses])
      (if (null? cs)
        #f
        (let* ([clause  (car cs)]
               [pattern (car clause)]
               [handler (cdr clause)]
               [bindings (match-pattern pattern stx)])
          (if bindings
            (if (procedure? handler)
              (handler bindings)
              handler)
            (loop (cdr cs)))))))

  ;; (syntax-match* stx clause ...) -> result or error on no match
  (define-syntax syntax-match*
    (lambda (stx)
      (syntax-case stx ()
        [(_ expr clause ...)
         #'(let ([__result (syntax-match expr clause ...)])
             (if (eq? __result #f)
               (error 'syntax-match* "no matching clause" expr)
               __result))])))

  ;; ========== Code Walking ==========

  ;; (walk-syntax proc stx) -> transformed stx (bottom-up)
  ;; proc: datum -> datum | #f (if #f, keep original after descending)
  (define (walk-syntax proc stx)
    (let ([descended
           (if (pair? stx)
             (map (lambda (s) (walk-syntax proc s)) stx)
             stx)])
      (let ([result (proc descended)])
        (or result descended))))

  ;; (fold-syntax proc init stx) -> accumulated value
  ;; proc: (acc stx) -> new-acc, called on every node (leaves first)
  (define (fold-syntax proc init stx)
    (if (pair? stx)
      (let ([after-children (fold-left (lambda (acc s) (fold-syntax proc acc s)) init stx)])
        (proc after-children stx))
      (proc init stx)))

  ;; (free-identifiers stx bound-ids) -> list of free identifiers (symbols)
  ;; Returns symbols in stx that are not in bound-ids and not literals/special forms.
  (define (free-identifiers stx bound-ids)
    (define special-forms
      '(quote lambda if let let* letrec letrec* define begin
        and or cond case do syntax-rules define-syntax
        let-syntax letrec-syntax set!))
    (let loop ([expr stx] [bound bound-ids] [free '()])
      (cond
        [(symbol? expr)
         (if (or (memq expr bound)
                 (memq expr special-forms))
           free
           (if (memq expr free) free (cons expr free)))]
        [(not (pair? expr)) free]
        ;; Lambda: extend bound set
        [(eq? (car expr) 'lambda)
         (let* ([formals (cadr expr)]
                [formal-syms
                 (cond
                   [(list? formals) formals]
                   [(pair? formals)
                    (let f ([fs formals])
                      (cond [(null? fs) '()]
                            [(pair? fs) (cons (car fs) (f (cdr fs)))]
                            [else (list fs)]))]
                   [(symbol? formals) (list formals)]
                   [else '()])]
                [new-bound (append formal-syms bound)])
           (fold-left (lambda (f e) (loop e new-bound f))
                      free (cddr expr)))]
        ;; Let: analyze rhs in current scope, body in extended scope
        [(eq? (car expr) 'let)
         (let* ([bindings (cadr expr)]
                [names    (map car bindings)]
                [rhs      (map cadr bindings)]
                [body     (cddr expr)]
                [after-rhs (fold-left (lambda (f e) (loop e bound f)) free rhs)]
                [new-bound (append names bound)])
           (fold-left (lambda (f e) (loop e new-bound f)) after-rhs body))]
        ;; Quote: no free vars
        [(eq? (car expr) 'quote) free]
        ;; Define: name is bound in scope
        [(eq? (car expr) 'define)
         (let ([name (stx-define-name expr)]
               [val  (stx-define-value expr)])
           (let ([new-bound (cons name bound)])
             (if val (loop val new-bound free) free)))]
        ;; General: recurse into all sub-expressions
        [else
         (fold-left (lambda (f e) (loop e bound f)) free expr)])))

  ;; ========== Building Syntax ==========

  ;; (build-let bindings body)
  ;; bindings: list of (sym expr) pairs
  (define (build-let bindings body)
    (if (null? bindings)
      body
      (list 'let bindings body)))

  ;; (build-lambda formals body)
  (define (build-lambda formals body)
    (list 'lambda formals body))

  ;; (build-if test then [else])
  (define (build-if test then . else-args)
    (if (null? else-args)
      (list 'if test then)
      (list 'if test then (car else-args))))

  ;; (build-begin exprs)
  (define (build-begin exprs)
    (if (= (length exprs) 1)
      (car exprs)
      (cons 'begin exprs)))

  ;; (build-app fn args)
  (define (build-app fn args)
    (cons fn args))

  ) ;; end library
