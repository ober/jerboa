#!chezscheme
;;; (std misc lazy-seq) — Clojure-style lazy sequences
;;;
;;; Lazy sequences are built from memoized thunks that produce either
;;; (cons head tail) or '() when forced. Once forced, the result is cached.
;;;
;;; (lazy-range 0 5)          => lazy seq: 0 1 2 3 4
;;; (lazy-seq->list (lazy-take 5 (lazy-iterate add1 0)))  => (0 1 2 3 4)
;;; (lazy-seq->list (lazy-filter odd? (lazy-range 0 10))) => (1 3 5 7 9)

(library (std misc lazy-seq)
  (export lazy-seq lazy-cons lazy-null lazy-null?
          lazy-car lazy-cdr lazy-seq->list list->lazy-seq
          lazy-take lazy-drop lazy-map lazy-filter
          lazy-append lazy-range lazy-iterate lazy-zip)
  (import (chezscheme))

  ;; A lazy sequence is a memoizing thunk.
  ;; When called, it returns either '() or (cons head lazy-tail).

  ;; Sentinel for "not yet forced"
  (define *unforced* (cons 'unforced '()))

  (define (make-lazy-thunk thunk)
    ;; Returns a procedure that forces thunk at most once, caching the result.
    (let ([result *unforced*])
      (lambda ()
        (when (eq? result *unforced*)
          (set! result (thunk)))
        result)))

  ;; lazy-seq macro: wraps body in a memoized thunk
  ;; Body should evaluate to (cons head tail) or '()
  (define-syntax lazy-seq
    (syntax-rules ()
      [(_ body ...)
       (make-lazy-thunk (lambda () body ...))]))

  ;; Construct a lazy pair: head is evaluated eagerly, tail is a lazy-seq
  (define-syntax lazy-cons
    (syntax-rules ()
      [(_ head tail-expr)
       (make-lazy-thunk (lambda () (cons head tail-expr)))]))

  ;; The empty lazy sequence
  (define lazy-null
    (make-lazy-thunk (lambda () '())))

  ;; Test if a lazy sequence is empty (forces it)
  (define (lazy-null? lseq)
    (null? (lseq)))

  ;; Force and get head
  (define (lazy-car lseq)
    (let ([v (lseq)])
      (if (null? v)
          (error 'lazy-car "empty lazy sequence")
          (car v))))

  ;; Force and get tail (which is itself a lazy-seq)
  (define (lazy-cdr lseq)
    (let ([v (lseq)])
      (if (null? v)
          (error 'lazy-cdr "empty lazy sequence")
          (cdr v))))

  ;; Force entire lazy sequence to a list
  (define (lazy-seq->list lseq)
    (let loop ([s lseq] [acc '()])
      (let ([v (s)])
        (if (null? v)
            (reverse acc)
            (loop (cdr v) (cons (car v) acc))))))

  ;; Convert a list to a lazy sequence
  (define (list->lazy-seq lst)
    (if (null? lst)
        lazy-null
        (lazy-cons (car lst) (list->lazy-seq (cdr lst)))))

  ;; Take at most n elements
  (define (lazy-take n lseq)
    (if (<= n 0)
        lazy-null
        (lazy-seq
          (let ([v (lseq)])
            (if (null? v)
                '()
                (cons (car v) (lazy-take (- n 1) (cdr v))))))))

  ;; Drop n elements
  (define (lazy-drop n lseq)
    (if (<= n 0)
        lseq
        (lazy-seq
          (let ([v (lseq)])
            (if (null? v)
                '()
                ((lazy-drop (- n 1) (cdr v))))))))

  ;; Lazy map
  (define (lazy-map f lseq)
    (lazy-seq
      (let ([v (lseq)])
        (if (null? v)
            '()
            (cons (f (car v)) (lazy-map f (cdr v)))))))

  ;; Lazy filter
  (define (lazy-filter pred lseq)
    (lazy-seq
      (let loop ([s lseq])
        (let ([v (s)])
          (if (null? v)
              '()
              (if (pred (car v))
                  (cons (car v) (lazy-filter pred (cdr v)))
                  (loop (cdr v))))))))

  ;; Lazy append two sequences
  (define (lazy-append lseq1 lseq2)
    (lazy-seq
      (let ([v (lseq1)])
        (if (null? v)
            (lseq2)
            (cons (car v) (lazy-append (cdr v) lseq2))))))

  ;; Generate a range [start, end) with step, or infinite from start
  (define lazy-range
    (case-lambda
      [() (lazy-iterate add1 0)]
      [(end) (lazy-range 0 end 1)]
      [(start end) (lazy-range start end 1)]
      [(start end step)
       (lazy-seq
         (if (if (positive? step) (< start end) (> start end))
             (cons start (lazy-range (+ start step) end step))
             '()))]))

  ;; Infinite sequence: seed, (f seed), (f (f seed)), ...
  (define (lazy-iterate f seed)
    (lazy-cons seed (lazy-iterate f (f seed))))

  ;; Zip two lazy sequences into pairs
  (define (lazy-zip lseq1 lseq2)
    (lazy-seq
      (let ([v1 (lseq1)]
            [v2 (lseq2)])
        (if (or (null? v1) (null? v2))
            '()
            (cons (cons (car v1) (car v2))
                  (lazy-zip (cdr v1) (cdr v2)))))))

) ;; end library
