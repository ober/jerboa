#!chezscheme
;;; (std typed typeclass) — Haskell-style type classes as dictionaries
;;;
;;; Type classes are dictionaries (eq-hashtables) mapping method names to
;;; procedures. Instances are registered per type-tag (a symbol or predicate).
;;; with-class does lexical method binding via let.
;;;
;;; API:
;;;   (define-class ClassName (method arg ...) ...)
;;;     — define a class with a set of method signatures
;;;
;;;   (define-instance ClassName type-tag
;;;     (method impl) ...)
;;;     — register an instance implementation for a type
;;;
;;;   (with-class ClassName body ...)
;;;     — bring class methods into scope (looks up instance by first arg's type)
;;;
;;;   (instance-of ClassName type-tag) => instance or #f
;;;   (class-method instance method-name) => procedure

(library (std typed typeclass)
  (export
    define-class
    define-instance
    with-class
    instance-of
    class-method)
  (import (chezscheme))

  ;; ========== Class registry ==========
  ;;
  ;; *class-registry* : symbol -> class-descriptor
  ;; class-descriptor: #(class-name methods instances)
  ;;   methods: list of method name symbols (for documentation/validation)
  ;;   instances: eq-hashtable of type-tag -> instance-hashtable

  (define *class-registry* (make-eq-hashtable))

  (define (make-class-descriptor name methods)
    (vector 'class-descriptor name methods (make-eq-hashtable)))

  (define (class-descriptor? v)
    (and (vector? v)
         (= (vector-length v) 4)
         (eq? (vector-ref v 0) 'class-descriptor)))

  (define (class-descriptor-name cd) (vector-ref cd 1))
  (define (class-descriptor-methods cd) (vector-ref cd 2))
  (define (class-descriptor-instances cd) (vector-ref cd 3))

  ;; ========== Instance lookup ==========

  (define (instance-of class-name type-tag)
    (let ([cd (hashtable-ref *class-registry* class-name #f)])
      (if cd
        (hashtable-ref (class-descriptor-instances cd) type-tag #f)
        #f)))

  (define (class-method inst method-name)
    (hashtable-ref inst method-name #f))

  ;; ========== Type tag inference ==========
  ;;
  ;; Determine the type tag for a value by trying common predicates.
  ;; Used by with-class to look up the right instance automatically.

  (define (infer-type-tag v)
    (cond
      [(boolean? v)    'boolean]
      [(fixnum? v)     'fixnum]
      [(flonum? v)     'flonum]
      [(integer? v)    'integer]
      [(number? v)     'number]
      [(string? v)     'string]
      [(char? v)       'char]
      [(symbol? v)     'symbol]
      [(pair? v)       'pair]
      [(null? v)       'null]
      [(vector? v)     'vector]
      [(bytevector? v) 'bytevector]
      [(procedure? v)  'procedure]
      [(hashtable? v)  'hashtable]
      [else            'unknown]))

  ;; ========== define-class ==========
  ;;
  ;; (define-class ClassName (method arg ...) ...)
  ;; Registers the class in *class-registry* with an empty instance table.

  (define-syntax define-class
    (lambda (stx)
      (syntax-case stx ()
        [(_ ClassName (method-name arg ...) ...)
         (let ([class-sym (syntax->datum #'ClassName)])
           (with-syntax ([csym (datum->syntax #'ClassName class-sym)]
                         [(msym ...) (map (lambda (m)
                                            (datum->syntax m (syntax->datum m)))
                                          (syntax->list #'(method-name ...)))])
             #'(begin
                 (define ClassName
                   (let ([cd (make-class-descriptor 'csym '(msym ...))])
                     (hashtable-set! *class-registry* 'csym cd)
                     cd))
                 (void))))])))

  ;; ========== define-instance ==========
  ;;
  ;; (define-instance ClassName type-tag
  ;;   (method-name impl) ...)
  ;;
  ;; Registers an instance: creates an eq-hashtable mapping each
  ;; method-name to its implementation, then stores it under type-tag
  ;; in the class's instances table.

  (define-syntax define-instance
    (lambda (stx)
      (syntax-case stx ()
        [(_ ClassName type-tag (method-name impl) ...)
         (let ([class-sym (syntax->datum #'ClassName)]
               [type-sym  (syntax->datum #'type-tag)])
           (with-syntax ([csym (datum->syntax #'ClassName class-sym)]
                         [tsym (datum->syntax #'type-tag type-sym)]
                         [(msym ...) (map (lambda (m)
                                            (datum->syntax m (syntax->datum m)))
                                          (syntax->list #'(method-name ...)))])
             #'(let* ([cd  (or (hashtable-ref *class-registry* 'csym #f)
                               (error 'define-instance "unknown class" 'csym))]
                      [inst (make-eq-hashtable)])
                 (begin
                   (hashtable-set! inst 'msym impl) ...)
                 (hashtable-set! (class-descriptor-instances cd) 'tsym inst))))])))

  ;; ========== class-dispatch ==========
  ;;
  ;; Runtime helper: look up and call a class method by name.
  ;; Used by with-class.

  (define (class-dispatch class-sym method-sym first-arg . rest-args)
    (let* ([cd   (or (hashtable-ref *class-registry* class-sym #f)
                     (error 'class-dispatch "unknown class" class-sym))]
           [tag  (infer-type-tag first-arg)]
           [inst (or (hashtable-ref (class-descriptor-instances cd) tag #f)
                     (error 'class-dispatch "no instance for type" tag class-sym))]
           [proc (or (hashtable-ref inst method-sym #f)
                     (error 'class-dispatch "method not found" method-sym class-sym))])
      (apply proc first-arg rest-args)))

  ;; ========== with-class ==========
  ;;
  ;; (with-class ClassName body ...)
  ;;
  ;; Introduces a local dispatch binding so callers can write:
  ;;   (ClassName method-name arg ...)
  ;; which expands to a runtime lookup through class-dispatch.
  ;;
  ;; This is implemented as a local macro that rewrites
  ;;   (ClassName meth first-arg rest ...)
  ;; to
  ;;   (class-dispatch 'ClassName 'meth first-arg rest ...)

  (define-syntax with-class
    (lambda (stx)
      (syntax-case stx ()
        [(_ ClassName body ...)
         (let ([class-sym (syntax->datum #'ClassName)])
           (with-syntax ([csym (datum->syntax #'ClassName class-sym)])
             ;; Use a fluid-let style trick: rebind ClassName locally as syntax.
             ;; We cannot nest define-syntax with live ellipsis easily, so we
             ;; generate the dispatch call directly.
             ;;
             ;; Strategy: transform each (ClassName m arg ...) in body via
             ;; a let-syntax that captures the class name as a datum.
             #'(let-syntax ([ClassName
                              (lambda (s)
                                (syntax-case s ()
                                  [(_ mname fst rest (... ...))
                                   #'(class-dispatch 'csym 'mname fst rest (... ...))]))])
                 body ...)))])))

  ) ; end library
