#!chezscheme
;;; (std agent) — Clojure-style agents.
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
;;; Actions run one at a time on a dedicated worker thread per agent,
;;; so there's never contention on the value — readers with
;;; `agent-value` / `deref` see the most recent successfully-applied
;;; state, and writers via `send` queue without blocking on each
;;; other.
;;;
;;; Error handling
;;; --------------
;;; If an action throws, the exception is captured and placed in the
;;; agent's error slot. Subsequent `send` calls raise an error until
;;; `restart-agent` is called to clear the error and optionally reset
;;; the value. This matches Clojure's default `:fail` error mode.
;;;
;;; Use `agent-error` to check for an error without raising:
;;;
;;;   (send a (lambda (v) (error 'bad "boom")))
;;;   (await a)
;;;   (agent-error a)     ;; => a condition
;;;   (send a + 1)        ;; raises: agent has error, call restart-agent
;;;   (restart-agent a 0) ;; clears error and resets value to 0
;;;   (send a + 1)        ;; works again
;;;
;;; Distinction from `(std actor)`
;;; ------------------------------
;;; `(std actor)` provides supervised message-passing hierarchies with
;;; behaviours, links, and monitors — full actor-model. `(std agent)`
;;; is a much smaller construct: a single state cell with a serialized
;;; action queue. Agents are good when you want one thing to hold
;;; state and coalesce updates without locking. Actors are good when
;;; you want a tree of supervised processes. They can coexist.
;;;
;;; Shutdown
;;; --------
;;; `shutdown-agent!` closes the action queue and lets the worker thread
;;; finish naturally when the queue drains. There is no forcible kill.
;;; After shutdown, further sends raise an error.

(library (std agent)
  (export
    agent agent?
    send send-off
    agent-value agent-error
    clear-agent-errors restart-agent
    await shutdown-agent!)

  (import (chezscheme)
          (std csp))

  ;; --- Agent record -------------------------------------------
  ;;
  ;; `val` and `err` are mutable. Only the worker thread writes
  ;; them; readers (deref / agent-value / agent-error) observe
  ;; the most recent write. There's no lock on reads — we rely on
  ;; Chez's atomic-word slot updates.
  ;;
  ;; The worker thread's handle is not stored in the record — the
  ;; thread exits naturally when its action channel is closed, and
  ;; Chez reclaims thread objects on GC. Nothing outside the library
  ;; needs to poke the thread object directly.

  (define-record-type %agent
    (fields (mutable val)
            (mutable err)
            (immutable action-ch))
    (sealed #t))

  (define (agent? x) (%agent? x))

  (define (agent-value a)
    (unless (%agent? a) (error 'agent-value "not an agent" a))
    (%agent-val a))

  (define (agent-error a)
    (unless (%agent? a) (error 'agent-error "not an agent" a))
    (%agent-err a))

  ;; --- Constructor --------------------------------------------

  ;; (agent initial-value)        — default queue capacity 1024
  ;; (agent initial-value n)      — custom queue capacity
  (define agent
    (case-lambda
      [(initial) (agent initial 1024)]
      [(initial buf-size)
       (let* ([ch (make-channel buf-size)]
              [a  (make-%agent initial #f ch)])
         (fork-thread (%make-worker-loop a ch))
         a)]))

  (define (%make-worker-loop a ch)
    (lambda ()
      (let loop ()
        (let ([action (chan-get! ch)])
          (cond
            [(eof-object? action) #f]   ;; channel closed, exit
            [else
             ;; Skip actions if the agent is already in an error
             ;; state — queued work drains but doesn't execute
             ;; until restart-agent.
             (unless (%agent-err a)
               (guard (exn [else (%agent-err-set! a exn)])
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
    (when (chan-closed? (%agent-action-ch a))
      (error 'send "agent has been shut down" a))
    (chan-put! (%agent-action-ch a) (cons fn args))
    a)

  ;; In Clojure, send-off dispatches on a dedicated unbounded I/O
  ;; thread pool so blocking operations don't starve the cpu pool.
  ;; Jerboa's agent runs on a single dedicated worker, so send and
  ;; send-off are operationally identical. The alias is kept so
  ;; Clojure code doesn't need rewriting.
  (define send-off send)

  ;; --- Error handling -----------------------------------------

  (define (clear-agent-errors a)
    (unless (%agent? a) (error 'clear-agent-errors "not an agent" a))
    (%agent-err-set! a #f)
    a)

  ;; (restart-agent a new-value) — clears error and resets value.
  ;; Clojure's restart-agent takes the new state as its required
  ;; second argument.
  (define (restart-agent a new-value)
    (unless (%agent? a) (error 'restart-agent "not an agent" a))
    (%agent-err-set! a #f)
    (%agent-val-set! a new-value)
    a)

  ;; --- Synchronization ----------------------------------------

  ;; (await a) — block until all currently-queued actions have been
  ;; processed. Returns the agent.
  ;;
  ;; Implementation: send a sentinel action that signals a private
  ;; channel. Because actions are processed in order, receiving on
  ;; the sentinel channel guarantees all prior actions have run.
  ;;
  ;; Note: if the agent is in an error state the sentinel will be
  ;; skipped along with all other actions, so await would hang
  ;; forever. We detect this and bail out with an error.
  (define (await a)
    (unless (%agent? a) (error 'await "not an agent" a))
    (when (%agent-err a)
      (error 'await "agent has error; call restart-agent to clear"
             (%agent-err a)))
    (when (chan-closed? (%agent-action-ch a))
      (error 'await "agent has been shut down" a))
    (let ([done (make-channel 1)])
      (chan-put! (%agent-action-ch a)
                 (cons (lambda (v)
                         (chan-put! done 'done)
                         v)
                       '()))
      (chan-get! done)
      a))

  ;; (shutdown-agent! a) — close the action queue. The worker
  ;; thread exits when it drains the queue. Subsequent sends raise.
  (define (shutdown-agent! a)
    (unless (%agent? a) (error 'shutdown-agent! "not an agent" a))
    (chan-close! (%agent-action-ch a))
    a)

) ;; end library
