#!chezscheme
;;; (std concur util) — Extended concurrency utilities
;;;
;;; Complements the existing scheduler and actor system with:
;;;   - Barriers (cyclic, reusable)
;;;   - Semaphores
;;;   - Read-write locks
;;;   - Simple thread pools
;;;   - Futures / promises
;;;   - Count-down latches

(library (std concur util)
  (export
    ;; Barriers
    make-barrier
    barrier?
    barrier-wait!
    barrier-reset!
    ;; Semaphores
    make-semaphore
    semaphore?
    semaphore-acquire!
    semaphore-release!
    semaphore-count
    semaphore-try-acquire!
    ;; Read-write locks
    make-rwlock
    rwlock?
    rwlock-read-lock!
    rwlock-read-unlock!
    rwlock-write-lock!
    rwlock-write-unlock!
    with-read-lock
    with-write-lock
    ;; Thread pools
    make-thread-pool
    thread-pool?
    thread-pool-submit!
    thread-pool-stop!
    thread-pool-worker-count
    ;; Futures
    make-future
    future?
    future-force
    future-ready?
    future-map
    spawn-future
    ;; Latches
    make-latch
    latch-count-down!
    latch-await)

  (import (chezscheme))

  ;; ========== Barrier ==========
  ;;
  ;; A cyclic barrier for N threads.  All threads block at barrier-wait!
  ;; until the Nth thread arrives, at which point all are released.
  ;; A "generation" counter lets the barrier be reset and reused.

  (define-record-type %barrier
    (fields
      (immutable total)      ;; N threads needed to trip
      (immutable mutex)
      (immutable condition)
      (mutable   count)      ;; how many have arrived so far
      (mutable   generation) ;; increments each time barrier trips
      (mutable   broken?))   ;; if reset mid-wait
    (protocol
      (lambda (new)
        (lambda (n)
          (unless (and (fixnum? n) (fx> n 0))
            (error 'make-barrier "count must be a positive fixnum" n))
          (new n (make-mutex) (make-condition) 0 0 #f))))
    (sealed #t))

  (define make-barrier make-%barrier)
  (define (barrier? x) (%barrier? x))

  (define (barrier-wait! b)
    (with-mutex (%barrier-mutex b)
      (let ([gen (%barrier-generation b)])
        (%barrier-count-set! b (fx+ (%barrier-count b) 1))
        (cond
          [(fx= (%barrier-count b) (%barrier-total b))
           ;; We are the last thread — trip the barrier
           (%barrier-count-set! b 0)
           (%barrier-generation-set! b (fx+ gen 1))
           (condition-broadcast (%barrier-condition b))]
          [else
           ;; Wait until our generation advances
           (let loop ()
             (when (and (fx= (%barrier-generation b) gen)
                        (not (%barrier-broken? b)))
               (condition-wait (%barrier-condition b) (%barrier-mutex b))
               (loop)))]))))

  (define (barrier-reset! b)
    (with-mutex (%barrier-mutex b)
      (%barrier-count-set! b 0)
      (%barrier-generation-set! b (fx+ (%barrier-generation b) 1))
      (%barrier-broken?-set! b #f)
      (condition-broadcast (%barrier-condition b))))

  ;; ========== Semaphore ==========
  ;;
  ;; Classic counting semaphore.

  (define-record-type %semaphore
    (fields
      (immutable mutex)
      (immutable condition)
      (mutable   count))
    (protocol
      (lambda (new)
        (lambda (initial)
          (unless (and (integer? initial) (>= initial 0))
            (error 'make-semaphore "initial count must be a non-negative integer" initial))
          (new (make-mutex) (make-condition) initial))))
    (sealed #t))

  (define make-semaphore make-%semaphore)
  (define (semaphore? x) (%semaphore? x))

  (define (semaphore-count s)
    (with-mutex (%semaphore-mutex s)
      (%semaphore-count s)))

  (define (semaphore-acquire! s)
    (with-mutex (%semaphore-mutex s)
      (let loop ()
        (if (> (%semaphore-count s) 0)
          (%semaphore-count-set! s (- (%semaphore-count s) 1))
          (begin
            (condition-wait (%semaphore-condition s) (%semaphore-mutex s))
            (loop))))))

  (define (semaphore-try-acquire! s)
    (with-mutex (%semaphore-mutex s)
      (if (> (%semaphore-count s) 0)
        (begin
          (%semaphore-count-set! s (- (%semaphore-count s) 1))
          #t)
        #f)))

  (define (semaphore-release! s)
    (with-mutex (%semaphore-mutex s)
      (%semaphore-count-set! s (+ (%semaphore-count s) 1))
      (condition-signal (%semaphore-condition s))))

  ;; ========== Read-write lock ==========
  ;;
  ;; Multiple readers / single writer.
  ;; Writers wait until all readers finish; readers wait during writes.
  ;; Writers get priority when pending (writer-waiting? flag).

  (define-record-type %rwlock
    (fields
      (immutable mutex)
      (immutable read-ok)    ;; condition: readers can proceed
      (immutable write-ok)   ;; condition: writer can proceed
      (mutable   readers)    ;; count of active readers
      (mutable   writer?)    ;; is there an active writer?
      (mutable   writers-waiting)) ;; count of writers waiting
    (protocol
      (lambda (new)
        (lambda ()
          (new (make-mutex)
               (make-condition)
               (make-condition)
               0 #f 0))))
    (sealed #t))

  (define make-rwlock make-%rwlock)
  (define (rwlock? x) (%rwlock? x))

  (define (rwlock-read-lock! rw)
    (with-mutex (%rwlock-mutex rw)
      (let loop ()
        ;; Wait if there's an active or pending writer
        (when (or (%rwlock-writer? rw) (> (%rwlock-writers-waiting rw) 0))
          (condition-wait (%rwlock-read-ok rw) (%rwlock-mutex rw))
          (loop)))
      (%rwlock-readers-set! rw (+ (%rwlock-readers rw) 1))))

  (define (rwlock-read-unlock! rw)
    (with-mutex (%rwlock-mutex rw)
      (%rwlock-readers-set! rw (- (%rwlock-readers rw) 1))
      (when (= (%rwlock-readers rw) 0)
        (condition-signal (%rwlock-write-ok rw)))))

  (define (rwlock-write-lock! rw)
    (with-mutex (%rwlock-mutex rw)
      (%rwlock-writers-waiting-set! rw (+ (%rwlock-writers-waiting rw) 1))
      (let loop ()
        (when (or (> (%rwlock-readers rw) 0) (%rwlock-writer? rw))
          (condition-wait (%rwlock-write-ok rw) (%rwlock-mutex rw))
          (loop)))
      (%rwlock-writers-waiting-set! rw (- (%rwlock-writers-waiting rw) 1))
      (%rwlock-writer?-set! rw #t)))

  (define (rwlock-write-unlock! rw)
    (with-mutex (%rwlock-mutex rw)
      (%rwlock-writer?-set! rw #f)
      (if (> (%rwlock-writers-waiting rw) 0)
        ;; Prefer waiting writers
        (condition-signal (%rwlock-write-ok rw))
        ;; Wake all readers
        (condition-broadcast (%rwlock-read-ok rw)))))

  (define-syntax with-read-lock
    (syntax-rules ()
      [(_ rw body ...)
       (dynamic-wind
         (lambda () (rwlock-read-lock! rw))
         (lambda () body ...)
         (lambda () (rwlock-read-unlock! rw)))]))

  (define-syntax with-write-lock
    (syntax-rules ()
      [(_ rw body ...)
       (dynamic-wind
         (lambda () (rwlock-write-lock! rw))
         (lambda () body ...)
         (lambda () (rwlock-write-unlock! rw)))]))

  ;; ========== Thread pool ==========
  ;;
  ;; Simple fixed-size thread pool backed by a shared FIFO task queue.

  (define-record-type %thread-pool
    (fields
      (immutable mutex)
      (immutable condition)   ;; workers wait on this for tasks
      (mutable   queue)       ;; list of thunks (front = next to run)
      (mutable   running?)
      (mutable   workers))    ;; list of thread objects
    (sealed #t))

  (define (thread-pool? x) (%thread-pool? x))

  (define (%pool-worker-loop pool)
    (let loop ()
      (let ([task
             (with-mutex (%thread-pool-mutex pool)
               (let wait ()
                 (cond
                   [(pair? (%thread-pool-queue pool))
                    (let ([t (car (%thread-pool-queue pool))])
                      (%thread-pool-queue-set! pool
                        (cdr (%thread-pool-queue pool)))
                      t)]
                   [(not (%thread-pool-running? pool))
                    #f]
                   [else
                    (condition-wait (%thread-pool-condition pool)
                                    (%thread-pool-mutex pool))
                    (wait)])))])
        (when task
          (guard (exn [#t (void)])
            (task))
          (loop)))))

  (define (make-thread-pool n)
    (unless (and (integer? n) (> n 0))
      (error 'make-thread-pool "worker count must be positive" n))
    (let ([pool (make-%thread-pool (make-mutex) (make-condition) '() #t '())])
      ;; Start N worker threads
      (let start ([i 0])
        (when (< i n)
          (let ([t (fork-thread (lambda () (%pool-worker-loop pool)))])
            (%thread-pool-workers-set! pool
              (cons t (%thread-pool-workers pool))))
          (start (+ i 1))))
      pool))

  (define (thread-pool-submit! pool thunk)
    (with-mutex (%thread-pool-mutex pool)
      (unless (%thread-pool-running? pool)
        (error 'thread-pool-submit! "pool is stopped"))
      (%thread-pool-queue-set! pool
        (append (%thread-pool-queue pool) (list thunk)))
      (condition-signal (%thread-pool-condition pool))))

  (define (thread-pool-stop! pool)
    (with-mutex (%thread-pool-mutex pool)
      (%thread-pool-running?-set! pool #f)
      (condition-broadcast (%thread-pool-condition pool))))

  (define (thread-pool-worker-count pool)
    (length (%thread-pool-workers pool)))

  ;; ========== Futures ==========
  ;;
  ;; A future wraps a computation that runs in a background thread.
  ;; future-force blocks until the result is ready.

  (define-record-type %future
    (fields
      (immutable mutex)
      (immutable condition)
      (mutable   ready?)
      (mutable   result)     ;; the computed value (or an exception)
      (mutable   failed?))   ;; did the computation raise?
    (protocol
      (lambda (new)
        (lambda ()
          (new (make-mutex) (make-condition) #f #f #f))))
    (sealed #t))

  (define (future? x) (%future? x))

  (define (future-ready? f)
    (with-mutex (%future-mutex f)
      (%future-ready? f)))

  (define (future-force f)
    (with-mutex (%future-mutex f)
      (let loop ()
        (unless (%future-ready? f)
          (condition-wait (%future-condition f) (%future-mutex f))
          (loop)))
      (if (%future-failed? f)
        (raise (%future-result f))
        (%future-result f))))

  (define (make-future)
    (make-%future))

  (define (%future-deliver! f val failed?)
    (with-mutex (%future-mutex f)
      (%future-result-set! f val)
      (%future-failed?-set! f failed?)
      (%future-ready?-set! f #t)
      (condition-broadcast (%future-condition f))))

  (define (spawn-future thunk)
    (let ([f (make-%future)])
      (fork-thread
        (lambda ()
          (guard (exn [#t (%future-deliver! f exn #t)])
            (%future-deliver! f (thunk) #f))))
      f))

  (define (future-map proc f)
    (spawn-future (lambda () (proc (future-force f)))))

  ;; ========== Count-down Latch ==========
  ;;
  ;; Starts at count N; each latch-count-down! decrements by 1.
  ;; latch-await blocks until count reaches 0.

  (define-record-type %latch
    (fields
      (immutable mutex)
      (immutable condition)
      (mutable   count))
    (protocol
      (lambda (new)
        (lambda (n)
          (unless (and (integer? n) (>= n 0))
            (error 'make-latch "count must be non-negative" n))
          (new (make-mutex) (make-condition) n))))
    (sealed #t))

  (define (make-latch n) (make-%latch n))

  (define (latch-count-down! latch)
    (with-mutex (%latch-mutex latch)
      (when (> (%latch-count latch) 0)
        (%latch-count-set! latch (- (%latch-count latch) 1)))
      (when (= (%latch-count latch) 0)
        (condition-broadcast (%latch-condition latch)))))

  (define (latch-await latch)
    (with-mutex (%latch-mutex latch)
      (let loop ()
        (unless (= (%latch-count latch) 0)
          (condition-wait (%latch-condition latch) (%latch-mutex latch))
          (loop)))))

  ) ;; end library
