#!chezscheme
;;; (std debug timetravel) — Time-Travel Debugger with Replay
;;;
;;; Records program events (calls, returns, state changes, snapshots)
;;; in a mutex-protected recorder so execution can be replayed and inspected.

(library (std debug timetravel)
  (export
    ;; Recording
    make-recorder
    recorder?
    recorder-start!
    recorder-stop!
    recorder-events
    recorder-event-count
    recorder-reset!
    ;; Event logging
    record-event!
    record-call!
    record-return!
    record-state!
    ;; Replay
    replay-events
    replay-to-step
    ;; Event structure
    make-event
    event?
    event-tag
    event-data
    event-timestamp
    event-step
    ;; Instrumentation macro
    with-recording
    trace-fn
    ;; Inspection
    events-between
    events-by-tag
    event-diff
    ;; Snapshot/restore
    record-snapshot!
    find-snapshot
    snapshots-for)

  (import (chezscheme))

  ;; ========== Event ==========
  ;; Immutable record: tag, data, timestamp (real-time ms), step (monotonic counter)

  (define-record-type %event
    (fields tag data timestamp step)
    (protocol
      (lambda (new)
        (lambda (tag data timestamp step)
          (new tag data timestamp step)))))

  (define (make-event tag data timestamp step)
    (make-%event tag data timestamp step))

  (define (event? x) (%event? x))
  (define (event-tag       e) (%event-tag       e))
  (define (event-data      e) (%event-data      e))
  (define (event-timestamp e) (%event-timestamp e))
  (define (event-step      e) (%event-step      e))

  ;; ========== Current wall-clock time in milliseconds ==========

  (define (now-ms)
    (let ([t (current-time 'time-utc)])
      (+ (* (time-second t) 1000)
         (quotient (time-nanosecond t) 1000000))))

  ;; ========== Recorder ==========
  ;; Wraps a mutex-protected list of events (newest-first) + step counter + running? flag

  (define-record-type %recorder
    (fields
      (mutable events-rev)   ;; events in reverse order (newest first)
      (mutable step-counter) ;; monotonic step counter
      (mutable running?))    ;; #t while recording
    (protocol
      (lambda (new)
        (lambda ()
          (new '() 0 #f)))))

  (define *recorder-mutex-table* (make-eq-hashtable))

  (define (recorder-mutex rec)
    (let ([m (hashtable-ref *recorder-mutex-table* rec #f)])
      (or m
          (let ([new-m (make-mutex)])
            (hashtable-set! *recorder-mutex-table* rec new-m)
            new-m))))

  (define (make-recorder)
    (let ([r (make-%recorder)])
      ;; Pre-allocate mutex
      (recorder-mutex r)
      r))

  (define (recorder? x) (%recorder? x))

  (define (recorder-start! rec)
    (with-mutex (recorder-mutex rec)
      (%recorder-running?-set! rec #t)))

  (define (recorder-stop! rec)
    (with-mutex (recorder-mutex rec)
      (%recorder-running?-set! rec #f)))

  (define (recorder-reset! rec)
    (with-mutex (recorder-mutex rec)
      (%recorder-events-rev-set! rec '())
      (%recorder-step-counter-set! rec 0)
      (%recorder-running?-set! rec #f)))

  ;; Returns events in replay order (oldest first)
  (define (recorder-events rec)
    (with-mutex (recorder-mutex rec)
      (reverse (%recorder-events-rev rec))))

  (define (recorder-event-count rec)
    (with-mutex (recorder-mutex rec)
      (length (%recorder-events-rev rec))))

  ;; ========== Event Logging ==========

  (define (record-event! rec tag data)
    (with-mutex (recorder-mutex rec)
      (when (%recorder-running? rec)
        (let* ([step (+ (%recorder-step-counter rec) 1)]
               [ts   (now-ms)]
               [ev   (make-%event tag data ts step)])
          (%recorder-step-counter-set! rec step)
          (%recorder-events-rev-set! rec
            (cons ev (%recorder-events-rev rec)))))))

  (define (record-call! rec fn-name args)
    (record-event! rec 'call (list fn-name args)))

  (define (record-return! rec fn-name result)
    (record-event! rec 'return (list fn-name result)))

  (define (record-state! rec label value)
    (record-event! rec 'state (list label value)))

  (define (record-snapshot! rec label value)
    (record-event! rec 'snapshot (list label value)))

  ;; ========== Replay ==========

  (define (replay-events events handler-proc)
    (for-each handler-proc events))

  ;; Replay up to step n; return state value from the last record-state! event seen
  (define (replay-to-step events n)
    (let loop ([evs events] [last-state #f])
      (cond
        [(null? evs) last-state]
        [else
         (let ([ev (car evs)])
           (if (> (%event-step ev) n)
             last-state
             (let ([new-state
                    (if (eq? (%event-tag ev) 'state)
                      (cadr (%event-data ev))
                      last-state)])
               (loop (cdr evs) new-state))))])))

  ;; ========== Instrumentation ==========

  ;; (with-recording rec body ...) macro — starts before body, stops after (dynamic-wind)
  (define-syntax with-recording
    (syntax-rules ()
      [(_ rec body ...)
       (dynamic-wind
         (lambda () (recorder-start! rec))
         (lambda () body ...)
         (lambda () (recorder-stop! rec)))]))

  ;; trace-fn — wraps fn to auto-record calls and returns
  (define (trace-fn rec fn)
    (lambda args
      (record-call! rec fn args)
      (let ([result (apply fn args)])
        (record-return! rec fn result)
        result)))

  ;; ========== Inspection ==========

  (define (events-between events t1 t2)
    (filter (lambda (ev)
              (and (>= (%event-timestamp ev) t1)
                   (<= (%event-timestamp ev) t2)))
            events))

  (define (events-by-tag events tag)
    (filter (lambda (ev) (equal? (%event-tag ev) tag)) events))

  ;; Returns a description of the difference between two events
  (define (event-diff e1 e2)
    (let ([same-tag?  (equal? (event-tag e1) (event-tag e2))]
          [same-data? (equal? (event-data e1) (event-data e2))]
          [step-diff  (- (event-step e2) (event-step e1))])
      (cond
        [(and same-tag? same-data?)
         (list 'identical 'step-delta step-diff)]
        [same-tag?
         (list 'same-tag (event-tag e1) 'data-changed
               (list 'from (event-data e1) 'to (event-data e2)))]
        [else
         (list 'tag-changed
               (list 'from (event-tag e1) 'to (event-tag e2))
               'data-changed
               (list 'from (event-data e1) 'to (event-data e2)))])))

  ;; ========== Snapshot helpers ==========

  (define (find-snapshot events label)
    ;; Most recent snapshot with matching label (events are in replay order = oldest first)
    ;; We scan all and keep the last match
    (let loop ([evs events] [result #f])
      (if (null? evs)
        result
        (let ([ev (car evs)])
          (loop (cdr evs)
                (if (and (eq? (event-tag ev) 'snapshot)
                         (equal? (car (event-data ev)) label))
                  (cadr (event-data ev))
                  result))))))

  (define (snapshots-for events label)
    ;; All snapshots with matching label, in replay order
    (filter-map
      (lambda (ev)
        (and (eq? (event-tag ev) 'snapshot)
             (equal? (car (event-data ev)) label)
             (cadr (event-data ev))))
      events))

  ;; filter-map helper
  (define (filter-map f lst)
    (let loop ([lst lst] [acc '()])
      (if (null? lst)
        (reverse acc)
        (let ([v (f (car lst))])
          (loop (cdr lst) (if v (cons v acc) acc))))))

) ;; end library
