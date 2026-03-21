#!chezscheme
;;; (std os landlock-native) — Linux Landlock via Rust/libc syscalls
;;;
;;; Replaces support/landlock-shim.c with Rust native implementation.
;;; Same public API as (std os landlock) but backed by Rust.

(library (std os landlock-native)
  (export
    landlock-available?
    landlock-abi-version
    landlock-enforce!
    ;; Low-level API for fine-grained control
    landlock-create-ruleset
    landlock-add-path-rule
    landlock-add-net-rule
    landlock-restrict-self!
    ;; Access right constants
    LANDLOCK_ACCESS_FS_EXECUTE LANDLOCK_ACCESS_FS_WRITE_FILE
    LANDLOCK_ACCESS_FS_READ_FILE LANDLOCK_ACCESS_FS_READ_DIR
    LANDLOCK_ACCESS_FS_REMOVE_DIR LANDLOCK_ACCESS_FS_REMOVE_FILE
    LANDLOCK_ACCESS_FS_MAKE_CHAR LANDLOCK_ACCESS_FS_MAKE_DIR
    LANDLOCK_ACCESS_FS_MAKE_REG LANDLOCK_ACCESS_FS_MAKE_SOCK
    LANDLOCK_ACCESS_FS_MAKE_FIFO LANDLOCK_ACCESS_FS_MAKE_BLOCK
    LANDLOCK_ACCESS_FS_MAKE_SYM LANDLOCK_ACCESS_FS_REFER
    LANDLOCK_ACCESS_FS_TRUNCATE
    LANDLOCK_ACCESS_NET_BIND_TCP LANDLOCK_ACCESS_NET_CONNECT_TCP
    ;; Condition type
    &landlock-error make-landlock-error landlock-error?
    landlock-error-reason)

  (import (chezscheme))

  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "./lib/libjerboa_native.so") #t)
        (error 'std/os/landlock-native "libjerboa_native.so not found")))

  ;; Condition type
  (define-condition-type &landlock-error &error
    make-landlock-error landlock-error?
    (reason landlock-error-reason))

  ;; Access right constants
  (define LANDLOCK_ACCESS_FS_EXECUTE      (bitwise-arithmetic-shift-left 1 0))
  (define LANDLOCK_ACCESS_FS_WRITE_FILE   (bitwise-arithmetic-shift-left 1 1))
  (define LANDLOCK_ACCESS_FS_READ_FILE    (bitwise-arithmetic-shift-left 1 2))
  (define LANDLOCK_ACCESS_FS_READ_DIR     (bitwise-arithmetic-shift-left 1 3))
  (define LANDLOCK_ACCESS_FS_REMOVE_DIR   (bitwise-arithmetic-shift-left 1 4))
  (define LANDLOCK_ACCESS_FS_REMOVE_FILE  (bitwise-arithmetic-shift-left 1 5))
  (define LANDLOCK_ACCESS_FS_MAKE_CHAR    (bitwise-arithmetic-shift-left 1 6))
  (define LANDLOCK_ACCESS_FS_MAKE_DIR     (bitwise-arithmetic-shift-left 1 7))
  (define LANDLOCK_ACCESS_FS_MAKE_REG     (bitwise-arithmetic-shift-left 1 8))
  (define LANDLOCK_ACCESS_FS_MAKE_SOCK    (bitwise-arithmetic-shift-left 1 9))
  (define LANDLOCK_ACCESS_FS_MAKE_FIFO    (bitwise-arithmetic-shift-left 1 10))
  (define LANDLOCK_ACCESS_FS_MAKE_BLOCK   (bitwise-arithmetic-shift-left 1 11))
  (define LANDLOCK_ACCESS_FS_MAKE_SYM     (bitwise-arithmetic-shift-left 1 12))
  (define LANDLOCK_ACCESS_FS_REFER        (bitwise-arithmetic-shift-left 1 13))
  (define LANDLOCK_ACCESS_FS_TRUNCATE     (bitwise-arithmetic-shift-left 1 14))

  (define LANDLOCK_ACCESS_NET_BIND_TCP    (bitwise-arithmetic-shift-left 1 0))
  (define LANDLOCK_ACCESS_NET_CONNECT_TCP (bitwise-arithmetic-shift-left 1 1))

  ;; All v1 filesystem access rights
  (define all-fs-v1
    (bitwise-ior
      LANDLOCK_ACCESS_FS_EXECUTE LANDLOCK_ACCESS_FS_WRITE_FILE
      LANDLOCK_ACCESS_FS_READ_FILE LANDLOCK_ACCESS_FS_READ_DIR
      LANDLOCK_ACCESS_FS_REMOVE_DIR LANDLOCK_ACCESS_FS_REMOVE_FILE
      LANDLOCK_ACCESS_FS_MAKE_CHAR LANDLOCK_ACCESS_FS_MAKE_DIR
      LANDLOCK_ACCESS_FS_MAKE_REG LANDLOCK_ACCESS_FS_MAKE_SOCK
      LANDLOCK_ACCESS_FS_MAKE_FIFO LANDLOCK_ACCESS_FS_MAKE_BLOCK
      LANDLOCK_ACCESS_FS_MAKE_SYM))

  ;; FFI
  (define c-landlock-abi-version
    (foreign-procedure "jerboa_landlock_abi_version" () int))
  (define c-landlock-create-ruleset
    (foreign-procedure "jerboa_landlock_create_ruleset"
      (unsigned-64 unsigned-64) int))
  (define c-landlock-add-path-rule
    (foreign-procedure "jerboa_landlock_add_path_rule"
      (int u8* size_t unsigned-64) int))
  (define c-landlock-add-net-rule
    (foreign-procedure "jerboa_landlock_add_net_rule"
      (int unsigned-64 unsigned-64) int))
  (define c-landlock-enforce
    (foreign-procedure "jerboa_landlock_enforce" (int) int))

  ;; --- Public API ---

  (define (landlock-available?)
    (>= (c-landlock-abi-version) 1))

  (define (landlock-abi-version)
    (c-landlock-abi-version))

  (define (landlock-create-ruleset fs-mask net-mask)
    (let ([fd (c-landlock-create-ruleset fs-mask net-mask)])
      (when (< fd 0)
        (raise (condition
          (make-landlock-error "create ruleset failed")
          (make-message-condition "landlock_create_ruleset syscall failed"))))
      fd))

  (define (landlock-add-path-rule ruleset-fd path access-mask)
    (let ([bv (string->utf8 path)])
      (let ([rc (c-landlock-add-path-rule ruleset-fd bv (bytevector-length bv) access-mask)])
        (when (< rc 0)
          (raise (condition
            (make-landlock-error "add path rule failed")
            (make-message-condition
              (string-append "failed to add rule for: " path)))))
        (void))))

  (define (landlock-add-net-rule ruleset-fd port access-mask)
    (let ([rc (c-landlock-add-net-rule ruleset-fd port access-mask)])
      (when (< rc 0)
        (raise (condition
          (make-landlock-error "add net rule failed")
          (make-message-condition "failed to add network rule"))))
      (void)))

  (define (landlock-restrict-self! ruleset-fd)
    (let ([rc (c-landlock-enforce ruleset-fd)])
      (when (< rc 0)
        (raise (condition
          (make-landlock-error "enforce failed")
          (make-message-condition "landlock_restrict_self failed"))))
      (void)))

  ;; High-level API matching (std os landlock)
  (define (landlock-enforce! read-paths write-paths exec-paths)
    (let ([abi (c-landlock-abi-version)])
      (if (< abi 1)
        'unsupported
        (let ([fs-mask all-fs-v1])
          (let ([ruleset (landlock-create-ruleset fs-mask 0)])
            ;; System paths for read
            (for-each
              (lambda (p)
                (guard (e [#t (void)])
                  (landlock-add-path-rule ruleset p
                    (bitwise-ior LANDLOCK_ACCESS_FS_READ_FILE
                                 LANDLOCK_ACCESS_FS_READ_DIR
                                 LANDLOCK_ACCESS_FS_EXECUTE))))
              '("/usr" "/lib" "/lib64" "/bin" "/sbin" "/etc" "/proc" "/dev"))
            ;; Read paths
            (for-each
              (lambda (p)
                (landlock-add-path-rule ruleset p
                  (bitwise-ior LANDLOCK_ACCESS_FS_READ_FILE
                               LANDLOCK_ACCESS_FS_READ_DIR)))
              read-paths)
            ;; Write paths
            (for-each
              (lambda (p)
                (landlock-add-path-rule ruleset p
                  (bitwise-ior LANDLOCK_ACCESS_FS_READ_FILE
                               LANDLOCK_ACCESS_FS_READ_DIR
                               LANDLOCK_ACCESS_FS_WRITE_FILE
                               LANDLOCK_ACCESS_FS_REMOVE_FILE
                               LANDLOCK_ACCESS_FS_REMOVE_DIR
                               LANDLOCK_ACCESS_FS_MAKE_REG
                               LANDLOCK_ACCESS_FS_MAKE_DIR)))
              write-paths)
            ;; Exec paths
            (for-each
              (lambda (p)
                (landlock-add-path-rule ruleset p
                  (bitwise-ior LANDLOCK_ACCESS_FS_READ_FILE
                               LANDLOCK_ACCESS_FS_READ_DIR
                               LANDLOCK_ACCESS_FS_EXECUTE)))
              exec-paths)
            ;; Enforce
            (landlock-restrict-self! ruleset)
            #t)))))

  ) ;; end library
