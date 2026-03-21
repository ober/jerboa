#!chezscheme
;;; (std security metrics) — Security metrics and alerting
;;;
;;; Real-time security health indicators with:
;;; - Counters (monotonic increment)
;;; - Gauges (set to current value)
;;; - Histograms (observe values)
;;; - Alerting thresholds with configurable actions

(library (std security metrics)
  (export
    ;; Metrics store
    make-security-metrics
    security-metrics?

    ;; Operations
    metric-increment!
    metric-set!
    metric-observe!
    metric-get

    ;; Alerting
    metric-alert!
    check-alerts!

    ;; Reporting
    metrics-snapshot
    metrics-reset-counters!)

  (import (chezscheme))

  ;; ========== Metrics Store ==========

  (define-record-type (security-metrics %make-security-metrics security-metrics?)
    (sealed #t)
    (fields
      (immutable counters %metrics-counters)       ;; hashtable: name -> count
      (immutable gauges %metrics-gauges)           ;; hashtable: name -> value
      (immutable histograms %metrics-histograms)   ;; hashtable: name -> (list of values)
      (immutable alerts %metrics-alerts)           ;; hashtable: name -> (threshold window action)
      (immutable mutex %metrics-mutex)))

  (define (make-security-metrics)
    (%make-security-metrics
      (make-eq-hashtable)
      (make-eq-hashtable)
      (make-eq-hashtable)
      (make-eq-hashtable)
      (make-mutex)))

  ;; ========== Counter Operations ==========

  (define (metric-increment! metrics name . opts)
    ;; Increment a counter by delta (default 1).
    (let ([delta (if (pair? opts) (car opts) 1)])
      (with-mutex (%metrics-mutex metrics)
        (let ([counters (%metrics-counters metrics)])
          (hashtable-set! counters name
            (+ (hashtable-ref counters name 0) delta))))))

  ;; ========== Gauge Operations ==========

  (define (metric-set! metrics name value)
    ;; Set a gauge to an absolute value.
    (with-mutex (%metrics-mutex metrics)
      (hashtable-set! (%metrics-gauges metrics) name value)))

  ;; ========== Histogram Operations ==========

  (define (metric-observe! metrics name value)
    ;; Record an observation (e.g., latency, size).
    ;; Keeps last 1000 observations per metric.
    (with-mutex (%metrics-mutex metrics)
      (let* ([histograms (%metrics-histograms metrics)]
             [current (hashtable-ref histograms name '())]
             [updated (if (>= (length current) 1000)
                        (cons value (list-head current 999))
                        (cons value current))])
        (hashtable-set! histograms name updated))))

  ;; ========== Get Current Value ==========

  (define (metric-get metrics name)
    ;; Get current value of any metric type.
    ;; Returns: (type . value) or #f
    (with-mutex (%metrics-mutex metrics)
      (cond
        [(hashtable-ref (%metrics-counters metrics) name #f)
         => (lambda (v) (cons 'counter v))]
        [(hashtable-ref (%metrics-gauges metrics) name #f)
         => (lambda (v) (cons 'gauge v))]
        [(hashtable-ref (%metrics-histograms metrics) name #f)
         => (lambda (v) (cons 'histogram v))]
        [else #f])))

  ;; ========== Alerting ==========

  (define (metric-alert! metrics name . opts)
    ;; Set up an alert threshold for a counter.
    ;; Options: threshold: N, window: seconds, action: (lambda (count) ...)
    (let loop ([o opts] [threshold 100] [window 300] [action #f])
      (if (or (null? o) (null? (cdr o)))
        (with-mutex (%metrics-mutex metrics)
          (hashtable-set! (%metrics-alerts metrics) name
            (list threshold window action
                  (time-second (current-time 'time-utc))  ;; window start
                  0)))  ;; window count
        (let ([k (car o)] [v (cadr o)])
          (loop (cddr o)
                (if (eq? k 'threshold:) v threshold)
                (if (eq? k 'window:) v window)
                (if (eq? k 'action:) v action))))))

  (define (check-alerts! metrics)
    ;; Check all alert thresholds. Triggers actions if exceeded.
    (with-mutex (%metrics-mutex metrics)
      (let ([alerts (%metrics-alerts metrics)]
            [counters (%metrics-counters metrics)]
            [now (time-second (current-time 'time-utc))])
        (let-values ([(ks vs) (hashtable-entries alerts)])
          (do ([i 0 (+ i 1)])
              ((= i (vector-length ks)))
            (let* ([name (vector-ref ks i)]
                   [alert (vector-ref vs i)]
                   [threshold (car alert)]
                   [window (cadr alert)]
                   [action (caddr alert)]
                   [window-start (list-ref alert 3)]
                   [count (hashtable-ref counters name 0)])
              ;; Reset window if expired
              (when (> (- now window-start) window)
                (set-car! (cdddr alert) now)
                (set-car! (cddddr alert) 0))
              ;; Check threshold
              (when (and action (>= count threshold))
                (guard (exn [#t (void)])
                  (action count)))))))))

  ;; ========== Reporting ==========

  (define (metrics-snapshot metrics)
    ;; Return an alist of all current metric values.
    (with-mutex (%metrics-mutex metrics)
      (let ([result '()])
        ;; Counters
        (let-values ([(ks vs) (hashtable-entries (%metrics-counters metrics))])
          (do ([i 0 (+ i 1)])
              ((= i (vector-length ks)))
            (set! result (cons (list (vector-ref ks i) 'counter (vector-ref vs i)) result))))
        ;; Gauges
        (let-values ([(ks vs) (hashtable-entries (%metrics-gauges metrics))])
          (do ([i 0 (+ i 1)])
              ((= i (vector-length ks)))
            (set! result (cons (list (vector-ref ks i) 'gauge (vector-ref vs i)) result))))
        ;; Histograms — report count and avg
        (let-values ([(ks vs) (hashtable-entries (%metrics-histograms metrics))])
          (do ([i 0 (+ i 1)])
              ((= i (vector-length ks)))
            (let* ([vals (vector-ref vs i)]
                   [cnt (length vals)]
                   [avg (if (> cnt 0) (/ (apply + vals) cnt) 0)])
              (set! result (cons (list (vector-ref ks i) 'histogram
                                       (list 'count cnt 'avg avg)) result)))))
        result)))

  (define (metrics-reset-counters! metrics)
    ;; Reset all counters to zero.
    (with-mutex (%metrics-mutex metrics)
      (let-values ([(ks vs) (hashtable-entries (%metrics-counters metrics))])
        (do ([i 0 (+ i 1)])
            ((= i (vector-length ks)))
          (hashtable-set! (%metrics-counters metrics) (vector-ref ks i) 0)))))

  ) ;; end library
