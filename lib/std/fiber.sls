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

    fiber?
    fiber-state
    fiber-name
    fiber-done?

    make-fiber-channel
    fiber-channel?
    fiber-channel-send
    fiber-channel-recv
    fiber-channel-try-send
    fiber-channel-try-recv
    fiber-channel-close

    current-fiber-runtime
    current-fiber

    with-fibers)

  (import (chezscheme))

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
      (immutable mx))           ;; per-fiber mutex for park/wake coordination
    (protocol
      (lambda (new)
        (lambda (id thunk name rt)
          (new id 'ready thunk name (void) rt #f (make-mutex))))))

  (define (fiber-done? f)
    (eq? (fiber-state f) 'done))

  ;; =========================================================================
  ;; Run queue
  ;; =========================================================================

  (define-record-type run-queue
    (fields
      (mutable head)
      (mutable tail)
      (mutable count)
      (immutable mutex)
      (immutable not-empty))
    (protocol
      (lambda (new)
        (lambda ()
          (new '() '() 0 (make-mutex) (make-condition))))))

  (define (rq-enqueue! rq fiber)
    (mutex-acquire (run-queue-mutex rq))
    (run-queue-tail-set! rq (cons fiber (run-queue-tail rq)))
    (run-queue-count-set! rq (fx+ (run-queue-count rq) 1))
    (condition-signal (run-queue-not-empty rq))
    (mutex-release (run-queue-mutex rq)))

  (define (rq-dequeue! rq timeout-ms)
    (mutex-acquire (run-queue-mutex rq))
    (let loop ()
      (cond
        [(pair? (run-queue-head rq))
         (let ([f (car (run-queue-head rq))])
           (run-queue-head-set! rq (cdr (run-queue-head rq)))
           (run-queue-count-set! rq (fx- (run-queue-count rq) 1))
           (mutex-release (run-queue-mutex rq))
           f)]
        [(pair? (run-queue-tail rq))
         (run-queue-head-set! rq (reverse (run-queue-tail rq)))
         (run-queue-tail-set! rq '())
         (loop)]
        [timeout-ms
         (condition-wait (run-queue-not-empty rq)
                         (run-queue-mutex rq)
                         (make-time 'time-duration
                                    (* (fxmod timeout-ms 1000) 1000000)
                                    (fxquotient timeout-ms 1000)))
         (cond
           [(pair? (run-queue-head rq))
            (let ([f (car (run-queue-head rq))])
              (run-queue-head-set! rq (cdr (run-queue-head rq)))
              (run-queue-count-set! rq (fx- (run-queue-count rq) 1))
              (mutex-release (run-queue-mutex rq))
              f)]
           [(pair? (run-queue-tail rq))
            (run-queue-head-set! rq (reverse (run-queue-tail rq)))
            (run-queue-tail-set! rq '())
            (loop)]
           [else
            (mutex-release (run-queue-mutex rq))
            #f])]
        [else
         (mutex-release (run-queue-mutex rq))
         #f])))

  (define (rq-wake-all! rq)
    (mutex-acquire (run-queue-mutex rq))
    (condition-broadcast (run-queue-not-empty rq))
    (mutex-release (run-queue-mutex rq)))

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
      (immutable run-queue)
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
        (case-lambda
          [()  (new (make-run-queue) (make-timer-queue)
                    '() (max 1 (- (cpu-count) 1))
                    #f 0 (make-mutex) 0 0
                    (make-mutex) (make-condition)
                    10000)]
          [(nworkers)
               (new (make-run-queue) (make-timer-queue)
                    '() (max 1 nworkers)
                    #f 0 (make-mutex) 0 0
                    (make-mutex) (make-condition)
                    10000)]
          [(nworkers fuel)
               (new (make-run-queue) (make-timer-queue)
                    '() (max 1 nworkers)
                    #f 0 (make-mutex) 0 0
                    (make-mutex) (make-condition)
                    (max 100 fuel))]))))

  (define (cpu-count)
    (if (threaded?) 4 1))

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
         (rq-enqueue! (fiber-runtime-run-queue rt) f)
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

  (define (fiber-yield)
    (let ([f (current-fiber)])
      (unless f (error 'fiber-yield "not running inside a fiber"))
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

  (define (mark-fiber-done! rt)
    (mutex-acquire (fiber-runtime-done-mutex rt))
    (fiber-runtime-done-fibers-set! rt
      (fx+ (fiber-runtime-done-fibers rt) 1))
    (when (fx= (fiber-runtime-done-fibers rt)
               (fiber-runtime-total-fibers rt))
      (condition-broadcast (fiber-runtime-all-done rt)))
    (mutex-release (fiber-runtime-done-mutex rt)))

  (define (handle-expire rt f remaining result)
    (fiber-state-set! f 'done)
    (fiber-result-set! f result)
    (fiber-continuation-set! f #f)
    (fiber-gate-set! f #f)
    (mark-fiber-done! rt))

  (define (handle-complete rt f new-engine)
    ;; Engine fuel exhausted — fiber was preempted.
    ;; Use per-fiber mutex to coordinate with wake-fiber!.
    (let ([gate (fiber-gate f)]
          [fmx (fiber-mx f)]
          [rq (fiber-runtime-run-queue rt)])
      (fiber-continuation-set! f (make-engine-resumer new-engine))
      (cond
        ;; No gate — normal preemption, re-enqueue
        [(not gate)
         (fiber-state-set! f 'ready)
         (rq-enqueue! rq f)]
        ;; Cooperative yield — open gate, re-enqueue
        [(eq? (unbox gate) 'yield)
         (set-box! gate 'done)
         (fiber-state-set! f 'ready)
         (rq-enqueue! rq f)]
        ;; Blocked (sleep/channel) — check if already woken
        [else
         (mutex-acquire fmx)
         (cond
           ;; Already woken by sender/timer while we were in the engine
           [(eq? (unbox gate) 'done)
            (fiber-state-set! f 'ready)
            (mutex-release fmx)
            (rq-enqueue! rq f)]
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
         (rq-enqueue! (fiber-runtime-run-queue (fiber-fiber-rt f)) f)]
        [else
         ;; Fiber still in engine — gate is set, will exit spin on resume
         (mutex-release fmx)])))

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

  (define (worker-loop rt)
    (let ([rq (fiber-runtime-run-queue rt)]
          [fuel (fiber-runtime-fuel rt)])
      (let loop ()
        (when (fiber-runtime-running? rt)
          (check-timers! rt)
          (let ([f (rq-dequeue! rq 5)])
            (when f
              (guard (exn [#t
                (fiber-state-set! f 'done)
                (fiber-result-set! f exn)
                (fiber-continuation-set! f #f)
                (fiber-gate-set! f #f)
                (mark-fiber-done! rt)])
                (run-fiber! rt f fuel))))
          (loop)))))

  ;; =========================================================================
  ;; Runtime start/stop
  ;; =========================================================================

  (define (fiber-runtime-run! rt)
    (fiber-runtime-running?-set! rt #t)
    (let ([threads
           (let build ([i (fiber-runtime-nworkers rt)] [acc '()])
             (if (fx= i 0) acc
               (build (fx- i 1)
                 (cons (fork-thread (lambda () (worker-loop rt)))
                       acc))))])
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
    (rq-wake-all! (fiber-runtime-run-queue rt))
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

) ;; end library
