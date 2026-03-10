#!chezscheme
;;; (std actor scheduler) — Work-stealing M:N thread pool
;;;
;;; N OS threads, each with a work-stealing deque.
;;; Owner pushes/pops own deque; idle workers steal from others.
;;; Tasks are zero-argument thunks.

(library (std actor scheduler)
  (export
    make-scheduler
    scheduler?
    scheduler-start!
    scheduler-stop!
    scheduler-submit!
    scheduler-worker-count
    current-scheduler
    default-scheduler
    cpu-count)
  (import (chezscheme) (std actor deque))

  ;; Per-worker state (one per OS thread in the pool)
  (define-record-type worker
    (fields
      (immutable id)          ;; integer index 0..N-1
      (immutable deque)       ;; this worker's task deque
      (mutable running?))
    (protocol
      (lambda (new)
        (lambda (id)
          (new id (make-work-deque) #t))))
    (sealed #t))

  ;; The scheduler: a pool of workers
  (define-record-type scheduler
    (fields
      (immutable workers)        ;; vector of worker records
      (immutable mutex)
      (immutable work-available) ;; condition: broadcast when new task added
      (mutable running?))
    (protocol
      (lambda (new)
        (lambda (n)
          (new (let ([v (make-vector n)])
                 (do ([i 0 (fx+ i 1)]) ((fx= i n) v)
                   (vector-set! v i (make-worker i))))
               (make-mutex)
               (make-condition)
               #f))))
    (sealed #t))

  ;; Thread-local: which worker is running on this thread
  (define current-worker    (make-thread-parameter #f))
  (define current-scheduler (make-thread-parameter #f))
  (define default-scheduler (make-parameter #f))

  ;; Submit a task to the scheduler.
  ;; Fast path: from worker thread → push own deque.
  ;; Slow path: from outside → push a random worker's deque.
  (define (scheduler-submit! sched thunk)
    (let ([w (current-worker)])
      (if w
        (deque-push-bottom! (worker-deque w) thunk)
        (let* ([workers (scheduler-workers sched)]
               [n       (vector-length workers)]
               [idx     (random n)]
               [target  (vector-ref workers idx)])
          (deque-push-bottom! (worker-deque target) thunk))))
    ;; Wake one sleeping worker
    (with-mutex (scheduler-mutex sched)
      (condition-signal (scheduler-work-available sched))))

  ;; The main loop for each worker thread
  (define (worker-run! sched w)
    (current-worker w)
    (current-scheduler sched)
    (let* ([workers (scheduler-workers sched)]
           [n       (vector-length workers)]
           [my-id   (worker-id w)])
      (let loop ()
        (when (scheduler-running? sched)
          ;; 1. Try own deque first (LIFO — hot cache)
          (let ([task (deque-pop-bottom! (worker-deque w))])
            (if task
              (begin
                (guard (exn [#t (void)])  ;; isolate task crashes from worker
                  (task))
                (loop))
              ;; 2. Try stealing from other workers (round-robin)
              (let try-steal ([attempts 0])
                (if (fx>= attempts n)
                  ;; 3. All deques empty — wait for work
                  (begin
                    (mutex-acquire (scheduler-mutex sched))
                    ;; Re-check before sleeping (prevent lost wakeup)
                    (let ([my-task (deque-pop-bottom! (worker-deque w))])
                      (if my-task
                        (begin
                          (mutex-release (scheduler-mutex sched))
                          (guard (exn [#t (void)]) (my-task))
                          (loop))
                        (begin
                          (when (scheduler-running? sched)
                            (condition-wait (scheduler-work-available sched)
                                            (scheduler-mutex sched)))
                          (mutex-release (scheduler-mutex sched))
                          (loop)))))
                  (let* ([victim-idx (fxmod (fx+ my-id attempts 1) n)]
                         [victim     (vector-ref workers victim-idx)])
                    (let-values ([(task ok) (deque-steal-top! (worker-deque victim))])
                      (if ok
                        (begin
                          (guard (exn [#t (void)]) (task))
                          (loop))
                        (try-steal (fx+ attempts 1)))))))))))))

  (define (scheduler-worker-count sched)
    (vector-length (scheduler-workers sched)))

  ;; Start the scheduler: fork N worker threads
  (define (scheduler-start! sched)
    (scheduler-running?-set! sched #t)
    (let ([workers (scheduler-workers sched)])
      (do ([i 0 (fx+ i 1)])
          ((fx= i (vector-length workers)))
        (let ([w (vector-ref workers i)])
          (fork-thread (lambda () (worker-run! sched w))))))
    sched)

  ;; Stop the scheduler: signal all workers to exit
  (define (scheduler-stop! sched)
    (scheduler-running?-set! sched #f)
    (with-mutex (scheduler-mutex sched)
      (condition-broadcast (scheduler-work-available sched))))

  ;; Read CPU count from /proc/cpuinfo on Linux; fallback to 4
  (define (cpu-count)
    (guard (exn [#t 4])
      (let ([p (open-input-file "/proc/cpuinfo")])
        (let loop ([n 0])
          (let ([line (get-line p)])
            (cond
              [(eof-object? line) (close-port p) (fxmax n 1)]
              [(and (fx>= (string-length line) 9)
                    (string=? (substring line 0 9) "processor"))
               (loop (fx+ n 1))]
              [else (loop n)]))))))

  ) ;; end library
