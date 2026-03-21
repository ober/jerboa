#!chezscheme
;;; (std event-source) — Event sourcing with projections
;;;
;;; State as a log of immutable events, with derived projections.
;;;
;;; API:
;;;   (make-event-store)             — create event store
;;;   (emit! store event)            — append event
;;;   (event-log store)              — get all events in order
;;;   (make-projection folder init)  — create projection (fold function + init)
;;;   (project store projection)     — compute projection over all events
;;;   (project-since store proj n)   — project events after index n
;;;   (event-count store)            — number of events
;;;   (snapshot! store proj)         — cache current projection state
;;;   (event-log-since store n)      — events after index n

(library (std event-source)
  (export make-event-store emit! event-log event-count
          make-projection project project-since
          snapshot! event-log-since event-store?
          projection-current)

  (import (chezscheme))

  ;; ========== Event store ==========

  (define-record-type event-store
    (fields
      (mutable events)       ;; vector (growable list for now)
      (mutable count)
      (mutable snapshots))   ;; hashtable: projection -> (index . state)
    (protocol
      (lambda (new)
        (lambda () (new '() 0 (make-eq-hashtable))))))

  (define (emit! store event)
    (let ([ts (event-store-count store)])
      (event-store-events-set! store
        (append (event-store-events store) (list (cons ts event))))
      (event-store-count-set! store (+ ts 1))
      ts))

  (define (event-log store)
    (event-store-events store))

  (define (event-count store)
    (event-store-count store))

  (define (event-log-since store n)
    (let loop ([events (event-store-events store)] [acc '()])
      (cond
        [(null? events) (reverse acc)]
        [(>= (caar events) n)
         (loop (cdr events) (cons (car events) acc))]
        [else (loop (cdr events) acc)])))

  ;; ========== Projections ==========

  (define-record-type projection
    (fields
      (immutable folder)     ;; (state event -> new-state)
      (immutable init))      ;; initial state
    (protocol
      (lambda (new)
        (lambda (folder init)
          (new folder init)))))

  (define (project store proj)
    ;; Check for snapshot
    (let ([snap (hashtable-ref (event-store-snapshots store) proj #f)])
      (if snap
        ;; Resume from snapshot
        (let ([idx (car snap)]
              [state (cdr snap)])
          (fold-events (event-log-since store (+ idx 1))
                       state (projection-folder proj)))
        ;; Full replay
        (fold-events (event-log store)
                     (projection-init proj)
                     (projection-folder proj)))))

  (define (project-since store proj n)
    (fold-events (event-log-since store n)
                 (projection-init proj)
                 (projection-folder proj)))

  (define (fold-events events state folder)
    (let loop ([evts events] [s state])
      (if (null? evts)
        s
        (loop (cdr evts) (folder s (cdar evts))))))

  (define (snapshot! store proj)
    (let ([state (project store proj)]
          [idx (- (event-store-count store) 1)])
      (hashtable-set! (event-store-snapshots store) proj
        (cons idx state))
      state))

  (define (projection-current store proj)
    (project store proj))

) ;; end library
