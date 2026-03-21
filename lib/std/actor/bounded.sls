#!chezscheme
;;; (std actor bounded) — Bounded actor mailboxes
;;;
;;; Wraps actor spawning with configurable mailbox capacity.
;;; Prevents memory exhaustion from message flooding.
;;;
;;; Backpressure strategies:
;;; - 'block: sender blocks until space available (default)
;;; - 'drop:  new messages are silently dropped
;;; - 'error: raises an error on the sender

(library (std actor bounded)
  (export
    ;; Bounded spawning
    spawn-bounded-actor
    spawn-bounded-actor/linked

    ;; Bounded send
    bounded-send

    ;; Configuration
    make-mailbox-config
    mailbox-config?
    mailbox-config-capacity
    mailbox-config-strategy
    default-mailbox-config

    ;; Status
    mailbox-size
    mailbox-full?

    ;; Condition type
    &mailbox-full
    make-mailbox-full
    mailbox-full-condition?
    mailbox-full-actor-id)

  (import (chezscheme)
          (std actor core)
          (std actor mpsc))

  ;; ========== Mailbox Configuration ==========

  (define-record-type (mailbox-config %make-mailbox-config mailbox-config?)
    (sealed #t)
    (fields
      (immutable capacity mailbox-config-capacity)     ;; max messages
      (immutable strategy mailbox-config-strategy)))   ;; 'block, 'drop, 'error

  (define (make-mailbox-config capacity . opts)
    (let ([strategy (if (and (pair? opts) (pair? (cdr opts))
                             (eq? (car opts) 'strategy:))
                      (cadr opts)
                      'block)])
      (unless (and (integer? capacity) (positive? capacity))
        (error 'make-mailbox-config "capacity must be a positive integer" capacity))
      (unless (memq strategy '(block drop error))
        (error 'make-mailbox-config "strategy must be block, drop, or error" strategy))
      (%make-mailbox-config capacity strategy)))

  (define default-mailbox-config
    (%make-mailbox-config 10000 'block))

  ;; ========== Mailbox Full Condition ==========

  (define-condition-type &mailbox-full &serious
    make-mailbox-full mailbox-full-condition?
    (actor-id mailbox-full-actor-id))

  ;; ========== Bounded Mailbox State ==========

  ;; Per-actor bounds tracking: actor-id -> #(config size mutex cond)
  (define *bounds* (make-eq-hashtable))
  (define *bounds-mutex* (make-mutex))

  (define (register-bounds! actor-id config)
    (with-mutex *bounds-mutex*
      (hashtable-set! *bounds* actor-id
        (vector config 0 (make-mutex) (make-condition)))))

  (define (unregister-bounds! actor-id)
    (with-mutex *bounds-mutex*
      (hashtable-delete! *bounds* actor-id)))

  (define (get-bounds actor-id)
    (with-mutex *bounds-mutex*
      (hashtable-ref *bounds* actor-id #f)))

  ;; ========== Bounded Actors ==========

  (define (spawn-bounded-actor behavior config . name-opt)
    ;; Spawn an actor with a bounded mailbox.
    (let* ([name (if (pair? name-opt) (car name-opt) #f)]
           ;; Wrap behavior to decrement count after processing
           [wrapped (lambda (msg)
                      (let ([bounds (get-bounds (actor-ref-id (self)))])
                        (when bounds
                          (let ([mtx (vector-ref bounds 2)]
                                [cond (vector-ref bounds 3)])
                            (with-mutex mtx
                              (vector-set! bounds 1
                                (max 0 (- (vector-ref bounds 1) 1)))
                              ;; Wake any blocked senders
                              (condition-broadcast cond)))))
                      (behavior msg))]
           [actor (spawn-actor wrapped name)])
      (register-bounds! (actor-ref-id actor) config)
      actor))

  (define (spawn-bounded-actor/linked behavior config . name-opt)
    (let* ([name (if (pair? name-opt) (car name-opt) #f)]
           [wrapped (lambda (msg)
                      (let ([bounds (get-bounds (actor-ref-id (self)))])
                        (when bounds
                          (let ([mtx (vector-ref bounds 2)]
                                [cond (vector-ref bounds 3)])
                            (with-mutex mtx
                              (vector-set! bounds 1
                                (max 0 (- (vector-ref bounds 1) 1)))
                              (condition-broadcast cond)))))
                      (behavior msg))]
           [actor (spawn-actor/linked wrapped name)])
      (register-bounds! (actor-ref-id actor) config)
      actor))

  ;; ========== Bounded Send ==========

  (define (bounded-send actor msg)
    ;; Send with backpressure based on mailbox bounds.
    ;; For unbounded actors, falls through to regular send.
    (let ([bounds (get-bounds (actor-ref-id actor))])
      (if (not bounds)
        ;; No bounds registered — regular send
        (send actor msg)
        (let ([config (vector-ref bounds 0)]
              [mtx (vector-ref bounds 2)]
              [cond (vector-ref bounds 3)])
          (let ([capacity (mailbox-config-capacity config)]
                [strategy (mailbox-config-strategy config)])
            (case strategy
              [(block)
               ;; Block until space available
               (with-mutex mtx
                 (let loop ()
                   (when (>= (vector-ref bounds 1) capacity)
                     (condition-wait cond mtx)
                     (loop)))
                 (vector-set! bounds 1 (+ (vector-ref bounds 1) 1)))
               (send actor msg)]
              [(drop)
               ;; Drop if full
               (with-mutex mtx
                 (when (< (vector-ref bounds 1) capacity)
                   (vector-set! bounds 1 (+ (vector-ref bounds 1) 1))
                   (send actor msg)))]
              [(error)
               ;; Error if full
               (with-mutex mtx
                 (if (>= (vector-ref bounds 1) capacity)
                   (raise (condition
                            (make-mailbox-full (actor-ref-id actor))
                            (make-message-condition
                              (format #f "mailbox full (capacity ~a)" capacity))))
                   (begin
                     (vector-set! bounds 1 (+ (vector-ref bounds 1) 1))
                     (send actor msg))))]))))))

  ;; ========== Status ==========

  (define (mailbox-size actor)
    ;; Get the current mailbox size for a bounded actor.
    (let ([bounds (get-bounds (actor-ref-id actor))])
      (if bounds
        (with-mutex (vector-ref bounds 2)
          (vector-ref bounds 1))
        0)))

  (define (mailbox-full? actor)
    ;; Check if the mailbox is at capacity.
    (let ([bounds (get-bounds (actor-ref-id actor))])
      (if bounds
        (let ([config (vector-ref bounds 0)])
          (with-mutex (vector-ref bounds 2)
            (>= (vector-ref bounds 1) (mailbox-config-capacity config))))
        #f)))

  ) ;; end library
