#!chezscheme
;;; (std security seatbelt) — macOS Seatbelt sandbox profiles
;;;
;;; Wraps macOS sandbox_init(3) to apply Seatbelt profiles.
;;; Profiles restrict filesystem, network, and process operations.
;;; Once applied, restrictions are IRREVERSIBLE for the process lifetime.
;;;
;;; macOS provides built-in named profiles:
;;;   kSBXProfilePureComputation — no I/O at all
;;;   kSBXProfileNoWrite — read-only filesystem
;;;   kSBXProfileNoWriteExceptTemporary — writes only to $TMPDIR
;;;   kSBXProfileNoInternet — no outbound network
;;;   kSBXProfileNoNetwork — no network at all (including local)
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

  (define (named-profile-string sym)
    (case sym
      [(pure-computation)          "kSBXProfilePureComputation"]
      [(no-write)                  "kSBXProfileNoWrite"]
      [(no-write-except-temporary) "kSBXProfileNoWriteExceptTemporary"]
      [(no-internet)               "kSBXProfileNoInternet"]
      [(no-network)                "kSBXProfileNoNetwork"]
      [else (error 'seatbelt-install!
              "unknown named profile; expected pure-computation, no-write, no-write-except-temporary, no-internet, or no-network"
              sym)]))

  ;; ========== Installation ==========

  (define (seatbelt-install! profile-sym)
    ;; Install a named Seatbelt profile. IRREVERSIBLE.
    ;; profile-sym: one of 'pure-computation, 'no-write,
    ;;   'no-write-except-temporary, 'no-internet, 'no-network
    (unless (macos?)
      (error 'seatbelt-install! "Seatbelt is only available on macOS"))
    (let* ([profile-name (named-profile-string profile-sym)]
           [errptr (foreign-alloc 8)])
      (foreign-set! 'void* errptr 0 0)
      (dynamic-wind
        (lambda () (void))
        (lambda ()
          (let ([rc (c-sandbox-init profile-name SANDBOX_NAMED errptr)])
            (when (< rc 0)
              (let ([errmsg (foreign-ref 'void* errptr 0)])
                (let ([msg (if (= errmsg 0)
                             "sandbox_init failed (unknown error)"
                             (let ([s (foreign-ref 'string errmsg 0)])
                               (c-sandbox-free-error errmsg)
                               (format "sandbox_init failed: ~a" s)))])
                  (error 'seatbelt-install! msg))))))
        (lambda ()
          (foreign-free errptr)))))

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

  ) ;; end library
