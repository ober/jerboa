#!chezscheme
;;; (std fiber) — Green Threads / Fibers
;;;
;;; M:N cooperative/preemptive fiber runtime built on Chez Scheme's
;;; engine API. Maps N fibers to M OS worker threads.
;;;
;;; Design:
;;;   - Each fiber runs inside a Chez engine for automatic preemption
;;;   - Cooperative yield: fiber sets a gate, calls (set-timer 1) to force
;;;     immediate engine preemption. Engine complete-proc opens gate for
;;;     yields, or parks fiber for sleep/channel. Near-zero yield cost.
;;;   - Per-fiber mutex coordinates handle-complete vs wake-fiber! to
;;;     prevent double-enqueue races in M:N scheduling.

(library (std fiber)
  (export
    make-fiber-runtime
    fiber-runtime?
    fiber-runtime-run!
    fiber-runtime-stop!
    fiber-runtime-fiber-count

    fiber-spawn
    fiber-spawn*
    fiber-yield
    fiber-sleep
    fiber-self
    fiber-id

    fiber?
    fiber-state
    fiber-name
    fiber-done?

    ;; Cancellation
    fiber-cancel!
    fiber-cancelled?
    fiber-check-cancelled!
    &fiber-cancelled
    make-fiber-cancelled
    fiber-cancelled-condition?
    cancelled-fiber-id

    ;; Fiber-local storage
    make-fiber-parameter
    fiber-parameterize

    ;; Join / error propagation
    fiber-join
    &fiber-timeout
    make-fiber-timeout
    fiber-timeout-condition?
    timeout-fiber-id

    ;; Link (Erlang-style crash propagation)
    fiber-link!
    fiber-unlink!
    &fiber-linked-crash
    make-fiber-linked-crash
    fiber-linked-crash?
    linked-crash-source
    linked-crash-condition

    ;; Channel select
    fiber-select

    ;; Timeouts
    fiber-timeout

    ;; Structured concurrency
    with-fiber-group
    fiber-group-spawn

    make-fiber-channel
    fiber-channel?
    fiber-channel-send
    fiber-channel-recv
    fiber-channel-try-send
    fiber-channel-try-recv
    fiber-channel-close
    fiber-channel-closed?

    current-fiber-runtime
    current-fiber

    with-fibers

    ;; Semaphore
    make-fiber-semaphore
    fiber-semaphore?
    fiber-semaphore-acquire!
    fiber-semaphore-release!
    fiber-semaphore-try-acquire!

    ;; Low-level primitives for I/O integration (used by std net io)
    wake-fiber!
    fiber-gate-set!
    spin-until-gate)

  (import (chezscheme) (std misc cpu) (std actor deque))

  ;; =========================================================================
  ;; Condition types
  ;; =========================================================================

  (define-condition-type &fiber-cancelled &serious
    make-fiber-cancelled fiber-cancelled-condition?
    (fiber-id cancelled-fiber-id))

  (define-condition-type &fiber-timeout &serious
    make-fiber-timeout fiber-timeout-condition?
    (fiber-id timeout-fiber-id))

  (define-condition-type &fiber-linked-crash &serious
    make-fiber-linked-crash fiber-linked-crash?
    (source-fiber-id linked-crash-source)
    (original-condition linked-crash-condition))

  ;; =========================================================================
  ;; Fiber record
  ;; =========================================================================

  (define-record-type fiber
    (fields
      (immutable id)
      (mutable state)           ;; 'ready | 'running | 'parked | 'done
      (mutable continuation)    ;; thunk or engine-resumer
      (mutable name)
      (mutable result)
      (mutable fiber-rt)        ;; back-pointer to fiber-runtime
      (mutable gate)            ;; #f or box: 'yield|'sleep|'channel -> 'done
      (immutable mx)            ;; per-fiber mutex for park/wake coordination
      (mutable cancelled)       ;; boolean — cooperative cancellation flag
      (mutable join-waiters)    ;; list of fibers waiting for this fiber to complete
      (mutable linked-fibers)   ;; list of fibers linked for crash propagation
      (mutable pending-crash))  ;; #f or &fiber-linked-crash condition to deliver
    (protocol
      (lambda (new)
        (lambda (id thunk name rt)
          (new id 'ready thunk name (void) rt #f (make-mutex)
               #f '() '() #f)))))

  (define (fiber-done? f)
    (eq? (fiber-state f) 'done))

  ;; =========================================================================
  ;; Fiber-local storage
  ;; =========================================================================

  ;; Global registry of all live fiber-parameters for cleanup on fiber death.
  (define *fiber-parameters* '())
  (define *fiber-parameters-mx* (make-mutex))

  (define (register-fiber-parameter! fp)
    (mutex-acquire *fiber-parameters-mx*)
    (set! *fiber-parameters* (cons fp *fiber-parameters*))
    (mutex-release *fiber-parameters-mx*))

  (define (cleanup-fiber-parameters! fid)
    (mutex-acquire *fiber-parameters-mx*)
    (for-each (lambda (fp) (fp fid #t)) *fiber-parameters*)
    (mutex-release *fiber-parameters-mx*))

  (define (make-fiber-parameter default)
    (let ([store (make-eq-hashtable)]
          [mx (make-mutex)])
      (define fp
        (case-lambda
          [()    ;; read
           (let ([f (current-fiber)])
             (if f
               (begin (mutex-acquire mx)
                      (let ([v (hashtable-ref store (fiber-id f) default)])
                        (mutex-release mx) v))
               default))]
          [(val) ;; write
           (let ([f (current-fiber)])
             (unless f (error 'fiber-parameter "not in a fiber"))
             (mutex-acquire mx)
             (hashtable-set! store (fiber-id f) val)
             (mutex-release mx))]
          [(fid cleanup?) ;; internal: cleanup by fiber id
           (when cleanup?
             (mutex-acquire mx)
             (hashtable-delete! store fid)
             (mutex-release mx))]))
      (register-fiber-parameter! fp)
      fp))

  (define-syntax fiber-parameterize
    (syntax-rules ()
      [(_ () body ...)
       (begin body ...)]
      [(_ ([fp val] rest ...) body ...)
       (let ([old (fp)])
         (dynamic-wind
           (lambda () (fp val))
           (lambda () (fiber-parameterize (rest ...) body ...))
           (lambda () (fp old))))]))

  ;; =========================================================================
  ;; Work-stealing run queues (per-worker deques)
  ;; =========================================================================
  ;;
  ;; Each worker owns a work-stealing deque from (std actor deque).
  ;; Owner pushes/pops LIFO (cache-hot). Idle workers steal FIFO.
  ;; A global condition variable wakes sleeping workers when work arrives.

  ;; Thread-local: which worker index this thread is (0..N-1), or #f
  (define current-worker-id (make-thread-parameter #f))

  ;; Enqueue a fiber to the runtime's work-stealing deques.
  ;; Fast path: from a worker thread → push to own deque (no contention).
  ;; Slow path: from outside or wake-fiber! → push to random worker's deque.
  (define (rt-enqueue! rt f)
    (let ([workers (fiber-runtime-workers rt)]
          [wid (current-worker-id)])
      (if (and wid (fx< wid (vector-length workers)))
        ;; Fast path: push to own deque
        (deque-push-bottom! (vector-ref workers wid) f)
        ;; Slow path (poller/external): random worker's deque
        (let ([n (vector-length workers)])
          (deque-push-bottom! (vector-ref workers (random n)) f)))))

  ;; =========================================================================
  ;; Timer queue
  ;; =========================================================================

  (define-record-type timer-entry
    (fields
      (immutable deadline)
      (immutable fiber)))

  (define-record-type timer-queue
    (fields
      (mutable entries)
      (immutable mutex))
    (protocol
      (lambda (new)
        (lambda ()
          (new '() (make-mutex))))))

  (define (tq-add! tq deadline fiber)
    (mutex-acquire (timer-queue-mutex tq))
    (let ([entry (make-timer-entry deadline fiber)])
      (timer-queue-entries-set! tq
        (let insert ([es (timer-queue-entries tq)])
          (cond
            [(null? es) (list entry)]
            [(time<? deadline (timer-entry-deadline (car es)))
             (cons entry es)]
            [else (cons (car es) (insert (cdr es)))]))))
    (mutex-release (timer-queue-mutex tq)))

  (define (tq-collect-expired! tq now)
    (mutex-acquire (timer-queue-mutex tq))
    (let loop ([es (timer-queue-entries tq)] [ready '()])
      (cond
        [(null? es)
         (timer-queue-entries-set! tq '())
         (mutex-release (timer-queue-mutex tq))
         ready]
        [(time<=? (timer-entry-deadline (car es)) now)
         (loop (cdr es) (cons (timer-entry-fiber (car es)) ready))]
        [else
         (timer-queue-entries-set! tq es)
         (mutex-release (timer-queue-mutex tq))
         ready])))

  ;; =========================================================================
  ;; Fiber runtime
  ;; =========================================================================

  (define-record-type fiber-runtime
    (fields
      (immutable workers)        ;; vector of work-deque (one per worker)
      (immutable timer-queue)
      (mutable worker-threads)
      (immutable nworkers)
      (mutable running?)
      (mutable next-id)
      (immutable id-mutex)
      (mutable total-fibers)
      (mutable done-fibers)
      (immutable done-mutex)
      (immutable all-done)
      (immutable fuel))
    (protocol
      (lambda (new)
        (define (make-worker-deques n)
          (let ([v (make-vector n)])
            (do ([i 0 (fx+ i 1)]) ((fx= i n) v)
              (vector-set! v i (make-work-deque)))))
        (case-lambda
          [()  (let ([n (max 1 (- (cpu-count) 1))])
                 (new (make-worker-deques n) (make-timer-queue)
                      '() n
                      #f 0 (make-mutex) 0 0
                      (make-mutex) (make-condition)
                      10000))]
          [(nworkers)
               (let ([n (max 1 nworkers)])
                 (new (make-worker-deques n) (make-timer-queue)
                      '() n
                      #f 0 (make-mutex) 0 0
                      (make-mutex) (make-condition)
                      10000))]
          [(nworkers fuel)
               (let ([n (max 1 nworkers)])
                 (new (make-worker-deques n) (make-timer-queue)
                      '() n
                      #f 0 (make-mutex) 0 0
                      (make-mutex) (make-condition)
                      (max 100 fuel)))]))))

  (define (fiber-runtime-fiber-count rt)
    (- (fiber-runtime-total-fibers rt)
       (fiber-runtime-done-fibers rt)))

  ;; =========================================================================
  ;; Parameters
  ;; =========================================================================

  (define current-fiber-runtime (make-thread-parameter #f))
  (define current-fiber (make-thread-parameter #f))

  ;; =========================================================================
  ;; Fiber spawn
  ;; =========================================================================

  (define (alloc-fiber-id! rt)
    (mutex-acquire (fiber-runtime-id-mutex rt))
    (let ([id (fiber-runtime-next-id rt)])
      (fiber-runtime-next-id-set! rt (fx+ id 1))
      (mutex-release (fiber-runtime-id-mutex rt))
      id))

  (define fiber-spawn
    (case-lambda
      [(rt thunk)
       (fiber-spawn rt thunk #f)]
      [(rt thunk name)
       (let* ([id (alloc-fiber-id! rt)]
              [f (make-fiber id thunk name rt)])
         (mutex-acquire (fiber-runtime-done-mutex rt))
         (fiber-runtime-total-fibers-set! rt
           (fx+ (fiber-runtime-total-fibers rt) 1))
         (mutex-release (fiber-runtime-done-mutex rt))
         (rt-enqueue! rt f)
         f)]))

  (define (fiber-spawn* thunk . name-opt)
    (let ([rt (current-fiber-runtime)])
      (unless rt (error 'fiber-spawn* "no active fiber runtime"))
      (fiber-spawn rt thunk (if (pair? name-opt) (car name-opt) #f))))

  ;; =========================================================================
  ;; Fiber self / yield / sleep
  ;; =========================================================================
  ;;
  ;; When a fiber wants to yield/block:
  ;; 1. Set a gate box on the fiber ('yield, 'sleep, or 'channel)
  ;; 2. Call (set-timer 1) to force immediate engine preemption
  ;; 3. Enter a minimal spin loop (runs ~1 iteration before preemption)
  ;; 4. Engine's complete-proc handles the gate:
  ;;    - 'yield: open gate, re-enqueue
  ;;    - 'sleep/'channel: park fiber (don't re-enqueue)
  ;; 5. When fiber is eventually resumed, spin loop exits (gate = 'done)

  (define (fiber-self)
    (or (current-fiber)
        (error 'fiber-self "not running inside a fiber")))

  (define (spin-until-gate gate)
    (let loop () (unless (eq? (unbox gate) 'done) (loop))))

  ;; =========================================================================
  ;; Cancellation
  ;; =========================================================================

  (define (fiber-cancelled? f)
    (fiber-cancelled f))

  (define fiber-cancel!
    (case-lambda
      [(f)
       (let ([fmx (fiber-mx f)])
         (mutex-acquire fmx)
         (unless (fiber-cancelled f)
           (fiber-cancelled-set! f #t))
         (cond
           [(eq? (fiber-state f) 'parked)
            (let ([gate (fiber-gate f)])
              (when (and gate (box? gate))
                (set-box! gate 'done))
              (fiber-state-set! f 'ready)
              (mutex-release fmx)
              (rt-enqueue! (fiber-fiber-rt f) f))]
           [else
            ;; Running or ready — flag is set, will be checked at next
            ;; cancellation point (yield/sleep/channel)
            (mutex-release fmx)]))]
      [(f timeout-ms)
       ;; Cooperative cancel, then force-abandon after timeout
       (fiber-cancel! f)
       (fork-thread
         (lambda ()
           (sleep (make-time 'time-duration
                             (* (fxmod timeout-ms 1000) 1000000)
                             (fxquotient timeout-ms 1000)))
           (unless (fiber-done? f)
             ;; Force: mark done without running further
             (let ([fmx (fiber-mx f)]
                   [rt (fiber-fiber-rt f)]
                   [forced? #f])
               (mutex-acquire fmx)
               (unless (eq? (fiber-state f) 'done)
                 (fiber-state-set! f 'done)
                 (fiber-result-set! f
                   (make-fiber-cancelled (fiber-id f)))
                 (fiber-continuation-set! f #f)
                 (fiber-gate-set! f #f)
                 (set! forced? #t))
               (mutex-release fmx)
               (when forced?
                 (fiber-done-hooks! f rt))))))]))

  (define (fiber-check-cancelled!)
    (let ([f (current-fiber)])
      (when (and f (fiber-cancelled f))
        (raise (make-fiber-cancelled (fiber-id f))))))

  ;; Check cancellation + linked crash at cancellation points
  (define (check-cancellation-point! f)
    (when (fiber-cancelled f)
      (raise (make-fiber-cancelled (fiber-id f))))
    (let ([crash (fiber-pending-crash f)])
      (when crash
        (fiber-pending-crash-set! f #f)
        (raise crash))))

  ;; =========================================================================
  ;; Yield / Sleep
  ;; =========================================================================

  (define (fiber-yield)
    (let ([f (current-fiber)])
      (unless f (error 'fiber-yield "not running inside a fiber"))
      (check-cancellation-point! f)
      (let ([gate (box 'yield)])
        (fiber-gate-set! f gate)
        ;; Force immediate preemption
        (set-timer 1)
        (spin-until-gate gate)
        (fiber-gate-set! f #f)
        (void))))

  (define (fiber-sleep duration-ms)
    (let ([f (current-fiber)]
          [rt (current-fiber-runtime)])
      (unless (and f rt)
        (error 'fiber-sleep "not running inside a fiber"))
      (check-cancellation-point! f)
      (let ([gate (box 'sleep)])
        (fiber-gate-set! f gate)
        ;; Register timer
        (let* ([now (current-time 'time-utc)]
               [deadline (add-duration now
                           (make-time 'time-duration
                                      (* (fxmod duration-ms 1000) 1000000)
                                      (fxquotient duration-ms 1000)))])
          (tq-add! (fiber-runtime-timer-queue rt) deadline f))
        ;; Force immediate preemption
        (set-timer 1)
        (spin-until-gate gate)
        (fiber-gate-set! f #f)
        (check-cancellation-point! f)
        (void))))

  ;; =========================================================================
  ;; Engine resume wrapper
  ;; =========================================================================

  (define (make-engine-resumer eng)
    (vector 'engine-resume eng))

  (define (engine-resumer? x)
    (and (vector? x) (fx= (vector-length x) 2)
         (eq? (vector-ref x 0) 'engine-resume)))

  (define (engine-resumer-engine x)
    (vector-ref x 1))

  ;; =========================================================================
  ;; Core: run-fiber!
  ;; =========================================================================

  (define (handle-expire rt f remaining result)
    (fiber-state-set! f 'done)
    (fiber-result-set! f result)
    (fiber-continuation-set! f #f)
    (fiber-gate-set! f #f)
    (fiber-done-hooks! f rt))

  (define (handle-complete rt f new-engine)
    ;; Engine fuel exhausted — fiber was preempted.
    ;; Use per-fiber mutex to coordinate with wake-fiber!.
    (let ([gate (fiber-gate f)]
          [fmx (fiber-mx f)])
      (fiber-continuation-set! f (make-engine-resumer new-engine))
      (cond
        ;; No gate — normal preemption, re-enqueue to own deque
        [(not gate)
         (fiber-state-set! f 'ready)
         (rt-enqueue! rt f)]
        ;; Cooperative yield — open gate, re-enqueue
        [(eq? (unbox gate) 'yield)
         (set-box! gate 'done)
         (fiber-state-set! f 'ready)
         (rt-enqueue! rt f)]
        ;; Blocked (sleep/channel) — check if already woken
        [else
         (mutex-acquire fmx)
         (cond
           ;; Already woken by sender/timer while we were in the engine
           [(eq? (unbox gate) 'done)
            (fiber-state-set! f 'ready)
            (mutex-release fmx)
            (rt-enqueue! rt f)]
           ;; Not yet woken — park the fiber
           [else
            (fiber-state-set! f 'parked)
            (mutex-release fmx)])])))

  ;; Wake a parked fiber (called by channel sender or timer).
  ;; Uses per-fiber mutex to avoid double-enqueue with handle-complete.
  (define (wake-fiber! f)
    (let ([fmx (fiber-mx f)]
          [gate (fiber-gate f)])
      (mutex-acquire fmx)
      (when (and gate (box? gate))
        (set-box! gate 'done))
      (cond
        [(eq? (fiber-state f) 'parked)
         ;; Fiber is parked — re-enqueue
         (fiber-state-set! f 'ready)
         (mutex-release fmx)
         (rt-enqueue! (fiber-fiber-rt f) f)]
        [else
         ;; Fiber still in engine — gate is set, will exit spin on resume
         (mutex-release fmx)])))

  ;; Post-completion hooks: wake join-waiters, propagate linked crashes,
  ;; clean up fiber-parameters. Called after fiber state is 'done and
  ;; result is set. Must be called OUTSIDE the fiber's mx.
  (define (fiber-done-hooks! f rt)
    ;; Wake join-waiters
    (let ([waiters (fiber-join-waiters f)])
      (fiber-join-waiters-set! f '())
      (for-each (lambda (w)
                  (fiber-result-set! w (fiber-result f))
                  (wake-fiber! w))
                waiters))
    ;; Crash propagation to linked fibers
    (let ([result (fiber-result f)])
      (when (condition? result)
        (let ([crash-cond (make-fiber-linked-crash (fiber-id f) result)])
          (for-each (lambda (linked)
                      (unless (fiber-done? linked)
                        (fiber-pending-crash-set! linked crash-cond)
                        ;; If parked, wake it so it can check the crash
                        (let ([fmx (fiber-mx linked)]
                              [need-enqueue? #f])
                          (mutex-acquire fmx)
                          (when (eq? (fiber-state linked) 'parked)
                            (let ([gate (fiber-gate linked)])
                              (when (and gate (box? gate))
                                (set-box! gate 'done)))
                            (fiber-state-set! linked 'ready)
                            (set! need-enqueue? #t))
                          (mutex-release fmx)
                          (when need-enqueue?
                            (rt-enqueue! (fiber-fiber-rt linked)
                                         linked)))))
                    (fiber-linked-fibers f)))))
    ;; Fiber-parameter cleanup
    (cleanup-fiber-parameters! (fiber-id f))
    ;; Decrement runtime counter
    (mutex-acquire (fiber-runtime-done-mutex rt))
    (fiber-runtime-done-fibers-set! rt
      (fx+ (fiber-runtime-done-fibers rt) 1))
    (when (fx= (fiber-runtime-done-fibers rt)
               (fiber-runtime-total-fibers rt))
      (condition-broadcast (fiber-runtime-all-done rt)))
    (mutex-release (fiber-runtime-done-mutex rt)))

  (define (run-fiber! rt f fuel)
    (let ([cont (fiber-continuation f)])
      (current-fiber-runtime rt)
      (current-fiber f)
      (fiber-state-set! f 'running)

      (if (engine-resumer? cont)
          ((engine-resumer-engine cont) fuel
            (lambda (remaining result) (handle-expire rt f remaining result))
            (lambda (new-engine) (handle-complete rt f new-engine)))
          (let ([eng (make-engine
                       (lambda ()
                         (current-fiber-runtime rt)
                         (current-fiber f)
                         (cont)))])
            (eng fuel
              (lambda (remaining result) (handle-expire rt f remaining result))
              (lambda (new-engine) (handle-complete rt f new-engine)))))))

  ;; =========================================================================
  ;; Worker loop
  ;; =========================================================================

  (define (check-timers! rt)
    (let ([expired (tq-collect-expired!
                     (fiber-runtime-timer-queue rt)
                     (current-time 'time-utc))])
      (for-each wake-fiber! expired)))

  (define (worker-loop rt wid)
    (current-worker-id wid)
    (let ([workers (fiber-runtime-workers rt)]
          [n (fiber-runtime-nworkers rt)]
          [fuel (fiber-runtime-fuel rt)]
          [my-deque (vector-ref (fiber-runtime-workers rt) wid)])

      ;; Try to find work: own deque first, then steal from others.
      ;; Returns a fiber or #f.
      (define (find-work)
        ;; Use steal-top (FIFO) for own deque to maintain fair scheduling.
        ;; LIFO (pop-bottom) would starve older fibers under load.
        (let-values ([(f ok) (deque-steal-top! my-deque)])
          (if ok f
            (let try-steal ([attempts 0])
              (cond
                [(fx>= attempts n) #f]
                [else
                 (let* ([victim-idx (fxmod (fx+ wid attempts 1) n)]
                        [victim-deque (vector-ref workers victim-idx)])
                   (let-values ([(stolen ok) (deque-steal-top! victim-deque)])
                     (if ok stolen (try-steal (fx+ attempts 1)))))])))))

      (let loop ()
        (when (fiber-runtime-running? rt)
          (check-timers! rt)
          (let ([f (find-work)])
            (cond
              [f (run-one! rt f fuel) (loop)]
              [else
               ;; No work found — brief sleep then retry.
               ;; 1ms is short enough for responsiveness, long enough
               ;; to avoid busy-spinning.
               (sleep (make-time 'time-duration 1000000 0))
               (loop)]))))))

  (define (run-one! rt f fuel)
    (guard (exn [#t
      (fiber-state-set! f 'done)
      (fiber-result-set! f exn)
      (fiber-continuation-set! f #f)
      (fiber-gate-set! f #f)
      (fiber-done-hooks! f rt)])
      (run-fiber! rt f fuel)))

  ;; =========================================================================
  ;; Runtime start/stop
  ;; =========================================================================

  (define (fiber-runtime-run! rt)
    (fiber-runtime-running?-set! rt #t)
    (let ([threads
           (let build ([i 0] [acc '()])
             (if (fx= i (fiber-runtime-nworkers rt)) acc
               (let ([wid i])
                 (build (fx+ i 1)
                   (cons (fork-thread (lambda () (worker-loop rt wid)))
                         acc)))))])
      (fiber-runtime-worker-threads-set! rt threads)
      (mutex-acquire (fiber-runtime-done-mutex rt))
      (let wait ()
        (unless (fx= (fiber-runtime-done-fibers rt)
                     (fiber-runtime-total-fibers rt))
          (condition-wait (fiber-runtime-all-done rt)
                          (fiber-runtime-done-mutex rt))
          (wait)))
      (mutex-release (fiber-runtime-done-mutex rt))
      (fiber-runtime-stop! rt)))

  (define (fiber-runtime-stop! rt)
    (fiber-runtime-running?-set! rt #f)
    ;; Workers will exit their loop on next iteration when running? = #f.
    ;; Brief sleep to let them drain.
    (sleep (make-time 'time-duration 50000000 0)))

  ;; =========================================================================
  ;; Convenience macro
  ;; =========================================================================

  (define-syntax with-fibers
    (syntax-rules ()
      [(_ body ...)
       (let ([rt (make-fiber-runtime)])
         (parameterize ([current-fiber-runtime rt])
           body ...
           (fiber-runtime-run! rt)))]))

  ;; =========================================================================
  ;; Fiber-aware channels
  ;; =========================================================================

  (define-record-type fiber-channel
    (fields
      (mutable buf)
      (mutable head)
      (mutable tail)
      (mutable count)
      (immutable capacity)
      (immutable mutex)
      (mutable recv-waiters)
      (mutable send-waiters)
      (mutable closed?))
    (protocol
      (lambda (new)
        (case-lambda
          [()    (new (make-vector 16) 0 0 0 #f (make-mutex) '() '() #f)]
          [(cap) (new (make-vector (max 1 cap)) 0 0 0 cap
                      (make-mutex) '() '() #f)]))))

  (define (fc-grow! ch)
    (let* ([old-buf (fiber-channel-buf ch)]
           [old-cap (vector-length old-buf)]
           [new-cap (fx* old-cap 2)]
           [new-buf (make-vector new-cap)]
           [head (fiber-channel-head ch)]
           [count (fiber-channel-count ch)])
      (do ([i 0 (fx+ i 1)]) ((fx= i count))
        (vector-set! new-buf i
          (vector-ref old-buf (fxmod (fx+ head i) old-cap))))
      (fiber-channel-buf-set! ch new-buf)
      (fiber-channel-head-set! ch 0)
      (fiber-channel-tail-set! ch count)))

  (define (fiber-channel-send ch val)
    (let ([f (current-fiber)])
      (when f (check-cancellation-point! f)))
    (let ([mx (fiber-channel-mutex ch)])
      (mutex-acquire mx)
      (when (fiber-channel-closed? ch)
        (mutex-release mx)
        (error 'fiber-channel-send "channel is closed"))
      (cond
        [(pair? (fiber-channel-recv-waiters ch))
         (let ([recv-f (car (fiber-channel-recv-waiters ch))])
           (fiber-channel-recv-waiters-set! ch
             (cdr (fiber-channel-recv-waiters ch)))
           (fiber-result-set! recv-f val)
           (mutex-release mx)
           (wake-fiber! recv-f))]
        [(or (not (fiber-channel-capacity ch))
             (fx< (fiber-channel-count ch) (fiber-channel-capacity ch)))
         (when (and (not (fiber-channel-capacity ch))
                    (fx= (fiber-channel-count ch) (vector-length (fiber-channel-buf ch))))
           (fc-grow! ch))
         (let ([buf (fiber-channel-buf ch)]
               [tail (fiber-channel-tail ch)])
           (vector-set! buf tail val)
           (fiber-channel-tail-set! ch (fxmod (fx+ tail 1) (vector-length buf)))
           (fiber-channel-count-set! ch (fx+ (fiber-channel-count ch) 1)))
         (mutex-release mx)]
        [else
         (let ([f (current-fiber)]
               [gate (box 'channel)])
           (fiber-channel-send-waiters-set! ch
             (append (fiber-channel-send-waiters ch)
                     (list (cons f val))))
           (fiber-gate-set! f gate)
           (mutex-release mx)
           ;; Force preemption to park
           (set-timer 1)
           (spin-until-gate gate)
           (fiber-gate-set! f #f))])))

  (define (fiber-channel-recv ch)
    (let ([f (current-fiber)])
      (when f (check-cancellation-point! f)))
    (let ([mx (fiber-channel-mutex ch)])
      (mutex-acquire mx)
      (cond
        [(fx> (fiber-channel-count ch) 0)
         (let* ([buf (fiber-channel-buf ch)]
                [head (fiber-channel-head ch)]
                [val (vector-ref buf head)])
           (vector-set! buf head #f)
           (fiber-channel-head-set! ch (fxmod (fx+ head 1) (vector-length buf)))
           (fiber-channel-count-set! ch (fx- (fiber-channel-count ch) 1))
           (if (pair? (fiber-channel-send-waiters ch))
             (let* ([entry (car (fiber-channel-send-waiters ch))]
                    [sender-f (car entry)]
                    [sender-val (cdr entry)])
               (fiber-channel-send-waiters-set! ch
                 (cdr (fiber-channel-send-waiters ch)))
               (let ([buf2 (fiber-channel-buf ch)]
                     [tail2 (fiber-channel-tail ch)])
                 (vector-set! buf2 tail2 sender-val)
                 (fiber-channel-tail-set! ch (fxmod (fx+ tail2 1) (vector-length buf2)))
                 (fiber-channel-count-set! ch (fx+ (fiber-channel-count ch) 1)))
               (mutex-release mx)
               (wake-fiber! sender-f)
               val)
             (begin (mutex-release mx) val)))]
        [(pair? (fiber-channel-send-waiters ch))
         (let* ([entry (car (fiber-channel-send-waiters ch))]
                [sender-f (car entry)]
                [val (cdr entry)])
           (fiber-channel-send-waiters-set! ch
             (cdr (fiber-channel-send-waiters ch)))
           (mutex-release mx)
           (wake-fiber! sender-f)
           val)]
        [(fiber-channel-closed? ch)
         (mutex-release mx)
         (error 'fiber-channel-recv "channel is closed and empty")]
        [else
         (let ([f (current-fiber)]
               [gate (box 'channel)])
           (fiber-channel-recv-waiters-set! ch
             (append (fiber-channel-recv-waiters ch)
                     (list f)))
           (fiber-gate-set! f gate)
           (fiber-result-set! f (void))
           (mutex-release mx)
           ;; Force preemption to park
           (set-timer 1)
           (spin-until-gate gate)
           (fiber-gate-set! f #f)
           (fiber-result f))])))

  (define (fiber-channel-try-send ch val)
    (let ([mx (fiber-channel-mutex ch)])
      (mutex-acquire mx)
      (cond
        [(fiber-channel-closed? ch)
         (mutex-release mx) #f]
        [(pair? (fiber-channel-recv-waiters ch))
         (let ([recv-f (car (fiber-channel-recv-waiters ch))])
           (fiber-channel-recv-waiters-set! ch
             (cdr (fiber-channel-recv-waiters ch)))
           (fiber-result-set! recv-f val)
           (mutex-release mx)
           (wake-fiber! recv-f))
         #t]
        [(or (not (fiber-channel-capacity ch))
             (fx< (fiber-channel-count ch) (fiber-channel-capacity ch)))
         (when (and (not (fiber-channel-capacity ch))
                    (fx= (fiber-channel-count ch) (vector-length (fiber-channel-buf ch))))
           (fc-grow! ch))
         (let ([buf (fiber-channel-buf ch)]
               [tail (fiber-channel-tail ch)])
           (vector-set! buf tail val)
           (fiber-channel-tail-set! ch (fxmod (fx+ tail 1) (vector-length buf)))
           (fiber-channel-count-set! ch (fx+ (fiber-channel-count ch) 1)))
         (mutex-release mx) #t]
        [else (mutex-release mx) #f])))

  (define (fiber-channel-try-recv ch)
    (let ([mx (fiber-channel-mutex ch)])
      (mutex-acquire mx)
      (if (fx> (fiber-channel-count ch) 0)
        (let* ([buf (fiber-channel-buf ch)]
               [head (fiber-channel-head ch)]
               [val (vector-ref buf head)])
          (vector-set! buf head #f)
          (fiber-channel-head-set! ch (fxmod (fx+ head 1) (vector-length buf)))
          (fiber-channel-count-set! ch (fx- (fiber-channel-count ch) 1))
          (mutex-release mx)
          (values val #t))
        (begin
          (mutex-release mx)
          (values #f #f)))))

  (define (fiber-channel-close ch)
    (let ([mx (fiber-channel-mutex ch)])
      (mutex-acquire mx)
      (fiber-channel-closed?-set! ch #t)
      (let ([waiters (fiber-channel-recv-waiters ch)]
            [senders (fiber-channel-send-waiters ch)])
        (fiber-channel-recv-waiters-set! ch '())
        (fiber-channel-send-waiters-set! ch '())
        (mutex-release mx)
        (for-each wake-fiber! waiters)
        (for-each (lambda (entry) (wake-fiber! (car entry))) senders))))

  ;; =========================================================================
  ;; Fiber join — block until fiber completes, return result or re-raise
  ;; =========================================================================

  (define fiber-join
    (case-lambda
      [(f) (fiber-join f #f)]
      [(f timeout-ms)
       (let ([caller (current-fiber)])
         (unless caller (error 'fiber-join "not running inside a fiber"))
         (cond
           [(fiber-done? f)
            (let ([r (fiber-result f)])
              (if (condition? r) (raise r) r))]
           [else
            (let ([fmx (fiber-mx f)]
                  [gate (box 'channel)])
              (when timeout-ms
                (let* ([rt (current-fiber-runtime)]
                       [now (current-time 'time-utc)]
                       [deadline (add-duration now
                                   (make-time 'time-duration
                                              (* (fxmod timeout-ms 1000) 1000000)
                                              (fxquotient timeout-ms 1000)))])
                  (tq-add! (fiber-runtime-timer-queue rt) deadline caller)))
              (mutex-acquire fmx)
              (cond
                [(eq? (fiber-state f) 'done)
                 (mutex-release fmx)
                 (let ([r (fiber-result f)])
                   (if (condition? r) (raise r) r))]
                [else
                 (fiber-join-waiters-set! f
                   (cons caller (fiber-join-waiters f)))
                 (fiber-gate-set! caller gate)
                 (fiber-result-set! caller (void))
                 (mutex-release fmx)
                 (set-timer 1)
                 (spin-until-gate gate)
                 (fiber-gate-set! caller #f)
                 (let ([r (fiber-result caller)])
                   (cond
                     [(and timeout-ms (eq? r (void)) (not (fiber-done? f)))
                      (mutex-acquire fmx)
                      (fiber-join-waiters-set! f
                        (remq caller (fiber-join-waiters f)))
                      (mutex-release fmx)
                      (raise (make-fiber-timeout (fiber-id f)))]
                     [(condition? r) (raise r)]
                     [else r]))]))]))]))

  ;; =========================================================================
  ;; Fiber link — Erlang-style crash propagation
  ;; =========================================================================

  (define (fiber-link! f)
    (let ([caller (current-fiber)])
      (unless caller (error 'fiber-link! "not running inside a fiber"))
      (let ([fmx (fiber-mx f)])
        (mutex-acquire fmx)
        (cond
          ;; Already done with error — deliver crash immediately
          [(and (fiber-done? f) (condition? (fiber-result f)))
           (mutex-release fmx)
           (raise (make-fiber-linked-crash (fiber-id f) (fiber-result f)))]
          [else
           (fiber-linked-fibers-set! f
             (cons caller (fiber-linked-fibers f)))
           (mutex-release fmx)]))))

  (define (fiber-unlink! f)
    (let ([caller (current-fiber)])
      (when caller
        (let ([fmx (fiber-mx f)])
          (mutex-acquire fmx)
          (fiber-linked-fibers-set! f
            (remq caller (fiber-linked-fibers f)))
          (mutex-release fmx)))))

  ;; =========================================================================
  ;; Fiber-channel select — auxiliary syntax and macros
  ;; =========================================================================

  ;; =========================================================================
  ;; Fiber-channel select — wait on multiple channels
  ;; =========================================================================
  ;;
  ;; (fiber-select clause ...)
  ;; Clause forms:
  ;;   [ch val => body ...]            — recv from ch, bind val
  ;;   [ch :send expr => body ...]     — send expr to ch
  ;;   [:timeout ms => body ...]       — timeout in milliseconds
  ;;   [:default => body ...]          — non-blocking fallback

  (define-syntax fiber-select
    (lambda (x)
      (define (keyword? id sym)
        (and (identifier? id)
             (eq? (syntax->datum id) sym)))
      (define (parse-clauses clauses)
        ;; Returns (recvs sends timeout default) as syntax objects
        (let loop ([cls clauses] [recvs '()] [sends '()] [tout #f] [dflt #f])
          (if (null? cls)
            (values (reverse recvs) (reverse sends) tout dflt)
            (syntax-case (car cls) (=>)
              [(kw => body ...)
               (keyword? #'kw ':default)
               (loop (cdr cls) recvs sends tout #'(body ...))]
              [(kw ms => body ...)
               (keyword? #'kw ':timeout)
               (loop (cdr cls) recvs sends #'(ms body ...) dflt)]
              [(ch kw expr => body ...)
               (keyword? #'kw ':send)
               (loop (cdr cls) recvs (cons #'(ch expr body ...) sends) tout dflt)]
              [(ch val => body ...)
               (loop (cdr cls) (cons #'(ch val body ...) recvs) sends tout dflt)]))))
      (syntax-case x ()
        [(_ clause ...)
         (let-values ([(recvs sends tout dflt) (parse-clauses #'(clause ...))])
           (with-syntax
             ([recv-specs
               (if (null? recvs) #''()
                 (let loop ([rs recvs])
                   (if (null? rs) #''()
                     (syntax-case (car rs) ()
                       [(ch val body ...)
                        #`(cons (cons ch (lambda (val) body ...))
                                #,(loop (cdr rs)))]))))]
              [send-specs
               (if (null? sends) #''()
                 (let loop ([ss sends])
                   (if (null? ss) #''()
                     (syntax-case (car ss) ()
                       [(ch expr body ...)
                        #`(cons (cons* ch expr (lambda () body ...))
                                #,(loop (cdr ss)))]))))]
              [timeout-spec
               (if tout
                 (syntax-case tout ()
                   [(ms body ...)
                    #'(cons ms (lambda () body ...))])
                 #'#f)]
              [default-spec
               (if dflt
                 (syntax-case dflt ()
                   [(body ...)
                    #'(lambda () body ...)])
                 #'#f)])
             #'(fiber-select-impl recv-specs send-specs timeout-spec default-spec)))])))


  ;; Runtime implementation of fiber-select
  (define (fiber-select-impl recv-specs send-specs timeout-spec default-spec)
    (define (try-recv specs)
      (cond
        [(null? specs) #f]
        [else
         (let* ([spec (car specs)]
                [ch (car spec)]
                [handler (cdr spec)])
           (let-values ([(val ok) (fiber-channel-try-recv ch)])
             (if ok
               (cons 'ok (handler val))
               (try-recv (cdr specs)))))]))
    (define (try-send specs)
      (cond
        [(null? specs) #f]
        [else
         (let* ([spec (car specs)]
                [ch (car spec)]
                [val (cadr spec)]
                [handler (cddr spec)])
           (if (fiber-channel-try-send ch val)
             (cons 'ok (handler))
             (try-send (cdr specs))))]))
    (define (block-on-channels f)
      (let ([gate (box 'channel)])
        (fiber-gate-set! f gate)
        (fiber-result-set! f (void))
        ;; Register timeout if present
        (when timeout-spec
          (let* ([rt (current-fiber-runtime)]
                 [ms (car timeout-spec)]
                 [now (current-time 'time-utc)]
                 [deadline (add-duration now
                             (make-time 'time-duration
                                        (* (fxmod ms 1000) 1000000)
                                        (fxquotient ms 1000)))])
            (tq-add! (fiber-runtime-timer-queue rt) deadline f)))
        ;; Register on recv channels
        (for-each (lambda (spec)
                    (let ([ch (car spec)]
                          [mx (fiber-channel-mutex (car spec))])
                      (mutex-acquire mx)
                      (fiber-channel-recv-waiters-set! ch
                        (append (fiber-channel-recv-waiters ch) (list f)))
                      (mutex-release mx)))
                  recv-specs)
        ;; Park the fiber
        (set-timer 1)
        (spin-until-gate gate)
        (fiber-gate-set! f #f)
        ;; Remove from all recv waiter lists
        (for-each (lambda (spec)
                    (let ([ch (car spec)]
                          [mx (fiber-channel-mutex (car spec))])
                      (mutex-acquire mx)
                      (fiber-channel-recv-waiters-set! ch
                        (remq f (fiber-channel-recv-waiters ch)))
                      (mutex-release mx)))
                  recv-specs)
        (check-cancellation-point! f)
        ;; Determine what woke us
        (let ([result (fiber-result f)])
          (cond
            [(not (eq? result (void)))
             (if (pair? recv-specs)
               ((cdr (car recv-specs)) result)
               result)]
            [timeout-spec
             ((cdr timeout-spec))]
            [else (select-loop)]))))
    (define (select-loop)
      (let ([hit (try-recv recv-specs)])
        (cond
          [hit (cdr hit)]
          [else
           (let ([hit2 (try-send send-specs)])
             (cond
               [hit2 (cdr hit2)]
               [default-spec (default-spec)]
               [else
                (let ([f (current-fiber)])
                  (unless f (error 'fiber-select "blocking select requires fiber context"))
                  (block-on-channels f))]))])))
    ;; Entry point
    (let ([f (current-fiber)])
      (when f (check-cancellation-point! f)))
    (select-loop))

  ;; =========================================================================
  ;; Fiber timeout — channel that fires after N milliseconds
  ;; =========================================================================

  (define (fiber-timeout ms)
    (let ([ch (make-fiber-channel 1)])
      (fiber-spawn* (lambda ()
        (fiber-sleep ms)
        (fiber-channel-try-send ch (void))))
      ch))

  ;; =========================================================================
  ;; Structured concurrency — with-fiber-group
  ;; =========================================================================

  (define-record-type fiber-group
    (fields
      (mutable fibers)           ;; list of child fibers
      (mutable first-exn)        ;; first exception, or #f
      (mutable group-cancelled?) ;; has group been cancelled?
      (immutable group-mutex)
      (immutable all-done-cv)    ;; condition variable
      (mutable done-count)
      (mutable total-count))
    (protocol
      (lambda (new)
        (lambda ()
          (new '() #f #f (make-mutex) (make-condition) 0 0)))))

  (define (fiber-group-spawn group thunk)
    (let ([rt (current-fiber-runtime)])
      (unless rt (error 'fiber-group-spawn "no active fiber runtime"))
      (let ([f (fiber-spawn rt
                 (lambda ()
                   (guard (exn [#t
                     ;; Record first exception and cancel siblings
                     (let ([gmx (fiber-group-group-mutex group)])
                       (mutex-acquire gmx)
                       (unless (fiber-group-first-exn group)
                         (fiber-group-first-exn-set! group exn))
                       (mutex-release gmx))
                     ;; Cancel all siblings
                     (for-each (lambda (sib)
                                 (unless (fiber-done? sib)
                                   (fiber-cancel! sib)))
                               (fiber-group-fibers group))
                     (raise exn)])
                   (thunk))))])
        ;; Track child in group
        (let ([gmx (fiber-group-group-mutex group)])
          (mutex-acquire gmx)
          (fiber-group-fibers-set! group
            (cons f (fiber-group-fibers group)))
          (fiber-group-total-count-set! group
            (fx+ (fiber-group-total-count group) 1))
          (mutex-release gmx))
        f)))

  (define (%fiber-group-wait group)
    ;; Wait for all children in the group to complete.
    ;; Uses fiber-join to block on each non-done child.
    (let wait ()
      (let ([pending #f])
        (let ([gmx (fiber-group-group-mutex group)])
          (mutex-acquire gmx)
          (let find ([fibs (fiber-group-fibers group)])
            (cond
              [(null? fibs) (void)]
              [(fiber-done? (car fibs)) (find (cdr fibs))]
              [else (set! pending (car fibs))]))
          (mutex-release gmx))
        (when pending
          (guard (e [#t (void)])  ;; ignore join errors; error captured in group
            (fiber-join pending))
          (wait)))))

  (define-syntax with-fiber-group
    (syntax-rules ()
      [(_ proc)
       (let ([group (make-fiber-group)])
         ;; NOTE: Cannot use dynamic-wind here because engine preemption
         ;; (via set-timer in fiber-join/yield/sleep) triggers dynamic-wind
         ;; cleanup handlers, which would cancel children prematurely.
         ;; Instead, use guard for error cleanup.
         (guard (exn
                  [#t
                   ;; Cancel any still-running children on error
                   (for-each (lambda (f)
                               (unless (fiber-done? f)
                                 (fiber-cancel! f)))
                             (fiber-group-fibers group))
                   (raise exn)])
           (proc group)
           ;; Wait for all children to complete
           (%fiber-group-wait group)
           ;; Re-raise first exception if any
           (let ([exn (fiber-group-first-exn group)])
             (when exn
               ;; Cancel any stragglers before re-raising
               (for-each (lambda (f)
                           (unless (fiber-done? f)
                             (fiber-cancel! f)))
                         (fiber-group-fibers group))
               (raise exn)))))]))

  ;; =========================================================================
  ;; Fiber-aware semaphore
  ;; =========================================================================
  ;;
  ;; Counting semaphore that parks fibers instead of blocking OS threads.
  ;; Used for admission control (max concurrent connections, etc.).

  (define-record-type fiber-semaphore
    (fields
      (mutable count)
      (immutable mutex)
      (mutable waiters))     ;; list of (fiber . gate) pairs
    (protocol
      (lambda (new)
        (lambda (max-count)
          (new max-count (make-mutex) '())))))

  ;; Acquire a permit. If none available, park the fiber until one is released.
  (define (fiber-semaphore-acquire! sem)
    (let ([mx (fiber-semaphore-mutex sem)])
      (mutex-acquire mx)
      (let ([c (fiber-semaphore-count sem)])
        (cond
          [(> c 0)
           ;; Permit available — take it
           (fiber-semaphore-count-set! sem (- c 1))
           (mutex-release mx)]
          [else
           ;; No permits — park the fiber
           (let* ([f (fiber-self)]
                  [gate (box 'channel)])
             (fiber-semaphore-waiters-set! sem
               (append (fiber-semaphore-waiters sem) (list (cons f gate))))
             (mutex-release mx)
             ;; Park
             (fiber-gate-set! f gate)
             (set-timer 1)
             (spin-until-gate gate)
             (fiber-gate-set! f #f))]))))

  ;; Release a permit. If fibers are waiting, wake the first one.
  (define (fiber-semaphore-release! sem)
    (let ([mx (fiber-semaphore-mutex sem)])
      (mutex-acquire mx)
      (let ([waiters (fiber-semaphore-waiters sem)])
        (cond
          [(null? waiters)
           ;; No waiters — increment count
           (fiber-semaphore-count-set! sem (+ (fiber-semaphore-count sem) 1))
           (mutex-release mx)]
          [else
           ;; Wake the first waiter
           (let ([entry (car waiters)])
             (fiber-semaphore-waiters-set! sem (cdr waiters))
             (mutex-release mx)
             ;; Open their gate and re-enqueue
             (set-box! (cdr entry) 'done)
             (wake-fiber! (car entry)))]))))

  ;; Try to acquire without blocking. Returns #t on success, #f if no permits.
  (define (fiber-semaphore-try-acquire! sem)
    (let ([mx (fiber-semaphore-mutex sem)])
      (mutex-acquire mx)
      (let ([c (fiber-semaphore-count sem)])
        (cond
          [(> c 0)
           (fiber-semaphore-count-set! sem (- c 1))
           (mutex-release mx)
           #t]
          [else
           (mutex-release mx)
           #f]))))

) ;; end library
