;;; Coroutines — Phase 5b (Track 12.2)
;;;
;;; Symmetric coroutines implemented on top of call/cc.
;;;
;;; Each coroutine wraps a thunk that receives a `yield` procedure.
;;; Calling `yield` suspends the coroutine and returns a value to
;;; whoever last called `coroutine-transfer`.  The coroutine is resumed
;;; by the next call to `coroutine-transfer`, which passes a value back
;;; to the waiting `yield` call.
;;;
;;; States:
;;;   ready      — created, not yet started
;;;   running    — currently executing
;;;   suspended  — paused at a `yield` call
;;;   done       — thunk returned normally
;;;
;;; Exports:
;;;   make-coroutine          thunk → coroutine
;;;   coroutine?              val → bool
;;;   coroutine-state         co → 'ready|'running|'suspended|'done
;;;   coroutine-transfer      co [val] → val
;;;   coroutine-done?         co → bool
;;;   make-round-robin-scheduler  → scheduler
;;;   scheduler-add!          sched co → void
;;;   scheduler-run!          sched → void

(library (std control coroutine)
  (export
    make-coroutine
    coroutine?
    coroutine-state
    coroutine-transfer
    coroutine-done?
    make-round-robin-scheduler
    scheduler-add!
    scheduler-run!)

  (import (chezscheme))

  ;; -----------------------------------------------------------------------
  ;; Coroutine record
  ;; -----------------------------------------------------------------------

  (define-record-type coroutine-record
    (fields
      (mutable state   coroutine-state   %coroutine-set-state!)
      (mutable resume  %coroutine-resume %coroutine-set-resume!)
      (mutable caller  %coroutine-caller %coroutine-set-caller!))
    (protocol
      (lambda (new)
        (lambda ()
          (new 'ready #f #f)))))

  ;; -----------------------------------------------------------------------
  ;; Public constructor
  ;; -----------------------------------------------------------------------

  ;; make-coroutine : (yield → any) → coroutine
  ;;
  ;; `thunk` receives a `yield` procedure.  Calling (yield val) suspends
  ;; the coroutine and returns val to the caller of coroutine-transfer.
  ;; The value passed to the next coroutine-transfer becomes yield's result.

  (define (make-coroutine thunk)
    (let ([co (make-coroutine-record)])
      ;; Attach the thunk as the initial transfer action
      (%coroutine-set-resume!
        co
        (lambda (val)
          ;; This lambda is invoked on the first coroutine-transfer.
          ;; We build the yield procedure here so it closes over `co`.
          (define (yield . yrest)
            (let ([yval (if (null? yrest) (void) (car yrest))])
              (call/cc
                (lambda (k)
                  (%coroutine-set-resume! co k)
                  (%coroutine-set-state! co 'suspended)
                  ((%coroutine-caller co) yval)))))
          (%coroutine-set-state! co 'running)
          (thunk yield)
          ;; thunk returned — coroutine is done
          (%coroutine-set-state! co 'done)
          (%coroutine-set-resume! co #f)
          ((%coroutine-caller co) (void))))
      co))

  ;; -----------------------------------------------------------------------
  ;; coroutine? — type predicate
  ;; -----------------------------------------------------------------------

  (define (coroutine? v)
    (coroutine-record? v))

  ;; -----------------------------------------------------------------------
  ;; coroutine-done?
  ;; -----------------------------------------------------------------------

  (define (coroutine-done? co)
    (eq? (coroutine-state co) 'done))

  ;; -----------------------------------------------------------------------
  ;; coroutine-transfer co [val] → val
  ;;
  ;; Transfers control to CO, passing VAL (default: void).
  ;; Returns the value passed to the next yield (or void when done).
  ;; -----------------------------------------------------------------------

  (define (coroutine-transfer co . rest)
    (let ([val (if (null? rest) (void) (car rest))])
      (case (coroutine-state co)
        [(ready suspended)
         (let ([resume (%coroutine-resume co)])
           (call/cc
             (lambda (caller-k)
               (%coroutine-set-caller! co caller-k)
               (resume val))))]
        [(done)
         (error 'coroutine-transfer "coroutine is already done" co)]
        [(running)
         (error 'coroutine-transfer "coroutine is already running" co)]
        [else
         (error 'coroutine-transfer "coroutine in unknown state"
                (coroutine-state co))])))

  ;; -----------------------------------------------------------------------
  ;; Round-robin scheduler
  ;; -----------------------------------------------------------------------

  (define-record-type scheduler-record
    (fields (mutable queue %sched-queue %sched-set-queue!))
    (protocol
      (lambda (new)
        (lambda () (new '())))))

  (define (make-round-robin-scheduler)
    (make-scheduler-record))

  (define (scheduler-add! sched co)
    (%sched-set-queue! sched
      (append (%sched-queue sched) (list co))))

  ;; scheduler-run! — repeatedly cycle through the queue until all done
  (define (scheduler-run! sched)
    (let loop ()
      (let ([alive (filter (lambda (co) (not (coroutine-done? co)))
                           (%sched-queue sched))])
        (when (not (null? alive))
          (%sched-set-queue! sched alive)
          (for-each (lambda (co) (coroutine-transfer co)) alive)
          (loop)))))

)
