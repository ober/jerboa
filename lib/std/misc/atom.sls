#!chezscheme
;;; :std/misc/atom -- Thread-safe mutable reference cells
;;;
;;; Gerbil-style atom API plus Clojure-style aliases for clojure users.
;;;
;;; Native / Gerbil style:
;;;   (define counter (atom 0))
;;;   (atom-deref counter)          ;; → 0
;;;   (atom-reset! counter 42)      ;; set to 42
;;;   (atom-swap! counter add1)     ;; atomically apply function → 1
;;;   (atom-update! counter + 10)   ;; atomically apply with args → 11
;;;
;;; Clojure style (same semantics, familiar names):
;;;   (define counter (atom 0))     ;; same constructor
;;;   (deref counter)                ;; like Clojure's @counter
;;;   (reset! counter 42)            ;; returns 42
;;;   (swap! counter + 1)            ;; (apply + @counter 1) → 43, variadic
;;;   (swap! counter inc)            ;; → 44
;;;   (compare-and-set! counter 44 100)  ;; CAS → #t/#f

(library (std misc atom)
  (export
    ;; ---- Gerbil-style native names ----
    atom atom? atom-deref atom-reset! atom-swap! atom-update!
    ;; ---- Clojure-style aliases ----
    ;; Note: no `atom?` alias — Clojure doesn't expose one either.
    ;; Use atom? (the existing predicate) or shared? from (std misc shared).
    deref reset! swap! compare-and-set!)

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

  ;; =========================================================================
  ;; Clojure-style aliases
  ;;
  ;; Clojure semantics (for context):
  ;;   @a / (deref a)             → read current value
  ;;   (reset! a v)               → set, returns new value
  ;;   (swap! a f args...)        → (apply f @a args), returns new value
  ;;   (compare-and-set! a o n)   → CAS, returns #t if swapped, #f otherwise
  ;; =========================================================================

  (define deref atom-deref)

  (define reset! atom-reset!)

  ;; Clojure's swap! is variadic: (swap! a f x y) calls (f @a x y).
  ;; That's exactly atom-update!'s signature.
  (define swap! atom-update!)

  (define (compare-and-set! a expected new-val)
    ;; Atomically: if current value is equal? to expected, replace
    ;; with new-val and return #t. Otherwise return #f.
    (with-mutex (atom-rec-mtx a)
      (if (equal? (atom-rec-val a) expected)
        (begin
          (atom-rec-val-set! a new-val)
          #t)
        #f)))

  ) ;; end library
