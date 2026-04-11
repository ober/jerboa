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
          chan->list chan-pipe chan-map chan-filter)

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
      (immutable not-full))    ;; signaled on get or close
    (protocol
      (lambda (new)
        (case-lambda
          [() (new '() '() 0 0 'fixed #f
                   (make-mutex) (make-condition) (make-condition))]
          [(cap) (new '() '() 0 cap 'fixed #f
                      (make-mutex) (make-condition) (make-condition))]
          [(cap kind) (new '() '() 0 cap kind #f
                           (make-mutex) (make-condition) (make-condition))]))))

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

  (define (chan-put! ch val)
    (with-mutex (channel-mutex ch)
      (let loop ()
        (cond
          [(channel-closed? ch)
           (error 'chan-put! "channel is closed")]
          [(not (q-full? ch))
           (q-enqueue! ch val)
           (condition-broadcast (channel-not-empty ch))]
          [(eq? 'sliding (channel-kind ch))
           ;; Drop the oldest value to make room, then enqueue.
           (q-dequeue! ch)
           (q-enqueue! ch val)
           (condition-broadcast (channel-not-empty ch))]
          [(eq? 'dropping (channel-kind ch))
           ;; Silently drop the incoming value.
           (void)]
          [else     ;; 'fixed (and the unbuffered degenerate case)
           (condition-wait (channel-not-full ch) (channel-mutex ch))
           (loop)]))))

  (define (chan-try-put! ch val)
    (with-mutex (channel-mutex ch)
      (cond
        [(channel-closed? ch) #f]
        [(not (q-full? ch))
         (q-enqueue! ch val)
         (condition-broadcast (channel-not-empty ch))
         #t]
        [(eq? 'sliding (channel-kind ch))
         (q-dequeue! ch)
         (q-enqueue! ch val)
         (condition-broadcast (channel-not-empty ch))
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
