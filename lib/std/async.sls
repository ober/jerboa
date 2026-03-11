#!chezscheme
;;; (std async) — Async I/O runtime built on algebraic effects
;;;
;;; Uses a thread-per-task model internally:
;;;   - Each async task runs in its own thread
;;;   - Async await blocks the thread until the promise resolves
;;;   - Async spawn creates a new task thread
;;;   - Async sleep sleeps the current thread
;;;
;;; The Async effect provides a clean API; threads handle actual suspension.
;;;
;;; API:
;;;   Async::descriptor       — effect descriptor
;;;   (Async await promise)   — block until promise resolves, return value
;;;   (Async spawn thunk)     — launch concurrent task (non-blocking)
;;;   (Async sleep ms)        — sleep for ms milliseconds
;;;   (run-async thunk)       — run thunk in async context, block until done
;;;   (make-async-promise)    — create a fulfillable promise
;;;   (async-promise-resolve! p val)  — fulfill a promise
;;;   (async-channel-get ch)  — get from channel, suspending via Async effect
;;;   (async-channel-put ch val) — put to channel (async)
;;;   (async-task thunk)      — spawn a task, return a promise for its result

(library (std async)
  (export
    ;; Async effect
    Async
    Async::descriptor

    ;; Event loop
    run-async
    run-async/workers

    ;; Promises
    make-async-promise
    async-promise?
    async-promise-resolve!
    async-promise-resolved?
    async-promise-value

    ;; Task management
    async-task
    async-task?

    ;; Async channels
    async-channel-get
    async-channel-put

    ;; Async sleep
    async-sleep)

  (import (chezscheme) (std effect) (std misc channel))

  ;; ========== Async Effect Definition ==========

  (defeffect Async
    (await promise)
    (spawn thunk)
    (sleep ms))

  ;; ========== Promise ==========

  (define-record-type async-promise
    (fields
      (mutable resolved?)
      (mutable value)
      (immutable mutex)
      (immutable cond))
    (protocol
      (lambda (new)
        (lambda ()
          (new #f #f (make-mutex) (make-condition)))))
    (sealed #t))

  (define (async-promise-resolve! p val)
    (with-mutex (async-promise-mutex p)
      (unless (async-promise-resolved? p)
        (async-promise-resolved?-set! p #t)
        (async-promise-value-set! p val)
        (condition-broadcast (async-promise-cond p)))))

  ;; Block current OS thread until promise resolves, then return value.
  (define (promise-wait! p)
    (with-mutex (async-promise-mutex p)
      (let loop ()
        (if (async-promise-resolved? p)
          (async-promise-value p)
          (begin
            (condition-wait (async-promise-cond p) (async-promise-mutex p))
            (loop))))))

  ;; ========== Async Effect Handlers ==========
  ;;
  ;; The handlers use thread-level blocking for true task suspension.
  ;; Each handler receives (k arg ...) where k is the one-shot continuation.
  ;; Instead of storing k and returning, handlers block the current thread
  ;; until the effect completes, then resume by calling k.
  ;;
  ;; Since we run each task in a thread, this correctly suspends the task.

  (define (install-async-handlers! thunk)
    (with-handler
      ([Async
        ;; await: block current thread until promise resolves
        (await (k promise)
          (let ([val (promise-wait! promise)])
            (resume k val)))
        ;; spawn: fork a new thread for the task, resume immediately
        (spawn (k task-thunk)
          (fork-thread
            (lambda ()
              (with-handler
                ([Async
                  (await (k2 p) (resume k2 (promise-wait! p)))
                  (spawn (k2 t)
                    (fork-thread (lambda () (install-async-handlers! t)))
                    (resume k2 (void)))
                  (sleep (k2 ms)
                    (sleep (make-time 'time-duration
                              (fx* (fxmod ms 1000) 1000000)
                              (fxquotient ms 1000)))
                    (resume k2 (void)))])
                (task-thunk))))
          (resume k (void)))
        ;; sleep: sleep the current thread
        (sleep (k ms)
          (sleep (make-time 'time-duration
                   (fx* (fxmod ms 1000) 1000000)
                   (fxquotient ms 1000)))
          (resume k (void)))])
      (thunk)))

  ;; ========== run-async ==========

  (define (run-async thunk)
    (let ([result-promise (make-async-promise)])
      ;; Run the thunk in a thread with Async handlers installed
      (fork-thread
        (lambda ()
          (guard (exn [#t
                       (fprintf (current-error-port)
                         "run-async error: ~a~%"
                         (if (message-condition? exn) (condition-message exn) exn))
                       (async-promise-resolve! result-promise
                         (raise-continuable exn))])
            (install-async-handlers!
              (lambda ()
                (let ([val (thunk)])
                  (async-promise-resolve! result-promise val)))))))
      ;; Block main thread until done
      (promise-wait! result-promise)))

  ;; (run-async/workers thunk n) — same as run-async (threads handle workers)
  (define (run-async/workers thunk n-workers)
    ;; The n-workers hint is noted but not used (each spawn creates its own thread)
    (run-async thunk))

  ;; ========== async-task ==========

  (define (async-task thunk)
    (let ([p (make-async-promise)])
      (Async spawn
        (lambda ()
          (let ([v (thunk)])
            (async-promise-resolve! p v))))
      p))

  (define async-task? async-promise?)

  ;; ========== async-sleep ==========

  (define (async-sleep ms)
    (Async sleep ms))

  ;; ========== Async Channels (Step 12) ==========

  ;; Get from channel. If empty, wait via Async await (suspends the task thread).
  (define (async-channel-get ch)
    (let-values ([(val ok) (channel-try-get ch)])
      (if ok
        val
        ;; Channel empty — create a promise and fulfill it when data arrives
        (let ([p (make-async-promise)])
          (fork-thread
            (lambda ()
              (let ([v (channel-get ch)])  ;; blocks this helper thread
                (async-promise-resolve! p v))))
          (Async await p)))))

  ;; Put to channel. If bounded and full, wait via Async await.
  (define (async-channel-put ch val)
    (let ([p (make-async-promise)])
      (fork-thread
        (lambda ()
          (channel-put ch val)  ;; may block if bounded and full
          (async-promise-resolve! p (void))))
      (Async await p)))

  ) ;; end library
