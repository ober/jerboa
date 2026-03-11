#!chezscheme
;;; (std dev profile) — Built-In Profiler (Step 33)
;;;
;;; Statistical profiler: samples call stack periodically.
;;; Deterministic profiler: instruments specific functions.
;;; Allocation tracker: counts allocations by call site.

(library (std dev profile)
  (export
    ;; Deterministic profiling
    profile-start!
    profile-stop!
    profile-reset!
    profile-results
    profile-report

    ;; Instrument specific functions
    with-profiling
    define/profiled

    ;; Statistical sampling (simulated)
    sample-start!
    sample-stop!
    sample-results

    ;; Allocation profiling
    alloc-profile-start!
    alloc-profile-stop!
    alloc-results

    ;; Timing utilities
    time-call
    time-thunk)

  (import (chezscheme))

  ;; ========== Deterministic Profiler ==========

  ;; Profile entry: (call-count total-ns min-ns max-ns)
  (define *profile-data* (make-eq-hashtable))
  (define *profiling?*   #f)
  (define *profile-mutex* (make-mutex))

  (define (profile-start!)
    (set! *profiling?* #t))

  (define (profile-stop!)
    (set! *profiling?* #f))

  (define (profile-reset!)
    (with-mutex *profile-mutex*
      (let-values ([(keys _) (hashtable-entries *profile-data*)])
        (vector-for-each
          (lambda (k) (hashtable-delete! *profile-data* k))
          keys)))
    (set! *profiling?* #f))

  (define (record-call! name elapsed-ns)
    (when *profiling?*
      (with-mutex *profile-mutex*
        (let ([entry (hashtable-ref *profile-data* name #f)])
          (if entry
            (hashtable-set! *profile-data* name
              (list (+ (car entry) 1)
                    (+ (cadr entry) elapsed-ns)
                    (min (caddr entry) elapsed-ns)
                    (max (cadddr entry) elapsed-ns)))
            (hashtable-set! *profile-data* name
              (list 1 elapsed-ns elapsed-ns elapsed-ns)))))))

  (define (profile-results)
    ;; Returns list of (name calls total-ns avg-ns min-ns max-ns)
    (with-mutex *profile-mutex*
      (let-values ([(names entries) (hashtable-entries *profile-data*)])
        (map (lambda (name entry)
               (list name
                     (car entry)                          ;; calls
                     (cadr entry)                         ;; total-ns
                     (quotient (cadr entry) (car entry))  ;; avg-ns
                     (caddr entry)                        ;; min-ns
                     (cadddr entry)))                     ;; max-ns
             (vector->list names)
             (vector->list entries)))))

  (define (profile-report . port-args)
    (let* ([port (if (null? port-args) (current-output-port) (car port-args))]
           [results (profile-results)]
           [sorted  (list-sort (lambda (a b) (> (caddr a) (caddr b))) results)]
           [total-ns (apply + (map caddr results))])
      (fprintf port "~%Profile Report~%")
      (fprintf port "~a~%" (make-string 60 #\-))
      (fprintf port "~30a ~8a ~10a ~8a~%"
               "Function" "Calls" "Total(ms)" "Avg(μs)")
      (fprintf port "~a~%" (make-string 60 #\-))
      (for-each
        (lambda (r)
          (fprintf port "~30a ~8a ~10,2f ~8,2f~%"
                   (car r)            ;; name
                   (cadr r)           ;; calls
                   (/ (caddr r) 1e6)  ;; total ms
                   (/ (cadddr r) 1e3) ;; avg μs
                   ))
        sorted)
      (fprintf port "~a~%" (make-string 60 #\-))
      (fprintf port "Total: ~,2f ms~%~%" (/ total-ns 1e6))))

  ;; ========== Instrumented Wrappers ==========

  ;; (with-profiling name thunk)
  ;; Executes thunk and records its wall-clock time under name.
  (define (with-profiling name thunk)
    (let* ([start  (current-time 'time-process)]
           [result (thunk)]
           [end    (current-time 'time-process)]
           [ns     (+ (* (- (time-second end) (time-second start)) 1000000000)
                      (- (time-nanosecond end) (time-nanosecond start)))])
      (record-call! name ns)
      result))

  ;; (define/profiled (name arg ...) body ...)
  ;; Defines a function that automatically records profiling data.
  (define-syntax define/profiled
    (syntax-rules ()
      [(_ (name arg ...) body ...)
       (define (name arg ...)
         (with-profiling 'name
           (lambda () body ...)))]))

  ;; ========== Statistical Sampler ==========
  ;;
  ;; Simulated: Since we can't inspect arbitrary thread stacks in portable
  ;; Scheme, we provide a hook-based sampling interface. Real statistical
  ;; profiling would require OS-level signals (SIGPROF).

  (define *sample-data*  (make-eq-hashtable))
  (define *sampling?*    #f)
  (define *sample-thread* #f)

  (define (sample-start! . opts)
    (let ([interval-ms (if (null? opts) 10 (car opts))])
      (set! *sampling?* #t)
      (set! *sample-thread*
        (fork-thread
          (lambda ()
            (let loop ()
              (when *sampling?*
                ;; In a real profiler, we'd inspect thread stacks here
                ;; For now, we just count "ticks"
                (with-mutex *profile-mutex*
                  (let ([count (hashtable-ref *sample-data* '*tick* 0)])
                    (hashtable-set! *sample-data* '*tick* (+ count 1))))
                (sleep (make-time 'time-duration
                         (* interval-ms 1000000) 0))
                (loop))))))))

  (define (sample-stop!)
    (set! *sampling?* #f))

  (define (sample-results)
    (with-mutex *profile-mutex*
      (let-values ([(keys vals) (hashtable-entries *sample-data*)])
        (map cons (vector->list keys) (vector->list vals)))))

  ;; ========== Allocation Profiler ==========

  (define *alloc-data*  (make-eq-hashtable))
  (define *alloc-profiling?* #f)
  (define *alloc-mutex* (make-mutex))

  (define (alloc-profile-start!)
    (set! *alloc-profiling?* #t))

  (define (alloc-profile-stop!)
    (set! *alloc-profiling?* #f))

  (define (track-alloc! site bytes)
    (when *alloc-profiling?*
      (with-mutex *alloc-mutex*
        (let ([entry (hashtable-ref *alloc-data* site #f)])
          (if entry
            (hashtable-set! *alloc-data* site
              (cons (+ (car entry) 1) (+ (cdr entry) bytes)))
            (hashtable-set! *alloc-data* site (cons 1 bytes)))))))

  (define (alloc-results)
    ;; Returns list of (site count total-bytes)
    (with-mutex *alloc-mutex*
      (let-values ([(sites entries) (hashtable-entries *alloc-data*)])
        (map (lambda (site entry)
               (list site (car entry) (cdr entry)))
             (vector->list sites)
             (vector->list entries)))))

  ;; ========== Timing Utilities ==========

  (define-syntax time-call
    ;; (time-call name body ...)
    ;; Times body expressions and prints result.
    (syntax-rules ()
      [(_ name body ...)
       (let* ([start  (current-time 'time-process)]
              [result (begin body ...)]
              [end    (current-time 'time-process)]
              [ns     (+ (* (- (time-second end) (time-second start)) 1000000000)
                         (- (time-nanosecond end) (time-nanosecond start)))])
         (printf "~a: ~,2f ms~%" 'name (/ ns 1e6))
         result)]))

  (define (time-thunk thunk)
    ;; Returns (result elapsed-ns)
    (let* ([start  (current-time 'time-process)]
           [result (thunk)]
           [end    (current-time 'time-process)]
           [ns     (+ (* (- (time-second end) (time-second start)) 1000000000)
                      (- (time-nanosecond end) (time-nanosecond start)))])
      (values result ns)))

  ) ;; end library
