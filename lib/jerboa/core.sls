#!chezscheme
;;; core.sls -- Gerbil-compatible syntax macros for Chez Scheme
;;;
;;; Implements: def, defstruct, defclass, defmethod, defrule, defrules,
;;; match, try/catch/finally, when, unless, while, until,
;;; hash, hash-eq, let-hash

(library (jerboa core)
  (export
    ;; definitions
    def def* defrule defrules

    ;; struct/class/method
    defstruct defclass defmethod

    ;; pattern matching
    match

    ;; control flow
    try catch finally
    while until

    ;; hash constructors
    hash-literal hash-eq-literal
    let-hash

    ;; re-export runtime
    ~ bind-method! call-method
    make-hash-table make-hash-table-eq
    hash-ref hash-get hash-put! hash-update! hash-remove!
    hash-key? hash->list hash->plist hash-for-each hash-map hash-fold
    hash-find hash-keys hash-values hash-copy hash-clear!
    hash-merge hash-merge! hash-length hash-table?
    list->hash-table plist->hash-table
    keyword? keyword->string string->keyword make-keyword
    error-message error-irritants error-trace
    displayln 1+ 1-
    iota last-pair
    *method-tables*
    register-struct-type! *struct-types*
    struct-predicate struct-field-ref struct-field-set!
    struct-type-info)

  (import (except (chezscheme)
            make-hash-table hash-table?
            iota
            1+ 1-)
          (jerboa runtime))

  ;;;; ---- Compile-time helpers ----

  (meta define (has-optionals? params)
    (cond
      [(null? params) #f]
      [(not (pair? params)) #f]  ; rest arg (symbol) = no optionals here
      [(pair? (car params)) #t]
      [else (has-optionals? (cdr params))]))

  (meta define (split-params params)
    (let loop ([rest params] [req '()] [opt '()])
      (cond
        [(null? rest) (values (reverse req) (reverse opt) #f)]
        [(symbol? rest) (values (reverse req) (reverse opt) rest)]
        [(pair? (car rest))
         (loop (cdr rest) req (cons (car rest) opt))]
        [else
         (if (null? opt)
           (loop (cdr rest) (cons (car rest) req) opt)
           (loop (cdr rest) req (cons (list (car rest) #f) opt)))])))

  (meta define (meta-take lst n)
    (if (or (zero? n) (null? lst)) '()
      (cons (car lst) (meta-take (cdr lst) (- n 1)))))

  (meta define (meta-drop lst n)
    (if (or (zero? n) (null? lst)) lst
      (meta-drop (cdr lst) (- n 1))))

  (meta define (generate-case-lambda-clauses name-stx params-stx body-stx)
    (let ([params (syntax->datum params-stx)])
      (let-values ([(required optionals rest)
                    (split-params params)])
        (let ([n-opt (length optionals)]
              [all-names (append required (map car optionals))])
          (let ([full-clause
                  (with-syntax ([(p ...) (datum->syntax name-stx all-names)]
                               [(b ...) body-stx])
                    #'((p ...) b ...))]
                [partial-clauses
                  (let loop ([i 0] [clauses '()])
                    (if (>= i n-opt)
                      (reverse clauses)
                      (let* ([present-opt (meta-take optionals i)]
                             [missing-opt (meta-drop optionals i)]
                             [clause-params (append required (map car present-opt))]
                             [defaults (map cadr missing-opt)]
                             [all-args (append clause-params defaults)])
                        (with-syntax ([(p ...) (datum->syntax name-stx clause-params)]
                                     [fn name-stx]
                                     [(a ...) (datum->syntax name-stx all-args)])
                          (loop (+ i 1)
                                (cons #'((p ...) (fn a ...)) clauses))))))])
            (append partial-clauses (list full-clause)))))))

  (meta define (gen-struct-names name-sym fields-sym)
    (let ([ns (symbol->string name-sym)])
      (values
        (string->symbol (string-append ns "::t"))
        (string->symbol (string-append "make-" ns))
        (string->symbol (string-append ns "?"))
        (map (lambda (f)
               (string->symbol (string-append ns "-" (symbol->string f))))
             fields-sym)
        (map (lambda (f)
               (string->symbol (string-append ns "-" (symbol->string f) "-set!")))
             fields-sym))))

  (meta define (gen-struct-body name-stx fields-list type-id-stx make-id-stx
                                pred-id-stx acc-stxs mut-stxs idx-stxs)
    ;; Generate accessor/mutator definitions as a list of syntax objects
    (let loop ([as acc-stxs] [ms mut-stxs] [is idx-stxs] [defs '()])
      (if (null? as)
        (reverse defs)
        (loop (cdr as) (cdr ms) (cdr is)
              (cons (with-syntax ([m (car ms)] [t type-id-stx] [i (car is)])
                      #'(define m (record-mutator t i)))
                    (cons (with-syntax ([a (car as)] [t type-id-stx] [i (car is)])
                            #'(define a (record-accessor t i)))
                          defs))))))

  ;;;; ---- DEF ----

  (define-syntax def
    (lambda (stx)
      (syntax-case stx ()
        [(_ (name . params) body ...)
         (identifier? #'name)
         (let ([params-list (syntax->datum #'params)])
           (if (has-optionals? params-list)
             (with-syntax ([(clause ...) (generate-case-lambda-clauses
                                           #'name #'params #'(body ...))])
               #'(define name (case-lambda clause ...)))
             #'(define (name . params) body ...)))]
        [(_ name expr)
         (identifier? #'name)
         #'(define name expr)]
        [(_ name)
         (identifier? #'name)
         #'(define name (void))])))

  ;;;; ---- DEF* (case-lambda) ----

  (define-syntax def*
    (syntax-rules ()
      [(_ name clause ...)
       (define name (case-lambda clause ...))]))

  ;;;; ---- DEFRULE / DEFRULES ----

  (define-syntax defrule
    (syntax-rules ()
      [(_ (name . pattern) template)
       (define-syntax name
         (syntax-rules ()
           [(_ . pattern) template]))]))

  (define-syntax defrules
    (syntax-rules ()
      [(_ name (keywords ...) clause ...)
       (define-syntax name
         (syntax-rules (keywords ...)
           clause ...))]))

  ;;;; ---- DEFSTRUCT ----

  (define-syntax defstruct
    (lambda (stx)
      (syntax-case stx ()
        [(_ name (field ...))
         (identifier? #'name)
         (let-values ([(type-id make-id pred-id accs muts)
                       (gen-struct-names (syntax->datum #'name)
                                         (syntax->datum #'(field ...)))])
           (with-syntax ([tid (datum->syntax #'name type-id)]
                         [mid (datum->syntax #'name make-id)]
                         [pid (datum->syntax #'name pred-id)]
                         [(acc ...) (datum->syntax #'name accs)]
                         [(mut ...) (datum->syntax #'name muts)]
                         [(idx ...) (datum->syntax #'name
                                     (iota (length (syntax->datum #'(field ...)))))])
             #'(begin
                 (define-record-type name
                   (fields (mutable field) ...))
                 (define tid (record-type-descriptor name))
                 (define mid
                   (record-constructor
                     (make-record-constructor-descriptor tid #f #f)))
                 (define pid (record-predicate tid))
                 (define acc (record-accessor tid idx)) ...
                 (define mut (record-mutator tid idx)) ...)))]
        [(_ (name parent) (field ...))
         (and (identifier? #'name) (identifier? #'parent))
         (let-values ([(type-id make-id pred-id accs muts)
                       (gen-struct-names (syntax->datum #'name)
                                         (syntax->datum #'(field ...)))])
           (with-syntax ([tid (datum->syntax #'name type-id)]
                         [mid (datum->syntax #'name make-id)]
                         [pid (datum->syntax #'name pred-id)]
                         [(acc ...) (datum->syntax #'name accs)]
                         [(mut ...) (datum->syntax #'name muts)]
                         [(idx ...) (datum->syntax #'name
                                     (iota (length (syntax->datum #'(field ...)))))])
             #'(begin
                 (define-record-type name
                   (parent parent)
                   (fields (mutable field) ...))
                 (define tid (record-type-descriptor name))
                 (define mid
                   (record-constructor
                     (make-record-constructor-descriptor tid #f #f)))
                 (define pid (record-predicate tid))
                 (define acc (record-accessor tid idx)) ...
                 (define mut (record-mutator tid idx)) ...)))])))

  ;;;; ---- DEFCLASS ----

  (define-syntax defclass
    (lambda (stx)
      (syntax-case stx ()
        [(_ (name parent) (field ...))
         #'(defstruct (name parent) (field ...))]
        [(_ name (field ...))
         #'(defstruct name (field ...))])))

  ;;;; ---- DEFMETHOD ----

  (define-syntax defmethod
    (lambda (stx)
      (syntax-case stx ()
        [(_ (method-name (self type) arg ...) body ...)
         (and (identifier? #'method-name)
              (identifier? #'self)
              (identifier? #'type))
         (with-syntax ([type-rtd (datum->syntax #'type
                                   (string->symbol
                                     (string-append
                                       (symbol->string (syntax->datum #'type))
                                       "::t")))])
           #'(bind-method! type-rtd 'method-name
               (lambda (self arg ...) body ...)))])))

  ;;;; ---- MATCH ----
  ;; Single procedural macro to avoid hygiene issues across macro boundaries

  (meta define (compile-match-pattern tmp-stx pat-stx success-stx fail-stx)
    (let ([pat (syntax->datum pat-stx)])
      (cond
        ;; Wildcard
        [(eq? pat '_) success-stx]

        ;; Null (empty list)
        [(null? pat)
         #`(if (null? #,tmp-stx) #,success-stx #,fail-stx)]

        ;; Boolean/number/string/char literal
        [(or (boolean? pat) (number? pat) (string? pat) (char? pat))
         #`(if (equal? #,tmp-stx #,pat-stx) #,success-stx #,fail-stx)]

        ;; Symbol = variable binding
        [(symbol? pat)
         #`(let ([#,pat-stx #,tmp-stx]) #,success-stx)]

        ;; List patterns
        [(pair? pat)
         (let ([head (car pat)])
           (cond
             ;; (quote x)
             [(eq? head 'quote)
              #`(if (equal? #,tmp-stx #,pat-stx) #,success-stx #,fail-stx)]

             ;; (list p ...)
             [(eq? head 'list)
              (let ([pats (cdr (syntax->list pat-stx))]
                    [n (length (cdr pat))])
                (let ([check-body
                        (let loop ([ps pats] [idx 0])
                          (if (null? ps)
                            success-stx
                            (let ([elem (datum->syntax tmp-stx (gensym "elem"))])
                              #`(let ([#,elem (list-ref #,tmp-stx #,idx)])
                                  #,(compile-match-pattern elem (car ps)
                                      (loop (cdr ps) (+ idx 1))
                                      fail-stx)))))])
                  #`(if (and (list? #,tmp-stx) (= (length #,tmp-stx) #,n))
                      #,check-body
                      #,fail-stx)))]

             ;; (cons a b)
             [(eq? head 'cons)
              (let ([parts (syntax->list pat-stx)])
                (let ([a-pat (cadr parts)]
                      [b-pat (caddr parts)]
                      [hd (datum->syntax tmp-stx (gensym "hd"))]
                      [tl (datum->syntax tmp-stx (gensym "tl"))])
                  (let ([inner (compile-match-pattern hd a-pat
                                 (compile-match-pattern tl b-pat success-stx fail-stx)
                                 fail-stx)])
                    #`(if (pair? #,tmp-stx)
                        (let ([#,hd (car #,tmp-stx)] [#,tl (cdr #,tmp-stx)])
                          #,inner)
                        #,fail-stx))))]

             ;; (? pred) or (? pred var)
             [(eq? head '?)
              (let ([parts (syntax->list pat-stx)])
                (if (= (length parts) 2)
                  ;; (? pred)
                  (let ([pred (cadr parts)])
                    #`(if (#,pred #,tmp-stx) #,success-stx #,fail-stx))
                  ;; (? pred var)
                  (let ([pred (cadr parts)]
                        [var (caddr parts)])
                    #`(if (#,pred #,tmp-stx)
                        (let ([#,var #,tmp-stx]) #,success-stx)
                        #,fail-stx))))]

             ;; (and p1 p2 ...)
             [(eq? head 'and)
              (let ([parts (cdr (syntax->list pat-stx))])
                (if (null? parts) success-stx
                  (let loop ([ps parts])
                    (if (null? (cdr ps))
                      (compile-match-pattern tmp-stx (car ps) success-stx fail-stx)
                      (compile-match-pattern tmp-stx (car ps)
                        (loop (cdr ps))
                        fail-stx)))))]

             ;; (or p1 p2 ...)
             [(eq? head 'or)
              (let ([parts (cdr (syntax->list pat-stx))])
                (if (null? parts) fail-stx
                  (let loop ([ps parts])
                    (if (null? (cdr ps))
                      (compile-match-pattern tmp-stx (car ps) success-stx fail-stx)
                      (compile-match-pattern tmp-stx (car ps)
                        success-stx
                        (loop (cdr ps)))))))]

             ;; (not p)
             [(eq? head 'not)
              (let ([parts (syntax->list pat-stx)])
                (compile-match-pattern tmp-stx (cadr parts) fail-stx success-stx))]

             ;; Pair pattern (a . b) — cons destructuring
             [else
              (let ([hd (datum->syntax tmp-stx (gensym "hd"))]
                    [tl (datum->syntax tmp-stx (gensym "tl"))])
                ;; Use syntax-case to destructure the pair pattern
                (syntax-case pat-stx ()
                  [(a-pat . b-pat)
                   (let ([inner (compile-match-pattern hd #'a-pat
                                  (compile-match-pattern tl #'b-pat success-stx fail-stx)
                                  fail-stx)])
                     #`(if (pair? #,tmp-stx)
                         (let ([#,hd (car #,tmp-stx)] [#,tl (cdr #,tmp-stx)])
                           #,inner)
                         #,fail-stx))]))]))]

        ;; Vector pattern
        [(vector? pat)
         ;; TODO: vector patterns
         fail-stx]

        ;; Fallthrough
        [else fail-stx])))

  (meta define (compile-match-clauses tmp-stx clauses)
    (if (null? clauses)
      #`(error 'match "no matching pattern" #,tmp-stx)
      (let ([clause (car clauses)]
            [rest (cdr clauses)])
        (let ([parts (syntax->list clause)])
          (let ([pat (car parts)]
                [body (cdr parts)])
            (if (eq? 'else (syntax->datum pat))
              ;; else clause
              #`(begin #,@body)
              ;; regular clause
              (let ([fail (compile-match-clauses tmp-stx rest)])
                (compile-match-pattern tmp-stx pat
                  #`(begin #,@body)
                  fail))))))))

  (define-syntax match
    (lambda (stx)
      (syntax-case stx ()
        [(k expr clause ...)
         (let ([tmp (datum->syntax #'k (gensym "match-tmp"))])
           #`(let ([#,tmp expr])
               #,(compile-match-clauses tmp (syntax->list #'(clause ...)))))])))

  ;;;; ---- TRY/CATCH/FINALLY ----

  (define-syntax try
    (lambda (stx)
      (syntax-case stx (catch finally)
        [(_ body ... (catch (pred var) handler ...) (finally cleanup ...))
         #'(dynamic-wind
             (lambda () (void))
             (lambda ()
               (guard (var [(pred var) handler ...])
                 body ...))
             (lambda () cleanup ...))]
        [(_ body ... (catch (var) handler ...) (finally cleanup ...))
         #'(dynamic-wind
             (lambda () (void))
             (lambda ()
               (guard (var [#t handler ...])
                 body ...))
             (lambda () cleanup ...))]
        [(_ body ... (catch (pred var) handler ...))
         #'(guard (var [(pred var) handler ...])
             body ...)]
        [(_ body ... (catch (var) handler ...))
         #'(guard (var [#t handler ...])
             body ...)]
        [(_ body ... (finally cleanup ...))
         #'(dynamic-wind
             (lambda () (void))
             (lambda () body ...)
             (lambda () cleanup ...))]
        [(_ body ...)
         #'(begin body ...)])))

  (define-syntax catch
    (lambda (stx)
      (syntax-violation 'catch "catch used outside of try" stx)))

  (define-syntax finally
    (lambda (stx)
      (syntax-violation 'finally "finally used outside of try" stx)))

  ;;;; ---- WHILE/UNTIL ----

  (define-syntax while
    (syntax-rules ()
      [(_ test body ...)
       (let loop ()
         (when test body ... (loop)))]))

  (define-syntax until
    (syntax-rules ()
      [(_ test body ...)
       (let loop ()
         (unless test body ... (loop)))]))

  ;;;; ---- HASH / HASH-EQ literals ----

  (define-syntax hash-literal
    (syntax-rules ()
      [(_ (key val) ...)
       (let ([ht (make-hash-table)])
         (hash-put! ht 'key val) ...
         ht)]))

  (define-syntax hash-eq-literal
    (syntax-rules ()
      [(_ (key val) ...)
       (let ([ht (make-hash-table-eq)])
         (hash-put! ht 'key val) ...
         ht)]))

  ;;;; ---- LET-HASH ----

  (define-syntax let-hash
    (lambda (stx)
      (syntax-case stx ()
        [(_ ht-expr body ...)
         (with-syntax ([ht-var (datum->syntax #'ht-expr (gensym "ht"))])
           #'(let ([ht-var ht-expr])
               (let-hash-body ht-var body) ...))])))

  (define-syntax let-hash-body
    (lambda (stx)
      (syntax-case stx ()
        [(_ ht expr)
         (let ([datum (syntax->datum #'expr)])
           (cond
             [(and (symbol? datum)
                   (let ([s (symbol->string datum)])
                     (and (> (string-length s) 1)
                          (char=? (string-ref s 0) #\.)
                          (not (and (> (string-length s) 1)
                                    (char=? (string-ref s 1) #\.))))))
              (let* ([s (symbol->string datum)]
                     [func/key
                       (cond
                         [(and (> (string-length s) 2)
                               (char=? (string-ref s 1) #\?))
                          (cons 'get (substring s 2 (string-length s)))]
                         [(and (> (string-length s) 2)
                               (char=? (string-ref s 1) #\$))
                          (cons 'get-str (substring s 2 (string-length s)))]
                         [else
                          (cons 'ref (substring s 1 (string-length s)))])])
                (let ([func (car func/key)]
                      [key-name (cdr func/key)])
                  (case func
                    [(ref)
                     (with-syntax ([key (datum->syntax #'expr
                                          (string->symbol key-name))])
                       #'(hash-ref ht 'key))]
                    [(get)
                     (with-syntax ([key (datum->syntax #'expr
                                          (string->symbol key-name))])
                       #'(hash-get ht 'key))]
                    [(get-str)
                     (with-syntax ([key (datum->syntax #'expr key-name)])
                       #'(hash-get ht key))])))]
             [(pair? datum)
              (with-syntax ([(transformed ...)
                             (map (lambda (sub)
                                    (with-syntax ([s sub])
                                      #'(let-hash-body ht s)))
                                  (syntax->list #'expr))])
                #'(transformed ...))]
             [else #'expr]))])))

  ) ;; end library
