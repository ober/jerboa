#!chezscheme
;;; (std os seccomp) — seccomp-bpf syscall filtering via Rust/libc
;;;
;;; Provides kernel-enforced syscall restrictions. Once installed,
;;; filters are IRREVERSIBLE for the process lifetime.

(library (std os seccomp)
  (export
    ;; Queries
    seccomp-available?
    ;; Irreversible filters
    seccomp-lock!
    seccomp-lock-strict!
    ;; Condition type
    &seccomp-error make-seccomp-error seccomp-error?
    seccomp-error-reason)

  (import (chezscheme))

  ;; Load native library
  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "./lib/libjerboa_native.so") #t)
        (error 'std/os/seccomp "libjerboa_native.so not found")))

  ;; Condition type
  (define-condition-type &seccomp-error &error
    make-seccomp-error seccomp-error?
    (reason seccomp-error-reason))

  ;; FFI bindings
  (define c-seccomp-available
    (foreign-procedure "jerboa_seccomp_available" () int))
  (define c-seccomp-lock
    (foreign-procedure "jerboa_seccomp_lock" () int))
  (define c-seccomp-lock-strict
    (foreign-procedure "jerboa_seccomp_lock_strict" (u8* size_t) int))

  ;; --- Public API ---

  ;; Check if seccomp filtering is supported on this kernel.
  (define (seccomp-available?)
    (= 1 (c-seccomp-available)))

  ;; Install a seccomp filter blocking debug-related syscalls:
  ;;   ptrace, process_vm_readv, process_vm_writev, personality
  ;; All other syscalls remain allowed.
  ;; IRREVERSIBLE. Returns (void) on success, raises on failure.
  (define (seccomp-lock!)
    (let ([rc (c-seccomp-lock)])
      (when (< rc 0)
        (raise (condition
          (make-seccomp-error "seccomp lock failed")
          (make-message-condition
            "failed to install seccomp-bpf filter"))))
      (void)))

  ;; Install a strict seccomp filter: ONLY the specified syscall numbers
  ;; are allowed. Everything else kills the process.
  ;; syscall-numbers: a list of exact integers (x86_64 syscall numbers).
  ;; IRREVERSIBLE. Returns (void) on success, raises on failure.
  ;;
  ;; Example:
  ;;   (seccomp-lock-strict! '(0 1 3 60 231))  ; read, write, close, exit, exit_group
  (define (seccomp-lock-strict! syscall-numbers)
    (let* ([count (length syscall-numbers)]
           [bv (make-bytevector (* count 4))])
      ;; Pack syscall numbers as native-endian 32-bit ints
      (let loop ([nums syscall-numbers] [i 0])
        (unless (null? nums)
          (bytevector-s32-native-set! bv (* i 4) (car nums))
          (loop (cdr nums) (+ i 1))))
      (let ([rc (c-seccomp-lock-strict bv count)])
        (when (< rc 0)
          (raise (condition
            (make-seccomp-error "strict seccomp lock failed")
            (make-message-condition
              "failed to install strict seccomp-bpf filter"))))
        (void))))

  ) ;; end library
