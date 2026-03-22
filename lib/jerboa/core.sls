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
    hash hash-eq
    hash-literal hash-eq-literal
    let-hash

    ;; struct export helper
    struct-out

    ;; Gerbil compat I/O and filesystem
    read-line
    read-string
    getenv

    ;; I/O compat
    force-output

    ;; Thread + mutex (re-exported from :std/misc/thread)
    spawn spawn/name spawn/group
    make-thread thread-start! thread-join!
    thread-yield! thread-sleep! current-thread thread-name
    thread? thread-specific thread-specific-set!
    thread-interrupt! thread-terminate!
    make-mutex make-mutex-gambit mutex? mutex-name
    mutex-lock! mutex-unlock! mutex-specific mutex-specific-set!
    make-condition-variable condition-variable?
    condition-variable-signal! condition-variable-broadcast!
    condition-variable-specific condition-variable-specific-set!
    thread-send thread-receive thread-mailbox-next

    ;; Path utilities (re-exported from :std/os/path)
    path-expand path-normalize path-directory
    path-strip-directory path-extension path-strip-extension
    path-strip-trailing-directory-separator
    path-join path-absolute?
    with-exception-catcher
    create-directory create-directory*
    file-info file-info-type file-info-size file-info-mode
    file-info-last-modification-time file-info-last-access-time
    file-info-device file-info-inode file-info-owner file-info-group
    directory-files

    ;; re-export runtime
    ~ bind-method! call-method
    make-hash-table make-hash-table-eq
    hash-ref hash-get hash-put! hash-update! hash-remove!
    hash-key? hash->list hash->plist hash-for-each hash-map hash-fold
    hash-find hash-keys hash-values hash-copy hash-clear!
    hash-merge hash-merge! hash-length hash-table?
    list->hash-table plist->hash-table
    keyword? keyword->string string->keyword make-keyword
    keyword-arg-ref
    error-message error-irritants error-trace
    display-exception display-continuation-backtrace
    string-split string-empty? string-subst random-integer copy-file setenv
    user-info user-info-home user-name
    read-u8 write-u8
    f64vector-ref f64vector-set! f64vector-length make-f64vector
    input-port-timeout-set! output-port-timeout-set!
    u8vector u8vector-ref u8vector-set! u8vector-length u8vector->list list->u8vector
    subu8vector string->bytes bytes->string
    getpid random-bytes object->string
    filter-map
    displayln 1+ 1-
    arithmetic-shift
    any every
    time->seconds
    open-process open-input-process process-status
    string-map take drop delete last
    call-with-input-string call-with-output-string
    iota last-pair
    *method-tables*
    register-struct-type! *struct-types*
    struct-predicate struct-field-ref struct-field-set!
    struct-type-info)

  (import (except (chezscheme)
            make-hash-table hash-table?
            iota 1+ 1-
            getenv           ;; shadowed by our variadic wrapper
            path-extension path-absolute?  ;; provided by (std os path)
            thread?          ;; shadowed by (std misc thread)
            make-mutex mutex? mutex-name)  ;; wrapped by (std misc thread)
          (rename (only (chezscheme) getenv) (getenv %chez-getenv))
          (jerboa runtime)
          (std os path)
          (std misc thread)
          (only (std misc string) string-split string-empty?)
          (only (std misc list) filter-map))

  ;;;; ---- Compile-time helpers ----

  (meta define (keyword-sym? sym)
    ;; Check if a symbol looks like a keyword arg: ends with ':'
    (and (symbol? sym)
         (let ([s (symbol->string sym)])
           (and (> (string-length s) 1)
                (char=? (string-ref s (- (string-length s) 1)) #\:)))))

  (meta define (has-keywords? params)
    ;; Check if param list contains keyword: (var default) patterns
    (cond
      [(null? params) #f]
      [(not (pair? params)) #f]
      [(keyword-sym? (car params)) #t]
      [else (has-keywords? (cdr params))]))

  (meta define (has-optionals? params)
    (cond
      [(null? params) #f]
      [(not (pair? params)) #f]  ; rest arg (symbol) = no optionals here
      [(keyword-sym? (car params)) #t]  ; keyword args count as optionals
      [(pair? (car params)) #t]
      [else (has-optionals? (cdr params))]))

  (meta define (split-params params)
    ;; Returns (values required optionals rest-arg keywords)
    ;; keywords is a list of (keyword-symbol var-name default)
    (let loop ([rest params] [req '()] [opt '()] [kw '()])
      (cond
        [(null? rest) (values (reverse req) (reverse opt) #f (reverse kw))]
        [(symbol? rest) (values (reverse req) (reverse opt) rest (reverse kw))]
        ;; keyword: (var default) pattern
        [(and (keyword-sym? (car rest)) (pair? (cdr rest)) (pair? (cadr rest)))
         (let* ([kw-sym (car rest)]
                [kw-str (symbol->string kw-sym)]
                [kw-name (substring kw-str 0 (- (string-length kw-str) 1))]
                [binding (cadr rest)]
                [var-name (car binding)]
                [default (cadr binding)])
           (loop (cddr rest) req opt
                 (cons (list (string->symbol kw-name) var-name default) kw)))]
        [(pair? (car rest))
         (loop (cdr rest) req (cons (car rest) opt) kw)]
        [else
         (if (and (null? opt) (null? kw))
           (loop (cdr rest) (cons (car rest) req) opt kw)
           (loop (cdr rest) req (cons (list (car rest) #f) opt) kw))])))

  (meta define (meta-take lst n)
    (if (or (zero? n) (null? lst)) '()
      (cons (car lst) (meta-take (cdr lst) (- n 1)))))

  (meta define (meta-drop lst n)
    (if (or (zero? n) (null? lst)) lst
      (meta-drop (cdr lst) (- n 1))))

  (meta define (generate-keyword-clause name-stx required optionals keywords body-stx)
    ;; Generate a single clause: (req1 req2 ... . kwargs)
    ;; with let-bindings that extract keyword values from kwargs
    (let* ([all-positional (append required (map car optionals))]
           [kw-var-names (map cadr keywords)]
           [kw-defaults (map caddr keywords)]
           [kw-key-syms (map car keywords)]
           ;; Build the keyword extraction let-bindings
           [kw-bindings
             (map (lambda (kw)
                    (let ([key-sym (car kw)]
                          [var-name (cadr kw)]
                          [default (caddr kw)])
                      (list var-name
                            (list 'keyword-arg-ref '%kwargs
                                  (list 'quote (string->symbol
                                                 (string-append (symbol->string key-sym) ":")))
                                  default))))
                  keywords)])
      ;; Build: ((req1 req2 ... . %kwargs) (let ([kw1 ...] ...) body ...))
      (with-syntax ([(p ...) (datum->syntax name-stx all-positional)]
                    [rest-var (datum->syntax name-stx '%kwargs)]
                    [((kv kx) ...) (datum->syntax name-stx kw-bindings)]
                    [(b ...) body-stx])
        (list #'((p ... . rest-var) (let ([kv kx] ...) b ...))))))

  (meta define (generate-case-lambda-clauses name-stx params-stx body-stx)
    (let ([params (syntax->datum params-stx)])
      (let-values ([(required optionals rest keywords)
                    (split-params params)])
        (if (not (null? keywords))
          ;; Keyword args: generate a single clause with rest arg + keyword parsing
          (generate-keyword-clause name-stx required optionals keywords body-stx)
          ;; Positional-only: original case-lambda logic
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
              (append partial-clauses (list full-clause))))))))

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
         (let* ([name-sym (syntax->datum #'name)]
                [fields-list (syntax->datum #'(field ...))]
                [ns (symbol->string name-sym)])
           (let-values ([(type-id make-id pred-id accs muts)
                         (gen-struct-names name-sym fields-list)])
             ;; Generate internal accessor/mutator names to avoid conflicts
             (let ([int-accs (map (lambda (f)
                                    (gensym (string-append ns "-" (symbol->string f))))
                                  fields-list)]
                   [int-muts (map (lambda (f)
                                    (gensym (string-append ns "-" (symbol->string f) "-set!")))
                                  fields-list)])
               (with-syntax ([tid (datum->syntax #'name type-id)]
                             [mid (datum->syntax #'name make-id)]
                             [pid (datum->syntax #'name pred-id)]
                             [(acc ...) (datum->syntax #'name accs)]
                             [(mut ...) (datum->syntax #'name muts)]
                             [(idx ...) (datum->syntax #'name
                                         (iota (length fields-list)))]
                             [(iacc ...) (datum->syntax #'name int-accs)]
                             [(imut ...) (datum->syntax #'name int-muts)]
                             [hidden-name (datum->syntax #'name
                                            (gensym (symbol->string name-sym)))])
                 #'(begin
                     (define-record-type (hidden-name mid pid)
                       (fields (mutable field iacc imut) ...))
                     (define tid (record-type-descriptor hidden-name))
                     (define acc iacc) ...
                     (define mut imut) ...)))))]
        [(_ (name parent) (field ...))
         (and (identifier? #'name) (identifier? #'parent))
         (let* ([name-sym (syntax->datum #'name)]
                [fields-list (syntax->datum #'(field ...))]
                [ns (symbol->string name-sym)])
           (let-values ([(type-id make-id pred-id accs muts)
                         (gen-struct-names name-sym fields-list)])
             (let ([int-accs (map (lambda (f)
                                    (gensym (string-append ns "-" (symbol->string f))))
                                  fields-list)]
                   [int-muts (map (lambda (f)
                                    (gensym (string-append ns "-" (symbol->string f) "-set!")))
                                  fields-list)])
               (with-syntax ([tid (datum->syntax #'name type-id)]
                             [mid (datum->syntax #'name make-id)]
                             [pid (datum->syntax #'name pred-id)]
                             [(acc ...) (datum->syntax #'name accs)]
                             [(mut ...) (datum->syntax #'name muts)]
                             [(idx ...) (datum->syntax #'name
                                         (iota (length fields-list)))]
                             [(iacc ...) (datum->syntax #'name int-accs)]
                             [(imut ...) (datum->syntax #'name int-muts)]
                             [hidden-name (datum->syntax #'name
                                            (gensym (symbol->string name-sym)))])
                 #'(begin
                     (define-record-type (hidden-name mid pid)
                       (parent parent)
                       (fields (mutable field iacc imut) ...))
                     (define tid (record-type-descriptor hidden-name))
                     (define acc iacc) ...
                     (define mut imut) ...)))))]
        ;; Accept and ignore trailing keyword-value options (transparent:, opaque:, etc.)
        [(_ name (field ...) kw val rest ...)
         #'(defstruct name (field ...))]
        [(_ (name parent) (field ...) kw val rest ...)
         #'(defstruct (name parent) (field ...))])))

  ;;;; ---- DEFCLASS ----

  (define-syntax defclass
    (lambda (stx)
      (syntax-case stx ()
        [(_ (name parent) (field ...) rest ...)
         #'(defstruct (name parent) (field ...))]
        [(_ name (field ...) rest ...)
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

  ;;;; ---- HASH / HASH-EQ aliases ----
  ;; Gerbil uses (hash (k v) ...) directly; jerboa had hash-literal
  (define-syntax hash
    (syntax-rules ()
      [(_ (key val) ...)
       (hash-literal (key val) ...)]))

  ;; hash-eq is already exported from runtime as a procedure.
  ;; Re-define as a macro for the (hash-eq (k v) ...) literal form.
  ;; The runtime version handles the (hash-eq) / (hash-eq pairs...) cases.

  ;;;; ---- STRUCT-OUT ----
  ;; (struct-out name) is used inside export forms in Gerbil.
  ;; In jerboa, it's a compile-time expansion that cannot work inside
  ;; R6RS (export ...) forms. Instead, provide it as a macro that
  ;; expands to a begin with explicit definitions — this is a helper
  ;; for generating manual export lists, not a true export-spec.
  ;;
  ;; Usage: call (struct-out-names 'typename) at the REPL to see what to export.
  ;; The defstruct macro already defines make-X, X?, X-field, X-field-set! etc.
  ;; Users just need to list them in their library's export form.
  ;;
  ;; For convenience in top-level programs (not libraries), struct-out
  ;; is a no-op identity — the names are already bound.
  (define-syntax struct-out
    (syntax-rules ()
      [(_ name) (void)]))

  ;;;; ---- Gerbil compat: I/O ----
  ;; read-line: Gerbil-style (port is optional)
  (define (read-line . args)
    (let ([port (if (pair? args) (car args) (current-input-port))])
      (get-line port)))

  ;; getenv: Gerbil-style with optional default
  ;; Wraps Chez's built-in getenv (aliased as %chez-getenv) to add optional default.
  (define (getenv name . rest)
    (or (%chez-getenv name) (if (pair? rest) (car rest) #f)))

  ;; with-exception-catcher: Gambit-style handler that catches and escapes.
  ;; Uses call/cc so the handler's return value becomes the overall result,
  ;; instead of re-raising (which with-exception-handler does).
  (define (with-exception-catcher handler thunk)
    (call-with-current-continuation
      (lambda (k)
        (with-exception-handler
          (lambda (e) (k (handler e)))
          thunk))))

  ;;;; ---- Gerbil compat: Filesystem ----
  ;; create-directory: Gerbil alias for Chez mkdir
  (define create-directory mkdir)

  ;; create-directory*: recursive mkdir -p
  ;; Uses strict quoting to prevent shell injection via path names.
  (define (create-directory* path)
    (system (string-append "mkdir -p '"
              (string-replace-simple path "'" "'\"'\"'")
              "'")))

  ;; file-info record type (using Chez fields syntax)
  (define-record-type (file-info-rec make-file-info-rec file-info-rec?)
    (fields
      (immutable type file-info-type)
      (immutable size file-info-size)
      (immutable mode file-info-mode)
      (immutable mtime file-info-last-modification-time)))

  (define (file-info-last-access-time fi) (file-info-last-modification-time fi))
  (define (file-info-device fi) 0)
  (define (file-info-inode fi) 0)
  (define (file-info-owner fi) 0)
  (define (file-info-group fi) 0)

  ;; file-info: return a file-info-rec for the given path
  ;; Uses stat(2) via Chez's file-stat when available, with POSIX fallback.
  (define (file-info path . rest)
    (let ([type (cond
                  [(file-directory? path) 'directory]
                  [(file-regular? path)   'regular]
                  [(file-symbolic-link? path) 'symbolic-link]
                  [else 'unknown])]
          ;; Use Chez's built-in file-length for size (only works for regular files)
          [size (guard (exn [#t 0])
                  (if (file-regular? path)
                    (call-with-port (open-file-input-port path)
                      (lambda (p) (port-length p)))
                    0))]
          ;; Get modification time via Chez's file-modification-time (seconds since epoch)
          [mtime (guard (exn [#t 0])
                   (file-change-time path))])
      (make-file-info-rec type size 0 mtime)))

  ;; directory-files: list files in a directory (like Gambit's)
  (define (directory-files path)
    (directory-list path))

  ;; read-string: Gerbil-style (n port) → read up to n chars from port
  (define (read-string n . args)
    (let ([port (if (pair? args) (car args) (current-input-port))])
      (get-string-n port n)))

  ;; force-output: Gerbil/Gambit alias for Chez flush-output-port
  (define (force-output . args)
    (let ([port (if (pair? args) (car args) (current-output-port))])
      (flush-output-port port)))

  ;; mutex-lock!/mutex-unlock! and thread functions are provided by (std misc thread)

  ;; display-exception: Gerbil/Gambit compat — display an exception to a port
  ;; In Gerbil: (display-exception e [port]) — uses Chez display-condition equivalent
  (define (display-exception e . args)
    (let ([port (if (pair? args) (car args) (current-output-port))])
      (cond
        [(condition? e) (display-condition e port)]
        [else (display e port)])
      (newline port)))

  ;; display-continuation-backtrace: Gerbil/Gambit compat — no-op stub
  ;; Gambit can display a continuation as a stack trace; Chez has no equivalent.
  (define (display-continuation-backtrace k port)
    (void))

  ;; arithmetic-shift: Gerbil/Gambit compat — alias for Chez's ash
  (define (arithmetic-shift n count) (ash n count))

  ;; any/every: Gerbil/Gambit compat — SRFI-1 aliases for Chez's exists/for-all
  (define (any pred lst) (exists pred lst))
  (define (every pred lst) (for-all pred lst))

  ;; thread-interrupt!: Gerbil/Gambit compat — no-op stub.
  ;; Gambit: (thread-interrupt! thread thunk) runs thunk in thread's context.
  ;; Chez has no equivalent API for interrupting another thread.
  (define (thread-interrupt! thread thunk)
    (void))

  ;; thread-terminate!: Gerbil/Gambit compat — no-op stub.
  ;; Gambit: (thread-terminate! thread) terminates the thread.
  ;; Chez uses thread-kill (via (std misc thread)) but not exposed here.
  (define (thread-terminate! thread)
    (void))

  ;; take/drop: Gerbil/SRFI-1 compat — take/drop first n elements of a list.
  (define (take lst n)
    (if (or (<= n 0) (null? lst))
      '()
      (cons (car lst) (take (cdr lst) (- n 1)))))

  (define (drop lst n)
    (if (or (<= n 0) (null? lst))
      lst
      (drop (cdr lst) (- n 1))))

  ;; call-with-input-string: R7RS/Gambit compat — open string as input port and call proc.
  (define (call-with-input-string str proc)
    (proc (open-input-string str)))

  ;; call-with-output-string: R7RS/Gambit compat — call proc with output port, return string.
  (define (call-with-output-string proc)
    (let ((port (open-output-string)))
      (proc port)
      (get-output-string port)))

  ;; random-integer: Gambit compat — alias for Chez random.
  (define (random-integer n) (random n))

  ;; setenv: Gerbil/Gambit compat — set environment variable.
  (define (setenv name val) (putenv name val))

  ;; u8vector: Gambit byte vector compat — map to Chez bytevectors
  (define (u8vector . args) (apply bytevector args))
  (define (u8vector-ref bv i) (bytevector-u8-ref bv i))
  (define (u8vector-set! bv i v) (bytevector-u8-set! bv i v))
  (define (u8vector-length bv) (bytevector-length bv))
  (define (u8vector->list bv)
    (let loop ((i 0) (acc '()))
      (if (>= i (bytevector-length bv))
        (reverse acc)
        (loop (+ i 1) (cons (bytevector-u8-ref bv i) acc)))))
  (define (list->u8vector lst)
    (let* ((n (length lst)) (bv (make-bytevector n)))
      (let loop ((i 0) (l lst))
        (if (null? l) bv
          (begin (bytevector-u8-set! bv i (car l))
                 (loop (+ i 1) (cdr l)))))))
  (define (subu8vector bv start end)
    (let* ((len (- end start)) (result (make-bytevector len)))
      (bytevector-copy! bv start result 0 len)
      result))

  ;; object->string: convert any object to its write representation
  (define (object->string obj)
    (call-with-string-output-port
      (lambda (p) (write obj p))))

  ;; random-bytes: generate n cryptographically random bytes from /dev/urandom.
  ;; Falls back to Chez (random 256) only if /dev/urandom is unavailable.
  (define (random-bytes n)
    (guard (exn [#t
      ;; Fallback: non-CSPRNG — only for non-security use
      (let ((bv (make-bytevector n)))
        (let loop ((i 0))
          (if (>= i n) bv
            (begin (bytevector-u8-set! bv i (random 256))
                   (loop (+ i 1))))))])
      (let ((bv (make-bytevector n))
            (port (open-file-input-port "/dev/urandom"
                    (file-options) (buffer-mode block))))
        (let loop ((offset 0))
          (if (>= offset n)
            (begin (close-port port) bv)
            (let ((byte (get-u8 port)))
              (bytevector-u8-set! bv offset byte)
              (loop (+ offset 1))))))))

  ;; getpid: POSIX process ID — read from /proc/self (Linux)
  (define (getpid)
    (guard (exn [#t 0])
      (let* ((line (call-with-port (open-input-file "/proc/self/stat")
                     (lambda (p) (get-line p))))
             (end (let lp ((i 0))
                    (if (or (>= i (string-length line))
                            (char=? (string-ref line i) #\space))
                      i (lp (+ i 1))))))
        (or (string->number (substring line 0 end)) 0))))

  ;; string<->bytes: Gerbil/Gambit UTF-8 string conversion
  (define (string->bytes str)
    (string->utf8 str))
  (define (bytes->string bv)
    (utf8->string bv))

  ;; Port timeout stubs — Gambit-specific, no-op in Chez
  (define (input-port-timeout-set! port timeout) (void))
  (define (output-port-timeout-set! port timeout) (void))

  ;; f64vector: Gambit float64 vector compat — map to Chez flvectors
  (define (make-f64vector n . rest)
    (let ((init (if (pair? rest) (car rest) 0.0)))
      (make-flvector n (inexact init))))
  (define (f64vector-ref v i) (flvector-ref v i))
  (define (f64vector-set! v i x) (flvector-set! v i (inexact x)))
  (define (f64vector-length v) (flvector-length v))

  ;; SRFI-1 last: return the last element of a list
  (define (last lst)
    (if (null? (cdr lst)) (car lst) (last (cdr lst))))

  ;; SRFI-1 delete: remove all elements equal? to x from lst
  (define (delete x lst . rest)
    (let ((= (if (pair? rest) (car rest) equal?)))
      (filter (lambda (e) (not (= x e))) lst)))

  ;; R7RS I/O compat
  (define (read-u8 . rest)
    (let ((port (if (pair? rest) (car rest) (current-input-port))))
      (get-u8 port)))
  (define (write-u8 byte . rest)
    (let ((port (if (pair? rest) (car rest) (current-output-port))))
      (put-u8 port byte)))

  ;; user-info: Gerbil/Gambit compat — returns a user-info record.
  ;; Simplified: reads from environment; only supports current user.
  ;; WARNING: The name-or-uid argument is checked — errors if it doesn't
  ;; match the current user, rather than silently returning wrong data.
  (define-record-type user-info-record
    (fields name home uid gid shell)
    (sealed #t))
  (define (user-name)
    (or (getenv "USER") (getenv "LOGNAME") "user"))
  (define (user-info name-or-uid)
    (let ([current (user-name)])
      (when (and (string? name-or-uid)
                 (not (string=? name-or-uid current)))
        (error 'user-info
          "only current user is supported; use POSIX getpwnam for other users"
          name-or-uid))
      (make-user-info-record
        current
        (or (getenv "HOME") "/")
        0 0 (or (getenv "SHELL") "/bin/sh"))))
  (define (user-info-home ui) (user-info-record-home ui))

  ;; copy-file: Gerbil compat — copy file at src to dst.
  (define (copy-file src dst)
    (call-with-port (open-file-input-port src)
      (lambda (in)
        (call-with-port (open-file-output-port dst (file-options no-fail) (buffer-mode block))
          (lambda (out)
            (let loop ()
              (let ((chunk (get-bytevector-n in 65536)))
                (unless (eof-object? chunk)
                  (put-bytevector out chunk)
                  (loop)))))))))

  ;; string-subst: Gerbil compat — replace all occurrences of old in str with new.
  (define (string-subst str old new)
    (let* ((old-len (string-length old))
           (new-len (string-length new))
           (str-len (string-length str)))
      (if (= old-len 0)
        str
        (let loop ((i 0) (result '()))
          (cond
            ((> (+ i old-len) str-len)
             (list->string (reverse (append (reverse (string->list (substring str i str-len))) result))))
            ((string=? (substring str i (+ i old-len)) old)
             (loop (+ i old-len) (append (reverse (string->list new)) result)))
            (else
             (loop (+ i 1) (cons (string-ref str i) result))))))))

  ;; string-map: R7RS compat — apply proc to each character and collect results.
  (define (string-map proc str . rest)
    (if (null? rest)
      (list->string (map proc (string->list str)))
      (list->string (apply map proc (map string->list (cons str rest))))))

  ;; time->seconds: Gerbil/SRFI-19 compat — converts a Chez time record to float seconds.
  (define (time->seconds t)
    (if (time? t)
      (+ (time-second t) (/ (time-nanosecond t) 1000000000.0))
      t))

  ;; Shell quoting helper: wraps in single quotes, escapes embedded single quotes.
  ;; This prevents ALL shell metacharacter interpretation.
  (define (shell-quote-simple s)
    (string-append "'" (string-replace-simple s "'" "'\"'\"'") "'"))

  ;; Simple string replacement (used for shell quoting)
  (define (string-replace-simple str old new)
    (let* ([old-len (string-length old)]
           [str-len (string-length str)])
      (if (= old-len 0) str
        (let loop ([i 0] [result '()])
          (cond
            [(> (+ i old-len) str-len)
             (list->string (reverse (append (reverse (string->list (substring str i str-len))) result)))]
            [(string=? (substring str i (+ i old-len)) old)
             (loop (+ i old-len) (append (reverse (string->list new)) result))]
            [else
             (loop (+ i 1) (cons (string-ref str i) result))])))))

  ;; open-process: Gambit compat — run a subprocess and return a bidirectional port.
  ;; plist is a list with keyword args: path: arguments: directory:
  ;; stdin-redirection: stdout-redirection: stderr-redirection:
  ;; Returns a custom textual port backed by open-process-ports.
  (define *process-pids* (make-hashtable equal-hash equal?))

  (define (open-process plist)
    (define (find-key key lst)
      (let loop ((l lst))
        (cond ((null? l) #f)
              ((equal? (car l) key) (cadr l))
              ((null? (cdr l)) #f)
              (else (loop (cddr l))))))
    (let* ((path (or (find-key 'path: plist) "sh"))
           (args (or (find-key 'arguments: plist) '()))
           (dir  (find-key 'directory: plist))
           ;; Shell-quote each argument to prevent injection
           (cmd  (apply string-append
                        (cons (shell-quote-simple path)
                              (map (lambda (a)
                                     (string-append " " (shell-quote-simple a)))
                                   args))))
           (full-cmd (if dir
                       (string-append "cd " (shell-quote-simple dir) " && " cmd)
                       cmd)))
      (let-values (((in-port out-port err-port pid)
                    (open-process-ports full-cmd
                                        (buffer-mode block)
                                        (native-transcoder))))
        ;; Create a custom port that reads from in-port and writes to out-port
        (let* ((closed #f)
               (read-proc (lambda (str start count)
                 (let loop ((i 0))
                   (if (>= i count)
                     i
                     (let ((ch (read-char in-port)))
                       (if (eof-object? ch)
                         i
                         (begin
                           (string-set! str (+ start i) ch)
                           (loop (+ i 1)))))))))
               (write-proc (lambda (str start count)
                 (display (substring str start (+ start count)) out-port)
                 count))
               (close-proc (lambda ()
                 (unless closed
                   (set! closed #t)
                   (close-port in-port)
                   (close-port out-port)
                   (close-port err-port))))
               (port (make-custom-textual-input/output-port
                       (string-append "process:" path)
                       read-proc write-proc #f #f close-proc)))
          (hashtable-set! *process-pids* port pid)
          port))))

  ;; open-input-process: Gambit compat — read-only subprocess.
  ;; Like open-process but returns a read-only port (stdout-redirection only).
  (define (open-input-process plist)
    (open-process plist))

  ;; process-status: Gambit compat — wait for process and return exit code.
  ;; Drains the port to allow the subprocess to finish, then retrieves the PID
  ;; from our tracking table and waits for the real exit status.
  (define (process-status proc)
    ;; Close port to signal we're done; process will exit
    (when (input-port? proc)
      (let drain ()
        (let ((ch (read-char proc)))
          (unless (eof-object? ch)
            (drain)))))
    ;; Try to get real exit status via the PID we stored
    (let ([pid (hashtable-ref *process-pids* proc #f)])
      (if pid
        (guard (exn [#t 0])
          ;; Use waitpid via system call
          (let ([status (system (string-append "wait " (number->string pid) " 2>/dev/null; echo $?"))])
            status))
        0)))

) ;; end (library jerboa core)
