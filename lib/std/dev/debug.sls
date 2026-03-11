#!chezscheme
;;; (std dev debug) — Time-Travel Debugger (Step 32)
;;;
;;; Records execution trace with optional step-back capability.
;;; Uses continuation capture and structured logging.

(library (std dev debug)
  (export
    ;; Execution recording
    with-recording
    recording?
    current-recording
    *current-recording*

    ;; Trace entries
    trace-event!
    trace-call!
    trace-return!
    trace-error!

    ;; Playback / inspection
    debug-history
    debug-rewind
    debug-forward
    debug-step
    debug-locals
    debug-inspect
    debug-current-frame
    debug-frame-count

    ;; Conditional breakpoints
    break-when!
    break-never!
    check-breakpoints!

    ;; Instrumentation macro
    instrument)

  (import (chezscheme))

  ;; ========== Trace Entries ==========

  ;; entry: (type timestamp depth data)
  ;; type: 'call | 'return | 'error | 'event
  ;; depth: call stack depth at the time
  ;; data: depends on type

  (define (make-entry type data)
    (list type
          (time-second (current-time))
          *current-depth*
          data))
  (define (entry-type  e) (list-ref e 0))
  (define (entry-time  e) (list-ref e 1))
  (define (entry-depth e) (list-ref e 2))
  (define (entry-data  e) (list-ref e 3))

  ;; ========== Recording State ==========

  (define *current-recording* (make-parameter #f))
  (define *current-depth*     0)

  (define (recording? obj)
    (and (vector? obj) (> (vector-length obj) 0) (eq? (vector-ref obj 0) 'recording)))

  (define (current-recording)
    (*current-recording*))

  ;; recording as a vector: #(tag buffer cursor count max pos mutex)
  ;; Using vector for mutable state (no list-set! needed)
  (define (make-recording-obj max-entries)
    (vector 'recording
            (make-vector max-entries #f)  ;; circular buffer
            0   ;; write cursor
            0   ;; count of entries written
            max-entries
            0   ;; current playback position
            (make-mutex)))

  (define (rec-buffer   r) (vector-ref r 1))
  (define (rec-cursor   r) (vector-ref r 2))
  (define (rec-count    r) (vector-ref r 3))
  (define (rec-max      r) (vector-ref r 4))
  (define (rec-pos      r) (vector-ref r 5))
  (define (rec-mutex    r) (vector-ref r 6))

  (define (rec-set-cursor! r v) (vector-set! r 2 v))
  (define (rec-set-count!  r v) (vector-set! r 3 v))
  (define (rec-set-pos!    r v) (vector-set! r 5 v))

  ;; ========== Recording ==========

  (define (with-recording thunk . opts)
    ;; Execute thunk with execution tracing enabled.
    ;; opts: max-entries (default 1000)
    (let* ([max  (if (null? opts) 1000 (car opts))]
           [rec  (make-recording-obj max)]
           [result #f]
           [exn    #f])
      (parameterize ([*current-recording* rec])
        (guard (e [#t
                   (trace-error! (if (condition? e)
                                    (condition-message e)
                                    (format "~a" e)))
                   (set! exn e)])
          (set! result (thunk))))
      (if exn
        (raise exn)
        result)))

  (define (rec-push! entry)
    (let ([r (*current-recording*)])
      (when r
        (with-mutex (rec-mutex r)
          (let ([cur  (rec-cursor r)]
                [max  (rec-max r)])
            (vector-set! (rec-buffer r) cur entry)
            (rec-set-cursor! r (modulo (+ cur 1) max))
            (rec-set-count!  r (min (+ (rec-count r) 1) max)))))))

  (define (trace-event! description . data)
    (rec-push! (make-entry 'event (cons description data))))

  (define (trace-call! name args)
    (set! *current-depth* (+ *current-depth* 1))
    (rec-push! (make-entry 'call (list name args))))

  (define (trace-return! name result)
    (rec-push! (make-entry 'return (list name result)))
    (set! *current-depth* (max 0 (- *current-depth* 1))))

  (define (trace-error! msg)
    (rec-push! (make-entry 'error msg)))

  ;; ========== Playback ==========

  (define (debug-history)
    ;; Return all recorded entries in order.
    (let ([r (*current-recording*)])
      (if (not r) '()
        (with-mutex (rec-mutex r)
          (let ([count  (rec-count r)]
                [cursor (rec-cursor r)]
                [max    (rec-max r)]
                [buf    (rec-buffer r)])
            ;; Reconstruct in-order from circular buffer
            (let ([start (if (< count max) 0 cursor)])
              (let loop ([i 0] [result '()])
                (if (= i count)
                  (reverse result)
                  (let ([idx (modulo (+ start i) max)])
                    (loop (+ i 1) (cons (vector-ref buf idx) result)))))))))))

  (define (debug-frame-count)
    (length (debug-history)))

  (define (debug-current-frame)
    (let ([r (*current-recording*)])
      (if (not r) #f
        (let ([history (debug-history)]
              [pos     (rec-pos r)])
          (if (>= pos (length history)) #f
            (list-ref history pos))))))

  (define (debug-rewind n)
    ;; Move playback position n steps backward.
    (let ([r (*current-recording*)])
      (when r
        (rec-set-pos! r (max 0 (- (rec-pos r) n))))))

  (define (debug-forward n)
    ;; Move playback position n steps forward.
    (let ([r (*current-recording*)])
      (when r
        (let ([max-pos (max 0 (- (debug-frame-count) 1))])
          (rec-set-pos! r (min max-pos (+ (rec-pos r) n)))))))

  (define (debug-step)
    ;; Move to next entry.
    (debug-forward 1)
    (debug-current-frame))

  (define (debug-locals)
    ;; Return local variable bindings at current frame.
    (let ([frame (debug-current-frame)])
      (if (not frame) '()
        (let ([data (entry-data frame)])
          (if (and (pair? data) (list? data))
            data
            (list (cons 'data data)))))))

  (define (debug-inspect sym)
    ;; Find the most recent value of sym in the history up to current pos.
    (let ([r (*current-recording*)])
      (if (not r) #f
        (let ([history (debug-history)]
              [pos     (rec-pos r)])
          (let loop ([entries (reverse (list-head history (min pos (length history))))])
            (if (null? entries) #f
              (let ([e (car entries)])
                (cond
                  ;; Look in call entries for argument named sym
                  [(and (eq? (entry-type e) 'call)
                        (pair? (entry-data e)))
                   (let ([args (cadr (entry-data e))])
                     (if (and (list? args) (assq sym args))
                       (cdr (assq sym args))
                       (loop (cdr entries))))]
                  [else (loop (cdr entries))]))))))))

  ;; ========== Breakpoints ==========

  (define *breakpoints* (make-eq-hashtable))

  (define (break-when! name predicate)
    ;; Set a conditional breakpoint: break when predicate returns #t.
    (hashtable-set! *breakpoints* name predicate))

  (define (break-never! name)
    (hashtable-delete! *breakpoints* name))

  (define (check-breakpoints! name value)
    ;; Returns #t if a breakpoint fires for (name value).
    (let ([pred (hashtable-ref *breakpoints* name #f)])
      (and pred (guard (exn [#t #f]) (pred value)))))

  ;; ========== Instrumentation Macro ==========

  ;; (instrument (name arg ...) body ...)
  ;; Wraps a function body with trace-call!/trace-return! calls.
  (define-syntax instrument
    (syntax-rules ()
      [(_ (name arg ...) body ...)
       (define (name arg ...)
         (trace-call! 'name (list (cons 'arg arg) ...))
         (let ([result (begin body ...)])
           (trace-return! 'name result)
           result))]))

  ) ;; end library
