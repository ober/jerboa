#!chezscheme
;;; (std security seatbelt) — macOS Seatbelt sandbox profiles
;;;
;;; Wraps macOS sandbox_init(3) to apply Seatbelt profiles.
;;; Profiles restrict filesystem, network, and process operations.
;;; Once applied, restrictions are IRREVERSIBLE for the process lifetime.
;;;
;;; Named profile symbols (mapped to equivalent SBPL since the
;;; legacy kSBXProfile* names were removed in modern macOS):
;;;   pure-computation — no I/O at all
;;;   no-write — read-only filesystem
;;;   no-write-except-temporary — writes only to $TMPDIR / /tmp
;;;   no-internet — no outbound IP network
;;;   no-network — no network at all (including local)
;;;
;;; Custom profiles use SBPL (Sandbox Profile Language), e.g.:
;;;   (version 1)(deny default)(allow file-read* (subpath "/usr/lib"))
;;;
;;; Usage:
;;;   ;; Apply a built-in profile:
;;;   (seatbelt-install! 'pure-computation)
;;;
;;;   ;; Apply a custom SBPL profile string:
;;;   (seatbelt-install-profile!
;;;     "(version 1)(deny default)(allow file-read* (subpath \"/usr/lib\"))")
;;;
;;;   ;; Pre-built profiles (return SBPL strings):
;;;   (seatbelt-compute-only-profile)     ; deny all except computation
;;;   (seatbelt-read-only-profile "/usr/lib" "/lib")  ; read-only access
;;;   (seatbelt-no-network-profile)       ; deny network

(library (std security seatbelt)
  (export
    ;; Installation
    seatbelt-install!
    seatbelt-install-profile!
    seatbelt-available?

    ;; Pre-built profiles (return SBPL strings)
    seatbelt-compute-only-profile
    seatbelt-read-only-profile
    seatbelt-no-network-profile
    seatbelt-no-write-profile

    ;; Path-based confinement profile (Landlock-equivalent)
    seatbelt-cage-profile
    seatbelt-macos-system-read-paths
    seatbelt-macos-system-execute-paths

    ;; Named profile symbols
    ;; 'pure-computation, 'no-write, 'no-write-except-temporary,
    ;; 'no-internet, 'no-network
    )

  (import (chezscheme))

  ;; ========== Platform Detection ==========

  (define (macos?)
    (let ([mt (symbol->string (machine-type))])
      (let loop ([i 0])
        (cond
          [(> (+ i 3) (string-length mt)) #f]
          [(string=? (substring mt i (+ i 3)) "osx") #t]
          [else (loop (+ i 1))]))))

  ;; ========== FFI ==========

  ;; Load libsystem_sandbox on macOS (required for sandbox_init)
  (define _libsandbox
    (if (macos?)
      (or (guard (e [#t #f]) (load-shared-object "libsandbox.dylib"))
          (guard (e [#t #f]) (load-shared-object "/usr/lib/libsandbox.1.dylib"))
          (guard (e [#t #f]) (load-shared-object "")))
      #f))

  ;; sandbox_init(const char *profile, uint64_t flags, char **errorbuf) -> int
  ;; Returns 0 on success, -1 on failure (errorbuf set).
  (define c-sandbox-init
    (if (macos?)
      (guard (e [#t (lambda args -1)])
        (foreign-procedure "sandbox_init" (string unsigned-64 void*) int))
      (lambda args -1)))

  ;; sandbox_free_error(char *errorbuf) -> void
  (define c-sandbox-free-error
    (if (macos?)
      (guard (e [#t (lambda (p) (void))])
        (foreign-procedure "sandbox_free_error" (void*) void))
      (lambda (p) (void))))

  ;; sandbox_init with a raw SBPL string uses flags = 0
  ;; sandbox_init with a named profile uses SANDBOX_NAMED = 1
  (define SANDBOX_NAMED 1)

  ;; ========== Availability ==========

  (define (seatbelt-available?)
    ;; Seatbelt is available on macOS. We check by verifying the platform
    ;; and that sandbox_init can be resolved.
    (and (macos?)
         (guard (e [#t #f])
           (let ([p (foreign-entry? "sandbox_init")])
             p))))

  ;; ========== Named Profile Map ==========
  ;;
  ;; Apple's `kSBXProfile*` named profiles were deprecated in macOS 10.7
  ;; and no longer load on modern macOS (sandbox_init returns "profile
  ;; not found"). We map the same symbols to equivalent SBPL strings
  ;; so the API keeps working across versions.

  (define (named-profile-sbpl sym)
    (case sym
      [(pure-computation)
       ;; Deny everything except basic process operation
       "(version 1)(deny default)(allow mach-lookup)(allow signal)(allow sysctl-read)"]
      [(no-write)
       "(version 1)(allow default)(deny file-write*)"]
      [(no-write-except-temporary)
       ;; Allow writes only under $TMPDIR / /tmp / /private/tmp / /private/var/folders
       (string-append
         "(version 1)"
         "(allow default)"
         "(deny file-write*)"
         "(allow file-write* "
         "(subpath \"/tmp\") "
         "(subpath \"/private/tmp\") "
         "(subpath \"/var/folders\") "
         "(subpath \"/private/var/folders\")"
         (let ([t (getenv "TMPDIR")])
           (if (and (string? t) (positive? (string-length t)))
             (format " (subpath ~s)" t)
             ""))
         ")")]
      [(no-internet)
       "(version 1)(allow default)(deny network-outbound (remote ip))"]
      [(no-network)
       "(version 1)(allow default)(deny network*)"]
      [else (error 'seatbelt-install!
              "unknown named profile; expected pure-computation, no-write, no-write-except-temporary, no-internet, or no-network"
              sym)]))

  ;; ========== Installation ==========

  (define (seatbelt-install! profile-sym)
    ;; Install a named Seatbelt profile. IRREVERSIBLE.
    ;; profile-sym: one of 'pure-computation, 'no-write,
    ;;   'no-write-except-temporary, 'no-internet, 'no-network
    ;;
    ;; Since the kSBXProfile* names are removed in modern macOS, this
    ;; expands the symbol to an equivalent SBPL string and applies that.
    (unless (macos?)
      (error 'seatbelt-install! "Seatbelt is only available on macOS"))
    (seatbelt-install-profile! (named-profile-sbpl profile-sym)))

  (define (seatbelt-install-profile! sbpl-string)
    ;; Install a custom SBPL profile string. IRREVERSIBLE.
    ;; sbpl-string: raw Seatbelt Profile Language string, e.g.:
    ;;   "(version 1)(deny default)(allow file-read* (subpath \"/usr/lib\"))"
    (unless (macos?)
      (error 'seatbelt-install-profile! "Seatbelt is only available on macOS"))
    (unless (string? sbpl-string)
      (error 'seatbelt-install-profile! "expected SBPL string" sbpl-string))
    (let ([errptr (foreign-alloc 8)])
      (foreign-set! 'void* errptr 0 0)
      (dynamic-wind
        (lambda () (void))
        (lambda ()
          (let ([rc (c-sandbox-init sbpl-string 0 errptr)])
            (when (< rc 0)
              (let ([errmsg (foreign-ref 'void* errptr 0)])
                (let ([msg (if (= errmsg 0)
                             "sandbox_init failed (unknown error)"
                             (let ([s (foreign-ref 'string errmsg 0)])
                               (c-sandbox-free-error errmsg)
                               (format "sandbox_init failed: ~a" s)))])
                  (error 'seatbelt-install-profile! msg))))))
        (lambda ()
          (foreign-free errptr)))))

  ;; ========== Pre-built SBPL Profiles ==========

  (define (seatbelt-compute-only-profile)
    ;; Deny everything except pure computation.
    ;; Equivalent to seccomp compute-only filter.
    "(version 1)(deny default)(allow mach-lookup)(allow signal)(allow sysctl-read)")

  (define (seatbelt-read-only-profile . paths)
    ;; Allow read-only access to specified paths (and system libraries).
    ;; Denies writes, network, and process operations.
    (let ([subpaths (apply string-append
                     (map (lambda (p)
                            (format "(subpath ~s)" p))
                          (append '("/usr/lib" "/usr/share" "/System"
                                    "/Library/Frameworks"
                                    "/private/var/db/dyld")
                                  paths)))])
      (string-append
        "(version 1)"
        "(deny default)"
        "(allow file-read* " subpaths ")"
        "(allow mach-lookup)"
        "(allow signal)"
        "(allow sysctl-read)"
        "(allow process-exec)")))

  (define (seatbelt-no-network-profile)
    ;; Allow everything except network access.
    ;; Equivalent to seccomp io-only filter.
    "(version 1)(allow default)(deny network*)")

  (define (seatbelt-no-write-profile . read-paths)
    ;; Allow reads everywhere (or specific paths), deny all writes.
    (if (null? read-paths)
      "(version 1)(allow default)(deny file-write*)"
      (let ([subpaths (apply string-append
                       (map (lambda (p) (format "(subpath ~s)" p))
                            read-paths))])
        (string-append
          "(version 1)"
          "(deny default)"
          "(allow file-read* " subpaths ")"
          "(allow mach-lookup)"
          "(allow signal)"
          "(allow sysctl-read)"))))

  ;; ========== macOS System Paths ==========
  ;;
  ;; Paths a Chez Scheme process needs to function on macOS:
  ;; dyld, system frameworks, TLS roots, DNS, terminal, devices.
  ;; macOS symlinks /etc, /tmp, /var to /private/etc, /private/tmp,
  ;; /private/var — we list both forms so realpath resolution works
  ;; either way.

  (define seatbelt-macos-system-read-paths
    '(;; System libraries and frameworks
      "/usr/lib"
      "/usr/local/lib"
      "/usr/share"
      "/System/Library"
      "/Library/Frameworks"
      "/Library/Apple"
      ;; dyld shared cache
      "/private/var/db/dyld"
      ;; TLS certificate roots
      "/etc/ssl"
      "/private/etc/ssl"
      "/private/var/db/mds"
      ;; DNS resolution / hosts
      "/etc/resolv.conf"
      "/etc/hosts"
      "/etc/services"
      "/private/etc/resolv.conf"
      "/private/etc/hosts"
      "/private/etc/services"
      ;; Terminal
      "/usr/share/terminfo"
      ;; Timezone / locale
      "/etc/localtime"
      "/private/etc/localtime"
      "/usr/share/zoneinfo"
      "/var/db/timezone"
      "/private/var/db/timezone"
      ;; Devices
      "/dev/null"
      "/dev/zero"
      "/dev/random"
      "/dev/urandom"
      "/dev/tty"
      "/dev/dtracehelper"))

  (define seatbelt-macos-system-execute-paths
    '("/usr/bin"
      "/bin"
      "/usr/local/bin"
      "/usr/sbin"
      "/sbin"
      "/usr/libexec"
      ;; Frameworks contain executable Mach-O binaries
      "/System/Library"
      "/Library/Frameworks"
      "/usr/lib"))

  ;; ========== Cage profile builder ==========
  ;;
  ;; Build an SBPL profile that mimics Landlock-style path confinement:
  ;;   - Read+write access to a list of paths (e.g. project root, $TMPDIR)
  ;;   - Read-only access to a list of paths (e.g. system libs, configs)
  ;;   - Execute access to a list of paths (e.g. /usr/bin)
  ;;   - Optional network access
  ;;
  ;; macOS Seatbelt always denies by default in this profile, then
  ;; whitelists specific operations. The result is roughly equivalent
  ;; to a Landlock ruleset on Linux.
  ;;
  ;; Operations needed for any usable Chez Scheme process are always
  ;; allowed: mach-lookup, signal, sysctl-read, process-fork,
  ;; ipc-posix-shm*, file-ioctl (terminal). These are not security-
  ;; relevant on macOS — the relevant restrictions are filesystem and
  ;; network.

  (define (sbpl-quote-path p)
    ;; Quote a path for inclusion in SBPL. format ~s gives "..." with
    ;; escaped backslashes/quotes, which matches SBPL string syntax.
    (format "~s" p))

  (define (subpath-form p)
    (string-append "(subpath " (sbpl-quote-path p) ")"))

  (define (literal-form p)
    (string-append "(literal " (sbpl-quote-path p) ")"))

  (define (path-form p)
    ;; A directory becomes (subpath ...), anything else (literal ...).
    ;; subpath also matches the directory itself, so it's a strict
    ;; superset for directory paths.
    (if (guard (e [#t #f]) (file-directory? p))
      (subpath-form p)
      (literal-form p)))

  (define (paths->sbpl-forms paths)
    (apply string-append
      (map (lambda (p) (string-append " " (path-form p))) paths)))

  (define (seatbelt-cage-profile . opts)
    ;; Build an SBPL profile from path lists.
    ;;
    ;; Keywords (any order):
    ;;   read-write: '("/path" ...)   ;; full read+write+create+delete
    ;;   read-only:  '("/path" ...)   ;; read access only
    ;;   execute:    '("/path" ...)   ;; process-exec from these paths
    ;;   network:    #t | #f          ;; allow outbound/inbound network
    ;;
    ;; Returns an SBPL string suitable for seatbelt-install-profile!.
    (let loop ([rest opts]
               [rw '()]
               [ro '()]
               [exec '()]
               [network #t])
      (cond
        [(null? rest)
         (build-cage-sbpl rw ro exec network)]
        [(null? (cdr rest))
         (error 'seatbelt-cage-profile "keyword missing value" (car rest))]
        [else
         (let ([key (cage-key->string (car rest))]
               [val (cadr rest)]
               [more (cddr rest)])
           (cond
             [(string=? key "read-write")
              (loop more val ro exec network)]
             [(string=? key "read-only")
              (loop more rw val exec network)]
             [(string=? key "execute")
              (loop more rw ro val network)]
             [(string=? key "network")
              (loop more rw ro exec val)]
             [else
              (error 'seatbelt-cage-profile
                "unknown keyword; expected read-write:, read-only:, execute:, or network:"
                (car rest))]))])))

  (define (cage-key->string sym)
    (let ([s (symbol->string sym)])
      (cond
        [(and (>= (string-length s) 2)
              (char=? (string-ref s 0) #\#)
              (char=? (string-ref s 1) #\:))
         (substring s 2 (string-length s))]
        [(and (> (string-length s) 0)
              (char=? (string-ref s (- (string-length s) 1)) #\:))
         (substring s 0 (- (string-length s) 1))]
        [else s])))

  (define (build-cage-sbpl rw-paths ro-paths exec-paths network?)
    ;; Read access covers: all read-only paths AND all read-write paths
    ;; (write access without read access is rarely useful, and Chez
    ;; needs to read its boot files anyway).
    (let* ([all-readable (append ro-paths rw-paths)]
           [read-forms  (paths->sbpl-forms all-readable)]
           [write-forms (paths->sbpl-forms rw-paths)]
           [exec-forms  (paths->sbpl-forms exec-paths)])
      (string-append
        "(version 1)"
        "(deny default)"
        ;; Always-allowed operations needed for basic process function.
        "(allow process-fork)"
        "(allow signal (target self))"
        "(allow sysctl-read)"
        "(allow mach-lookup)"
        "(allow ipc-posix-shm*)"
        "(allow file-ioctl)"
        "(allow file-read-metadata)"
        ;; Read access
        (if (null? all-readable)
          ""
          (string-append "(allow file-read*" read-forms ")"))
        ;; Write access (read-write paths only)
        (if (null? rw-paths)
          ""
          (string-append "(allow file-write*" write-forms ")"))
        ;; Execute access
        (if (null? exec-paths)
          ""
          (string-append "(allow process-exec*" exec-forms ")"))
        ;; Network
        (if network?
          "(allow network*)"
          ""))))

  ) ;; end library
