#!chezscheme
;;; (std misc shared) -- Thread-safe shared mutable state
;;;
;;; A shared cell wraps a value with a mutex for thread-safe access.
;;; Similar to atom but with compare-and-swap semantics.
;;;
;;; Usage:
;;;   (import (std misc shared))
;;;   (define s (make-shared 0))
;;;   (shared-ref s)                   ;; => 0
;;;   (shared-set! s 42)               ;; set to 42
;;;   (shared-update! s add1)          ;; atomically increment => 43
;;;   (shared-cas! s 43 100)           ;; compare-and-swap => #t
;;;   (shared-ref s)                   ;; => 100
;;;   (shared-swap! s (lambda (x) (* x 2)))  ;; => 200 (old value 100)

(library (std misc shared)
  (export
    make-shared
    shared?
    shared-ref
    shared-set!
    shared-update!
    shared-cas!
    shared-swap!)

  (import (chezscheme))

  (define-record-type shared-rec
    (fields (mutable val)
            (immutable mtx))
    (sealed #t))

  (define (make-shared initial-value)
    (make-shared-rec initial-value (make-mutex)))

  (define (shared? x) (shared-rec? x))

  (define (shared-ref s)
    ;; Acquire lock, read value, release lock.
    (with-mutex (shared-rec-mtx s)
      (shared-rec-val s)))

  (define (shared-set! s new-val)
    ;; Acquire lock, write value, release lock.
    (with-mutex (shared-rec-mtx s)
      (shared-rec-val-set! s new-val)
      (void)))

  (define (shared-update! s proc . args)
    ;; Acquire lock, apply proc to current value (plus extra args),
    ;; store result, release lock. Returns the new value.
    (with-mutex (shared-rec-mtx s)
      (let ([new-val (apply proc (shared-rec-val s) args)])
        (shared-rec-val-set! s new-val)
        new-val)))

  (define (shared-cas! s expected new-val)
    ;; Compare-and-swap: if current value is equal? to expected,
    ;; set to new-val and return #t; otherwise return #f.
    (with-mutex (shared-rec-mtx s)
      (if (equal? (shared-rec-val s) expected)
        (begin
          (shared-rec-val-set! s new-val)
          #t)
        #f)))

  (define (shared-swap! s proc)
    ;; Atomically apply proc to current value, store and return
    ;; the OLD value (pre-swap).
    (with-mutex (shared-rec-mtx s)
      (let* ([old (shared-rec-val s)]
             [new-val (proc old)])
        (shared-rec-val-set! s new-val)
        old)))

) ;; end library
