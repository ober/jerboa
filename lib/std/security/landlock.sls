#!chezscheme
;;; (std security landlock) — Landlock filesystem access control
;;;
;;; Linux 5.13+ filesystem sandboxing without root privileges.
;;; Restricts filesystem access to explicitly allowed paths.
;;; Rules are irreversible — can only tighten after installation.
;;;
;;; REAL IMPLEMENTATION: Uses actual landlock_create_ruleset,
;;; landlock_add_rule, landlock_restrict_self syscalls via foreign memory.

(library (std security landlock)
  (export
    ;; Rule construction
    make-landlock-ruleset
    landlock-ruleset?
    landlock-add-read-only!
    landlock-add-read-write!
    landlock-add-execute!

    ;; Installation
    landlock-install!
    landlock-available?

    ;; Convenience
    with-landlock

    ;; Pre-built rulesets
    make-readonly-ruleset
    make-tmpdir-ruleset)

  (import (chezscheme))

  ;; ========== FFI ==========

  ;; Syscall numbers (x86_64 Linux)
  (define SYS_landlock_create_ruleset 444)
  (define SYS_landlock_add_rule 445)
  (define SYS_landlock_restrict_self 446)

  ;; We need syscall() with pointer-sized args (long = 8 bytes on x86_64)
  (define c-syscall
    (guard (e [#t (lambda args -1)])
      (foreign-procedure "syscall" (long long long long) long)))

  (define c-open
    (guard (e [#t (lambda args -1)])
      (foreign-procedure "open" (string int) int)))

  (define c-close
    (guard (e [#t (lambda args -1)])
      (foreign-procedure "close" (int) int)))

  (define c-prctl
    (guard (e [#t (lambda args -1)])
      (foreign-procedure "prctl" (int int int int int) int)))

  (define c-errno
    (guard (e [#t (lambda () 0)])
      (foreign-procedure "__errno_location" () void*)))

  (define (get-errno)
    (guard (e [#t 0])
      (let ([loc (c-errno)])
        (if (= loc 0) 0
            (foreign-ref 'int loc 0)))))

  ;; Landlock access rights for files/dirs
  (define LANDLOCK_ACCESS_FS_EXECUTE          #x1)
  (define LANDLOCK_ACCESS_FS_WRITE_FILE       #x2)
  (define LANDLOCK_ACCESS_FS_READ_FILE        #x4)
  (define LANDLOCK_ACCESS_FS_READ_DIR         #x8)
  (define LANDLOCK_ACCESS_FS_REMOVE_DIR       #x10)
  (define LANDLOCK_ACCESS_FS_REMOVE_FILE      #x20)
  (define LANDLOCK_ACCESS_FS_MAKE_CHAR        #x40)
  (define LANDLOCK_ACCESS_FS_MAKE_DIR         #x80)
  (define LANDLOCK_ACCESS_FS_MAKE_REG         #x100)
  (define LANDLOCK_ACCESS_FS_MAKE_SOCK        #x200)
  (define LANDLOCK_ACCESS_FS_MAKE_FIFO        #x400)
  (define LANDLOCK_ACCESS_FS_MAKE_BLOCK       #x800)
  (define LANDLOCK_ACCESS_FS_MAKE_SYM         #x1000)
  (define LANDLOCK_ACCESS_FS_REFER            #x2000)
  (define LANDLOCK_ACCESS_FS_TRUNCATE         #x4000)

  ;; ABI v1 access rights (supported on all Landlock kernels)
  (define LANDLOCK_ACCESS_FS_V1
    (bitwise-ior
      LANDLOCK_ACCESS_FS_EXECUTE
      LANDLOCK_ACCESS_FS_WRITE_FILE
      LANDLOCK_ACCESS_FS_READ_FILE
      LANDLOCK_ACCESS_FS_READ_DIR
      LANDLOCK_ACCESS_FS_REMOVE_DIR
      LANDLOCK_ACCESS_FS_REMOVE_FILE
      LANDLOCK_ACCESS_FS_MAKE_CHAR
      LANDLOCK_ACCESS_FS_MAKE_DIR
      LANDLOCK_ACCESS_FS_MAKE_REG
      LANDLOCK_ACCESS_FS_MAKE_SOCK
      LANDLOCK_ACCESS_FS_MAKE_FIFO
      LANDLOCK_ACCESS_FS_MAKE_BLOCK
      LANDLOCK_ACCESS_FS_MAKE_SYM))

  ;; ABI v2+ additions
  (define LANDLOCK_ACCESS_FS_V2
    (bitwise-ior LANDLOCK_ACCESS_FS_V1 LANDLOCK_ACCESS_FS_REFER))

  ;; ABI v3+ additions
  (define LANDLOCK_ACCESS_FS_V3
    (bitwise-ior LANDLOCK_ACCESS_FS_V2 LANDLOCK_ACCESS_FS_TRUNCATE))

  (define READ_ONLY_ACCESS
    (bitwise-ior LANDLOCK_ACCESS_FS_READ_FILE LANDLOCK_ACCESS_FS_READ_DIR))

  (define READ_WRITE_ACCESS
    (bitwise-ior
      LANDLOCK_ACCESS_FS_READ_FILE
      LANDLOCK_ACCESS_FS_READ_DIR
      LANDLOCK_ACCESS_FS_WRITE_FILE
      LANDLOCK_ACCESS_FS_MAKE_REG
      LANDLOCK_ACCESS_FS_MAKE_DIR
      LANDLOCK_ACCESS_FS_REMOVE_FILE
      LANDLOCK_ACCESS_FS_REMOVE_DIR
      LANDLOCK_ACCESS_FS_TRUNCATE))

  ;; O_PATH for opening paths without access
  (define O_PATH #x200000)

  ;; Rule type
  (define LANDLOCK_RULE_PATH_BENEATH 1)

  ;; prctl
  (define PR_SET_NO_NEW_PRIVS 38)

  ;; ========== ABI version detection ==========

  ;; landlock_create_ruleset(NULL, 0, LANDLOCK_CREATE_RULESET_VERSION)
  ;; returns the highest ABI version supported by the kernel.
  (define LANDLOCK_CREATE_RULESET_VERSION 1)

  (define (landlock-abi-version)
    ;; Returns the Landlock ABI version (1, 2, 3, ...) or 0 if not available.
    (let ([ver (c-syscall SYS_landlock_create_ruleset 0 0
                          LANDLOCK_CREATE_RULESET_VERSION)])
      (if (< ver 0) 0 ver)))

  ;; ========== Ruleset Record ==========

  (define-record-type (landlock-ruleset %make-landlock-ruleset landlock-ruleset?)
    (sealed #t)
    (fields
      (mutable rules %landlock-rules %landlock-set-rules!)
      (mutable installed? %landlock-installed? %landlock-set-installed!)))

  (define (make-landlock-ruleset)
    (%make-landlock-ruleset '() #f))

  ;; ========== Rule Addition ==========

  (define (landlock-add-read-only! ruleset . paths)
    (when (%landlock-installed? ruleset)
      (error 'landlock-add-read-only! "ruleset already installed"))
    (for-each
      (lambda (path)
        (%landlock-set-rules! ruleset
          (cons (list 'read-only path READ_ONLY_ACCESS)
                (%landlock-rules ruleset))))
      paths))

  (define (landlock-add-read-write! ruleset . paths)
    (when (%landlock-installed? ruleset)
      (error 'landlock-add-read-write! "ruleset already installed"))
    (for-each
      (lambda (path)
        (%landlock-set-rules! ruleset
          (cons (list 'read-write path READ_WRITE_ACCESS)
                (%landlock-rules ruleset))))
      paths))

  (define (landlock-add-execute! ruleset . paths)
    (when (%landlock-installed? ruleset)
      (error 'landlock-add-execute! "ruleset already installed"))
    (for-each
      (lambda (path)
        (%landlock-set-rules! ruleset
          (cons (list 'execute path
                      (bitwise-ior LANDLOCK_ACCESS_FS_EXECUTE
                                   LANDLOCK_ACCESS_FS_READ_FILE))
                (%landlock-rules ruleset))))
      paths))

  ;; ========== Availability ==========

  (define (landlock-available?)
    ;; Probe the kernel for Landlock support via ABI version query.
    (> (landlock-abi-version) 0))

  ;; ========== Foreign memory helpers ==========

  ;; Pack struct landlock_ruleset_attr (ABI v1: 8 bytes)
  ;; { __u64 handled_access_fs; }
  (define RULESET_ATTR_SIZE 8)

  ;; Pack struct landlock_path_beneath_attr (12 bytes, packed)
  ;; { __u64 allowed_access; __s32 parent_fd; }
  (define PATH_BENEATH_ATTR_SIZE 12)

  ;; ========== Installation ==========

  (define (landlock-install! ruleset)
    ;; Install the Landlock ruleset. IRREVERSIBLE.
    ;; This makes REAL kernel syscalls that restrict the process.
    (when (%landlock-installed? ruleset)
      (error 'landlock-install! "ruleset already installed"))

    (let ([abi (landlock-abi-version)])
      (when (= abi 0)
        (error 'landlock-install!
          "Landlock not available on this kernel (need Linux 5.13+)"))

      ;; Determine which access rights the kernel supports
      (let ([handled-fs (cond
                          [(>= abi 3) LANDLOCK_ACCESS_FS_V3]
                          [(>= abi 2) LANDLOCK_ACCESS_FS_V2]
                          [else       LANDLOCK_ACCESS_FS_V1])])

        ;; Step 1: Create ruleset fd
        ;; Pack struct landlock_ruleset_attr
        (let ([attr-mem (foreign-alloc RULESET_ATTR_SIZE)])
          (foreign-set! 'unsigned-64 attr-mem 0 handled-fs)
          (let ([ruleset-fd (c-syscall SYS_landlock_create_ruleset
                                       attr-mem RULESET_ATTR_SIZE 0)])
            (foreign-free attr-mem)
            (when (< ruleset-fd 0)
              (error 'landlock-install!
                (format "landlock_create_ruleset failed (errno ~a)" (get-errno))))

            ;; Step 2: Add rules for each path
            ;; Pack struct landlock_path_beneath_attr for each rule
            (let ([rule-mem (foreign-alloc PATH_BENEATH_ATTR_SIZE)])
              (dynamic-wind
                (lambda () (void))
                (lambda ()
                  (for-each
                    (lambda (rule)
                      (let* ([path    (cadr rule)]
                             [access  (caddr rule)]
                             ;; Mask access rights to what kernel supports
                             [masked  (bitwise-and access handled-fs)]
                             ;; Open the path with O_PATH (no actual I/O access needed)
                             [path-fd (c-open path O_PATH)])
                        (when (< path-fd 0)
                          (c-close ruleset-fd)
                          (foreign-free rule-mem)
                          (error 'landlock-install!
                            (format "cannot open path ~a (errno ~a)" path (get-errno))))
                        ;; Pack path_beneath_attr: { u64 allowed_access, s32 parent_fd }
                        (foreign-set! 'unsigned-64 rule-mem 0 masked)
                        (foreign-set! 'integer-32  rule-mem 8 path-fd)
                        (let ([rc (c-syscall SYS_landlock_add_rule
                                            ruleset-fd
                                            LANDLOCK_RULE_PATH_BENEATH
                                            rule-mem
                                            0)])
                          (c-close path-fd)
                          (when (< rc 0)
                            (c-close ruleset-fd)
                            (foreign-free rule-mem)
                            (error 'landlock-install!
                              (format "landlock_add_rule failed for ~a (errno ~a)"
                                      path (get-errno)))))))
                    (%landlock-rules ruleset)))
                (lambda ()
                  (foreign-free rule-mem))))

            ;; Step 3: Set NO_NEW_PRIVS (required before restrict_self)
            (let ([rc (c-prctl PR_SET_NO_NEW_PRIVS 1 0 0 0)])
              (when (< rc 0)
                (c-close ruleset-fd)
                (error 'landlock-install!
                  "prctl(PR_SET_NO_NEW_PRIVS) failed")))

            ;; Step 4: Restrict self — IRREVERSIBLE
            (let ([rc (c-syscall SYS_landlock_restrict_self ruleset-fd 0 0)])
              (c-close ruleset-fd)
              (when (< rc 0)
                (error 'landlock-install!
                  (format "landlock_restrict_self failed (errno ~a)" (get-errno)))))

            ;; Mark as installed
            (%landlock-set-installed! ruleset #t))))))

  ;; ========== Convenience ==========

  (define-syntax with-landlock
    (syntax-rules ()
      [(_ ruleset body ...)
       (begin
         (landlock-install! ruleset)
         body ...)]))

  ;; ========== Pre-built Rulesets ==========

  (define (make-readonly-ruleset . paths)
    ;; Create a ruleset that only allows reading the given paths.
    (let ([rs (make-landlock-ruleset)])
      (for-each (lambda (p) (landlock-add-read-only! rs p)) paths)
      rs))

  (define (make-tmpdir-ruleset base-dir)
    ;; Read-only system libs + read-write in base-dir.
    (let ([rs (make-landlock-ruleset)])
      (landlock-add-read-only! rs "/usr/lib" "/lib" "/etc/ssl")
      (landlock-add-read-write! rs base-dir)
      (landlock-add-execute! rs "/usr/bin" "/bin")
      rs))

  ) ;; end library
