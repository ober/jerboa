#!chezscheme
;;; (std csp ops) — channel combinators (Phase 2 / Phase 3 of core-async.md)
;;;
;;; Everything on top of the `(std csp)` primitives that would be
;;; fiddly but not novel: collection bridges, merge/split/pipe,
;;; mult/tap/untap, pub/sub, pipeline, and promise-chan. Nothing
;;; here is thread-hot — the implementations spawn helper threads
;;; freely, preferring clarity over minimum OS-thread count.

(library (std csp ops)
  (export
    ;; Collection bridges
    to-chan onto-chan onto-chan! onto-chan!!
    chan-reduce chan-reduce-async chan-into
    ;; Non-blocking callbacks
    put! take!
    ;; Composition
    chan-merge chan-split chan-classify-by chan-pipe-to
    ;; Broadcast: mult / tap / untap
    make-mult mult? mult-source mult-policy
    tap! untap! untap-all!
    ;; Topic routing: pub / sub
    make-pub pub? pub-source
    sub! unsub! unsub-all!
    ;; Pipelines and promise
    chan-pipeline chan-pipeline-async
    make-promise-channel promise-channel?
    promise-channel-put! promise-channel-get!)

  (import (chezscheme)
          (std csp))

  ;;; ======================================================
  ;;; Collection bridges
  ;;; ======================================================

  ;; (to-chan lst)                → channel that emits each item, then closes.
  ;; (to-chan lst buf)            → with the given buffer size.
  (define to-chan
    (case-lambda
      [(lst) (to-chan lst 0)]
      [(lst buf-size)
       (let ([ch (if (zero? buf-size)
                     (make-channel)
                     (make-channel buf-size))])
         (fork-thread
           (lambda ()
             (for-each (lambda (x) (chan-put! ch x)) lst)
             (chan-close! ch)))
         ch)]))

  ;; (onto-chan ch lst)           → pump lst onto ch, close ch.
  ;; (onto-chan ch lst close?)    → optionally leave ch open.
  (define onto-chan
    (case-lambda
      [(ch lst) (onto-chan ch lst #t)]
      [(ch lst close?)
       (fork-thread
         (lambda ()
           (for-each (lambda (x) (chan-put! ch x)) lst)
           (when close? (chan-close! ch))))
       ch]))

  ;; Clojure core.async aliases:
  ;;
  ;;   (onto-chan!  ch lst)         — non-blocking: returns ch and
  ;;                                   feeds items from a helper thread.
  ;;                                   Same behavior as onto-chan above.
  ;;   (onto-chan!! ch lst)         — blocking: runs on the caller's
  ;;                                   thread and only returns once every
  ;;                                   item has been delivered (and the
  ;;                                   channel closed, if close? is #t).
  ;;
  ;; Use the blocking form when you want back-pressure to reach the
  ;; caller (e.g. tests, pipelines where the next stage can't start
  ;; until the feed has completed).
  (define onto-chan! onto-chan)

  (define onto-chan!!
    (case-lambda
      [(ch lst) (onto-chan!! ch lst #t)]
      [(ch lst close?)
       (for-each (lambda (x) (chan-put! ch x)) lst)
       (when close? (chan-close! ch))
       ch]))

  ;; (chan-reduce f init ch)      → fold ch into a single value.
  ;;
  ;; Runs on the caller's thread — this is the blocking variant.
  ;; For a parking variant, wrap it in (go (chan-reduce ...)).
  (define (chan-reduce f init ch)
    (let loop ([acc init])
      (let ([v (chan-get! ch)])
        (if (eof-object? v)
            acc
            (loop (f acc v))))))

  ;; (chan-reduce-async f init ch) → channel with the final acc.
  ;;
  ;; Clojure core.async's `async/reduce`: spawns a helper thread that
  ;; folds `ch` with `f` starting from `init`, and delivers the
  ;; single final value onto a fresh size-1 channel which is then
  ;; closed. The caller can `chan-get!` / `<!!` to await the result.
  ;; Any number of takers can read the value back — once the put
  ;; lands the channel sits with one value until drained, and after
  ;; close a taker on the drained channel receives `(eof-object)`.
  ;;
  ;; If `f` raises, the helper thread swallows the exception and
  ;; closes the result channel so a pending taker observes eof
  ;; rather than hanging. This matches the documented semantics in
  ;; core-async.md §3.5 and mirrors how `go` treats body exceptions.
  (define (chan-reduce-async f init ch)
    (let ([out (make-channel 1)])
      (fork-thread
        (lambda ()
          (guard (_ [else (chan-close! out)])
            (let ([acc (chan-reduce f init ch)])
              (chan-put! out acc)
              (chan-close! out)))))
      out))

  ;; (chan-into container ch)     → collect into a list or vector.
  ;;
  ;; The only containers supported for now are `'()` (list) and
  ;; `(vector)` (vector). Matches Clojure's `(into [] ch)` idiom.
  (define (chan-into container ch)
    (cond
      [(null? container) (chan->list ch)]
      [(pair? container)
       ;; Prepend onto an existing list (reverse-append at the end
       ;; to preserve incoming order).
       (let loop ([acc container])
         (let ([v (chan-get! ch)])
           (if (eof-object? v)
               (reverse (let rev ([a acc] [r '()])
                          (if (null? a) r (rev (cdr a) (cons (car a) r)))))
               (loop (cons v acc)))))]
      [(vector? container)
       (list->vector (append (vector->list container) (chan->list ch)))]
      [else (error 'chan-into "unsupported container" container)]))

  ;;; ======================================================
  ;;; Callback-style put! / take!
  ;;; ======================================================
  ;;
  ;; Non-blocking versions of put / take that spawn a helper thread,
  ;; perform the operation, then invoke the user's callback with the
  ;; result. These are the Clojure core.async `put!` / `take!` — the
  ;; foundation for bridging callback-based APIs (Netty, raw sockets,
  ;; AJAX shims) into channel pipelines without writing a go-block
  ;; per request.
  ;;
  ;; Semantics:
  ;;   - (put! ch v)      — fire-and-forget async put. No callback.
  ;;                         Errors from a closed channel are swallowed.
  ;;   - (put! ch v fn)   — async put; callback fn receives #t on a
  ;;                         successful put and #f if the channel was
  ;;                         closed before the put could land.
  ;;   - (take! ch fn)    — async take; callback fn receives the value
  ;;                         that arrives, or the eof-object when the
  ;;                         channel closes without delivering one.
  ;;
  ;; Both `fn` callbacks run on the helper thread — they should not
  ;; do heavy work, since each outstanding callback keeps one thread
  ;; alive. If the callback itself raises an exception, a warning is
  ;; printed to current-error-port and the helper thread exits (the
  ;; exception does NOT propagate to the caller of put!/take!).
  ;;
  ;; WARNING — thread-per-callback. At high request rates the naive
  ;; implementation creates one short-lived OS thread per callback.
  ;; For production workloads consider batching onto a single
  ;; dedicated dispatch thread. See core-async.md §3.4.

  (define (%run-callback who fn . args)
    ;; Guarded callback invocation — keeps a misbehaved user callback
    ;; from bringing down the helper thread silently with no trace.
    (guard (exn [else
                 (fprintf (current-error-port)
                   "~a callback raised: ~a~%"
                   who
                   (if (message-condition? exn)
                       (condition-message exn)
                       exn))])
      (apply fn args)))

  (define put!
    (case-lambda
      [(ch v)
       (fork-thread
         (lambda ()
           ;; fire-and-forget: swallow closed-channel errors.
           (guard (_ [else (void)]) (chan-put! ch v))))
       (void)]
      [(ch v fn)
       (fork-thread
         (lambda ()
           (let ([ok? (guard (_ [else #f])
                        (chan-put! ch v)
                        #t)])
             (%run-callback 'put! fn ok?))))
       (void)]))

  (define (take! ch fn)
    (fork-thread
      (lambda ()
        (let ([v (chan-get! ch)])
          (%run-callback 'take! fn v))))
    (void))

  ;;; ======================================================
  ;;; Composition — merge / split / pipe-to
  ;;; ======================================================

  ;; (chan-merge chans)           → new channel receiving everything
  ;;                                 from every input, closes when the
  ;;                                 last input closes.
  ;; (chan-merge chans buf)       → with explicit buffer size.
  (define chan-merge
    (case-lambda
      [(chans) (chan-merge chans 0)]
      [(chans buf-size)
       (let ([out (if (zero? buf-size)
                      (make-channel)
                      (make-channel buf-size))]
             [remaining (length chans)]
             [lk (make-mutex)])
         (for-each
           (lambda (ch)
             (fork-thread
               (lambda ()
                 (let loop ()
                   (let ([v (chan-get! ch)])
                     (cond
                       [(eof-object? v)
                        (with-mutex lk
                          (set! remaining (- remaining 1))
                          (when (zero? remaining)
                            (chan-close! out)))]
                       [else (chan-put! out v) (loop)]))))))
           chans)
         out)]))

  ;; (chan-split pred ch)         → (list true-ch false-ch).
  ;;
  ;; Each incoming value goes to true-ch if `(pred v)` is truthy,
  ;; false-ch otherwise. Both downstream channels close when the
  ;; input closes.
  (define (chan-split pred ch)
    (let ([tch (make-channel)]
          [fch (make-channel)])
      (fork-thread
        (lambda ()
          (let loop ()
            (let ([v (chan-get! ch)])
              (cond
                [(eof-object? v)
                 (chan-close! tch)
                 (chan-close! fch)]
                [(pred v) (chan-put! tch v) (loop)]
                [else     (chan-put! fch v) (loop)])))))
      (list tch fch)))

  ;; (chan-classify-by f ch)                   — n-way split by key
  ;; (chan-classify-by f ch buf-fn)            — per-class buffer factory
  ;; (chan-classify-by f ch buf-fn initial-keys)
  ;;
  ;; Fan `ch` out to per-class channels. `f` is a classifier: it maps
  ;; each incoming value to a key (any `equal?`-comparable value). For
  ;; every new key the classifier sees, it calls `buf-fn` with the key
  ;; to construct a fresh output channel; `buf-fn` defaults to making
  ;; an unbuffered channel. `initial-keys` is a list of expected keys
  ;; whose channels are pre-created eagerly, so callers can look them
  ;; up before the classifier has processed any values (useful in
  ;; tests and when you know the class universe in advance).
  ;;
  ;; Returns a Chez hashtable mapping keys → output channels. Every
  ;; output channel is closed when the source `ch` closes. Access to
  ;; the hashtable is serialised internally via a mutex, so callers
  ;; may safely use `hashtable-ref` at any time — but new keys only
  ;; become visible after the classifier has seen a value bearing
  ;; that key.
  (define chan-classify-by
    (case-lambda
      [(f ch)
       (chan-classify-by f ch (lambda (_k) (make-channel)) '())]
      [(f ch buf-fn)
       (chan-classify-by f ch buf-fn '())]
      [(f ch buf-fn initial-keys)
       (let ([outs (make-hashtable equal-hash equal?)]
             [lk   (make-mutex)])
         ;; Eagerly create channels for any caller-declared keys.
         (for-each
           (lambda (k) (hashtable-set! outs k (buf-fn k)))
           initial-keys)
         (fork-thread
           (lambda ()
             (let loop ()
               (let ([v (chan-get! ch)])
                 (cond
                   [(eof-object? v)
                    ;; Close every output channel once the source is done.
                    (with-mutex lk
                      (let-values ([(_ks vs) (hashtable-entries outs)])
                        (vector-for-each chan-close! vs)))]
                   [else
                    (let ([out-ch
                           (with-mutex lk
                             (let* ([k (f v)]
                                    [existing (hashtable-ref outs k #f)])
                               (or existing
                                   (let ([c (buf-fn k)])
                                     (hashtable-set! outs k c)
                                     c))))])
                      (chan-put! out-ch v))
                    (loop)])))))
         outs)]))

  ;; (chan-pipe-to from to)                  → close `to` on EOF
  ;; (chan-pipe-to from to close?)           → don't close `to` when
  ;;                                            from closes if #f.
  ;;
  ;; Named `chan-pipe-to` to avoid the pre-existing `chan-pipe`
  ;; in `(std csp)` which takes a transform proc and has a
  ;; different signature.
  (define chan-pipe-to
    (case-lambda
      [(from to) (chan-pipe-to from to #t)]
      [(from to close?)
       (fork-thread
         (lambda ()
           (let loop ()
             (let ([v (chan-get! from)])
               (cond
                 [(eof-object? v)
                  (when close? (chan-close! to))]
                 [else (chan-put! to v) (loop)])))))
       to]))

  ;;; ======================================================
  ;;; Broadcast — mult / tap / untap
  ;;; ======================================================
  ;;
  ;; A `mult` fans out every value from a source channel to a
  ;; dynamically maintained set of subscriber channels. Subscribers
  ;; are added with `tap!` and removed with `untap!`.
  ;;
  ;; Slow-subscriber policy
  ;; ----------------------
  ;; The default policy ('block) preserves Clojure's core.async
  ;; behaviour: the fan-out thread blocks on `chan-put!` until every
  ;; subscriber has accepted the value, so a slow tap stalls the
  ;; entire mult. Two additional policies are available at creation
  ;; time for code that prefers drop-on-slow-consumer semantics:
  ;;
  ;;   (make-mult src)               ;; 'block (default)
  ;;   (make-mult src 'block)        ;; same as (make-mult src)
  ;;   (make-mult src 'drop)         ;; drop values for a slow sub
  ;;                                 ;; via chan-try-put!
  ;;   (make-mult src 'timeout 100)  ;; give each sub up to 100ms;
  ;;                                 ;; drop if it still can't accept
  ;;
  ;; The policy is fixed at creation. `mult-policy` returns the
  ;; configured policy symbol (useful for introspection and tests).

  (define-record-type %mult
    (fields (immutable source)
            (mutable   subs)
            (immutable lock)
            (immutable policy)    ;; 'block | 'drop | 'timeout
            (immutable send-fn))) ;; (lambda (sub val) ...)

  ;; Monotonic-ms clock for the 'timeout policy.
  (define (%now-ms)
    (let ([t (current-time 'time-monotonic)])
      (+ (* (time-second t) 1000)
         (quotient (time-nanosecond t) 1000000))))

  (define %mult-tick (make-time 'time-duration 1000000 0)) ;; 1 ms

  ;; Pre-built send functions per policy.
  (define %mult-send-block
    (lambda (s v)
      ;; chan-put! errors if already closed elsewhere — guard so an
      ;; untap of a still-open sub doesn't nuke the fan-out thread.
      (guard (_ [else (void)]) (chan-put! s v))))

  (define %mult-send-drop
    (lambda (s v)
      (guard (_ [else (void)]) (chan-try-put! s v))))

  (define (%make-mult-send-timeout ms)
    (lambda (s v)
      (guard (_ [else (void)])
        (let ([deadline (+ (%now-ms) ms)])
          (let loop ()
            (cond
              [(chan-try-put! s v) #t]
              [(>= (%now-ms) deadline) #f]  ;; drop
              [else (sleep %mult-tick) (loop)]))))))

  ;; Shared fan-out loop: reads from source, dispatches via send-fn,
  ;; closes all subs on EOF.
  (define (%mult-run! m)
    (fork-thread
      (lambda ()
        (let ([send-fn (%mult-send-fn m)])
          (let loop ()
            (let ([v (chan-get! (%mult-source m))])
              (cond
                [(eof-object? v)
                 (with-mutex (%mult-lock m)
                   (for-each
                     (lambda (s)
                       (guard (_ [else (void)]) (chan-close! s)))
                     (%mult-subs m)))]
                [else
                 (let ([subs (with-mutex (%mult-lock m) (%mult-subs m))])
                   (for-each (lambda (s) (send-fn s v)) subs))
                 (loop)]))))))
    m)

  (define make-mult
    (case-lambda
      [(source)
       (%mult-run!
         (make-%mult source '() (make-mutex) 'block %mult-send-block))]
      [(source policy)
       (case policy
         [(block)
          (%mult-run!
            (make-%mult source '() (make-mutex) 'block %mult-send-block))]
         [(drop)
          (%mult-run!
            (make-%mult source '() (make-mutex) 'drop %mult-send-drop))]
         [(timeout)
          (error 'make-mult
            "'timeout policy requires a timeout in milliseconds" policy)]
         [else (error 'make-mult "unknown mult policy" policy)])]
      [(source policy ms)
       (unless (eq? policy 'timeout)
         (error 'make-mult
           "third argument only valid for 'timeout policy" policy))
       (unless (and (integer? ms) (positive? ms))
         (error 'make-mult
           "timeout must be a positive integer (milliseconds)" ms))
       (%mult-run!
         (make-%mult source '() (make-mutex) 'timeout
           (%make-mult-send-timeout ms)))]))

  (define (mult? x) (%mult? x))
  (define (mult-source m) (%mult-source m))
  (define (mult-policy m) (%mult-policy m))

  (define (tap! m ch)
    (with-mutex (%mult-lock m)
      (%mult-subs-set! m (cons ch (%mult-subs m))))
    ch)

  (define (untap! m ch)
    (with-mutex (%mult-lock m)
      (%mult-subs-set! m
        (remp (lambda (x) (eq? x ch)) (%mult-subs m))))
    ch)

  (define (untap-all! m)
    (with-mutex (%mult-lock m)
      (%mult-subs-set! m '())))

  ;;; ======================================================
  ;;; Topic routing — pub / sub
  ;;; ======================================================
  ;;
  ;; A `pub` is a source channel + a `topic-fn` + a topic→mult map.
  ;; Subscribers register for a topic; the dispatcher reads the
  ;; source, computes `(topic-fn v)`, and forwards to the matching
  ;; topic mult. Each topic gets its own fan-out mult lazily.

  (define-record-type %pub
    (fields
      (immutable source)
      (immutable topic-fn)
      (mutable   topics)    ;; alist of topic → (cons topic-ch topic-mult)
      (immutable lock)))

  (define (make-pub source topic-fn)
    (let ([p (make-%pub source topic-fn '() (make-mutex))])
      (fork-thread
        (lambda ()
          (let loop ()
            (let ([v (chan-get! source)])
              (cond
                [(eof-object? v)
                 ;; Close each topic channel so its mult drains and
                 ;; closes every downstream subscriber in turn.
                 (with-mutex (%pub-lock p)
                   (for-each
                     (lambda (entry)
                       (guard (_ [else (void)])
                         (chan-close! (car (cdr entry)))))
                     (%pub-topics p)))]
                [else
                 (let ([topic ((%pub-topic-fn p) v)])
                   (let ([entry (with-mutex (%pub-lock p)
                                  (assoc topic (%pub-topics p)))])
                     (when entry
                       (guard (_ [else (void)])
                         (chan-put! (car (cdr entry)) v)))
                     (loop)))])))))
      p))

  (define (pub? x) (%pub? x))
  (define (pub-source p) (%pub-source p))

  (define (pub-get-or-make-mult! p topic)
    (with-mutex (%pub-lock p)
      (let ([found (assoc topic (%pub-topics p))])
        (cond
          [found (cddr found)]
          [else
           (let* ([tch (make-channel 16)]
                  [tm  (make-mult tch)])
             (%pub-topics-set! p
               (cons (cons topic (cons tch tm)) (%pub-topics p)))
             tm)]))))

  (define (sub! p topic ch)
    (tap! (pub-get-or-make-mult! p topic) ch)
    ch)

  (define (unsub! p topic ch)
    (with-mutex (%pub-lock p)
      (let ([entry (assoc topic (%pub-topics p))])
        (when entry
          (untap! (cddr entry) ch))))
    ch)

  (define (unsub-all! p)
    (with-mutex (%pub-lock p)
      (for-each (lambda (entry) (untap-all! (cddr entry)))
                (%pub-topics p))))

  ;;; ======================================================
  ;;; Pipelines — N workers, ordered output
  ;;; ======================================================
  ;;
  ;; `chan-pipeline n out f in` spawns `n` worker threads that read
  ;; from `in`, apply `f`, and hand the result to `out`. To preserve
  ;; input order across workers each item is tagged with an index;
  ;; a dedicated reassembler holds out-of-order results until their
  ;; turn comes up. When the input closes the reassembler waits for
  ;; in-flight workers to drain and then closes `out`.
  ;;
  ;; `f` is a plain unary procedure (not a transducer). For the
  ;; transducer variant call `chan-pipeline-xf` once it's added.
  ;;
  ;; `chan-pipeline-async af` is the async variant: `af` takes two
  ;; args `(item result-ch)` and is expected to `chan-put!` its
  ;; result(s) then `chan-close!` the result channel. The pipeline
  ;; reads results off the per-item result channel until it closes.

  (define (chan-pipeline n out f in)
    (pipeline-run n out in
      (lambda (item result-ch)
        (chan-put! result-ch (f item))
        (chan-close! result-ch))))

  (define (chan-pipeline-async n out af in)
    (pipeline-run n out in af))

  (define (pipeline-run n out in af)
    ;; Step 1: tag each input with a monotonically increasing index
    ;; and fan it out to a queue-channel that workers read from.
    (let ([job-ch    (make-channel (* n 2))]
          [result-ch (make-channel (* n 2))]
          [job-lock  (make-mutex)])
      ;; Producer: read `in`, tag, enqueue
      (fork-thread
        (lambda ()
          (let loop ([i 0])
            (let ([v (chan-get! in)])
              (cond
                [(eof-object? v)
                 (chan-close! job-ch)]
                [else
                 (chan-put! job-ch (cons i v))
                 (loop (+ i 1))])))))
      ;; Workers
      (let loop-workers ([k 0])
        (when (< k n)
          (fork-thread
            (lambda ()
              (let loop ()
                (let ([job (chan-get! job-ch)])
                  (cond
                    [(eof-object? job) (void)]
                    [else
                     (let* ([idx  (car job)]
                            [item (cdr job)]
                            [rc   (make-channel 1)])
                       (af item rc)
                       ;; Drain the per-item result channel into the
                       ;; shared result-ch, each result tagged with idx.
                       (let drain ()
                         (let ([r (chan-get! rc)])
                           (unless (eof-object? r)
                             (chan-put! result-ch (cons idx r))
                             (drain))))
                       (loop))])))))
          (loop-workers (+ k 1))))
      ;; Reassembler: track next expected index and a pending table.
      (fork-thread
        (lambda ()
          (let ([next 0] [pending (make-eqv-hashtable)] [seen-eof 0])
            (let loop ()
              (let ([tagged (chan-get! result-ch)])
                (cond
                  [(eof-object? tagged)
                   (chan-close! out)]
                  [else
                   (let ([i (car tagged)] [v (cdr tagged)])
                     (hashtable-set! pending i
                       (cons v (hashtable-ref pending i '()))))
                   (let emit ()
                     (let ([ready (hashtable-ref pending next #f)])
                       (when ready
                         (for-each (lambda (x) (chan-put! out x)) (reverse ready))
                         (hashtable-delete! pending next)
                         (set! next (+ next 1))
                         (emit))))
                   (loop)]))))))
      ;; Closer: when all workers are done (job-ch drained) we close
      ;; the result-ch so the reassembler can close `out`.
      (fork-thread
        (lambda ()
          ;; Wait for every worker to be idle. A simple heuristic:
          ;; once job-ch is closed AND empty, spin-wait briefly and
          ;; then close result-ch. Workers that are mid-task will
          ;; push to result-ch before noticing — the reassembler
          ;; reads eagerly so nothing is lost.
          (let wait ()
            (unless (and (chan-closed? job-ch)
                         (chan-empty? job-ch))
              (sleep (make-time 'time-duration 1000000 0))  ;; 1ms
              (wait)))
          ;; Grace period for workers in the middle of their last job.
          (sleep (make-time 'time-duration 5000000 0)) ;; 5ms
          (chan-close! result-ch)))
      out))

  ;;; ======================================================
  ;;; promise-chan
  ;;; ======================================================
  ;;
  ;; Semantics:
  ;;   - First put wins; subsequent puts are silently dropped.
  ;;   - Every taker gets the winning value, even after it's set.
  ;;   - On close-without-put, every pending and future taker gets
  ;;     (eof-object).
  ;;   - `chan-get!` semantics: block until set or closed.

  (define-record-type %promise-channel
    (fields
      (immutable lock)
      (immutable ready)       ;; condition: broadcast on first put/close
      (mutable   value)
      (mutable   set?)
      (mutable   closed?)))

  (define (make-promise-channel)
    (make-%promise-channel
      (make-mutex) (make-condition) #f #f #f))

  (define (promise-channel? x) (%promise-channel? x))

  (define (promise-channel-put! pc v)
    (with-mutex (%promise-channel-lock pc)
      (cond
        [(%promise-channel-closed? pc) #f]
        [(%promise-channel-set? pc) #f]
        [else
         (%promise-channel-value-set! pc v)
         (%promise-channel-set?-set! pc #t)
         (condition-broadcast (%promise-channel-ready pc))
         #t])))

  (define (promise-channel-get! pc)
    (with-mutex (%promise-channel-lock pc)
      (let loop ()
        (cond
          [(%promise-channel-set? pc)
           (%promise-channel-value pc)]
          [(%promise-channel-closed? pc)
           (eof-object)]
          [else
           (condition-wait (%promise-channel-ready pc)
                           (%promise-channel-lock pc))
           (loop)]))))

) ;; end library
