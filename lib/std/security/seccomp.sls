#!chezscheme
;;; (std security seccomp) — seccomp-BPF syscall filtering
;;;
;;; Restrict available system calls for sandboxed workers.
;;; Uses Linux seccomp-BPF via prctl(2) and seccomp(2).
;;; Filters are irreversible — once installed, can only tighten.
;;;
;;; REAL IMPLEMENTATION: Generates actual BPF bytecode and installs
;;; it via the seccomp(2) syscall. Includes architecture validation
;;; to prevent syscall number confusion attacks.

(library (std security seccomp)
  (export
    ;; Filter construction
    make-seccomp-filter
    seccomp-filter?
    seccomp-filter-default-action
    seccomp-filter-allowed-syscalls

    ;; Installation
    seccomp-install!
    seccomp-available?

    ;; Pre-built filters
    compute-only-filter
    network-server-filter
    io-only-filter

    ;; Actions
    seccomp-kill
    seccomp-trap
    seccomp-errno
    seccomp-log)

  (import (chezscheme))

  ;; ========== FFI ==========

  (define c-prctl
    (guard (e [#t (lambda args -1)])
      (foreign-procedure "prctl" (int int int int int) int)))

  ;; syscall with pointer-compatible args (long = 8 bytes on x86_64)
  (define c-syscall
    (guard (e [#t (lambda args -1)])
      (foreign-procedure "syscall" (long long long long) long)))

  (define c-errno
    (guard (e [#t (lambda () 0)])
      (if (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb))
        (foreign-procedure "__error" () void*)
        (foreign-procedure "__errno_location" () void*))))

  (define (get-errno)
    (guard (e [#t 0])
      (let ([loc (c-errno)])
        (if (= loc 0) 0
            (foreign-ref 'int loc 0)))))

  ;; ========== Architecture Detection ==========

  ;; Architecture validation constants
  ;; AUDIT_ARCH_X86_64 = 0xC000003E (EM_X86_64 | __AUDIT_ARCH_64BIT | __AUDIT_ARCH_LE)
  ;; AUDIT_ARCH_AARCH64 = 0xC00000B7 (EM_AARCH64 | __AUDIT_ARCH_64BIT | __AUDIT_ARCH_LE)
  (define AUDIT_ARCH_X86_64  #xC000003E)
  (define AUDIT_ARCH_AARCH64 #xC00000B7)

  ;; Detect current architecture at load time
  (define *current-arch*
    (case (machine-type)
      [(a6le ta6le)     'x86_64]
      [(arm64le)        'aarch64]
      [else             'x86_64]))  ;; conservative default

  (define (current-audit-arch)
    (case *current-arch*
      [(x86_64)  AUDIT_ARCH_X86_64]
      [(aarch64) AUDIT_ARCH_AARCH64]
      [else      AUDIT_ARCH_X86_64]))

  ;; prctl constants
  (define PR_SET_NO_NEW_PRIVS 38)

  ;; seccomp syscall number (architecture-dependent)
  (define SYS_seccomp
    (case *current-arch*
      [(aarch64) 277]
      [else      317]))  ;; x86_64

  ;; seccomp operations
  (define SECCOMP_SET_MODE_FILTER 1)

  ;; seccomp actions (for BPF return values)
  (define SECCOMP_RET_KILL_PROCESS #x80000000)
  (define SECCOMP_RET_KILL_THREAD  #x00000000)
  (define SECCOMP_RET_TRAP         #x00030000)
  (define SECCOMP_RET_ERRNO        #x00050000)
  (define SECCOMP_RET_LOG          #x7ffc0000)
  (define SECCOMP_RET_ALLOW        #x7fff0000)

  ;; ========== BPF Constants ==========

  ;; BPF instruction classes
  (define BPF_LD   #x00)
  (define BPF_JMP  #x05)
  (define BPF_RET  #x06)

  ;; BPF ld/st sizes
  (define BPF_W    #x00)  ;; 32-bit word

  ;; BPF ld/st modes
  (define BPF_ABS  #x20)  ;; absolute offset into seccomp_data

  ;; BPF jump operations
  (define BPF_JEQ  #x10)

  ;; BPF source
  (define BPF_K    #x00)  ;; immediate value

  ;; seccomp_data offsets
  (define SECCOMP_DATA_NR   0)  ;; offset of syscall number (int, 4 bytes)
  (define SECCOMP_DATA_ARCH 4)  ;; offset of architecture (u32, 4 bytes)

  ;; ========== BPF Instruction Encoding ==========
  ;;
  ;; struct sock_filter { u16 code; u8 jt; u8 jf; u32 k; }
  ;; Total: 8 bytes per instruction
  ;;
  ;; struct sock_fprog { u16 len; <6 bytes pad>; void* filter; }
  ;; Total: 16 bytes on x86_64

  (define BPF_INSN_SIZE 8)
  (define SOCK_FPROG_SIZE 16)

  (define (pack-bpf-insn! mem offset code jt jf k)
    ;; Pack one BPF instruction at the given offset in foreign memory.
    (foreign-set! 'unsigned-16 mem offset code)
    (foreign-set! 'unsigned-8  mem (+ offset 2) jt)
    (foreign-set! 'unsigned-8  mem (+ offset 3) jf)
    (foreign-set! 'unsigned-32 mem (+ offset 4) k))

  (define (bpf-stmt code k)
    ;; Return (code jt jf k) for a BPF statement (no jumps).
    (list code 0 0 k))

  (define (bpf-jump code k jt jf)
    ;; Return (code jt jf k) for a BPF jump.
    (list code jt jf k))

  ;; ========== BPF Program Generation ==========
  ;;
  ;; Generate a BPF program that:
  ;; 1. Validates architecture is x86_64 (prevents syscall confusion)
  ;; 2. Loads syscall number
  ;; 3. For each allowed syscall: jump to ALLOW
  ;; 4. Default action (kill/trap/errno)
  ;;
  ;; Program structure:
  ;;   [0]   LOAD arch
  ;;   [1]   JEQ AUDIT_ARCH_X86_64 → skip, else → KILL
  ;;   [2]   RET KILL (wrong arch)
  ;;   [3]   LOAD syscall_nr
  ;;   [4..N+3]   JEQ syscall_i → ALLOW
  ;;   [N+4] RET default_action
  ;;   [N+5] RET ALLOW

  (define (generate-bpf-program allowed-syscall-numbers default-action)
    ;; Returns a list of (code jt jf k) instruction tuples.
    (let* ([n (length allowed-syscall-numbers)]
           ;; After the arch check (3 insns) + load nr (1 insn), the JEQ chain starts at index 4.
           ;; The ALLOW return is at index (n + 5), default at (n + 4).
           ;; From JEQ at index (4 + i), jump-true to ALLOW = (n + 5) - (4 + i) - 1 = n - i
           ;; jump-false = 0 (fall through to next JEQ)
           [insns
             (append
               ;; [0] Load architecture from seccomp_data
               (list (bpf-stmt (bitwise-ior BPF_LD BPF_W BPF_ABS)
                               SECCOMP_DATA_ARCH))
               ;; [1] Check arch matches current platform; if yes skip 1, if no fall through to kill
               (list (bpf-jump (bitwise-ior BPF_JMP BPF_JEQ BPF_K)
                               (current-audit-arch)
                               1    ;; jt: skip 1 instruction (over the kill)
                               0))  ;; jf: fall through to kill
               ;; [2] Kill on wrong architecture
               (list (bpf-stmt (bitwise-ior BPF_RET BPF_K)
                               SECCOMP_RET_KILL_PROCESS))
               ;; [3] Load syscall number
               (list (bpf-stmt (bitwise-ior BPF_LD BPF_W BPF_ABS)
                               SECCOMP_DATA_NR))
               ;; [4..N+3] JEQ for each allowed syscall
               (let loop ([syscalls allowed-syscall-numbers] [i 0] [acc '()])
                 (if (null? syscalls)
                   (reverse acc)
                   (loop (cdr syscalls) (+ i 1)
                         (cons (bpf-jump (bitwise-ior BPF_JMP BPF_JEQ BPF_K)
                                         (car syscalls)
                                         (- n i)  ;; jt: jump to ALLOW
                                         0)        ;; jf: fall through
                               acc))))
               ;; [N+4] Default action
               (list (bpf-stmt (bitwise-ior BPF_RET BPF_K) default-action))
               ;; [N+5] ALLOW
               (list (bpf-stmt (bitwise-ior BPF_RET BPF_K) SECCOMP_RET_ALLOW)))])
      insns))

  ;; ========== Syscall Tables ==========

  ;; x86_64 syscall numbers (Linux)
  (define *syscall-table-x86_64*
    '((read . 0) (write . 1) (close . 3) (fstat . 5)
      (mmap . 9) (mprotect . 10) (munmap . 11) (brk . 12)
      (rt_sigaction . 13) (rt_sigprocmask . 14) (rt_sigreturn . 15)
      (ioctl . 16) (access . 21) (pipe . 22)
      (select . 23) (sched_yield . 24)
      (mremap . 25) (madvise . 28) (nanosleep . 35)
      (getpid . 39) (socket . 41) (connect . 42)
      (accept . 43) (sendto . 44) (recvfrom . 45)
      (bind . 49) (listen . 50) (getsockname . 51)
      (setsockopt . 54) (clone . 56) (fork . 57)
      (execve . 59) (exit . 60) (wait4 . 61)
      (kill . 62) (uname . 63) (fcntl . 72)
      (ftruncate . 77) (getdents . 78) (getcwd . 79)
      (chdir . 80) (rename . 82) (mkdir . 83)
      (rmdir . 84) (creat . 85) (link . 86)
      (unlink . 87) (readlink . 89)
      (gettimeofday . 96) (getuid . 102)
      (getgid . 104) (setuid . 105) (setgid . 106)
      (getppid . 110) (setsid . 112)
      (sigaltstack . 131) (prctl . 157) (arch_prctl . 158)
      (futex . 202) (clock_gettime . 228)
      (set_tid_address . 218) (exit_group . 231)
      (epoll_create1 . 291) (epoll_ctl . 233) (epoll_wait . 232)
      (openat . 257) (newfstatat . 262)
      (set_robust_list . 273) (getrandom . 318)
      (rseq . 334) (clone3 . 435)
      (close_range . 436) (prlimit64 . 302)))

  ;; aarch64 (ARM64) syscall numbers (Linux)
  ;; ARM64 uses a clean numbering starting from the generic Linux asm-generic/unistd.h.
  ;; Many legacy x86_64 syscalls (fork, access, pipe, select, etc.) don't exist on ARM64;
  ;; their modern replacements (clone, faccessat, pipe2, pselect6, etc.) are used instead.
  (define *syscall-table-aarch64*
    '((read . 63) (write . 64) (close . 57) (fstat . 80)
      (mmap . 222) (mprotect . 226) (munmap . 215) (brk . 214)
      (rt_sigaction . 134) (rt_sigprocmask . 135) (rt_sigreturn . 139)
      (ioctl . 29) (access . 439) (pipe . 59)       ;; access=faccessat2, pipe=pipe2
      (select . 72) (sched_yield . 124)              ;; select=pselect6
      (mremap . 216) (madvise . 233) (nanosleep . 101)
      (getpid . 172) (socket . 198) (connect . 203)
      (accept . 202) (sendto . 206) (recvfrom . 207)
      (bind . 200) (listen . 201) (getsockname . 204)
      (setsockopt . 208) (clone . 220) (fork . 220)  ;; ARM64: use clone for fork
      (execve . 221) (exit . 93) (wait4 . 260)
      (kill . 129) (uname . 160) (fcntl . 25)
      (ftruncate . 46) (getdents . 61) (getcwd . 17)
      (chdir . 49) (rename . 38) (mkdir . 34)        ;; rename=renameat, mkdir=mkdirat
      (rmdir . 35) (creat . 56) (link . 37)          ;; rmdir=unlinkat, link=linkat
      (unlink . 35) (readlink . 78)                   ;; unlink=unlinkat, readlink=readlinkat
      (gettimeofday . 169) (getuid . 174)
      (getgid . 176) (setuid . 146) (setgid . 144)
      (getppid . 173) (setsid . 157)
      (sigaltstack . 132) (prctl . 167) (arch_prctl . 167)  ;; no arch_prctl on ARM64, map to prctl
      (futex . 98) (clock_gettime . 113)
      (set_tid_address . 96) (exit_group . 94)
      (epoll_create1 . 20) (epoll_ctl . 21) (epoll_wait . 22)  ;; epoll_wait=epoll_pwait
      (openat . 56) (newfstatat . 79)
      (set_robust_list . 99) (getrandom . 278)
      (rseq . 293) (clone3 . 435)
      (close_range . 436) (prlimit64 . 261)))

  ;; Select table based on detected architecture
  (define *syscall-table*
    (case *current-arch*
      [(aarch64) *syscall-table-aarch64*]
      [else      *syscall-table-x86_64*]))

  (define (syscall-name->number name)
    (let ([pair (assq name *syscall-table*)])
      (if pair
        (cdr pair)
        (error 'syscall-name->number
          (format "unknown syscall name: ~a (arch: ~a)" name *current-arch*)))))

  ;; ========== Action Constructors ==========

  (define seccomp-kill   SECCOMP_RET_KILL_PROCESS)
  (define seccomp-trap   SECCOMP_RET_TRAP)
  (define (seccomp-errno errno-val) (bitwise-ior SECCOMP_RET_ERRNO (bitwise-and errno-val #xffff)))
  (define seccomp-log    SECCOMP_RET_LOG)

  ;; ========== Filter Record ==========

  (define-record-type (seccomp-filter %make-seccomp-filter seccomp-filter?)
    (sealed #t)
    (fields
      (immutable default-action seccomp-filter-default-action)
      (immutable allowed-syscalls seccomp-filter-allowed-syscalls)))

  (define (make-seccomp-filter default-action . allowed)
    ;; allowed: list of syscall name symbols
    (%make-seccomp-filter default-action allowed))

  ;; ========== Availability Check ==========

  (define (seccomp-available?)
    ;; Check if seccomp is supported by trying prctl(PR_SET_NO_NEW_PRIVS).
    ;; This is idempotent and always succeeds on modern Linux.
    (and (file-exists? "/proc/self/status")
         (>= (c-prctl PR_SET_NO_NEW_PRIVS 1 0 0 0) 0)))

  ;; ========== Installation ==========

  (define (seccomp-install! filter)
    ;; Install a seccomp-BPF filter. This is IRREVERSIBLE.
    ;; After installation, only syscalls in the allowed list are permitted.
    ;; Generates real BPF bytecode and installs via seccomp(2) syscall.
    (unless (seccomp-filter? filter)
      (error 'seccomp-install! "expected seccomp-filter"))

    ;; Step 1: Set NO_NEW_PRIVS (required before seccomp filter)
    (let ([rc (c-prctl PR_SET_NO_NEW_PRIVS 1 0 0 0)])
      (when (< rc 0)
        (error 'seccomp-install!
          "prctl(PR_SET_NO_NEW_PRIVS) failed — kernel too old?")))

    ;; Step 2: Resolve syscall names to numbers
    (let* ([syscall-names (seccomp-filter-allowed-syscalls filter)]
           [syscall-numbers (map syscall-name->number syscall-names)]
           [default-action (seccomp-filter-default-action filter)])

      ;; Step 3: Generate BPF program
      (let* ([insns (generate-bpf-program syscall-numbers default-action)]
             [num-insns (length insns)]
             [filter-size (* num-insns BPF_INSN_SIZE)])

        ;; Step 4: Allocate foreign memory and pack BPF instructions
        (let ([filter-mem (foreign-alloc filter-size)]
              [fprog-mem  (foreign-alloc SOCK_FPROG_SIZE)])
          (dynamic-wind
            (lambda () (void))
            (lambda ()
              ;; Pack each BPF instruction
              (let loop ([insn-list insns] [offset 0])
                (unless (null? insn-list)
                  (let ([insn (car insn-list)])
                    (pack-bpf-insn! filter-mem offset
                      (list-ref insn 0)   ;; code
                      (list-ref insn 1)   ;; jt
                      (list-ref insn 2)   ;; jf
                      (list-ref insn 3))) ;; k
                  (loop (cdr insn-list) (+ offset BPF_INSN_SIZE))))

              ;; Pack sock_fprog: { u16 len, <pad>, void* filter }
              ;; On x86_64: len at offset 0 (u16), filter pointer at offset 8
              ;; Zero the whole struct first to clear padding
              (let clear ([i 0])
                (when (< i SOCK_FPROG_SIZE)
                  (foreign-set! 'unsigned-8 fprog-mem i 0)
                  (clear (+ i 1))))
              (foreign-set! 'unsigned-16 fprog-mem 0 num-insns)
              (foreign-set! 'void*       fprog-mem 8 filter-mem)

              ;; Step 5: Install the BPF filter via seccomp(2) syscall
              ;; seccomp(SECCOMP_SET_MODE_FILTER, 0, &fprog)
              (let ([rc (c-syscall SYS_seccomp SECCOMP_SET_MODE_FILTER 0 fprog-mem)])
                (when (< rc 0)
                  (error 'seccomp-install!
                    (format "seccomp(SECCOMP_SET_MODE_FILTER) failed (errno ~a)"
                            (get-errno))))))
            (lambda ()
              ;; Always free memory
              (foreign-free filter-mem)
              (foreign-free fprog-mem)))))))

  ;; ========== Pre-built Filters ==========

  (define compute-only-filter
    (make-seccomp-filter seccomp-kill
      'read 'write 'close 'fstat 'mmap 'mprotect
      'munmap 'brk 'rt_sigaction 'rt_sigprocmask 'rt_sigreturn
      'clone 'exit_group 'futex 'nanosleep
      'getrandom 'arch_prctl 'set_tid_address
      'set_robust_list 'sched_yield 'sigaltstack
      'clock_gettime 'prctl 'prlimit64 'rseq 'close_range))

  (define network-server-filter
    (make-seccomp-filter seccomp-kill
      ;; Compute basics
      'read 'write 'close 'fstat 'mmap 'mprotect
      'munmap 'brk 'rt_sigaction 'rt_sigprocmask 'rt_sigreturn
      'clone 'exit_group 'futex 'nanosleep
      'getrandom 'arch_prctl 'set_tid_address
      'set_robust_list 'sched_yield 'sigaltstack
      'clock_gettime 'prctl 'prlimit64 'rseq 'close_range
      ;; Network
      'socket 'connect 'accept 'sendto 'recvfrom
      'bind 'listen 'getsockname 'setsockopt
      'select 'ioctl 'fcntl
      'epoll_create1 'epoll_ctl 'epoll_wait
      ;; File I/O
      'openat 'newfstatat 'getdents 'access))

  (define io-only-filter
    (make-seccomp-filter seccomp-kill
      'read 'write 'close 'fstat 'mmap 'mprotect
      'munmap 'brk 'rt_sigaction 'rt_sigprocmask 'rt_sigreturn
      'clone 'exit_group 'futex 'nanosleep
      'getrandom 'arch_prctl 'set_tid_address
      'set_robust_list 'sigaltstack
      'clock_gettime 'prctl 'prlimit64 'rseq 'close_range
      ;; File I/O only — no network
      'openat 'newfstatat 'getdents 'access
      'getcwd 'fcntl))

  ) ;; end library
