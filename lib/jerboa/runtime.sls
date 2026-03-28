#!chezscheme
;;; runtime.sls -- Jerboa runtime library
;;;
;;; Simplified MOP, hash tables, keywords, errors, method dispatch.
;;; All built on Chez records + hashtables. No Gambit compat needed.

(library (jerboa runtime)
  (export
    ;; Method dispatch
    ~ bind-method! call-method
    *method-tables*

    ;; Hash tables (Gerbil API)
    make-hash-table make-hash-table-eq
    hash-ref hash-get hash-put! hash-update! hash-remove!
    hash-key? hash->list hash->plist hash-for-each hash-map hash-fold
    hash-find hash-keys hash-values hash-copy hash-clear!
    hash-merge hash-merge! hash-length
    list->hash-table plist->hash-table
    hash-table?
    hash-eq hash-eq?

    ;; Keywords
    keyword? keyword->string string->keyword make-keyword

    ;; Errors
    error-message error-irritants error-trace
    with-exception-handler raise

    ;; Keyword argument support
    keyword-arg-ref

    ;; Utilities
    displayln
    1+ 1-
    void
    make-list
    iota
    last-pair
    cons*

    ;; Struct runtime support
    struct-type-info
    register-struct-type!
    *struct-types*
    struct-predicate
    struct-field-ref
    struct-field-set!)

  (import (except (chezscheme)
            make-hash-table hash-table?
            iota
            1+ 1-))

  ;;;; ---- Method dispatch ----
  ;; type-descriptor → (symbol → procedure) hashtable
  (define *method-tables* (make-eq-hashtable))

  (define (bind-method! type name proc)
    (let ([table (or (hashtable-ref *method-tables* type #f)
                     (let ([t (make-eq-hashtable)])
                       (hashtable-set! *method-tables* type t)
                       t))])
      (hashtable-set! table name proc)))

  (define (find-method type name)
    (let loop ([t type])
      (and t
           (let ([table (hashtable-ref *method-tables* t #f)])
             (or (and table (hashtable-ref table name #f))
                 (loop (record-type-parent t)))))))

  (define (call-method obj name . args)
    (let ([type (record-rtd obj)])
      (let ([method (find-method type name)])
        (if method
          (apply method obj args)
          (error 'call-method "no method" name (record-type-name type))))))

  ;; ~ is the dispatch operator: (~ obj 'method args...)
  (define (~ obj method-name . args)
    (apply call-method obj method-name args))

  ;;;; ---- Hash tables (Gerbil API on Chez hashtables) ----

  (define *not-found* (gensym "hash-not-found"))

  (define make-hash-table
    (case-lambda
      (() (make-hashtable equal-hash equal?))
      ((n) (make-hashtable equal-hash equal? n))))

  (define make-hash-table-eq
    (case-lambda
      (() (make-eq-hashtable))
      ((n) (make-eq-hashtable n))))

  (define hash-table? hashtable?)

  (define hash-length hashtable-size)

  (define hash-ref
    (case-lambda
      ((ht key) (let ([v (hashtable-ref ht key *not-found*)])
                  (if (eq? v *not-found*)
                    (error 'hash-ref "key not found" key)
                    v)))
      ((ht key default)
       ;; If default is a thunk (procedure), invoke it on missing key.
       (let ([v (hashtable-ref ht key *not-found*)])
         (if (eq? v *not-found*)
           (if (procedure? default) (default) default)
           v)))))

  (define-syntax hash-get
    (syntax-rules ()
      ((_ ht key) (hashtable-ref ht key #f))))

  (define hash-put! hashtable-set!)

  (define hash-update!
    (case-lambda
      ((ht key proc) (hash-update! ht key proc #f))
      ((ht key proc default)
       (let ([v (hashtable-ref ht key *not-found*)])
         (hashtable-set! ht key
           (proc (if (eq? v *not-found*) default v)))))))

  (define hash-remove! hashtable-delete!)

  (define (hash-key? ht key)
    (not (eq? (hashtable-ref ht key *not-found*) *not-found*)))

  (define (hash->list ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let loop ([i 0] [acc '()])
        (if (fx= i (vector-length keys)) acc
          (loop (fx+ i 1)
                (cons (cons (vector-ref keys i) (vector-ref vals i)) acc))))))

  (define (hash->plist ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let loop ([i 0] [acc '()])
        (if (fx= i (vector-length keys)) acc
          (loop (fx+ i 1)
                (cons (vector-ref keys i)
                      (cons (vector-ref vals i) acc)))))))

  (define (hash-for-each proc ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (vector-for-each
        (lambda (k v) (proc k v))
        keys vals)))

  (define (hash-map proc ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let loop ([i 0] [acc '()])
        (if (fx= i (vector-length keys)) acc
          (loop (fx+ i 1)
                (cons (proc (vector-ref keys i) (vector-ref vals i)) acc))))))

  (define (hash-fold proc init ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let loop ([i 0] [acc init])
        (if (fx= i (vector-length keys)) acc
          (loop (fx+ i 1)
                (proc (vector-ref keys i) (vector-ref vals i) acc))))))

  (define (hash-find proc ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let loop ([i 0])
        (cond
          [(fx= i (vector-length keys)) #f]
          [(proc (vector-ref keys i) (vector-ref vals i))
           (cons (vector-ref keys i) (vector-ref vals i))]
          [else (loop (fx+ i 1))]))))

  (define (hash-keys ht) (vector->list (hashtable-keys ht)))
  (define (hash-values ht)
    (let-values ([(_ vals) (hashtable-entries ht)])
      (vector->list vals)))

  (define (hash-copy ht) (hashtable-copy ht #t))

  (define hash-clear!
    (case-lambda
      ((ht) (hashtable-clear! ht))
      ((ht n) (hashtable-clear! ht n))))

  (define (hash-merge ht1 ht2)
    (let ([new (hashtable-copy ht1 #t)])
      (hash-for-each (lambda (k v) (hashtable-set! new k v)) ht2)
      new))

  (define (hash-merge! ht1 ht2)
    (hash-for-each (lambda (k v) (hashtable-set! ht1 k v)) ht2)
    ht1)

  (define (list->hash-table lst)
    (let ([ht (make-hash-table)])
      (for-each (lambda (p) (hashtable-set! ht (car p) (cdr p))) lst)
      ht))

  (define (plist->hash-table lst)
    (let ([ht (make-hash-table)])
      (let lp ([rest lst])
        (cond
          [(null? rest) ht]
          [(null? (cdr rest))
           (error 'plist->hash-table
             "odd number of elements (missing value for last key)"
             (car rest))]
          [else
           (hashtable-set! ht (car rest) (cadr rest))
           (lp (cddr rest))]))))

  ;; hash-eq constructor: (hash-eq (k1 v1) (k2 v2) ...) is a macro in core.sls
  ;; but we need hash-eq? predicate
  (define (hash-eq? ht)
    (eq-hashtable? ht))

  ;; hash-eq as runtime function (make eq hashtable from pairs)
  (define hash-eq
    (case-lambda
      (() (make-eq-hashtable))
      (pairs (let ([ht (make-eq-hashtable)])
               (for-each (lambda (p) (hashtable-set! ht (car p) (cdr p))) pairs)
               ht))))

  ;;;; ---- Keywords ----
  ;; Keywords are symbols prefixed with #: (matching the reader)

  (define (keyword? v)
    (and (symbol? v)
         (let ([s (symbol->string v)])
           (and (fx>= (string-length s) 2)
                (char=? (string-ref s 0) #\#)
                (char=? (string-ref s 1) #\:)))))

  (define (keyword->string kw)
    (let ([s (symbol->string kw)])
      (if (and (fx>= (string-length s) 2)
               (char=? (string-ref s 0) #\#)
               (char=? (string-ref s 1) #\:))
        (substring s 2 (string-length s))
        s)))

  (define (string->keyword s)
    (string->symbol (string-append "#:" s)))

  (define make-keyword string->keyword)

  ;;;; ---- Errors ----

  (define (error-message e)
    (if (message-condition? e)
      (condition-message e)
      (format "~a" e)))

  (define (error-irritants e)
    (if (irritants-condition? e)
      (condition-irritants e)
      '()))

  (define (error-trace e)
    (if (condition? e)
      (format "~a" e)
      ""))

  ;;;; ---- Keyword argument support ----

  (define (keyword-arg-ref kwargs key default)
    ;; Search a flat list (key1: val1 key2: val2 ...) for key, return val or default.
    ;; key is a symbol like 'setter:
    (let loop ([rest kwargs])
      (cond
        [(null? rest) default]
        [(null? (cdr rest))
         ;; Odd-length kwargs list: last key has no value.
         ;; Raise error so callers don't silently lose arguments.
         (error 'keyword-arg-ref
           "odd number of keyword arguments (missing value for last key)"
           (car rest))]
        [(eq? (car rest) key) (cadr rest)]
        [else (loop (cddr rest))])))

  ;;;; ---- Utilities ----

  (define (displayln . args)
    (for-each display args)
    (newline))

  (define (1+ n) (+ n 1))
  (define (1- n) (- n 1))

  ;; make-list, last-pair, cons* are provided by Chez
  ;; iota needs our own version supporting start/step (Chez only has (iota count))
  (define iota
    (case-lambda
      ((n) (iota n 0 1))
      ((n start) (iota n start 1))
      ((n start step)
       (let loop ([i 0] [acc '()])
         (if (fx>= i n) (reverse acc)
           (loop (fx+ i 1) (cons (+ start (* i step)) acc)))))))

  ;;;; ---- Struct runtime support ----
  ;; Registry for struct types (maps record-type-descriptor to metadata)
  (define *struct-types* (make-eq-hashtable))

  (define-record-type struct-info
    (fields name rtd parent-rtd field-names))

  (define (register-struct-type! rtd name parent-rtd field-names)
    (hashtable-set! *struct-types* rtd
      (make-struct-info name rtd parent-rtd field-names)))

  (define (struct-type-info rtd)
    (hashtable-ref *struct-types* rtd #f))

  (define (struct-predicate rtd)
    (record-predicate rtd))

  (define (struct-field-ref rtd field-index)
    (record-accessor rtd field-index))

  (define (struct-field-set! rtd field-index)
    (record-mutator rtd field-index))

  ) ;; end library
