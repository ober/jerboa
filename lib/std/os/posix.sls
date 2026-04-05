#!chezscheme
;;; (std os posix) — Declarative POSIX FFI bindings
;;;
;;; Track 20: Eliminates the need for C shims by providing direct
;;; foreign-procedure calls to libc with automatic errno checking,
;;; flag constants, and struct accessors.

(library (std os posix)
  (export
    ;; Errno
    posix-errno posix-strerror
    &posix-error make-posix-error posix-error? posix-error-errno
    posix-error-syscall posix-error-message
    check-posix check-posix/ptr

    ;; Process
    posix-fork posix-execve posix-waitpid posix-exit
    posix-getpid posix-getppid
    posix-setpgid posix-getpgid
    posix-tcsetpgrp posix-tcgetpgrp
    posix-setsid

    ;; Wait status decoders
    WIFEXITED WEXITSTATUS WIFSIGNALED WTERMSIG WIFSTOPPED WSTOPSIG

    ;; File descriptors
    posix-open posix-close posix-read posix-write
    posix-dup posix-dup2 posix-pipe
    posix-fcntl-getfl posix-fcntl-setfl
    posix-lseek
    posix-mkfifo posix-unlink

    ;; Open flags
    O_RDONLY O_WRONLY O_RDWR O_CREAT O_TRUNC O_APPEND
    O_NONBLOCK O_CLOEXEC O_EXCL O_NOCTTY
    ;; Seek whence
    SEEK_SET SEEK_CUR SEEK_END

    ;; Signals
    posix-kill posix-sigprocmask posix-sigwait
    SIG_BLOCK SIG_UNBLOCK SIG_SETMASK
    ;; Signal constants re-exported
    SIGHUP SIGINT SIGQUIT SIGILL SIGTRAP SIGABRT SIGFPE SIGKILL
    SIGSEGV SIGPIPE SIGALRM SIGTERM SIGUSR1 SIGUSR2
    SIGCHLD SIGCONT SIGSTOP SIGTSTP SIGTTIN SIGTTOU
    SIGURG SIGXCPU SIGXFSZ SIGVTALRM SIGPROF SIGWINCH SIGIO SIGSYS

    ;; Terminal
    posix-isatty posix-tcgetattr posix-tcsetattr
    posix-get-terminal-size
    TCSANOW TCSADRAIN TCSAFLUSH

    ;; User/permissions
    posix-umask posix-getuid posix-geteuid posix-getegid posix-access
    posix-setuid posix-setgid posix-getgid
    ;; Directory
    posix-chdir
    ;; Access mode flags
    F_OK R_OK W_OK X_OK

    ;; Environment
    posix-setenv posix-unsetenv

    ;; Stat
    posix-stat posix-fstat posix-lstat
    stat-dev stat-ino stat-mode stat-nlink stat-uid stat-gid
    stat-size stat-mtime stat-atime stat-ctime
    stat-is-directory? stat-is-regular? stat-is-symlink?
    stat-is-fifo? stat-is-socket? stat-is-block? stat-is-char?
    free-stat

    ;; Resources
    posix-getrlimit posix-setrlimit
    RLIMIT_NOFILE RLIMIT_NPROC RLIMIT_STACK RLIMIT_CORE RLIMIT_FSIZE
    RLIMIT_AS RLIMIT_DATA

    ;; Time
    posix-strftime

    ;; Wait flags
    WNOHANG WUNTRACED WCONTINUED

    ;; define-posix macro for extension
    define-posix)

  (import (chezscheme))

  ;; ========== libc loading ==========
  ;; In static builds (musl), symbols are already linked.
  ;; In dynamic builds, load libc.
  (define _libc (or (guard (e [#t #f]) (load-shared-object "libc.so.7"))
                    (guard (e [#t #f]) (load-shared-object "libc.so.6"))
                    (guard (e [#t #f]) (load-shared-object "libc.so"))))
  (define _libc2 (guard (e [#t #f]) (load-shared-object "")))

  ;; ========== Errno ==========

  ;; errno is thread-local via __errno_location on Linux / __error on FreeBSD
  (define c-errno-location
    (guard (e [#t #f])
      (let ((mt (symbol->string (machine-type))))

        (if (or (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb))

                (and (>= (string-length mt) 3)

                     (string=? (substring mt (- (string-length mt) 3) (string-length mt)) "osx")))

          (foreign-procedure "__error" () void*)

          (foreign-procedure "__errno_location" () void*)))))

  (define (posix-errno)
    (if c-errno-location
      (foreign-ref 'int (c-errno-location) 0)
      0))

  (define c-strerror
    (foreign-procedure "strerror" (int) string))

  (define (posix-strerror errno)
    (c-strerror errno))

  ;; POSIX error condition type
  (define-condition-type &posix-error &error
    make-posix-error posix-error?
    (errno posix-error-errno)
    (syscall posix-error-syscall))

  (define (posix-error-message c)
    (if (message-condition? c)
      (condition-message c)
      ""))

  ;; Check return value; raise &posix-error on -1
  (define (check-posix syscall-name result)
    (if (= result -1)
      (let ([e (posix-errno)])
        (raise (condition
                 (make-posix-error e syscall-name)
                 (make-message-condition
                   (format "~a failed: ~a" syscall-name (posix-strerror e))))))
      result))

  ;; Check pointer return; raise on NULL
  (define (check-posix/ptr syscall-name result)
    (if (zero? result)
      (let ([e (posix-errno)])
        (raise (condition
                 (make-posix-error e syscall-name)
                 (make-message-condition
                   (format "~a failed: ~a" syscall-name (posix-strerror e))))))
      result))

  ;; ========== define-posix macro ==========
  ;; Generates a checked foreign-procedure wrapper
  (define-syntax define-posix
    (syntax-rules (->)
      [(_ name c-name (arg-type ...) -> ret-type)
       (define (name . args)
         (let ([result (apply (foreign-procedure c-name (arg-type ...) ret-type) args)])
           (check-posix 'name result)))]))

  ;; ========== Signal Constants ==========
  (define SIGHUP    1)
  (define SIGINT    2)
  (define SIGQUIT   3)
  (define SIGILL    4)
  (define SIGTRAP   5)
  (define SIGABRT   6)
  (define SIGFPE    8)
  (define SIGKILL   9)
  (define SIGSEGV  11)
  (define SIGPIPE  13)
  (define SIGALRM  14)
  (define SIGTERM  15)
  (define SIGUSR1  10)
  (define SIGUSR2  12)
  (define SIGCHLD  17)
  (define SIGCONT  18)
  (define SIGSTOP  19)
  (define SIGTSTP  20)
  (define SIGTTIN  21)
  (define SIGTTOU  22)
  (define SIGURG   23)
  (define SIGXCPU  24)
  (define SIGXFSZ  25)
  (define SIGVTALRM 26)
  (define SIGPROF  27)
  (define SIGWINCH 28)
  (define SIGIO    29)
  (define SIGSYS   31)

  ;; ========== Wait Flags ==========
  (define WNOHANG    1)
  (define WUNTRACED  2)
  (define WCONTINUED 8)

  ;; ========== Wait Status Decoders ==========
  (define (WIFEXITED s)   (= (bitwise-and s #x7f) 0))
  (define (WEXITSTATUS s) (bitwise-arithmetic-shift-right (bitwise-and s #xff00) 8))
  (define (WIFSIGNALED s)
    (let ([lo (bitwise-and s #x7f)])
      (and (not (= lo 0)) (not (= lo #x7f)))))
  (define (WTERMSIG s)    (bitwise-and s #x7f))
  (define (WIFSTOPPED s)  (= (bitwise-and s #xff) #x7f))
  (define (WSTOPSIG s)    (bitwise-arithmetic-shift-right (bitwise-and s #xff00) 8))

  ;; ========== Open Flags ==========
  ;; Values differ between Linux and FreeBSD
  (define *freebsd?* (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb)))
  (define O_RDONLY    #x0)
  (define O_WRONLY    #x1)
  (define O_RDWR      #x2)
  (define O_CREAT    (if *freebsd?* #x200    #x40))
  (define O_EXCL     (if *freebsd?* #x800    #x80))
  (define O_NOCTTY   (if *freebsd?* #x8000   #x100))
  (define O_TRUNC    (if *freebsd?* #x400    #x200))
  (define O_APPEND   (if *freebsd?* #x8      #x400))
  (define O_NONBLOCK (if *freebsd?* #x4      #x800))
  (define O_CLOEXEC  (if *freebsd?* #x100000 #x80000))

  ;; ========== Seek Constants ==========
  (define SEEK_SET 0)
  (define SEEK_CUR 1)
  (define SEEK_END 2)

  ;; ========== Access Mode Flags ==========
  (define F_OK 0)
  (define R_OK 4)
  (define W_OK 2)
  (define X_OK 1)

  ;; ========== Signal Mask Constants ==========
  ;; FreeBSD: SIG_BLOCK=1, SIG_UNBLOCK=2, SIG_SETMASK=3
  ;; Linux:   SIG_BLOCK=0, SIG_UNBLOCK=1, SIG_SETMASK=2
  (define SIG_BLOCK   (if *freebsd?* 1 0))
  (define SIG_UNBLOCK (if *freebsd?* 2 1))
  (define SIG_SETMASK (if *freebsd?* 3 2))

  ;; ========== Terminal Constants ==========
  (define TCSANOW   0)
  (define TCSADRAIN 1)
  (define TCSAFLUSH 2)

  ;; ========== Resource Limit Constants ==========
  (define RLIMIT_NOFILE  7)
  (define RLIMIT_NPROC   6)
  (define RLIMIT_STACK   3)
  (define RLIMIT_CORE    4)
  (define RLIMIT_FSIZE   1)
  (define RLIMIT_DATA    2)
  (define RLIMIT_AS      9)

  ;; ========== Process Operations ==========

  (define c-fork (foreign-procedure "fork" () int))
  (define (posix-fork)
    (check-posix 'fork (c-fork)))

  (define c-exit (foreign-procedure "_exit" (int) void))
  (define (posix-exit code)
    (c-exit code))

  ;; waitpid uses an out-pointer for status
  (define c-waitpid (foreign-procedure "waitpid" (int void* int) int))

  (define (posix-waitpid pid options)
    (let ([status-buf (foreign-alloc 4)])
      (dynamic-wind
        void
        (lambda ()
          (let ([result (c-waitpid pid status-buf options)])
            (if (= result -1)
              (let ([e (posix-errno)])
                (raise (condition
                         (make-posix-error e 'waitpid)
                         (make-message-condition
                           (format "waitpid failed: ~a" (posix-strerror e))))))
              (let ([status (foreign-ref 'int status-buf 0)])
                (values result status)))))
        (lambda ()
          (foreign-free status-buf)))))

  (define c-getpid  (foreign-procedure "getpid" () int))
  (define c-getppid (foreign-procedure "getppid" () int))
  (define (posix-getpid) (c-getpid))
  (define (posix-getppid) (c-getppid))

  (define c-setpgid (foreign-procedure "setpgid" (int int) int))
  (define (posix-setpgid pid pgid) (check-posix 'setpgid (c-setpgid pid pgid)))

  (define c-getpgid (foreign-procedure "getpgid" (int) int))
  (define (posix-getpgid pid) (check-posix 'getpgid (c-getpgid pid)))

  (define c-tcsetpgrp (foreign-procedure "tcsetpgrp" (int int) int))
  (define (posix-tcsetpgrp fd pgid) (check-posix 'tcsetpgrp (c-tcsetpgrp fd pgid)))

  (define c-tcgetpgrp (foreign-procedure "tcgetpgrp" (int) int))
  (define (posix-tcgetpgrp fd) (check-posix 'tcgetpgrp (c-tcgetpgrp fd)))

  (define c-setsid (foreign-procedure "setsid" () int))
  (define (posix-setsid) (check-posix 'setsid (c-setsid)))

  ;; execve: takes path, argv array, envp array as NULL-terminated string arrays
  ;; For now, expose the raw call; higher-level wrappers in Track 24
  (define c-execve (foreign-procedure "execve" (string void* void*) int))
  (define (posix-execve path argv-ptr envp-ptr)
    (check-posix 'execve (c-execve path argv-ptr envp-ptr)))

  ;; ========== File Descriptor Operations ==========

  (define c-open (foreign-procedure "open" (string int int) int))
  (define (posix-open path flags . rest)
    (let ([mode (if (pair? rest) (car rest) #o644)])
      (check-posix 'open (c-open path flags mode))))

  (define c-close (foreign-procedure "close" (int) int))
  (define (posix-close fd)
    (check-posix 'close (c-close fd)))

  (define c-read (foreign-procedure "read" (int u8* size_t) ssize_t))
  (define (posix-read fd buf count)
    (check-posix 'read (c-read fd buf count)))

  (define c-write (foreign-procedure "write" (int u8* size_t) ssize_t))
  (define (posix-write fd buf count)
    (check-posix 'write (c-write fd buf count)))

  (define c-dup (foreign-procedure "dup" (int) int))
  (define (posix-dup fd)
    (check-posix 'dup (c-dup fd)))

  (define c-dup2 (foreign-procedure "dup2" (int int) int))
  (define (posix-dup2 oldfd newfd)
    (check-posix 'dup2 (c-dup2 oldfd newfd)))

  (define c-pipe (foreign-procedure "pipe" (void*) int))
  (define (posix-pipe)
    (let ([buf (foreign-alloc 8)])  ;; 2 ints
      (dynamic-wind
        void
        (lambda ()
          (check-posix 'pipe (c-pipe buf))
          (values (foreign-ref 'int buf 0)
                  (foreign-ref 'int buf 4)))
        (lambda ()
          (foreign-free buf)))))

  ;; F_GETFL = 3, F_SETFL = 4
  (define c-fcntl2 (foreign-procedure "fcntl" (int int) int))
  (define c-fcntl3 (foreign-procedure "fcntl" (int int int) int))

  (define (posix-fcntl-getfl fd)
    (check-posix 'fcntl (c-fcntl2 fd 3)))

  (define (posix-fcntl-setfl fd flags)
    (check-posix 'fcntl (c-fcntl3 fd 4 flags)))

  (define c-lseek (foreign-procedure "lseek" (int long int) long))
  (define (posix-lseek fd offset whence)
    (check-posix 'lseek (c-lseek fd offset whence)))

  (define c-mkfifo (foreign-procedure "mkfifo" (string int) int))
  (define (posix-mkfifo path mode) (check-posix 'mkfifo (c-mkfifo path mode)))

  (define c-unlink (foreign-procedure "unlink" (string) int))
  (define (posix-unlink path) (check-posix 'unlink (c-unlink path)))

  ;; ========== Signal Operations ==========

  (define c-kill (foreign-procedure "kill" (int int) int))
  (define (posix-kill pid sig) (check-posix 'kill (c-kill pid sig)))

  ;; sigprocmask with sigset_t management
  ;; sigset_t: 16 bytes on FreeBSD, 128 bytes on Linux (1024 bits)
  (define SIGSET_SIZE (if *freebsd?* 16 128))

  (define c-sigemptyset (foreign-procedure "sigemptyset" (void*) int))
  (define c-sigfillset  (foreign-procedure "sigfillset" (void*) int))
  (define c-sigaddset   (foreign-procedure "sigaddset" (void* int) int))
  (define c-sigdelset   (foreign-procedure "sigdelset" (void* int) int))
  (define c-sigismember (foreign-procedure "sigismember" (void* int) int))
  (define c-sigprocmask (foreign-procedure "sigprocmask" (int void* void*) int))
  (define c-sigwait     (foreign-procedure "sigwait" (void* void*) int))

  (define (posix-sigprocmask how signals)
    ;; signals: list of signal numbers
    ;; Returns the old signal set as a list
    (let ([set (foreign-alloc SIGSET_SIZE)]
          [old (foreign-alloc SIGSET_SIZE)])
      (dynamic-wind
        void
        (lambda ()
          (c-sigemptyset set)
          (for-each (lambda (sig) (c-sigaddset set sig)) signals)
          (check-posix 'sigprocmask (c-sigprocmask how set old))
          ;; Return old set as list of blocked signals
          (let loop ([i 1] [result '()])
            (if (> i 64) (reverse result)
              (loop (+ i 1)
                    (if (= (c-sigismember old i) 1)
                      (cons i result)
                      result)))))
        (lambda ()
          (foreign-free set)
          (foreign-free old)))))

  (define (posix-sigwait signals)
    ;; Block until one of signals arrives, return its number
    (let ([set (foreign-alloc SIGSET_SIZE)]
          [sig-buf (foreign-alloc 4)])
      (dynamic-wind
        void
        (lambda ()
          (c-sigemptyset set)
          (for-each (lambda (s) (c-sigaddset set s)) signals)
          (let ([rc (c-sigwait set sig-buf)])
            (if (= rc 0)
              (foreign-ref 'int sig-buf 0)
              (raise (condition
                       (make-posix-error rc 'sigwait)
                       (make-message-condition
                         (format "sigwait failed: ~a" (posix-strerror rc))))))))
        (lambda ()
          (foreign-free set)
          (foreign-free sig-buf)))))

  ;; ========== Terminal Operations ==========

  (define c-isatty (foreign-procedure "isatty" (int) int))
  (define (posix-isatty fd) (= (c-isatty fd) 1))

  ;; termios struct is ~60 bytes on Linux; we allocate 256 to be safe
  (define TERMIOS_SIZE 256)

  (define c-tcgetattr (foreign-procedure "tcgetattr" (int void*) int))
  (define c-tcsetattr (foreign-procedure "tcsetattr" (int int void*) int))

  (define (posix-tcgetattr fd)
    ;; Returns an opaque termios bytevector
    (let ([buf (make-bytevector TERMIOS_SIZE 0)])
      (let ([ptr (foreign-alloc TERMIOS_SIZE)])
        (dynamic-wind
          void
          (lambda ()
            (check-posix 'tcgetattr (c-tcgetattr fd ptr))
            ;; Copy foreign memory to bytevector
            (do ([i 0 (+ i 1)])
                ((= i TERMIOS_SIZE))
              (bytevector-u8-set! buf i (foreign-ref 'unsigned-8 ptr i)))
            buf)
          (lambda () (foreign-free ptr))))))

  (define (posix-tcsetattr fd action termios-bv)
    ;; termios-bv is a bytevector from posix-tcgetattr
    (let ([ptr (foreign-alloc TERMIOS_SIZE)])
      (dynamic-wind
        void
        (lambda ()
          ;; Copy bytevector to foreign memory
          (do ([i 0 (+ i 1)])
              ((= i (min TERMIOS_SIZE (bytevector-length termios-bv))))
            (foreign-set! 'unsigned-8 ptr i (bytevector-u8-ref termios-bv i)))
          (check-posix 'tcsetattr (c-tcsetattr fd action ptr)))
        (lambda () (foreign-free ptr)))))

  ;; Terminal size via ioctl TIOCGWINSZ
  (define TIOCGWINSZ #x5413)  ;; Linux
  (define c-ioctl (foreign-procedure "ioctl" (int unsigned-long void*) int))

  (define (posix-get-terminal-size fd)
    ;; Returns (values rows cols)
    ;; struct winsize: unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel
    (let ([buf (foreign-alloc 8)])
      (dynamic-wind
        void
        (lambda ()
          (let ([rc (c-ioctl fd TIOCGWINSZ buf)])
            (if (= rc -1)
              (values 24 80)  ;; default
              (values (foreign-ref 'unsigned-16 buf 0)
                      (foreign-ref 'unsigned-16 buf 2)))))
        (lambda () (foreign-free buf)))))

  ;; ========== User/Permissions ==========

  (define c-umask   (foreign-procedure "umask" (int) int))
  (define (posix-umask mask) (c-umask mask))

  (define c-getuid  (foreign-procedure "getuid" () unsigned))
  (define c-geteuid (foreign-procedure "geteuid" () unsigned))
  (define c-getegid (foreign-procedure "getegid" () unsigned))
  (define (posix-getuid)  (c-getuid))
  (define (posix-geteuid) (c-geteuid))
  (define (posix-getegid) (c-getegid))

  (define c-access (foreign-procedure "access" (string int) int))
  (define (posix-access path mode) (= (c-access path mode) 0))

  (define c-setuid (foreign-procedure "setuid" (unsigned) int))
  (define (posix-setuid uid) (check-posix 'setuid (c-setuid uid)))

  (define c-setgid (foreign-procedure "setgid" (unsigned) int))
  (define (posix-setgid gid) (check-posix 'setgid (c-setgid gid)))

  (define c-getgid (foreign-procedure "getgid" () unsigned))
  (define (posix-getgid) (c-getgid))

  ;; ========== Directory ==========

  (define c-chdir (foreign-procedure "chdir" (string) int))
  (define (posix-chdir path) (check-posix 'chdir (c-chdir path)))

  ;; ========== Environment ==========

  (define c-setenv (foreign-procedure "setenv" (string string int) int))
  (define (posix-setenv name value overwrite?)
    (check-posix 'setenv (c-setenv name value (if overwrite? 1 0))))

  (define c-unsetenv (foreign-procedure "unsetenv" (string) int))
  (define (posix-unsetenv name)
    (check-posix 'unsetenv (c-unsetenv name)))

  ;; ========== Stat ==========

  ;; struct stat is ~144 bytes on Linux x86_64
  (define STAT_SIZE 256)

  (define c-stat  (foreign-procedure "stat"  (string void*) int))
  (define c-fstat (foreign-procedure "fstat" (int void*) int))
  (define c-lstat (foreign-procedure "lstat" (string void*) int))

  (define (posix-stat path)
    (let ([buf (foreign-alloc STAT_SIZE)])
      (let ([rc (c-stat path buf)])
        (if (= rc -1)
          (let ([e (posix-errno)])
            (foreign-free buf)
            (raise (condition
                     (make-posix-error e 'stat)
                     (make-message-condition
                       (format "stat ~a failed: ~a" path (posix-strerror e))))))
          buf))))

  (define (posix-fstat fd)
    (let ([buf (foreign-alloc STAT_SIZE)])
      (let ([rc (c-fstat fd buf)])
        (if (= rc -1)
          (let ([e (posix-errno)])
            (foreign-free buf)
            (raise (condition
                     (make-posix-error e 'fstat)
                     (make-message-condition
                       (format "fstat ~a failed: ~a" fd (posix-strerror e))))))
          buf))))

  (define (posix-lstat path)
    (let ([buf (foreign-alloc STAT_SIZE)])
      (let ([rc (c-lstat path buf)])
        (if (= rc -1)
          (let ([e (posix-errno)])
            (foreign-free buf)
            (raise (condition
                     (make-posix-error e 'lstat)
                     (make-message-condition
                       (format "lstat ~a failed: ~a" path (posix-strerror e))))))
          buf))))

  (define (free-stat stat-buf)
    (foreign-free stat-buf))

  ;; struct stat field offsets (first 6 fields match Linux and FreeBSD x86_64)
  (define (stat-dev buf)    (foreign-ref 'unsigned-64 buf 0))    ;; st_dev
  (define (stat-ino buf)    (foreign-ref 'unsigned-64 buf 8))    ;; st_ino
  (define (stat-nlink buf)  (foreign-ref 'unsigned-64 buf 16))   ;; st_nlink
  (define (stat-mode buf)   (foreign-ref 'unsigned-32 buf 24))   ;; st_mode
  (define (stat-uid buf)    (foreign-ref 'unsigned-32 buf 28))   ;; st_uid
  (define (stat-gid buf)    (foreign-ref 'unsigned-32 buf 32))   ;; st_gid
  ;; Remaining fields differ: FreeBSD has st_atim at 48, st_mtim at 64,
  ;; st_ctim at 80, st_size at 112. Linux has st_size at 48, st_atim at 72,
  ;; st_mtim at 88, st_ctim at 104.
  (define (stat-size buf)   (foreign-ref 'integer-64  buf (if *freebsd?* 112 48)))
  (define (stat-atime buf)  (foreign-ref 'integer-64  buf (if *freebsd?* 48 72)))
  (define (stat-mtime buf)  (foreign-ref 'integer-64  buf (if *freebsd?* 64 88)))
  (define (stat-ctime buf)  (foreign-ref 'integer-64  buf (if *freebsd?* 80 104)))

  ;; File type checks (from st_mode)
  (define S_IFMT   #o170000)
  (define S_IFDIR  #o040000)
  (define S_IFREG  #o100000)
  (define S_IFLNK  #o120000)
  (define S_IFIFO  #o010000)
  (define S_IFSOCK #o140000)
  (define S_IFBLK  #o060000)
  (define S_IFCHR  #o020000)

  (define (stat-is-directory? buf) (= (bitwise-and (stat-mode buf) S_IFMT) S_IFDIR))
  (define (stat-is-regular? buf)   (= (bitwise-and (stat-mode buf) S_IFMT) S_IFREG))
  (define (stat-is-symlink? buf)   (= (bitwise-and (stat-mode buf) S_IFMT) S_IFLNK))
  (define (stat-is-fifo? buf)      (= (bitwise-and (stat-mode buf) S_IFMT) S_IFIFO))
  (define (stat-is-socket? buf)    (= (bitwise-and (stat-mode buf) S_IFMT) S_IFSOCK))
  (define (stat-is-block? buf)     (= (bitwise-and (stat-mode buf) S_IFMT) S_IFBLK))
  (define (stat-is-char? buf)      (= (bitwise-and (stat-mode buf) S_IFMT) S_IFCHR))

  ;; ========== Resources ==========

  ;; struct rlimit { rlim_t rlim_cur, rlim_max; } — 16 bytes on x86_64
  (define c-getrlimit (foreign-procedure "getrlimit" (int void*) int))
  (define c-setrlimit (foreign-procedure "setrlimit" (int void*) int))

  (define (posix-getrlimit resource)
    ;; Returns (values soft-limit hard-limit)
    (let ([buf (foreign-alloc 16)])
      (dynamic-wind
        void
        (lambda ()
          (check-posix 'getrlimit (c-getrlimit resource buf))
          (values (foreign-ref 'unsigned-64 buf 0)
                  (foreign-ref 'unsigned-64 buf 8)))
        (lambda () (foreign-free buf)))))

  (define (posix-setrlimit resource soft hard)
    (let ([buf (foreign-alloc 16)])
      (dynamic-wind
        void
        (lambda ()
          (foreign-set! 'unsigned-64 buf 0 soft)
          (foreign-set! 'unsigned-64 buf 8 hard)
          (check-posix 'setrlimit (c-setrlimit resource buf)))
        (lambda () (foreign-free buf)))))

  ;; ========== Time ==========

  (define c-strftime  (foreign-procedure "strftime" (u8* size_t string void*) size_t))
  (define c-localtime (foreign-procedure "localtime" (void*) void*))

  (define (posix-strftime fmt epoch)
    (let ([time-buf (foreign-alloc 8)]
          [out-buf (make-bytevector 256 0)])
      (dynamic-wind
        void
        (lambda ()
          (foreign-set! 'integer-64 time-buf 0 epoch)
          (let* ([tm (c-localtime time-buf)]
                 [n (c-strftime out-buf 256 fmt tm)])
            (if (> n 0)
              (let ([result (make-bytevector n)])
                (bytevector-copy! out-buf 0 result 0 n)
                (utf8->string result))
              "")))
        (lambda () (foreign-free time-buf)))))

  ) ;; end library
