#!chezscheme
;;; :std/srfi/158 -- Generators and Accumulators (SRFI-158)
;;; Superset of SRFI-121 with accumulators.

(library (std srfi srfi-158)
  (export
    generator circular-generator
    make-iota-generator make-range-generator
    make-coroutine-generator
    list->generator vector->generator string->generator
    bytevector->generator
    generator->list generator->vector generator->string
    generator-fold generator-for-each generator-map->list
    generator-find generator-count generator-any generator-every
    gcons* gappend gcombine gfilter gremove
    gtake gdrop gdelete-neighbor-dups gflatten
    make-accumulator count-accumulator
    list-accumulator vector-accumulator sum-accumulator)

  (import (chezscheme))

  (define eof (eof-object))

  ;; ---- Constructors ----

  (define (generator . args)
    (let ([lst args])
      (lambda ()
        (if (null? lst)
          eof
          (let ([v (car lst)])
            (set! lst (cdr lst))
            v)))))

  (define (circular-generator . args)
    (when (null? args)
      (error 'circular-generator "at least one argument required"))
    (let ([lst args] [cur args])
      (lambda ()
        (when (null? cur) (set! cur lst))
        (let ([v (car cur)])
          (set! cur (cdr cur))
          v))))

  (define (make-iota-generator count . args)
    (let ([start (if (pair? args) (car args) 0)]
          [step (if (and (pair? args) (pair? (cdr args))) (cadr args) 1)])
      (let ([n start] [remaining count])
        (lambda ()
          (if (<= remaining 0)
            eof
            (let ([v n])
              (set! n (+ n step))
              (set! remaining (- remaining 1))
              v))))))

  (define (make-range-generator start . args)
    (let ([end (if (pair? args) (car args) +inf.0)]
          [step (if (and (pair? args) (pair? (cdr args))) (cadr args) 1)])
      (let ([n start])
        (lambda ()
          (if (if (positive? step) (>= n end) (<= n end))
            eof
            (let ([v n])
              (set! n (+ n step))
              v))))))

  (define (make-coroutine-generator proc)
    (define return #f)
    (define resume #f)
    (define finished #f)
    (define (yield value)
      (call/cc (lambda (k)
        (set! resume k)
        (return value))))
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

  (define (list->generator lst)
    (let ([cur lst])
      (lambda ()
        (if (null? cur)
          eof
          (let ([v (car cur)])
            (set! cur (cdr cur))
            v)))))

  (define (vector->generator vec . args)
    (let ([start (if (pair? args) (car args) 0)]
          [end (if (and (pair? args) (pair? (cdr args)))
                   (cadr args) (vector-length vec))])
      (let ([i start])
        (lambda ()
          (if (>= i end)
            eof
            (let ([v (vector-ref vec i)])
              (set! i (+ i 1))
              v))))))

  (define (string->generator str . args)
    (let ([start (if (pair? args) (car args) 0)]
          [end (if (and (pair? args) (pair? (cdr args)))
                   (cadr args) (string-length str))])
      (let ([i start])
        (lambda ()
          (if (>= i end)
            eof
            (let ([c (string-ref str i)])
              (set! i (+ i 1))
              c))))))

  (define (bytevector->generator bv . args)
    (let ([start (if (pair? args) (car args) 0)]
          [end (if (and (pair? args) (pair? (cdr args)))
                   (cadr args) (bytevector-length bv))])
      (let ([i start])
        (lambda ()
          (if (>= i end)
            eof
            (let ([b (bytevector-u8-ref bv i)])
              (set! i (+ i 1))
              b))))))

  ;; ---- Consumers ----

  (define (generator->list gen . args)
    (let ([n (if (pair? args) (car args) -1)])
      (let loop ([acc '()] [count 0])
        (if (= count n)
          (reverse acc)
          (let ([v (gen)])
            (if (eof-object? v)
              (reverse acc)
              (loop (cons v acc) (+ count 1))))))))

  (define (generator->vector gen . args)
    (list->vector (apply generator->list gen args)))

  (define (generator->string gen . args)
    (list->string (apply generator->list gen args)))

  (define (generator-fold proc seed gen)
    (let loop ([acc seed])
      (let ([v (gen)])
        (if (eof-object? v)
          acc
          (loop (proc v acc))))))

  (define (generator-for-each proc gen . rest)
    (if (null? rest)
      (let loop ()
        (let ([v (gen)])
          (unless (eof-object? v)
            (proc v)
            (loop))))
      (let ([gens (cons gen rest)])
        (let loop ()
          (let ([vals (map (lambda (g) (g)) gens)])
            (unless (exists eof-object? vals)
              (apply proc vals)
              (loop)))))))

  (define (generator-map->list proc gen . rest)
    (if (null? rest)
      (let loop ([acc '()])
        (let ([v (gen)])
          (if (eof-object? v)
            (reverse acc)
            (loop (cons (proc v) acc)))))
      (let ([gens (cons gen rest)])
        (let loop ([acc '()])
          (let ([vals (map (lambda (g) (g)) gens)])
            (if (exists eof-object? vals)
              (reverse acc)
              (loop (cons (apply proc vals) acc))))))))

  (define (generator-find pred gen)
    (let loop ()
      (let ([v (gen)])
        (cond
          [(eof-object? v) #f]
          [(pred v) v]
          [else (loop)]))))

  (define (generator-count pred gen)
    (let loop ([n 0])
      (let ([v (gen)])
        (if (eof-object? v)
          n
          (loop (if (pred v) (+ n 1) n))))))

  (define (generator-any pred gen)
    (let loop ()
      (let ([v (gen)])
        (cond
          [(eof-object? v) #f]
          [(pred v) => values]
          [else (loop)]))))

  (define (generator-every pred gen)
    (let loop ([last #t])
      (let ([v (gen)])
        (if (eof-object? v)
          last
          (let ([result (pred v)])
            (if result
              (loop result)
              #f))))))

  ;; ---- Combinators ----

  (define (gcons* . args)
    (when (null? args)
      (error 'gcons* "at least one argument (a generator) required"))
    (let ([vals (reverse (cdr (reverse args)))]  ;; all but last
          [gen (car (reverse args))])             ;; last is the generator
      (let ([prefix vals])
        (lambda ()
          (if (null? prefix)
            (gen)
            (let ([v (car prefix)])
              (set! prefix (cdr prefix))
              v))))))

  (define (gappend . gens)
    (let ([gs gens])
      (lambda ()
        (let loop ()
          (if (null? gs)
            eof
            (let ([v ((car gs))])
              (if (eof-object? v)
                (begin (set! gs (cdr gs)) (loop))
                v)))))))

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

  (define (gfilter pred gen)
    (lambda ()
      (let loop ()
        (let ([v (gen)])
          (cond
            [(eof-object? v) eof]
            [(pred v) v]
            [else (loop)])))))

  (define (gremove pred gen)
    (gfilter (lambda (x) (not (pred x))) gen))

  (define (gtake gen n . args)
    (let ([padding (if (pair? args) (car args) eof)]
          [count 0])
      (lambda ()
        (if (>= count n)
          eof
          (begin
            (set! count (+ count 1))
            (let ([v (gen)])
              (if (eof-object? v) padding v)))))))

  (define (gdrop gen n)
    (let ([dropped #f])
      (lambda ()
        (unless dropped
          (set! dropped #t)
          (do ([i 0 (+ i 1)])
              ((= i n))
            (gen)))
        (gen))))

  (define (gdelete-neighbor-dups gen . args)
    (let ([= (if (pair? args) (car args) equal?)]
          [prev (list 'unset)])  ;; unique sentinel
      (lambda ()
        (let loop ()
          (let ([v (gen)])
            (cond
              [(eof-object? v) eof]
              [(eq? prev (list 'unset))  ;; never happens after first, use pair identity
               ;; First element
               (set! prev v)
               v]
              [(= prev v) (loop)]  ;; duplicate, skip
              [else
               (set! prev v)
               v]))))))

  ;; Fix: use a mutable box for the sentinel check
  (define (gdelete-neighbor-dups* gen =?)
    (let ([have-prev #f] [prev #f])
      (lambda ()
        (let loop ()
          (let ([v (gen)])
            (cond
              [(eof-object? v) eof]
              [(not have-prev)
               (set! have-prev #t)
               (set! prev v)
               v]
              [(=? prev v) (loop)]
              [else
               (set! prev v)
               v]))))))

  ;; Override the first version with the correct one
  (set! gdelete-neighbor-dups
    (lambda (gen . args)
      (let ([=? (if (pair? args) (car args) equal?)])
        (gdelete-neighbor-dups* gen =?))))

  (define (gflatten gen)
    (let ([current '()])
      (lambda ()
        (let loop ()
          (cond
            [(pair? current)
             (let ([v (car current)])
               (set! current (cdr current))
               v)]
            [else
             (let ([v (gen)])
               (cond
                 [(eof-object? v) eof]
                 [(pair? v)
                  (set! current v)
                  (loop)]
                 [else v]))])))))

  ;; ---- Accumulators ----

  (define (make-accumulator kons seed)
    (let ([state seed])
      (lambda (v)
        (set! state (kons v state))
        state)))

  (define (count-accumulator)
    (let ([n 0])
      (lambda (v)
        (set! n (+ n 1))
        n)))

  (define (list-accumulator)
    (let ([lst '()])
      (lambda (v)
        (set! lst (cons v lst))
        ;; Return reversed to get insertion order on final call
        ;; Actually, SRFI-158 says list-accumulator returns in order,
        ;; so we accumulate in reverse and the caller gets reversed at end.
        ;; But the accumulator returns the accumulated value each time.
        ;; Let's return the reverse each time (less efficient but correct).
        (reverse lst))))

  (define (vector-accumulator)
    (let ([lst '()])
      (lambda (v)
        (set! lst (cons v lst))
        (list->vector (reverse lst)))))

  (define (sum-accumulator)
    (let ([total 0])
      (lambda (v)
        (set! total (+ total v))
        total)))

) ;; end library
