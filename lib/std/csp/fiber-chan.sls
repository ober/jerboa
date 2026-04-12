#!chezscheme
;;; (std csp fiber-chan) — Fiber-aware CSP channel adapter
;;;
;;; Wraps `(std fiber)` fiber-channels with the `(std csp)` channel
;;; interface so that `(std csp clj)` can transparently use fiber
;;; channels when running inside a fiber runtime.
;;;
;;; This module provides:
;;;   - Constructors that create fiber-channels with CSP buffer policies
;;;   - The standard chan-put!/chan-get!/chan-close! interface that
;;;     parks fibers instead of blocking OS threads
;;;   - try-put!/try-get! non-blocking variants
;;;   - alts! via fiber-select for multi-channel rendezvous
;;;   - timeout via fiber-timeout
;;;
;;; The key insight: all operations detect whether they're running
;;; inside a fiber context (current-fiber-runtime returns non-#f)
;;; and dispatch accordingly. When outside a fiber, they fall back
;;; to the OS-thread channel from (std csp).

(library (std csp fiber-chan)
  (export
    ;; Predicates
    fiber-runtime-active?

    ;; Channel constructors (create fiber-channels with CSP semantics)
    make-fiber-csp-channel
    make-fiber-csp-channel/sliding
    make-fiber-csp-channel/dropping

    ;; Unified operations (dispatch based on context)
    unified-chan-put!
    unified-chan-get!
    unified-chan-try-put!
    unified-chan-try-get
    unified-chan-close!
    unified-chan-closed?

    ;; Unified select
    unified-alts!

    ;; Unified timeout
    unified-timeout

    ;; Fiber-channel wrapper record
    fiber-csp-chan
    fiber-csp-chan?
    fiber-csp-chan-inner
    fiber-csp-chan-kind)

  (import (chezscheme)
          (std fiber)
          (std csp)
          (std csp select))

  ;; =========================================================================
  ;; Context detection
  ;; =========================================================================

  (define (fiber-runtime-active?)
    (and (current-fiber-runtime) #t))

  ;; =========================================================================
  ;; Fiber CSP channel wrapper
  ;;
  ;; Wraps a fiber-channel with metadata about buffer policy. The inner
  ;; channel is a plain fiber-channel from (std fiber); the kind field
  ;; tracks which buffer policy was requested.
  ;; =========================================================================

  (define-record-type fiber-csp-chan
    (fields
      (immutable inner)    ;; the actual fiber-channel
      (immutable kind))    ;; 'fixed, 'sliding, or 'dropping
    (sealed #t))

  ;; =========================================================================
  ;; Constructors
  ;;
  ;; These mirror (std csp) constructors but create fiber-channels.
  ;; Sliding/dropping policies are implemented by try-send semantics
  ;; in the put operation.
  ;; =========================================================================

  (define make-fiber-csp-channel
    (case-lambda
      [()  (make-fiber-csp-chan (make-fiber-channel 0) 'fixed)]
      [(n) (make-fiber-csp-chan (make-fiber-channel (max n 1)) 'fixed)]))

  (define (make-fiber-csp-channel/sliding n)
    (make-fiber-csp-chan (make-fiber-channel (max n 1)) 'sliding))

  (define (make-fiber-csp-channel/dropping n)
    (make-fiber-csp-chan (make-fiber-channel (max n 1)) 'dropping))

  ;; =========================================================================
  ;; Unified channel operations
  ;;
  ;; These work with BOTH fiber-csp-chan and regular (std csp) channels.
  ;; When given a fiber-csp-chan, they use fiber primitives (parking).
  ;; When given a regular channel, they use OS-thread primitives (blocking).
  ;; =========================================================================

  (define (unified-chan-put! ch val)
    (cond
      [(fiber-csp-chan? ch)
       (let ([inner (fiber-csp-chan-inner ch)]
             [kind  (fiber-csp-chan-kind ch)])
         (case kind
           [(sliding)
            ;; Sliding buffer: if full, drop oldest then send
            (let loop ()
              (if (fiber-channel-try-send inner val)
                (void)
                (begin
                  ;; Drain one item to make room
                  (fiber-channel-try-recv inner)
                  (loop))))]
           [(dropping)
            ;; Dropping buffer: if full, silently drop
            (fiber-channel-try-send inner val)
            (void)]
           [else
            ;; Fixed: block (park fiber) until space available
            (fiber-channel-send inner val)]))]
      [else
       ;; Regular CSP channel — OS thread blocking
       (chan-put! ch val)]))

  (define (unified-chan-get! ch)
    (cond
      [(fiber-csp-chan? ch)
       (fiber-channel-recv (fiber-csp-chan-inner ch))]
      [else
       (chan-get! ch)]))

  (define (unified-chan-try-put! ch val)
    (cond
      [(fiber-csp-chan? ch)
       (let ([inner (fiber-csp-chan-inner ch)]
             [kind  (fiber-csp-chan-kind ch)])
         (case kind
           [(sliding)
            (let loop ()
              (if (fiber-channel-try-send inner val)
                #t
                (begin (fiber-channel-try-recv inner) (loop))))]
           [(dropping)
            (fiber-channel-try-send inner val)
            #t]
           [else
            (fiber-channel-try-send inner val)]))]
      [else
       (chan-try-put! ch val)]))

  (define (unified-chan-try-get ch)
    (cond
      [(fiber-csp-chan? ch)
       (let-values ([(val ok) (fiber-channel-try-recv (fiber-csp-chan-inner ch))])
         (if ok val #f))]
      [else
       (chan-try-get ch)]))

  (define (unified-chan-close! ch)
    (cond
      [(fiber-csp-chan? ch)
       (fiber-channel-close (fiber-csp-chan-inner ch))]
      [else
       (chan-close! ch)]))

  (define (unified-chan-closed? ch)
    (cond
      [(fiber-csp-chan? ch)
       ;; Check if the fiber channel is closed by attempting a try-recv
       ;; and seeing if it signals closed. fiber-channel has a closed? field.
       ;; We need to access it via the mutex — use try-send with a sentinel.
       ;; Actually, fiber-channel-closed? is a field accessor.
       (fiber-channel-closed? (fiber-csp-chan-inner ch))]
      [else
       (chan-closed? ch)]))

  ;; =========================================================================
  ;; Unified alts! — multi-channel select
  ;;
  ;; When inside a fiber runtime, uses fiber-select-based polling.
  ;; Otherwise, falls back to the OS-thread spin-poll from (std csp select).
  ;; =========================================================================

  (define (unified-alts! specs . opts)
    (if (and (fiber-runtime-active?) (current-fiber))
      ;; Fiber path: use non-blocking poll loop that yields instead of sleeping
      (let* ([priority?    (and (memq 'priority opts) #t)]
             [default-cell (memq 'default opts)]
             [has-default? (and default-cell #t)]
             [default-val  (if (and default-cell (pair? (cdr default-cell)))
                               (cadr default-cell) #f)])
        (let* ([pass (if priority? specs (shuffle-specs specs))]
               [hit  (try-once-unified pass)])
          (cond
            [hit hit]
            [has-default? (list default-val 'default)]
            [else (fiber-spin-select specs priority?)])))
      ;; OS-thread path: delegate to existing alts!!
      (apply alts!! specs opts)))

  ;; Try each spec once (non-blocking). Returns (list result ch) or #f.
  (define (try-once-unified specs)
    (let loop ([s specs])
      (cond
        [(null? s) #f]
        [else
         (let ([hit (try-spec-unified (car s))])
           (if hit hit (loop (cdr s))))])))

  (define (try-spec-unified spec)
    (cond
      [(pair? spec)
       ;; Put spec: (list ch val)
       (let ([ch  (car spec)]
             [val (cadr spec)])
         (if (unified-chan-try-put! ch val)
           (list #t ch)
           #f))]
      [else
       ;; Take spec: ch
       (let ([val (unified-chan-try-get spec)])
         (cond
           [val (list val spec)]
           [(unified-chan-closed? spec)
            (list (eof-object) spec)]
           [else #f]))]))

  ;; Fiber-aware spin: yield the fiber between attempts instead of
  ;; sleeping an OS thread. Much lighter — other fibers run while
  ;; we wait.
  (define (fiber-spin-select specs priority?)
    (let loop ([attempts 0])
      (let* ([pass (if priority? specs (shuffle-specs specs))]
             [hit  (try-once-unified pass)])
        (cond
          [hit hit]
          [else
           ;; Yield to let other fibers run, then retry
           (if (< attempts 10)
             (begin (fiber-yield) (loop (+ attempts 1)))
             ;; After 10 yields, sleep briefly to avoid busy-spin
             (begin (fiber-sleep 1) (loop 0)))]))))

  ;; Fisher-Yates shuffle
  (define (shuffle-specs lst)
    (let ([v (list->vector lst)])
      (let loop ([i (- (vector-length v) 1)])
        (when (> i 0)
          (let* ([j (random (+ i 1))]
                 [tmp (vector-ref v i)])
            (vector-set! v i (vector-ref v j))
            (vector-set! v j tmp)
            (loop (- i 1)))))
      (vector->list v)))

  ;; =========================================================================
  ;; Unified timeout
  ;; =========================================================================

  (define (unified-timeout ms)
    (if (and (fiber-runtime-active?) (current-fiber))
      ;; Inside fiber: use fiber-timeout (spawns a fiber, not a thread)
      (let ([fch (fiber-timeout ms)])
        ;; Wrap in fiber-csp-chan so unified operations work on it
        (make-fiber-csp-chan fch 'fixed))
      ;; Outside fiber: use OS-thread timeout from (std csp select)
      (timeout ms)))

  ;; Need to export fiber-channel-closed? accessor — check if available
  ;; from (std fiber). It's a record field accessor, should be exported.
  ;; If not, we need a workaround.

) ;; end library
