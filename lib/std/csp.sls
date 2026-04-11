#!chezscheme
;;; (std csp) — Communicating Sequential Processes over OS threads
;;;
;;; Channels with blocking put/get and non-blocking try variants,
;;; buffered or unbuffered, safe for multi-producer/multi-consumer
;;; use. Built on Chez Scheme's mutex + condition variables.
;;;
;;; NOTE ON THREADS: `go` and `go-named` are thin wrappers around
;;; `fork-thread` — each `go` spawns a real OS thread. There is no
;;; CPS transform and no green-thread scheduler. For lightweight
;;; fan-out up to a few thousand threads this is fine; don't expect
;;; to scale to millions of concurrent go-blocks the way Clojure's
;;; core.async does.
;;;
;;; NOTE ON SELECT: multi-channel select / alts! is NOT provided by
;;; this module. Build it on top of (std event), or use explicit
;;; polling with `chan-try-get`.
;;;
;;; NOTE ON BUFFERS: three policies are supported:
;;;   - fixed   : `make-channel/buf`      — blocks the writer when full
;;;   - sliding : `make-channel/sliding`  — drops the oldest queued value
;;;   - dropping: `make-channel/dropping` — drops the incoming value
;;;
;;; NOTE ON TRANSDUCERS: a channel can be "backed" by a transducer via
;;; the `channel-xform-fn-set!` hook. When set, `chan-put!` and
;;; `chan-try-put!` run the step procedure instead of a raw enqueue
;;; (the step procedure may itself call `%chan-enqueue-raw!` zero or
;;; more times to expand one input into many outputs). If the step
;;; returns the literal symbol `'stop`, the channel is closed
;;; immediately — this is how transducers like `(taking n)` signal
;;; early termination. On `chan-close!`, the done-fn is invoked first
;;; so stateful transducers (e.g. partitioning-by) can flush buffered
;;; state. The xform-fn is OPAQUE to (std csp) — it neither imports
;;; (std transducer) nor understands `reduced?`. The clj constructor
;;; in (std csp clj) wraps the user's transducer into a closure that
;;; translates `reduced` into `'stop`.
;;;
;;; API:
;;;   (make-channel)              — unbuffered channel
;;;   (make-channel n)            — buffered channel with capacity n
;;;   (make-channel/buf n)        — alias for (make-channel n)
;;;   (make-channel/sliding n)    — capacity n, drop-oldest policy
;;;   (make-channel/dropping n)   — capacity n, drop-incoming policy
;;;   (chan-put! ch val)          — blocking send (errors on closed)
;;;   (chan-get! ch)              — blocking receive (eof on closed+drained)
;;;   (chan-try-put! ch val)      — non-blocking send; #t success, #f full/closed
;;;   (chan-try-get ch)           — non-blocking receive; val or #f if empty
;;;   (chan-close! ch)            — mark channel closed
;;;   (chan-closed? ch)           — test if closed
;;;   (chan-empty? ch)            — queue is empty (not the same as closed)
;;;   (chan-kind ch)              — buffer kind: 'fixed / 'sliding / 'dropping
;;;   (go thunk)                  — spawn an OS thread (= fork-thread)
;;;   (go-named name thunk)       — spawn an OS thread; name is documentation only
;;;   (yield)                     — 1ms sleep; no scheduler to yield to
;;;   (csp-run thunk)             — run thunk (no-op wrapper)
;;;   (chan->list ch)             — drain a closed channel to a list
;;;   (chan-pipe from to proc)    — spawn a pipeline stage, closes `to` on EOF
;;;   (chan-map ch proc)          — lazy map onto a new channel
;;;   (chan-filter ch pred)       — lazy filter onto a new channel
;;;
;;; For the Clojure-style `core.async` surface (chan, >!!, <!!, alts!!,
;;; go macro with body forms, timeout, merge, mult, tap, pipeline, ...)
;;; see `(std csp clj)`.

(library (std csp)
  (export make-channel make-channel/buf
          make-channel/sliding make-channel/dropping
          channel? chan-empty? chan-kind
          chan-put! chan-get! chan-try-put! chan-try-get
          chan-close! chan-closed?
          go go-named yield csp-run
          chan->list chan-pipe chan-map chan-filter
          ;; Transducer hook — used by (std csp clj) to back a channel
          ;; with a transducer. `%chan-enqueue-raw!` is a low-level
          ;; helper that enqueues one value unconditionally (caller must
          ;; hold the channel's mutex). The xform-fn / xform-done-fn
          ;; setters attach opaque procedures that (std csp) invokes
          ;; during put / close — see the header comments.
          %chan-enqueue-raw!
          channel-xform-fn channel-xform-fn-set!
          channel-xform-done-fn channel-xform-done-fn-set!)

  (import (chezscheme))

  ;; ========== Channel ==========
  ;;
  ;; FIFO queue is represented in-place with head/tail pointers and an
  ;; explicit count. Empty: head = '(), tail = '(), count = 0. Enqueue
  ;; and dequeue are O(1). The previous implementation used `append` on
  ;; every put — O(n) per put and O(n^2) over n puts.

  (define-record-type channel
    (fields
      (mutable head)           ;; first pair of the queue, or '()
      (mutable tail)           ;; last pair of the queue, or '()
      (mutable count)          ;; number of items currently buffered
      (immutable capacity)     ;; max items (0 = unbuffered)
      (immutable kind)         ;; 'fixed / 'sliding / 'dropping
      (mutable closed?)
      (immutable mutex)
      (immutable not-empty)    ;; signaled on put or close
      (immutable not-full)     ;; signaled on get or close
      (mutable xform-fn)       ;; opaque (lambda (ch val) → 'stop | #f), or #f
      (mutable xform-done-fn)) ;; opaque (lambda (ch) → _), or #f
    (protocol
      (lambda (new)
        (case-lambda
          [() (new '() '() 0 0 'fixed #f
                   (make-mutex) (make-condition) (make-condition)
                   #f #f)]
          [(cap) (new '() '() 0 cap 'fixed #f
                      (make-mutex) (make-condition) (make-condition)
                      #f #f)]
          [(cap kind) (new '() '() 0 cap kind #f
                           (make-mutex) (make-condition) (make-condition)
                           #f #f)]))))

  (define (make-channel/buf n) (make-channel n))

  (define (make-channel/sliding n)
    (when (or (not (integer? n)) (<= n 0))
      (error 'make-channel/sliding "sliding buffer needs positive capacity" n))
    (make-channel n 'sliding))

  (define (make-channel/dropping n)
    (when (or (not (integer? n)) (<= n 0))
      (error 'make-channel/dropping "dropping buffer needs positive capacity" n))
    (make-channel n 'dropping))

  (define (chan-closed? ch) (channel-closed? ch))
  (define (chan-kind ch) (channel-kind ch))
  (define (chan-empty? ch)
    (with-mutex (channel-mutex ch)
      (zero? (channel-count ch))))

  ;; ---- queue helpers (must be called with channel-mutex held) ----

  (define (q-empty? ch) (zero? (channel-count ch)))

  (define (q-full? ch)
    (and (> (channel-capacity ch) 0)
         (>= (channel-count ch) (channel-capacity ch))))

  (define (q-enqueue! ch val)
    (let ([cell (cons val '())])
      (cond
        [(null? (channel-head ch))
         (channel-head-set! ch cell)
         (channel-tail-set! ch cell)]
        [else
         (set-cdr! (channel-tail ch) cell)
         (channel-tail-set! ch cell)])
      (channel-count-set! ch (+ (channel-count ch) 1))))

  (define (q-dequeue! ch)
    (let ([val (car (channel-head ch))])
      (channel-head-set! ch (cdr (channel-head ch)))
      (when (null? (channel-head ch))
        (channel-tail-set! ch '()))
      (channel-count-set! ch (- (channel-count ch) 1))
      val))

  ;; ---- put ----
  ;;
  ;; Three buffer policies:
  ;;   'fixed    — block the writer when the queue is at capacity
  ;;   'sliding  — drop the oldest item to make room (writer never blocks)
  ;;   'dropping — silently drop the incoming value (writer never blocks)
  ;;
  ;; For unbuffered channels (capacity=0), q-full? is always true
  ;; because count>=0>=0 is the "no slot" condition. We treat the
  ;; unbuffered case identically to fixed — the writer blocks until
  ;; a reader shows up.

  ;; Low-level raw enqueue: add one value to ch's queue and notify
  ;; any waiting reader. The caller MUST hold the channel's mutex.
  ;; Returns ch so it can serve as a reducing-function accumulator.
  ;; This is the only "back door" the transducer bridge needs from
  ;; (std csp) — it lets the buffer-rf in (std csp clj) push items
  ;; past a raw put-check.
  (define (%chan-enqueue-raw! ch val)
    (q-enqueue! ch val)
    (condition-broadcast (channel-not-empty ch))
    ch)

  ;; Put one value into a channel with the mutex already held, running
  ;; the channel's transducer step if one is attached. If the xform
  ;; returns the literal symbol 'stop (the opaque signal for reduced),
  ;; the channel is closed in place (without re-acquiring the mutex).
  ;; Without a transducer this collapses to the raw enqueue.
  (define (%chan-put-into! ch val)
    (let ([xf (channel-xform-fn ch)])
      (cond
        [xf
         (let ([result (xf ch val)])
           (when (eq? result 'stop)
             ;; Transducer signaled early termination. Mark closed
             ;; directly — we already hold the mutex, so can't reuse
             ;; chan-close! which would re-enter with-mutex.
             (channel-closed?-set! ch #t)
             (condition-broadcast (channel-not-empty ch))
             (condition-broadcast (channel-not-full ch))))]
        [else
         (q-enqueue! ch val)
         (condition-broadcast (channel-not-empty ch))])))

  (define (chan-put! ch val)
    (with-mutex (channel-mutex ch)
      (let loop ()
        (cond
          [(channel-closed? ch)
           (error 'chan-put! "channel is closed")]
          [(not (q-full? ch))
           (%chan-put-into! ch val)]
          [(eq? 'sliding (channel-kind ch))
           ;; Drop the oldest value to make room, then put.
           (q-dequeue! ch)
           (%chan-put-into! ch val)]
          [(eq? 'dropping (channel-kind ch))
           ;; Silently drop the incoming value — do NOT run the xform,
           ;; matching Clojure's behavior for a dropping buffer.
           (void)]
          [else     ;; 'fixed (and the unbuffered degenerate case)
           (condition-wait (channel-not-full ch) (channel-mutex ch))
           (loop)]))))

  (define (chan-try-put! ch val)
    (with-mutex (channel-mutex ch)
      (cond
        [(channel-closed? ch) #f]
        [(not (q-full? ch))
         (%chan-put-into! ch val)
         #t]
        [(eq? 'sliding (channel-kind ch))
         (q-dequeue! ch)
         (%chan-put-into! ch val)
         #t]
        [(eq? 'dropping (channel-kind ch))
         ;; Drop silently but report success (no block).
         #t]
        [else #f])))

  ;; ---- get ----

  (define (chan-get! ch)
    (with-mutex (channel-mutex ch)
      (let loop ()
        (cond
          [(not (q-empty? ch))
           (let ([val (q-dequeue! ch)])
             (condition-broadcast (channel-not-full ch))
             val)]
          [(channel-closed? ch)
           (eof-object)]
          [else
           (condition-wait (channel-not-empty ch) (channel-mutex ch))
           (loop)]))))

  (define (chan-try-get ch)
    (with-mutex (channel-mutex ch)
      (cond
        [(not (q-empty? ch))
         (let ([val (q-dequeue! ch)])
           (condition-broadcast (channel-not-full ch))
           val)]
        [else #f])))

  ;; ---- close ----

  (define (chan-close! ch)
    (with-mutex (channel-mutex ch)
      ;; If a transducer is attached, flush its stateful tail first
      ;; (e.g. partitioning-by's in-flight partition). The done-fn
      ;; may itself call %chan-enqueue-raw! through its buffer-rf.
      ;; We only flush once per channel — the `closed?` guard prevents
      ;; a double-flush if chan-close! races with itself.
      (let ([done (channel-xform-done-fn ch)])
        (when (and done (not (channel-closed? ch)))
          (done ch)))
      (channel-closed?-set! ch #t)
      (condition-broadcast (channel-not-empty ch))
      (condition-broadcast (channel-not-full ch))))

  ;; ========== Process spawning ==========
  ;; `go` and `go-named` are thin wrappers over `fork-thread`. Each
  ;; spawn creates a real OS thread. There is no scheduler.

  (define (go thunk)
    (fork-thread thunk))

  (define (go-named name thunk)
    ;; Chez fork-thread takes no name argument; `name` is accepted
    ;; for API compatibility and ignored at runtime.
    (fork-thread thunk))

  (define (yield)
    ;; Chez has no cooperative scheduler, so there is nothing to
    ;; yield *to*. This is a 1ms sleep that relinquishes the current
    ;; OS timeslice — useful for backoff in spin loops, not a
    ;; replacement for coroutine yielding.
    (sleep (make-time 'time-duration 1000000 0)))

  (define (csp-run thunk)
    (thunk))

  ;; ========== Channel utilities ==========

  (define (chan->list ch)
    (let loop ([acc '()])
      (let ([v (chan-get! ch)])
        (if (eof-object? v)
          (reverse acc)
          (loop (cons v acc))))))

  (define (chan-pipe from to proc)
    (go (lambda ()
          (let loop ()
            (let ([v (chan-get! from)])
              (unless (eof-object? v)
                (chan-put! to (proc v))
                (loop))))
          (chan-close! to))))

  (define (chan-map ch proc)
    (let ([out (make-channel 16)])
      (chan-pipe ch out proc)
      out))

  (define (chan-filter ch pred)
    (let ([out (make-channel 16)])
      (go (lambda ()
            (let loop ()
              (let ([v (chan-get! ch)])
                (unless (eof-object? v)
                  (when (pred v)
                    (chan-put! out v))
                  (loop))))
            (chan-close! out)))
      out))

) ;; end library
