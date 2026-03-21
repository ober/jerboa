#!chezscheme
;;; (std event) — First-class synchronizable events
;;;
;;; Gerbil-compatible event system for concurrent programming.
;;; Events are first-class values that can be combined and synchronized.
;;;
;;; (sync (choice (timeout-evt 1.0)
;;;               (channel-recv-evt ch)))

(library (std event)
  (export make-event event?
          sync select
          choice wrap handle
          always-evt never-evt
          timeout-evt
          guard-evt)

  (import (chezscheme))

  ;; An event is a record wrapping a poll procedure and a sync procedure.
  ;; poll: () → result/#f  (non-blocking check)
  ;; sync: () → result     (blocking wait)
  (define-record-type event
    (fields poll-proc sync-proc))

  ;; always-evt: immediately ready with a value
  (define (always-evt val)
    (make-event
     (lambda () val)
     (lambda () val)))

  ;; never-evt: never ready
  (define never-evt
    (make-event
     (lambda () #f)
     (lambda ()
       ;; Block forever (practically)
       (let loop ()
         (sleep (make-time 'time-duration 0 3600))
         (loop)))))

  ;; timeout-evt: ready after N seconds
  (define (timeout-evt seconds)
    (let ([deadline (+ (current-time-ms) (inexact->exact (round (* seconds 1000))))])
      (make-event
       ;; poll
       (lambda ()
         (if (>= (current-time-ms) deadline)
             (void)
             #f))
       ;; sync
       (lambda ()
         (let loop ()
           (let ([remaining (- deadline (current-time-ms))])
             (if (<= remaining 0)
                 (void)
                 (begin
                   (sleep (make-time 'time-duration
                                     (* (min remaining 100) 1000000)
                                     0))
                   (loop)))))))))

  (define (current-time-ms)
    (let ([t (current-time)])
      (+ (* (time-second t) 1000)
         (quotient (time-nanosecond t) 1000000))))

  ;; choice: combine events — first ready wins
  (define (choice . evts)
    (make-event
     ;; poll: try each
     (lambda ()
       (let loop ([es evts])
         (if (null? es)
             #f
             (let ([r ((event-poll-proc (car es)))])
               (if r r (loop (cdr es)))))))
     ;; sync: spin-poll with backoff
     (lambda ()
       (let loop ([backoff 1])
         (let try ([es evts])
           (if (null? es)
               (begin
                 (sleep (make-time 'time-duration
                                   (* (min backoff 50) 1000000)
                                   0))
                 (loop (min (* backoff 2) 50)))
               (let ([r ((event-poll-proc (car es)))])
                 (if r r (try (cdr es))))))))))

  ;; wrap: transform event result
  (define (wrap evt proc)
    (make-event
     (lambda ()
       (let ([r ((event-poll-proc evt))])
         (and r (proc r))))
     (lambda ()
       (proc ((event-sync-proc evt))))))

  ;; handle: like wrap but proc receives the event value
  (define (handle evt proc)
    (wrap evt proc))

  ;; guard-evt: lazily construct event
  (define (guard-evt thunk)
    (make-event
     (lambda ()
       (let ([evt (thunk)])
         ((event-poll-proc evt))))
     (lambda ()
       (let ([evt (thunk)])
         ((event-sync-proc evt))))))

  ;; sync: synchronize on a single event (blocking)
  (define (sync . evts)
    (if (= (length evts) 1)
        ((event-sync-proc (car evts)))
        ((event-sync-proc (apply choice evts)))))

  ;; select: like sync but returns (values index result)
  (define (select . evts)
    (let loop ([backoff 1])
      (let try ([es evts] [idx 0])
        (if (null? es)
            (begin
              (sleep (make-time 'time-duration
                                (* (min backoff 50) 1000000)
                                0))
              (loop (min (* backoff 2) 50)))
            (let ([r ((event-poll-proc (car es)))])
              (if r
                  (values idx r)
                  (try (cdr es) (+ idx 1))))))))

) ;; end library
