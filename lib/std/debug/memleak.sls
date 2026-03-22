#!chezscheme
;;; (std debug memleak) — Memory leak detection via guardians
;;;
;;; Uses Chez Scheme's guardian mechanism to track object lifetimes.
;;; Objects registered with `track-allocation` are monitored; after GC,
;;; `report-leaks` shows which tracked objects are still live (i.e., not
;;; collected by the guardian, meaning something still references them).

(library (std debug memleak)
  (export track-allocation untrack-allocation report-leaks
          with-leak-check leak-tracker-reset! leak-tracker-count)

  (import (chezscheme))

  ;; -----------------------------------------------------------------
  ;; Global tracker state
  ;; -----------------------------------------------------------------

  ;; We use a guardian to detect when objects become unreachable.
  ;; We also maintain a registry (eq-hashtable) mapping tracked objects
  ;; to their labels.  When an object is collected by GC, the guardian
  ;; returns it; we then remove it from the registry.  Objects remaining
  ;; in the registry after GC are "still live" (potential leaks).

  (define *guardian* (make-guardian))
  (define *registry* (make-eq-hashtable))
  (define *tracker-mutex* (make-mutex))

  ;; -----------------------------------------------------------------
  ;; Core operations
  ;; -----------------------------------------------------------------

  ;; Register an object for leak tracking with a descriptive label.
  (define (track-allocation obj label)
    (with-mutex *tracker-mutex*
      (hashtable-set! *registry* obj label)
      (*guardian* obj))
    obj)

  ;; Stop tracking an object (e.g., when intentionally retained).
  (define (untrack-allocation obj)
    (with-mutex *tracker-mutex*
      (hashtable-delete! *registry* obj)))

  ;; Drain the guardian: remove objects that have been collected.
  (define (drain-guardian!)
    (let loop ()
      (let ([obj (*guardian*)])
        (when obj
          (hashtable-delete! *registry* obj)
          (loop)))))

  ;; Force GC and report objects that are still live (not collected).
  ;; Returns a list of (label . object) pairs for objects still tracked.
  (define (report-leaks)
    (with-mutex *tracker-mutex*
      ;; Force full GC
      (collect (collect-maximum-generation))
      (collect (collect-maximum-generation))
      ;; Drain guardian to remove collected objects
      (drain-guardian!)
      ;; Remaining entries are still live — potential leaks
      (let ([leaks '()])
        (let-values ([(keys vals) (hashtable-entries *registry*)])
          (vector-for-each
            (lambda (obj label)
              (set! leaks (cons (cons label obj) leaks)))
            keys vals))
        leaks)))

  ;; Run a thunk with leak tracking.  Returns (values result leak-report).
  ;; All allocations tracked during the thunk are monitored.
  ;; After the thunk completes, forces GC and reports leaks.
  (define (with-leak-check thunk)
    ;; Save current registry state
    (let ([saved-keys '()])
      (with-mutex *tracker-mutex*
        (let-values ([(keys vals) (hashtable-entries *registry*)])
          (set! saved-keys (vector->list keys))))
      ;; Run the thunk
      (let ([result (thunk)])
        ;; Force GC and collect
        (collect (collect-maximum-generation))
        (collect (collect-maximum-generation))
        (with-mutex *tracker-mutex*
          (drain-guardian!)
          ;; Find newly tracked objects that are still live
          (let ([leaks '()])
            (let-values ([(keys vals) (hashtable-entries *registry*)])
              (vector-for-each
                (lambda (obj label)
                  (unless (memq obj saved-keys)
                    (set! leaks (cons (cons label obj) leaks))))
                keys vals))
            (values result leaks))))))

  ;; Reset the tracker: clear all tracked objects.
  (define (leak-tracker-reset!)
    (with-mutex *tracker-mutex*
      ;; Drain the guardian completely
      (drain-guardian!)
      ;; Clear the registry
      (hashtable-clear! *registry*)
      ;; Replace with fresh guardian
      (set! *guardian* (make-guardian))))

  ;; Return the number of currently tracked objects.
  (define (leak-tracker-count)
    (with-mutex *tracker-mutex*
      ;; Drain first to get accurate count
      (drain-guardian!)
      (hashtable-size *registry*)))

) ;; end library
