#!chezscheme
;;; (std misc typeclass) — Haskell-style typeclasses via dictionary-passing
;;;
;;; (define-typeclass (Eq a)
;;;   (eq? a a -> boolean))
;;;
;;; (define-instance (Eq number)
;;;   (eq? =))
;;;
;;; (tc-apply 'Eq 'eq? 'number 1 2) => #f
;;; (tc-apply 'Show '->string 'number 42) => "42"

(library (std misc typeclass)
  (export define-typeclass define-instance
          typeclass-dispatch tc-apply tc-ref
          typeclass-instance? typeclass-instance-of?
          lookup-instance lookup-typeclass
          register-typeclass! register-instance!
          build-instance-dict)
  (import (chezscheme))

  ;; ---------------------------------------------------------------
  ;; Global dispatch table: (class-name . type-name) -> dictionary
  ;; ---------------------------------------------------------------
  (define *instance-table* (make-hashtable equal-hash equal?))

  (define (register-instance! class-name type-name dict)
    (hashtable-set! *instance-table* (cons class-name type-name) dict))

  (define (lookup-instance class-name type-name)
    (hashtable-ref *instance-table* (cons class-name type-name) #f))

  ;; ---------------------------------------------------------------
  ;; Typeclass metadata
  ;; ---------------------------------------------------------------
  (define-record-type typeclass-meta
    (fields name method-names superclasses))

  (define *typeclass-registry* (make-hashtable symbol-hash symbol=?))

  (define (register-typeclass! name method-names supers)
    (hashtable-set! *typeclass-registry* name
                    (make-typeclass-meta name method-names supers)))

  (define (lookup-typeclass name)
    (hashtable-ref *typeclass-registry* name #f))

  ;; ---------------------------------------------------------------
  ;; Predicates
  ;; ---------------------------------------------------------------
  (define (typeclass-instance? class-name type-name)
    (and (lookup-instance class-name type-name) #t))

  (define (typeclass-instance-of? class-name type-name)
    (typeclass-instance? class-name type-name))

  ;; ---------------------------------------------------------------
  ;; Dispatch
  ;; ---------------------------------------------------------------
  (define (typeclass-dispatch class-name type-name method-name)
    (let ([dict (lookup-instance class-name type-name)])
      (unless dict
        (error 'typeclass-dispatch
               (format "no instance of ~a for type ~a" class-name type-name)))
      (let ([proc (hashtable-ref dict method-name #f)])
        (unless proc
          (error 'typeclass-dispatch
                 (format "no method ~a in ~a instance for ~a"
                         method-name class-name type-name)))
        proc)))

  (define tc-ref typeclass-dispatch)

  (define (tc-apply class-name method-name type-name . args)
    (let ([proc (typeclass-dispatch class-name type-name method-name)])
      (apply proc args)))

  ;; ---------------------------------------------------------------
  ;; build-instance-dict — build a dictionary, inheriting superclass methods
  ;; ---------------------------------------------------------------
  (define (build-instance-dict class-name type-name method-pairs)
    (let ([dict (make-hashtable symbol-hash symbol=?)])
      ;; Copy superclass methods first
      (let ([meta (lookup-typeclass class-name)])
        (when (and meta (not (null? (typeclass-meta-superclasses meta))))
          (for-each
            (lambda (super-name)
              (let ([super-dict (lookup-instance super-name type-name)])
                (when super-dict
                  (let-values ([(keys vals) (hashtable-entries super-dict)])
                    (vector-for-each
                      (lambda (k v) (hashtable-set! dict k v))
                      keys vals)))))
            (typeclass-meta-superclasses meta))))
      ;; Add own methods
      (for-each
        (lambda (pair) (hashtable-set! dict (car pair) (cdr pair)))
        method-pairs)
      dict))

  ;; ---------------------------------------------------------------
  ;; define-typeclass macro
  ;;
  ;; (define-typeclass (Eq a)
  ;;   (eq? a a -> boolean))
  ;;
  ;; (define-typeclass (Ord a) extends (Eq a)
  ;;   (compare a a -> integer) ...)
  ;;
  ;; Expands to a definition to stay in R6RS definition context.
  ;; ---------------------------------------------------------------
  (define-syntax define-typeclass
    (lambda (stx)
      (syntax-case stx (extends)
        [(_ (class-name a) extends (super-name a2) (method-name . sig) ...)
         #'(define class-name
             (begin
               (register-typeclass! 'class-name '(method-name ...) '(super-name))
               'class-name))]
        [(_ (class-name a) (method-name . sig) ...)
         #'(define class-name
             (begin
               (register-typeclass! 'class-name '(method-name ...) '())
               'class-name))])))

  ;; ---------------------------------------------------------------
  ;; define-instance macro
  ;;
  ;; (define-instance (Eq number)
  ;;   (eq? =))
  ;;
  ;; Expands to a definition using a generated name.
  ;; ---------------------------------------------------------------
  (define-syntax define-instance
    (lambda (stx)
      (syntax-case stx ()
        [(_ (class-name type-name) (method-name impl) ...)
         (with-syntax ([inst-id (datum->syntax #'class-name (gensym "inst"))])
           #'(define inst-id
               (let ([dict (build-instance-dict
                             'class-name 'type-name
                             (list (cons 'method-name impl) ...))])
                 (register-instance! 'class-name 'type-name dict)
                 dict)))])))

  ;; ---------------------------------------------------------------
  ;; Built-in typeclasses
  ;; ---------------------------------------------------------------

  ;; Eq
  (define-typeclass (Eq a)
    (eq? a a -> boolean))

  ;; Ord (extends Eq)
  (define-typeclass (Ord a) extends (Eq a)
    (compare a a -> integer)
    (lt? a a -> boolean)
    (gt? a a -> boolean)
    (le? a a -> boolean)
    (ge? a a -> boolean))

  ;; Show
  (define-typeclass (Show a)
    (->string a -> string))

  ;; ---------------------------------------------------------------
  ;; Built-in instances
  ;; ---------------------------------------------------------------

  ;; Helpers
  (define (number-compare a b)
    (cond [(< a b) -1] [(> a b) 1] [else 0]))
  (define (string-compare a b)
    (cond [(string<? a b) -1] [(string>? a b) 1] [else 0]))

  ;; Eq
  (define-instance (Eq number)
    (eq? =))
  (define-instance (Eq string)
    (eq? string=?))
  (define-instance (Eq symbol)
    (eq? symbol=?))

  ;; Ord
  (define-instance (Ord number)
    (compare number-compare)
    (lt? <)
    (gt? >)
    (le? <=)
    (ge? >=))
  (define-instance (Ord string)
    (compare string-compare)
    (lt? string<?)
    (gt? string>?)
    (le? string<=?)
    (ge? string>=?))

  ;; Show
  (define-instance (Show number)
    (->string number->string))
  (define-instance (Show string)
    (->string (lambda (s) s)))
  (define-instance (Show symbol)
    (->string symbol->string))

) ;; end library
