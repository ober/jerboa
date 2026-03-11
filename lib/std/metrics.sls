#!chezscheme
;;; (std metrics) -- Metrics collection: counters, gauges, histograms
;;;
;;; Prometheus-compatible metrics registry with text exposition format.

(library (std metrics)
  (export
    ;; Registry
    make-registry registry? registry-collect default-registry
    ;; Counter
    make-counter counter? counter-inc! counter-add! counter-value
    ;; Gauge
    make-gauge gauge? gauge-set! gauge-inc! gauge-dec! gauge-value
    ;; Histogram
    make-histogram histogram? histogram-observe!
    histogram-count histogram-sum histogram-buckets
    ;; Exposition
    prometheus-format)

  (import (chezscheme))

  ;;; ========== Registry ==========
  ;; Holds a mutable list of metric objects.
  (define-record-type %registry
    (fields (mutable metrics))
    (protocol (lambda (new) (lambda () (new '())))))

  (define (make-registry) (make-%registry))
  (define (registry? x) (%registry? x))

  (define (registry-register! reg metric)
    (%registry-metrics-set! reg
      (cons metric (%registry-metrics reg))))

  (define (registry-collect reg)
    ;; Returns a list of all metric objects
    (reverse (%registry-metrics reg)))

  (define default-registry (make-%registry))

  ;;; ========== Labels helper ==========
  ;; Labels are stored as an alist: (("name" . "value") …)
  ;; We keep label-names on the metric descriptor.

  ;;; ========== Counter ==========
  ;; name, help, label-names, value (mutable)
  (define-record-type %counter
    (fields name help label-names (mutable value))
    (protocol
      (lambda (new)
        (lambda (name help label-names)
          (new name help label-names 0)))))

  (define (counter? x) (%counter? x))

  (define (make-counter reg name help . label-names-opt)
    (let* ([lnames (if (pair? label-names-opt) (car label-names-opt) '())]
           [c (make-%counter name help lnames)])
      (when reg (registry-register! reg c))
      c))

  (define (counter-value c)   (%counter-value c))

  (define (counter-inc! c . labels-opt)
    ;; labels-opt is ignored in this simple implementation (no label instances)
    (%counter-value-set! c (+ (%counter-value c) 1)))

  (define (counter-add! c n . labels-opt)
    (when (< n 0) (error 'counter-add! "counter cannot decrease" n))
    (%counter-value-set! c (+ (%counter-value c) n)))

  ;;; ========== Gauge ==========
  (define-record-type %gauge
    (fields name help label-names (mutable value))
    (protocol
      (lambda (new)
        (lambda (name help label-names)
          (new name help label-names 0)))))

  (define (gauge? x) (%gauge? x))

  (define (make-gauge reg name help . label-names-opt)
    (let* ([lnames (if (pair? label-names-opt) (car label-names-opt) '())]
           [g (make-%gauge name help lnames)])
      (when reg (registry-register! reg g))
      g))

  (define (gauge-value g)       (%gauge-value g))
  (define (gauge-set!  g v)     (%gauge-value-set! g v))
  (define (gauge-inc!  g . opt) (%gauge-value-set! g (+ (%gauge-value g) (if (pair? opt) (car opt) 1))))
  (define (gauge-dec!  g . opt) (%gauge-value-set! g (- (%gauge-value g) (if (pair? opt) (car opt) 1))))

  ;;; ========== Histogram ==========
  ;; buckets — sorted list of upper-bound thresholds (numbers)
  ;; bucket-counts — mutable vector, one count per bucket + 1 for +Inf
  ;; count-val, sum-val — mutable totals
  (define-record-type %histogram
    (fields name help label-names
            buckets
            (mutable bucket-counts)
            (mutable count-val)
            (mutable sum-val))
    (protocol
      (lambda (new)
        (lambda (name help label-names buckets)
          (new name help label-names buckets
               (make-vector (+ (length buckets) 1) 0)
               0
               0)))))

  (define histogram? %histogram?)

  (define default-buckets '(0.005 0.01 0.025 0.05 0.1 0.25 0.5 1.0 2.5 5.0 10.0))

  (define (make-histogram reg name help . args)
    ;; args: [label-names] [buckets: list]
    ;; We accept (make-histogram reg name help) or
    ;;           (make-histogram reg name help label-names) or
    ;;           (make-histogram reg name help label-names buckets)
    (let* ([label-names (if (and (pair? args) (list? (car args)) (or (null? (car args)) (string? (caar args))))
                          (car args) '())]
           [rest        (if (and (pair? args) (list? (car args)) (or (null? (car args)) (string? (caar args))))
                          (cdr args) args)]
           [buckets     (if (pair? rest) (car rest) default-buckets)]
           [sorted      (sort < buckets)]
           [h           (make-%histogram name help label-names sorted)])
      (when reg (registry-register! reg h))
      h))

  (define (histogram-observe! h v)
    (let* ([bs (%histogram-buckets h)]
           [bv (%histogram-bucket-counts h)]
           [n  (length bs)])
      ;; Prometheus cumulative buckets: for each bucket le_i, if v <= le_i
      ;; then increment that bucket.  +Inf (index n) always gets incremented.
      (let loop ([i 0] [lst bs])
        (unless (null? lst)
          (when (<= v (car lst))
            (vector-set! bv i (+ (vector-ref bv i) 1)))
          (loop (+ i 1) (cdr lst))))
      ;; +Inf always counts
      (vector-set! bv n (+ (vector-ref bv n) 1))
      (%histogram-count-val-set! h (+ (%histogram-count-val h) 1))
      (%histogram-sum-val-set!   h (+ (%histogram-sum-val h) v))))

  (define (histogram-count h) (%histogram-count-val h))
  (define (histogram-sum   h) (%histogram-sum-val h))
  (define (histogram-buckets h)
    ;; Returns alist of (upper-bound . count) including +inf
    (let* ([bs (%histogram-buckets h)]
           [bv (%histogram-bucket-counts h)])
      (let loop ([i 0] [lst bs] [acc '()])
        (if (null? lst)
          (reverse (cons (cons '+inf (vector-ref bv (length bs))) acc))
          (loop (+ i 1) (cdr lst)
                (cons (cons (car lst) (vector-ref bv i)) acc))))))

  ;;; ========== Prometheus text format ==========

  (define (prometheus-format reg . port-opt)
    (let* ([port (if (pair? port-opt) (car port-opt) #f)]
           [out  (open-output-string)])
      (for-each
        (lambda (m)
          (cond
            [(counter? m)   (write-counter   m out)]
            [(gauge? m)     (write-gauge     m out)]
            [(histogram? m) (write-histogram m out)]))
        (registry-collect reg))
      (let ([s (get-output-string out)])
        (when port (display s port))
        s)))

  (define (write-metric-header type m port)
    (fprintf port "# HELP ~a ~a\n# TYPE ~a ~a\n"
      (%counter-name m) ; works for gauge/histogram too via duck
      (metric-help m)
      (metric-name m)
      type))

  (define (metric-name m)
    (cond [(counter?   m) (%counter-name   m)]
          [(gauge?     m) (%gauge-name     m)]
          [(histogram? m) (%histogram-name m)]))

  (define (metric-help m)
    (cond [(counter?   m) (%counter-help   m)]
          [(gauge?     m) (%gauge-help     m)]
          [(histogram? m) (%histogram-help m)]))

  (define (write-counter c port)
    (fprintf port "# HELP ~a ~a\n# TYPE ~a counter\n~a ~a\n"
      (%counter-name c)
      (%counter-help c)
      (%counter-name c)
      (%counter-name c)
      (%counter-value c)))

  (define (write-gauge g port)
    (fprintf port "# HELP ~a ~a\n# TYPE ~a gauge\n~a ~a\n"
      (%gauge-name g)
      (%gauge-help g)
      (%gauge-name g)
      (%gauge-name g)
      (%gauge-value g)))

  (define (write-histogram h port)
    (let ([name (%histogram-name h)])
      (fprintf port "# HELP ~a ~a\n# TYPE ~a histogram\n"
        name (%histogram-help h) name)
      (for-each
        (lambda (bkt)
          (let ([bound (car bkt)]
                [cnt   (cdr bkt)])
            (if (eq? bound '+inf)
              (fprintf port "~a_bucket{le=\"+Inf\"} ~a\n" name cnt)
              (fprintf port "~a_bucket{le=\"~a\"} ~a\n"   name bound cnt))))
        (histogram-buckets h))
      (fprintf port "~a_count ~a\n~a_sum ~a\n"
        name (%histogram-count-val h)
        name (%histogram-sum-val h))))

) ;; end library
