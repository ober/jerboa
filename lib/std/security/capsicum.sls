#!chezscheme
;;; (std security capsicum) — FreeBSD Capsicum capability mode
;;;
;;; Wraps FreeBSD's Capsicum framework for process sandboxing.
;;; cap_enter(2) puts the process into capability mode — IRREVERSIBLE.
;;; In capability mode:
;;;   - No new file descriptors from the global namespace (no open, connect, etc.)
;;;   - Only operations on pre-opened file descriptors
;;;   - File descriptors can be further restricted with cap_rights_limit(2)
;;;
;;; This is a fundamentally different model from Linux Landlock/seccomp:
;;;   - Landlock: path-based filesystem restrictions
;;;   - seccomp: syscall filtering
;;;   - Capsicum: capability-based fd restrictions
;;;
;;; Usage:
;;;   ;; Enter capability mode (irreversible):
;;;   (capsicum-enter!)
;;;
;;;   ;; Restrict an fd to read-only before entering capability mode:
;;;   (capsicum-limit-fd! fd '(read))
;;;
;;;   ;; Check availability:
;;;   (capsicum-available?)

(library (std security capsicum)
  (export
    ;; Capability mode
    capsicum-enter!
    capsicum-available?
    capsicum-in-capability-mode?

    ;; FD rights management
    capsicum-limit-fd!

    ;; Rights constants
    capsicum-right-read
    capsicum-right-write
    capsicum-right-seek
    capsicum-right-mmap
    capsicum-right-fstat
    capsicum-right-ftruncate
    capsicum-right-event
    capsicum-right-lookup)

  (import (chezscheme))

  ;; ========== Platform Detection ==========

  (define (freebsd?)
    (let ([mt (symbol->string (machine-type))])
      (let loop ([i 0])
        (cond
          [(> (+ i 2) (string-length mt)) #f]
          [(string=? (substring mt i (+ i 2)) "fb") #t]
          [else (loop (+ i 1))]))))

  ;; ========== FFI ==========

  ;; cap_enter(void) -> int  (0 on success, -1 on error)
  (define c-cap-enter
    (if (freebsd?)
      (guard (e [#t (lambda () -1)])
        (foreign-procedure "cap_enter" () int))
      (lambda () -1)))

  ;; cap_getmode(u_int *modep) -> int
  (define c-cap-getmode
    (if (freebsd?)
      (guard (e [#t (lambda (p) -1)])
        (foreign-procedure "cap_getmode" (void*) int))
      (lambda (p) -1)))

  ;; cap_rights_limit(int fd, const cap_rights_t *rights) -> int
  (define c-cap-rights-limit
    (if (freebsd?)
      (guard (e [#t (lambda (fd rights) -1)])
        (foreign-procedure "cap_rights_limit" (int void*) int))
      (lambda (fd rights) -1)))

  ;; cap_rights_init(cap_rights_t *rights, ...) -> cap_rights_t*
  ;; We can't use variadic FFI directly. Instead we'll use
  ;; __cap_rights_init with version and rights array.
  ;; cap_rights_t on FreeBSD is: struct { uint64_t cr_rights[CAP_RIGHTS_VERSION + 2]; }
  ;; CAP_RIGHTS_VERSION = 0, so cr_rights[2] = 16 bytes
  (define CAP_RIGHTS_VERSION 0)
  (define CAP_RIGHTS_SIZE 16)  ;; 2 * uint64_t

  ;; errno on FreeBSD
  (define c-errno
    (if (freebsd?)
      (guard (e [#t (lambda () 0)])
        (foreign-procedure "__error" () void*))
      (lambda () 0)))

  (define (get-errno)
    (guard (e [#t 0])
      (let ([loc (c-errno)])
        (if (= loc 0) 0
            (foreign-ref 'int loc 0)))))

  ;; ========== Capsicum Rights Constants ==========
  ;; From sys/capsicum.h — these are bit positions in the rights bitmask

  ;; Index 0 rights (general operations)
  (define capsicum-right-read       (bitwise-arithmetic-shift-left 1 57))   ;; CAP_READ
  (define capsicum-right-write      (bitwise-arithmetic-shift-left 1 58))   ;; CAP_WRITE
  (define capsicum-right-seek       (bitwise-arithmetic-shift-left 1 11))   ;; CAP_SEEK
  (define capsicum-right-mmap       (bitwise-arithmetic-shift-left 1 24))   ;; CAP_MMAP
  (define capsicum-right-fstat      (bitwise-arithmetic-shift-left 1 40))   ;; CAP_FSTAT
  (define capsicum-right-ftruncate  (bitwise-arithmetic-shift-left 1 42))   ;; CAP_FTRUNCATE
  (define capsicum-right-event      (bitwise-arithmetic-shift-left 1 46))   ;; CAP_EVENT
  (define capsicum-right-lookup     (bitwise-arithmetic-shift-left 1 56))   ;; CAP_LOOKUP

  ;; ========== Rights Helpers ==========

  (define (symbol->right sym)
    (case sym
      [(read)      capsicum-right-read]
      [(write)     capsicum-right-write]
      [(seek)      capsicum-right-seek]
      [(mmap)      capsicum-right-mmap]
      [(fstat)     capsicum-right-fstat]
      [(ftruncate) capsicum-right-ftruncate]
      [(event)     capsicum-right-event]
      [(lookup)    capsicum-right-lookup]
      [else (error 'capsicum-limit-fd!
              "unknown right; expected read, write, seek, mmap, fstat, ftruncate, event, or lookup"
              sym)]))

  (define (pack-rights right-symbols)
    ;; Pack a list of right symbols into a cap_rights_t foreign structure.
    ;; Returns a foreign pointer that must be freed by the caller.
    (let ([rights-mem (foreign-alloc CAP_RIGHTS_SIZE)]
          [mask (fold-left
                  (lambda (acc sym) (bitwise-ior acc (symbol->right sym)))
                  0
                  right-symbols)])
      ;; cap_rights_t = { cr_rights[0] = version_and_rights, cr_rights[1] = 0 }
      ;; cr_rights[0] bits 57..62 encode the version (CAP_RIGHTS_VERSION = 0)
      ;; The actual rights are OR'd in
      (foreign-set! 'unsigned-64 rights-mem 0
        (bitwise-ior
          (bitwise-arithmetic-shift-left (+ CAP_RIGHTS_VERSION 2) 57)
          mask))
      (foreign-set! 'unsigned-64 rights-mem 8 0)
      rights-mem))

  ;; ========== Availability ==========

  (define (capsicum-available?)
    ;; Capsicum is available on FreeBSD 10+.
    (and (freebsd?)
         (guard (e [#t #f])
           (foreign-entry? "cap_enter"))))

  ;; ========== Capability Mode ==========

  (define (capsicum-enter!)
    ;; Enter Capsicum capability mode. IRREVERSIBLE.
    ;; After this call, the process cannot:
    ;;   - Open new files/directories from the global namespace
    ;;   - Create new sockets
    ;;   - Access any path not reachable from pre-opened descriptors
    ;;
    ;; Pre-open any needed file descriptors BEFORE calling this.
    (unless (freebsd?)
      (error 'capsicum-enter! "Capsicum is only available on FreeBSD"))
    (let ([rc (c-cap-enter)])
      (when (< rc 0)
        (error 'capsicum-enter!
          (format "cap_enter(2) failed (errno ~a)" (get-errno))))))

  (define (capsicum-in-capability-mode?)
    ;; Check if the process is already in capability mode.
    (if (not (freebsd?))
      #f
      (let ([buf (foreign-alloc 4)])
        (dynamic-wind
          (lambda () (void))
          (lambda ()
            (let ([rc (c-cap-getmode buf)])
              (and (>= rc 0)
                   (= (foreign-ref 'unsigned-32 buf 0) 1))))
          (lambda ()
            (foreign-free buf))))))

  ;; ========== FD Rights Restriction ==========

  (define (capsicum-limit-fd! fd right-symbols)
    ;; Restrict an fd to only the specified operations.
    ;; right-symbols: list of symbols from: read, write, seek, mmap,
    ;;                fstat, ftruncate, event, lookup
    ;;
    ;; This is IRREVERSIBLE — rights can only be narrowed, never widened.
    ;; Must be called BEFORE capsicum-enter! for fds you want to keep.
    ;;
    ;; Example:
    ;;   (capsicum-limit-fd! my-fd '(read fstat))  ; read-only
    (unless (freebsd?)
      (error 'capsicum-limit-fd! "Capsicum is only available on FreeBSD"))
    (unless (and (list? right-symbols) (not (null? right-symbols)))
      (error 'capsicum-limit-fd! "expected non-empty list of right symbols"
             right-symbols))
    (let ([rights-mem (pack-rights right-symbols)])
      (dynamic-wind
        (lambda () (void))
        (lambda ()
          (let ([rc (c-cap-rights-limit fd rights-mem)])
            (when (< rc 0)
              (error 'capsicum-limit-fd!
                (format "cap_rights_limit(2) failed for fd ~a (errno ~a)"
                        fd (get-errno))))))
        (lambda ()
          (foreign-free rights-mem)))))

  ) ;; end library
