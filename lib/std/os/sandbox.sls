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
;;;   OpenBSD: pledge(2) + unveil(2)
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
    sandbox-run/pledge
    sandbox-available?)

  (import (chezscheme)
          (std security capsicum))

  ;; ========== Platform Detection ==========

  (define (detect-platform)
    (let ([mt (symbol->string (machine-type))])
      (cond
        [(string-contains mt "osx") 'macos]
        [(string-contains mt "ob")  'openbsd]
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

  ;; ========== OpenBSD pledge/unveil FFI ==========

  (define c-pledge-available
    (if (eq? *platform* 'openbsd)
      (guard (e [#t (lambda () 0)])
        (foreign-procedure "ffi_pledge_available" () int))
      (lambda () 0)))

  (define c-pledge
    (if (eq? *platform* 'openbsd)
      (guard (e [#t (lambda (p ep) -1)])
        (foreign-procedure "ffi_pledge" (string string) int))
      (lambda (p ep) -1)))

  (define c-unveil
    (if (eq? *platform* 'openbsd)
      (guard (e [#t (lambda (p perms) -1)])
        (foreign-procedure "ffi_unveil" (string string) int))
      (lambda (p perms) -1)))

  (define c-unveil-lock
    (if (eq? *platform* 'openbsd)
      (guard (e [#t (lambda () -1)])
        (foreign-procedure "ffi_unveil" (void* void*) int))
      (lambda () -1)))

  (define c-openbsd-sandbox
    (if (eq? *platform* 'openbsd)
      (guard (e [#t (lambda args -1)])
        (foreign-procedure "ffi_openbsd_sandbox" (string string string string string) int))
      (lambda args -1)))

  (define (pledge-available?)
    (and (eq? *platform* 'openbsd)
         (= 1 (c-pledge-available))))

  ;; Capsicum availability (delegates to the capsicum module)
  ;; capsicum-available?, capsicum-enter!, capsicum-limit-fd!,
  ;; capsicum-open-path, capsicum-apply-preset! imported from
  ;; (std security capsicum)

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
      [(openbsd) (pledge-available?)]
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
           [(openbsd)
            ;; Apply unveil for path restrictions, then pledge for syscall restriction.
            ;; unveil restricts filesystem visibility (like Landlock paths).
            ;; pledge restricts syscall families (like seccomp profiles).
            (when (pledge-available?)
              (guard (e [#t
                        (display "sandbox: OpenBSD pledge/unveil enforcement failed: "
                                 (current-error-port))
                        (display-condition e (current-error-port))
                        (newline (current-error-port))
                        (c-exit 126)])
                (openbsd-sandbox-paths! read-paths write-paths exec-paths)))]
           [(freebsd)
            ;; Pre-open paths as restricted fds, then enter capability mode.
            ;; This gives Landlock-equivalent path-based restrictions via Capsicum.
            (when (capsicum-available?)
              (guard (e [#t
                        (display "sandbox: Capsicum enforcement failed: "
                                 (current-error-port))
                        (display-condition e (current-error-port))
                        (newline (current-error-port))
                        (c-exit 126)])
                (capsicum-sandbox-paths! read-paths write-paths exec-paths)))]
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
  ;; Optional fd-rights: alist of (fd . (right-symbol ...)) for per-fd restriction.
  (define (sandbox-run/capsicum thunk . maybe-fd-rights)
    (let ((pid (c-fork)))
      (cond
        ((< pid 0)
         (error 'sandbox-run/capsicum "fork failed"))
        ((= pid 0)
         ;; CHILD: apply fd restrictions then enter Capsicum mode
         (guard (e [#t
                   (display "sandbox: " (current-error-port))
                   (display-condition e (current-error-port))
                   (newline (current-error-port))
                   (c-exit 1)])
           (when (capsicum-available?)
             (if (and (pair? maybe-fd-rights) (pair? (car maybe-fd-rights)))
               ;; Apply preset with fd restrictions
               (capsicum-apply-preset! (car maybe-fd-rights))
               ;; Bare cap_enter
               (capsicum-enter!))))
         (guard (e [#t
                   (display "sandbox: " (current-error-port))
                   (display-condition e (current-error-port))
                   (newline (current-error-port))
                   (c-exit 1)])
           (thunk))
         (c-exit 0))
        (else
         (wait-for-child pid)))))

  ;; ========== OpenBSD pledge/unveil ==========

  ;; Map Landlock-style path restrictions to unveil + pledge.
  ;; 1. unveil each allowed path with appropriate permissions
  ;; 2. unveil essential system paths for basic operation
  ;; 3. Lock unveil (no more paths can be added)
  ;; 4. Apply pledge to restrict syscall families
  ;;
  ;; Default pledge promises: stdio rpath proc exec
  ;; With write paths: + wpath cpath
  ;; With exec paths:  + exec (already included by default)
  (define (openbsd-sandbox-paths! read-paths write-paths exec-paths)
    ;; Unveil essential system paths for a functional shell
    (c-unveil "/usr/lib"     "r")
    (c-unveil "/usr/libexec" "r")
    (c-unveil "/usr/share"   "r")
    (c-unveil "/dev/null"    "rw")
    (c-unveil "/dev/random"  "r")
    (c-unveil "/dev/urandom" "r")
    (c-unveil "/etc/resolv.conf" "r")
    (c-unveil "/etc/ssl"     "r")
    ;; User-specified read-only paths
    (for-each (lambda (p) (c-unveil p "r"))
      (if (list? read-paths) read-paths '()))
    ;; User-specified read+write paths
    (for-each (lambda (p) (c-unveil p "rwc"))
      (if (list? write-paths) write-paths '()))
    ;; User-specified execute paths — rx so the binaries can be read and exec'd
    (for-each (lambda (p) (c-unveil p "rx"))
      (if (list? exec-paths) exec-paths '()))
    ;; Lock unveil — IRREVERSIBLE, no more paths can be added
    (c-unveil-lock)
    ;; Build pledge promises based on what's needed
    (let* ([base "stdio rpath proc"]
           [promises
             (string-append base
               (if (pair? write-paths) " wpath cpath fattr" "")
               (if (pair? exec-paths) " exec" ""))])
      (when (< (c-pledge promises #f) 0)
        (error 'openbsd-sandbox-paths! "pledge failed"))))

  ;; OpenBSD-specific: run a thunk under custom pledge promises.
  ;; promises: string of space-separated promise names
  ;; execpromises: promises for exec'd children (or #f for none)
  ;; Optional unveil-specs: list of (path . permissions) pairs applied before pledge.
  (define (sandbox-run/pledge promises thunk . maybe-unveils)
    (let ((pid (c-fork)))
      (cond
        ((< pid 0)
         (error 'sandbox-run/pledge "fork failed"))
        ((= pid 0)
         ;; CHILD: apply unveil restrictions then pledge
         (guard (e [#t
                   (display "sandbox: " (current-error-port))
                   (display-condition e (current-error-port))
                   (newline (current-error-port))
                   (c-exit 1)])
           (when (pledge-available?)
             ;; Apply unveil specs if provided
             (when (and (pair? maybe-unveils) (pair? (car maybe-unveils)))
               (for-each
                 (lambda (spec)
                   (when (< (c-unveil (car spec) (cdr spec)) 0)
                     (error 'sandbox-run/pledge
                       (string-append "unveil failed for " (car spec)))))
                 (car maybe-unveils))
               ;; Lock unveil
               (c-unveil-lock))
             ;; Apply pledge
             (when (< (c-pledge promises #f) 0)
               (error 'sandbox-run/pledge "pledge failed"))))
         (guard (e [#t
                   (display "sandbox: " (current-error-port))
                   (display-condition e (current-error-port))
                   (newline (current-error-port))
                   (c-exit 1)])
           (thunk))
         (c-exit 0))
        (else
         (wait-for-child pid)))))

  ;; ========== Capsicum Path Pre-opening ==========

  (define (capsicum-sandbox-paths! read-paths write-paths exec-paths)
    ;; Pre-open paths as fds with appropriate Capsicum rights, restrict
    ;; stdio, then enter capability mode. This maps Landlock-style path
    ;; restrictions to the Capsicum fd-capability model.
    ;;
    ;; After this call, the process can only operate on pre-opened fds
    ;; with their restricted rights. No new fds from global namespace.
    ;;
    ;; Returns the list of opened fds (caller can use with openat(2)).
    (let ([opened-fds '()])
      ;; Pre-open read-only paths
      (for-each
        (lambda (p)
          (guard (e [#t (void)])  ;; skip paths that can't be opened
            (let ([fd (capsicum-open-path p '(read fstat seek lookup))])
              (set! opened-fds (cons fd opened-fds)))))
        (if (list? read-paths) read-paths '()))
      ;; Pre-open read-write paths
      (for-each
        (lambda (p)
          (guard (e [#t (void)])
            (let ([fd (capsicum-open-path p '(read write fstat seek ftruncate lookup))])
              (set! opened-fds (cons fd opened-fds)))))
        (if (list? write-paths) write-paths '()))
      ;; Pre-open execute paths (read-only access for loading)
      (for-each
        (lambda (p)
          (guard (e [#t (void)])
            (let ([fd (capsicum-open-path p '(read fstat lookup))])
              (set! opened-fds (cons fd opened-fds)))))
        (if (list? exec-paths) exec-paths '()))
      ;; Restrict stdio fds
      (guard (e [#t (void)]) (capsicum-limit-fd! 0 '(read fstat)))
      (guard (e [#t (void)]) (capsicum-limit-fd! 1 '(write fstat)))
      (guard (e [#t (void)]) (capsicum-limit-fd! 2 '(write fstat)))
      ;; Enter capability mode
      (capsicum-enter!)
      (reverse opened-fds)))

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
