#!chezscheme
;;; (std concur deadlock) — Runtime deadlock detection via wait-for graph
;;;
;;; Maintains two graphs:
;;;   waiting-for  : thread → resource   (what resource is this thread waiting for)
;;;   held-by      : resource → thread   (which thread holds this resource)
;;;
;;; A deadlock cycle exists when following:
;;;   thread A → waits for → resource R1 → held by → thread B
;;;              → waits for → resource R2 → held by → thread A
;;;
;;; detect-deadlock performs DFS on the composed graph to find cycles.

(library (std concur deadlock)
  (export
    ;; Wait-for graph management
    register-waiting!
    unregister-waiting!
    holding-resource!
    releasing-resource!
    ;; Detection
    detect-deadlock
    deadlock?
    ;; Conditions
    make-deadlock-condition
    deadlock-condition?
    deadlock-condition-cycle
    ;; Instrumented synchronization
    deadlock-checked-mutex-lock!
    deadlock-checked-mutex-unlock!
    deadlock-checked-channel-get
    ;; Control
    *deadlock-detection-enabled*
    with-deadlock-detection
    deadlock-detection-report)

  (import (chezscheme))

  ;; ========== Internal graph state ==========

  ;; Protect graph mutations
  (define *graph-mutex* (make-mutex))

  ;; waiting-for: eq-hashtable thread → resource-id
  (define *waiting-for* (make-eq-hashtable))

  ;; held-by: eq-hashtable resource-id → thread
  ;; We use an equal-hash hashtable since resource ids may be any value
  (define *held-by* (make-hashtable equal-hash equal?))

  ;; ========== Thread identity ==========

  ;; get-thread-id returns the current thread's integer id (no-arg form).
  (define (self) (get-thread-id))

  ;; ========== Control parameter ==========

  (define *deadlock-detection-enabled* (make-parameter #t))

  ;; ========== Wait-for graph API ==========

  (define (register-waiting! thread-id resource-id)
    (when (*deadlock-detection-enabled*)
      (with-mutex *graph-mutex*
        (hashtable-set! *waiting-for* thread-id resource-id))))

  (define (unregister-waiting! thread-id)
    (when (*deadlock-detection-enabled*)
      (with-mutex *graph-mutex*
        (hashtable-delete! *waiting-for* thread-id))))

  (define (holding-resource! thread-id resource-id)
    (when (*deadlock-detection-enabled*)
      (with-mutex *graph-mutex*
        (hashtable-set! *held-by* resource-id thread-id))))

  (define (releasing-resource! thread-id resource-id)
    (when (*deadlock-detection-enabled*)
      (with-mutex *graph-mutex*
        ;; Only remove if we actually hold it
        (let ([holder (hashtable-ref *held-by* resource-id #f)])
          (when (eq? holder thread-id)
            (hashtable-delete! *held-by* resource-id))))))

  ;; ========== Cycle detection (DFS) ==========
  ;;
  ;; Graph for DFS: thread → thread
  ;;   edge(A → B) exists when:
  ;;     - A is waiting for resource R  (waiting-for[A] = R)
  ;;     - R is held by B              (held-by[R] = B)
  ;;
  ;; detect-deadlock returns a list of thread-ids forming the cycle, or #f.

  (define (next-thread-for thread)
    ;; Given a thread, follow waiting-for and held-by to find who blocks it.
    (let ([res (hashtable-ref *waiting-for* thread #f)])
      (and res (hashtable-ref *held-by* res #f))))

  (define (detect-deadlock)
    ;; Snapshot threads that are waiting
    (let* ([snapshot
            (with-mutex *graph-mutex*
              (let-values ([(threads _) (hashtable-entries *waiting-for*)])
                (vector->list threads)))]
           [result #f])
      ;; DFS from each waiting thread
      (let try-each ([ts snapshot])
        (unless (or result (null? ts))
          (let ([cycle (find-cycle (car ts))])
            (if cycle
              (set! result cycle)
              (try-each (cdr ts))))))
      result))

  (define (find-cycle start)
    ;; Follow the next-thread chain starting from start.
    ;; If we reach start again, we have a cycle.
    ;; Returns the cycle as a list of thread-ids, or #f.
    (let loop ([current start] [path (list start)] [visited (list start)])
      (let ([next (with-mutex *graph-mutex* (next-thread-for current))])
        (cond
          [(not next) #f]
          [(eq? next start)
           ;; Full cycle back to start
           (reverse (cons next path))]
          [(memq next visited)
           ;; Cycle not through start — still a deadlock
           (let ([cycle-start (memq next (reverse path))])
             (if cycle-start
               (reverse cycle-start)
               (list next)))]
          [else
           (loop next (cons next path) (cons next visited))]))))

  (define (deadlock?)
    (and (detect-deadlock) #t))

  ;; ========== Deadlock condition type ==========

  (define-condition-type &deadlock &serious
    make-deadlock-condition deadlock-condition?
    (cycle deadlock-condition-cycle))

  ;; ========== Instrumented mutex lock/unlock ==========
  ;;
  ;; These wrap Chez's built-in mutex-acquire/mutex-release with wait-for
  ;; graph updates and optional deadlock checking.

  (define (deadlock-checked-mutex-lock! m)
    (let ([tid (self)])
      ;; Register that we're waiting for this mutex
      (register-waiting! tid m)
      ;; Check for deadlock BEFORE blocking
      (when (*deadlock-detection-enabled*)
        (let ([cycle (detect-deadlock)])
          (when cycle
            (unregister-waiting! tid)
            (raise
              (condition
                (make-message-condition "deadlock detected")
                (make-deadlock-condition cycle))))))
      ;; Actually acquire the mutex
      (mutex-acquire m)
      ;; We're no longer waiting; we now hold it
      (unregister-waiting! tid)
      (holding-resource! tid m)))

  (define (deadlock-checked-mutex-unlock! m)
    (let ([tid (self)])
      (releasing-resource! tid m)
      (mutex-release m)))

  ;; ========== Instrumented channel get ==========
  ;;
  ;; For channel-based concurrency, register a symbolic resource id.
  ;; We represent the channel itself as the resource.

  (define (deadlock-checked-channel-get ch)
    (let ([tid (self)])
      (register-waiting! tid ch)
      (let ([cycle (and (*deadlock-detection-enabled*) (detect-deadlock))])
        (when cycle
          (unregister-waiting! tid)
          (raise
            (condition
              (make-message-condition "deadlock detected on channel wait")
              (make-deadlock-condition cycle)))))
      ;; Actual receive — for a bare channel object we just note the wait
      ;; and the caller handles the actual blocking.  Return unblocked
      ;; notification so callers can use this as a guard.
      (unregister-waiting! tid)
      'ok))

  ;; ========== with-deadlock-detection ==========

  (define-syntax with-deadlock-detection
    (syntax-rules ()
      [(_ body ...)
       (parameterize ([*deadlock-detection-enabled* #t])
         body ...)]))

  ;; ========== Human-readable graph dump ==========

  (define (deadlock-detection-report)
    (with-mutex *graph-mutex*
      (let-values ([(wthreads wresources) (hashtable-entries *waiting-for*)]
                   [(hresources hthreads) (hashtable-entries *held-by*)])
        (with-output-to-string
          (lambda ()
            (display "=== Deadlock Detection Graph ===\n")
            (display "Waiting-for (thread → resource):\n")
            (vector-for-each
              (lambda (t r)
                (printf "  ~s → ~s\n" t r))
              wthreads wresources)
            (display "Held-by (resource → thread):\n")
            (vector-for-each
              (lambda (r t)
                (printf "  ~s held by ~s\n" r t))
              hresources hthreads)
            (let ([cycle (detect-deadlock)])
              (if cycle
                (printf "DEADLOCK DETECTED: ~s\n" cycle)
                (display "No deadlock detected.\n"))))))))

  ) ;; end library
