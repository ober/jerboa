#!chezscheme
;;; (std borrow) — Borrow checker for mutable state
;;;
;;; Single-writer/multiple-reader discipline enforced at runtime.
;;; Prevents data races by tracking borrow state.
;;;
;;; API:
;;;   (make-owned val)               — create an owned value
;;;   (owned? v)                     — test for owned value
;;;   (borrow v thunk)               — immutable borrow
;;;   (borrow-mut v thunk)           — mutable borrow (exclusive)
;;;   (owned-ref v)                  — get value (only when not borrowed)
;;;   (owned-set! v val)             — set value (only when not borrowed)
;;;   (consume v)                    — consume the owned value

(library (std borrow)
  (export make-owned owned? borrow borrow-mut
          owned-ref owned-set! consume owned-consumed?
          borrow-count)

  (import (chezscheme))

  ;; ========== Owned value ==========
  ;; State: idle | borrowed(n) | borrowed-mut | consumed

  (define-record-type owned
    (fields
      (mutable value)
      (mutable borrow-state)   ;; 'idle | ('shared . count) | 'exclusive | 'consumed
      (immutable mutex))
    (protocol
      (lambda (new)
        (lambda (val) (new val 'idle (make-mutex))))))

  (define (owned-consumed? v)
    (eq? (owned-borrow-state v) 'consumed))

  (define (borrow-count v)
    (let ([state (owned-borrow-state v)])
      (cond
        [(eq? state 'idle) 0]
        [(and (pair? state) (eq? (car state) 'shared)) (cdr state)]
        [(eq? state 'exclusive) 1]
        [else 0])))

  (define (check-not-consumed who v)
    (when (eq? (owned-borrow-state v) 'consumed)
      (error who "owned value has been consumed")))

  ;; ========== Borrow (shared/immutable) ==========

  (define (borrow v thunk)
    (with-mutex (owned-mutex v)
      (check-not-consumed 'borrow v)
      (let ([state (owned-borrow-state v)])
        (when (eq? state 'exclusive)
          (error 'borrow "cannot borrow: exclusively borrowed"))
        (if (and (pair? state) (eq? (car state) 'shared))
          (owned-borrow-state-set! v (cons 'shared (+ (cdr state) 1)))
          (owned-borrow-state-set! v (cons 'shared 1)))))
    (dynamic-wind
      void
      (lambda () (thunk (owned-value v)))
      (lambda ()
        (with-mutex (owned-mutex v)
          (let ([state (owned-borrow-state v)])
            (when (and (pair? state) (eq? (car state) 'shared))
              (if (<= (cdr state) 1)
                (owned-borrow-state-set! v 'idle)
                (owned-borrow-state-set! v (cons 'shared (- (cdr state) 1))))))))))

  ;; ========== Borrow-mut (exclusive/mutable) ==========

  (define (borrow-mut v thunk)
    (with-mutex (owned-mutex v)
      (check-not-consumed 'borrow-mut v)
      (let ([state (owned-borrow-state v)])
        (unless (eq? state 'idle)
          (error 'borrow-mut "cannot borrow mutably: already borrowed" state))
        (owned-borrow-state-set! v 'exclusive)))
    (dynamic-wind
      void
      (lambda ()
        (let ([result (thunk (owned-value v))])
          ;; If thunk returns a new value, update
          result))
      (lambda ()
        (with-mutex (owned-mutex v)
          (owned-borrow-state-set! v 'idle)))))

  ;; ========== Direct access ==========

  (define (owned-ref v)
    (with-mutex (owned-mutex v)
      (check-not-consumed 'owned-ref v)
      (unless (eq? (owned-borrow-state v) 'idle)
        (error 'owned-ref "cannot access: currently borrowed"))
      (owned-value v)))

  (define (owned-set! v val)
    (with-mutex (owned-mutex v)
      (check-not-consumed 'owned-set! v)
      (let ([state (owned-borrow-state v)])
        (unless (or (eq? state 'idle) (eq? state 'exclusive))
          (error 'owned-set! "cannot mutate: shared borrow active")))
      (owned-value-set! v val)))

  ;; ========== Consume ==========

  (define (consume v)
    (with-mutex (owned-mutex v)
      (check-not-consumed 'consume v)
      (unless (eq? (owned-borrow-state v) 'idle)
        (error 'consume "cannot consume: currently borrowed"))
      (let ([val (owned-value v)])
        (owned-borrow-state-set! v 'consumed)
        (owned-value-set! v #f)
        val)))

) ;; end library
