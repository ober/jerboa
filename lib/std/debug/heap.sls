#!chezscheme
;;; (std debug heap) — Heap introspection and GC statistics
;;;
;;; Uses Chez Scheme's built-in procedures: bytes-allocated, collections,
;;; collect-maximum-generation, collect, statistics/sstats, and timing.

(library (std debug heap)
  (export heap-size gc-count gc-time-ms gc-collect-and-report
          object-counts with-gc-stats heap-report)

  (import (except (chezscheme) object-counts))

  ;; Current heap size in bytes.
  (define (heap-size)
    (bytes-allocated))

  ;; Total GC collections performed.
  (define (gc-count)
    (collections))

  ;; Total GC time in milliseconds.
  ;; Uses sstats-gc-real from (statistics) which returns a time object.
  (define (gc-time-ms)
    (let* ([s (statistics)]
           [gc-real (sstats-gc-real s)])
      (+ (* (time-second gc-real) 1000)
         (quotient (time-nanosecond gc-real) 1000000))))

  ;; Force a full GC and report bytes freed and collection count delta.
  (define (gc-collect-and-report)
    (let ([before-bytes (bytes-allocated)]
          [before-count (collections)])
      (collect (collect-maximum-generation))
      (let ([after-bytes (bytes-allocated)]
            [after-count (collections)])
        (list
          (cons 'freed-bytes (- before-bytes after-bytes))
          (cons 'bytes-before before-bytes)
          (cons 'bytes-after after-bytes)
          (cons 'collections-triggered (- after-count before-count))))))

  ;; Approximate object counts by type.
  ;; Uses Chez's object-counts (excluded from import to avoid name conflict,
  ;; accessed via top-level-value).
  (define (object-counts)
    (guard (exn [else '()])
      (let ([oc (top-level-value 'object-counts)])
        (if (procedure? oc)
            (let ([counts (oc)])
              (if (list? counts) counts '()))
            '()))))

  ;; Run a thunk and return (values result stats-alist) with GC metrics.
  (define (with-gc-stats thunk)
    (collect (collect-maximum-generation))
    (let ([before-bytes (bytes-allocated)]
          [before-gc (collections)]
          [before-time (current-time 'time-monotonic)])
      (let ([result (thunk)])
        (let ([after-bytes (bytes-allocated)]
              [after-gc (collections)]
              [after-time (current-time 'time-monotonic)])
          (let ([elapsed-ns (+ (* (- (time-second after-time)
                                     (time-second before-time))
                                  1000000000)
                               (- (time-nanosecond after-time)
                                  (time-nanosecond before-time)))])
            (values result
                    (list
                      (cons 'bytes-before before-bytes)
                      (cons 'bytes-after after-bytes)
                      (cons 'bytes-delta (- after-bytes before-bytes))
                      (cons 'gc-collections (- after-gc before-gc))
                      (cons 'elapsed-ms (inexact->exact
                                          (round (/ elapsed-ns 1000000)))))))))))

  ;; Print a formatted heap report to current-output-port.
  (define (heap-report)
    (let ([bytes (heap-size)]
          [gcs (gc-count)]
          [gc-ms (gc-time-ms)]
          [max-gen (collect-maximum-generation)])
      (display "=== Heap Report ===\n")
      (display (format "  Heap size:       ~a bytes (~a MB)\n"
                       bytes (quotient bytes (* 1024 1024))))
      (display (format "  Total GC count:  ~a\n" gcs))
      (display (format "  GC time:         ~a ms\n" gc-ms))
      (display (format "  Max generation:  ~a\n" max-gen))
      ;; Object counts if available
      (let ([counts (object-counts)])
        (unless (null? counts)
          (display (format "  Object type count: ~a types tracked\n"
                           (length counts)))))
      (display "===================\n")))

) ;; end library
