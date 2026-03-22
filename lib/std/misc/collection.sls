#!chezscheme
;;; (std misc collection) — Generic collection protocol
;;;
;;; Decouples algorithms from data structures via iterators.
;;; An iterator is a thunk returning (values elem #t) or (values #f #f).
;;;
;;; (collection->list '(1 2 3))       => (1 2 3)
;;; (collection->list '#(4 5 6))      => (4 5 6)
;;; (collection-fold + 0 '(1 2 3))    => 6
;;; (collection-map add1 '#(1 2 3))   => (2 3 4)

(library (std misc collection)
  (export make-iterator
          define-collection
          collection-fold
          collection-map
          collection-filter
          collection-for-each
          collection-find
          collection-any
          collection-every
          collection->list
          collection-length)
  (import (chezscheme))

  ;; ----- Dispatch table -----
  ;; Each entry is (predicate . iterator-constructor).
  ;; The iterator-constructor takes a collection and returns an iterator thunk.
  ;; We use a list (not a hashtable) because keys are predicates, not hashable values.
  (define *collection-registry* '())

  (define (register-collection! pred make-iter)
    (set! *collection-registry*
      (cons (cons pred make-iter) *collection-registry*)))

  ;; Look up the iterator constructor for a value
  (define (lookup-iterator-constructor coll)
    (let loop ([entries *collection-registry*])
      (cond
        [(null? entries)
         (error 'make-iterator "no iterator registered for value" coll)]
        [((caar entries) coll)
         (cdar entries)]
        [else (loop (cdr entries))])))

  ;; ----- Core: make-iterator -----
  ;; Returns a thunk. Each call returns (values elem #t) or (values #f #f).
  (define (make-iterator coll)
    (let ([make-iter (lookup-iterator-constructor coll)])
      (make-iter coll)))

  ;; ----- Macro: define-collection -----
  (define-syntax define-collection
    (syntax-rules ()
      [(_ pred make-iter)
       (register-collection! pred make-iter)]))

  ;; ----- Built-in iterators -----

  ;; List iterator
  (define (make-list-iterator lst)
    (let ([rest lst])
      (lambda ()
        (if (null? rest)
            (values #f #f)
            (let ([elem (car rest)])
              (set! rest (cdr rest))
              (values elem #t))))))

  ;; Vector iterator
  (define (make-vector-iterator vec)
    (let ([len (vector-length vec)]
          [i 0])
      (lambda ()
        (if (fx>= i len)
            (values #f #f)
            (let ([elem (vector-ref vec i)])
              (set! i (fx+ i 1))
              (values elem #t))))))

  ;; String iterator (iterates over characters)
  (define (make-string-iterator str)
    (let ([len (string-length str)]
          [i 0])
      (lambda ()
        (if (fx>= i len)
            (values #f #f)
            (let ([ch (string-ref str i)])
              (set! i (fx+ i 1))
              (values ch #t))))))

  ;; Bytevector iterator (iterates over bytes as exact integers)
  (define (make-bytevector-iterator bv)
    (let ([len (bytevector-length bv)]
          [i 0])
      (lambda ()
        (if (fx>= i len)
            (values #f #f)
            (let ([byte (bytevector-u8-ref bv i)])
              (set! i (fx+ i 1))
              (values byte #t))))))

  ;; Hashtable iterator (iterates over (key . value) pairs)
  (define (make-hashtable-iterator ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let ([len (vector-length keys)]
            [i 0])
        (lambda ()
          (if (fx>= i len)
              (values #f #f)
              (let ([pair (cons (vector-ref keys i) (vector-ref vals i))])
                (set! i (fx+ i 1))
                (values pair #t)))))))

  ;; ----- Generic algorithms -----

  (define (collection-fold proc seed coll)
    (let ([iter (make-iterator coll)])
      (let loop ([acc seed])
        (let-values ([(elem ok?) (iter)])
          (if ok?
              (loop (proc elem acc))
              acc)))))

  (define (collection-map proc coll)
    (let ([iter (make-iterator coll)])
      (let loop ([result '()])
        (let-values ([(elem ok?) (iter)])
          (if ok?
              (loop (cons (proc elem) result))
              (reverse result))))))

  (define (collection-filter pred coll)
    (let ([iter (make-iterator coll)])
      (let loop ([result '()])
        (let-values ([(elem ok?) (iter)])
          (if ok?
              (if (pred elem)
                  (loop (cons elem result))
                  (loop result))
              (reverse result))))))

  (define (collection-for-each proc coll)
    (let ([iter (make-iterator coll)])
      (let loop ()
        (let-values ([(elem ok?) (iter)])
          (when ok?
            (proc elem)
            (loop))))))

  (define (collection-find pred coll)
    (let ([iter (make-iterator coll)])
      (let loop ()
        (let-values ([(elem ok?) (iter)])
          (cond
            [(not ok?) #f]
            [(pred elem) elem]
            [else (loop)])))))

  (define (collection-any pred coll)
    (let ([iter (make-iterator coll)])
      (let loop ()
        (let-values ([(elem ok?) (iter)])
          (cond
            [(not ok?) #f]
            [(pred elem) #t]
            [else (loop)])))))

  (define (collection-every pred coll)
    (let ([iter (make-iterator coll)])
      (let loop ()
        (let-values ([(elem ok?) (iter)])
          (cond
            [(not ok?) #t]
            [(not (pred elem)) #f]
            [else (loop)])))))

  (define (collection->list coll)
    (collection-map (lambda (x) x) coll))

  (define (collection-length coll)
    (collection-fold (lambda (_elem count) (fx+ count 1)) 0 coll))

  ;; ----- Register built-in types -----
  (register-collection! list? make-list-iterator)
  (register-collection! vector? make-vector-iterator)
  (register-collection! string? make-string-iterator)
  (register-collection! bytevector? make-bytevector-iterator)
  (register-collection! hashtable? make-hashtable-iterator)

) ;; end library
