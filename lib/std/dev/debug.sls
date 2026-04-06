#!chezscheme
;;; (std dev debug) — Time-Travel Debugger
;;;
;;; Records execution trace with step-back capability.
;;; with-recording returns (values result recording) so callers can
;;; inspect history after execution completes.

(library (std dev debug)
  (export
    ;; Execution recording
    with-recording
    call-with-recording
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
    debug-goto
    debug-summary
    debug-print-frame

    ;; Conditional breakpoints
    break-when!
    break-never!
    check-breakpoints!

    ;; Instrumentation macro
    instrument)

  (import (chezscheme))

  ;; ========== Trace Entries ==========

  ;; entry: #(type timestamp depth data)
  ;; type:  'call | 'return | 'error | 'event
  ;; depth: call stack depth at the time of recording

  (define (make-entry type depth data)
    (vector type (time-second (current-time)) depth data))

  (define (entry-type  e) (vector-ref e 0))
  (define (entry-time  e) (vector-ref e 1))
  (define (entry-depth e) (vector-ref e 2))
  (define (entry-data  e) (vector-ref e 3))

  ;; ========== Recording Object ==========

  ;; #(tag buffer write-cursor count max-entries playback-pos call-depth mutex)
  ;;   0    1      2            3     4            5            6          7

  (define (make-recording-obj max-entries)
    (vector 'recording
            (make-vector max-entries #f)  ;; circular buffer
            0    ;; write cursor
            0    ;; count of entries written (capped at max)
            max-entries
            0    ;; playback position
            0    ;; call depth (stored here, not as global)
            (make-mutex)))

  (define (recording? obj)
    (and (vector? obj)
         (= (vector-length obj) 8)
         (eq? (vector-ref obj 0) 'recording)))

  (define (rec-buffer    r) (vector-ref r 1))
  (define (rec-cursor    r) (vector-ref r 2))
  (define (rec-count     r) (vector-ref r 3))
  (define (rec-max       r) (vector-ref r 4))
  (define (rec-pos       r) (vector-ref r 5))
  (define (rec-depth     r) (vector-ref r 6))
  (define (rec-mutex     r) (vector-ref r 7))

  (define (rec-set-cursor! r v) (vector-set! r 2 v))
  (define (rec-set-count!  r v) (vector-set! r 3 v))
  (define (rec-set-pos!    r v) (vector-set! r 5 v))
  (define (rec-set-depth!  r v) (vector-set! r 6 v))

  ;; ========== Current Recording Parameter ==========

  (define *current-recording* (make-parameter #f))

  (define (current-recording) (*current-recording*))

  ;; ========== Recording ==========

  (define (condition->string c)
    (if (condition? c)
      (call-with-string-output-port
        (lambda (p) (display-condition c p)))
      (format #f "~a" c)))

  (define (with-recording thunk . opts)
    ;; Execute thunk with tracing enabled.
    ;; Returns (values result recording) — recording is always returned
    ;; so callers can inspect history even after an exception.
    (let* ([max  (if (null? opts) 1000 (car opts))]
           [rec  (make-recording-obj max)]
           [result #f]
           [exn    #f])
      (parameterize ([*current-recording* rec])
        (guard (e [#t
                   (trace-error! (condition->string e))
                   (set! exn e)])
          (set! result (thunk))))
      (if exn (raise exn) (values result rec))))

  (define (call-with-recording max-entries proc)
    ;; Alternative entry point: (call-with-recording 500 (lambda (rec) ...))
    ;; proc receives the recording object directly, can call trace-* inside.
    (let ([rec (make-recording-obj max-entries)])
      (parameterize ([*current-recording* rec])
        (proc rec))
      rec))

  ;; ========== Appending Entries ==========

  (define (rec-push! entry)
    (let ([r (*current-recording*)])
      (when r
        (with-mutex (rec-mutex r)
          (let ([cur (rec-cursor r)]
                [max (rec-max r)])
            (vector-set! (rec-buffer r) cur entry)
            (rec-set-cursor! r (modulo (+ cur 1) max))
            (rec-set-count!  r (min (+ (rec-count r) 1) max)))))))

  (define (trace-event! description . data)
    (let ([r (*current-recording*)])
      (rec-push! (make-entry 'event (if r (rec-depth r) 0)
                             (cons description data)))))

  (define (trace-call! name args)
    (let ([r (*current-recording*)])
      (when r
        (with-mutex (rec-mutex r)
          (rec-set-depth! r (+ (rec-depth r) 1))))
      (rec-push! (make-entry 'call (if r (rec-depth r) 0)
                             (list name args)))))

  (define (trace-return! name result)
    (let ([r (*current-recording*)])
      (rec-push! (make-entry 'return (if r (rec-depth r) 0)
                             (list name result)))
      (when r
        (with-mutex (rec-mutex r)
          (rec-set-depth! r (max 0 (- (rec-depth r) 1)))))))

  (define (trace-error! msg)
    ;; msg may be a string or condition object
    (let ([r (*current-recording*)])
      (rec-push! (make-entry 'error (if r (rec-depth r) 0)
                             (cond
                               [(string? msg)    msg]
                               [(condition? msg) (condition->string msg)]
                               [else             (format #f "~a" msg)])))))

  ;; ========== Playback ==========

  (define (debug-history . args)
    ;; Return all recorded entries in order.
    ;; Optionally pass a recording object; defaults to current-recording.
    (let ([r (if (null? args) (*current-recording*) (car args))])
      (if (not r) '()
        (with-mutex (rec-mutex r)
          (let ([count  (rec-count r)]
                [cursor (rec-cursor r)]
                [max    (rec-max r)]
                [buf    (rec-buffer r)])
            (let ([start (if (< count max) 0 cursor)])
              (let loop ([i 0] [acc '()])
                (if (= i count)
                  (reverse acc)
                  (let ([idx (modulo (+ start i) max)])
                    (loop (+ i 1) (cons (vector-ref buf idx) acc)))))))))))

  (define (debug-frame-count . args)
    (length (apply debug-history args)))

  (define (debug-current-frame . args)
    (let ([r (if (null? args) (*current-recording*) (car args))])
      (if (not r) #f
        (let ([history (debug-history r)]
              [pos     (rec-pos r)])
          (and (< pos (length history))
               (list-ref history pos))))))

  (define (debug-goto n . args)
    ;; Jump to absolute frame index n.
    (let ([r (if (null? args) (*current-recording*) (car args))])
      (when r
        (let ([max-pos (max 0 (- (debug-frame-count r) 1))])
          (rec-set-pos! r (min max-pos (max 0 n)))))))

  (define (debug-rewind n . args)
    ;; Move n steps backward.
    (let ([r (if (null? args) (*current-recording*) (car args))])
      (when r
        (rec-set-pos! r (max 0 (- (rec-pos r) n))))))

  (define (debug-forward n . args)
    ;; Move n steps forward.
    (let ([r (if (null? args) (*current-recording*) (car args))])
      (when r
        (let ([max-pos (max 0 (- (debug-frame-count r) 1))])
          (rec-set-pos! r (min max-pos (+ (rec-pos r) n)))))))

  (define (debug-step . args)
    ;; Advance one frame and return it.
    (apply debug-forward (cons 1 args))
    (apply debug-current-frame args))

  (define (debug-locals . args)
    ;; Return local bindings at current frame (call entry args).
    (let ([frame (apply debug-current-frame args)])
      (if (not frame) '()
        (let ([data (entry-data frame)])
          (case (entry-type frame)
            [(call)   (if (and (pair? data) (pair? (cdr data))) (cadr data) '())]
            [(return) (list (cons 'result (if (pair? data) (cadr data) data)))]
            [(event)  (if (pair? data) (cdr data) '())]
            [else     '()])))))

  (define (debug-inspect sym . args)
    ;; Find most recent value of sym in history up to current pos.
    (let ([r (if (null? args) (*current-recording*) (car args))])
      (if (not r) #f
        (let* ([history (debug-history r)]
               [pos     (rec-pos r)]
               [window  (list-head history (min pos (length history)))])
          (let loop ([entries (reverse window)])
            (if (null? entries) #f
              (let ([e (car entries)])
                (and (eq? (entry-type e) 'call)
                     (pair? (entry-data e))
                     (let ([args-alist (if (and (pair? (entry-data e))
                                               (pair? (cdr (entry-data e))))
                                        (cadr (entry-data e))
                                        '())])
                       (or (and (list? args-alist) (assq sym args-alist)
                                (cdr (assq sym args-alist)))
                           (loop (cdr entries))))))))))))

  ;; ========== Display Helpers ==========

  (define (debug-print-frame frame . port-arg)
    ;; Pretty-print a single trace entry.
    (let ([port (if (null? port-arg) (current-output-port) (car port-arg))])
      (when frame
        (let ([type  (entry-type frame)]
              [depth (entry-depth frame)]
              [data  (entry-data frame)])
          (let ([indent (make-string (* depth 2) #\space)])
            (case type
              [(call)
               (let ([name (if (pair? data) (car data) data)]
                     [args (if (and (pair? data) (pair? (cdr data))) (cadr data) '())])
                 (format port "~a→ ~a ~a~n" indent name args))]
              [(return)
               (let ([name   (if (pair? data) (car data) data)]
                     [result (if (and (pair? data) (pair? (cdr data))) (cadr data) data)])
                 (format port "~a← ~a = ~a~n" indent name result))]
              [(error)
               (format port "~a! ERROR: ~a~n" indent data)]
              [(event)
               (let ([desc (if (pair? data) (car data) data)]
                     [rest (if (pair? data) (cdr data) '())])
                 (format port "~a· ~a~a~n" indent desc
                         (if (null? rest) "" (format #f " ~a" rest))))]
              [else
               (format port "~a? ~a: ~a~n" indent type data)]))))))

  (define (debug-summary rec . port-arg)
    ;; Print a summary header and all frames.
    (let ([port   (if (null? port-arg) (current-output-port) (car port-arg))]
          [frames (debug-history rec)])
      (format port "=== debugger: ~a events recorded ===~n" (length frames))
      (let loop ([i 0] [entries frames])
        (when (pair? entries)
          (format port "[~a] " i)
          (debug-print-frame (car entries) port)
          (loop (+ i 1) (cdr entries))))))

  ;; ========== Breakpoints ==========

  (define *breakpoints* (make-eq-hashtable))

  (define (break-when! name predicate)
    (hashtable-set! *breakpoints* name predicate))

  (define (break-never! name)
    (hashtable-delete! *breakpoints* name))

  (define (check-breakpoints! name value)
    (let ([pred (hashtable-ref *breakpoints* name #f)])
      (and pred (guard (exn [#t #f]) (pred value)))))

  ;; ========== Instrumentation Macro ==========

  ;; (instrument (name arg ...) body ...)
  ;; Wraps a function body with trace-call!/trace-return! bookends.
  (define-syntax instrument
    (syntax-rules ()
      [(_ (name arg ...) body ...)
       (define (name arg ...)
         (trace-call! 'name (list (cons 'arg arg) ...))
         (let ([result (begin body ...)])
           (trace-return! 'name result)
           result))]))

  ) ;; end library
