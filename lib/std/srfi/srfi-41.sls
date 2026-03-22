#!chezscheme
;;; :std/srfi/41 -- Streams (SRFI-41)
;;; Lazy sequences with delayed head and tail.

(library (std srfi srfi-41)
  (export
    stream-null stream-null? stream-cons stream-car stream-cdr
    stream-pair? stream? stream-map stream-filter stream-fold
    stream-for-each stream-take stream-drop stream-ref
    stream-append stream->list list->stream stream-range
    stream-iterate stream-constant stream-zip)

  (import (chezscheme))

  ;; Stream type: a promise that forces to either stream-null-obj
  ;; or a stream-pair record.

  (define stream-null-obj (cons 'stream 'null))

  (define (stream-null? x)
    (and (box? x)
         (eq? (unbox x) stream-null-obj)))

  (define stream-null
    (box stream-null-obj))

  (define-record-type stream-pair-rec
    (fields (immutable hd) (immutable tl))
    (sealed #t))

  ;; stream-cons delays both head and tail, wrapping in a box (eager promise).
  ;; We use Chez's delay/force for laziness.
  (define-syntax stream-cons
    (syntax-rules ()
      [(_ head tail)
       (box (make-stream-pair-rec (delay head) (delay tail)))]))

  (define (stream-pair? x)
    (and (box? x)
         (stream-pair-rec? (unbox x))))

  (define (stream? x)
    (or (stream-null? x)
        (stream-pair? x)))

  (define (stream-car s)
    (unless (stream-pair? s)
      (error 'stream-car "not a stream pair" s))
    (force (stream-pair-rec-hd (unbox s))))

  (define (stream-cdr s)
    (unless (stream-pair? s)
      (error 'stream-cdr "not a stream pair" s))
    (force (stream-pair-rec-tl (unbox s))))

  (define (stream-ref s n)
    (when (< n 0)
      (error 'stream-ref "negative index" n))
    (let loop ([s s] [n n])
      (cond
        [(stream-null? s) (error 'stream-ref "index out of range")]
        [(= n 0) (stream-car s)]
        [else (loop (stream-cdr s) (- n 1))])))

  (define (stream-take s n)
    (if (or (<= n 0) (stream-null? s))
      stream-null
      (stream-cons (stream-car s)
                   (stream-take (stream-cdr s) (- n 1)))))

  (define (stream-drop s n)
    (let loop ([s s] [n n])
      (if (or (<= n 0) (stream-null? s))
        s
        (loop (stream-cdr s) (- n 1)))))

  (define (stream->list s . args)
    (let ([n (if (pair? args) (car args) -1)])
      (let loop ([s s] [n n] [acc '()])
        (if (or (stream-null? s) (= n 0))
          (reverse acc)
          (loop (stream-cdr s) (- n 1) (cons (stream-car s) acc))))))

  (define (list->stream lst)
    (if (null? lst)
      stream-null
      (stream-cons (car lst) (list->stream (cdr lst)))))

  (define (stream-map proc s . rest)
    (if (null? rest)
      ;; Single-stream fast path
      (let loop ([s s])
        (if (stream-null? s)
          stream-null
          (stream-cons (proc (stream-car s))
                       (loop (stream-cdr s)))))
      ;; Multi-stream
      (let ([streams (cons s rest)])
        (let loop ([streams streams])
          (if (exists stream-null? streams)
            stream-null
            (stream-cons
              (apply proc (map stream-car streams))
              (loop (map stream-cdr streams))))))))

  (define (stream-filter pred s)
    (let loop ([s s])
      (cond
        [(stream-null? s) stream-null]
        [(pred (stream-car s))
         (stream-cons (stream-car s)
                      (loop (stream-cdr s)))]
        [else (loop (stream-cdr s))])))

  (define (stream-fold proc seed s)
    (let loop ([acc seed] [s s])
      (if (stream-null? s)
        acc
        (loop (proc acc (stream-car s)) (stream-cdr s)))))

  (define (stream-for-each proc s . rest)
    (if (null? rest)
      (let loop ([s s])
        (unless (stream-null? s)
          (proc (stream-car s))
          (loop (stream-cdr s))))
      (let ([streams (cons s rest)])
        (let loop ([streams streams])
          (unless (exists stream-null? streams)
            (apply proc (map stream-car streams))
            (loop (map stream-cdr streams)))))))

  (define (stream-append . streams)
    (cond
      [(null? streams) stream-null]
      [(null? (cdr streams)) (car streams)]
      [else
       (let loop ([s (car streams)] [rest (cdr streams)])
         (if (stream-null? s)
           (apply stream-append rest)
           (stream-cons (stream-car s)
                        (loop (stream-cdr s) rest))))]))

  (define (stream-range first past . step-arg)
    (let ([step (if (pair? step-arg) (car step-arg)
                    (if (< first past) 1 -1))])
      (let loop ([n first])
        (if (if (positive? step) (>= n past) (<= n past))
          stream-null
          (stream-cons n (loop (+ n step)))))))

  (define (stream-iterate proc seed)
    (stream-cons seed (stream-iterate proc (proc seed))))

  (define (stream-constant . objs)
    (if (null? objs)
      (error 'stream-constant "at least one argument required")
      (let ([lst objs])
        (let loop ([l lst])
          (if (null? l)
            (loop lst)
            (stream-cons (car l) (loop (cdr l))))))))

  (define (stream-zip s . rest)
    (let ([streams (cons s rest)])
      (let loop ([streams streams])
        (if (exists stream-null? streams)
          stream-null
          (stream-cons
            (map stream-car streams)
            (loop (map stream-cdr streams)))))))

) ;; end library
