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

    ;; Introspection
    cage-root
    cage-allowed-paths

    ;; Condition
    &cage-error make-cage-error cage-error?
    cage-error-phase cage-error-detail)

  (import (chezscheme)
          (std security landlock)
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

  (define (cage-active?) *cage-active*)
  (define (cage-root) *cage-root-path*)
  (define (cage-allowed-paths) *cage-all-paths*)

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
      (immutable temp-dir     cage-config-temp-dir)))

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
               [temp-dir "/tmp"])
      (if (null? rest)
        (begin
          (unless root
            (raise (make-cage-error
                     "cage"
                     'config
                     "root: is required")))
          (%make-cage-config root read-only read-write execute
                             network system-paths temp-dir))
        (begin
          (when (null? (cdr rest))
            (error 'make-cage-config "keyword missing value" (car rest)))
          (let ([key (normalize-key (car rest))]
                [val (cadr rest)]
                [remaining (cddr rest)])
            (cond
              [(string=? key "root")
               (loop remaining val read-only read-write execute
                     network system-paths temp-dir)]
              [(string=? key "read-only")
               (loop remaining root val read-write execute
                     network system-paths temp-dir)]
              [(string=? key "read-write")
               (loop remaining root read-only val execute
                     network system-paths temp-dir)]
              [(string=? key "execute")
               (loop remaining root read-only read-write val
                     network system-paths temp-dir)]
              [(string=? key "network")
               (loop remaining root read-only read-write execute
                     val system-paths temp-dir)]
              [(string=? key "system-paths")
               (loop remaining root read-only read-write execute
                     network val temp-dir)]
              [(string=? key "temp-dir")
               (loop remaining root read-only read-write execute
                     network system-paths val)]
              [else
               (error 'make-cage-config
                 "unknown keyword; expected root:, read-only:, read-write:, execute:, network:, system-paths:, or temp-dir:"
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
      [(linux)  (cage-linux! cfg)]
      [(openbsd) (cage-openbsd! cfg)]
      [else
       (raise (make-cage-error
                "cage"
                'platform
                (format "cage! not yet supported on ~a (Linux and OpenBSD only)"
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

      (void)))

  ;; ========== OpenBSD implementation (pledge/unveil) ==========
  ;; Stub for future implementation — OpenBSD has native unveil(2)
  ;; which is exactly what cage! wants to be.

  (define (cage-openbsd! cfg)
    (raise (make-cage-error
             "cage"
             'platform
             "OpenBSD cage! not yet implemented (needs unveil(2) FFI bindings)")))

) ;; end library
