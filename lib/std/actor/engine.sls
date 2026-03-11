#!chezscheme
;;; (std actor engine) — Engine-based preemptive actor scheduling
;;;
;;; Chez Scheme's engine API provides preemptible computations via
;;; "fuel" (instruction quanta).  This library builds an actor pool
;;; where each actor is run inside an engine so that long-running
;;; behaviors are automatically time-sliced.
;;;
;;; API:
;;;   (make-engine-pool #:workers n #:fuel f) -> engine-pool
;;;   (engine-pool? x)
;;;   (spawn-engine-actor pool behavior) -> actor-ref
;;;   (engine-pool-submit! pool thunk)
;;;   (engine-pool-stop! pool)
;;;   (engine-pool-worker-count pool)
;;;   (default-fuel) -> 10000
;;;
;;; How it works:
;;;   Each worker OS thread runs a tight loop that dequeues thunks and
;;;   wraps them in Chez engines.  If a thunk's engine runs out of fuel
;;;   (the computation is still in progress) the remaining engine is
;;;   re-queued so another worker can eventually run it.  When the
;;;   engine completes the result is discarded (fire-and-forget
;;;   semantics, matching the actor model).

(library (std actor engine)
  (export
    make-engine-pool
    engine-pool?
    spawn-engine-actor
    engine-pool-submit!
    engine-pool-stop!
    engine-pool-worker-count
    default-fuel)

  (import (chezscheme) (std actor core))

  ;; -------- Default fuel quanta --------

  (define (default-fuel) 10000)

  ;; -------- Shared task queue --------
  ;; A simple mutex-protected FIFO of thunks / pending engines.
  ;; Each item is either:
  ;;   (cons 'thunk  thunk)      — not yet started, wrap in make-engine
  ;;   (cons 'engine engine-fn)  — partially run, resume with more fuel

  (define-record-type eng-task-queue
    (fields
      (immutable mutex)
      (immutable not-empty)   ;; condition variable
      (mutable   head)        ;; list: items ready to dequeue
      (mutable   tail))       ;; list: newly enqueued items (reversed)
    (protocol
      (lambda (new)
        (lambda ()
          (new (make-mutex)
               (make-condition)
               '()
               '()))))
    (sealed #t))

  (define (tq-enqueue! tq item)
    (with-mutex (eng-task-queue-mutex tq)
      (eng-task-queue-tail-set! tq (cons item (eng-task-queue-tail tq)))
      (condition-signal (eng-task-queue-not-empty tq))))

  ;; Blocking dequeue.  Returns an item, or #f when the pool is stopping.
  (define (tq-dequeue! tq running-thunk)
    (mutex-acquire (eng-task-queue-mutex tq))
    (let loop ()
      (cond
        ;; Head has items — take from front
        [(pair? (eng-task-queue-head tq))
         (let ([item (car (eng-task-queue-head tq))])
           (eng-task-queue-head-set! tq (cdr (eng-task-queue-head tq)))
           (mutex-release (eng-task-queue-mutex tq))
           item)]
        ;; Promote tail into head
        [(pair? (eng-task-queue-tail tq))
         (eng-task-queue-head-set! tq (reverse (eng-task-queue-tail tq)))
         (eng-task-queue-tail-set! tq '())
         (loop)]
        ;; Empty — wait if still running
        [(running-thunk)
         (condition-wait (eng-task-queue-not-empty tq)
                         (eng-task-queue-mutex tq))
         (loop)]
        ;; Stopping — release and signal shutdown
        [else
         (mutex-release (eng-task-queue-mutex tq))
         #f])))

  ;; -------- Engine pool record --------
  ;; Use a distinct record name (eng-pool-rec) so we can provide a
  ;; user-facing make-engine-pool procedure with keyword parsing.

  (define-record-type eng-pool-rec
    (fields
      (immutable queue)          ;; eng-task-queue
      (immutable fuel)           ;; integer: ticks per engine slice
      (immutable nworkers)       ;; integer: number of OS threads
      (mutable   running?))      ;; boolean
    (protocol
      (lambda (new)
        (lambda (nworkers fuel)
          (new (make-eng-task-queue) fuel nworkers #f))))
    (sealed #t))

  (define engine-pool? eng-pool-rec?)

  ;; -------- Worker loop --------
  ;;
  ;; NOTE: In Chez Scheme 10.x the engine API uses INVERTED semantics
  ;; compared to the traditional (Dybvig) documentation:
  ;;
  ;;   expire-proc   — called when the computation FINISHES within the fuel
  ;;                   budget: (expire-proc remaining-fuel result)
  ;;   complete-proc — called when the computation is PREEMPTED (fuel
  ;;                   exhausted): (complete-proc new-engine)
  ;;
  ;; We rename the parameters accordingly: done-proc / preempt-proc.

  (define (worker-loop pool)
    (let ([q    (eng-pool-rec-queue pool)]
          [fuel (eng-pool-rec-fuel  pool)])
      (let loop ()
        (let ([item (tq-dequeue! q (lambda () (eng-pool-rec-running? pool)))])
          (when item
            ;; Build or retrieve the engine
            (let ([eng (case (car item)
                         [(thunk)  (make-engine (cdr item))]
                         [(engine) (cdr item)]
                         [else
                          (error 'engine-pool-worker
                                 "unknown task type" (car item))])])
              ;; Run the engine for one fuel slice.
              (eng fuel
                   ;; done-proc (called "expire" in Chez): computation finished
                   ;; (remaining-fuel result) — result is discarded (fire-and-forget)
                   (lambda (remaining result) (void))
                   ;; preempt-proc (called "complete" in Chez): fuel exhausted
                   ;; (new-engine) — re-enqueue the continuation
                   (lambda (new-engine)
                     (tq-enqueue! q (cons 'engine new-engine)))))
            (loop))))))

  ;; -------- Public API --------

  ;; Keyword predicate helpers.
  ;; In Chez Scheme, the #:foo syntax at a call site evaluates the symbol
  ;; as a variable, so callers must quote keyword symbols: '#:workers.
  ;; We compare by symbol name string (stripping a leading "#:" if present).
  (define (kw=? sym name)
    (and (symbol? sym)
         (let ([s (symbol->string sym)])
           (or (string=? s name)
               ;; Accept symbol with literal "#:" prefix in case the reader
               ;; is configured to preserve it (some Chez versions / modes).
               (and (fx>= (string-length s) 2)
                    (char=? (string-ref s 0) #\#)
                    (char=? (string-ref s 1) #\:)
                    (string=? (substring s 2 (string-length s)) name))))))

  ;; (make-engine-pool '#:workers n '#:fuel f)
  ;; OR (make-engine-pool) for defaults (4 workers, default-fuel ticks).
  ;; OR (make-engine-pool n) for n workers with default fuel.
  ;; OR (make-engine-pool n f) for n workers with f fuel.
  (define (make-engine-pool . args)
    (define (start! workers fuel)
      (let ([pool (make-eng-pool-rec workers fuel)])
        (eng-pool-rec-running?-set! pool #t)
        (do ([i 0 (fx+ i 1)])
            ((fx= i workers))
          (fork-thread (lambda () (worker-loop pool))))
        pool))
    (cond
      ;; No args — defaults
      [(null? args)
       (start! 4 (default-fuel))]
      ;; First arg is a number — positional: (workers) or (workers fuel)
      [(and (number? (car args)) (null? (cdr args)))
       (start! (car args) (default-fuel))]
      [(and (number? (car args)) (pair? (cdr args)) (number? (cadr args))
            (null? (cddr args)))
       (start! (car args) (cadr args))]
      ;; Keyword-style: '#:workers n '#:fuel f (args are quoted symbols)
      [else
       (let parse ([rest args] [workers 4] [fuel (default-fuel)])
         (cond
           [(null? rest) (start! workers fuel)]
           [(and (kw=? (car rest) "workers") (pair? (cdr rest)))
            (parse (cddr rest) (cadr rest) fuel)]
           [(and (kw=? (car rest) "fuel") (pair? (cdr rest)))
            (parse (cddr rest) workers (cadr rest))]
           [else
            (error 'make-engine-pool
                   "unexpected argument (use '#:workers n or '#:fuel f)"
                   (car rest))]))]))

  (define (engine-pool-submit! pool thunk)
    (unless (eng-pool-rec-running? pool)
      (error 'engine-pool-submit! "pool has been stopped" pool))
    (tq-enqueue! (eng-pool-rec-queue pool) (cons 'thunk thunk)))

  (define (engine-pool-stop! pool)
    (eng-pool-rec-running?-set! pool #f)
    ;; Broadcast to wake all sleeping workers so they exit their loops
    (with-mutex (eng-task-queue-mutex (eng-pool-rec-queue pool))
      (condition-broadcast
        (eng-task-queue-not-empty (eng-pool-rec-queue pool)))))

  (define (engine-pool-worker-count pool)
    (eng-pool-rec-nworkers pool))

  ;; Spawn an actor that runs preemptively inside the engine pool.
  ;;
  ;; The pool is installed as the global actor scheduler so that all
  ;; subsequent scheduling decisions for this actor land in the pool's
  ;; engine queue, giving preemptive time-slicing.
  ;;
  ;; Callers that want multiple pools should set the scheduler themselves
  ;; before spawning; this convenience wrapper sets it once and leaves it.
  (define (spawn-engine-actor pool behavior)
    ;; Build a submit procedure matching set-actor-scheduler!'s contract:
    ;; it receives a zero-argument thunk and submits it to the pool.
    (set-actor-scheduler!
      (lambda (thunk) (engine-pool-submit! pool thunk)))
    (spawn-actor behavior))

  ) ;; end library
