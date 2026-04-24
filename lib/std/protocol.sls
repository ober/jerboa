#!chezscheme
;;; (std protocol) — Clojure-style protocols.
;;;
;;; A protocol is a named bundle of method names. Each method is a
;;; procedure that dispatches on the *type* of its first argument.
;;; Any number of types can opt in by providing method implementations;
;;; types do not need to know about the protocol up front.
;;;
;;;   (defprotocol Shape
;;;     (area     (self))
;;;     (perimeter (self)))
;;;
;;;   (defstruct circle (r))
;;;   (extend-type circle::t Shape
;;;     (area     (c) (* 3.14 (circle-r c) (circle-r c)))
;;;     (perimeter (c) (* 2 3.14 (circle-r c))))
;;;
;;;   (extend-protocol Shape
;;;     ('string (area (s) (string-length s))
;;;              (perimeter (s) (* 4 (string-length s))))
;;;     ('pair   (area (p) (length p))
;;;              (perimeter (p) (* 2 (length p)))))
;;;
;;;   (area (make-circle 3))  ;; => 28.26
;;;   (area "hello")          ;; => 5
;;;
;;; Type keys
;;; ---------
;;; A "type key" identifies the type for dispatch:
;;;
;;; - For records (`defstruct` / `define-record-type`), use the rtd:
;;;     `point::t` for defstruct forms (they bind the rtd as `name::t`)
;;;     `(record-type-descriptor point)` for define-record-type.
;;; - For built-in types, use a symbol: `'string`, `'vector`, `'pair`,
;;;   `'null`, `'number`, `'symbol`, `'boolean`, `'char`, `'procedure`,
;;;   `'hashtable`, `'bytevector`, `'eof`.
;;; - The sentinel `'any` is the universal fallback. A method with an
;;;   'any implementation fires when no type-specific method exists.
;;;
;;; Method body syntax
;;; ------------------
;;; Each method is written like a plain lambda:
;;;
;;;   (area (c) (* 3.14 (circle-r c) (circle-r c)))
;;;
;;; The first parameter is always the dispatch value (traditionally
;;; `self` in Clojure), but any name works.
;;;
;;; Unlike (std multi), `defprotocol` shares namespace with the rest
;;; of your code: each method name is defined as a top-level procedure.
;;; This is safe to import into the prelude because the method names
;;; are user-chosen and don't collide with built-ins.
;;;
;;; Thread safety
;;; -------------
;;; Protocol dispatch is backed by a global registry guarded by a
;;; single mutex. Method lookup takes the lock; method *bodies* run
;;; outside the lock, so a method may call the same protocol on a
;;; different type without deadlocking.

(library (std protocol)
  (export
    defprotocol extend-type extend-protocol
    protocol? protocol-name protocol-methods
    satisfies? extenders extends?)

  (import (chezscheme))

  ;; --- Type key -----------------------------------------------

  (define (%type-of x)
    (cond
      [(record? x) (record-rtd x)]
      [(pair? x) 'pair]
      [(null? x) 'null]
      [(string? x) 'string]
      [(vector? x) 'vector]
      [(symbol? x) 'symbol]
      [(number? x) 'number]
      [(boolean? x) 'boolean]
      [(char? x) 'char]
      [(procedure? x) 'procedure]
      [(hashtable? x) 'hashtable]
      [(bytevector? x) 'bytevector]
      [(eof-object? x) 'eof]
      [else 'any]))

  ;; --- Dispatch table -----------------------------------------
  ;;
  ;; The dispatch table is a two-level `eq?`-hashtable:
  ;;
  ;;   type-key -> (eq-hashtable method-sym -> procedure)
  ;;
  ;; Both keys are always `eq?`-comparable:
  ;; - method-sym is a symbol
  ;; - type-key is either a symbol (for built-ins) or an rtd (records).
  ;;   Record type descriptors compare by identity in Chez.

  (define %dispatch (make-eq-hashtable))
  (define %dispatch-lock (make-mutex))

  (define (%register-impl! method-sym type-key proc)
    (with-mutex %dispatch-lock
      (let ([inner (eq-hashtable-ref %dispatch type-key #f)])
        (cond
          [inner (eq-hashtable-set! inner method-sym proc)]
          [else
           (let ([new-inner (make-eq-hashtable)])
             (eq-hashtable-set! new-inner method-sym proc)
             (eq-hashtable-set! %dispatch type-key new-inner))]))))

  (define (%lookup-impl method-sym obj)
    (let ([type-key (%type-of obj)])
      (with-mutex %dispatch-lock
        (let ([inner (eq-hashtable-ref %dispatch type-key #f)])
          (or (and inner (eq-hashtable-ref inner method-sym #f))
              (let ([any-inner (eq-hashtable-ref %dispatch 'any #f)])
                (and any-inner
                     (eq-hashtable-ref any-inner method-sym #f))))))))

  (define (%has-impl-for? method-sym type-key)
    (with-mutex %dispatch-lock
      (let ([inner (eq-hashtable-ref %dispatch type-key #f)])
        (and inner
             (and (eq-hashtable-ref inner method-sym #f) #t)))))

  (define (%make-dispatcher method-sym)
    (lambda args
      (when (null? args)
        (error method-sym
               "protocol method called with no arguments"))
      (let ([impl (%lookup-impl method-sym (car args))])
        (cond
          [impl (apply impl args)]
          [else
           (error method-sym
                  "no implementation for type"
                  (%type-of (car args)))]))))

  ;; --- Protocol record ----------------------------------------

  (define-record-type %protocol
    (fields (immutable name)
            (immutable methods))       ;; list of method name symbols
    (sealed #t))

  (define (protocol? x) (%protocol? x))
  (define (protocol-name p)
    (unless (%protocol? p)
      (error 'protocol-name "not a protocol" p))
    (%protocol-name p))
  (define (protocol-methods p)
    (unless (%protocol? p)
      (error 'protocol-methods "not a protocol" p))
    (%protocol-methods p))

  ;; --- Public macros ------------------------------------------

  ;; (defprotocol NAME
  ;;   (method-name (self arg ...)) ...)
  ;;
  ;; Binds NAME to a protocol handle and introduces each method-name
  ;; as a top-level procedure that dispatches on the first argument's
  ;; type. The formals list after each method-name is documentation —
  ;; individual implementations may have any arity.
  (define-syntax defprotocol
    (syntax-rules ()
      [(_ name (method-name formals) ...)
       (begin
         (define method-name (%make-dispatcher 'method-name)) ...
         (define name
           (make-%protocol 'name '(method-name ...))))]))

  ;; (extend-type TYPE-EXPR PROTOCOL
  ;;   (method-name (self arg ...) body ...) ...)
  ;;
  ;; Registers method implementations for TYPE-EXPR against PROTOCOL.
  ;; TYPE-EXPR is evaluated and must be either a record type
  ;; descriptor (rtd) or a symbol identifying a built-in type.
  ;; PROTOCOL is referenced for documentation only — the actual
  ;; registration is keyed on method name + type key.
  (define-syntax extend-type
    (syntax-rules ()
      [(_ type-expr protocol-name
          (method-name (arg ...) body ...) ...)
       (let ([%tk type-expr])
         (%register-impl! 'method-name %tk
                          (lambda (arg ...) body ...))
         ...
         %tk)]))

  ;; (extend-protocol PROTOCOL
  ;;   (TYPE-EXPR
  ;;     (method-name (self arg ...) body ...) ...) ...)
  ;;
  ;; Shorthand for registering multiple types against a single
  ;; protocol. Each (TYPE-EXPR ...) group produces one `extend-type`
  ;; expansion.
  (define-syntax extend-protocol
    (syntax-rules ()
      [(_ protocol-name
          (type-expr (method-name (arg ...) body ...) ...) ...)
       (begin
         (extend-type type-expr protocol-name
           (method-name (arg ...) body ...) ...)
         ...)]))

  ;; (satisfies? PROTOCOL OBJ)
  ;;
  ;; Returns #t iff every method in PROTOCOL has an explicit
  ;; implementation for the object's type. An 'any fallback does
  ;; NOT count as satisfying the protocol — matches Clojure's
  ;; behaviour where `Object` methods are separate from type-specific
  ;; ones.
  (define (satisfies? p x)
    (unless (%protocol? p)
      (error 'satisfies? "not a protocol" p))
    (let ([type-key (%type-of x)])
      (for-all
        (lambda (name) (%has-impl-for? name type-key))
        (%protocol-methods p))))

  ;; (extenders PROTOCOL)
  ;;
  ;; Returns the list of type-keys (rtds or symbols) that have
  ;; registered implementations for EVERY method in PROTOCOL.
  ;; Types with partial coverage are excluded — mirrors Clojure's
  ;; contract that a type either satisfies the protocol or it doesn't.
  ;; Order is unspecified.
  (define (extenders p)
    (unless (%protocol? p)
      (error 'extenders "not a protocol" p))
    (let ([methods (%protocol-methods p)])
      (with-mutex %dispatch-lock
        (let-values ([(tks _) (hashtable-entries %dispatch)])
          (let loop ([i 0] [acc '()])
            (cond
              [(= i (vector-length tks)) acc]
              [else
               (let* ([tk (vector-ref tks i)]
                      [inner (eq-hashtable-ref %dispatch tk #f)]
                      [covers-all?
                       (and inner
                            (for-all
                              (lambda (m)
                                (and (eq-hashtable-ref inner m #f) #t))
                              methods))])
                 (loop (+ i 1)
                       (if covers-all? (cons tk acc) acc)))]))))))

  ;; (extends? PROTOCOL TYPE-KEY)
  ;;
  ;; True iff TYPE-KEY has implementations for every method in PROTOCOL.
  ;; Accepts either an rtd or a symbol; distinct from `satisfies?`,
  ;; which takes an instance.
  (define (extends? p type-key)
    (unless (%protocol? p)
      (error 'extends? "not a protocol" p))
    (for-all
      (lambda (m) (%has-impl-for? m type-key))
      (%protocol-methods p)))

) ;; end library
