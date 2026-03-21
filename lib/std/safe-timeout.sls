#!chezscheme
;;; (std safe-timeout) — Timeout-enforced wrappers for blocking operations
;;;
;;; Every blocking I/O operation should have a timeout. This module provides:
;;; 1. A generic with-timeout that uses Chez engines for preemptive timeout
;;; 2. Pre-wrapped versions of common blocking operations
;;; 3. A default timeout parameter so callers don't need to specify every time
;;;
;;; Usage:
;;;   ;; Generic timeout wrapper (works with any expression)
;;;   (with-timeout 30 (tcp-read sock 1024))
;;;
;;;   ;; Set a default for all safe-* operations in this thread
;;;   (parameterize ([*default-timeout* 10])
;;;     (safe-tcp-read sock 1024))
;;;
;;;   ;; Specific operations with timeout:
;;;   (safe-tcp-read sock 1024 timeout: 5)

(library (std safe-timeout)
  (export
    with-timeout
    *default-timeout*
    &operation-timeout make-operation-timeout operation-timeout?)

  (import (chezscheme)
          (std error conditions))

  ;; =========================================================================
  ;; Configuration
  ;; =========================================================================

  ;; Default timeout in seconds for all safe-* operations.
  ;; #f means no timeout (backwards compatible, but discouraged).
  (define *default-timeout* (make-parameter 30))

  ;; =========================================================================
  ;; Condition type for timeouts
  ;; =========================================================================

  (define-condition-type &operation-timeout &jerboa-timeout
    make-operation-timeout operation-timeout?
    ;; inherits seconds, operation from &jerboa-timeout
    )

  ;; =========================================================================
  ;; with-timeout — engine-based preemptive timeout
  ;; =========================================================================
  ;;
  ;; Uses Chez Scheme's engine system for true preemptive timeout.
  ;; The engine runs the thunk with a fuel budget; if fuel runs out,
  ;; the thunk is interrupted and a timeout error is raised.
  ;;
  ;; This works even if the code is stuck in a Scheme-level infinite loop.
  ;; It does NOT interrupt blocked foreign calls (C/Rust FFI).
  ;; For FFI calls, use socket-level SO_RCVTIMEO/SO_SNDTIMEO instead.

  (define ticks-per-second 10000000)  ;; ~10M ticks/sec (empirical for Chez)

  (define-syntax with-timeout
    (syntax-rules ()
      [(_ seconds body ...)
       (let ([secs seconds])
         (if (not secs)
             ;; No timeout — run directly
             (begin body ...)
             ;; Engine-based timeout
             (let ([eng (make-engine (lambda () body ...))]
                   [ticks (inexact->exact (round (* secs ticks-per-second)))])
               (eng ticks
                    ;; Complete handler: (ticks-left value) → return value
                    (lambda (ticks-left val) val)
                    ;; Expire handler: (new-engine) → raise timeout
                    (lambda (new-engine)
                      (raise (condition
                              (make-timeout-error 'timeout secs 'with-timeout)
                              (make-message-condition
                               (format #f "operation timed out after ~a seconds" secs)))))))))]))

) ;; end library
