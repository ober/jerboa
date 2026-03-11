#!chezscheme
;;; (std typed hkt) — Higher-Kinded Types (HKT)
;;;
;;; Provides type classes that abstract over type constructors (f :: * -> *).
;;; Instances are registered by a type-constructor tag (a symbol like 'Option).
;;;
;;; API:
;;;   (defprotocol-hkt Name (method arg ...) ...)  — define an HKT class
;;;   (implement-hkt Name tag (method impl) ...)   — register an instance
;;;   (hkt-instance Name tag)                      — look up instance or #f
;;;   (hkt-instance? Name tag)                     — predicate
;;;
;;;   Built-in classes: Functor Applicative Monad Foldable Traversable
;;;   do/m macro for monadic do-notation
;;;
;;;   Option type: make-Some make-None Some? None? Some-val
;;;     option-fmap option-bind option-return
;;;   Result type: make-Ok make-Err Ok? Err? Ok-val Err-val
;;;     result-fmap result-bind result-return

(library (std typed hkt)
  (export
    ;; Protocol / instance machinery
    defprotocol-hkt
    implement-hkt
    hkt-instance
    hkt-instance?
    hkt-dispatch

    ;; Built-in HKT classes
    Functor
    Applicative
    Monad
    Foldable
    Traversable

    ;; do/m notation
    do/m

    ;; Option type
    make-Some
    make-None
    Some?
    None?
    Some-val
    option-fmap
    option-bind
    option-return

    ;; Result type
    make-Ok
    make-Err
    Ok?
    Err?
    Ok-val
    Err-val
    result-fmap
    result-bind
    result-return)

  (import (chezscheme))

  ;; ========== HKT Registry ==========
  ;;
  ;; *hkt-registry* : class-name-sym -> class-descriptor
  ;; class-descriptor: vector of (name methods instances-hashtable)

  (define *hkt-registry* (make-eq-hashtable))

  (define (make-hkt-class-descriptor name methods)
    (vector 'hkt-class name methods (make-eq-hashtable)))

  (define (hkt-class-descriptor? v)
    (and (vector? v) (= (vector-length v) 4) (eq? (vector-ref v 0) 'hkt-class)))

  (define (hkt-cd-name cd)      (vector-ref cd 1))
  (define (hkt-cd-methods cd)   (vector-ref cd 2))
  (define (hkt-cd-instances cd) (vector-ref cd 3))

  ;; ========== Instance lookup ==========

  (define (hkt-instance class-name type-tag)
    (let ([cd (hashtable-ref *hkt-registry* class-name #f)])
      (if cd
        (hashtable-ref (hkt-cd-instances cd) type-tag #f)
        #f)))

  (define (hkt-instance? class-name type-tag)
    (and (hkt-instance class-name type-tag) #t))

  ;; ========== defprotocol-hkt ==========
  ;;
  ;; (defprotocol-hkt Name (method arg ...) ...)
  ;; Registers the HKT class in *hkt-registry*.

  (define-syntax defprotocol-hkt
    (lambda (stx)
      (syntax-case stx ()
        [(_ ClassName (method-name arg ...) ...)
         (let ([class-sym (syntax->datum #'ClassName)])
           (with-syntax ([csym (datum->syntax #'ClassName class-sym)]
                         [(msym ...) (map (lambda (m)
                                            (datum->syntax m (syntax->datum m)))
                                          (syntax->list #'(method-name ...)))])
             #'(define ClassName
                 (let ([cd (make-hkt-class-descriptor 'csym '(msym ...))])
                   (hashtable-set! *hkt-registry* 'csym cd)
                   cd))))])))

  ;; ========== implement-hkt ==========
  ;;
  ;; (implement-hkt ClassName type-tag (method-name impl) ...)
  ;; Registers an instance for a given type constructor tag.

  (define-syntax implement-hkt
    (lambda (stx)
      (syntax-case stx ()
        [(_ ClassName type-tag (method-name impl) ...)
         (let ([class-sym (syntax->datum #'ClassName)]
               [type-sym  (syntax->datum #'type-tag)])
           (with-syntax ([csym (datum->syntax #'ClassName class-sym)]
                         [tsym (datum->syntax #'type-tag type-sym)]
                         [reg-var (datum->syntax #'ClassName
                                    (string->symbol
                                      (string-append "%hkt-instance-"
                                        (symbol->string class-sym) "-"
                                        (symbol->string type-sym) "%")))]
                         [(msym ...) (map (lambda (m)
                                            (datum->syntax m (syntax->datum m)))
                                          (syntax->list #'(method-name ...)))])
             ;; Expand to a define so we stay in definition context
             #'(define reg-var
                 (let* ([cd   (or (hashtable-ref *hkt-registry* 'csym #f)
                                 (error 'implement-hkt "unknown HKT class" 'csym))]
                        [inst (make-eq-hashtable)])
                   (hashtable-set! inst 'msym impl) ...
                   (hashtable-set! (hkt-cd-instances cd) 'tsym inst)
                   inst))))])))

  ;; ========== HKT method dispatch ==========

  (define (hkt-dispatch class-sym method-sym type-tag . args)
    (let* ([cd   (or (hashtable-ref *hkt-registry* class-sym #f)
                     (error 'hkt-dispatch "unknown HKT class" class-sym))]
           [inst (or (hashtable-ref (hkt-cd-instances cd) type-tag #f)
                     (error 'hkt-dispatch "no instance for type tag" type-tag class-sym))]
           [proc (or (hashtable-ref inst method-sym #f)
                     (error 'hkt-dispatch "method not found" method-sym class-sym))])
      (apply proc args)))

  ;; ========== Built-in HKT Classes ==========

  (defprotocol-hkt Functor
    (fmap f fa))

  (defprotocol-hkt Applicative
    (pure a)
    (ap ff fa))

  (defprotocol-hkt Monad
    (bind ma f)
    (return a))

  (defprotocol-hkt Foldable
    (fold-hkt f init fa))

  (defprotocol-hkt Traversable
    (traverse f fa))

  ;; ========== Option type ==========
  ;;
  ;; Option is represented as a tagged vector:
  ;;   (Some v)  → #(option-some v)
  ;;   None      → #(option-none)

  (define (make-Some val)
    (vector 'option-some val))

  (define (make-None)
    (vector 'option-none))

  (define (Some? v)
    (and (vector? v)
         (= (vector-length v) 2)
         (eq? (vector-ref v 0) 'option-some)))

  (define (None? v)
    (and (vector? v)
         (= (vector-length v) 1)
         (eq? (vector-ref v 0) 'option-none)))

  (define (Some-val v)
    (if (Some? v)
      (vector-ref v 1)
      (error 'Some-val "not a Some value" v)))

  ;; Option functor/monad primitives
  (define (option-fmap f opt)
    (if (Some? opt)
      (make-Some (f (Some-val opt)))
      opt))

  (define (option-bind opt f)
    (if (Some? opt)
      (f (Some-val opt))
      opt))

  (define (option-return v)
    (make-Some v))

  ;; ========== Result type ==========
  ;;
  ;; Result is a tagged vector:
  ;;   (Ok v)  → #(result-ok v)
  ;;   (Err e) → #(result-err e)

  (define (make-Ok val)
    (vector 'result-ok val))

  (define (make-Err val)
    (vector 'result-err val))

  (define (Ok? v)
    (and (vector? v)
         (= (vector-length v) 2)
         (eq? (vector-ref v 0) 'result-ok)))

  (define (Err? v)
    (and (vector? v)
         (= (vector-length v) 2)
         (eq? (vector-ref v 0) 'result-err)))

  (define (Ok-val v)
    (if (Ok? v)
      (vector-ref v 1)
      (error 'Ok-val "not an Ok value" v)))

  (define (Err-val v)
    (if (Err? v)
      (vector-ref v 1)
      (error 'Err-val "not an Err value" v)))

  ;; Result functor/monad primitives
  (define (result-fmap f r)
    (if (Ok? r)
      (make-Ok (f (Ok-val r)))
      r))

  (define (result-bind r f)
    (if (Ok? r)
      (f (Ok-val r))
      r))

  (define (result-return v)
    (make-Ok v))

  ;; ========== Register built-in instances ==========

  ;; Functor instances
  (implement-hkt Functor Option
    (fmap (lambda (f fa) (option-fmap f fa))))

  (implement-hkt Functor List
    (fmap (lambda (f fa) (map f fa))))

  (implement-hkt Functor Result
    (fmap (lambda (f fa) (result-fmap f fa))))

  ;; Monad instances
  (implement-hkt Monad Option
    (bind   (lambda (ma f) (option-bind ma f)))
    (return (lambda (a)    (option-return a))))

  (implement-hkt Monad List
    (bind   (lambda (ma f) (apply append (map f ma))))
    (return (lambda (a)    (list a))))

  (implement-hkt Monad Result
    (bind   (lambda (ma f) (result-bind ma f)))
    (return (lambda (a)    (result-return a))))

  ;; Applicative instances
  (implement-hkt Applicative Option
    (pure (lambda (a) (option-return a)))
    (ap   (lambda (ff fa)
            (if (and (Some? ff) (Some? fa))
              (make-Some ((Some-val ff) (Some-val fa)))
              (make-None)))))

  (implement-hkt Applicative List
    (pure (lambda (a) (list a)))
    (ap   (lambda (ff fa)
            (apply append
              (map (lambda (f) (map f fa)) ff)))))

  ;; Foldable instances
  (implement-hkt Foldable Option
    (fold-hkt (lambda (f init fa)
                (if (Some? fa)
                  (f init (Some-val fa))
                  init))))

  (implement-hkt Foldable List
    (fold-hkt (lambda (f init fa)
                (fold-left f init fa))))

  ;; Traversable instance for Option
  (implement-hkt Traversable Option
    (traverse (lambda (f fa)
                (if (Some? fa)
                  (option-fmap make-Some (f (Some-val fa)))
                  (make-Some (make-None))))))

  ;; ========== do/m notation ==========
  ;;
  ;; (do/m type-tag
  ;;   [x <- mx]       — bind mx to x
  ;;   [_ <- mx]       — sequence (discard)
  ;;   [let x = expr]  — pure binding
  ;;   body)           — final expression (wrapped in return)
  ;;
  ;; Desugars using (hkt-dispatch 'Monad 'bind tag ...) and
  ;; (hkt-dispatch 'Monad 'return tag ...).

  (define-syntax do/m
    (lambda (stx)
      (syntax-case stx ()
        ;; Base case: single expression — just evaluate it
        [(_ tag body)
         #'body]

        ;; Bind: [x <- mx] rest...
        [(_ tag [x <- mx] rest ...)
         (identifier? #'x)
         #'(hkt-dispatch 'Monad 'bind 'tag mx
             (lambda (x) (do/m tag rest ...)))]

        ;; Sequence with _ (discard result)
        [(_ tag [_ <- mx] rest ...)
         #'(hkt-dispatch 'Monad 'bind 'tag mx
             (lambda (_ignored) (do/m tag rest ...)))]

        ;; Pure let binding: [let x = expr]
        [(_ tag [let x = expr] rest ...)
         (identifier? #'x)
         #'(let ([x expr]) (do/m tag rest ...))]

        ;; Side-effecting expression (no binding): [mx]
        [(_ tag [mx] rest ...)
         #'(hkt-dispatch 'Monad 'bind 'tag mx
             (lambda (_ignored) (do/m tag rest ...)))])))

) ; end library
