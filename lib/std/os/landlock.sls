#!chezscheme
;;; (std os landlock) — Linux Landlock filesystem sandboxing
;;;
;;; Kernel-enforced filesystem access restrictions via Linux Landlock LSM.
;;; Once applied, restrictions are PERMANENT and IRREVERSIBLE for the
;;; process and all its children. This is real enforcement, not advisory.
;;;
;;; Requires: Linux 5.13+ with CONFIG_SECURITY_LANDLOCK=y
;;;           support/landlock-shim.c compiled and linked (or loaded)
;;;
;;; For static binaries: register symbols via Sforeign_symbol():
;;;   Sforeign_symbol("jerboa_landlock_abi_version", (void*)jerboa_landlock_abi_version);
;;;   Sforeign_symbol("jerboa_landlock_sandbox", (void*)jerboa_landlock_sandbox);
;;;
;;; For dynamic binaries: compile and load the shared library:
;;;   gcc -shared -fPIC -O2 -o libjerboa-landlock.so support/landlock-shim.c
;;;   Then (load-shared-object "./libjerboa-landlock.so") before importing.

(library (std os landlock)
  (export
    landlock-available?
    landlock-abi-version
    landlock-enforce!

    ;; Condition type for enforcement failures
    &landlock-error make-landlock-error landlock-error?
    landlock-error-reason)

  (import (chezscheme))

  ;; ========== Condition Type ==========

  (define-condition-type &landlock-error &error
    make-landlock-error landlock-error?
    (reason landlock-error-reason))

  ;; ========== FFI Bindings ==========
  ;; These call into support/landlock-shim.c

  (define c-landlock-abi-version
    (foreign-procedure "jerboa_landlock_abi_version" () int))

  (define c-landlock-sandbox
    (foreign-procedure "jerboa_landlock_sandbox"
      (string string string) int))

  ;; ========== Public API ==========

  ;; Check if Landlock is supported by the running kernel.
  (define (landlock-available?)
    (>= (c-landlock-abi-version) 1))

  ;; Return the Landlock ABI version (1-6+), or -1 if unsupported.
  (define (landlock-abi-version)
    (c-landlock-abi-version))

  ;; Apply Landlock restrictions to the current process.
  ;;
  ;; read-paths:  list of paths to allow read-only access
  ;; write-paths: list of paths to allow read+write access
  ;; exec-paths:  list of paths to allow execute access
  ;;
  ;; System paths (/usr, /lib, /bin, /etc, /proc, /dev) are always
  ;; allowed for read so that exec and basic operations work.
  ;;
  ;; Returns #t on success.
  ;; Raises &landlock-error on failure.
  ;; Returns 'unsupported if kernel doesn't support Landlock.
  ;;
  ;; WARNING: This is PERMANENT. Once called, the process can NEVER
  ;; regain access to restricted paths. There is no undo.
  (define (landlock-enforce! read-paths write-paths exec-paths)
    (let ((packed-read  (pack-paths read-paths))
          (packed-write (pack-paths write-paths))
          (packed-exec  (pack-paths exec-paths)))
      (let ((ret (c-landlock-sandbox packed-read packed-write packed-exec)))
        (cond
          ((= ret 0) #t)
          ((= ret 1) 'unsupported)
          (else
           (raise (condition
                    (make-landlock-error "Landlock enforcement failed")
                    (make-message-condition
                      "Failed to apply Landlock restrictions"))))))))

  ;; ========== Internal Helpers ==========

  ;; Pack a list of path strings with SOH (\x01) separator for C FFI.
  (define (pack-paths lst)
    (if (or (not lst) (null? lst)) ""
      (let loop ((rest (cdr lst)) (acc (car lst)))
        (if (null? rest) acc
          (loop (cdr rest)
                (string-append acc (string #\x1) (car rest)))))))

  ) ;; end library
