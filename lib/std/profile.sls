#!chezscheme
;;; (std profile) — Profiling utilities
;;;
;;; Wraps Chez's profiling and timing infrastructure.
;;;
;;; (with-profile (lambda () (fib 30)))
;;; => (values result '((wall-ms . 45) (cpu-ms . 44) (bytes . 1024)))

(library (std profile)
  (export with-profile profile-stats time-it
          allocation-count with-timing)

  (import (chezscheme))

  ;; Profile a thunk — returns (values result stats-alist)
  (define (with-profile thunk)
    (let* ([t0 (current-time 'time-monotonic)]
           [cpu0 (current-time 'time-thread)]
           [bytes0 (bytes-allocated)]
           [result (thunk)]
           [bytes1 (bytes-allocated)]
           [cpu1 (current-time 'time-thread)]
           [t1 (current-time 'time-monotonic)])
      (values result
              `((wall-ms . ,(time-diff-ms t0 t1))
                (cpu-ms . ,(time-diff-ms cpu0 cpu1))
                (bytes-allocated . ,(- bytes1 bytes0))))))

  (define (time-diff-ms t0 t1)
    (let ([s0 (time-second t0)]
          [ns0 (time-nanosecond t0)]
          [s1 (time-second t1)]
          [ns1 (time-nanosecond t1)])
      (+ (* (- s1 s0) 1000)
         (quotient (- ns1 ns0) 1000000))))

  ;; Dump profile data as alist
  (define (profile-stats thunk)
    (let-values ([(result stats) (with-profile thunk)])
      stats))

  ;; Simple timing with display
  (define (time-it label thunk)
    (let-values ([(result stats) (with-profile thunk)])
      (let ([wall (cdr (assq 'wall-ms stats))]
            [cpu (cdr (assq 'cpu-ms stats))]
            [bytes (cdr (assq 'bytes-allocated stats))])
        (printf "~a: ~ams (~ams cpu, ~a bytes allocated)~n"
                label wall cpu bytes))
      result))

  ;; Count bytes allocated during thunk
  (define (allocation-count thunk)
    (collect (collect-maximum-generation))
    (let ([before (bytes-allocated)])
      (thunk)
      (- (bytes-allocated) before)))

  ;; with-timing: returns (values result elapsed-ms)
  (define (with-timing thunk)
    (let* ([t0 (current-time 'time-monotonic)]
           [result (thunk)]
           [t1 (current-time 'time-monotonic)])
      (values result (time-diff-ms t0 t1))))

) ;; end library
