#!chezscheme
;;; (std misc pool) — Generic resource pool with mutex + condition variable
;;;
;;; Thread-safe resource pooling. Tracks idle vs in-use resources separately.
;;; Supports optional idle-timeout and acquire-timeout.
;;;
;;; Usage:
;;;   (define p (make-pool (lambda () (open-connection))
;;;                        (lambda (c) (close-connection c))
;;;                        10))            ;; max-size
;;;   (with-resource p (lambda (conn) (query conn "SELECT 1")))

(library (std misc pool)
  (export
    make-pool
    pool?
    pool-acquire
    pool-release
    with-resource
    pool-drain
    pool-stats)

  (import (chezscheme))

  ;; An idle entry: the resource plus the time it became idle.
  (define-record-type idle-entry
    (fields (immutable resource)
            (immutable idle-since)))  ;; (current-time) when released

  ;; The pool record.
  (define-record-type pool-rec
    (fields
      (immutable create-fn)       ;; (-> resource)
      (immutable destroy-fn)      ;; (resource -> void)
      (immutable max-size)        ;; fixnum
      (immutable idle-timeout)    ;; #f or seconds (real number)
      (mutable idle)              ;; list of idle-entry
      (mutable in-use-count)      ;; fixnum: number currently checked out
      (immutable mtx)
      (immutable cv)))

  ;; make-pool: creator, destroyer, max-size, optional idle-timeout
  (define make-pool
    (case-lambda
      [(creator destroyer max-size)
       (make-pool creator destroyer max-size #f)]
      [(creator destroyer max-size idle-timeout)
       (make-pool-rec creator destroyer max-size idle-timeout
                      '() 0 (make-mutex) (make-condition))]))

  (define (pool? x) (pool-rec? x))

  ;; Total resources = idle + in-use
  (define (pool-total p)
    (+ (length (pool-rec-idle p)) (pool-rec-in-use-count p)))

  ;; Evict expired idle entries (must be called under mutex).
  (define (evict-expired! p)
    (let ([timeout (pool-rec-idle-timeout p)])
      (when timeout
        (let ([now (current-time 'time-monotonic)])
          (let loop ([entries (pool-rec-idle p)]
                     [kept '()])
            (cond
              [(null? entries)
               (pool-rec-idle-set! p (reverse kept))]
              [else
               (let* ([e (car entries)]
                      [elapsed (time-difference now (idle-entry-idle-since e))])
                 (if (>= (+ (time-second elapsed)
                             (/ (time-nanosecond elapsed) 1000000000.0))
                         timeout)
                     ;; Expired — destroy it
                     (begin
                       ((pool-rec-destroy-fn p) (idle-entry-resource e))
                       (loop (cdr entries) kept))
                     ;; Still valid
                     (loop (cdr entries) (cons e kept))))]))))))

  ;; pool-acquire: get a resource, optionally with a timeout in seconds.
  ;; Returns a resource, or #f if the timeout expired.
  (define pool-acquire
    (case-lambda
      [(p) (pool-acquire p #f)]
      [(p timeout)
       (mutex-acquire (pool-rec-mtx p))
       (evict-expired! p)
       (let ([deadline (and timeout
                            (let ([now (current-time 'time-utc)])
                              (add-duration now
                                (make-time 'time-duration
                                           (exact (truncate (* (- timeout (truncate timeout))
                                                               1000000000)))
                                           (exact (truncate timeout))))))])
         (let loop ()
           (cond
             ;; Idle resource available
             [(pair? (pool-rec-idle p))
              (let* ([entry (car (pool-rec-idle p))]
                     [r (idle-entry-resource entry)])
                (pool-rec-idle-set! p (cdr (pool-rec-idle p)))
                (pool-rec-in-use-count-set! p (+ (pool-rec-in-use-count p) 1))
                (mutex-release (pool-rec-mtx p))
                r)]
             ;; Room to create a new one
             [(< (pool-total p) (pool-rec-max-size p))
              (pool-rec-in-use-count-set! p (+ (pool-rec-in-use-count p) 1))
              (mutex-release (pool-rec-mtx p))
              ;; Create outside the lock to avoid holding it during I/O
              ((pool-rec-create-fn p))]
             ;; Pool full — must wait
             [else
              (if deadline
                  ;; Timed wait
                  (let ([ok (condition-wait (pool-rec-cv p) (pool-rec-mtx p)
                                            deadline)])
                    (if ok
                        (loop)  ;; signaled, try again
                        ;; Timeout: one last check before giving up
                        (if (pair? (pool-rec-idle p))
                            (let* ([entry (car (pool-rec-idle p))]
                                   [r (idle-entry-resource entry)])
                              (pool-rec-idle-set! p (cdr (pool-rec-idle p)))
                              (pool-rec-in-use-count-set! p
                                (+ (pool-rec-in-use-count p) 1))
                              (mutex-release (pool-rec-mtx p))
                              r)
                            (begin
                              (mutex-release (pool-rec-mtx p))
                              #f))))
                  ;; No timeout — block indefinitely
                  (begin
                    (condition-wait (pool-rec-cv p) (pool-rec-mtx p))
                    (loop)))])))]))

  ;; pool-release: return a resource to the pool.
  (define (pool-release p resource)
    (mutex-acquire (pool-rec-mtx p))
    (pool-rec-in-use-count-set! p (max 0 (- (pool-rec-in-use-count p) 1)))
    (pool-rec-idle-set! p
      (cons (make-idle-entry resource (current-time 'time-monotonic))
            (pool-rec-idle p)))
    (condition-signal (pool-rec-cv p))
    (mutex-release (pool-rec-mtx p)))

  ;; with-resource: acquire, run body, release even on exception.
  (define-syntax with-resource
    (syntax-rules ()
      [(_ pool (var) body ...)
       (let ([p pool]
             [r #f])
         (dynamic-wind
           (lambda () (set! r (pool-acquire p)))
           (lambda () (let ([var r]) body ...))
           (lambda () (when r (pool-release p r)))))]))

  ;; pool-drain: destroy all idle resources.
  (define (pool-drain p)
    (mutex-acquire (pool-rec-mtx p))
    (let ([entries (pool-rec-idle p)])
      (pool-rec-idle-set! p '())
      (mutex-release (pool-rec-mtx p))
      ;; Destroy outside the lock
      (for-each (lambda (e) ((pool-rec-destroy-fn p) (idle-entry-resource e)))
                entries)))

  ;; pool-stats: return alist of counts.
  (define (pool-stats p)
    (mutex-acquire (pool-rec-mtx p))
    (evict-expired! p)
    (let ([idle-count (length (pool-rec-idle p))]
          [in-use (pool-rec-in-use-count p)])
      (mutex-release (pool-rec-mtx p))
      `((total . ,(+ idle-count in-use))
        (idle . ,idle-count)
        (in-use . ,in-use))))

) ;; end library
