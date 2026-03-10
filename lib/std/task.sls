#!chezscheme
;;; (std task) — Structured concurrency for Chez Scheme
;;;
;;; Task groups (nurseries): scoped task lifetime with cancellation
;;; No task can outlive its parent scope. If any task throws, all others
;;; are cancelled. Built on Chez OS threads + mutexes + conditions.
;;;
;;; API:
;;;   (with-task-group (lambda (tg) body ...))
;;;   (task-group-spawn tg thunk)
;;;   (task-group-async tg thunk) → future
;;;   (task-group-cancel! tg)
;;;   (make-cancel-token) / (cancelled? token) / (cancel! token)
;;;   (future-get future) — blocks until result available

(library (std task)
  (export
    with-task-group
    task-group-spawn
    task-group-async
    task-group-cancel!
    task-group?
    ;; Cancel tokens
    make-cancel-token cancelled? cancel!
    cancel-token?
    ;; Futures
    make-future future-get future-done? future?
    future-complete! future-fail!
    ;; Internal (for task-group access)
    task-group-cancel-tok)
  (import (chezscheme))

  ;; ========== Cancel Tokens ==========
  ;; Shared atomic flag for cooperative cancellation

  (define-record-type cancel-token
    (fields
      (mutable flag)    ;; #f or #t
      (immutable mutex)
      (immutable cond))
    (protocol
      (lambda (new)
        (lambda () (new #f (make-mutex) (make-condition)))))
    (sealed #t))

  (define (cancelled? tok)
    (cancel-token-flag tok))

  (define (cancel! tok)
    (unless (cancel-token-flag tok)
      (cancel-token-flag-set! tok #t)
      (with-mutex (cancel-token-mutex tok)
        (condition-broadcast (cancel-token-cond tok)))))

  ;; ========== Futures ==========
  ;; A future holds the result of an async computation

  (define-record-type future
    (fields
      (mutable result)
      (mutable exception)
      (mutable done?)
      (immutable mutex)
      (immutable cond))
    (protocol
      (lambda (new)
        (lambda () (new (void) #f #f (make-mutex) (make-condition)))))
    (sealed #t))

  (define (future-complete! fut val)
    (with-mutex (future-mutex fut)
      (future-result-set! fut val)
      (future-done?-set! fut #t)
      (condition-broadcast (future-cond fut))))

  (define (future-fail! fut exn)
    (with-mutex (future-mutex fut)
      (future-exception-set! fut exn)
      (future-done?-set! fut #t)
      (condition-broadcast (future-cond fut))))

  (define (future-get fut)
    (with-mutex (future-mutex fut)
      (let loop ()
        (cond
          [(future-done? fut)
           (if (future-exception fut)
             (raise (future-exception fut))
             (future-result fut))]
          [else
           (condition-wait (future-cond fut) (future-mutex fut))
           (loop)]))))

  ;; ========== Task Group ==========

  (define-record-type task-group
    (fields
      (immutable cancel-tok)    ;; shared cancellation token
      (mutable active-count)    ;; number of running tasks
      (mutable first-exn)       ;; first exception from any task
      (immutable mutex)
      (immutable all-done-cond) ;; signaled when active-count reaches 0
      )
    (protocol
      (lambda (new)
        (lambda ()
          (new (make-cancel-token) 0 #f
               (make-mutex) (make-condition)))))
    (sealed #t))

  (define (task-group-cancel! tg)
    (cancel! (task-group-cancel-tok tg)))

  ;; Spawn a fire-and-forget task in the group
  (define (task-group-spawn tg thunk)
    (with-mutex (task-group-mutex tg)
      (task-group-active-count-set! tg
        (fx+ (task-group-active-count tg) 1)))
    (fork-thread
      (lambda ()
        (guard (exn
                 [#t
                  ;; Record first exception and cancel the group
                  (with-mutex (task-group-mutex tg)
                    (unless (task-group-first-exn tg)
                      (task-group-first-exn-set! tg exn)))
                  (task-group-cancel! tg)
                  (task-finished! tg)])
          (thunk)
          (task-finished! tg)))))

  ;; Spawn a task that returns a future
  (define (task-group-async tg thunk)
    (let ([fut (make-future)])
      (with-mutex (task-group-mutex tg)
        (task-group-active-count-set! tg
          (fx+ (task-group-active-count tg) 1)))
      (fork-thread
        (lambda ()
          (guard (exn
                   [#t
                    (future-fail! fut exn)
                    (with-mutex (task-group-mutex tg)
                      (unless (task-group-first-exn tg)
                        (task-group-first-exn-set! tg exn)))
                    (task-group-cancel! tg)
                    (task-finished! tg)])
            (let ([result (thunk)])
              (future-complete! fut result)
              (task-finished! tg)))))
      fut))

  ;; Decrement active count and signal if zero
  (define (task-finished! tg)
    (with-mutex (task-group-mutex tg)
      (task-group-active-count-set! tg
        (fx- (task-group-active-count tg) 1))
      (when (fx= (task-group-active-count tg) 0)
        (condition-broadcast (task-group-all-done-cond tg)))))

  ;; Wait for all tasks to complete
  (define (task-group-wait! tg)
    (with-mutex (task-group-mutex tg)
      (let loop ()
        (unless (fx= (task-group-active-count tg) 0)
          (condition-wait (task-group-all-done-cond tg) (task-group-mutex tg))
          (loop)))))

  ;; ========== with-task-group ==========
  ;; Scoped task execution: body receives the task group, and all tasks
  ;; must complete before the scope exits. If any task throws, the first
  ;; exception is re-raised after all tasks finish.

  (define (with-task-group proc)
    (let ([tg (make-task-group)])
      (let ([result
             (guard (exn
                      [#t
                       ;; Body threw — cancel remaining tasks and wait
                       (task-group-cancel! tg)
                       (task-group-wait! tg)
                       (raise exn)])
               (call-with-values (lambda () (proc tg)) list))])
        ;; Body returned — wait for all spawned tasks
        (task-group-wait! tg)
        ;; Re-raise first task exception if any
        (let ([exn (task-group-first-exn tg)])
          (when exn (raise exn)))
        ;; Return the body's result(s)
        (apply values result))))

  ) ;; end library
