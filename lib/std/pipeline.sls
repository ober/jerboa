#!chezscheme
;;; (std pipeline) -- Data pipeline DSL

(library (std pipeline)
  (export
    make-pipeline pipeline? pipeline-add-stage! pipeline-run pipeline-run-parallel
    make-stage stage? stage-name stage-fn stage-result
    pipeline-result pipeline-stats
    \x7C;\x3E; pipe
    pipeline-compose pipeline-map pipeline-filter pipeline-reduce
    pipeline-tap pipeline-catch pipeline-timeout)

  (import (chezscheme))

  ;;; ---- Stage ----

  (define-record-type %stage
    (fields name fn (mutable result) (mutable elapsed) (mutable in-count) (mutable out-count))
    (protocol (lambda (new)
      (lambda (name fn) (new name fn #f 0 0 0)))))

  (define (make-stage name fn) (make-%stage name fn))
  (define (stage? x) (%stage? x))
  (define (stage-name s) (%stage-name s))
  (define (stage-fn s) (%stage-fn s))
  (define (stage-result s) (%stage-result s))

  ;;; ---- Pipeline ----

  (define-record-type %pipeline
    (fields (mutable stages) (mutable result))
    (protocol (lambda (new) (lambda () (new '() #f)))))

  (define (make-pipeline) (make-%pipeline))
  (define (pipeline? x) (%pipeline? x))

  (define (pipeline-add-stage! p stage)
    (%pipeline-stages-set! p (append (%pipeline-stages p) (list stage))))

  (define (pipeline-result p) (%pipeline-result p))

  (define (pipeline-stats p)
    (map (lambda (s)
           (list (stage-name s)
                 (cons 'elapsed (%stage-elapsed s))
                 (cons 'in (%stage-in-count s))
                 (cons 'out (%stage-out-count s))))
         (%pipeline-stages p)))

  ;;; ---- pipeline-run: sequential ----

  (define (pipeline-run p initial)
    (let loop ([stages (%pipeline-stages p)] [val initial])
      (if (null? stages)
        (begin (%pipeline-result-set! p val) val)
        (let* ([s (car stages)]
               [in-count (if (list? val) (length val) 1)]
               [start (real-time)]
               [result ((%stage-fn s) val)]
               [elapsed (- (real-time) start)]
               [out-count (if (list? result) (length result) 1)])
          (%stage-result-set! s result)
          (%stage-elapsed-set! s elapsed)
          (%stage-in-count-set! s in-count)
          (%stage-out-count-set! s out-count)
          (loop (cdr stages) result)))))

  ;;; ---- pipeline-run-parallel: parallel stages ----

  (define (pipeline-run-parallel p inputs)
    ;; Run each stage on its corresponding input in parallel
    (let* ([stages (%pipeline-stages p)]
           [pairs (if (list? inputs) inputs (list inputs))]
           [results (make-vector (length stages) #f)]
           [threads (map
                      (lambda (s i)
                        (fork-thread
                          (lambda ()
                            (let ([r ((%stage-fn s) (if (pair? pairs) (list-ref pairs (min i (- (length pairs) 1))) inputs))])
                              (%stage-result-set! s r)
                              (vector-set! results i r)))))
                      stages
                      (iota (length stages)))])
        (for-each thread-join threads)
        (let ([result (vector->list results)])
          (%pipeline-result-set! p result)
          result)))

  ;;; ---- |> threading macro ----

  ;; |> is represented with hex escapes since |...| is special in Chez Scheme
  (define-syntax \x7C;\x3E;
    (syntax-rules ()
      [(_ val) val]
      [(_ val (f arg ...) rest ...)
       (\x7C;\x3E; (f val arg ...) rest ...)]))

  ;;; ---- pipe: function composition ----

  (define (pipe . fns)
    (lambda (x)
      (let loop ([fns fns] [val x])
        (if (null? fns)
          val
          (loop (cdr fns) ((car fns) val))))))

  ;;; ---- pipeline-compose: compose two pipeline stages ----

  (define (pipeline-compose . stages)
    (make-stage
      (string-append "composed["
        (apply string-append
          (map (lambda (s) (string-append (stage-name s) ",")) stages))
        "]")
      (lambda (input)
        (let loop ([ss stages] [val input])
          (if (null? ss)
            val
            (loop (cdr ss) ((stage-fn (car ss)) val)))))))

  ;;; ---- Stage factory functions ----

  (define (pipeline-map f)
    (make-stage "map"
      (lambda (lst)
        (if (list? lst)
          (map f lst)
          (f lst)))))

  (define (pipeline-filter pred)
    (make-stage "filter"
      (lambda (lst)
        (if (list? lst)
          (filter pred lst)
          (if (pred lst) lst '())))))

  (define (pipeline-reduce f init)
    (make-stage "reduce"
      (lambda (lst)
        (if (list? lst)
          (fold-left f init lst)
          (f init lst)))))

  (define (pipeline-tap f)
    (make-stage "tap"
      (lambda (val)
        (f val)
        val)))

  (define (pipeline-catch handler)
    (make-stage "catch"
      (lambda (val)
        (guard (exn [#t (handler exn val)])
          val))))

  (define (pipeline-timeout ms inner-stage)
    (make-stage (string-append "timeout[" (number->string ms) "ms]")
      (lambda (val)
        (let* ([result-box (list #f)]
               [done? (list #f)]
               [mutex (make-mutex)]
               [cond-var (make-condition)]
               [worker (fork-thread
                         (lambda ()
                           (let ([r (guard (exn [#t exn])
                                     ((stage-fn inner-stage) val))])
                             (with-mutex mutex
                               (set-car! result-box r)
                               (set-car! done? #t)
                               (condition-signal cond-var)))))])
          (with-mutex mutex
            (let loop ([remaining ms])
              (cond
                [(car done?) (car result-box)]
                [(< remaining 0)
                 (error 'pipeline-timeout "stage timed out" ms)]
                [else
                 (condition-wait cond-var mutex (/ remaining 1000.0))
                 (if (car done?)
                   (car result-box)
                   (error 'pipeline-timeout "stage timed out" ms))])))))))


) ;; end library
