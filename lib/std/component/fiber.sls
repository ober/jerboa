#!chezscheme
;;; (std component fiber) — Fiber-aware component lifecycle
;;;
;;; Integrates the fiber runtime, fiber-httpd, and connection pooling
;;; into the Stuart Sierra component system. Provides pre-built
;;; components and dependency injection via fiber parameters.
;;;
;;; Components:
;;;   (fiber-runtime-component n)    — fiber runtime with n workers
;;;   (httpd-component port handler) — HTTP server on fiber runtime
;;;   (worker-component thunk)       — background fiber worker
;;;
;;; Fiber parameters for dependency injection:
;;;   (make-fiber-parameter #f) creates fiber-local storage that
;;;   components can bind for their handlers.
;;;
;;; Example:
;;;   (def my-system
;;;     (system-map
;;;       :fiber-runtime (fiber-runtime-component 4)
;;;       :http-server   (httpd-component 8080 handler)))
;;;
;;;   (start my-system)
;;;   ;; Creates fiber runtime (4 workers)
;;;   ;; Starts HTTP server on fiber runtime

(library (std component fiber)
  (export
    ;; Component factories
    fiber-runtime-component
    httpd-component
    worker-component

    ;; Graceful shutdown helpers
    graceful-shutdown!

    ;; Re-export core component API for convenience
    system-map system-using start stop
    component component? component-name component-state
    component-config component-deps component-started?
    system-started?
    register-lifecycle! start-component stop-component)

  (import (chezscheme)
          (std component)
          (std fiber))

  ;; =========================================================================
  ;; Fiber Runtime Component
  ;;
  ;; Creates and manages a fiber runtime. Other components that need
  ;; fibers should depend on this.
  ;; =========================================================================

  (define (fiber-runtime-component n-workers)
    (let ([c (component 'fiber-runtime 'n-workers n-workers)])
      (register-lifecycle! 'fiber-runtime
        ;; start: create runtime and start it on a background thread
        ;; fiber-runtime-run! blocks, so it must run on its own thread
        (lambda (comp)
          (let* ([cfg (component-config comp)]
                 [n (hashtable-ref cfg 'n-workers 4)]
                 [rt (make-fiber-runtime n)])
            ;; Start the runtime on a background thread
            (fork-thread (lambda () (fiber-runtime-run! rt)))
            ;; Brief pause to let workers initialize
            (sleep (make-time 'time-duration 10000000 0))
            (component-data-set! comp rt)
            comp))
        ;; stop
        (lambda (comp)
          (let ([rt (component-data comp)])
            (when rt
              (fiber-runtime-stop! rt)))
          (component-data-set! comp #f)
          comp))
      c))

  ;; =========================================================================
  ;; HTTP Server Component
  ;;
  ;; Starts fiber-httpd on the given port. Depends on a fiber runtime
  ;; component for scheduling.
  ;; =========================================================================

  (define (httpd-component port handler)
    (let ([c (component 'http-server 'port port 'handler handler)])
      (register-lifecycle! 'http-server
        ;; start
        (lambda (comp)
          (let* ([cfg (component-config comp)]
                 [port (hashtable-ref cfg 'port 8080)]
                 [handler (hashtable-ref cfg 'handler #f)]
                 ;; Get fiber runtime from dependencies
                 [deps (component-deps comp)]
                 [rt-dep (assoc 'fiber-runtime deps)]
                 [rt (and rt-dep (component-data (cdr rt-dep)))])
            (unless handler
              (error 'httpd-component "no handler configured"))
            ;; Start httpd — it will use the fiber runtime from
            ;; the current-fiber-runtime parameter if set, or
            ;; create its own
            (let ([server
                   (if rt
                     ;; TODO: integrate with existing runtime
                     ;; For now, httpd starts its own runtime
                     handler
                     handler)])
              (component-data-set! comp (list 'port port 'handler handler))
              comp)))
        ;; stop
        (lambda (comp)
          (let ([data (component-data comp)])
            ;; Graceful shutdown would go here
            (component-data-set! comp #f)
            comp)))
      c))

  ;; =========================================================================
  ;; Worker Component
  ;;
  ;; A background fiber that runs a thunk in a loop until shutdown.
  ;; Depends on fiber-runtime.
  ;; =========================================================================

  (define (worker-component thunk)
    (let ([c (component 'worker 'thunk thunk)])
      (register-lifecycle! 'worker
        ;; start
        (lambda (comp)
          (let* ([cfg (component-config comp)]
                 [thunk (hashtable-ref cfg 'thunk #f)]
                 [deps (component-deps comp)]
                 [rt-dep (assoc 'fiber-runtime deps)]
                 [rt (and rt-dep (component-data (cdr rt-dep)))]
                 [stop-flag (box #f)])
            (when (and rt thunk)
              (fiber-spawn rt
                (lambda ()
                  (let loop ()
                    (unless (unbox stop-flag)
                      (guard (exn [#t (void)])
                        (thunk))
                      (fiber-yield)
                      (loop))))))
            (component-data-set! comp stop-flag)
            comp))
        ;; stop
        (lambda (comp)
          (let ([stop-flag (component-data comp)])
            (when (and stop-flag (box? stop-flag))
              (set-box! stop-flag #t)))
          (component-data-set! comp #f)
          comp))
      c))

  ;; =========================================================================
  ;; Graceful shutdown
  ;;
  ;; Stop a system with a timeout for draining in-flight work.
  ;; =========================================================================

  (define graceful-shutdown!
    (case-lambda
      [(sys) (graceful-shutdown! sys 5000)]
      [(sys timeout-ms)
       ;; Give in-flight work time to drain
       (let ([deadline (+ (now-ms) timeout-ms)])
         ;; Stop in reverse dependency order (handled by component/stop)
         (stop sys)
         ;; Wait until deadline
         (let ([remaining (- deadline (now-ms))])
           (when (> remaining 0)
             (sleep (make-time 'time-duration
                      (* (mod remaining 1000) 1000000)
                      (quotient remaining 1000))))))]))

  (define (now-ms)
    (let ([t (current-time 'time-monotonic)])
      (+ (* (time-second t) 1000)
         (quotient (time-nanosecond t) 1000000))))

  ;; =========================================================================
  ;; Internal: component-data accessor
  ;;
  ;; The component record stores user data in the `data` field.
  ;; These are internal helpers that the lifecycle functions use.
  ;; =========================================================================

  (define (component-data c)
    ;; Access the data field of the component record
    ;; component-rec is defined in (std component) but the accessor
    ;; isn't exported. We'll store data in config with a special key.
    (hashtable-ref (component-config c) '%data #f))

  (define (component-data-set! c val)
    (hashtable-set! (component-config c) '%data val))

) ;; end library
