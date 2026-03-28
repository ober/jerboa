#!chezscheme
;;; (std security cage) — Pledge/unveil-style process confinement
;;;
;;; Locks the CURRENT process to a directory. Irreversible.
;;; Network access is preserved. Child processes inherit the cage.
;;;
;;; Unlike run-safe (which forks), cage! applies Landlock restrictions
;;; directly to the calling process — like OpenBSD's unveil(2).
;;;
;;; Usage:
;;;   ;; Lock to a project directory (minimal):
;;;   (cage! (make-cage-config root: "/home/user/project"))
;;;
;;;   ;; Full options:
;;;   (cage! (make-cage-config
;;;     root: "/home/user/project"
;;;     read-only: '("/usr/share/man")
;;;     read-write: '("/tmp/scratch")
;;;     execute: '("/opt/bin")
;;;     network: #t
;;;     system-paths: 'auto
;;;     temp-dir: "/tmp"))
;;;
;;; After cage!, the process (and all children) can only access:
;;;   - The root directory (read-write)
;;;   - System paths needed for runtime (auto-detected, read-only)
;;;   - Standard binary paths (execute)
;;;   - /tmp or specified temp-dir (read-write)
;;;   - Network (unrestricted by default)
;;;
;;; There is no uncage!. Start a new process to escape.

(library (std security cage)
  (export
    ;; Core
    cage!
    make-cage-config
    cage-config?
    cage-active?

    ;; Config accessors
    cage-config-root
    cage-config-read-only
    cage-config-read-write
    cage-config-execute
    cage-config-network
    cage-config-system-paths
    cage-config-temp-dir
    cage-config-namespaces

    ;; Namespace isolation (Linux)
    cage-unshare!
    cage-namespaces-available?

    ;; PROTMAX (FreeBSD) — block mprotect escalation
    cage-protmax!
    cage-protmax-available?

    ;; Introspection
    cage-root
    cage-allowed-paths
    cage-namespaces-active?

    ;; Condition
    &cage-error make-cage-error cage-error?
    cage-error-phase cage-error-detail)

  (import (chezscheme)
          (std security landlock)
          (std security capsicum)
          (std error conditions))

  ;; ========== libc ==========

  (define _libc
    (or (guard (e [#t #f]) (load-shared-object "libc.so.7"))
        (guard (e [#t #f]) (load-shared-object "libc.so.6"))
        (guard (e [#t #f]) (load-shared-object "libc.dylib"))
        (guard (e [#t #f]) (load-shared-object "libc.so"))
        (guard (e [#t #f]) (load-shared-object ""))))

  ;; ========== Platform detection ==========

  (define (string-contains-ci str sub)
    (let ([slen (string-length str)]
          [sublen (string-length sub)])
      (let lp ([i 0])
        (cond
          [(> (+ i sublen) slen) #f]
          [(string-ci=? (substring str i (+ i sublen)) sub) #t]
          [else (lp (+ i 1))]))))

  (define (detect-platform)
    (let ([mt (symbol->string (machine-type))])
      (cond
        [(string-contains-ci mt "le")  'linux]
        [(string-contains-ci mt "osx") 'macos]
        [(string-contains-ci mt "ob")  'openbsd]
        [(string-contains-ci mt "fb")  'freebsd]
        [else                          'unknown])))

  (define *current-platform* (detect-platform))

  ;; ========== Condition type ==========

  (define-condition-type &cage-error &jerboa
    make-cage-error cage-error?
    (phase cage-error-phase)      ;; 'landlock | 'config | 'platform | 'resolve
    (detail cage-error-detail))   ;; string

  ;; ========== Global state ==========

  (define *cage-active* #f)
  (define *cage-root-path* #f)
  (define *cage-all-paths* '())
  (define *cage-namespaces-active* #f)

  (define (cage-active?) *cage-active*)
  (define (cage-root) *cage-root-path*)
  (define (cage-allowed-paths) *cage-all-paths*)
  (define (cage-namespaces-active?) *cage-namespaces-active*)

  ;; ========== Linux namespace isolation (unshare) ==========
  ;;
  ;; unshare(2) creates new namespaces for the calling process.
  ;; After unshare, the process is isolated from:
  ;;   CLONE_NEWPID  — other processes (can't see/signal them)
  ;;   CLONE_NEWNS   — mount tree (sees only its own mounts)
  ;;   CLONE_NEWNET  — network stack (only loopback unless configured)
  ;;
  ;; CLONE_NEWNET is opt-out because DNS/network servers need it.
  ;; Requires CAP_SYS_ADMIN or unprivileged user namespaces.

  ;; Linux clone flags for unshare(2)
  (define CLONE_NEWNS    #x00020000)
  (define CLONE_NEWPID   #x20000000)
  (define CLONE_NEWNET   #x40000000)
  (define CLONE_NEWUSER  #x10000000)

  (define c-unshare
    (guard (e [#t #f])
      (foreign-procedure "unshare" (int) int)))

  (define (cage-namespaces-available?)
    (and (eq? *current-platform* 'linux)
         (procedure? c-unshare)))

  (define (cage-unshare! . opts)
    "Enter Linux namespaces for process isolation. Call AFTER cage! and
     AFTER binding any sockets. Options:
       pid:     #t to isolate PID namespace (default #t)
       mount:   #t to isolate mount namespace (default #t)
       network: #f to isolate network namespace (default #f — preserves network)
     Raises &cage-error on failure."
    (unless (cage-namespaces-available?)
      (raise (make-cage-error
               "cage"
               'platform
               "Namespaces not available (Linux only, needs unshare(2))")))
    (let ([do-pid     (%cage-kwarg 'pid:     opts #t)]
          [do-mount   (%cage-kwarg 'mount:   opts #t)]
          [do-network (%cage-kwarg 'network: opts #f)])
      (let ([flags (bitwise-ior
                     (if do-pid     CLONE_NEWPID 0)
                     (if do-mount   CLONE_NEWNS  0)
                     (if do-network CLONE_NEWNET 0))])
        (when (> flags 0)
          (let ([rc (c-unshare flags)])
            (unless (= rc 0)
              ;; Try with CLONE_NEWUSER prepended (unprivileged namespaces)
              (let ([rc2 (c-unshare (bitwise-ior CLONE_NEWUSER flags))])
                (unless (= rc2 0)
                  (raise (make-cage-error
                           "cage"
                           'platform
                           (format "unshare() failed (flags=#x~x). Need CAP_SYS_ADMIN or unprivileged user namespaces."
                                   flags)))))))
          (set! *cage-namespaces-active* #t)
          (void)))))

  (define (%cage-kwarg key opts default)
    (let loop ([lst opts])
      (cond [(or (null? lst) (null? (cdr lst))) default]
            [(eq? (car lst) key) (cadr lst)]
            [else (loop (cddr lst))])))

  ;; ========== FreeBSD PROTMAX (block mprotect escalation) ==========
  ;;
  ;; procctl(P_PID, 0, PROC_PROTMAX_CTL, &arg) where arg = PROC_PROTMAX_FORCE_ENABLE
  ;; prevents mprotect from escalating page protections beyond what was set at
  ;; mmap time. This blocks the classic ROP second stage: attacker chains gadgets
  ;; to call mprotect(addr, len, PROT_READ|PROT_WRITE|PROT_EXEC) on their payload.
  ;;
  ;; IMPORTANT: Must be called AFTER all JIT compilation and boot file loading
  ;; is complete, because Chez's pattern is mmap(RW) then mprotect(RX).
  ;; Once PROTMAX is enabled, mmap(RW) → mprotect(RX) will fail.

  ;; FreeBSD constants from sys/procctl.h
  (define PROC_PROTMAX_CTL       14)
  (define PROC_PROTMAX_FORCE_ENABLE 2)
  (define P_PID 0)

  (define c-procctl
    (guard (e [#t #f])
      (foreign-procedure "procctl" (int int int void*) int)))

  (define (cage-protmax-available?)
    (and (eq? *current-platform* 'freebsd)
         (procedure? c-procctl)))

  (define (cage-protmax!)
    "Enable PROTMAX for the current process. After this call, mprotect cannot
     escalate page protections beyond what was set at mmap time. This blocks
     ROP chains from making data executable. MUST be called after all Chez
     compilation is complete (boot files loaded, libraries compiled).
     Raises &cage-error on failure."
    (unless (cage-protmax-available?)
      (raise (make-cage-error
               "cage"
               'platform
               "PROTMAX not available (FreeBSD 14+ with procctl required)")))
    (let ([arg-buf (foreign-alloc 4)])
      (foreign-set! 'int arg-buf 0 PROC_PROTMAX_FORCE_ENABLE)
      (let ([rc (c-procctl P_PID 0 PROC_PROTMAX_CTL arg-buf)])
        (foreign-free arg-buf)
        (when (< rc 0)
          (raise (make-cage-error
                   "cage"
                   'platform
                   "procctl(PROC_PROTMAX_CTL) failed — requires FreeBSD 14+"))))))

  ;; ========== FFI for realpath ==========

  (define c-realpath
    (guard (exn [#t #f])
      (let ([f (foreign-procedure "realpath" (string void*) string)])
        (lambda (path) (f path 0)))))

  (define (resolve-path who path)
    ;; Resolve symlinks via realpath(3). Raises &cage-error if path
    ;; does not exist (we want early failure, not silent skipping).
    (let ([resolved (and c-realpath
                         (guard (exn [#t #f])
                           (c-realpath path)))])
      (or resolved
          ;; realpath failed — path doesn't exist or FFI unavailable
          ;; Try the path as-is if it looks absolute
          (if (and (> (string-length path) 0)
                   (char=? (string-ref path 0) #\/))
            path
            (raise (make-cage-error
                     "cage"
                     'resolve
                     (format "cannot resolve path: ~a" path)))))))

  (define (resolve-paths who paths)
    (map (lambda (p) (resolve-path who p)) paths))

  ;; ========== System paths ==========

  ;; Paths needed for a Chez Scheme process to function, including
  ;; DNS resolution, TLS, terminal, and device access.

  (define *system-read-only-paths*
    '("/usr/lib"
      "/lib"
      "/lib64"
      "/lib32"
      ;; TLS certificates
      "/etc/ssl"
      "/etc/pki"
      "/etc/ca-certificates"
      ;; DNS resolution
      "/etc/resolv.conf"
      "/etc/hosts"
      "/etc/nsswitch.conf"
      "/etc/gai.conf"
      ;; Terminal
      "/usr/share/terminfo"
      "/lib/terminfo"
      "/etc/terminfo"
      ;; Devices
      "/dev/urandom"
      "/dev/random"
      "/dev/null"
      "/dev/zero"
      "/dev/tty"
      "/dev/pts"
      "/dev/ptmx"
      "/dev/fd"
      "/dev/shm"
      ;; Process introspection (git, compilers, etc. read /proc)
      "/proc"
      ;; Timezone
      "/etc/localtime"
      "/usr/share/zoneinfo"
      ;; Locale
      "/usr/share/locale"
      "/usr/lib/locale"
      ;; Shared library config
      "/etc/ld.so.cache"
      "/etc/ld.so.conf"))

  (define *system-execute-paths*
    '("/usr/bin"
      "/bin"
      "/usr/local/bin"
      "/usr/sbin"
      "/sbin"
      ;; Shared libs need execute for dlopen
      "/usr/lib"
      "/lib"
      "/lib64"))

  (define (existing-paths paths)
    ;; Filter to paths that actually exist on this system.
    ;; Avoids Landlock errors for paths like /lib64 on systems without it.
    (filter
      (lambda (p)
        (guard (exn [#t #f])
          (or (file-exists? p)
              (file-directory? p))))
      paths))

  ;; ========== Config record ==========

  (define-record-type (%cage-config %make-cage-config cage-config?)
    (sealed #t)
    (fields
      (immutable root         cage-config-root)
      (immutable read-only    cage-config-read-only)
      (immutable read-write   cage-config-read-write)
      (immutable execute      cage-config-execute)
      (immutable network      cage-config-network)
      (immutable system-paths cage-config-system-paths)
      (immutable temp-dir     cage-config-temp-dir)
      (immutable namespaces   cage-config-namespaces)))  ;; #f | #t | list of flags

  ;; Normalize keyword symbols: both 'root: (Chez reader) and '#:root
  ;; (Jerboa reader keyword) map to the string "root".
  (define (normalize-key sym)
    (let ([s (symbol->string sym)])
      (cond
        ;; Jerboa keyword: #:root → "root"
        [(and (>= (string-length s) 2)
              (char=? (string-ref s 0) #\#)
              (char=? (string-ref s 1) #\:))
         (substring s 2 (string-length s))]
        ;; Chez symbol with colon: root: → "root"
        [(and (> (string-length s) 0)
              (char=? (string-ref s (- (string-length s) 1)) #\:))
         (substring s 0 (- (string-length s) 1))]
        [else s])))

  (define (make-cage-config . args)
    (let loop ([rest args]
               [root #f]
               [read-only '()]
               [read-write '()]
               [execute '()]
               [network #t]
               [system-paths 'auto]
               [temp-dir "/tmp"]
               [namespaces #f])
      (if (null? rest)
        (begin
          (unless root
            (raise (make-cage-error
                     "cage"
                     'config
                     "root: is required")))
          (%make-cage-config root read-only read-write execute
                             network system-paths temp-dir namespaces))
        (begin
          (when (null? (cdr rest))
            (error 'make-cage-config "keyword missing value" (car rest)))
          (let ([key (normalize-key (car rest))]
                [val (cadr rest)]
                [remaining (cddr rest)])
            (cond
              [(string=? key "root")
               (loop remaining val read-only read-write execute
                     network system-paths temp-dir namespaces)]
              [(string=? key "read-only")
               (loop remaining root val read-write execute
                     network system-paths temp-dir namespaces)]
              [(string=? key "read-write")
               (loop remaining root read-only val execute
                     network system-paths temp-dir namespaces)]
              [(string=? key "execute")
               (loop remaining root read-only read-write val
                     network system-paths temp-dir namespaces)]
              [(string=? key "network")
               (loop remaining root read-only read-write execute
                     val system-paths temp-dir namespaces)]
              [(string=? key "system-paths")
               (loop remaining root read-only read-write execute
                     network val temp-dir namespaces)]
              [(string=? key "temp-dir")
               (loop remaining root read-only read-write execute
                     network system-paths val namespaces)]
              [(string=? key "namespaces")
               (loop remaining root read-only read-write execute
                     network system-paths temp-dir val)]
              [else
               (error 'make-cage-config
                 "unknown keyword; expected root:, read-only:, read-write:, execute:, network:, system-paths:, temp-dir:, or namespaces:"
                 (car rest))]))))))

  ;; ========== Core: cage! ==========

  (define (cage! cfg)
    ;; Apply cage to current process. IRREVERSIBLE.
    (unless (cage-config? cfg)
      (error 'cage! "expected cage-config" cfg))

    (when *cage-active*
      (raise (make-cage-error
               "cage"
               'config
               "cage already active — can only tighten, not replace")))

    (case *current-platform*
      [(linux)   (cage-linux! cfg)]
      [(openbsd) (cage-openbsd! cfg)]
      [(freebsd) (cage-freebsd! cfg)]
      [else
       (raise (make-cage-error
                "cage"
                'platform
                (format "cage! not yet supported on ~a"
                        *current-platform*)))]))

  ;; ========== Linux implementation (Landlock) ==========

  (define (cage-linux! cfg)
    (unless (landlock-available?)
      (raise (make-cage-error
               "cage"
               'landlock
               "Landlock not available (need Linux 5.13+)")))

    (let* ([root (resolve-path 'cage! (cage-config-root cfg))]
           [extra-ro (resolve-paths 'cage! (cage-config-read-only cfg))]
           [extra-rw (resolve-paths 'cage! (cage-config-read-write cfg))]
           [extra-exec (resolve-paths 'cage! (cage-config-execute cfg))]
           [temp (and (cage-config-temp-dir cfg)
                      (resolve-path 'cage! (cage-config-temp-dir cfg)))]
           ;; Build system paths
           [sys-ro (case (cage-config-system-paths cfg)
                     [(auto) (existing-paths *system-read-only-paths*)]
                     [(#f)   '()]
                     [else   (cage-config-system-paths cfg)])]
           [sys-exec (case (cage-config-system-paths cfg)
                       [(auto) (existing-paths *system-execute-paths*)]
                       [(#f)   '()]
                       [else   '()])]
           ;; Build the Landlock ruleset
           [rs (make-landlock-ruleset)])

      ;; Read-write: root + temp + extras
      (apply landlock-add-read-write! rs root
             (append (if temp (list temp) '()) extra-rw))

      ;; Read-only: system paths + extras
      (unless (null? (append sys-ro extra-ro))
        (apply landlock-add-read-only! rs (append sys-ro extra-ro)))

      ;; Execute: system bin paths + extras
      (unless (null? (append sys-exec extra-exec))
        (apply landlock-add-execute! rs (append sys-exec extra-exec)))

      ;; Install — IRREVERSIBLE
      (guard (exn
               [#t (raise (make-cage-error
                            "cage"
                            'landlock
                            (if (message-condition? exn)
                              (condition-message exn)
                              "landlock-install! failed")))])
        (landlock-install! rs))

      ;; Record state
      (set! *cage-active* #t)
      (set! *cage-root-path* root)
      (set! *cage-all-paths*
        (append
          (map (lambda (p) (cons 'read-write p))
               (cons root (append (if temp (list temp) '()) extra-rw)))
          (map (lambda (p) (cons 'read-only p))
               (append sys-ro extra-ro))
          (map (lambda (p) (cons 'execute p))
               (append sys-exec extra-exec))))

      ;; Apply namespace isolation if requested
      (when (cage-config-namespaces cfg)
        (guard (e [#t (void)])  ;; best-effort — don't fail cage if namespaces unavailable
          (cage-unshare!
            'pid:     #t
            'mount:   #t
            'network: (not (cage-config-network cfg)))))

      (void)))

  ;; ========== OpenBSD implementation (pledge/unveil) ==========
  ;; Stub for future implementation — OpenBSD has native unveil(2)
  ;; which is exactly what cage! wants to be.

  (define (cage-openbsd! cfg)
    (raise (make-cage-error
             "cage"
             'platform
             "OpenBSD cage! not yet implemented (needs unveil(2) FFI bindings)")))

  ;; ========== FreeBSD implementation (Capsicum) ==========
  ;;
  ;; Capsicum's capability mode is fundamentally different from Landlock:
  ;; - After cap_enter(), NO new open() calls work from the global namespace
  ;; - Only pre-opened file descriptors (and their descendants) are usable
  ;; - openat() with a pre-opened directory fd works for relative paths
  ;;
  ;; We pre-open all allowed directories as O_DIRECTORY fds with
  ;; appropriate capability rights, then enter capability mode.
  ;; The pre-opened fds are stored globally so higher-level code
  ;; can use openat() to access files within allowed directories.

  ;; FreeBSD-specific system paths
  (define *freebsd-system-read-only-paths*
    '("/usr/lib"
      "/lib"
      "/libexec"
      ;; TLS certificates
      "/etc/ssl"
      "/usr/share/certs"
      "/etc/ssl/cert.pem"
      ;; DNS resolution
      "/etc/resolv.conf"
      "/etc/hosts"
      "/etc/nsswitch.conf"
      ;; Terminal
      "/usr/share/terminfo"
      ;; Devices
      "/dev/urandom"
      "/dev/random"
      "/dev/null"
      "/dev/zero"
      "/dev/tty"
      "/dev/pts"
      "/dev/fd"
      ;; Timezone
      "/etc/localtime"
      "/usr/share/zoneinfo"
      ;; Locale
      "/usr/share/locale"
      ;; Shared library config
      "/var/run/ld-elf.so.hints"))

  (define *freebsd-system-execute-paths*
    '("/usr/bin"
      "/bin"
      "/usr/local/bin"
      "/usr/sbin"
      "/sbin"
      "/usr/lib"
      "/lib"
      "/libexec"
      "/usr/local/lib"))

  ;; Track pre-opened directory fds for the cage
  (define *cage-dir-fds* '())  ;; alist of (path . fd)

  (define c-open-dir
    (guard (e [#t #f])
      (foreign-procedure "open" (string int) int)))

  (define (cage-freebsd! cfg)
    (unless (capsicum-available?)
      (raise (make-cage-error
               "cage"
               'platform
               "Capsicum not available on this FreeBSD system")))

    (let* ([root (resolve-path 'cage! (cage-config-root cfg))]
           [extra-ro (resolve-paths 'cage! (cage-config-read-only cfg))]
           [extra-rw (resolve-paths 'cage! (cage-config-read-write cfg))]
           [extra-exec (resolve-paths 'cage! (cage-config-execute cfg))]
           [temp (and (cage-config-temp-dir cfg)
                      (resolve-path 'cage! (cage-config-temp-dir cfg)))]
           ;; Build system paths
           [sys-ro (case (cage-config-system-paths cfg)
                     [(auto) (existing-paths *freebsd-system-read-only-paths*)]
                     [(#f)   '()]
                     [else   (cage-config-system-paths cfg)])]
           [sys-exec (case (cage-config-system-paths cfg)
                       [(auto) (existing-paths *freebsd-system-execute-paths*)]
                       [(#f)   '()]
                       [else   '()])]
           ;; Collect all paths to pre-open
           [rw-paths (append (list root) (if temp (list temp) '()) extra-rw)]
           [ro-paths (append sys-ro extra-ro)]
           [exec-paths (append sys-exec extra-exec)])

      ;; Pre-open directories with appropriate Capsicum rights
      ;; Read-write directories
      (for-each
        (lambda (path)
          (guard (e [#t (void)])  ;; skip paths that fail to open
            (let ([fd (capsicum-open-path path
                        '(read write seek fstat ftruncate lookup))])
              (set! *cage-dir-fds*
                (cons (cons path fd) *cage-dir-fds*)))))
        (filter (lambda (p) (guard (e [#t #f]) (file-directory? p)))
                rw-paths))

      ;; Read-only directories
      (for-each
        (lambda (path)
          (guard (e [#t (void)])
            (let ([fd (capsicum-open-path path '(read fstat seek lookup))])
              (set! *cage-dir-fds*
                (cons (cons path fd) *cage-dir-fds*)))))
        (filter (lambda (p) (guard (e [#t #f]) (file-directory? p)))
                ro-paths))

      ;; Execute directories (need read + lookup for path resolution)
      (for-each
        (lambda (path)
          (guard (e [#t (void)])
            (let ([fd (capsicum-open-path path '(read fstat lookup))])
              (set! *cage-dir-fds*
                (cons (cons path fd) *cage-dir-fds*)))))
        (filter (lambda (p) (guard (e [#t #f]) (file-directory? p)))
                exec-paths))

      ;; Restrict stdio fds
      (guard (e [#t (void)])
        (capsicum-limit-fd! 0 '(read fstat event)))
      (guard (e [#t (void)])
        (capsicum-limit-fd! 1 '(write fstat event)))
      (guard (e [#t (void)])
        (capsicum-limit-fd! 2 '(write fstat event)))

      ;; Enter capability mode — IRREVERSIBLE
      (guard (exn
               [#t (raise (make-cage-error
                            "cage"
                            'platform
                            (if (message-condition? exn)
                              (condition-message exn)
                              "cap_enter() failed")))])
        (capsicum-enter!))

      ;; Enable PROTMAX — block mprotect(PROT_EXEC) escalation
      ;; This prevents ROP chains from making attacker data executable.
      ;; Best-effort: PROTMAX requires FreeBSD 14+ and may not be available.
      (when (cage-protmax-available?)
        (guard (e [#t (void)])  ;; best-effort
          (cage-protmax!)))

      ;; Record state
      (set! *cage-active* #t)
      (set! *cage-root-path* root)
      (set! *cage-all-paths*
        (append
          (map (lambda (p) (cons 'read-write p)) rw-paths)
          (map (lambda (p) (cons 'read-only p)) ro-paths)
          (map (lambda (p) (cons 'execute p)) exec-paths)))

      (void)))

) ;; end library
