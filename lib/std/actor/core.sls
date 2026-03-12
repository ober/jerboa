#!chezscheme
;;; (std actor core) — Actor spawn, send, lifecycle, links, monitors
;;;
;;; Actors run in 1:1 OS thread mode by default.
;;; Call (set-actor-scheduler! submit-proc) to switch to M:N mode.

(library (std actor core)
  (export
    ;; Creation
    spawn-actor
    spawn-actor/linked
    actor-ref?
    actor-ref-id
    actor-ref-name
    actor-ref-node

    ;; Sending
    send

    ;; Context inside a behavior
    self
    actor-id

    ;; Lifecycle
    actor-alive?
    actor-kill!
    actor-wait!

    ;; Link / monitor accessors (used by supervisor and protocol layers)
    actor-ref-links
    actor-ref-links-set!
    actor-ref-monitors
    actor-ref-monitors-set!

    ;; Dead letter
    set-dead-letter-handler!

    ;; Scheduler integration
    set-actor-scheduler!

    ;; Remote send hook (for transport layer)
    set-remote-send-handler!

    ;; Internal: lookup for distributed layer
    lookup-local-actor

    ;; Create a remote actor reference (for transport layer)
    make-remote-actor-ref

    ;; Internal: mailbox accessor (used by checkpoint layer)
    actor-ref-mailbox
  )
  (import (chezscheme) (std actor mpsc))

  ;; -------- Actor ID counter --------

  (define *next-actor-id* 0)
  (define *actor-id-mutex* (make-mutex))

  (define (next-actor-id!)
    (with-mutex *actor-id-mutex*
      (let ([id *next-actor-id*])
        (set! *next-actor-id* (fx+ id 1))
        id)))

  ;; -------- Actor record --------

  (define-record-type actor-ref
    (fields
      (immutable id)           ;; unique integer
      (immutable node)         ;; #f = local; string = remote node-id
      (immutable mailbox)      ;; mpsc-queue (or #f for remote refs)
      (immutable sched-mutex)  ;; protects idle→scheduled transition
      (mutable state)          ;; 'idle | 'scheduled | 'running | 'dead
      (mutable behavior)       ;; (lambda (msg) ...)
      (mutable links)          ;; list of actor-refs to notify on death
      (mutable monitors)       ;; list of (actor-ref . tag)
      (immutable name)         ;; symbol or #f
      (immutable done-mutex)
      (immutable done-cond)    ;; signaled when state = 'dead
      (mutable exit-reason))   ;; 'normal | exception | 'killed
    (protocol
      (lambda (new)
        (case-lambda
          ;; Local actor
          [(behavior name)
           (new (next-actor-id!)
                #f
                (make-mpsc-queue)
                (make-mutex)
                'idle
                behavior
                '()
                '()
                name
                (make-mutex)
                (make-condition)
                #f)]
          ;; Remote actor ref (no mailbox, no behavior).
          ;; Use 3 args to avoid arity collision with the local 2-arg branch.
          ;; Call as (make-actor-ref id node-id 'remote).
          [(id node _sentinel)
           (new id
                node
                #f
                (make-mutex)
                'idle
                (lambda (msg) (void))
                '() '()
                #f
                (make-mutex)
                (make-condition)
                #f)])))
    (sealed #t))

  ;; -------- Global actor table --------

  (define *actor-table* (make-eq-hashtable))
  (define *actor-table-mutex* (make-mutex))

  (define (register-local-actor! a)
    (with-mutex *actor-table-mutex*
      (hashtable-set! *actor-table* (actor-ref-id a) a)))

  (define (unregister-local-actor! a)
    (with-mutex *actor-table-mutex*
      (hashtable-delete! *actor-table* (actor-ref-id a))))

  (define (lookup-local-actor id)
    (with-mutex *actor-table-mutex*
      (hashtable-ref *actor-table* id #f)))

  ;; Create a reference to an actor on a remote node.
  ;; The ref has no local mailbox; send routes through the remote-send handler.
  (define (make-remote-actor-ref id node-id)
    (make-actor-ref id node-id 'remote))

  ;; -------- Thread-local actor context --------

  (define current-actor (make-thread-parameter #f))
  (define (self) (current-actor))
  (define (actor-id) (and (current-actor) (actor-ref-id (current-actor))))

  ;; -------- Dead letter handler --------

  (define *dead-letter-handler*
    (make-parameter
      (lambda (msg dest)
        (fprintf (current-error-port)
          "DEAD LETTER: actor #~a (~a) is dead, message dropped: ~s~%"
          (actor-ref-id dest)
          (or (actor-ref-name dest) "?")
          msg))))

  (define (set-dead-letter-handler! proc)
    (*dead-letter-handler* proc))

  ;; -------- Scheduler integration --------
  ;; *actor-scheduler* holds a (lambda (thunk) ...) or #f for 1:1 mode.

  (define *actor-scheduler* (make-parameter #f))

  (define (set-actor-scheduler! submit-proc)
    (*actor-scheduler* submit-proc))

  ;; -------- Remote send hook --------
  ;; Set by (std actor transport) to avoid circular import.

  (define *remote-send-handler* (make-parameter #f))

  (define (set-remote-send-handler! proc)
    (*remote-send-handler* proc))

  ;; -------- Internal: run an actor --------

  (define *max-batch* 64)

  (define (run-actor! a)
    (parameterize ([current-actor a])
      (with-mutex (actor-ref-sched-mutex a)
        (actor-ref-state-set! a 'running))
      (let loop ([count 0])
        (let-values ([(msg ok) (mpsc-try-dequeue! (actor-ref-mailbox a))])
          (cond
            [(and ok (fx< count *max-batch*))
             (guard (exn [#t (actor-die! a exn)])
               ((actor-ref-behavior a) msg))
             (unless (eq? (actor-ref-state a) 'dead)
               (loop (fx+ count 1)))]
            [else
             (with-mutex (actor-ref-sched-mutex a)
               (cond
                 ;; Batch limit — re-schedule for fairness
                 [(and ok (eq? (actor-ref-state a) 'running))
                  (actor-ref-state-set! a 'scheduled)
                  (schedule-actor-task! a)]
                 ;; Messages arrived while processing — re-schedule
                 [(and (not (mpsc-empty? (actor-ref-mailbox a)))
                       (eq? (actor-ref-state a) 'running))
                  (actor-ref-state-set! a 'scheduled)
                  (schedule-actor-task! a)]
                 ;; Truly idle
                 [(eq? (actor-ref-state a) 'running)
                  (actor-ref-state-set! a 'idle)]
                 ;; Actor died during processing
                 [else (void)]))])))))

  (define (schedule-actor-task! a)
    (let ([submit (*actor-scheduler*)])
      (if submit
        (submit (lambda () (run-actor! a)))
        (fork-thread (lambda () (run-actor! a))))))

  (define (actor-die! a reason)
    (with-mutex (actor-ref-sched-mutex a)
      (actor-ref-state-set! a 'dead))
    (actor-ref-exit-reason-set! a reason)
    (unregister-local-actor! a)
    ;; Close mailbox (wakes any blocked dequeue)
    (guard (exn [#t (void)])
      (mpsc-close! (actor-ref-mailbox a)))
    ;; Notify linked actors
    (for-each
      (lambda (linked)
        (when (actor-alive? linked)
          (guard (exn [#t (void)])
            (send linked (list 'EXIT (actor-ref-id a) reason)))))
      (actor-ref-links a))
    ;; Notify monitors
    (for-each
      (lambda (mon)
        (let ([watcher (car mon)]
              [tag     (cdr mon)])
          (when (actor-alive? watcher)
            (guard (exn [#t (void)])
              (send watcher (list 'DOWN tag (actor-ref-id a) reason))))))
      (actor-ref-monitors a))
    ;; Wake anyone in actor-wait!
    (with-mutex (actor-ref-done-mutex a)
      (condition-broadcast (actor-ref-done-cond a))))

  ;; -------- Public API --------

  (define spawn-actor
    (case-lambda
      [(behavior)       (spawn-actor-impl behavior #f)]
      [(behavior name)  (spawn-actor-impl behavior name)]))

  (define (spawn-actor-impl behavior name)
    (let ([a (make-actor-ref behavior name)])
      (register-local-actor! a)
      a))

  (define spawn-actor/linked
    (case-lambda
      [(behavior)      (spawn-actor/linked-impl behavior #f)]
      [(behavior name) (spawn-actor/linked-impl behavior name)]))

  (define (spawn-actor/linked-impl behavior name)
    (let ([parent (current-actor)]
          [child  (spawn-actor-impl behavior name)])
      (when parent
        (actor-ref-links-set! parent (cons child (actor-ref-links parent)))
        (actor-ref-links-set! child  (cons parent (actor-ref-links child))))
      child))

  (define (send actor msg)
    (cond
      [(not (actor-ref? actor))
       (error 'send "not an actor-ref" actor)]
      ;; Remote actor
      [(actor-ref-node actor)
       (let ([handler (*remote-send-handler*)])
         (if handler
           (handler actor msg)
           (error 'send "remote send not configured; call set-remote-send-handler!" actor)))]
      ;; Local, alive
      [(actor-alive? actor)
       (mpsc-enqueue! (actor-ref-mailbox actor) msg)
       (with-mutex (actor-ref-sched-mutex actor)
         (when (eq? (actor-ref-state actor) 'idle)
           (actor-ref-state-set! actor 'scheduled)
           (schedule-actor-task! actor)))]
      ;; Local, dead
      [else
       ((*dead-letter-handler*) msg actor)]))

  (define (actor-alive? actor)
    (not (eq? (actor-ref-state actor) 'dead)))

  (define (actor-kill! actor)
    (unless (eq? (actor-ref-state actor) 'dead)
      (actor-die! actor 'killed)))

  (define (actor-wait! actor)
    (with-mutex (actor-ref-done-mutex actor)
      (let loop ()
        (unless (eq? (actor-ref-state actor) 'dead)
          (condition-wait (actor-ref-done-cond actor)
                          (actor-ref-done-mutex actor))
          (loop)))))

  ) ;; end library
