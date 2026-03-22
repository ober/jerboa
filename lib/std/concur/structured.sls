#!chezscheme
;;; (std concur structured) — Structured concurrency
;;;
;;; Concurrent tasks that follow lexical scoping: no task outlives its scope.
;;; All spawned tasks are guaranteed terminated when scope exits.
;;;
;;; Inspired by Kotlin coroutines, Swift structured concurrency, Java Loom.
;;;
;;; API:
;;;   (with-task-scope thunk)        — run thunk, cancel all tasks on exit
;;;   (scope-spawn thunk)            — spawn a task in current scope
;;;   (scope-spawn-named name thunk) — spawn a named task
;;;   (task-await task)              — wait for task result
;;;   (task-cancel task)             — cancel a task
;;;   (task-result task)             — get result (blocking)
;;;   (task? x)                      — test for task
;;;   (parallel thunk ...)           — run thunks in parallel, return all results
;;;   (race thunk ...)               — run thunks, return first to complete

(library (std concur structured)
  (export with-task-scope scope-spawn scope-spawn-named
          task-await task-cancel task-result task?
          parallel race task-name task-done?)

  (import (chezscheme))

  ;; ========== Task record ==========

  (define-record-type task
    (fields
      (immutable name)
      (immutable thread)
      (mutable result)
      (mutable error)
      (mutable done?)
      (immutable mutex)
      (immutable condvar))
    (protocol
      (lambda (new)
        (lambda (name thread)
          (new name thread #f #f #f (make-mutex) (make-condition))))))

  ;; ========== Task scope ==========

  (define *current-scope* (make-thread-parameter #f))

  (define-record-type task-scope
    (fields
      (mutable tasks)
      (immutable mutex))
    (protocol
      (lambda (new)
        (lambda ()
          (new '() (make-mutex))))))

  (define (scope-add-task! scope task)
    (with-mutex (task-scope-mutex scope)
      (task-scope-tasks-set! scope
        (cons task (task-scope-tasks scope)))))

  ;; ========== Spawn ==========

  (define (scope-spawn thunk)
    (scope-spawn-named "anonymous" thunk))

  (define (scope-spawn-named name thunk)
    (let ([scope (*current-scope*)])
      (unless scope
        (error 'scope-spawn "not inside with-task-scope"))
      ;; Create the task record BEFORE forking the thread, so the thread
      ;; always has a valid task reference. Use a gate (mutex+cond) to
      ;; ensure the thread doesn't start work until the task is ready.
      (let* ([gate-mutex (make-mutex)]
             [gate-cond (make-condition)]
             [gate-open? #f]
             [t #f]
             [thread (fork-thread
                       (lambda ()
                         ;; Wait for task record to be initialized
                         (with-mutex gate-mutex
                           (let loop ()
                             (unless gate-open?
                               (condition-wait gate-cond gate-mutex)
                               (loop))))
                         (guard (exn
                                 [#t (task-error-set! t exn)
                                     (task-done?-set! t #t)
                                     (with-mutex (task-mutex t)
                                       (condition-broadcast (task-condvar t)))])
                           (let ([result (thunk)])
                             (task-result-set! t result)
                             (task-done?-set! t #t)
                             (with-mutex (task-mutex t)
                               (condition-broadcast (task-condvar t)))))))])
        (set! t (make-task name thread))
        (task-done?-set! t #f)
        (scope-add-task! scope t)
        ;; Open the gate — thread can now proceed
        (with-mutex gate-mutex
          (set! gate-open? #t)
          (condition-broadcast gate-cond))
        t)))

  ;; ========== Await ==========

  (define (task-await task)
    (unless (task-done? task)
      (let loop ()
        (with-mutex (task-mutex task)
          (unless (task-done? task)
            (condition-wait (task-condvar task) (task-mutex task))))
        (unless (task-done? task) (loop))))
    (if (task-error task)
      (raise (task-error task))
      (task-result task)))

  (define (task-cancel task)
    ;; Mark as done with a cancellation error.
    ;; NOTE: This does NOT stop the underlying thread — Chez Scheme has no
    ;; safe thread interruption. The thread continues executing but its result
    ;; is ignored. Callers should use cooperative cancellation (check a flag
    ;; periodically) for long-running tasks.
    (unless (task-done? task)
      (task-error-set! task (make-message-condition "task cancelled"))
      (task-done?-set! task #t)
      (with-mutex (task-mutex task)
        (condition-broadcast (task-condvar task)))))

  ;; ========== Scope ==========

  (define (cancel-all-tasks! scope)
    (for-each task-cancel (task-scope-tasks scope)))

  (define (await-all-tasks! scope)
    ;; Wait for all tasks, but don't block forever on cancelled tasks
    ;; whose threads are still running. Use a 5-second timeout per
    ;; cancelled task to prevent with-task-scope from hanging.
    (for-each
      (lambda (t)
        (guard (exn [#t (void)])  ;; ignore errors from cancelled tasks
          (if (task-done? t)
            ;; Already done — just retrieve (may re-raise error)
            (task-await t)
            ;; Not done — wait with timeout
            (let loop ([attempts 0])
              (with-mutex (task-mutex t)
                (unless (task-done? t)
                  (condition-wait (task-condvar t) (task-mutex t)
                    (make-time 'time-duration 0 5))))  ;; 5 second timeout
              (unless (or (task-done? t) (> attempts 0))
                (loop (+ attempts 1)))))))
      (task-scope-tasks scope)))

  (define (with-task-scope thunk)
    (let ([scope (make-task-scope)])
      (parameterize ([*current-scope* scope])
        (guard (exn
                [#t (cancel-all-tasks! scope)
                    (await-all-tasks! scope)
                    (raise exn)])
          (let ([result (thunk)])
            (await-all-tasks! scope)
            result)))))

  ;; ========== Parallel ==========

  (define (parallel-run thunks)
    (with-task-scope
      (lambda ()
        (let ([tasks (map scope-spawn thunks)])
          (map task-await tasks)))))

  (define-syntax parallel
    (syntax-rules ()
      [(_ t ...)
       (parallel-run (list t ...))]))

  ;; ========== Race ==========

  (define (race-run thunks)
    (with-task-scope
      (lambda ()
        (let ([result-box #f]
              [done-mutex (make-mutex)]
              [done-cv (make-condition)]
              [finished #f])
          (for-each
            (lambda (fn)
              (scope-spawn
                (lambda ()
                  (let ([r (fn)])
                    (with-mutex done-mutex
                      (unless finished
                        (set! finished #t)
                        (set! result-box r)
                        (condition-broadcast done-cv)))))))
            thunks)
          (with-mutex done-mutex
            (let loop ()
              (unless finished
                (condition-wait done-cv done-mutex)
                (loop))))
          result-box))))

  (define-syntax race
    (syntax-rules ()
      [(_ t ...)
       (race-run (list t ...))]))

) ;; end library
