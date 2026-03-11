#!chezscheme
;;; (std select) -- Go-style channel select
;;;
;;; Provides a unified select expression for waiting on multiple channels
;;; with optional timeout and non-blocking default.
;;;
;;; Syntax:
;;;   (select
;;;     [(recv ch) => (lambda (msg) ...)]    ; receive from ch
;;;     [(send ch val) => (lambda () ...)]   ; send val to ch
;;;     [(after ms) => (lambda () ...)]      ; timeout in milliseconds
;;;     [default => (lambda () ...)])        ; non-blocking fallback
;;;
;;; Semantics:
;;;   - If any channel is immediately ready, handle it (priority: listed order)
;;;   - If 'default' clause: execute it if nothing ready (non-blocking)
;;;   - If 'after' clause: block up to ms milliseconds, then run timeout handler
;;;   - Otherwise: block until a channel becomes ready

(library (std select)
  (export select channel-try-send
          recv send after default)

  (import (chezscheme)
          (std misc channel))

  ;;; Auxiliary syntax keywords for select clauses.
  ;;; Must be exported so that free-identifier=? matches at the call site.
  (define-syntax recv
    (lambda (x) (syntax-error x "recv: used outside select")))
  (define-syntax send
    (lambda (x) (syntax-error x "send: used outside select")))
  (define-syntax after
    (lambda (x) (syntax-error x "after: used outside select")))
  (define-syntax default
    (lambda (x) (syntax-error x "default: used outside select")))

  ;;; ========== channel-try-send: non-blocking send attempt ==========
  ;; Returns #t if value was enqueued, #f if channel is full or closed.
  (define (channel-try-send ch val)
    ;; We use channel-try-get's counterpart: we need non-blocking put.
    ;; Since channel internals are not exported, we detect fullness by
    ;; checking channel-length vs capacity from the outside.
    ;; Strategy: use a helper thread with zero timeout.
    ;; This is a polling approximation for bounded channels.
    ;;
    ;; For unbounded channels (the common case), channel-put never blocks
    ;; on capacity (only on close). We can call it safely.
    ;;
    ;; For a proper implementation with bounded channels, we'd need
    ;; channel-try-put exported from channel.sls.
    ;;
    ;; Here we attempt a very short timeout: spawn a thread that does
    ;; channel-put, wait at most ~0s, and check if it completed.
    (let ([done #f]
          [m (make-mutex)]
          [c (make-condition)])
      (guard (exn [#t #f])
        (let ([t (fork-thread
                   (lambda ()
                     (channel-put ch val)
                     (with-mutex m
                       (set! done #t)
                       (condition-signal c))))])
          ;; Poll once after a brief yield
          (sleep (make-time 'time-duration 500000 0))
          (mutex-acquire m)
          (let ([result done])
            (mutex-release m)
            result)))))

  ;;; ========== Runtime select ==========

  ;; Non-blocking: try each recv channel, then each send spec.
  ;; Returns (list result) if handled, #f if nothing ready.
  (define (select-try-nonblocking recv-chs recv-handlers send-specs)
    (let try-recv ([chs recv-chs] [hs recv-handlers])
      (if (null? chs)
        ;; Try sends
        (let try-send ([specs send-specs])
          (if (null? specs)
            #f  ; nothing ready
            (let* ([ch      (car (car specs))]
                   [val     (cadr (car specs))]
                   [handler (caddr (car specs))])
              (if (channel-try-send ch val)
                (list (handler))
                (try-send (cdr specs))))))
        ;; Try next recv
        (let-values ([(v ok) (channel-try-get (car chs))])
          (if ok
            (list ((car hs) v))
            (try-recv (cdr chs) (cdr hs)))))))

  ;; Blocking select with optional timeout (milliseconds or #f).
  ;; Returns the handler's return value.
  (define (select-run-blocking recv-chs recv-handlers send-specs
                               timeout-ms timeout-handler)
    (let* ([deadline (and timeout-ms
                          (let ([t (current-time 'time-monotonic)])
                            (add-duration t
                              (make-time 'time-duration
                                (* (remainder timeout-ms 1000) 1000000)
                                (quotient timeout-ms 1000)))))])
      (let loop ()
        (let ([r (select-try-nonblocking recv-chs recv-handlers send-specs)])
          (cond
            [r (car r)]
            ;; Check timeout
            [(and deadline (time>=? (current-time 'time-monotonic) deadline))
             (if timeout-handler (timeout-handler) (void))]
            ;; Yield and retry
            [else
             (sleep (make-time 'time-duration 500000 0))
             (loop)])))))

  ;; Main runtime entry point
  (define (select-run recv-chs recv-handlers send-specs
                      timeout-ms timeout-handler default-handler)
    (cond
      ;; Non-blocking (has default)
      [default-handler
       (let ([r (select-try-nonblocking recv-chs recv-handlers send-specs)])
         (if r (car r) (default-handler)))]
      ;; Blocking (with optional timeout)
      [else
       (select-run-blocking recv-chs recv-handlers send-specs
                            timeout-ms timeout-handler)]))

  ;;; ========== select macro ==========

  (define-syntax select
    (lambda (stx)
      (syntax-case stx (recv send after default =>)
        [(k clause ...)
         (let ()
           (define recv-clauses '())
           (define send-clauses '())
           (define after-clause #f)
           (define default-clause #f)

           ;; Parse each clause
           (for-each
             (lambda (c)
               (syntax-case c (recv send after default =>)
                 ;; Receive: [(recv ch) => handler]
                 [((recv ch) => handler)
                  (set! recv-clauses (cons (list #'ch #'handler) recv-clauses))]
                 ;; Send: [(send ch val) => handler]
                 [((send ch val) => handler)
                  (set! send-clauses (cons (list #'ch #'val #'handler) send-clauses))]
                 ;; After (timeout in ms): [(after ms) => handler]
                 [((after ms) => handler)
                  (set! after-clause (list #'ms #'handler))]
                 ;; Default (non-blocking): [default => handler]
                 [(default => handler)
                  (set! default-clause #'handler)]))
             (syntax->list #'(clause ...)))

           (set! recv-clauses (reverse recv-clauses))
           (set! send-clauses (reverse send-clauses))

           ;; Emit the runtime call
           (with-syntax
             ([(recv-ch ...) (map car recv-clauses)]
              [(recv-h  ...) (map cadr recv-clauses)]
              [(send-ch ...) (map car send-clauses)]
              [(send-val ...) (map cadr send-clauses)]
              [(send-h  ...) (map caddr send-clauses)])
             (cond
               [default-clause
                (with-syntax ([dflt default-clause])
                  #'(select-run
                      (list recv-ch ...)
                      (list recv-h ...)
                      (list (list send-ch send-val send-h) ...)
                      #f #f dflt))]
               [after-clause
                (with-syntax ([ms      (car after-clause)]
                              [after-h (cadr after-clause)])
                  #'(select-run
                      (list recv-ch ...)
                      (list recv-h ...)
                      (list (list send-ch send-val send-h) ...)
                      ms after-h #f))]
               [else
                #'(select-run
                    (list recv-ch ...)
                    (list recv-h ...)
                    (list (list send-ch send-val send-h) ...)
                    #f #f #f)])))])))

) ;; end library
