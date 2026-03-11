#!chezscheme
;;; Tests for (std metrics) -- Metrics collection

(import (chezscheme)
        (std metrics))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(define (string-contains? str sub)
  (let ([slen (string-length str)]
        [sublen (string-length sub)])
    (if (> sublen slen) #f
      (let loop ([i 0])
        (cond
          [(> (+ i sublen) slen) #f]
          [(string=? (substring str i (+ i sublen)) sub) #t]
          [else (loop (+ i 1))])))))

(printf "--- Phase 3a: Metrics ---~%~%")

;;; ======== Registry ========

(test "registry? true"
  (registry? (make-registry))
  #t)

(test "registry? false"
  (registry? 42)
  #f)

(test "empty registry collects nothing"
  (registry-collect (make-registry))
  '())

;;; ======== Counter ========

(let* ([reg (make-registry)]
       [c   (make-counter reg "requests_total" "Total requests")])

  (test "counter? true"
    (counter? c)
    #t)

  (test "counter? false"
    (counter? "not-a-counter")
    #f)

  (test "counter initial value"
    (counter-value c)
    0)

  (counter-inc! c)
  (test "counter after inc"
    (counter-value c)
    1)

  (counter-inc! c)
  (counter-inc! c)
  (test "counter after 3 incs"
    (counter-value c)
    3)

  (counter-add! c 10)
  (test "counter after add 10"
    (counter-value c)
    13)

  (test "counter in registry"
    (length (registry-collect reg))
    1)

  (test "counter-add! negative raises"
    (guard (exn [(message-condition? exn) 'error])
      (counter-add! c -1))
    'error))

;;; ======== Gauge ========

(let* ([reg (make-registry)]
       [g   (make-gauge reg "temperature" "Current temperature")])

  (test "gauge? true"
    (gauge? g)
    #t)

  (test "gauge initial value"
    (gauge-value g)
    0)

  (gauge-set! g 42)
  (test "gauge after set"
    (gauge-value g)
    42)

  (gauge-inc! g)
  (test "gauge after inc"
    (gauge-value g)
    43)

  (gauge-inc! g 5)
  (test "gauge after inc 5"
    (gauge-value g)
    48)

  (gauge-dec! g)
  (test "gauge after dec"
    (gauge-value g)
    47)

  (gauge-dec! g 7)
  (test "gauge after dec 7"
    (gauge-value g)
    40)

  (gauge-set! g -10)
  (test "gauge can go negative"
    (gauge-value g)
    -10))

;;; ======== Histogram ========

(let* ([reg (make-registry)]
       [h   (make-histogram reg "latency_seconds" "Request latency"
                            '() '(0.1 0.5 1.0 5.0))])

  (test "histogram? true"
    (histogram? h)
    #t)

  (test "histogram initial count"
    (histogram-count h)
    0)

  (test "histogram initial sum"
    (histogram-sum h)
    0)

  (histogram-observe! h 0.05)
  (test "histogram count after 1 observe"
    (histogram-count h)
    1)

  (test "histogram sum after 0.05"
    (histogram-sum h)
    0.05)

  (histogram-observe! h 0.3)
  (histogram-observe! h 2.0)

  (test "histogram count after 3 observes"
    (histogram-count h)
    3)

  (test "histogram sum after 3 observes"
    (histogram-sum h)
    (+ 0.05 0.3 2.0))

  (let ([bkts (histogram-buckets h)])
    (test "histogram buckets include +inf"
      (assq '+inf bkts)
      (cons '+inf 3))

    ;; 0.05 falls in le=0.1 bucket
    (test "histogram bucket 0.1 has 1 (0.05 obs)"
      (cdr (assv 0.1 bkts))
      1)))

;;; ======== Prometheus format ========

(let* ([reg (make-registry)]
       [c   (make-counter reg "http_requests" "HTTP request count")]
       [g   (make-gauge   reg "active_conns"  "Active connections")]
       [h   (make-histogram reg "rtt_ms" "Round-trip time ms"
                            '() '(1 5 10))])
  (counter-add! c 7)
  (gauge-set! g 3)
  (histogram-observe! h 2)
  (histogram-observe! h 8)

  (let ([out (prometheus-format reg)])
    (test "prometheus output non-empty"
      (> (string-length out) 0)
      #t)

    (test "prometheus contains counter TYPE"
      (string-contains? out "# TYPE http_requests counter")
      #t)

    (test "prometheus contains counter value"
      (string-contains? out "http_requests 7")
      #t)

    (test "prometheus contains gauge TYPE"
      (string-contains? out "# TYPE active_conns gauge")
      #t)

    (test "prometheus contains histogram TYPE"
      (string-contains? out "# TYPE rtt_ms histogram")
      #t)))

;;; Summary

(printf "~%Metrics tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
