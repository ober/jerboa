#!chezscheme
;;; :std/srfi/121 -- Generators (SRFI-121)
;;; A generator is a thunk that yields successive values, then eof-object.

(library (std srfi srfi-121)
  (export
    generator make-coroutine-generator circular-generator
    list->generator vector->generator string->generator
    range->generator
    generator->list generator->vector
    generator-fold generator-for-each generator-map
    generator-filter generator-take generator-drop
    gappend gcombine)

  (import (chezscheme))

  (define eof (eof-object))

  ;; generator: create a generator from a fixed list of values
  (define (generator . args)
    (let ([lst args])
      (lambda ()
        (if (null? lst)
          eof
          (let ([v (car lst)])
            (set! lst (cdr lst))
            v)))))

  ;; make-coroutine-generator: proc receives a yield procedure
  (define (make-coroutine-generator proc)
    (define return #f)
    (define resume #f)
    (define (yield value)
      (call/cc (lambda (k)
        (set! resume k)
        (return value))))
    (define finished #f)
    (lambda ()
      (if finished
        eof
        (call/cc (lambda (k)
          (set! return k)
          (if resume
            (resume (void))
            (begin
              (proc yield)
              (set! finished #t)
              (return eof))))))))

  ;; circular-generator: cycle through values forever
  (define (circular-generator . args)
    (when (null? args)
      (error 'circular-generator "at least one argument required"))
    (let ([lst args] [cur args])
      (lambda ()
        (when (null? cur)
          (set! cur lst))
        (let ([v (car cur)])
          (set! cur (cdr cur))
          v))))

  ;; list->generator
  (define (list->generator lst)
    (let ([cur lst])
      (lambda ()
        (if (null? cur)
          eof
          (let ([v (car cur)])
            (set! cur (cdr cur))
            v)))))

  ;; vector->generator with optional start/end
  (define (vector->generator vec . args)
    (let ([start (if (pair? args) (car args) 0)]
          [end (if (and (pair? args) (pair? (cdr args)))
                   (cadr args)
                   (vector-length vec))])
      (let ([i start])
        (lambda ()
          (if (>= i end)
            eof
            (let ([v (vector-ref vec i)])
              (set! i (+ i 1))
              v))))))

  ;; string->generator
  (define (string->generator str . args)
    (let ([start (if (pair? args) (car args) 0)]
          [end (if (and (pair? args) (pair? (cdr args)))
                   (cadr args)
                   (string-length str))])
      (let ([i start])
        (lambda ()
          (if (>= i end)
            eof
            (let ([c (string-ref str i)])
              (set! i (+ i 1))
              c))))))

  ;; range->generator
  (define (range->generator start . args)
    (let ([end (if (pair? args) (car args) +inf.0)]
          [step (if (and (pair? args) (pair? (cdr args)))
                    (cadr args) 1)])
      (let ([n start])
        (lambda ()
          (if (if (positive? step) (>= n end) (<= n end))
            eof
            (let ([v n])
              (set! n (+ n step))
              v))))))

  ;; generator->list
  (define (generator->list gen . args)
    (let ([n (if (pair? args) (car args) -1)])
      (let loop ([acc '()] [count 0])
        (if (= count n)
          (reverse acc)
          (let ([v (gen)])
            (if (eof-object? v)
              (reverse acc)
              (loop (cons v acc) (+ count 1))))))))

  ;; generator->vector
  (define (generator->vector gen . args)
    (list->vector (apply generator->list gen args)))

  ;; generator-fold
  (define (generator-fold proc seed gen)
    (let loop ([acc seed])
      (let ([v (gen)])
        (if (eof-object? v)
          acc
          (loop (proc v acc))))))

  ;; generator-for-each
  (define (generator-for-each proc gen)
    (let loop ()
      (let ([v (gen)])
        (unless (eof-object? v)
          (proc v)
          (loop)))))

  ;; generator-map: returns a new generator
  (define (generator-map proc gen)
    (lambda ()
      (let ([v (gen)])
        (if (eof-object? v)
          eof
          (proc v)))))

  ;; generator-filter: returns a new generator
  (define (generator-filter pred gen)
    (lambda ()
      (let loop ()
        (let ([v (gen)])
          (cond
            [(eof-object? v) eof]
            [(pred v) v]
            [else (loop)])))))

  ;; generator-take: take at most n values
  (define (generator-take gen n)
    (let ([count 0])
      (lambda ()
        (if (>= count n)
          eof
          (let ([v (gen)])
            (set! count (+ count 1))
            v)))))

  ;; generator-drop: skip first n values
  (define (generator-drop gen n)
    (let ([dropped #f])
      (lambda ()
        (unless dropped
          (set! dropped #t)
          (do ([i 0 (+ i 1)])
              ((= i n))
            (gen)))
        (gen))))

  ;; gappend: concatenate generators
  (define (gappend . gens)
    (let ([gs gens])
      (lambda ()
        (let loop ()
          (if (null? gs)
            eof
            (let ([v ((car gs))])
              (if (eof-object? v)
                (begin
                  (set! gs (cdr gs))
                  (loop))
                v)))))))

  ;; gcombine: combine with state
  (define (gcombine proc seed gen)
    (let ([state seed])
      (lambda ()
        (let ([v (gen)])
          (if (eof-object? v)
            eof
            (call-with-values
              (lambda () (proc v state))
              (lambda (result new-state)
                (set! state new-state)
                result)))))))

) ;; end library
