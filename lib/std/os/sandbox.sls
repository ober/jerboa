#!chezscheme
;;; (std os sandbox) — Fork-and-sandbox execution
;;;
;;; Forks the current process, applies Landlock restrictions in the child,
;;; runs a thunk, then exits. The parent process is NEVER affected.
;;;
;;; This is the high-level API for sandboxed execution. It combines:
;;; - fork(2) to isolate the sandbox from the parent
;;; - Landlock to enforce filesystem restrictions in the child
;;; - waitpid(2) to collect the child's exit status
;;;
;;; Usage:
;;;   (sandbox-run
;;;     '("/tmp" "/var/data")   ; read-only paths
;;;     '("/tmp/output")        ; read+write paths
;;;     '()                     ; execute paths
;;;     (lambda () (system "ls /tmp")))
;;;   => exit status (0 on success)
;;;
;;; The thunk runs in a forked child with Landlock applied.
;;; Any attempt to access paths outside the allowed set gets
;;; EACCES from the kernel.

(library (std os sandbox)
  (export
    sandbox-run
    sandbox-run/command
    sandbox-available?)

  (import (chezscheme)
          (std os landlock))

  ;; ========== FFI ==========

  (define c-fork (foreign-procedure "fork" () int))
  (define c-waitpid (foreign-procedure "waitpid" (int void* int) int))
  (define c-exit (foreign-procedure "_exit" (int) void))

  ;; ========== Public API ==========

  ;; Check if sandboxing is available on this system.
  (define (sandbox-available?)
    (landlock-available?))

  ;; Fork, apply Landlock in child, run thunk, return exit status.
  ;;
  ;; read-paths:  list of paths for read-only access
  ;; write-paths: list of paths for read+write access
  ;; exec-paths:  list of paths for execute access
  ;; thunk:       procedure to run in the sandboxed child
  ;;
  ;; Returns the child's exit status (0-255).
  ;; The parent process is NEVER affected by the sandbox.
  (define (sandbox-run read-paths write-paths exec-paths thunk)
    (let ((pid (c-fork)))
      (cond
        ((< pid 0)
         (error 'sandbox-run "fork failed"))

        ((= pid 0)
         ;; === CHILD PROCESS ===
         ;; Apply Landlock — PERMANENT and IRREVERSIBLE in this process
         (let ((ret (landlock-enforce! read-paths write-paths exec-paths)))
           (when (condition? ret)
             (display "sandbox: Landlock enforcement failed\n"
                      (current-error-port))
             (c-exit 126))
           (when (eq? ret 'unsupported)
             (display "sandbox: Landlock not supported by kernel, "
                      (current-error-port))
             (display "running without enforcement\n"
                      (current-error-port))))
         ;; Run the thunk in the sandboxed child
         (guard (e [#t
                   (display "sandbox: " (current-error-port))
                   (display-condition e (current-error-port))
                   (newline (current-error-port))
                   (c-exit 1)])
           (thunk))
         (c-exit 0))

        (else
         ;; === PARENT PROCESS ===
         (wait-for-child pid)))))

  ;; Convenience: run a shell command string in a sandbox.
  ;; Equivalent to: sandbox-run ... (lambda () (system cmd))
  (define (sandbox-run/command read-paths write-paths exec-paths cmd)
    (sandbox-run read-paths write-paths exec-paths
      (lambda () (system cmd))))

  ;; ========== Internal ==========

  ;; Wait for child and decode exit status.
  (define (wait-for-child pid)
    (let ((status-buf (foreign-alloc 4)))
      (let loop ()
        (let ((result (c-waitpid pid status-buf 0)))
          (cond
            ((> result 0)
             (let ((raw (foreign-ref 'int status-buf 0)))
               (foreign-free status-buf)
               ;; Decode: WIFEXITED -> (status >> 8) & 0xff
               ;;         WIFSIGNALED -> 128 + (status & 0x7f)
               (if (= (bitwise-and raw #x7f) 0)
                 (bitwise-and (bitwise-arithmetic-shift-right raw 8) #xff)
                 (+ 128 (bitwise-and raw #x7f)))))
            ((and (< result 0) (= (foreign-ref 'int (foreign-alloc 4) 0) 4))
             ;; EINTR — retry
             (loop))
            (else
             (foreign-free status-buf)
             -1))))))

  ) ;; end library
