#!chezscheme
;;; (std proc supervisor) — OTP-Style Process Supervisor
;;;
;;; Monitors child threads. When a child dies unexpectedly, applies a
;;; restart strategy. Three strategies:
;;;   one-for-one  — restart only the failed child
;;;   one-for-all  — restart all children when any fails
;;;   rest-for-one — restart the failed child + all started after it
;;;
;;; Child specs describe how to start/restart a child.
;;;
;;; API:
;;;   (child-spec id thunk [restart-type [max-restarts [restart-window]]])
;;;   (make-supervisor strategy [max-restarts [restart-window]])
;;;   (supervisor-start-child! sup spec)
;;;   (supervisor-stop-child! sup id)
;;;   (supervisor-restart-child! sup id)
;;;   (supervisor-children sup) → list of child-info
;;;   (supervisor-run! sup) → starts supervisor monitoring loop
;;;   (supervisor-stop! sup) → stops supervisor and all children
;;;   (one-for-one) (one-for-all) (rest-for-one) → strategy constants

(library (std proc supervisor)
  (export
    make-supervisor
    supervisor?
    supervisor-running?
    supervisor-start-child!
    supervisor-stop-child!
    supervisor-restart-child!
    supervisor-children
    supervisor-run!
    supervisor-stop!
    child-spec
    child-spec?
    child-spec-id
    child-spec-thunk
    child-spec-restart-type
    child-spec-max-restarts
    child-spec-restart-window
    one-for-one
    one-for-all
    rest-for-one)

  (import (chezscheme) (std misc channel))

  ;; ========== Strategy Constants ==========

  (define one-for-one  'one-for-one)
  (define one-for-all  'one-for-all)
  (define rest-for-one 'rest-for-one)

  ;; ========== Child Spec ==========

  (define-record-type (%child-spec %make-child-spec child-spec?)
    (fields
      (immutable id    child-spec-id)
      (immutable thunk child-spec-thunk)
      (immutable restart-type  child-spec-restart-type)
      (immutable max-restarts  child-spec-max-restarts)
      (immutable restart-window child-spec-restart-window)))

  ;; Public constructor with defaults
  (define child-spec
    (case-lambda
      [(id thunk)
       (%make-child-spec id thunk 'permanent 3 60)]
      [(id thunk restart-type)
       (%make-child-spec id thunk restart-type 3 60)]
      [(id thunk restart-type max-restarts restart-window)
       (%make-child-spec id thunk restart-type max-restarts restart-window)]))

  ;; ========== Child Info (runtime state) ==========

  (define-record-type child-info
    (fields
      spec                    ;; child-spec-rec
      (mutable thread-id)     ;; Chez thread id (from fork-thread)
      (mutable status)        ;; 'running | 'stopped | 'failed
      (mutable restart-count) ;; how many times restarted
      (mutable last-restart)  ;; timestamp of last restart
      done-mutex              ;; for join-like behavior
      done-cond
      (mutable exit-value)    ;; #f or exn on failure
      (mutable alive?))       ;; thread still running?
    (protocol
      (lambda (new)
        (lambda (spec)
          (new spec #f 'stopped 0 0
               (make-mutex) (make-condition)
               #f #f)))))

  ;; ========== Supervisor ==========

  (define-record-type (supervisor %make-supervisor supervisor?)
    (fields
      strategy            ;; 'one-for-one | 'one-for-all | 'rest-for-one
      max-restarts        ;; max restarts in window before crash
      restart-window      ;; window in seconds
      (mutable child-list)  ;; list of child-info in start order
      (mutable running?)
      mutex               ;; protects children list
      monitor-ch))        ;; channel for death notifications

  (define (make-supervisor strategy . opts)
    (let ([max-r (if (pair? opts) (car opts) 10)]
          [window (if (and (pair? opts) (pair? (cdr opts))) (cadr opts) 60)])
      (%make-supervisor strategy max-r window
                        '() #f (make-mutex)
                        ;; We use a simple channel for exit notifications
                        (make-channel 64))))

  ;; ========== Starting Children ==========

  (define (start-child-thread! sup info)
    (let* ([spec (child-info-spec info)]
           [thunk (child-spec-thunk spec)]
           [mon-ch (supervisor-monitor-ch sup)])
      (child-info-status-set! info 'running)
      (child-info-alive?-set! info #t)
      (fork-thread
        (lambda ()
          (let ([result
                 (call-with-current-continuation
                   (lambda (k)
                     (with-exception-handler
                       (lambda (exn)
                         (k (cons 'failed exn)))
                       (lambda ()
                         (thunk)
                         (cons 'exited #f)))))])
            (child-info-alive?-set! info #f)
            (child-info-exit-value-set! info (cdr result))
            ;; Notify supervisor
            (channel-put mon-ch (cons info (car result))))))))

  (define (supervisor-start-child! sup spec)
    (let ([info (make-child-info spec)])
      (mutex-acquire (supervisor-mutex sup))
      (supervisor-child-list-set! sup
        (append (supervisor-child-list sup) (list info)))
      (mutex-release (supervisor-mutex sup))
      (start-child-thread! sup info)
      info))

  ;; ========== Stopping Children ==========

  (define (stop-child-thread! info)
    ;; We can't kill threads in Chez, but we mark them stopped.
    ;; The thread will eventually finish on its own.
    ;; In production, use thread interrupts or a stop channel per child.
    (child-info-status-set! info 'stopped)
    (child-info-alive?-set! info #f))

  (define (supervisor-stop-child! sup id)
    (mutex-acquire (supervisor-mutex sup))
    (let ([info (find-child sup id)])
      (when info (stop-child-thread! info)))
    (mutex-release (supervisor-mutex sup)))

  (define (find-child sup id)
    (let loop ([children (supervisor-child-list sup)])
      (cond
        [(null? children) #f]
        [(equal? (child-spec-id (child-info-spec (car children))) id)
         (car children)]
        [else (loop (cdr children))])))

  ;; ========== Restarting ==========

  (define (maybe-restart! sup info exit-type)
    (let* ([spec (child-info-spec info)]
           [restart-type (child-spec-restart-type spec)])
      (cond
        ;; temporary: never restart
        [(eq? restart-type 'temporary)
         (child-info-status-set! info 'stopped)]
        ;; transient: only restart on failure
        [(and (eq? restart-type 'transient) (eq? exit-type 'exited))
         (child-info-status-set! info 'stopped)]
        ;; permanent or transient+failed: restart
        [else
         (let ([count (child-info-restart-count info)])
           (if (>= count (child-spec-max-restarts spec))
             ;; Too many restarts — give up
             (begin
               (child-info-status-set! info 'failed)
               (when (supervisor-running? sup)
                 (display
                   (string-append "supervisor: child "
                     (if (symbol? (child-spec-id spec))
                       (symbol->string (child-spec-id spec))
                       (child-spec-id spec))
                     " exceeded max restarts, not restarting\n"))))
             ;; Restart
             (begin
               (child-info-restart-count-set! info (+ count 1))
               (child-info-last-restart-set! info
                 (time-second (current-time 'time-monotonic)))
               (start-child-thread! sup info))))])))

  (define (apply-strategy! sup failed-info exit-type)
    (let ([strategy (supervisor-strategy sup)])
      (cond
        [(eq? strategy one-for-one)
         (maybe-restart! sup failed-info exit-type)]
        [(eq? strategy one-for-all)
         ;; Stop all, restart all
         (for-each
           (lambda (info)
             (unless (eq? info failed-info)
               (stop-child-thread! info)))
           (supervisor-child-list sup))
         (for-each
           (lambda (info)
             (maybe-restart! sup info exit-type))
           (supervisor-child-list sup))]
        [(eq? strategy rest-for-one)
         ;; Find position of failed child, restart it + all after it
         (let ([children (supervisor-child-list sup)])
           (let loop ([remaining children] [found? #f])
             (unless (null? remaining)
               (let ([info (car remaining)])
                 (if (or found? (eq? info failed-info))
                   (begin
                     (unless (eq? info failed-info)
                       (stop-child-thread! info))
                     (maybe-restart! sup info exit-type)
                     (loop (cdr remaining) #t))
                   (loop (cdr remaining) #f))))))])))

  ;; ========== Restart ==========

  (define (supervisor-restart-child! sup id)
    (mutex-acquire (supervisor-mutex sup))
    (let ([info (find-child sup id)])
      (when info
        (start-child-thread! sup info)))
    (mutex-release (supervisor-mutex sup)))

  ;; ========== Children Inspection ==========

  (define (supervisor-children sup)
    (supervisor-child-list sup))

  ;; ========== Supervisor Lifecycle ==========

  (define (supervisor-run! sup)
    (supervisor-running?-set! sup #t)
    ;; Monitor loop runs in a thread
    (fork-thread
      (lambda ()
        (let loop ()
          (when (supervisor-running? sup)
            (let ([notification
                   ;; Wait for a child exit notification
                   (let wait ()
                     (let-values ([(val ok)
                                   (channel-try-get (supervisor-monitor-ch sup))])
                       (if ok
                         val
                         (begin
                           ;; Poll with small sleep
                           (sleep (make-time 'time-duration 10000000 0))
                           (wait)))))])
              (when notification
                (let ([info (car notification)]
                      [exit-type (cdr notification)])
                  (when (supervisor-running? sup)
                    (mutex-acquire (supervisor-mutex sup))
                    (apply-strategy! sup info exit-type)
                    (mutex-release (supervisor-mutex sup))))))
            (loop)))))
    sup)

  (define (supervisor-stop! sup)
    (supervisor-running?-set! sup #f)
    (mutex-acquire (supervisor-mutex sup))
    (for-each stop-child-thread! (supervisor-child-list sup))
    (mutex-release (supervisor-mutex sup)))

) ;; end library
