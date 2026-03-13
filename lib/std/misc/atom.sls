#!chezscheme
;;; :std/misc/atom -- Thread-safe mutable reference cells
;;;
;;; Gerbil's atom API: a mutable cell with mutex-protected updates.
;;; Used for background thread state (caches, indices, flags).
;;;
;;; (define counter (atom 0))
;;; (atom-deref counter)          ;; → 0
;;; (atom-reset! counter 42)      ;; set to 42
;;; (atom-swap! counter add1)     ;; atomically apply function → 1
;;; (atom-update! counter + 10)   ;; atomically apply with args → 11

(library (std misc atom)
  (export atom atom? atom-deref atom-reset! atom-swap! atom-update!)

  (import (except (chezscheme) atom?))

  (define-record-type atom-rec
    (fields
      (mutable val)
      (immutable mtx))
    (sealed #t))

  (define (atom initial-value)
    (make-atom-rec initial-value (make-mutex)))

  (define (atom? x) (atom-rec? x))

  (define (atom-deref a)
    (with-mutex (atom-rec-mtx a)
      (atom-rec-val a)))

  (define (atom-reset! a new-val)
    (with-mutex (atom-rec-mtx a)
      (atom-rec-val-set! a new-val)
      new-val))

  (define (atom-swap! a fn)
    ;; Atomically apply fn to current value, store and return result.
    (with-mutex (atom-rec-mtx a)
      (let ([new-val (fn (atom-rec-val a))])
        (atom-rec-val-set! a new-val)
        new-val)))

  (define (atom-update! a fn . args)
    ;; Atomically apply (fn current-val args ...), store and return result.
    (with-mutex (atom-rec-mtx a)
      (let ([new-val (apply fn (atom-rec-val a) args)])
        (atom-rec-val-set! a new-val)
        new-val)))

  ) ;; end library
