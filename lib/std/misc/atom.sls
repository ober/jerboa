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
;;;
;;; Watches (Clojure parity, §4.7)
;;; ------------------------------
;;; `(add-watch! atom key fn)` registers `fn` to run after every
;;; successful reset!/swap!/update!/CAS, with the signature
;;; `(fn key atom old-val new-val)`. Same-key re-add replaces the
;;; previous callback. Callbacks run OUTSIDE the atom's lock, so
;;; they can call back into the atom without deadlock; raised
;;; exceptions are swallowed (a broken watch can't corrupt the atom).
;;;
;;; `(remove-watch! atom key)` removes the watch for `key`. Both
;;; calls return the atom, so they chain.
;;;
;;; Volatiles (Clojure parity, §4.7)
;;; --------------------------------
;;; `volatile!` is a lightweight, SINGLE-THREADED mutable cell for
;;; transient accumulators inside transducers (the `partition-by`
;;; pattern). It has no mutex, no watches, and no CAS. Use when you
;;; know the cell is captured in a closure that cannot be touched
;;; from multiple threads. If you need thread-safety, use `atom`.
;;;
;;;   (define v (volatile! 0))
;;;   (vderef v)                   ;; → 0
;;;   (vreset! v 10)                ;; → 10
;;;   (vswap! v + 5)                ;; → 15
;;;

(library (std misc atom)
  (export
    ;; ---- Gerbil-style native names ----
    atom atom? atom-deref atom-reset! atom-swap! atom-update!
    ;; ---- Clojure-style aliases ----
    ;; Note: no `atom?` alias — Clojure doesn't expose one either.
    ;; Use atom? (the existing predicate) or shared? from (std misc shared).
    deref reset! swap! compare-and-set!
    ;; ---- Watches (§4.7) ----
    add-watch! remove-watch!
    ;; ---- Volatiles (§4.7) ----
    volatile! volatile? vreset! vswap! vderef)

  (import (except (chezscheme) atom?))

  (define-record-type atom-rec
    (fields
      (mutable val)
      (immutable mtx)
      (mutable watches))  ;; alist of (key . (lambda (k atom old new) ...))
    (sealed #t))

  (define (atom initial-value)
    (make-atom-rec initial-value (make-mutex) '()))

  (define (atom? x) (atom-rec? x))

  (define (atom-deref a)
    (with-mutex (atom-rec-mtx a)
      (atom-rec-val a)))

  ;; Fire watches OUTSIDE the atom's mutex so a watch can call back
  ;; into the atom without deadlock. Exceptions are swallowed so a
  ;; broken watch cannot corrupt the atom's state.
  (define (%fire-watches! a old new watches)
    (for-each
      (lambda (w)
        (guard (_ [else (void)])
          ((cdr w) (car w) a old new)))
      watches))

  (define (atom-reset! a new-val)
    (let-values ([(old watches)
                  (with-mutex (atom-rec-mtx a)
                    (let ([o (atom-rec-val a)])
                      (atom-rec-val-set! a new-val)
                      (values o (atom-rec-watches a))))])
      (%fire-watches! a old new-val watches)
      new-val))

  (define (atom-swap! a fn)
    ;; Atomically apply fn to current value, store and return result.
    (let-values ([(old new watches)
                  (with-mutex (atom-rec-mtx a)
                    (let* ([o (atom-rec-val a)]
                           [n (fn o)])
                      (atom-rec-val-set! a n)
                      (values o n (atom-rec-watches a))))])
      (%fire-watches! a old new watches)
      new))

  (define (atom-update! a fn . args)
    ;; Atomically apply (fn current-val args ...), store and return result.
    (let-values ([(old new watches)
                  (with-mutex (atom-rec-mtx a)
                    (let* ([o (atom-rec-val a)]
                           [n (apply fn o args)])
                      (atom-rec-val-set! a n)
                      (values o n (atom-rec-watches a))))])
      (%fire-watches! a old new watches)
      new))

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
    ;; with new-val and return #t. Otherwise return #f. Fires watches
    ;; ONLY on successful swap.
    (let-values ([(swapped? old watches)
                  (with-mutex (atom-rec-mtx a)
                    (cond
                      [(equal? (atom-rec-val a) expected)
                       (let ([o (atom-rec-val a)])
                         (atom-rec-val-set! a new-val)
                         (values #t o (atom-rec-watches a)))]
                      [else (values #f #f '())]))])
      (when swapped?
        (%fire-watches! a old new-val watches))
      swapped?))

  ;; =========================================================================
  ;; Watches (§4.7)
  ;; =========================================================================

  ;; Register `fn` under `key`. Same-key re-add replaces the previous
  ;; callback (matches Clojure). Returns the atom so calls chain.
  (define (add-watch! a key fn)
    (with-mutex (atom-rec-mtx a)
      (atom-rec-watches-set! a
        (cons (cons key fn)
              (remp (lambda (w) (equal? (car w) key))
                    (atom-rec-watches a)))))
    a)

  ;; Remove the watch registered under `key`. Idempotent: removing a
  ;; key that isn't present is a no-op. Returns the atom.
  (define (remove-watch! a key)
    (with-mutex (atom-rec-mtx a)
      (atom-rec-watches-set! a
        (remp (lambda (w) (equal? (car w) key)) (atom-rec-watches a))))
    a)

  ;; =========================================================================
  ;; Volatiles (§4.7) — single-threaded transient cells for transducers
  ;; =========================================================================

  (define-record-type volatile-rec
    (fields (mutable val))
    (sealed #t))

  (define (volatile! v) (make-volatile-rec v))

  (define (volatile? x) (volatile-rec? x))

  (define (vderef vol) (volatile-rec-val vol))

  (define (vreset! vol v)
    (volatile-rec-val-set! vol v)
    v)

  (define (vswap! vol fn . args)
    (let ([new (apply fn (volatile-rec-val vol) args)])
      (volatile-rec-val-set! vol new)
      new))

  ) ;; end library
