#!chezscheme
;;; (std debug replay) — Deterministic record & replay
;;;
;;; Record nondeterministic events (I/O, time, random) during execution,
;;; then replay deterministically.
;;;
;;; API:
;;;   (record-execution thunk)       — run thunk, record all events
;;;   (replay-execution recording thunk) — replay with recorded events
;;;   (recording-events rec)         — get event list
;;;   (recording-result rec)         — get final result
;;;   (make-recording)               — create empty recording
;;;   (recording-add! rec type val)  — add event to recording

(library (std debug replay)
  (export record-execution replay-execution
          recording? recording-events recording-result
          make-recording recording-add!
          replay-random replay-time
          recording-count)

  (import (chezscheme))

  ;; ========== Recording ==========

  (define-record-type recording
    (fields
      (mutable events)       ;; list of (type . value)
      (mutable result)
      (mutable index))       ;; for replay: current position
    (protocol
      (lambda (new)
        (lambda () (new '() #f 0)))))

  (define (recording-add! rec type val)
    (recording-events-set! rec
      (append (recording-events rec) (list (cons type val)))))

  (define (recording-count rec)
    (length (recording-events rec)))

  (define (recording-next! rec expected-type)
    (let ([events (recording-events rec)]
          [idx (recording-index rec)])
      (when (>= idx (length events))
        (error 'replay "recording exhausted"))
      (let ([event (list-ref events idx)])
        (recording-index-set! rec (+ idx 1))
        (unless (eq? (car event) expected-type)
          (error 'replay "event type mismatch" expected-type (car event)))
        (cdr event))))

  ;; ========== Record mode ==========

  (define *current-recording* (make-thread-parameter #f))
  (define *replay-mode* (make-thread-parameter #f))

  (define (record-execution thunk)
    (let ([rec (make-recording)])
      (parameterize ([*current-recording* rec]
                     [*replay-mode* #f])
        (let ([result (thunk)])
          (recording-result-set! rec result)
          rec))))

  ;; ========== Replay mode ==========

  (define (replay-execution rec thunk)
    (recording-index-set! rec 0)
    (parameterize ([*current-recording* rec]
                   [*replay-mode* #t])
      (thunk)))

  ;; ========== Interceptors ==========

  (define (replay-random n)
    (let ([rec (*current-recording*)])
      (cond
        [(not rec) (random n)]
        [(*replay-mode*)
         (recording-next! rec 'random)]
        [else
         (let ([val (random n)])
           (recording-add! rec 'random val)
           val)])))

  (define (replay-time)
    (let ([rec (*current-recording*)])
      (cond
        [(not rec) (current-time)]
        [(*replay-mode*)
         (recording-next! rec 'time)]
        [else
         (let ([val (current-time)])
           (recording-add! rec 'time val)
           val)])))

) ;; end library
