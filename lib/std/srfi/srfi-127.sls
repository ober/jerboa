#!chezscheme
;;; :std/srfi/127 -- Lazy Sequences (SRFI-127)
;;; An lseq is a pair whose cdr is a promise (delayed computation).
;;; Converts SRFI-121 generators to lazy sequences and vice versa.

(library (std srfi srfi-127)
  (export
    generator->lseq lseq? lseq-car lseq-cdr
    lseq-first lseq-rest lseq-null? lseq-pair?
    lseq-take lseq-drop lseq-ref lseq-length
    lseq-map lseq-filter lseq-for-each lseq-fold
    lseq-any lseq-every lseq-append
    lseq->list lseq->generator)

  (import (chezscheme))

  ;; An lseq is either:
  ;;   '() -- the empty lseq
  ;;   (value . promise) -- a pair whose cdr is a promise that forces to an lseq
  ;; We use Chez's delay/force for promises.

  (define (lseq-null? x) (null? x))

  (define (lseq-pair? x)
    (and (pair? x) #t))

  (define (lseq? x)
    (or (null? x) (pair? x)))

  ;; Force the cdr if it's a promise (procedure), memoizing the result
  (define (lseq-realize! p)
    (when (pair? p)
      (let ([d (cdr p)])
        (when (procedure? d)
          (let ([result (d)])
            (set-cdr! p result))))))

  (define (lseq-car ls)
    (if (null? ls)
        (error 'lseq-car "empty lseq")
        (car ls)))

  (define lseq-first lseq-car)

  (define (lseq-cdr ls)
    (if (null? ls)
        (error 'lseq-cdr "empty lseq")
        (begin
          (lseq-realize! ls)
          (cdr ls))))

  (define lseq-rest lseq-cdr)

  ;; Convert a SRFI-121 generator (thunk returning eof-object at end) to lseq
  (define (generator->lseq gen)
    (let ([v (gen)])
      (if (eof-object? v)
          '()
          (cons v (lambda () (generator->lseq gen))))))

  (define (lseq-take ls n)
    (if (or (zero? n) (null? ls))
        '()
        (cons (lseq-car ls)
              (lambda () (lseq-take (lseq-cdr ls) (- n 1))))))

  (define (lseq-drop ls n)
    (if (zero? n) ls
        (if (null? ls)
            (error 'lseq-drop "index out of range")
            (lseq-drop (lseq-cdr ls) (- n 1)))))

  (define (lseq-ref ls n)
    (lseq-car (lseq-drop ls n)))

  (define (lseq-length ls)
    (let loop ([l ls] [n 0])
      (if (null? l) n
          (loop (lseq-cdr l) (+ n 1)))))

  (define (lseq-map f ls)
    (if (null? ls)
        '()
        (cons (f (lseq-car ls))
              (lambda () (lseq-map f (lseq-cdr ls))))))

  (define (lseq-filter pred ls)
    (let loop ([l ls])
      (cond
        [(null? l) '()]
        [(pred (lseq-car l))
         (cons (lseq-car l)
               (lambda () (lseq-filter pred (lseq-cdr l))))]
        [else (loop (lseq-cdr l))])))

  (define (lseq-for-each f ls)
    (unless (null? ls)
      (f (lseq-car ls))
      (lseq-for-each f (lseq-cdr ls))))

  (define (lseq-fold f seed ls)
    (if (null? ls) seed
        (lseq-fold f (f (lseq-car ls) seed) (lseq-cdr ls))))

  (define (lseq-any pred ls)
    (and (not (null? ls))
         (or (pred (lseq-car ls))
             (lseq-any pred (lseq-cdr ls)))))

  (define (lseq-every pred ls)
    (or (null? ls)
        (if (null? (let ([rest (lseq-cdr ls)]) rest))
            ;; last element -- return its truth value
            (let ([rest (lseq-cdr ls)])
              (if (null? rest)
                  (pred (lseq-car ls))
                  (and (pred (lseq-car ls))
                       (lseq-every pred rest))))
            (and (pred (lseq-car ls))
                 (lseq-every pred (lseq-cdr ls))))))

  (define (lseq-append . lseqs)
    (cond
      [(null? lseqs) '()]
      [(null? (cdr lseqs)) (car lseqs)]
      [else
       (let append2 ([a (car lseqs)] [rest (cdr lseqs)])
         (if (null? a)
             (apply lseq-append rest)
             (cons (lseq-car a)
                   (lambda ()
                     (append2 (lseq-cdr a) rest)))))]))

  (define (lseq->list ls)
    (if (null? ls) '()
        (cons (lseq-car ls) (lseq->list (lseq-cdr ls)))))

  (define (lseq->generator ls)
    (let ([cursor ls])
      (lambda ()
        (if (null? cursor)
            (eof-object)
            (let ([v (lseq-car cursor)])
              (set! cursor (lseq-cdr cursor))
              v)))))
)
