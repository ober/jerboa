#!chezscheme
;;; (std net workpool) — Thread pool for blocking work offload
;;;
;;; Fibers park while blocking work (DNS, file I/O, etc.) runs on
;;; a small pool of OS threads. The pool thread wakes the fiber
;;; when the work completes.
;;;
;;; API:
;;;   (make-work-pool n)       — create pool with n worker threads
;;;   (work-pool-start! pool)  — start the worker threads
;;;   (work-pool-stop! pool)   — drain and stop workers
;;;   (work-pool-submit! pool thunk) — run thunk on pool, park fiber, return result

(library (std net workpool)
  (export
    make-work-pool
    work-pool?
    work-pool-start!
    work-pool-stop!
    work-pool-submit!)

  (import (chezscheme)
          (std fiber))

  ;; ========== Work item ==========

  (define-record-type work-item
    (fields
      (immutable thunk)        ;; zero-arg procedure to run (blocking)
      (immutable fiber)        ;; parked fiber to wake
      (mutable result)         ;; set by worker thread
      (mutable error)          ;; set on exception
      (immutable gate))        ;; fiber's gate box
    (protocol
      (lambda (new)
        (lambda (thunk fiber gate)
          (new thunk fiber #f #f gate)))))

  ;; ========== Thread-safe work queue ==========

  (define-record-type work-queue
    (fields
      (mutable items)          ;; list of work-item
      (immutable mutex)
      (immutable cv)
      (mutable closed?))
    (protocol
      (lambda (new)
        (lambda ()
          (new '() (make-mutex) (make-condition) #f)))))

  (define (wq-enqueue! wq item)
    (mutex-acquire (work-queue-mutex wq))
    (work-queue-items-set! wq (append (work-queue-items wq) (list item)))
    (condition-signal (work-queue-cv wq))
    (mutex-release (work-queue-mutex wq)))

  (define (wq-dequeue! wq)
    ;; Block until an item is available or queue is closed.
    ;; Returns #f when closed and empty.
    (mutex-acquire (work-queue-mutex wq))
    (let loop ()
      (cond
        [(not (null? (work-queue-items wq)))
         (let ([item (car (work-queue-items wq))])
           (work-queue-items-set! wq (cdr (work-queue-items wq)))
           (mutex-release (work-queue-mutex wq))
           item)]
        [(work-queue-closed? wq)
         (mutex-release (work-queue-mutex wq))
         #f]
        [else
         (condition-wait (work-queue-cv wq) (work-queue-mutex wq))
         (loop)])))

  (define (wq-close! wq)
    (mutex-acquire (work-queue-mutex wq))
    (work-queue-closed?-set! wq #t)
    (condition-broadcast (work-queue-cv wq))
    (mutex-release (work-queue-mutex wq)))

  ;; ========== Work pool ==========

  (define-record-type work-pool
    (fields
      (immutable nthreads)
      (immutable queue)
      (mutable threads)
      (mutable running?))
    (protocol
      (lambda (new)
        (lambda (n)
          (new (max 1 n) (make-work-queue) '() #f)))))

  (define (worker-loop pool)
    (let ([wq (work-pool-queue pool)])
      (let loop ()
        (let ([item (wq-dequeue! wq)])
          (when item
            ;; Execute the blocking work
            (guard (exn [#t
              (work-item-error-set! item exn)])
              (work-item-result-set! item ((work-item-thunk item))))
            ;; Wake the parked fiber by opening its gate
            (let ([gate (work-item-gate item)])
              (set-box! gate 'done))
            (wake-fiber! (work-item-fiber item))
            (loop))))))

  (define (work-pool-start! pool)
    (work-pool-running?-set! pool #t)
    (work-pool-threads-set! pool
      (let loop ([i 0] [acc '()])
        (if (= i (work-pool-nthreads pool))
          acc
          (loop (+ i 1)
                (cons (fork-thread (lambda () (worker-loop pool))) acc))))))

  (define (work-pool-stop! pool)
    (work-pool-running?-set! pool #f)
    (wq-close! (work-pool-queue pool))
    ;; Give threads time to drain
    (sleep (make-time 'time-duration 100000000 0)))

  ;; Submit blocking work from a fiber.
  ;; Parks the current fiber until the work completes.
  ;; Returns the result of thunk, or re-raises any exception.
  (define (work-pool-submit! pool thunk)
    (let* ([f (fiber-self)]
           [gate (box 'channel)]
           [item (make-work-item thunk f gate)])
      ;; Set up fiber for parking
      (fiber-gate-set! f gate)
      ;; Enqueue work
      (wq-enqueue! (work-pool-queue pool) item)
      ;; Park the fiber — will be woken by worker thread
      (set-timer 1)
      (spin-until-gate gate)
      (fiber-gate-set! f #f)
      ;; Check for error
      (when (work-item-error item)
        (raise (work-item-error item)))
      (work-item-result item)))

) ;; end library
