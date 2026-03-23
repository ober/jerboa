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
;;;   ;; Apply a preset (restrict fds + enter cap mode in one call):
;;;   (capsicum-apply-preset! (capsicum-compute-only-preset pipe-fd))
;;;
;;;   ;; Pre-open a path as a restricted fd:
;;;   (capsicum-open-path "/data" '(read fstat seek lookup))
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

    ;; Presets (analogous to seccomp presets)
    capsicum-compute-only-preset
    capsicum-io-only-preset
    capsicum-apply-preset!

    ;; Path pre-opening
    capsicum-open-path

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

  ;; Load libc on FreeBSD (required for cap_enter, cap_getmode, etc.)
  (define _libc
    (if (freebsd?)
      (or (guard (e [#t #f]) (load-shared-object "libc.so.7"))
          (guard (e [#t #f]) (load-shared-object "libc.so"))
          (guard (e [#t #f]) (load-shared-object "")))
      #f))

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
  ;;
  ;; From sys/capsicum.h:
  ;;   #define CAPRIGHT(idx, bit) ((1ULL << (57 + (idx))) | (bit))
  ;;   cap_rights_t = struct { uint64_t cr_rights[2]; }
  ;;   cr_rights[0] = (1 << 57) | index-0-rights
  ;;   cr_rights[1] = (1 << 58) | index-1-rights
  ;;
  ;; Each right has an index (0 or 1) and a bit value.
  ;; We store them as (index . bit) pairs for correct packing.

  ;; Index 0 rights — stored as raw bit values (no index marker)
  (define capsicum-right-read       #x0000000000000001)  ;; CAP_READ
  (define capsicum-right-write      #x0000000000000002)  ;; CAP_WRITE
  (define capsicum-right-seek       #x000000000000000c)  ;; CAP_SEEK
  (define capsicum-right-mmap       #x0000000000000010)  ;; CAP_MMAP
  (define capsicum-right-fstat      #x0000000000080000)  ;; CAP_FSTAT
  (define capsicum-right-ftruncate  #x0000000000000200)  ;; CAP_FTRUNCATE
  (define capsicum-right-lookup     #x0000000000000400)  ;; CAP_LOOKUP

  ;; Index 1 rights
  (define capsicum-right-event      #x0000000000000020)  ;; CAP_EVENT (index 1)

  ;; ========== Rights Helpers ==========

  ;; Returns (values bit-value index) for a right symbol.
  (define (symbol->right+index sym)
    (case sym
      [(read)      (values capsicum-right-read       0)]
      [(write)     (values capsicum-right-write      0)]
      [(seek)      (values capsicum-right-seek       0)]
      [(mmap)      (values capsicum-right-mmap       0)]
      [(fstat)     (values capsicum-right-fstat      0)]
      [(ftruncate) (values capsicum-right-ftruncate  0)]
      [(lookup)    (values capsicum-right-lookup     0)]
      [(event)     (values capsicum-right-event      1)]
      [else (error 'capsicum-limit-fd!
              "unknown right; expected read, write, seek, mmap, fstat, ftruncate, event, or lookup"
              sym)]))

  (define (pack-rights right-symbols)
    ;; Pack a list of right symbols into a cap_rights_t foreign structure.
    ;; Returns a foreign pointer that must be freed by the caller.
    ;;
    ;; cap_rights_t layout:
    ;;   cr_rights[0] = (1 << 57) | all index-0 right bits
    ;;   cr_rights[1] = (1 << 58) | all index-1 right bits
    (let loop ([syms right-symbols] [idx0-bits 0] [idx1-bits 0])
      (if (null? syms)
        (let ([rights-mem (foreign-alloc CAP_RIGHTS_SIZE)])
          ;; cr_rights[0]: version marker (1 << 57) | index-0 rights
          (foreign-set! 'unsigned-64 rights-mem 0
            (bitwise-ior (bitwise-arithmetic-shift-left 1 57) idx0-bits))
          ;; cr_rights[1]: version marker (1 << 58) | index-1 rights
          (foreign-set! 'unsigned-64 rights-mem 8
            (bitwise-ior (bitwise-arithmetic-shift-left 1 58) idx1-bits))
          rights-mem)
        (let-values ([(bit idx) (symbol->right+index (car syms))])
          (if (= idx 0)
            (loop (cdr syms) (bitwise-ior idx0-bits bit) idx1-bits)
            (loop (cdr syms) idx0-bits (bitwise-ior idx1-bits bit)))))))

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

  ;; ========== Path Pre-opening ==========

  ;; FreeBSD open(2) flags
  (define O_RDONLY   #x0000)
  (define O_RDWR     #x0002)
  (define O_DIRECTORY #x00020000)  ;; FreeBSD O_DIRECTORY

  (define c-open
    (if (freebsd?)
      (guard (e [#t (lambda (path flags) -1)])
        (foreign-procedure "open" (string int) int))
      (lambda (path flags) -1)))

  (define c-close
    (if (freebsd?)
      (guard (e [#t (lambda (fd) -1)])
        (foreign-procedure "close" (int) int))
      (lambda (fd) -1)))

  (define (capsicum-open-path path right-symbols)
    ;; Pre-open a path and restrict the resulting fd.
    ;; Returns the fd number (caller must track it).
    ;; The fd is restricted to the given rights via cap_rights_limit.
    ;;
    ;; If 'write is in right-symbols, opens O_RDWR; otherwise O_RDONLY.
    ;; If 'lookup is in right-symbols, adds O_DIRECTORY for directories.
    (unless (freebsd?)
      (error 'capsicum-open-path "Capsicum is only available on FreeBSD"))
    (let* ([has-write (memq 'write right-symbols)]
           [flags (if has-write O_RDWR O_RDONLY)]
           [fd (c-open path flags)])
      (when (< fd 0)
        (error 'capsicum-open-path
          (format "open(~s) failed (errno ~a)" path (get-errno))))
      ;; Restrict the fd to the requested rights
      (capsicum-limit-fd! fd right-symbols)
      fd))

  ;; ========== Presets ==========
  ;;
  ;; Presets are alists of (fd . (right-symbol ...)) that specify
  ;; how each fd should be restricted before entering capability mode.
  ;; Analogous to seccomp's compute-only-filter / io-only-filter.

  (define (capsicum-compute-only-preset pipe-fd)
    ;; Minimal preset: restrict stdio + pipe fd.
    ;; No file I/O, no network — just computation with stdio.
    ;; Analogous to seccomp compute-only-filter.
    `((0 . (read fstat))            ;; stdin: read-only
      (1 . (write fstat))           ;; stdout: write-only
      (2 . (write fstat))           ;; stderr: write-only
      (,pipe-fd . (write fstat))))  ;; pipe to parent: write-only

  (define (capsicum-io-only-preset pipe-fd extra-fds)
    ;; Like compute-only but with additional pre-opened fds.
    ;; extra-fds: list of (fd . (right-symbol ...)) pairs for
    ;; fds the caller pre-opened via capsicum-open-path.
    ;; Analogous to seccomp io-only-filter + Landlock paths.
    (append
      (capsicum-compute-only-preset pipe-fd)
      extra-fds))

  (define (capsicum-apply-preset! preset)
    ;; Apply a preset: restrict each fd then enter capability mode.
    ;; preset: alist of (fd . (right-symbol ...))
    ;;
    ;; This is the single-call entry point for Capsicum sandboxing
    ;; with per-fd restrictions. IRREVERSIBLE.
    (unless (freebsd?)
      (error 'capsicum-apply-preset! "Capsicum is only available on FreeBSD"))
    (unless (and (list? preset) (not (null? preset)))
      (error 'capsicum-apply-preset! "expected non-empty preset alist" preset))
    ;; Step 1: Restrict each fd
    (for-each
      (lambda (entry)
        (let ([fd (car entry)]
              [rights (cdr entry)])
          (capsicum-limit-fd! fd rights)))
      preset)
    ;; Step 2: Enter capability mode
    (capsicum-enter!))

  ) ;; end library
