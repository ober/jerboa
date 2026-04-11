#!chezscheme
;;; (std csp select) — multi-channel select / alts! / timeout
;;;
;;; Implements the core.async-style rendezvous operators over
;;; `(std csp)` channels. Built on a spin-poll loop with exponential
;;; back-off: each iteration tries every spec in (optionally
;;; randomized) order via `chan-try-get` / `chan-try-put!`, then
;;; sleeps a short, growing interval if nothing was ready. The
;;; back-off caps at ~10ms, so latency is bounded but idle CPU is
;;; negligible.
;;;
;;; alts! specs
;;; -----------
;;; Each spec is either:
;;;   ch             -- a take spec: `(chan-try-get ch)` → val on hit
;;;   (list ch val)  -- a put spec:  `(chan-try-put! ch val)` → #t on hit
;;;
;;; alts!/alts!! return (list result ch), matching Clojure's
;;; [val ch] shape. On a take spec, `result` is the received value
;;; (or `(eof-object)` if the channel closed). On a put spec,
;;; `result` is #t on success.
;;;
;;; Options (pass after the specs list as plain symbols):
;;;   'priority      — try specs in order instead of a random permutation
;;;   'default val   — if NO spec is ready at the first poll, return
;;;                    (list val 'default) immediately
;;;
;;; Plain symbols are used instead of colon-prefixed `:priority` /
;;; `:default` because the Jerboa reader reserves a leading `:` for
;;; Gerbil-style module paths — `:priority` becomes `(priority)`,
;;; not a symbol — so any user code calling alts!! from a .ss file
;;; wouldn't be able to spell the option.
;;;
;;; timeout
;;; -------
;;; `(timeout ms)` returns a fresh channel that closes itself after
;;; `ms` milliseconds. Taking from it with `chan-get!` or inside
;;; `alts!` yields `(eof-object)` once the deadline fires. Each
;;; call spawns one helper thread — fine for low-rate timeouts,
;;; see the Phase-4 notes in core-async.md for a timer-wheel
;;; replacement.

(library (std csp select)
  (export
    ;; Event bridge (expose for advanced use)
    chan-recv-evt chan-send-evt
    ;; Rendezvous
    alts! alts!!
    ;; Macro sugar — Clojure's alt!/alt!!
    alt! alt!!
    ;; Auxiliary keyword for alt!/alt!! default clauses. Users
    ;; who want `(default ...)` as a clause head need to import it
    ;; (it's re-exported from (std csp clj) for convenience).
    default
    ;; Timeout channel
    timeout timeout-channel
    ;; Force the timer-wheel implementation regardless of env var.
    ;; Useful for tests and for callers that always want the wheel.
    wheel-timeout)

  (import (chezscheme)
          (std csp)
          (std event)
          (std misc pqueue))

  ;; ==========================================================
  ;; Event bridge — expose a channel as a (std event) event.
  ;; poll uses chan-try-get / chan-try-put!, sync uses blocking
  ;; chan-get! / chan-put!. sync returns the same shape as poll
  ;; so (choice …) works identically whether it's spin-polling
  ;; or settling on a single event.
  ;; ==========================================================

  (define (chan-recv-evt ch)
    (make-event
      ;; poll — return the received value on hit, or #f
      (lambda ()
        (cond
          [(chan-try-get ch)
           => (lambda (v) (list v ch))]
          [(chan-closed? ch)
           ;; Drained + closed → propagate eof so the picker can
           ;; distinguish "channel closed" from "nothing yet".
           (list (eof-object) ch)]
          [else #f]))
      ;; sync — block until something comes through
      (lambda ()
        (let ([v (chan-get! ch)])
          (list v ch)))))

  (define (chan-send-evt ch val)
    (make-event
      (lambda ()
        (if (chan-try-put! ch val)
            (list #t ch)
            #f))
      (lambda ()
        (chan-put! ch val)
        (list #t ch))))

  ;; ==========================================================
  ;; alts! / alts!!
  ;;
  ;; Implements Clojure's multi-way rendezvous. Polls each spec
  ;; once per pass, backs off with sleep between passes, and
  ;; returns the first hit as `(list result channel)`.
  ;;
  ;; In core.async, alts! (without the !!) is for use inside a
  ;; go block where it parks; alts!! is the thread-blocking form.
  ;; In Jerboa, parking and blocking collapse to the same thing,
  ;; so both names are the same procedure.
  ;;
  ;; Keyword options after the specs list:
  ;;   'priority    — don't randomize pass order
  ;;   'default v   — if nothing is ready on the first pass, give
  ;;                  up and return (list v 'default)
  ;; ==========================================================

  (define (alts!! specs . opts)
    (let* ([priority?    (and (memq 'priority opts) #t)]
           [default-cell (memq 'default opts)]
           [has-default? (and default-cell #t)]
           [default-val  (if (and default-cell (pair? (cdr default-cell)))
                             (cadr default-cell) #f)])
      (let* ([pass (if priority? specs (shuffle specs))]
             [hit  (try-once pass)])
        (cond
          [hit hit]
          [has-default? (list default-val 'default)]
          [else (spin-poll specs priority?)]))))

  (define alts! alts!!)  ;; no parking distinction here

  ;; Try every spec exactly once; return the first hit or #f.
  (define (try-once specs)
    (let loop ([s specs])
      (cond
        [(null? s) #f]
        [else
         (let ([hit (try-spec (car s))])
           (if hit hit (loop (cdr s))))])))

  ;; Try one spec: take if it's a channel, put if it's (list ch val).
  (define (try-spec spec)
    (cond
      [(pair? spec)
       ;; put spec: (list ch val)
       (let ([ch  (car spec)]
             [val (cadr spec)])
         (if (chan-try-put! ch val)
             (list #t ch)
             #f))]
      [else
       ;; take spec: ch
       (let ([ch spec])
         (cond
           [(chan-try-get ch)
            => (lambda (v) (list v ch))]
           [(chan-closed? ch)
            ;; Surface eof so the caller can react to a closed chan.
            (list (eof-object) ch)]
           [else #f]))]))

  ;; Spin with exponential back-off. Caps the sleep at 10ms so
  ;; an idle alts!! uses negligible CPU.
  (define (spin-poll specs priority?)
    (let loop ([delay-us 100])
      (let* ([pass (if priority? specs (shuffle specs))]
             [hit  (try-once pass)])
        (cond
          [hit hit]
          [else
           (sleep (make-time 'time-duration (* delay-us 1000) 0))
           (loop (min (* delay-us 2) 10000))]))))

  ;; Random shuffle — Fisher–Yates over a copy of the list.
  (define (shuffle lst)
    (let ([v (list->vector lst)])
      (let loop ([i (- (vector-length v) 1)])
        (when (> i 0)
          (let* ([j (random (+ i 1))]
                 [tmp (vector-ref v i)])
            (vector-set! v i (vector-ref v j))
            (vector-set! v j tmp)
            (loop (- i 1)))))
      (vector->list v)))

  ;; ==========================================================
  ;; alt! / alt!! — macro sugar over alts!!
  ;;
  ;; `alt!!` binds the result of `alts!!` and dispatches to a
  ;; clause body based on which channel won. Each clause is either
  ;;   (ch expr)        — run expr when ch wins, with `v` bound to
  ;;                      the received value
  ;;   (default expr)   — run expr when nothing was ready at the
  ;;                      first poll pass
  ;;
  ;; This is a minimal subset of Clojure's alt! — it doesn't
  ;; implement put-clauses or the (timeout …) shorthand directly
  ;; (users can always pass `(timeout ms)` explicitly as a channel).
  ;;
  ;; The `default` identifier is used as a literal in syntax-rules.
  ;; We avoid Clojure's `:default` because Jerboa's reader rewrites
  ;; `:x` into a module path.
  ;; ==========================================================

  ;; Auxiliary keyword: usable only as a clause head in `alt!!`.
  ;; Defining it as a syntax transformer gives it a binding in
  ;; the library so that `syntax-case`'s literal matching compares
  ;; against the same binding the user gets when they import
  ;; `default` — two free identifiers spelled "default" across a
  ;; library boundary are NOT free-identifier=? in Chez, which is
  ;; why the naive literal approach failed.
  (define-syntax default
    (lambda (stx)
      (syntax-violation 'default
        "misplaced aux keyword — use inside alt!! as (default expr)"
        stx)))

  ;; The body of each clause gets `v` bound to the received value
  ;; (or #t for a successful put spec). `v` is injected into the
  ;; caller's lexical scope via datum->syntax so plain syntax-rules
  ;; hygiene doesn't hide it from user code.
  ;;
  ;; The default-clause branch is listed FIRST because the general
  ;; `(ch expr) ...` branch would otherwise match `(default expr)`
  ;; as a bogus channel clause — remember that `default` isn't a
  ;; pattern keyword until syntax-case sees it in the literals list,
  ;; and syntax-case tries branches in order.
  (define-syntax alt!!
    (lambda (stx)
      (syntax-case stx (default)
        [(k (ch expr) ... (default def-expr))
         (with-syntax ([v-id (datum->syntax #'k 'v)])
           #'(let* ([pick (alts!! (list ch ...) 'default 'none)]
                    [val  (car pick)]
                    [won  (cadr pick)])
               (cond
                 [(eq? won 'default) def-expr]
                 [(eq? won ch) (let ([v-id val]) expr)] ...
                 [else (error 'alt!! "no matching clause for channel" won)])))]
        [(k (ch expr) ...)
         (with-syntax ([v-id (datum->syntax #'k 'v)])
           #'(let* ([pick (alts!! (list ch ...))]
                    [val  (car pick)]
                    [won  (cadr pick)])
               (cond
                 [(eq? won ch) (let ([v-id val]) expr)] ...
                 [else (error 'alt!! "no matching clause for channel" won)])))])))

  (define-syntax alt!
    (syntax-rules ()
      [(_ clause ...) (alt!! clause ...)]))

  ;; ==========================================================
  ;; timeout — channel that closes itself after N milliseconds.
  ;;
  ;; Two implementations selected at library load time by the
  ;; `JERBOA_CSP_TIMER_WHEEL` environment variable.
  ;;
  ;; Default (env unset or !=1)
  ;; --------------------------
  ;; One helper thread per timeout. Cheap to spin up and fine up to
  ;; a few hundred outstanding timeouts per second. Each `(timeout N)`
  ;; allocates a thread that sleeps N ms then closes the channel.
  ;;
  ;; Wheel mode (JERBOA_CSP_TIMER_WHEEL=1)
  ;; -------------------------------------
  ;; A single long-lived timer thread owns a min-heap of absolute
  ;; deadlines. Enqueue is O(log n), dispatch is O(log n) per fire,
  ;; and there is no per-deadline thread — appropriate for high-rate
  ;; short-timeout workloads (rate limiting, retry back-off).
  ;;
  ;; Chez's `condition-wait` has no timed variant, so the wheel's
  ;; "wait until next deadline" path sleeps in 5ms chunks and
  ;; short-circuits through a size-1 wake-up channel when a new
  ;; shorter deadline is enqueued. 5ms is the practical granularity
  ;; floor; a deadline 3ms away may fire at 5ms.
  ;; ==========================================================

  (define (ms->time ms)
    (let* ([whole-secs (quotient ms 1000)]
           [rem-ms     (remainder ms 1000)]
           [nanos      (* rem-ms 1000000)])
      (make-time 'time-duration nanos whole-secs)))

  (define (%now-ms)
    (let ([t (current-time 'time-monotonic)])
      (+ (* (time-second t) 1000)
         (quotient (time-nanosecond t) 1000000))))

  ;; -- Timer wheel --------------------------------------------

  (define-record-type %timer-wheel
    (fields (immutable heap)      ;; pqueue of (deadline . chan)
            (immutable lock)      ;; mutex guarding heap
            (immutable wake-ch))) ;; size-1 wake-up channel

  (define (%make-timer-wheel)
    (let ([w (make-%timer-wheel
               (make-pqueue (lambda (a b) (< (car a) (car b))))
               (make-mutex)
               (make-channel 1))])
      (fork-thread (lambda () (%timer-wheel-loop w)))
      w))

  ;; Push (deadline . ch) onto the heap and poke the wake-up channel
  ;; so a sleeping timer thread rechecks. The poke is non-blocking;
  ;; if the wake channel is already full (previous poke not yet
  ;; consumed) we drop the new poke — one is enough.
  (define (%timer-wheel-enqueue! w deadline ch)
    (with-mutex (%timer-wheel-lock w)
      (pqueue-push! (%timer-wheel-heap w) (cons deadline ch)))
    (chan-try-put! (%timer-wheel-wake-ch w) 'poke))

  ;; Sleep in 5ms chunks until `until` (absolute deadline in ms) has
  ;; passed, or a wake-up message arrives. Returns 'expired if the
  ;; deadline was reached, 'woken if short-circuited.
  (define %wheel-chunk-ms 5)
  (define (%wait-until until wake-ch)
    (let loop ()
      (let* ([now (%now-ms)]
             [rem (- until now)])
        (cond
          [(<= rem 0) 'expired]
          [(chan-try-get wake-ch) 'woken]
          [else
           (let ([chunk (if (< rem %wheel-chunk-ms) rem %wheel-chunk-ms)])
             (sleep (ms->time chunk))
             (loop))]))))

  ;; Pop every entry whose deadline is <= now. Returns the list of
  ;; channels to close, in fire order.
  (define (%drain-expired! w now)
    (with-mutex (%timer-wheel-lock w)
      (let loop ([acc '()])
        (cond
          [(pqueue-empty? (%timer-wheel-heap w)) (reverse acc)]
          [(<= (car (pqueue-peek (%timer-wheel-heap w))) now)
           (loop (cons (cdr (pqueue-pop! (%timer-wheel-heap w))) acc))]
          [else (reverse acc)]))))

  ;; Main loop. If the heap is empty, block on the wake-up channel.
  ;; Otherwise peek the min deadline: if due, drain+close; if not,
  ;; chunk-sleep until it fires or a wake arrives.
  (define (%timer-wheel-loop w)
    (let loop ()
      (let ([next
             (with-mutex (%timer-wheel-lock w)
               (cond
                 [(pqueue-empty? (%timer-wheel-heap w)) #f]
                 [else (car (pqueue-peek (%timer-wheel-heap w)))]))])
        (cond
          [(not next)
           (chan-get! (%timer-wheel-wake-ch w))
           (loop)]
          [else
           (let ([now (%now-ms)])
             (cond
               [(<= next now)
                (for-each (lambda (ch)
                            (guard (_ [else (void)])
                              (chan-close! ch)))
                          (%drain-expired! w now))
                (loop)]
               [else
                (%wait-until next (%timer-wheel-wake-ch w))
                (loop)]))]))))

  ;; -- Dispatch -----------------------------------------------

  (define %use-wheel?
    (equal? (getenv "JERBOA_CSP_TIMER_WHEEL") "1"))

  ;; Lazily built so libraries that never call `timeout` don't pay
  ;; for a timer thread. The initial `#f` is replaced on first use
  ;; under the singleton lock.
  (define %timer-wheel-singleton #f)
  (define %timer-wheel-init-lock (make-mutex))

  (define (%ensure-timer-wheel!)
    (or %timer-wheel-singleton
        (with-mutex %timer-wheel-init-lock
          (or %timer-wheel-singleton
              (let ([w (%make-timer-wheel)])
                (set! %timer-wheel-singleton w)
                w)))))

  (define (%thread-timeout ms)
    (let ([ch (make-channel)])
      (fork-thread
        (lambda ()
          (sleep (ms->time ms))
          (chan-close! ch)))
      ch))

  ;; Always uses the timer wheel, regardless of JERBOA_CSP_TIMER_WHEEL.
  ;; Lazily spins up the singleton on first call.
  (define (wheel-timeout ms)
    (let ([ch (make-channel)]
          [w  (%ensure-timer-wheel!)])
      (%timer-wheel-enqueue! w (+ (%now-ms) ms) ch)
      ch))

  (define (timeout ms)
    (if %use-wheel?
        (wheel-timeout ms)
        (%thread-timeout ms)))

  (define timeout-channel timeout)

) ;; end library
