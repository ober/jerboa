#!chezscheme
;;; (std typed) — Gradual typing for Chez Scheme
;;;
;;; Optional type annotations that compile to assertions in debug mode
;;; and strip in release mode. Zero overhead when disabled.
;;;
;;; API:
;;;   (define/t (name [arg : type] ...) : ret-type body ...)
;;;   (lambda/t ([arg : type] ...) : ret-type body ...)
;;;   (assert-type expr type)  — inline assertion
;;;   (*typed-mode* 'debug)   — emit assertions (default)
;;;   (*typed-mode* 'release) — strip assertions
;;;   (*typed-mode* 'none)    — same as release

(library (std typed)
  (export define/t lambda/t assert-type
          *typed-mode*
          register-type-predicate!
          type-predicate)
  (import (chezscheme))

  ;; ========== Configuration ==========

  (define *typed-mode*
    (make-parameter 'debug
      (lambda (v)
        (unless (memq v '(debug release none))
          (error '*typed-mode* "must be debug, release, or none" v))
        v)))

  ;; ========== Type → Predicate Mapping ==========

  (define *type-predicates*
    (let ([ht (make-hashtable symbol-hash eq?)])
      (hashtable-set! ht 'fixnum fixnum?)
      (hashtable-set! ht 'flonum flonum?)
      (hashtable-set! ht 'string string?)
      (hashtable-set! ht 'pair pair?)
      (hashtable-set! ht 'vector vector?)
      (hashtable-set! ht 'bytevector bytevector?)
      (hashtable-set! ht 'boolean boolean?)
      (hashtable-set! ht 'char char?)
      (hashtable-set! ht 'symbol symbol?)
      (hashtable-set! ht 'list list?)
      (hashtable-set! ht 'number number?)
      (hashtable-set! ht 'integer integer?)
      (hashtable-set! ht 'real real?)
      (hashtable-set! ht 'any (lambda (x) #t))
      ht))

  (define (register-type-predicate! type-name pred)
    (hashtable-set! *type-predicates* type-name pred))

  (define (type-predicate type-name)
    (hashtable-ref *type-predicates* type-name #f))

  ;; ========== Runtime Type Checking ==========

  (define (check-type! who arg-name val type-name)
    (when (eq? (*typed-mode*) 'debug)
      (let ([pred (type-predicate type-name)])
        (when (and pred (not (eq? type-name 'any)))
          (unless (pred val)
            (error who
              (format "~a: expected ~a, got ~a" arg-name type-name val)
              val))))))

  (define (check-return-type! who val type-name)
    (when (eq? (*typed-mode*) 'debug)
      (let ([pred (type-predicate type-name)])
        (when (and pred (not (eq? type-name 'any)))
          (unless (pred val)
            (error who
              (format "return value: expected ~a, got ~a" type-name val)
              val))))))

  ;; ========== assert-type ==========

  (define-syntax assert-type
    (syntax-rules ()
      [(_ expr type-name)
       (let ([v expr])
         (check-type! 'assert-type 'expr v 'type-name)
         v)]))

  ;; ========== define/t ==========
  ;;
  ;; (define/t (name [arg : type] ...) : ret-type body ...)
  ;; (define/t (name [arg : type] ...) body ...)

  (define-syntax define/t
    (lambda (stx)
      (define (parse-typed-args args)
        (let loop ([rest (syntax->list args)] [result '()])
          (if (null? rest)
            (reverse result)
            (let ([item (car rest)])
              (syntax-case item ()
                [(arg-name sep type-name)
                 (eq? (syntax->datum #'sep) ':)
                 (loop (cdr rest)
                       (cons (list #'arg-name #'type-name) result))]
                [arg-name
                 (identifier? #'arg-name)
                 (loop (cdr rest)
                       (cons (list #'arg-name (datum->syntax #'arg-name 'any)) result))])))))
      (syntax-case stx ()
        ;; With return type
        [(k (name typed-arg ...) colon ret-type body ...)
         (eq? (syntax->datum #'colon) ':)
         (let ([parsed (parse-typed-args #'(typed-arg ...))])
           (with-syntax ([(arg ...) (map car parsed)]
                         [((aname atype) ...) parsed])
             #'(define (name arg ...)
                 (check-type! 'name 'aname arg 'atype) ...
                 (let ([result (begin body ...)])
                   (check-return-type! 'name result 'ret-type)
                   result))))]
        ;; Without return type
        [(k (name typed-arg ...) body ...)
         (let ([parsed (parse-typed-args #'(typed-arg ...))])
           (with-syntax ([(arg ...) (map car parsed)]
                         [((aname atype) ...) parsed])
             #'(define (name arg ...)
                 (check-type! 'name 'aname arg 'atype) ...
                 body ...)))])))

  ;; ========== lambda/t ==========

  (define-syntax lambda/t
    (lambda (stx)
      (define (parse-typed-args args)
        (let loop ([rest (syntax->list args)] [result '()])
          (if (null? rest)
            (reverse result)
            (let ([item (car rest)])
              (syntax-case item ()
                [(arg-name sep type-name)
                 (eq? (syntax->datum #'sep) ':)
                 (loop (cdr rest)
                       (cons (list #'arg-name #'type-name) result))]
                [arg-name
                 (identifier? #'arg-name)
                 (loop (cdr rest)
                       (cons (list #'arg-name (datum->syntax #'arg-name 'any)) result))])))))
      (syntax-case stx ()
        ;; With return type
        [(k (typed-arg ...) colon ret-type body ...)
         (eq? (syntax->datum #'colon) ':)
         (let ([parsed (parse-typed-args #'(typed-arg ...))])
           (with-syntax ([(arg ...) (map car parsed)]
                         [((aname atype) ...) parsed])
             #'(lambda (arg ...)
                 (check-type! 'lambda 'aname arg 'atype) ...
                 (let ([result (begin body ...)])
                   (check-return-type! 'lambda result 'ret-type)
                   result))))]
        ;; Without return type
        [(k (typed-arg ...) body ...)
         (let ([parsed (parse-typed-args #'(typed-arg ...))])
           (with-syntax ([(arg ...) (map car parsed)]
                         [((aname atype) ...) parsed])
             #'(lambda (arg ...)
                 (check-type! 'lambda 'aname arg 'atype) ...
                 body ...)))])))

  ) ;; end library
