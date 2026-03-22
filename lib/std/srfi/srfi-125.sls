#!chezscheme
;;; :std/srfi/125 -- SRFI-125 Intermediate Hash Tables
;;; Wraps Chez Scheme's native hashtable operations with SRFI-125 names.

(library (std srfi srfi-125)
  (export
    make-hash-table hash-table hash-table?
    hash-table-ref hash-table-ref/default
    hash-table-set! hash-table-delete! hash-table-contains?
    hash-table-size
    hash-table-keys hash-table-values hash-table-entries
    hash-table-update! hash-table-update!/default
    hash-table-fold hash-table-for-each
    hash-table-map hash-table-map->list
    hash-table-copy
    hash-table->alist alist->hash-table)

  (import (except (chezscheme)
            make-hash-table hash-table? hash-table-for-each hash-table-map))

  ;; make-hash-table: accepts equality predicate and optional hash function
  ;; (make-hash-table equal-proc hash-proc)
  ;; (make-hash-table equal-proc hash-proc capacity)
  ;; (make-hash-table) defaults to equal?/equal-hash
  (define make-hash-table
    (case-lambda
      [() (make-hashtable equal-hash equal?)]
      [(equiv) (make-hashtable (default-hash-for equiv) equiv)]
      [(equiv hash) (make-hashtable hash equiv)]
      [(equiv hash capacity) (make-hashtable hash equiv capacity)]))

  ;; Pick a default hash for well-known equality predicates
  (define (default-hash-for equiv)
    (cond
      [(eq? equiv equal?) equal-hash]
      [(eq? equiv string=?) string-hash]
      [(eq? equiv symbol=?) symbol-hash]
      [(eq? equiv eq?) equal-hash]
      [(eq? equiv eqv?) equal-hash]
      [else equal-hash]))

  ;; hash-table: create and populate
  ;; (hash-table equiv key1 val1 key2 val2 ...)
  (define (hash-table equiv . kvs)
    (let ([ht (make-hash-table equiv)])
      (let loop ([rest kvs])
        (unless (null? rest)
          (when (null? (cdr rest))
            (error 'hash-table "odd number of arguments" kvs))
          (hashtable-set! ht (car rest) (cadr rest))
          (loop (cddr rest))))
      ht))

  (define hash-table? hashtable?)

  ;; hash-table-ref: (hash-table-ref ht key) or (hash-table-ref ht key failure)
  (define hash-table-ref
    (case-lambda
      [(ht key)
       (let ([v (hashtable-ref ht key (void))])
         (if (eq? v (void))
           (error 'hash-table-ref "key not found" key)
           v))]
      [(ht key failure)
       (let ([v (hashtable-ref ht key (void))])
         (if (eq? v (void))
           (if (procedure? failure) (failure) failure)
           v))]))

  (define (hash-table-ref/default ht key default)
    (hashtable-ref ht key default))

  (define hash-table-set!
    (case-lambda
      [(ht key val) (hashtable-set! ht key val)]
      [(ht . kvs)
       (let loop ([rest kvs])
         (unless (null? rest)
           (hashtable-set! ht (car rest) (cadr rest))
           (loop (cddr rest))))]))

  (define hash-table-delete!
    (case-lambda
      [(ht key) (hashtable-delete! ht key)]
      [(ht . keys)
       (for-each (lambda (k) (hashtable-delete! ht k)) keys)]))

  (define (hash-table-contains? ht key)
    (hashtable-contains? ht key))

  (define (hash-table-size ht)
    (hashtable-size ht))

  (define (hash-table-keys ht)
    (vector->list (hashtable-keys ht)))

  (define (hash-table-values ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (vector->list vals)))

  (define (hash-table-entries ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (values (vector->list keys) (vector->list vals))))

  ;; hash-table-update!: (hash-table-update! ht key updater)
  ;; or (hash-table-update! ht key updater failure)
  (define hash-table-update!
    (case-lambda
      [(ht key updater)
       (hashtable-update! ht key updater (void))]
      [(ht key updater failure)
       (let ([v (hashtable-ref ht key (void))])
         (if (eq? v (void))
           (hashtable-set! ht key (updater (if (procedure? failure) (failure) failure)))
           (hashtable-set! ht key (updater v))))]))

  (define (hash-table-update!/default ht key updater default)
    (hashtable-update! ht key updater default))

  ;; hash-table-fold: (hash-table-fold ht proc init)
  ;; proc receives (key value accumulator)
  (define (hash-table-fold ht proc init)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let ([len (vector-length keys)])
        (let loop ([i 0] [acc init])
          (if (= i len) acc
            (loop (+ i 1)
                  (proc (vector-ref keys i) (vector-ref vals i) acc)))))))

  ;; hash-table-for-each: (hash-table-for-each ht proc)
  ;; proc receives (key value)
  (define (hash-table-for-each ht proc)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let ([len (vector-length keys)])
        (let loop ([i 0])
          (unless (= i len)
            (proc (vector-ref keys i) (vector-ref vals i))
            (loop (+ i 1)))))))

  ;; hash-table-map: (hash-table-map ht proc)
  ;; Returns a new hash table with same keys but values mapped by proc
  (define (hash-table-map ht proc)
    (let ([result (make-hashtable
                    (hashtable-hash-function ht)
                    (hashtable-equivalence-function ht))])
      (let-values ([(keys vals) (hashtable-entries ht)])
        (let ([len (vector-length keys)])
          (let loop ([i 0])
            (unless (= i len)
              (hashtable-set! result
                (vector-ref keys i)
                (proc (vector-ref keys i) (vector-ref vals i)))
              (loop (+ i 1))))))
      result))

  ;; hash-table-map->list: (hash-table-map->list ht proc)
  ;; Apply proc to each key/value pair, collect results in a list
  (define (hash-table-map->list ht proc)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let ([len (vector-length keys)])
        (let loop ([i (- len 1)] [acc '()])
          (if (< i 0) acc
            (loop (- i 1)
                  (cons (proc (vector-ref keys i) (vector-ref vals i))
                        acc)))))))

  (define hash-table-copy
    (case-lambda
      [(ht) (hashtable-copy ht #t)]
      [(ht mutable?) (hashtable-copy ht mutable?)]))

  (define (hash-table->alist ht)
    (hash-table-map->list ht cons))

  (define alist->hash-table
    (case-lambda
      [(alist) (alist->hash-table alist equal?)]
      [(alist equiv) (alist->hash-table alist equiv (default-hash-for equiv))]
      [(alist equiv hash)
       (let ([ht (make-hashtable hash equiv)])
         (for-each (lambda (pair)
                     (unless (hashtable-contains? ht (car pair))
                       (hashtable-set! ht (car pair) (cdr pair))))
                   alist)
         ht)]))

) ;; end library
