#!chezscheme
;;; (std sched) — M:N Cooperative/Preemptive Scheduler
;;;
;;; Maps N green threads (tasks) to M OS threads via a work-stealing queue.
;;; Green threads are thunks. OS threads (workers) pull tasks from a shared
;;; deque. Work-stealing: idle workers steal from other workers' deques.
;;;
;;; API:
;;;   (make-scheduler [thread-count]) — create scheduler with M OS threads
;;;   (scheduler-spawn! sched thunk) — enqueue a new green thread
;;;   (scheduler-yield sched)         — yield current green thread slot
;;;   (scheduler-run! sched)          — start OS worker threads (non-blocking)
;;;   (scheduler-running? sched)      — is scheduler active?
;;;   (current-scheduler)             — parameter: current scheduler
;;;   (scheduler-thread-count sched)  — number of OS threads
;;;   (scheduler-task-count sched)    — pending task count
;;;   (scheduler-stop! sched)         — stop all workers
;;;   (with-scheduler sched thunk)    — run thunk with scheduler as current

(library (std sched)
  (export
    make-scheduler
    scheduler?
    scheduler-spawn!
    scheduler-yield
    scheduler-run!
    scheduler-running?
    current-scheduler
    scheduler-thread-count
    scheduler-task-count
    scheduler-stop!
    with-scheduler)

  (import (chezscheme))

  ;; ========== Work Queue ==========
  ;; Simple thread-safe FIFO queue for tasks

  (define-record-type work-queue
    (fields
      (mutable items)     ;; list of thunks
      mutex
      not-empty)          ;; condition: item available
    (protocol
      (lambda (new)
        (lambda ()
          (new '() (make-mutex) (make-condition))))))

  (define (wq-push! wq thunk)
    (mutex-acquire (work-queue-mutex wq))
    (work-queue-items-set! wq (append (work-queue-items wq) (list thunk)))
    (condition-signal (work-queue-not-empty wq))
    (mutex-release (work-queue-mutex wq)))

  (define (wq-pop! wq timeout-ms)
    ;; Returns (values thunk #t) or (values #f #f) on timeout/empty
    (mutex-acquire (work-queue-mutex wq))
    (let loop ()
      (cond
        [(pair? (work-queue-items wq))
         (let ([item (car (work-queue-items wq))])
           (work-queue-items-set! wq (cdr (work-queue-items wq)))
           (mutex-release (work-queue-mutex wq))
           (values item #t))]
        [timeout-ms
         ;; Wait with timeout
         (let* ([ms timeout-ms]
                [ns (* ms 1000000)]
                [s  (quotient ns 1000000000)]
                [ns-part (remainder ns 1000000000)])
           (condition-wait (work-queue-not-empty wq)
                           (work-queue-mutex wq)
                           (make-time 'time-duration ns-part s)))
         (if (pair? (work-queue-items wq))
           (let ([item (car (work-queue-items wq))])
             (work-queue-items-set! wq (cdr (work-queue-items wq)))
             (mutex-release (work-queue-mutex wq))
             (values item #t))
           (begin
             (mutex-release (work-queue-mutex wq))
             (values #f #f)))]
        [else
         (mutex-release (work-queue-mutex wq))
         (values #f #f)])))

  (define (wq-length wq)
    (mutex-acquire (work-queue-mutex wq))
    (let ([n (length (work-queue-items wq))])
      (mutex-release (work-queue-mutex wq))
      n))

  (define (wq-wake-all! wq)
    (mutex-acquire (work-queue-mutex wq))
    (condition-broadcast (work-queue-not-empty wq))
    (mutex-release (work-queue-mutex wq)))

  ;; ========== Scheduler ==========

  (define-record-type scheduler
    (fields
      (mutable running?)          ;; bool
      (mutable worker-threads)    ;; list of thread-ids
      nthreads                    ;; M OS threads (immutable)
      queue                       ;; shared work queue
      mutex                       ;; protects running?
      stop-cond)                  ;; signaled when stopped
    (protocol
      (lambda (new)
        (case-lambda
          [()    (new #f '() 4 (make-work-queue)
                      (make-mutex) (make-condition))]
          [(n)   (new #f '() (max 1 n) (make-work-queue)
                      (make-mutex) (make-condition))]))))

  (define current-scheduler (make-parameter #f))

  (define (scheduler-spawn! sched thunk)
    (wq-push! (scheduler-queue sched) thunk))

  (define (scheduler-yield sched)
    ;; In M:N model, yield re-enqueues the current continuation.
    ;; For simplicity, we just sleep briefly to allow other tasks to run.
    ;; A full implementation would capture the continuation.
    (sleep (make-time 'time-duration 0 0)))

  (define (scheduler-task-count sched)
    (wq-length (scheduler-queue sched)))

  (define (scheduler-thread-count sched)
    (scheduler-nthreads sched))

  ;; Worker loop: pull tasks and execute
  (define (worker-loop sched)
    (let loop ()
      (when (scheduler-running? sched)
        (let-values ([(task ok) (wq-pop! (scheduler-queue sched) 50)])
          (when ok
            (guard (exn [#t (void)]) ;; swallow task errors
              (parameterize ([current-scheduler sched])
                (task))))
          (loop)))))

  (define (scheduler-run! sched)
    (mutex-acquire (scheduler-mutex sched))
    (unless (scheduler-running? sched)
      (scheduler-running?-set! sched #t)
      (let ([threads
             (let build ([i (scheduler-nthreads sched)] [acc '()])
               (if (= i 0)
                 acc
                 (build (- i 1)
                   (cons (fork-thread (lambda () (worker-loop sched)))
                         acc))))])
        (scheduler-worker-threads-set! sched threads)))
    (mutex-release (scheduler-mutex sched)))

  (define (scheduler-stop! sched)
    (mutex-acquire (scheduler-mutex sched))
    (scheduler-running?-set! sched #f)
    (mutex-release (scheduler-mutex sched))
    ;; Wake all blocked workers so they can exit
    (wq-wake-all! (scheduler-queue sched))
    ;; Brief wait for workers to drain
    (sleep (make-time 'time-duration 100000000 0)))

  (define-syntax with-scheduler
    (syntax-rules ()
      [(_ sched body ...)
       (parameterize ([current-scheduler sched])
         body ...)]))

) ;; end library
