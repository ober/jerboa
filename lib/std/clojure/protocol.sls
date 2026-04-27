#!chezscheme
;;; (std clojure protocol) — Clojure-style defprotocol.
;;;
;;; Round 14 (2026-04-27) — closes the last common Clojure surface gap.
;;;
;;; (defprotocol Name
;;;   (method-1 [this])
;;;   (method-2 [this x y]))
;;;
;;; (extend-type predicate Name
;;;   (method-1 [this] body ...)
;;;   (method-2 [this x y] body ...))
;;;
;;; (extend-protocol Name
;;;   pred-1 (m1 [this] ...) (m2 [this x y] ...)
;;;   pred-2 (m1 [this] ...) (m2 [this x y] ...))
;;;
;;; (satisfies? Name value)   — does value's type implement Name?
;;; (extends?   Name pred)    — has Name been extended for pred?
;;;
;;; Dispatch: each protocol carries a mutable list of
;;; (predicate . method-alist) entries; calling a protocol method
;;; walks the list for the first matching predicate.
;;;
;;; No relation to (std actor protocol), which is actor-specific.

(library (std clojure protocol)
  (export
    defprotocol
    extend-type
    extend-protocol
    satisfies?
    extends?
    protocol?
    protocol-name
    protocol-methods
    ;; Clojure-named predicate aliases for ergonomic extend-protocol
    Number? String? Vector? List? Keyword? Symbol? Char?
    Boolean? Hash? Bytevector? Pair? Null?)

  (import (chezscheme))

  ;; ---- protocol record ----

  (define-record-type protocol-rec
    (fields
      name
      methods                  ;; list of method names (symbols)
      (mutable impls))          ;; list of (predicate . method-alist)
    (protocol
      (lambda (new)
        (lambda (name methods)
          (new name methods '())))))

  (define (protocol? x) (protocol-rec? x))
  (define (protocol-name p) (protocol-rec-name p))
  (define (protocol-methods p) (protocol-rec-methods p))

  ;; ---- dispatch ----

  (define (lookup-impl prot value method-name)
    (let loop ([entries (protocol-rec-impls prot)])
      (cond
        [(null? entries) #f]
        [((caar entries) value)
         (cond
           [(assq method-name (cdar entries)) => cdr]
           [else (loop (cdr entries))])]
        [else (loop (cdr entries))])))

  (define (protocol-not-satisfied prot method-name value)
    (error method-name
           (string-append "no implementation of protocol "
                          (symbol->string (protocol-rec-name prot))
                          " method "
                          (symbol->string method-name)
                          " for value")
           value))

  (define (extend-protocol! prot pred method-alist)
    ;; Replace any previous registration for the same predicate
    ;; (so that re-extending is idempotent and updates impls).
    (let* ([impls (protocol-rec-impls prot)]
           [filtered (filter (lambda (e) (not (eq? (car e) pred)))
                             impls)])
      (protocol-rec-impls-set! prot
        (cons (cons pred method-alist) filtered))))

  ;; ---- satisfies? / extends? ----

  (define (satisfies? prot value)
    (let loop ([entries (protocol-rec-impls prot)])
      (cond
        [(null? entries) #f]
        [((caar entries) value) #t]
        [else (loop (cdr entries))])))

  (define (extends? prot pred)
    (let loop ([entries (protocol-rec-impls prot)])
      (cond
        [(null? entries) #f]
        [(eq? (caar entries) pred) #t]
        [else (loop (cdr entries))])))

  ;; ---- defprotocol macro ----
  ;;
  ;; (defprotocol Name
  ;;   (method-1 [this] "optional docstring")
  ;;   (method-2 [this a b]))
  ;;
  ;; Each method form starts with the method name and its signature.
  ;; A trailing string is treated as a docstring and ignored at runtime.

  (define-syntax defprotocol
    (lambda (stx)
      (syntax-case stx ()
        [(_ name method-spec ...)
         (with-syntax
             ([(mname ...)
               (map (lambda (spec)
                      (syntax-case spec ()
                        [(mname . rest) #'mname]))
                    #'(method-spec ...))])
           #'(begin
               (define name (make-protocol-rec 'name '(mname ...)))
               (define (mname . args)
                 (when (null? args)
                   (error 'mname
                          "protocol method requires at least one argument"))
                 (let* ([this (car args)]
                        [impl (lookup-impl name this 'mname)])
                   (if impl
                     (apply impl args)
                     (protocol-not-satisfied name 'mname this))))
               ...))])))

  ;; ---- extend-type macro ----
  ;;
  ;; (extend-type pred Protocol
  ;;   (method-1 [this] body ...)
  ;;   (method-2 [this a b] body ...))

  (define-syntax extend-type
    (syntax-rules ()
      [(_ pred prot (mname args body ...) ...)
       (extend-protocol! prot pred
         (list (cons 'mname (lambda args body ...)) ...))]))

  ;; ---- extend-protocol macro ----
  ;;
  ;; Multi-type form:
  ;;   (extend-protocol Prot
  ;;     pred-1 (m1 [this] ...) (m2 [this x] ...)
  ;;     pred-2 (m1 [this] ...) (m2 [this x] ...))
  ;;
  ;; Limitation: predicates must be identifiers (so the macro can
  ;; distinguish them from method forms).  For expression-valued
  ;; predicates, use separate `extend-type` calls.

  (define-syntax extend-protocol
    (syntax-rules ()
      [(_ prot clause ...)
       (do-extend-protocol prot () (clause ...))]))

  (define-syntax do-extend-protocol
    (syntax-rules ()
      [(_ prot () ()) (begin)]
      [(_ prot (acc ...) ()) (begin acc ...)]
      [(_ prot (acc ...) (pred clause-rest ...))
       (collect-methods prot pred () (acc ...) (clause-rest ...))]))

  (define-syntax collect-methods
    (syntax-rules ()
      [(_ prot pred (mforms ...) (acc ...) ())
       (begin acc ... (extend-type pred prot mforms ...))]
      [(_ prot pred (mforms ...) (acc ...) ((mname args body ...) rest ...))
       (collect-methods prot pred (mforms ... (mname args body ...))
                        (acc ...) (rest ...))]
      [(_ prot pred (mforms ...) (acc ...) (next-pred rest ...))
       (do-extend-protocol prot
         (acc ... (extend-type pred prot mforms ...))
         (next-pred rest ...))]))

  ;; ---- Clojure-named predicate aliases ----
  ;;
  ;; These let users write `extend-protocol P Number? ...` matching
  ;; Clojure's `extend-protocol P Number ...` syntax.  All are simple
  ;; one-argument predicates over Scheme values.

  (define (Number?     x) (number? x))
  (define (String?     x) (string? x))
  (define (Vector?     x) (vector? x))
  (define (List?       x) (or (null? x) (pair? x)))
  (define (Pair?       x) (pair? x))
  (define (Null?       x) (null? x))
  (define (Keyword?    x) (and (symbol? x)
                               (let ([s (symbol->string x)])
                                 (and (> (string-length s) 0)
                                      (char=? #\: (string-ref s 0))))))
  (define (Symbol?     x) (and (symbol? x) (not (Keyword? x))))
  (define (Char?       x) (char? x))
  (define (Boolean?    x) (boolean? x))
  (define (Hash?       x) (hashtable? x))
  (define (Bytevector? x) (bytevector? x))

) ;; end library
