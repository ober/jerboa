#!chezscheme
;;; (std agent) — Clojure-style agents (fiber-aware)
;;;
;;; An agent is an asynchronous state cell with a serialized action
;;; queue. You create one with an initial value and then dispatch
;;; actions against it:
;;;
;;;   (def a (agent 0))
;;;   (send a + 1)        ;; queues (+ 0 1) -> 1; returns a
;;;   (send a * 3)        ;; queues (* 1 3) -> 3; returns a
;;;   (await a)           ;; blocks until the queue drains
;;;   (agent-value a)     ;; => 3
;;;
;;; FIBER-AWARE DISPATCH
;;; --------------------
;;; When created inside a fiber runtime, the agent's worker loop runs
;;; as a fiber and the action channel is a fiber-channel. This means
;;; `send` parks instead of blocking, and agent workers cost ~4KB
;;; each instead of an OS thread.
;;;
;;; When created outside a fiber runtime, falls back to OS threads
;;; and (std csp) channels (original behavior).
;;;
;;; Error handling
;;; --------------
;;; If an action throws, the exception is captured and placed in the
;;; agent's error slot. Subsequent `send` calls raise an error until
;;; `restart-agent` is called to clear the error and optionally reset
;;; the value. This matches Clojure's default `:fail` error mode.
;;;
;;; Shutdown
;;; --------
;;; `shutdown-agent!` closes the action queue and lets the worker
;;; finish naturally when the queue drains.

(library (std agent)
  (export
    agent agent?
    send send-off
    agent-value agent-error
    clear-agent-errors restart-agent
    await await-for shutdown-agent!
    set-error-handler! set-error-mode!
    agent-error-mode agent-error-handler)

  (import (chezscheme)
          (std csp)
          (std fiber))

  ;; --- Agent record -------------------------------------------

  (define-record-type %agent
    (fields (mutable val)
            (mutable err)
            (immutable action-ch)
            (immutable fiber-mode?)       ;; #t if backed by fiber
            (mutable error-mode)          ;; 'fail (default) | 'continue
            (mutable error-handler))      ;; #f or (a exn) -> ignored
    (sealed #t))

  (define (agent? x) (%agent? x))

  (define (agent-value a)
    (unless (%agent? a) (error 'agent-value "not an agent" a))
    (%agent-val a))

  (define (agent-error a)
    (unless (%agent? a) (error 'agent-error "not an agent" a))
    (%agent-err a))

  ;; --- Constructor --------------------------------------------

  (define agent
    (case-lambda
      [(initial) (agent initial 1024)]
      [(initial buf-size)
       (let ([rt (current-fiber-runtime)])
         (if rt
           ;; Fiber mode: fiber-channel + fiber worker
           (let* ([ch (make-fiber-channel buf-size)]
                  [a  (make-%agent initial #f ch #t 'fail #f)])
             (fiber-spawn rt (%make-fiber-worker-loop a ch))
             a)
           ;; Thread mode: OS channel + OS thread worker
           (let* ([ch (make-channel buf-size)]
                  [a  (make-%agent initial #f ch #f 'fail #f)])
             (fork-thread (%make-thread-worker-loop a ch))
             a)))]))

  ;; --- Error policy helpers -----------------------------------

  (define (%run-error-handler! a exn)
    (let ([h (%agent-error-handler a)])
      (when h
        (guard (_ [else #f])   ;; swallow handler exceptions
          (h a exn)))))

  (define (%on-action-error! a exn)
    (%run-error-handler! a exn)
    (case (%agent-error-mode a)
      [(continue) #f]                     ;; drop the error, keep going
      [else (%agent-err-set! a exn)]))    ;; 'fail — latch the error

  ;; --- Worker loops -------------------------------------------

  ;; OS-thread worker: blocks on chan-get!
  (define (%make-thread-worker-loop a ch)
    (lambda ()
      (let loop ()
        (let ([action (chan-get! ch)])
          (cond
            [(eof-object? action) #f]
            [else
             (unless (%agent-err a)
               (guard (exn [else (%on-action-error! a exn)])
                 (let ([new-val (apply (car action)
                                       (%agent-val a)
                                       (cdr action))])
                   (%agent-val-set! a new-val))))
             (loop)])))))

  ;; Fiber worker: parks on fiber-channel-recv
  (define (%make-fiber-worker-loop a ch)
    (lambda ()
      (let loop ()
        (let ([action (fiber-channel-recv ch)])
          (cond
            [(eof-object? action) #f]
            [else
             (unless (%agent-err a)
               (guard (exn [else (%on-action-error! a exn)])
                 (let ([new-val (apply (car action)
                                       (%agent-val a)
                                       (cdr action))])
                   (%agent-val-set! a new-val))))
             (loop)])))))

  ;; --- Dispatch -----------------------------------------------

  (define (send a fn . args)
    (unless (%agent? a) (error 'send "not an agent" a))
    (unless (procedure? fn) (error 'send "action is not a procedure" fn))
    (when (%agent-err a)
      (error 'send
             "agent has error; call restart-agent to clear"
             (%agent-err a)))
    (let ([ch (%agent-action-ch a)])
      (if (%agent-fiber-mode? a)
        (begin
          (when (fiber-channel-closed? ch)
            (error 'send "agent has been shut down" a))
          (fiber-channel-send ch (cons fn args)))
        (begin
          (when (chan-closed? ch)
            (error 'send "agent has been shut down" a))
          (chan-put! ch (cons fn args)))))
    a)

  ;; send-off: in Clojure dispatches on unbounded I/O pool.
  ;; In Jerboa, agents already have a dedicated worker, so
  ;; send and send-off are identical.
  (define send-off send)

  ;; --- Error handling -----------------------------------------

  (define (clear-agent-errors a)
    (unless (%agent? a) (error 'clear-agent-errors "not an agent" a))
    (%agent-err-set! a #f)
    a)

  (define (restart-agent a new-value)
    (unless (%agent? a) (error 'restart-agent "not an agent" a))
    (%agent-err-set! a #f)
    (%agent-val-set! a new-value)
    a)

  ;; --- Synchronization ----------------------------------------

  ;; (await a) — block until all currently-queued actions have been
  ;; processed. Sends a sentinel action that signals completion.
  (define (await a)
    (unless (%agent? a) (error 'await "not an agent" a))
    (when (%agent-err a)
      (error 'await "agent has error; call restart-agent to clear"
             (%agent-err a)))
    (let ([ch (%agent-action-ch a)])
      (if (%agent-fiber-mode? a)
        ;; Fiber mode: use fiber-channel for sentinel
        (begin
          (when (fiber-channel-closed? ch)
            (error 'await "agent has been shut down" a))
          (let ([done (make-fiber-channel 1)])
            (fiber-channel-send ch
              (cons (lambda (v)
                      (fiber-channel-send done 'done)
                      v)
                    '()))
            (fiber-channel-recv done)
            a))
        ;; Thread mode: use OS channel for sentinel
        (begin
          (when (chan-closed? ch)
            (error 'await "agent has been shut down" a))
          (let ([done (make-channel 1)])
            (chan-put! ch
              (cons (lambda (v)
                      (chan-put! done 'done)
                      v)
                    '()))
            (chan-get! done)
            a)))))

  ;; (shutdown-agent! a) — close the action queue.
  (define (shutdown-agent! a)
    (unless (%agent? a) (error 'shutdown-agent! "not an agent" a))
    (let ([ch (%agent-action-ch a)])
      (if (%agent-fiber-mode? a)
        (fiber-channel-close ch)
        (chan-close! ch)))
    a)

  ;; (await-for ms a) — like `await` but gives up after ms milliseconds.
  ;; Returns #t if the queue drained in time, #f on timeout.
  ;; Implemented by sending a marker action and polling for its completion.
  (define (await-for ms a)
    (unless (%agent? a) (error 'await-for "not an agent" a))
    (unless (and (integer? ms) (>= ms 0))
      (error 'await-for "ms must be a non-negative integer" ms))
    (when (%agent-err a)
      (error 'await-for "agent has error; call restart-agent to clear"
             (%agent-err a)))
    (let ([done-box (list 'pending)]
          [ch (%agent-action-ch a)])
      ;; Action that marks completion by mutating the box.
      ;; Capture: cons on first slot so the caller can observe via eq?.
      (let ([marker (cons (lambda (v)
                            (set-car! done-box 'done)
                            v)
                          '())])
        (if (%agent-fiber-mode? a)
          (begin
            (when (fiber-channel-closed? ch)
              (error 'await-for "agent has been shut down" a))
            (fiber-channel-send ch marker))
          (begin
            (when (chan-closed? ch)
              (error 'await-for "agent has been shut down" a))
            (chan-put! ch marker))))
      ;; Poll for completion. 5ms steps keeps overhead low.
      (let loop ([remaining ms])
        (cond
          [(eq? (car done-box) 'done) #t]
          [(<= remaining 0) #f]
          [else
           (sleep (make-time 'time-duration 5000000 0))
           (loop (- remaining 5))]))))

  ;; (set-error-handler! a fn) — install a handler called with
  ;; (fn agent exception) each time an action throws. Handler runs
  ;; after the action failure and before the latched-error logic.
  ;; Pass #f to clear. Handler exceptions are swallowed.
  (define (set-error-handler! a fn)
    (unless (%agent? a) (error 'set-error-handler! "not an agent" a))
    (unless (or (not fn) (procedure? fn))
      (error 'set-error-handler! "handler must be a procedure or #f" fn))
    (%agent-error-handler-set! a fn)
    a)

  ;; (set-error-mode! a mode) — mode is 'fail (default) or 'continue.
  ;; In 'continue mode, action errors do not latch, so subsequent sends
  ;; proceed (paired with set-error-handler! for observability).
  (define (set-error-mode! a mode)
    (unless (%agent? a) (error 'set-error-mode! "not an agent" a))
    (unless (memq mode '(fail continue))
      (error 'set-error-mode! "mode must be 'fail or 'continue" mode))
    (%agent-error-mode-set! a mode)
    a)

  ;; Accessors (documented surface — useful for assertions/tests).
  (define (agent-error-mode a)
    (unless (%agent? a) (error 'agent-error-mode "not an agent" a))
    (%agent-error-mode a))

  (define (agent-error-handler a)
    (unless (%agent? a) (error 'agent-error-handler "not an agent" a))
    (%agent-error-handler a))

) ;; end library
