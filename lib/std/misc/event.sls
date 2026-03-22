#!chezscheme
;;; (std misc event) — Unified event system with multiplexed selectors
;;;
;;; Events are lazy values that may or may not be ready. They can be
;;; composed with choice, transformed with wrap/handle, and synchronized
;;; with sync/sync-timeout.
;;;
;;; Channels provide synchronous rendezvous-style communication between
;;; threads, built on events.
;;;
;;; (sync (choice (wrap (timer-event 1000) (lambda (v) 'timeout))
;;;               (wrap (channel-recv-event ch) handle-message)))

(library (std misc event)
  (export make-event event-ready? event-value
          sync sync/timeout
          choice wrap handle
          timer-event always-event never-event
          make-channel channel-send channel-recv
          channel-send-event channel-recv-event)
  (import (chezscheme))

  ;; ---------- Event record ----------
  ;; An event wraps a poll thunk that returns (values ready? value).
  ;; When polled and ready, it yields its value.

  (define-record-type evt
    (fields
      (immutable poll)       ;; thunk -> (values ready? value)
      (immutable transform)) ;; #f or (proc . evt) chain
    (protocol
      (lambda (new)
        (case-lambda
          [(poll) (new poll #f)]
          [(poll transform) (new poll transform)]))))

  ;; Public constructor: make-event from a poll thunk
  (define (make-event poll-thunk)
    (make-evt poll-thunk))

  ;; Poll a single event, applying any transforms
  (define (event-poll e)
    (let-values ([(ready? val) ((evt-poll e))])
      (if ready?
        (values #t (apply-transforms e val))
        (values #f #f))))

  ;; Apply the transform chain for wrapped events
  (define (apply-transforms e val)
    (let ([tx (evt-transform e)])
      (if tx
        (let ([proc (car tx)]
              [inner (cdr tx)])
          ;; The transform is on the outer event; inner event's transforms
          ;; are already applied during its poll.
          (proc val))
        val)))

  ;; ---------- Public API ----------

  (define (event-ready? e)
    (let-values ([(ready? val) (event-poll e)])
      ready?))

  (define (event-value e)
    ;; Blocking: spin-wait with backoff until ready
    (let loop ([spins 0])
      (let-values ([(ready? val) (event-poll e)])
        (if ready?
          val
          (begin
            (when (fx> spins 10)
              (sleep (make-time 'time-duration 1000000 0)))  ;; 1ms
            (loop (fx+ spins 1)))))))

  ;; ---------- Combinators ----------

  ;; choice: combine multiple events; polling tries each in order
  (define (choice . events)
    (make-evt
      (lambda ()
        (let loop ([evts events])
          (if (null? evts)
            (values #f #f)
            (let-values ([(ready? val) (event-poll (car evts))])
              (if ready?
                (values #t val)
                (loop (cdr evts)))))))))

  ;; wrap: transform an event's value
  (define (wrap e proc)
    (make-evt
      (lambda ()
        (let-values ([(ready? val) (event-poll e)])
          (if ready?
            (values #t (proc val))
            (values #f #f))))))

  ;; handle: like wrap (transform value with handler proc)
  (define (handle e proc)
    (wrap e proc))

  ;; ---------- sync ----------
  ;; Wait for any one of the given events to be ready.
  ;; Returns the value of the first ready event.

  (define (sync . events)
    (let ([mtx (make-mutex)]
          [cnd (make-condition)]
          [flat (flatten-events events)])
      (let loop ([spins 0])
        ;; Try each event
        (let try ([evts flat])
          (if (null? evts)
            ;; None ready — backoff and retry
            (begin
              (if (fx< spins 20)
                ;; Busy-spin for first 20 attempts (sub-microsecond latency)
                (void)
                ;; After that, sleep with increasing backoff
                (let ([ms (fxmin 10 (fx- spins 19))])
                  (sleep (make-time 'time-duration (fx* ms 1000000) 0))))
              (loop (fx+ spins 1)))
            (let-values ([(ready? val) (event-poll (car evts))])
              (if ready?
                val
                (try (cdr evts)))))))))

  ;; Flatten nested choice events into a single list
  (define (flatten-events events)
    events)

  ;; sync/timeout: like sync but returns #f if no event fires within timeout-ms
  (define (sync/timeout timeout-ms . events)
    (let ([flat (flatten-events events)]
          [deadline (+ (current-time-ms) timeout-ms)])
      (let loop ([spins 0])
        (let try ([evts flat])
          (if (null? evts)
            ;; None ready — check timeout
            (if (>= (current-time-ms) deadline)
              #f
              (begin
                (when (fx> spins 20)
                  (let ([remaining (- deadline (current-time-ms))])
                    (when (> remaining 0)
                      (let ([ms (min 5 remaining)])
                        (sleep (make-time 'time-duration
                                          (exact (floor (* ms 1000000)))
                                          0))))))
                (loop (fx+ spins 1))))
            (let-values ([(ready? val) (event-poll (car evts))])
              (if ready?
                val
                (try (cdr evts)))))))))

  ;; Current monotonic time in milliseconds
  (define (current-time-ms)
    (let ([t (current-time 'time-monotonic)])
      (+ (* (time-second t) 1000)
         (div (time-nanosecond t) 1000000))))

  ;; ---------- Built-in events ----------

  ;; always-event: immediately ready with value
  (define (always-event val)
    (make-evt (lambda () (values #t val))))

  ;; never-event: never ready
  (define never-event
    (make-evt (lambda () (values #f #f))))

  ;; timer-event: fires after delay-ms milliseconds with value #t
  (define (timer-event delay-ms)
    (let ([deadline (+ (current-time-ms) delay-ms)])
      (make-evt
        (lambda ()
          (if (>= (current-time-ms) deadline)
            (values #t #t)
            (values #f #f))))))

  ;; ---------- Channels ----------
  ;; Synchronous rendezvous channels: a send blocks until a receiver is
  ;; waiting, and vice versa. Both sides get an event for use with sync.

  (define-record-type chan
    (fields
      (immutable mutex)
      (immutable send-cond)     ;; signaled when a sender deposits a value
      (immutable recv-cond)     ;; signaled when a receiver picks up the value
      (mutable has-value?)      ;; is there a value in the slot?
      (mutable value)           ;; the value in transit
      (mutable send-waiting?)   ;; sender is blocked waiting for receiver
      (mutable recv-waiting?))  ;; receiver is blocked waiting for sender
    (protocol
      (lambda (new)
        (lambda ()
          (new (make-mutex) (make-condition) (make-condition)
               #f #f #f #f)))))

  (define (make-channel) (make-chan))

  ;; Blocking send: deposit value and wait for receiver to pick it up
  (define (channel-send ch val)
    (mutex-acquire (chan-mutex ch))
    ;; Wait until channel slot is free
    (let loop ()
      (when (chan-has-value? ch)
        (condition-wait (chan-recv-cond ch) (chan-mutex ch))
        (loop)))
    ;; Deposit value
    (chan-value-set! ch val)
    (chan-has-value?-set! ch #t)
    (chan-send-waiting?-set! ch #t)
    ;; Signal receivers that a value is available
    (condition-broadcast (chan-send-cond ch))
    ;; Wait for receiver to pick it up
    (let loop ()
      (when (chan-has-value? ch)
        (condition-wait (chan-recv-cond ch) (chan-mutex ch))
        (loop)))
    (chan-send-waiting?-set! ch #f)
    (mutex-release (chan-mutex ch)))

  ;; Blocking recv: wait for a sender to deposit a value, then take it
  (define (channel-recv ch)
    (mutex-acquire (chan-mutex ch))
    ;; Wait for a value
    (let loop ()
      (unless (chan-has-value? ch)
        (chan-recv-waiting?-set! ch #t)
        (condition-wait (chan-send-cond ch) (chan-mutex ch))
        (loop)))
    ;; Take the value
    (let ([val (chan-value ch)])
      (chan-value-set! ch #f)
      (chan-has-value?-set! ch #f)
      (chan-recv-waiting?-set! ch #f)
      ;; Signal sender that value was consumed
      (condition-broadcast (chan-recv-cond ch))
      (mutex-release (chan-mutex ch))
      val))

  ;; Non-blocking try-recv: returns (values val #t) or (values #f #f)
  (define (try-recv ch)
    (mutex-acquire (chan-mutex ch))
    (if (chan-has-value? ch)
      (let ([val (chan-value ch)])
        (chan-value-set! ch #f)
        (chan-has-value?-set! ch #f)
        (condition-broadcast (chan-recv-cond ch))
        (mutex-release (chan-mutex ch))
        (values val #t))
      (begin
        (mutex-release (chan-mutex ch))
        (values #f #f))))

  ;; channel-recv-event: an event that fires when a value is available
  (define (channel-recv-event ch)
    (make-evt
      (lambda ()
        (let-values ([(val ok) (try-recv ch)])
          (if ok
            (values #t val)
            (values #f #f))))))

  ;; channel-send-event: an event for sending (fires when receiver takes it)
  ;; For use with sync — sends val when a receiver is available
  (define (channel-send-event ch val)
    (make-evt
      (lambda ()
        (mutex-acquire (chan-mutex ch))
        (cond
          ;; If slot is free and a receiver is waiting, deposit directly
          [(and (not (chan-has-value? ch)) (chan-recv-waiting? ch))
           (chan-value-set! ch val)
           (chan-has-value?-set! ch #t)
           (condition-broadcast (chan-send-cond ch))
           (mutex-release (chan-mutex ch))
           ;; Value deposited, but we need to wait for pickup for true rendezvous
           ;; For the event model, we consider the send "fired" once deposited
           (values #t (void))]
          [else
           (mutex-release (chan-mutex ch))
           (values #f #f)]))))

) ;; end library
