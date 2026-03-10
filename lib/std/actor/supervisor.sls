#!chezscheme
;;; (std actor supervisor) — OTP-style supervision trees
;;;
;;; Strategies: one-for-one, one-for-all, rest-for-one
;;; Restart policies: permanent, transient, temporary
;;; Monitors child actors; escalates if restart intensity exceeded.

(library (std actor supervisor)
  (export
    make-child-spec
    child-spec?
    child-spec-id
    child-spec-start-thunk
    child-spec-restart
    child-spec-shutdown
    child-spec-type

    start-supervisor

    supervisor-which-children
    supervisor-count-children
    supervisor-terminate-child!
    supervisor-restart-child!
    supervisor-start-child!
    supervisor-delete-child!
  )
  (import (chezscheme)
          (only (jerboa core) match)
          (std actor core)
          (std actor protocol))

  ;; -------- Child spec --------

  (define-record-type child-spec
    (fields
      (immutable id)           ;; symbol
      (immutable start-thunk)  ;; (lambda () → actor-ref)
      (immutable restart)      ;; 'permanent | 'transient | 'temporary
      (immutable shutdown)     ;; 'brutal-kill | number (seconds)
      (immutable type))        ;; 'worker | 'supervisor
    (sealed #t))

  ;; -------- Runtime child entry --------

  (define-record-type child-entry
    (fields
      (immutable spec)
      (mutable actor-ref)   ;; current actor-ref or #f
      (mutable status))     ;; 'running | 'stopped | 'dead
    (sealed #t))

  ;; -------- Supervisor state (captured in behavior closure) --------

  (define-record-type supervisor-state
    (fields
      (immutable strategy)       ;; 'one-for-one | 'one-for-all | 'rest-for-one
      (immutable max-restarts)
      (immutable period-secs)
      (mutable children)         ;; ordered list of child-entry
      (mutable restart-log))     ;; list of timestamps (floats)
    (sealed #t))

  ;; -------- Time helper (no SRFI-19 needed) --------

  (define (current-seconds)
    (let ([t (current-time)])
      (+ (time-second t) (/ (time-nanosecond t) 1e9))))

  ;; -------- Supervisor startup --------

  (define start-supervisor
    (case-lambda
      [(strategy child-specs)
       (start-supervisor-impl strategy child-specs 10 5)]
      [(strategy child-specs max-restarts)
       (start-supervisor-impl strategy child-specs max-restarts 5)]
      [(strategy child-specs max-restarts period-secs)
       (start-supervisor-impl strategy child-specs max-restarts period-secs)]))

  (define (start-supervisor-impl strategy child-specs max-restarts period-secs)
    (let ([state (make-supervisor-state strategy max-restarts period-secs '() '())])
      (let ([sup (spawn-actor
                   (lambda (msg) (supervisor-behavior state msg))
                   'supervisor)])
        (for-each (lambda (spec) (start-child! state sup spec)) child-specs)
        sup)))

  ;; -------- Start a single child --------

  (define (start-child! state sup spec)
    (let* ([child ((child-spec-start-thunk spec))]
           [entry (make-child-entry spec child 'running)])
      ;; Monitor: supervisor gets 'DOWN when child dies (one-way)
      (actor-ref-monitors-set! child
        (cons (cons sup (child-spec-id spec))
              (actor-ref-monitors child)))
      (supervisor-state-children-set! state
        (append (supervisor-state-children state) (list entry)))
      entry))

  ;; -------- Supervisor behavior --------

  (define (supervisor-behavior state msg)
    (with-ask-context msg
      (lambda (actual)
        (match actual
          [('DOWN spec-id child-id reason)
           (handle-child-exit! state spec-id child-id reason)]

          [('which-children)
           (reply (format-children state))]

          [('terminate-child id)
           (terminate-child-by-id! state id)
           (reply 'ok)]

          [('restart-child id)
           (reply (restart-child-by-id! state id))]

          [('start-child spec)
           (let ([entry (start-child! state (self) spec)])
             (reply (child-entry-actor-ref entry)))]

          [('delete-child id)
           (delete-child-by-id! state id)
           (reply 'ok)]

          [_ (void)]))))

  ;; -------- Handle child exit --------

  (define (handle-child-exit! state spec-id child-id reason)
    (let ([entry (find-child-by-id state spec-id)])
      (when entry
        (let ([spec (child-entry-spec entry)])
          (let ([should-restart?
                 (case (child-spec-restart spec)
                   [(permanent) #t]
                   [(transient) (not (memq reason '(normal killed)))]
                   [(temporary) #f]
                   [else #f])])
            (if should-restart?
              (begin
                (check-restart-intensity! state)
                (case (supervisor-state-strategy state)
                  [(one-for-one) (restart-one! state entry)]
                  [(one-for-all) (restart-all! state)]
                  [(rest-for-one) (restart-rest! state entry)]))
              (child-entry-status-set! entry 'dead)))))))

  ;; -------- Restart intensity --------

  (define (check-restart-intensity! state)
    (let* ([now    (current-seconds)]
           [period (supervisor-state-period-secs state)]
           [recent (filter (lambda (t) (> t (- now period)))
                           (supervisor-state-restart-log state))])
      (supervisor-state-restart-log-set! state (cons now recent))
      (when (>= (length recent) (supervisor-state-max-restarts state))
        (error 'supervisor "restart intensity exceeded"
               (supervisor-state-max-restarts state)
               (supervisor-state-period-secs state)))))

  ;; -------- Restart strategies --------

  ;; NOTE: restart-one!, restart-all!, restart-rest! are called only from
  ;; handle-child-exit!, which runs inside the supervisor actor's behavior.
  ;; (self) correctly returns the supervisor actor-ref in this context.

  (define (restart-one! state entry)
    (stop-child-entry! entry)
    (let* ([spec      (child-entry-spec entry)]
           [new-actor ((child-spec-start-thunk spec))])
      (child-entry-actor-ref-set! entry new-actor)
      (child-entry-status-set!    entry 'running)
      (actor-ref-monitors-set! new-actor
        (cons (cons (self) (child-spec-id spec))
              (actor-ref-monitors new-actor)))))

  (define (restart-all! state)
    (let ([children (supervisor-state-children state)])
      (for-each stop-child-entry! (reverse children))
      (for-each
        (lambda (entry)
          (let* ([spec      (child-entry-spec entry)]
                 [new-actor ((child-spec-start-thunk spec))])
            (child-entry-actor-ref-set! entry new-actor)
            (child-entry-status-set!    entry 'running)
            (actor-ref-monitors-set! new-actor
              (cons (cons (self) (child-spec-id spec))
                    (actor-ref-monitors new-actor)))))
        children)))

  (define (restart-rest! state failed-entry)
    (let* ([children (supervisor-state-children state)]
           [pos (let loop ([cs children] [i 0])
                  (cond [(null? cs) -1]
                        [(eq? (car cs) failed-entry) i]
                        [else (loop (cdr cs) (fx+ i 1))]))]
           [rest (if (fx>= pos 0) (list-tail children pos) '())])
      (for-each stop-child-entry! (reverse rest))
      (for-each
        (lambda (entry)
          (let* ([spec      (child-entry-spec entry)]
                 [new-actor ((child-spec-start-thunk spec))])
            (child-entry-actor-ref-set! entry new-actor)
            (child-entry-status-set!    entry 'running)
            (actor-ref-monitors-set! new-actor
              (cons (cons (self) (child-spec-id spec))
                    (actor-ref-monitors new-actor)))))
        rest)))

  ;; -------- Stop a child --------

  (define (stop-child-entry! entry)
    (let ([a        (child-entry-actor-ref entry)]
          [shutdown (child-spec-shutdown (child-entry-spec entry))])
      (when (and a (actor-alive? a))
        ;; Remove our monitor BEFORE killing so the forced stop does not
        ;; deliver a DOWN message back to this supervisor and trigger a restart.
        (actor-ref-monitors-set! a
          (filter (lambda (mon) (not (eq? (car mon) (self))))
                  (actor-ref-monitors a)))
        (cond
          [(eq? shutdown 'brutal-kill)
           (actor-kill! a)]
          [(number? shutdown)
           ;; Graceful: send 'shutdown, wait, then force-kill
           (guard (exn [#t (void)])
             (send a '(shutdown)))
           (let ([deadline (+ (current-seconds) shutdown)])
             (let loop ()
               (cond
                 [(not (actor-alive? a))  (void)]
                 [(>= (current-seconds) deadline) (actor-kill! a)]
                 [else
                  (sleep (make-time 'time-duration 20000000 0)) ;; 20ms
                  (loop)])))]))
      (child-entry-actor-ref-set! entry #f)
      (child-entry-status-set!    entry 'stopped)))

  ;; -------- Dynamic child management --------

  (define (terminate-child-by-id! state id)
    (let ([entry (find-child-by-id state id)])
      (when entry (stop-child-entry! entry))))

  (define (restart-child-by-id! state id)
    (let ([entry (find-child-by-id state id)])
      (if (and entry (eq? (child-entry-status entry) 'stopped))
        (begin (restart-one! state entry) 'ok)
        'not-found)))

  (define (delete-child-by-id! state id)
    (let ([entry (find-child-by-id state id)])
      (when entry
        (stop-child-entry! entry)
        (supervisor-state-children-set! state
          (filter (lambda (e) (not (eq? e entry)))
                  (supervisor-state-children state))))))

  ;; -------- Public management API --------
  ;; Called from outside the supervisor actor via ask-sync.

  (define (supervisor-which-children sup)
    (ask-sync sup '(which-children)))

  (define (supervisor-count-children sup)
    (let ([children (supervisor-which-children sup)])
      (let loop ([cs children] [total 0] [active 0])
        (if (null? cs)
          (values total active)
          (loop (cdr cs)
                (fx+ total 1)
                (if (eq? (cadr (car cs)) 'running) (fx+ active 1) active))))))

  (define (supervisor-terminate-child! sup id)
    (ask-sync sup (list 'terminate-child id)))

  (define (supervisor-restart-child! sup id)
    (ask-sync sup (list 'restart-child id)))

  (define (supervisor-start-child! sup spec)
    (ask-sync sup (list 'start-child spec)))

  (define (supervisor-delete-child! sup id)
    (ask-sync sup (list 'delete-child id)))

  ;; -------- Helpers --------

  (define (find-child-by-id state id)
    (let loop ([cs (supervisor-state-children state)])
      (cond
        [(null? cs) #f]
        [(eq? (child-spec-id (child-entry-spec (car cs))) id) (car cs)]
        [else (loop (cdr cs))])))

  (define (format-children state)
    (map (lambda (entry)
           (list (child-spec-id   (child-entry-spec entry))
                 (child-entry-status entry)
                 (child-entry-actor-ref entry)))
         (supervisor-state-children state)))

  ) ;; end library
