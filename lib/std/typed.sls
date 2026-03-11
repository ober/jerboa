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
          type-predicate
          ;; Phase 3: op specialization
          with-fixnum-ops with-flonum-ops)
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

  ;; Look up or construct a predicate for a type spec.
  ;; Handles:
  ;;   symbol          — direct lookup in *type-predicates*
  ;;   (listof T)      — list whose elements satisfy T
  ;;   (vectorof T)    — vector whose elements satisfy T
  ;;   (hashof K V)    — hashtable? (key/value types not checked at runtime)
  ;;   (-> A ... B)    — procedure?
  (define (type-predicate spec)
    (cond
      [(symbol? spec)
       (hashtable-ref *type-predicates* spec #f)]
      [(and (pair? spec) (eq? (car spec) 'listof) (= (length spec) 2))
       (let ([elem-pred (type-predicate (cadr spec))])
         (if elem-pred
           (lambda (x)
             (and (list? x) (for-all elem-pred x)))
           list?))]
      [(and (pair? spec) (eq? (car spec) 'vectorof) (= (length spec) 2))
       (let ([elem-pred (type-predicate (cadr spec))])
         (if elem-pred
           (lambda (x)
             (and (vector? x)
                  (let loop ([i 0])
                    (or (= i (vector-length x))
                        (and (elem-pred (vector-ref x i))
                             (loop (+ i 1)))))))
           vector?))]
      [(and (pair? spec) (eq? (car spec) 'hashof) (= (length spec) 3))
       ;; Runtime check is just "is it a hashtable?"; key/value types not verified per-entry
       hashtable?]
      [(and (pair? spec) (eq? (car spec) '->) (>= (length spec) 2))
       ;; Function type — just verify it's a procedure
       procedure?]
      [else #f]))

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

  ;; ========== Phase 3: Op Specialization ==========
  ;;
  ;; (with-fixnum-ops body ...)
  ;;   Recursively replaces generic arithmetic operators in body with fixnum
  ;;   variants: + → fx+, - → fx-, * → fx*, < → fx<, etc.
  ;;   The programmer takes responsibility for ensuring the values are fixnums.
  ;;   This allows Chez's cp0/cptypes to see the specialized ops directly.
  ;;
  ;; (with-flonum-ops body ...)
  ;;   Like with-fixnum-ops but replaces + → fl+, - → fl-, * → fl*, / → fl/, etc.

  ;; ========== Phase 3: Op Specialization ==========
  ;;
  ;; (with-fixnum-ops body ...)
  ;;   Recursively replaces generic arithmetic operators in body with fixnum
  ;;   variants: + → fx+, - → fx-, * → fx*, < → fx<, etc.
  ;;   The programmer takes responsibility for ensuring the values are fixnums.
  ;;   This allows Chez's cp0/cptypes to see the specialized ops directly.
  ;;
  ;; (with-flonum-ops body ...)
  ;;   Like with-fixnum-ops but replaces + → fl+, - → fl-, * → fl*, / → fl/, etc.

  (define-syntax with-fixnum-ops
    (lambda (stx)
      ;; Map of generic op → fixnum op (both as symbols)
      (define fx-map
        '((+          . fx+)
          (-          . fx-)
          (*          . fx*)
          (<          . fx<)
          (>          . fx>)
          (<=         . fx<=)
          (>=         . fx>=)
          (=          . fx=)
          (quotient   . fxquotient)
          (remainder  . fxremainder)
          (modulo     . fxmodulo)
          (abs        . fxabs)
          (zero?      . fxzero?)
          (positive?  . fxpositive?)
          (negative?  . fxnegative?)
          (min        . fxmin)
          (max        . fxmax)
          (add1       . fx1+)
          (sub1       . fx1-)))
      ;; Special forms whose head must not be transformed
      (define special-heads
        '(quote if begin let let* letrec letrec* cond case when unless
          and or lambda define set! do guard
          with-syntax define-syntax let-syntax letrec-syntax
          syntax-rules define-record-type library import export))
      (define (transform datum)
        (cond
          [(pair? datum)
           (let ([head (car datum)])
             (cond
               ;; Special forms: preserve head, recurse into subforms
               [(memq head special-heads)
                (cons head (map transform (cdr datum)))]
               ;; Known arithmetic op: replace with fixnum version
               [(assq head fx-map) =>
                (lambda (pair) (cons (cdr pair) (map transform (cdr datum))))]
               ;; Other applications: recurse everywhere
               [else (map transform datum)]))]
          [else datum]))
      (syntax-case stx ()
        [(kw body ...)
         (let ([transformed (map (lambda (b) (transform (syntax->datum b)))
                                 (syntax->list #'(body ...)))])
           (datum->syntax #'kw `(begin ,@transformed)))])))

  (define-syntax with-flonum-ops
    (lambda (stx)
      (define fl-map
        '((+          . fl+)
          (-          . fl-)
          (*          . fl*)
          (/          . fl/)
          (<          . fl<)
          (>          . fl>)
          (<=         . fl<=)
          (>=         . fl>=)
          (=          . fl=)
          (abs        . flabs)
          (sqrt       . flsqrt)
          (floor      . flfloor)
          (ceiling    . flceiling)
          (round      . flround)
          (truncate   . fltruncate)
          (sin        . flsin)
          (cos        . flcos)
          (tan        . fltan)
          (exp        . flexp)
          (log        . fllog)
          (zero?      . flzero?)
          (positive?  . flpositive?)
          (negative?  . flnegative?)
          (min        . flmin)
          (max        . flmax)))
      (define special-heads
        '(quote if begin let let* letrec letrec* cond case when unless
          and or lambda define set! do guard
          with-syntax define-syntax let-syntax letrec-syntax
          syntax-rules define-record-type library import export))
      (define (transform datum)
        (cond
          [(pair? datum)
           (let ([head (car datum)])
             (cond
               [(memq head special-heads)
                (cons head (map transform (cdr datum)))]
               [(assq head fl-map) =>
                (lambda (pair) (cons (cdr pair) (map transform (cdr datum))))]
               [else (map transform datum)]))]
          [else datum]))
      (syntax-case stx ()
        [(kw body ...)
         (let ([transformed (map (lambda (b) (transform (syntax->datum b)))
                                 (syntax->list #'(body ...)))])
           (datum->syntax #'kw `(begin ,@transformed)))])))

  ) ;; end library
