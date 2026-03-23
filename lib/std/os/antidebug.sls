#!chezscheme
;;; (std os antidebug) — Anti-debugging primitives via Rust/libc
;;;
;;; Provides runtime checks for debuggers, tracers, library injection,
;;; breakpoints, and timing anomalies. Backed by libjerboa_native.so.

(library (std os antidebug)
  (export
    ;; One-shot defense (irreversible)
    antidebug-ptrace!
    ;; Non-destructive queries
    antidebug-traced?
    antidebug-ld-preload?
    antidebug-breakpoint?
    antidebug-timing-anomaly?
    antidebug-check-all
    ;; Condition type
    &antidebug-error make-antidebug-error antidebug-error?
    antidebug-error-reason)

  (import (chezscheme))

  ;; Load native library
  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "./lib/libjerboa_native.so") #t)
        (error 'std/os/antidebug "libjerboa_native.so not found")))

  ;; Condition type
  (define-condition-type &antidebug-error &error
    make-antidebug-error antidebug-error?
    (reason antidebug-error-reason))

  ;; FFI bindings
  (define c-ptrace
    (foreign-procedure "jerboa_antidebug_ptrace" () int))
  (define c-check-tracer
    (foreign-procedure "jerboa_antidebug_check_tracer" () int))
  (define c-check-ld-preload
    (foreign-procedure "jerboa_antidebug_check_ld_preload" () int))
  (define c-check-breakpoint
    (foreign-procedure "jerboa_antidebug_check_breakpoint" (uptr) int))
  (define c-timing-check
    (foreign-procedure "jerboa_antidebug_timing_check" (unsigned-64) int))
  (define c-check-all
    (foreign-procedure "jerboa_antidebug_check_all" () int))

  ;; --- Public API ---

  ;; PTRACE_TRACEME self-trace. Prevents debuggers from attaching.
  ;; Irreversible — calling twice always fails the second time.
  ;; Returns (void) on success, raises on failure (already traced).
  (define (antidebug-ptrace!)
    (let ([rc (c-ptrace)])
      (when (< rc 0)
        (raise (condition
          (make-antidebug-error "ptrace self-trace failed")
          (make-message-condition
            "PTRACE_TRACEME failed: process is already being traced"))))
      (void)))

  ;; Check if a tracer (debugger) is attached via /proc/self/status.
  ;; Returns #t if traced, #f if clean.
  (define (antidebug-traced?)
    (let ([rc (c-check-tracer)])
      (cond
        [(= rc 1) #t]
        [(= rc 0) #f]
        [else
         (raise (condition
           (make-antidebug-error "tracer check failed")
           (make-message-condition "cannot read /proc/self/status")))])))

  ;; Check if LD_PRELOAD is set (library injection detection).
  ;; Checks both current env and /proc/self/environ.
  ;; Returns #t if detected, #f if clean.
  (define (antidebug-ld-preload?)
    (let ([rc (c-check-ld-preload)])
      (cond
        [(= rc 1) #t]
        [(= rc 0) #f]
        [else
         (raise (condition
           (make-antidebug-error "LD_PRELOAD check failed")
           (make-message-condition "error checking LD_PRELOAD")))])))

  ;; Check if a software breakpoint (INT3, 0xCC) exists at a code address.
  ;; addr: an unsigned pointer (uptr) to a readable code address.
  ;; Returns #t if breakpoint detected, #f if clean.
  ;; WARNING: addr must point to readable memory in the process's .text section.
  (define (antidebug-breakpoint? addr)
    (let ([rc (c-check-breakpoint addr)])
      (cond
        [(= rc 1) #t]
        [(= rc 0) #f]
        [else
         (raise (condition
           (make-antidebug-error "breakpoint check failed")
           (make-message-condition "null or invalid address")))])))

  ;; Check for timing anomalies indicating single-stepping.
  ;; max-ns: maximum nanoseconds for calibration loop (e.g. 50000000 for 50ms).
  ;; Returns #t if suspiciously slow, #f if normal.
  (define (antidebug-timing-anomaly? max-ns)
    (let ([rc (c-timing-check max-ns)])
      (cond
        [(= rc 1) #t]
        [(= rc 0) #f]
        [else
         (raise (condition
           (make-antidebug-error "timing check failed")
           (make-message-condition "timing calibration error")))])))

  ;; Run all non-destructive checks at once.
  ;; Returns an alist of detection results:
  ;;   ((traced . #t/#f) (ld-preload . #t/#f) (timing . #t/#f))
  ;; Raises on error.
  (define (antidebug-check-all)
    (let ([rc (c-check-all)])
      (when (< rc 0)
        (raise (condition
          (make-antidebug-error "combined check failed")
          (make-message-condition "antidebug check-all error"))))
      (list
        (cons 'traced     (not (zero? (bitwise-and rc 1))))
        (cons 'ld-preload (not (zero? (bitwise-and rc 2))))
        (cons 'timing     (not (zero? (bitwise-and rc 4)))))))

  ) ;; end library
