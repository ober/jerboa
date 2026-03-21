#!chezscheme
;;; (std debug contract-monitor) — Runtime contract visualization
;;;
;;; Monitor contract satisfaction across a running system.
;;; Tracks: hot contracts, near-misses, violation log, overhead.
;;;
;;; API:
;;;   (make-contract-monitor)        — create monitor
;;;   (monitor-check! mon name pred val) — check a contract
;;;   (monitor-report mon)           — get summary report
;;;   (monitor-violations mon)       — get violation log
;;;   (monitor-stats mon)            — get per-contract statistics
;;;   (with-monitoring mon thunk)    — run thunk with monitoring active

(library (std debug contract-monitor)
  (export make-contract-monitor monitor-check!
          monitor-report monitor-violations monitor-stats
          with-monitoring monitor-clear!
          monitor-check-count monitor-violation-count)

  (import (chezscheme))

  ;; ========== Monitor ==========

  (define-record-type contract-monitor
    (fields
      (immutable stats)        ;; eq-hashtable: name -> (checks . violations)
      (mutable violations)     ;; list of (name value timestamp)
      (mutable total-checks)
      (mutable total-violations)
      (mutable total-time-ns))
    (protocol
      (lambda (new)
        (lambda () (new (make-eq-hashtable) '() 0 0 0)))))

  (define (monitor-check-count mon) (contract-monitor-total-checks mon))
  (define (monitor-violation-count mon) (contract-monitor-total-violations mon))

  (define (monitor-check! mon name pred val)
    (contract-monitor-total-checks-set! mon
      (+ 1 (contract-monitor-total-checks mon)))
    ;; Update per-contract stats
    (let ([stats (contract-monitor-stats mon)])
      (let ([entry (hashtable-ref stats name #f)])
        (unless entry
          (set! entry (cons 0 0))
          (hashtable-set! stats name entry))
        (set-car! entry (+ 1 (car entry)))
        (let ([ok (pred val)])
          (unless ok
            (set-cdr! entry (+ 1 (cdr entry)))
            (contract-monitor-total-violations-set! mon
              (+ 1 (contract-monitor-total-violations mon)))
            (contract-monitor-violations-set! mon
              (cons (list name val (current-time))
                    (contract-monitor-violations mon))))
          ok))))

  (define (monitor-report mon)
    (list
      (cons 'total-checks (contract-monitor-total-checks mon))
      (cons 'total-violations (contract-monitor-total-violations mon))
      (cons 'contracts (hashtable-size (contract-monitor-stats mon)))))

  (define (monitor-violations mon)
    (reverse (contract-monitor-violations mon)))

  (define (monitor-stats mon)
    (let-values ([(keys vals) (hashtable-entries (contract-monitor-stats mon))])
      (let loop ([i 0] [acc '()])
        (if (= i (vector-length keys))
          acc
          (let ([k (vector-ref keys i)]
                [v (vector-ref vals i)])
            (loop (+ i 1)
                  (cons (list k (car v) (cdr v)) acc)))))))

  (define (monitor-clear! mon)
    (hashtable-clear! (contract-monitor-stats mon))
    (contract-monitor-violations-set! mon '())
    (contract-monitor-total-checks-set! mon 0)
    (contract-monitor-total-violations-set! mon 0))

  ;; ========== Active monitoring ==========

  (define *active-monitor* (make-thread-parameter #f))

  (define (with-monitoring mon thunk)
    (parameterize ([*active-monitor* mon])
      (thunk)))

) ;; end library
