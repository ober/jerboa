#!chezscheme
;;; (std os sandbox) — Fork-and-sandbox execution
;;;
;;; Forks the current process, applies platform-specific restrictions
;;; in the child, runs a thunk, then exits. The parent process is
;;; NEVER affected.
;;;
;;; Platform protections:
;;;   Linux:   Landlock filesystem access control
;;;   macOS:   Seatbelt sandbox profiles
;;;   FreeBSD: Capsicum capability mode
;;;
;;; This is the high-level API for sandboxed execution. It combines:
;;; - fork(2) to isolate the sandbox from the parent
;;; - Platform-specific enforcement in the child
;;; - waitpid(2) to collect the child's exit status
;;;
;;; Usage:
;;;   ;; Linux — Landlock path restrictions:
;;;   (sandbox-run
;;;     '("/tmp" "/var/data")   ; read-only paths
;;;     '("/tmp/output")        ; read+write paths
;;;     '()                     ; execute paths
;;;     (lambda () (system "ls /tmp")))
;;;   => exit status (0 on success)
;;;
;;;   ;; macOS — Seatbelt profile:
;;;   (sandbox-run/profile 'no-write
;;;     (lambda () (system "ls /tmp")))
;;;
;;;   ;; FreeBSD — Capsicum:
;;;   (sandbox-run/capsicum
;;;     (lambda () (display "sandboxed\n")))
;;;
;;; The thunk runs in a forked child with protections applied.

(library (std os sandbox)
  (export
    sandbox-run
    sandbox-run/command
    sandbox-run/profile
    sandbox-run/capsicum
    sandbox-available?)

  (import (chezscheme))

  ;; ========== Platform Detection ==========

  (define (detect-platform)
    (let ([mt (symbol->string (machine-type))])
      (cond
        [(string-contains mt "osx") 'macos]
        [(string-contains mt "fb")  'freebsd]
        [(string-contains mt "le")  'linux]
        [else                       'unknown])))

  (define (string-contains str sub)
    (let ([slen (string-length str)]
          [sublen (string-length sub)])
      (let lp ([i 0])
        (cond
          [(> (+ i sublen) slen) #f]
          [(string=? (substring str i (+ i sublen)) sub) #t]
          [else (lp (+ i 1))]))))

  (define *platform* (detect-platform))

  ;; ========== FFI ==========

  (define c-fork (foreign-procedure "fork" () int))
  (define c-waitpid (foreign-procedure "waitpid" (int void* int) int))
  (define c-exit (foreign-procedure "_exit" (int) void))

  ;; ========== Landlock FFI (Linux) ==========

  ;; Lazy import: try to load landlock procedures only on Linux.
  ;; These match the (std os landlock) C shim API.
  (define c-landlock-abi-version
    (if (eq? *platform* 'linux)
      (guard (e [#t (lambda () -1)])
        (foreign-procedure "jerboa_landlock_abi_version" () int))
      (lambda () -1)))

  (define c-landlock-sandbox
    (if (eq? *platform* 'linux)
      (guard (e [#t (lambda (r w x) -1)])
        (foreign-procedure "jerboa_landlock_sandbox" (string string string) int))
      (lambda (r w x) -1)))

  (define (landlock-available?)
    (and (eq? *platform* 'linux)
         (>= (c-landlock-abi-version) 1)))

  ;; ========== Seatbelt FFI (macOS) ==========

  (define c-sandbox-init
    (if (eq? *platform* 'macos)
      (guard (e [#t (lambda args -1)])
        (foreign-procedure "sandbox_init" (string unsigned-64 void*) int))
      (lambda args -1)))

  (define c-sandbox-free-error
    (if (eq? *platform* 'macos)
      (guard (e [#t (lambda (p) (void))])
        (foreign-procedure "sandbox_free_error" (void*) void))
      (lambda (p) (void))))

  (define SANDBOX_NAMED 1)

  (define (seatbelt-available?)
    (and (eq? *platform* 'macos)
         (guard (e [#t #f])
           (foreign-entry? "sandbox_init"))))

  ;; Named profile map
  (define (named-profile-string sym)
    (case sym
      [(pure-computation)          "kSBXProfilePureComputation"]
      [(no-write)                  "kSBXProfileNoWrite"]
      [(no-write-except-temporary) "kSBXProfileNoWriteExceptTemporary"]
      [(no-internet)               "kSBXProfileNoInternet"]
      [(no-network)                "kSBXProfileNoNetwork"]
      [else #f]))

  (define (apply-seatbelt! profile-spec)
    ;; Apply a Seatbelt profile. profile-spec is a symbol or SBPL string.
    (let ([errptr (foreign-alloc 8)])
      (foreign-set! 'void* errptr 0 0)
      (dynamic-wind
        (lambda () (void))
        (lambda ()
          (let ([rc (if (string? profile-spec)
                      ;; Raw SBPL string — flags = 0
                      (c-sandbox-init profile-spec 0 errptr)
                      ;; Named profile — flags = SANDBOX_NAMED
                      (let ([name (named-profile-string profile-spec)])
                        (if name
                          (c-sandbox-init name SANDBOX_NAMED errptr)
                          (begin
                            (display "sandbox: unknown Seatbelt profile\n"
                                     (current-error-port))
                            -1))))])
            (when (< rc 0)
              (let ([errmsg (foreign-ref 'void* errptr 0)])
                (unless (= errmsg 0)
                  (c-sandbox-free-error errmsg)))
              (display "sandbox: Seatbelt enforcement failed\n"
                       (current-error-port)))))
        (lambda ()
          (foreign-free errptr)))))

  ;; ========== Capsicum FFI (FreeBSD) ==========

  (define c-cap-enter
    (if (eq? *platform* 'freebsd)
      (guard (e [#t (lambda () -1)])
        (foreign-procedure "cap_enter" () int))
      (lambda () -1)))

  (define (capsicum-available?)
    (and (eq? *platform* 'freebsd)
         (guard (e [#t #f])
           (foreign-entry? "cap_enter"))))

  ;; ========== Landlock helpers ==========

  ;; Pack a list of path strings with SOH (\x01) separator for C FFI.
  (define (pack-paths lst)
    (if (or (not lst) (null? lst)) ""
      (let loop ((rest (cdr lst)) (acc (car lst)))
        (if (null? rest) acc
          (loop (cdr rest)
                (string-append acc (string #\x1) (car rest)))))))

  (define (landlock-enforce! read-paths write-paths exec-paths)
    (let ((packed-read  (pack-paths read-paths))
          (packed-write (pack-paths write-paths))
          (packed-exec  (pack-paths exec-paths)))
      (let ((ret (c-landlock-sandbox packed-read packed-write packed-exec)))
        (cond
          ((= ret 0) #t)
          ((= ret 1) 'unsupported)
          (else
           (display "sandbox: Landlock enforcement failed\n"
                    (current-error-port))
           #f)))))

  ;; ========== Public API ==========

  ;; Check if sandboxing is available on this system.
  (define (sandbox-available?)
    (case *platform*
      [(linux)   (landlock-available?)]
      [(macos)   (seatbelt-available?)]
      [(freebsd) (capsicum-available?)]
      [else #f]))

  ;; Fork, apply Landlock in child, run thunk, return exit status.
  ;; (Linux-style API — kept for backward compatibility)
  ;;
  ;; read-paths:  list of paths for read-only access
  ;; write-paths: list of paths for read+write access
  ;; exec-paths:  list of paths for execute access
  ;; thunk:       procedure to run in the sandboxed child
  ;;
  ;; Returns the child's exit status (0-255).
  ;; The parent process is NEVER affected by the sandbox.
  ;;
  ;; On non-Linux platforms, the path arguments are mapped to the
  ;; closest equivalent:
  ;;   macOS:   Generates an SBPL profile from the path lists
  ;;   FreeBSD: Enters Capsicum mode (path args are informational only)
  (define (sandbox-run read-paths write-paths exec-paths thunk)
    (let ((pid (c-fork)))
      (cond
        ((< pid 0)
         (error 'sandbox-run "fork failed"))

        ((= pid 0)
         ;; === CHILD PROCESS ===
         ;; Apply platform-specific restrictions
         (case *platform*
           [(linux)
            (let ((ret (landlock-enforce! read-paths write-paths exec-paths)))
              (when (condition? ret)
                (display "sandbox: Landlock enforcement failed\n"
                         (current-error-port))
                (c-exit 126))
              (when (eq? ret 'unsupported)
                (display "sandbox: Landlock not supported by kernel, "
                         (current-error-port))
                (display "running without enforcement\n"
                         (current-error-port))))]
           [(macos)
            ;; Generate an SBPL profile from the path lists
            (when (seatbelt-available?)
              (let ([sbpl (paths->sbpl-profile read-paths write-paths exec-paths)])
                (apply-seatbelt! sbpl)))]
           [(freebsd)
            ;; Enter Capsicum capability mode
            (when (capsicum-available?)
              (let ([rc (c-cap-enter)])
                (when (< rc 0)
                  (display "sandbox: Capsicum cap_enter failed\n"
                           (current-error-port))
                  (c-exit 126))))]
           [else (void)])
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
  (define (sandbox-run/command read-paths write-paths exec-paths cmd)
    (sandbox-run read-paths write-paths exec-paths
      (lambda () (system cmd))))

  ;; macOS-specific: run a thunk under a Seatbelt profile.
  ;; profile-spec: symbol ('pure-computation, 'no-write, etc.) or SBPL string.
  (define (sandbox-run/profile profile-spec thunk)
    (let ((pid (c-fork)))
      (cond
        ((< pid 0)
         (error 'sandbox-run/profile "fork failed"))
        ((= pid 0)
         ;; CHILD: apply Seatbelt
         (when (seatbelt-available?)
           (apply-seatbelt! profile-spec))
         (guard (e [#t
                   (display "sandbox: " (current-error-port))
                   (display-condition e (current-error-port))
                   (newline (current-error-port))
                   (c-exit 1)])
           (thunk))
         (c-exit 0))
        (else
         (wait-for-child pid)))))

  ;; FreeBSD-specific: run a thunk in Capsicum capability mode.
  (define (sandbox-run/capsicum thunk)
    (let ((pid (c-fork)))
      (cond
        ((< pid 0)
         (error 'sandbox-run/capsicum "fork failed"))
        ((= pid 0)
         ;; CHILD: enter Capsicum mode
         (when (capsicum-available?)
           (let ([rc (c-cap-enter)])
             (when (< rc 0)
               (display "sandbox: cap_enter failed\n" (current-error-port))
               (c-exit 126))))
         (guard (e [#t
                   (display "sandbox: " (current-error-port))
                   (display-condition e (current-error-port))
                   (newline (current-error-port))
                   (c-exit 1)])
           (thunk))
         (c-exit 0))
        (else
         (wait-for-child pid)))))

  ;; ========== Internal ==========

  ;; Generate an SBPL profile string from path lists.
  ;; Maps Landlock-style path restrictions to Seatbelt Profile Language.
  (define (paths->sbpl-profile read-paths write-paths exec-paths)
    (string-append
      "(version 1)"
      "(deny default)"
      ;; Allow Mach and signal for basic process operation
      "(allow mach-lookup)"
      "(allow signal)"
      "(allow sysctl-read)"
      ;; Always allow reading system libraries
      "(allow file-read* (subpath \"/usr/lib\")"
      "                  (subpath \"/System\")"
      "                  (subpath \"/Library/Frameworks\")"
      "                  (subpath \"/private/var/db/dyld\")"
      ;; User-specified read paths
      (apply string-append
        (map (lambda (p) (format " (subpath ~s)" p)) read-paths))
      ;; Write paths also get read access
      (apply string-append
        (map (lambda (p) (format " (subpath ~s)" p)) write-paths))
      ")"
      ;; Write permissions
      (if (null? write-paths) ""
        (string-append
          "(allow file-write* "
          (apply string-append
            (map (lambda (p) (format "(subpath ~s) " p)) write-paths))
          ")"))
      ;; Execute permissions
      (if (null? exec-paths) ""
        (string-append
          "(allow process-exec (subpath \"/usr/bin\") (subpath \"/bin\")"
          (apply string-append
            (map (lambda (p) (format " (subpath ~s)" p)) exec-paths))
          ")"))))

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
