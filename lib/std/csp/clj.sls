#!chezscheme
;;; (std csp clj) — Clojure `core.async`-compatible surface (fiber-aware)
;;;
;;; A thin renaming layer over `(std csp)`, `(std csp select)`,
;;; `(std csp ops)`, and `(std csp fiber-chan)` that exposes Clojure's
;;; short operator names: chan, >!, <!, >!!, <!!, close!, poll!, offer!,
;;; alts!, alts!!, alt!, alt!!, timeout, go, go-loop, to-chan, onto-chan,
;;; merge, split, pipe, mult, tap, untap, untap-all, pub, sub, unsub,
;;; unsub-all, pipeline, pipeline-blocking, pipeline-async, promise-chan,
;;; sliding-buffer, dropping-buffer.
;;;
;;; FIBER-AWARE DISPATCH
;;; --------------------
;;; When running inside a fiber runtime (e.g. inside `fiber-httpd`),
;;; `go` spawns a fiber (~4KB), channels park fibers instead of blocking
;;; OS threads, and `alts!`/`timeout` use fiber-native primitives. When
;;; running standalone (tests, scripts), everything falls back to OS
;;; threads. No user code changes needed.
;;;
;;; GO AND THREAD
;;; -------------
;;; `(go body ...)` spawns work and returns a result channel. Inside a
;;; fiber runtime, the work runs as a fiber; outside, it's an OS thread.
;;; `(clj-thread body ...)` always uses an OS thread.
;;;
;;; BUFFER FACTORIES
;;; ----------------
;;; `(sliding-buffer n)` and `(dropping-buffer n)` return opaque
;;; buffer-spec records that `chan` recognizes.

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
    merge split split-by pipe
    ;; Broadcast
    mult tap untap untap-all
    ;; Dynamic fan-in (mix)
    mix admix unmix unmix-all toggle solo-mode
    ;; Topic
    pub sub unsub unsub-all
    ;; Pipelines
    pipeline pipeline-blocking pipeline-async
    ;; Promise
    promise-chan)

  (import (except (chezscheme) merge)
          (except (std csp) go go-named)
          (except (std csp select) alts! alts!! alt! alt!! default timeout timeout-channel)
          (std csp ops)
          (std csp fiber-chan)
          (std fiber)
          (std transducer)
          (only (std clojure) capture-dynamic-bindings apply-dynamic-bindings))

  ;; ======================================================
  ;; Buffer specs — opaque tags for chan to dispatch on
  ;; ======================================================

  (define-record-type buffer-spec
    (fields (immutable kind) (immutable size)))

  (define (sliding-buffer n)  (make-buffer-spec 'sliding  n))
  (define (dropping-buffer n) (make-buffer-spec 'dropping n))

  ;; ======================================================
  ;; chan — Clojure-style constructor
  ;;
  ;; Detects fiber context and creates the appropriate channel
  ;; type: fiber-csp-chan inside a fiber runtime, OS-thread
  ;; channel outside.
  ;; ======================================================

  ;; Build a bare channel from a buffer-size or buffer-spec argument.
  (define (%make-bare-chan x)
    (if (fiber-runtime-active?)
      ;; Fiber path: create fiber-channel wrapper
      (cond
        [(buffer-spec? x)
         (case (buffer-spec-kind x)
           [(sliding)  (make-fiber-csp-channel/sliding  (buffer-spec-size x))]
           [(dropping) (make-fiber-csp-channel/dropping (buffer-spec-size x))]
           [else       (make-fiber-csp-channel (buffer-spec-size x))])]
        [(and (integer? x) (zero? x)) (make-fiber-csp-channel)]
        [(integer? x) (make-fiber-csp-channel x)]
        [else (error 'chan "expected buffer spec or non-negative integer" x)])
      ;; OS-thread path: create regular channel
      (cond
        [(buffer-spec? x)
         (case (buffer-spec-kind x)
           [(sliding)  (make-channel/sliding  (buffer-spec-size x))]
           [(dropping) (make-channel/dropping (buffer-spec-size x))]
           [else       (make-channel (buffer-spec-size x))])]
        [(and (integer? x) (zero? x)) (make-channel)]
        [(integer? x) (make-channel x)]
        [else (error 'chan "expected buffer spec or non-negative integer" x)])))

  ;; Attach a transducer to an already-constructed channel.
  ;; Only works with OS-thread channels (fiber channels don't support
  ;; xform hooks directly). For fiber channels, the transducer is
  ;; applied inline in the put operation.
  (define (%attach-xform! ch xform ex-handler)
    (cond
      [(fiber-csp-chan? ch)
       ;; For fiber channels, wrap the channel with a transducing put
       (build-xform-fiber-chan ch xform ex-handler)]
      [else
       ;; OS-thread channel: install xform hooks on channel record
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
         ch)]))

  ;; Wrap a fiber-csp-chan with transducer support.
  ;; Since fiber channels don't have xform hooks, we create a proxy
  ;; that applies the transducer on put.
  (define-record-type xform-fiber-chan
    (fields
      (immutable inner)        ;; the fiber-csp-chan
      (immutable xform-rf)     ;; the composed reducing function
      (immutable ex-handler)   ;; exception handler or #f
      (mutable closed?))
    (sealed #t))

  (define (build-xform-fiber-chan fch xform ex-handler)
    (let* ([buffer-rf
            (case-lambda
              [() fch]
              [(acc) acc]
              [(acc val)
               (unified-chan-put! (xform-fiber-chan-inner acc) val)
               acc])]
           [rf (apply-xf xform buffer-rf)])
      (make-xform-fiber-chan fch rf ex-handler #f)))

  (define chan
    (case-lambda
      [() (if (fiber-runtime-active?)
            (make-fiber-csp-channel)
            (make-channel))]
      [(x) (%make-bare-chan x)]
      [(x xform)
       (%attach-xform! (%make-bare-chan x) xform #f)]
      [(x xform ex-handler)
       (%attach-xform! (%make-bare-chan x) xform ex-handler)]))

  ;; ======================================================
  ;; Put / take / close / poll / offer
  ;;
  ;; All operations dispatch through unified-* which handles
  ;; both fiber-csp-chan and regular channels.
  ;; ======================================================

  (define (>!! ch v)
    (cond
      [(xform-fiber-chan? ch)
       ;; Apply transducer
       (guard (exn [#t
         (if (xform-fiber-chan-ex-handler ch)
           (let ([v ((xform-fiber-chan-ex-handler ch) exn)])
             (when v (unified-chan-put! (xform-fiber-chan-inner ch) v)))
           (raise exn))])
         (let ([result ((xform-fiber-chan-xform-rf ch) ch v)])
           (when (reduced? result)
             (unified-chan-close! (xform-fiber-chan-inner ch)))))]
      [else (unified-chan-put! ch v)]))

  (define (<!! ch)
    (cond
      [(xform-fiber-chan? ch)
       (unified-chan-get! (xform-fiber-chan-inner ch))]
      [else (unified-chan-get! ch)]))

  ;; Parking and blocking are the same in fiber context (both park)
  ;; and the same in thread context (both block).
  (define >! >!!)
  (define <! <!!)

  (define (close! ch)
    (cond
      [(xform-fiber-chan? ch)
       ;; Flush transducer, then close underlying channel
       (guard (_ [#t (void)])
         ((xform-fiber-chan-xform-rf ch) ch))
       (xform-fiber-chan-closed?-set! ch #t)
       (unified-chan-close! (xform-fiber-chan-inner ch))]
      [else (unified-chan-close! ch)]))

  (define (poll! ch)
    (cond
      [(xform-fiber-chan? ch)
       (unified-chan-try-get (xform-fiber-chan-inner ch))]
      [else (unified-chan-try-get ch)]))

  (define (offer! ch v)
    (cond
      [(xform-fiber-chan? ch)
       ;; Non-blocking put through transducer
       (unified-chan-try-put! (xform-fiber-chan-inner ch) v)]
      [else (unified-chan-try-put! ch v)]))

  ;; ======================================================
  ;; go / go-loop / clj-thread
  ;;
  ;; `go` detects fiber context: inside a fiber runtime, it
  ;; spawns a fiber (~4KB); outside, it falls back to an OS
  ;; thread. In both cases, it returns a result channel.
  ;; ======================================================

  (define-syntax go
    (syntax-rules ()
      [(_ body ...)
       (let ([rt (current-fiber-runtime)]
             [%bindings (capture-dynamic-bindings)])
         (if rt
           ;; Inside fiber runtime: spawn a fiber, return fiber-csp-chan
           (let ([%result-ch (make-fiber-csp-channel 1)])
             (fiber-spawn rt
               (lambda ()
                 (apply-dynamic-bindings %bindings
                   (lambda ()
                     (guard (exn [else (unified-chan-close! %result-ch)])
                       (let ([%v (let () body ...)])
                         (unified-chan-put! %result-ch %v)
                         (unified-chan-close! %result-ch)))))))
             %result-ch)
           ;; Outside fiber runtime: OS thread, regular channel
           (let ([%result-ch (make-channel 1)])
             (fork-thread
               (lambda ()
                 (apply-dynamic-bindings %bindings
                   (lambda ()
                     (guard (exn [else (chan-close! %result-ch)])
                       (let ([%v (let () body ...)])
                         (chan-put! %result-ch %v)
                         (chan-close! %result-ch)))))))
             %result-ch)))]))

  (define-syntax go-loop
    (lambda (stx)
      (syntax-case stx ()
        [(k ((var init) ...) body ...)
         (with-syntax ([loop-id (datum->syntax #'k 'loop)])
           #'(go (let loop-id ([var init] ...) body ...)))])))

  ;; clj-thread always uses an OS thread, even inside a fiber runtime.
  ;; Use this for blocking I/O that can't be fibered.
  (define-syntax clj-thread
    (syntax-rules ()
      [(_ body ...)
       (let ([%result-ch (make-channel 1)]
             [%bindings (capture-dynamic-bindings)])
         (fork-thread
           (lambda ()
             (apply-dynamic-bindings %bindings
               (lambda ()
                 (guard (exn [else (chan-close! %result-ch)])
                   (let ([%v (let () body ...)])
                     (chan-put! %result-ch %v)
                     (chan-close! %result-ch)))))))
         %result-ch)]))

  ;; ======================================================
  ;; alts! / alts!! — unified fiber/thread dispatch
  ;; ======================================================

  (define (alts!! specs . opts)
    (apply unified-alts! specs opts))

  (define alts! alts!!)

  ;; ======================================================
  ;; alt! / alt!! — macro sugar over alts!!
  ;; ======================================================

  (define-syntax default
    (lambda (stx)
      (syntax-violation 'default
        "misplaced aux keyword — use inside alt!! as (default expr)"
        stx)))

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

  ;; ======================================================
  ;; timeout — fiber-aware
  ;; ======================================================

  (define timeout unified-timeout)

  ;; ======================================================
  ;; Clojure-named aliases for (std csp ops) procedures
  ;;
  ;; These use OS-thread channels. When fiber support is
  ;; needed for these combinators, they should be wrapped.
  ;; For now, the core go/chan/alts!/timeout path is
  ;; fiber-aware, which covers the vast majority of use cases.
  ;; ======================================================

  (define merge      chan-merge)
  (define split      chan-split)
  (define split-by   chan-classify-by)
  (define pipe       chan-pipe-to)
  (define async-reduce chan-reduce-async)

  (define mult       make-mult)
  (define tap        tap!)
  (define untap      untap!)
  (define untap-all  untap-all!)

  (define mix        make-mix)
  (define admix      admix!)
  (define unmix      unmix!)
  (define unmix-all  unmix-all!)
  (define toggle     toggle!)
  (define solo-mode  solo-mode!)

  (define pub        make-pub)
  (define sub        sub!)
  (define unsub      unsub!)
  (define unsub-all  unsub-all!)

  ;; ======================================================
  ;; Pipelines — fiber-aware
  ;;
  ;; pipeline: Inside fiber runtime, spawns N fiber workers.
  ;; pipeline-blocking: Always uses OS thread pool via
  ;;   work-pool-submit! for blocking I/O.
  ;; pipeline-async: Each item gets its own fiber (in fiber
  ;;   context) or thread.
  ;; ======================================================

  (define pipeline
    (case-lambda
      [(n to xf from)       (pipeline n to xf from #t)]
      [(n to xf from close?)
       (if (fiber-runtime-active?)
         ;; Fiber path: spawn N fiber workers sharing a transducer
         (fiber-pipeline n to xf from close?)
         ;; OS-thread path: existing implementation
         (chan-pipeline n to xf from close?))]))

  (define pipeline-blocking
    (case-lambda
      [(n to xf from)       (pipeline-blocking n to xf from #t)]
      [(n to xf from close?)
       ;; Always OS threads — designed for blocking I/O
       (chan-pipeline n to xf from close?)]))

  (define pipeline-async
    (case-lambda
      [(n to af from)       (pipeline-async n to af from #t)]
      [(n to af from close?)
       (if (fiber-runtime-active?)
         ;; Fiber path: each item gets a fiber
         (fiber-pipeline-async n to af from close?)
         ;; OS-thread path
         (chan-pipeline-async n to af from close?))]))

  ;; Fiber pipeline implementation: N fiber workers reading from `from`,
  ;; applying transducer, writing results to `to`.
  (define (fiber-pipeline n to xf from close?)
    (let* ([rt (current-fiber-runtime)]
           [done-count (box 0)]
           [done-mx (make-mutex)])
      (do ([i 0 (+ i 1)]) ((= i n))
        (fiber-spawn rt
          (lambda ()
            (let loop ()
              (let ([val (unified-chan-try-get from)])
                (cond
                  [val
                   ;; Apply transducer step and put result
                   (let* ([buffer-rf
                           (case-lambda
                             [() (void)]
                             [(acc) (void)]
                             [(acc v) (unified-chan-put! to v)])]
                          [rf (apply-xf xf buffer-rf)])
                     (rf #f val)
                     (rf #f))
                   (loop)]
                  [(unified-chan-closed? from)
                   ;; Input exhausted
                   (mutex-acquire done-mx)
                   (let ([c (+ (unbox done-count) 1)])
                     (set-box! done-count c)
                     (mutex-release done-mx)
                     (when (and close? (= c n))
                       (unified-chan-close! to)))]
                  [else
                   ;; No data yet, yield and retry
                   (fiber-yield)
                   (loop)]))))))))
  ;; Fiber async pipeline: each item gets its own fiber
  (define (fiber-pipeline-async n to af from close?)
    (let ([rt (current-fiber-runtime)]
          [sem (make-fiber-semaphore n)])
      (fiber-spawn rt
        (lambda ()
          (let loop ()
            (let ([val (unified-chan-try-get from)])
              (cond
                [val
                 (fiber-semaphore-acquire! sem)
                 (fiber-spawn rt
                   (lambda ()
                     (let ([result-ch (make-fiber-csp-channel 1)])
                       (af val result-ch)
                       ;; Read result and forward to output
                       (let ([result (unified-chan-get! result-ch)])
                         (unified-chan-put! to result))
                       (fiber-semaphore-release! sem))))
                 (loop)]
                [(unified-chan-closed? from)
                 ;; Wait for all in-flight items
                 (do ([i 0 (+ i 1)]) ((= i n))
                   (fiber-semaphore-acquire! sem))
                 (when close? (unified-chan-close! to))]
                [else
                 (fiber-yield)
                 (loop)])))))))

  (define promise-chan make-promise-channel)

) ;; end library

