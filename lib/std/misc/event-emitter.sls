#!chezscheme
;;; (std misc event-emitter) -- Pub/Sub Event System
;;;
;;; Node.js-style EventEmitter for decoupled architecture.
;;;
;;; Usage:
;;;   (import (std misc event-emitter))
;;;   (define ee (make-event-emitter))
;;;   (on ee 'data (lambda (x) (printf "got ~a~n" x)))
;;;   (once ee 'done (lambda () (printf "finished~n")))
;;;   (emit ee 'data 42)
;;;   (emit ee 'done)
;;;   (off ee 'data)

(library (std misc event-emitter)
  (export
    make-event-emitter
    event-emitter?
    on
    once
    off
    off-all
    emit
    listeners
    listener-count
    event-names)

  (import (chezscheme))

  (define-record-type event-emitter-rec
    (fields (mutable handlers))  ;; hashtable: event-name -> list of (handler . once?)
    (protocol (lambda (new)
      (lambda () (new (make-eq-hashtable))))))

  (define (make-event-emitter) (make-event-emitter-rec))
  (define (event-emitter? x) (event-emitter-rec? x))

  (define (on ee event handler)
    ;; Register a persistent listener
    (let* ([ht (event-emitter-rec-handlers ee)]
           [existing (hashtable-ref ht event '())])
      (hashtable-set! ht event (append existing (list (cons handler #f))))))

  (define (once ee event handler)
    ;; Register a one-time listener
    (let* ([ht (event-emitter-rec-handlers ee)]
           [existing (hashtable-ref ht event '())])
      (hashtable-set! ht event (append existing (list (cons handler #t))))))

  (define off
    (case-lambda
      [(ee event)
       ;; Remove all listeners for event
       (hashtable-delete! (event-emitter-rec-handlers ee) event)]
      [(ee event handler)
       ;; Remove specific handler
       (let* ([ht (event-emitter-rec-handlers ee)]
              [existing (hashtable-ref ht event '())]
              [filtered (filter (lambda (pair) (not (eq? (car pair) handler)))
                               existing)])
         (if (null? filtered)
           (hashtable-delete! ht event)
           (hashtable-set! ht event filtered)))]))

  (define (off-all ee)
    ;; Remove all listeners
    (hashtable-clear! (event-emitter-rec-handlers ee)))

  (define (emit ee event . args)
    ;; Fire all handlers for event, remove once handlers
    (let* ([ht (event-emitter-rec-handlers ee)]
           [handlers (hashtable-ref ht event '())]
           [remaining '()])
      (for-each
        (lambda (pair)
          (guard (exn [#t (void)])  ;; don't let one handler crash others
            (apply (car pair) args))
          (unless (cdr pair)  ;; not a once handler
            (set! remaining (cons pair remaining))))
        handlers)
      (if (null? remaining)
        (hashtable-delete! ht event)
        (hashtable-set! ht event (reverse remaining)))))

  (define (listeners ee event)
    ;; Return list of handler procedures for event
    (map car (hashtable-ref (event-emitter-rec-handlers ee) event '())))

  (define (listener-count ee event)
    (length (hashtable-ref (event-emitter-rec-handlers ee) event '())))

  (define (event-names ee)
    ;; Return list of all event names with handlers
    (let-values ([(keys vals) (hashtable-entries (event-emitter-rec-handlers ee))])
      (vector->list keys)))

) ;; end library
