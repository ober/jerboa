#!chezscheme
;;; (std dev benchmark) -- Benchmark Framework with Statistical Analysis

(library (std dev benchmark)
  (export
    ;; Benchmark definition
    make-benchmark benchmark? benchmark-name benchmark-setup benchmark-run benchmark-teardown
    ;; Running
    run-benchmark
    run-benchmark-suite
    ;; Result access
    benchmark-result?
    benchmark-result-name
    benchmark-result-mean-ns
    benchmark-result-median-ns
    benchmark-result-stddev-ns
    benchmark-result-min-ns
    benchmark-result-max-ns
    benchmark-result-samples
    ;; Reporting
    benchmark-report
    ;; Macros
    define-benchmark
    with-benchmark
    ;; Utilities
    benchmark-compare
    benchmark-faster?
    benchmark->alist)

  (import (chezscheme))

  ;; ========== Record Types ==========

  ;; Internal constructor: (make-benchmark-rec name setup run teardown)
  (define-record-type benchmark-rec
    (fields (immutable name      benchmark-name)
            (immutable setup     benchmark-setup)
            (immutable run       benchmark-run)
            (immutable teardown  benchmark-teardown)))

  (define (make-benchmark name run . opts)
    (let ([setup    (if (null? opts) #f (car opts))]
          [teardown (if (or (null? opts) (null? (cdr opts))) #f (cadr opts))])
      (make-benchmark-rec name setup run teardown)))

  (define (benchmark? x) (benchmark-rec? x))

  (define-record-type benchmark-result-rec
    (fields (immutable name       benchmark-result-name)
            (immutable mean-ns    benchmark-result-mean-ns)
            (immutable median-ns  benchmark-result-median-ns)
            (immutable stddev-ns  benchmark-result-stddev-ns)
            (immutable min-ns     benchmark-result-min-ns)
            (immutable max-ns     benchmark-result-max-ns)
            (immutable samples    benchmark-result-samples)))

  (define (benchmark-result? x) (benchmark-result-rec? x))

  ;; ========== Time Measurement ==========

  (define (measure-ns thunk)
    ;; Returns elapsed nanoseconds for calling thunk
    (let* ([start (current-time 'time-process)]
           [_     (thunk)]
           [end   (current-time 'time-process)])
      (+ (* (- (time-second end) (time-second start)) 1000000000)
         (- (time-nanosecond end) (time-nanosecond start)))))

  ;; ========== Statistics ==========

  (define (list-mean lst)
    (if (null? lst)
        0.0
        (/ (apply + lst) (length lst))))

  (define (list-median lst)
    (let* ([sorted (list-sort < lst)]
           [n      (length sorted)]
           [mid    (quotient n 2)])
      (if (odd? n)
          (list-ref sorted mid)
          (/ (+ (list-ref sorted (- mid 1))
                (list-ref sorted mid))
             2))))

  (define (list-stddev lst mean)
    (if (< (length lst) 2)
        0.0
        (let* ([diffs  (map (lambda (x) (let ([d (- x mean)]) (* d d))) lst)]
               [var    (/ (apply + diffs) (- (length lst) 1))])
          (sqrt var))))

  ;; ========== Keyword Argument Helper ==========

  (define (kw-get opts key default)
    ;; opts is a flat plist; key is a symbol (compared by name for Chez #: gensyms)
    (let ([key-str (symbol->string key)])
      (let loop ([o opts])
        (cond
          [(null? o) default]
          [(and (pair? o) (symbol? (car o))
                (string=? (symbol->string (car o)) key-str))
           (if (pair? (cdr o)) (cadr o) default)]
          [else (loop (if (pair? o) (cdr o) '()))]))))

  ;; ========== Running Benchmarks ==========

  (define (run-benchmark bm . opts)
    ;; Options: #:iterations n, #:warmup n, #:gc-between bool
    (let* ([iterations  (kw-get opts '#:iterations 100)]
           [warmup      (kw-get opts '#:warmup 10)]
           [gc-between  (kw-get opts '#:gc-between #f)]
           [name        (benchmark-name bm)]
           [setup-fn    (benchmark-setup bm)]
           [run-fn      (benchmark-run bm)]
           [teardown-fn (benchmark-teardown bm)])
      ;; Warmup phase
      (let warmup-loop ([i warmup])
        (when (> i 0)
          (let ([data (if setup-fn (setup-fn) #f)])
            (when gc-between (collect))
            (if setup-fn
                (run-fn data)
                (run-fn))
            (when teardown-fn
              (if setup-fn
                  (teardown-fn data)
                  (teardown-fn))))
          (warmup-loop (- i 1))))
      ;; Measurement phase
      (let measure-loop ([i iterations] [samples '()])
        (if (= i 0)
            ;; Compute statistics
            (let* ([n      (length samples)]
                   [mean   (list-mean samples)]
                   [median (list-median samples)]
                   [stddev (list-stddev samples mean)]
                   [mn     (apply min samples)]
                   [mx     (apply max samples)])
              (make-benchmark-result-rec name
                (inexact mean) (inexact median) (inexact stddev)
                (inexact mn) (inexact mx)
                samples))
            ;; Run one iteration
            (let* ([data    (if setup-fn (setup-fn) #f)]
                   [elapsed (begin
                              (when gc-between (collect))
                              (if setup-fn
                                  (measure-ns (lambda () (run-fn data)))
                                  (measure-ns (lambda () (run-fn)))))]
                   [_       (when teardown-fn
                              (if setup-fn
                                  (teardown-fn data)
                                  (teardown-fn)))])
              (measure-loop (- i 1) (cons elapsed samples)))))))

  (define (run-benchmark-suite suite . opts)
    ;; suite is a list of benchmarks
    (map (lambda (bm) (apply run-benchmark bm opts)) suite))

  ;; ========== Reporting ==========

  (define (format-ns ns)
    (cond
      [(>= ns 1e9)  (format #f "~,3f s"  (/ ns 1e9))]
      [(>= ns 1e6)  (format #f "~,3f ms" (/ ns 1e6))]
      [(>= ns 1e3)  (format #f "~,3f us" (/ ns 1e3))]
      [else         (format #f "~,3f ns" ns)]))

  (define (benchmark-report results . port-args)
    (let ([port (if (null? port-args) (current-output-port) (car port-args))])
      (let ([rs (if (list? results) results (list results))])
        (fprintf port "~%Benchmark Results~%")
        (fprintf port "~a~%" (make-string 70 #\-))
        (fprintf port "~30a ~12a ~12a ~12a~%"
                 "Name" "Mean" "Median" "StdDev")
        (fprintf port "~a~%" (make-string 70 #\-))
        (for-each
          (lambda (r)
            (fprintf port "~30a ~12a ~12a ~12a~%"
                     (benchmark-result-name r)
                     (format-ns (benchmark-result-mean-ns r))
                     (format-ns (benchmark-result-median-ns r))
                     (format-ns (benchmark-result-stddev-ns r))))
          rs)
        (fprintf port "~a~%~%" (make-string 70 #\-)))))

  ;; ========== Macros ==========

  (define-syntax define-benchmark
    (syntax-rules (#:setup #:run #:teardown)
      [(_ name #:setup setup #:run run #:teardown teardown)
       (define name
         (make-benchmark-rec 'name setup run teardown))]
      [(_ name #:setup setup #:run run)
       (define name
         (make-benchmark-rec 'name setup run #f))]
      [(_ name #:run run)
       (define name
         (make-benchmark-rec 'name #f run #f))]))

  (define-syntax with-benchmark
    (syntax-rules ()
      [(_ name body ...)
       (run-benchmark
         (make-benchmark-rec 'name #f (lambda () body ...) #f)
         '#:iterations 10
         '#:warmup 3)]))

  ;; ========== Utilities ==========

  (define (benchmark-compare r1 r2)
    ;; Returns ratio: (mean r1) / (mean r2)
    ;; < 1 means r1 is faster, > 1 means r1 is slower
    (let ([m1 (benchmark-result-mean-ns r1)]
          [m2 (benchmark-result-mean-ns r2)])
      (if (= m2 0.0)
          +inf.0
          (/ m1 m2))))

  (define (benchmark-faster? r1 r2)
    ;; Returns #t if r1 has lower mean time than r2
    (< (benchmark-result-mean-ns r1)
       (benchmark-result-mean-ns r2)))

  (define (benchmark->alist r)
    (list
      (cons 'name    (benchmark-result-name r))
      (cons 'mean-ns (benchmark-result-mean-ns r))
      (cons 'median-ns (benchmark-result-median-ns r))
      (cons 'stddev-ns (benchmark-result-stddev-ns r))
      (cons 'min-ns  (benchmark-result-min-ns r))
      (cons 'max-ns  (benchmark-result-max-ns r))))

) ;; end library
