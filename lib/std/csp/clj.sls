#!chezscheme
;;; (std csp clj) — Clojure `core.async`-compatible surface
;;;
;;; A thin renaming layer over `(std csp)`, `(std csp select)`, and
;;; `(std csp ops)` that exposes Clojure's short operator names:
;;; chan, >!, <!, >!!, <!!, close!, poll!, offer!, alts!, alts!!,
;;; alt!, alt!!, timeout, go, go-loop, to-chan, onto-chan, merge,
;;; split, pipe, mult, tap, untap, untap-all, pub, sub, unsub,
;;; unsub-all, pipeline, pipeline-blocking, pipeline-async,
;;; promise-chan, sliding-buffer, dropping-buffer.
;;;
;;; PARKING VS BLOCKING
;;; -------------------
;;; In Clojure core.async, `>!` and `<!` "park" a go-block on a
;;; lightweight scheduler and `>!!` / `<!!` block an OS thread. In
;;; Jerboa every `go` is a real OS thread (there is no CPS transform
;;; and no green-thread scheduler), so parking and blocking collapse
;;; to the same operation. Both name pairs are provided for
;;; compatibility — they all reduce to `chan-put!` / `chan-get!`.
;;;
;;; GO AND THREAD
;;; -------------
;;; `(go body ...)` spawns a thread, evaluates the body, puts the
;;; result onto a freshly made size-1 channel, and returns it. If the
;;; body raises an exception, the result channel is closed and any
;;; taker gets `(eof-object)`. `(go-loop ((var init) ...) body ...)`
;;; is `(go (let loop ([var init] ...) body ...))` with `loop` bound
;;; hygienically in the user's scope so bodies can tail-recur via
;;; `(loop ...)`.
;;;
;;; BUFFER FACTORIES
;;; ----------------
;;; `(sliding-buffer n)` and `(dropping-buffer n)` return opaque
;;; buffer-spec records that `chan` recognizes as a request for a
;;; sliding or dropping channel. Passing an integer keeps the
;;; default (fixed) policy.

(library (std csp clj)
  (export
    ;; Constructors
    chan sliding-buffer dropping-buffer buffer-spec?
    ;; Put / take / close / non-blocking
    >! <! >!! <!! close! poll! offer!
    ;; Async callback forms
    put! take!
    ;; Select / timeout (re-exported from std csp select)
    alts! alts!! alt! alt!! default timeout
    ;; Go / thread
    go go-loop clj-thread
    ;; Collection bridges
    to-chan onto-chan onto-chan! onto-chan!!
    async-reduce
    ;; Composition
    merge split pipe
    ;; Broadcast
    mult tap untap untap-all
    ;; Topic
    pub sub unsub unsub-all
    ;; Pipelines
    pipeline pipeline-blocking pipeline-async
    ;; Promise
    promise-chan)

  (import (except (chezscheme) merge)
          (except (std csp) go go-named)
          (std csp select)
          (std csp ops)
          (std transducer))

  ;; ======================================================
  ;; Buffer specs — opaque tags for chan to dispatch on
  ;; ======================================================

  (define-record-type buffer-spec
    (fields (immutable kind) (immutable size)))

  (define (sliding-buffer n)  (make-buffer-spec 'sliding  n))
  (define (dropping-buffer n) (make-buffer-spec 'dropping n))

  ;; ======================================================
  ;; chan — Clojure-style constructor
  ;; ======================================================
  ;;
  ;; Clojure supports all of
  ;;   (chan)
  ;;   (chan n)            (chan buf)
  ;;   (chan n xform)      (chan buf xform)
  ;;   (chan n xform eh)   (chan buf xform eh)
  ;;
  ;; With a transducer, every put runs through `xform` before landing
  ;; in the buffer. If the transducer signals early termination
  ;; (via `reduced`), the channel closes immediately. If a step raises
  ;; an exception the optional `ex-handler` is called with the
  ;; condition; its return value is enqueued verbatim (a #f return
  ;; drops the value silently, matching Clojure semantics).

  ;; Build a bare channel from a buffer-size or buffer-spec argument.
  (define (%make-bare-chan x)
    (cond
      [(buffer-spec? x)
       (case (buffer-spec-kind x)
         [(sliding)  (make-channel/sliding  (buffer-spec-size x))]
         [(dropping) (make-channel/dropping (buffer-spec-size x))]
         [else       (make-channel (buffer-spec-size x))])]
      [(and (integer? x) (zero? x)) (make-channel)]
      [(integer? x) (make-channel x)]
      [else (error 'chan "expected buffer spec or non-negative integer" x)]))

  ;; Attach a transducer to an already-constructed channel. Builds a
  ;; buffer-rf that writes directly into the channel's queue, wraps it
  ;; in the user's xform, and installs two closures (step / done) on
  ;; the channel record. `reduced` is translated into the symbol 'stop
  ;; so (std csp) does not need to know about the reduced type.
  (define (%attach-xform! ch xform ex-handler)
    (let* ([buffer-rf
            (case-lambda
              [() ch]
              [(acc) acc]
              [(acc val) (%chan-enqueue-raw! acc val) acc])]
           [rf (apply-xf xform buffer-rf)])
      (channel-xform-fn-set!
        ch
        (lambda (c val)
          (call/cc
            (lambda (k)
              (with-exception-handler
                (lambda (exn)
                  (cond
                    [ex-handler
                     (let ([v (ex-handler exn)])
                       (when v (%chan-enqueue-raw! c v))
                       (k #f))]
                    [else (raise exn)]))
                (lambda ()
                  (let ([result (rf c val)])
                    (if (reduced? result) 'stop #f))))))))
      (channel-xform-done-fn-set!
        ch
        (lambda (c)
          (call/cc
            (lambda (k)
              (with-exception-handler
                (lambda (exn)
                  (when ex-handler (ex-handler exn))
                  (k #f))
                (lambda () (rf c) #f))))))
      ch))

  (define chan
    (case-lambda
      [() (make-channel)]
      [(x) (%make-bare-chan x)]
      [(x xform)
       (%attach-xform! (%make-bare-chan x) xform #f)]
      [(x xform ex-handler)
       (%attach-xform! (%make-bare-chan x) xform ex-handler)]))

  ;; ======================================================
  ;; Put / take / close / poll / offer
  ;; ======================================================

  (define (>!! ch v)    (chan-put! ch v))
  (define (<!! ch)      (chan-get! ch))
  ;; parking vs blocking collapse in Jerboa
  (define >! >!!)
  (define <! <!!)

  (define (close! ch)   (chan-close! ch))
  (define (poll! ch)    (chan-try-get ch))
  (define (offer! ch v) (chan-try-put! ch v))

  ;; ======================================================
  ;; go / go-loop / clj-thread
  ;; ======================================================
  ;;
  ;; `go` returns a size-1 channel with the body's result, closing
  ;; on completion or exception. `clj-thread` is an alias — in
  ;; Clojure `thread` spawns a blocking OS thread while `go` spawns a
  ;; parked goroutine, but Jerboa has only OS threads so the
  ;; distinction is moot.

  (define-syntax go
    (syntax-rules ()
      [(_ body ...)
       (let ([%result-ch (make-channel 1)])
         (fork-thread
           (lambda ()
             (guard (exn [else (chan-close! %result-ch)])
               (let ([%v (let () body ...)])
                 (chan-put! %result-ch %v)
                 (chan-close! %result-ch)))))
         %result-ch)]))

  ;; go-loop expands to (go (let loop ([var init] ...) body ...))
  ;; with `loop` bound in the caller's scope (standard hygienic trick
  ;; via datum->syntax) so the user can write (loop ...) to recur.
  (define-syntax go-loop
    (lambda (stx)
      (syntax-case stx ()
        [(k ((var init) ...) body ...)
         (with-syntax ([loop-id (datum->syntax #'k 'loop)])
           #'(go (let loop-id ([var init] ...) body ...)))])))

  (define-syntax clj-thread
    (syntax-rules ()
      [(_ body ...) (go body ...)]))

  ;; ======================================================
  ;; Clojure-named aliases for (std csp ops) procedures
  ;; ======================================================

  (define merge      chan-merge)
  (define split      chan-split)
  (define pipe       chan-pipe-to)

  ;; Clojure core.async's `async/reduce` — an async fold over a
  ;; channel that returns a promise-channel holding the final value.
  (define async-reduce chan-reduce-async)

  (define mult       make-mult)
  (define tap        tap!)
  (define untap      untap!)
  (define untap-all  untap-all!)

  (define pub        make-pub)
  (define sub        sub!)
  (define unsub      unsub!)
  (define unsub-all  unsub-all!)

  (define pipeline          chan-pipeline)
  (define pipeline-blocking chan-pipeline)
  (define pipeline-async    chan-pipeline-async)

  (define promise-chan      make-promise-channel)

) ;; end library
