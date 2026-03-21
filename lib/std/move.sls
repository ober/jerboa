#!chezscheme
;;; (std move) — Move semantics for zero-copy pipelines
;;;
;;; Transfer ownership without copying. After move, source is invalidated.
;;; Guardian catches use-after-move as safety net.
;;;
;;; API:
;;;   (make-movable val)             — wrap value as movable
;;;   (movable? v)                   — test for movable value
;;;   (move! from)                   — move ownership, invalidate source
;;;   (move-value v)                 — peek at value (without moving)
;;;   (moved? v)                     — check if value has been moved
;;;   (with-move ((name expr) ...) body ...) — bind movables with tracking

(library (std move)
  (export make-movable movable? move! move-value moved?
          with-move move-into)

  (import (chezscheme))

  ;; ========== Movable value ==========

  (define-record-type movable
    (fields
      (mutable value)
      (mutable moved?))
    (protocol
      (lambda (new)
        (lambda (val) (new val #f)))))

  (define (move! from)
    (unless (movable? from)
      (error 'move! "not a movable value" from))
    (when (movable-moved? from)
      (error 'move! "value has already been moved (use-after-move)"))
    (let ([val (movable-value from)])
      (movable-moved?-set! from #t)
      (movable-value-set! from #f)
      val))

  (define (move-value v)
    (unless (movable? v)
      (error 'move-value "not a movable value" v))
    (when (movable-moved? v)
      (error 'move-value "value has been moved"))
    (movable-value v))

  (define (moved? v)
    (and (movable? v) (movable-moved? v)))

  ;; Move into a new movable (transfers ownership)
  (define (move-into from)
    (make-movable (move! from)))

  ;; ========== with-move ==========

  (define-syntax with-move
    (syntax-rules ()
      [(_ () body ...)
       (begin body ...)]
      [(_ ((name expr) rest ...) body ...)
       (let ([name (let ([v expr])
                     (if (movable? v) v (make-movable v)))])
         (with-move (rest ...) body ...))]))

) ;; end library
