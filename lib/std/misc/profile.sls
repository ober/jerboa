#!chezscheme
;;; (std misc profile) — Lightweight profiling framework
;;;
;;; (define-profiled (fib n)
;;;   (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
;;;
;;; (profile-report)          ; print stats sorted by total time
;;; (profile-data)            ; get stats as alist
;;; (profile-reset!)          ; clear all collected data
;;; (with-profiling body ...) ; profile and report
;;; (time-it expr)            ; returns (values result elapsed-ms)

(library (std misc profile)
  (export define-profiled
          profile-reset!
          profile-report
          profile-data
          with-profiling
          time-it
          profiling-active?)
  (import (chezscheme))

  ;; Global switch — when #f, define-profiled functions run with zero
  ;; overhead (no timing, no hashtable lookup).
  (define profiling-active? (make-parameter #f))

  ;; name → mutable vector #(call-count total-ns min-ns max-ns)
  (define *profile-table* (make-hashtable symbol-hash symbol=?))

  ;; Monotonic clock helpers
  (define (now-ns)
    (let ([t (current-time 'time-monotonic)])
      (+ (* (time-second t) 1000000000)
         (time-nanosecond t))))

  (define (ensure-entry! name)
    (let ([v (hashtable-ref *profile-table* name #f)])
      (or v
          (let ([new (vector 0 0 (greatest-fixnum) 0)])
            (hashtable-set! *profile-table* name new)
            new))))

  (define (record-call! name elapsed-ns)
    (let ([v (ensure-entry! name)])
      (vector-set! v 0 (+ (vector-ref v 0) 1))           ; count
      (vector-set! v 1 (+ (vector-ref v 1) elapsed-ns))   ; total
      (vector-set! v 2 (min (vector-ref v 2) elapsed-ns)) ; min
      (vector-set! v 3 (max (vector-ref v 3) elapsed-ns)))) ; max

  ;; ---- Public API ----

  (define (profile-reset!)
    (hashtable-clear! *profile-table*))

  (define (profile-data)
    ;; Returns: ((name . ((count . N) (total-ms . T) (min-ms . M)
    ;;                     (max-ms . X) (avg-ms . A))) ...)
    ;; Sorted by total-ms descending.
    (let-values ([(keys vals) (hashtable-entries *profile-table*)])
      (let ([entries
             (let loop ([i 0] [acc '()])
               (if (= i (vector-length keys))
                   acc
                   (let* ([name (vector-ref keys i)]
                          [v    (vector-ref vals i)]
                          [cnt  (vector-ref v 0)]
                          [tot  (vector-ref v 1)]
                          [mn   (vector-ref v 2)]
                          [mx   (vector-ref v 3)]
                          [ns->ms (lambda (ns) (/ ns 1000000.0))]
                          [avg  (if (> cnt 0) (/ tot cnt) 0)])
                     (loop (+ i 1)
                           (cons (cons name
                                       (list (cons 'count   cnt)
                                             (cons 'total-ms (ns->ms tot))
                                             (cons 'min-ms   (ns->ms mn))
                                             (cons 'max-ms   (ns->ms mx))
                                             (cons 'avg-ms   (ns->ms avg))))
                                 acc)))))])
        (list-sort (lambda (a b)
                     (> (cdr (assq 'total-ms (cdr a)))
                        (cdr (assq 'total-ms (cdr b)))))
                   entries))))

  (define (profile-report)
    (let ([data (profile-data)])
      (when (null? data)
        (display "No profiling data collected.\n")
        (return))
      (display (format "~a~%"
        "----------------------------------------------------------------------"))
      (display (format "~20a ~8a ~12a ~12a ~12a ~12a~%"
        "Function" "Calls" "Total(ms)" "Avg(ms)" "Min(ms)" "Max(ms)"))
      (display (format "~a~%"
        "----------------------------------------------------------------------"))
      (for-each
        (lambda (entry)
          (let ([name  (car entry)]
                [props (cdr entry)])
            (display (format "~20a ~8d ~12,3f ~12,3f ~12,3f ~12,3f~%"
              name
              (cdr (assq 'count props))
              (cdr (assq 'total-ms props))
              (cdr (assq 'avg-ms props))
              (cdr (assq 'min-ms props))
              (cdr (assq 'max-ms props))))))
        data)
      (display (format "~a~%"
        "----------------------------------------------------------------------"))))

  ;; return is used in profile-report for early exit
  (define-syntax return
    (syntax-rules ()
      [(_) (void)]))

  ;; ---- Macros ----

  (define-syntax define-profiled
    (syntax-rules ()
      [(_ (name args ...) body ...)
       (define name
         (let ([proc (lambda (args ...) body ...)])
           (lambda (args ...)
             (if (profiling-active?)
                 (let ([start (now-ns)])
                   (call-with-values
                     (lambda () (proc args ...))
                     (lambda results
                       (let ([elapsed (- (now-ns) start)])
                         (record-call! 'name elapsed)
                         (apply values results)))))
                 (proc args ...)))))]))

  (define-syntax time-it
    (syntax-rules ()
      [(_ expr)
       (let ([start (now-ns)])
         (call-with-values
           (lambda () expr)
           (lambda results
             (let ([elapsed-ms (/ (- (now-ns) start) 1000000.0)])
               (apply values (append results (list elapsed-ms)))))))]))

  (define-syntax with-profiling
    (syntax-rules ()
      [(_ body ...)
       (begin
         (profile-reset!)
         (parameterize ([profiling-active? #t])
           (let ([result (begin body ...)])
             (profile-report)
             result)))]))

) ;; end library
