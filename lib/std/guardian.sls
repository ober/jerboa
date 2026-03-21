#!chezscheme
;;; (std guardian) — GC Guardian for resource cleanup
;;;
;;; Wraps Chez's guardian system for GC-triggered finalization.
;;; Register objects for cleanup; poll guardians to reclaim resources.

(library (std guardian)
  (export make-guardian guardian-register! guardian-drain!
          with-guardian)

  (import (chezscheme))

  ;; Re-export Chez's make-guardian (returns a guardian procedure)
  ;; Guardian usage:
  ;;   (define g (make-guardian))
  ;;   (g obj)          ; register obj
  ;;   (g)              ; retrieve one collected obj, or #f

  ;; Register an object with a guardian
  (define (guardian-register! guardian obj)
    (guardian obj))

  ;; Drain all collected objects from a guardian, call finalizer on each
  (define (guardian-drain! guardian finalizer)
    (let loop ()
      (let ([obj (guardian)])
        (when obj
          (finalizer obj)
          (loop)))))

  ;; Create a guardian, register obj, and ensure cleanup runs on GC
  ;; Returns the object so it can be used
  (define (with-guardian obj finalizer)
    (let ([g (make-guardian)])
      (g obj)
      ;; Register a collect-request handler to drain
      (collect-request-handler
        (let ([old (collect-request-handler)])
          (lambda ()
            (old)
            (guardian-drain! g finalizer))))
      obj))

) ;; end library
