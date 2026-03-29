#!chezscheme
;;; :std/os/signal -- POSIX signal constants, kill(2), and handler registration

(library (std os signal)
  (export
    SIGHUP SIGINT SIGQUIT SIGILL SIGTRAP SIGABRT SIGFPE SIGKILL
    SIGSEGV SIGPIPE SIGALRM SIGTERM SIGUSR1 SIGUSR2
    SIGCHLD SIGCONT SIGSTOP SIGTSTP SIGTTIN SIGTTOU
    SIGURG SIGXCPU SIGXFSZ SIGVTALRM SIGPROF SIGWINCH SIGIO SIGSYS
    kill
    signal-names
    add-signal-handler!
    remove-signal-handler!)

  (import (chezscheme))

  ;; Ensure libc is loaded for foreign-procedure lookups.
  ;; In static builds (musl), dlopen is unavailable — libc symbols are
  ;; already linked into the binary, so this is safely skipped.
  (define libc (or (guard (e [#t #f]) (load-shared-object "libc.so.7"))
                   (guard (e [#t #f]) (load-shared-object "libc.so.6"))
                   (guard (e [#t #f]) (load-shared-object "libc.so"))))

  ;; POSIX kill(pid, sig)
  (define kill (foreign-procedure "kill" (int int) int))

  ;; Signal numbers that are the same on Linux and FreeBSD
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
  (define SIGTTIN  21)
  (define SIGTTOU  22)
  (define SIGXCPU  24)
  (define SIGXFSZ  25)
  (define SIGVTALRM 26)
  (define SIGPROF  27)
  (define SIGWINCH 28)

  ;; Signal numbers that differ between Linux and FreeBSD.
  ;; Detect platform at load time via uname.
  (define %freebsd?
    (or (guard (e [#t #f])
          (equal? (machine-type) 'ta6fb))
        (guard (e [#t #f])
          (memq (machine-type) '(ta6fb a6fb ti3fb i3fb tarm64fb arm64fb)))
        ;; Fallback for static builds: check for FreeBSD kernel file
        (guard (e [#t #f])
          (file-exists? "/boot/kernel/kernel"))
        #f))

  (define SIGUSR1  (if %freebsd? 30 10))
  (define SIGUSR2  (if %freebsd? 31 12))
  (define SIGSYS   (if %freebsd? 12 31))
  (define SIGURG   (if %freebsd? 16 23))
  (define SIGSTOP  (if %freebsd? 17 19))
  (define SIGTSTP  (if %freebsd? 18 20))
  (define SIGCONT  (if %freebsd? 19 18))
  (define SIGCHLD  (if %freebsd? 20 17))
  (define SIGIO    (if %freebsd? 23 29))

  (define signal-names
    `((1 . "SIGHUP") (2 . "SIGINT") (3 . "SIGQUIT") (4 . "SIGILL")
      (5 . "SIGTRAP") (6 . "SIGABRT") (8 . "SIGFPE") (9 . "SIGKILL")
      (,SIGUSR1 . "SIGUSR1") (11 . "SIGSEGV") (,SIGUSR2 . "SIGUSR2")
      (13 . "SIGPIPE") (14 . "SIGALRM") (15 . "SIGTERM")
      (,SIGCHLD . "SIGCHLD") (,SIGCONT . "SIGCONT")
      (,SIGSTOP . "SIGSTOP") (,SIGTSTP . "SIGTSTP")
      (21 . "SIGTTIN") (22 . "SIGTTOU")
      (,SIGURG . "SIGURG") (24 . "SIGXCPU") (25 . "SIGXFSZ")
      (26 . "SIGVTALRM") (27 . "SIGPROF") (28 . "SIGWINCH")
      (,SIGIO . "SIGIO") (,SIGSYS . "SIGSYS")))

  ;; --- Signal handler registration ---

  (define *signal-handlers* '())

  (define (add-signal-handler! signum handler)
    ;; Register a signal handler. On Chez, we use register-signal-handler
    ;; if available, otherwise this is a best-effort stub.
    ;; Chez's register-signal-handler calls (handler signum), but Gerbil's
    ;; add-signal-handler! expects 0-argument handlers. Wrap to adapt.
    (set! *signal-handlers*
      (cons (cons signum handler) *signal-handlers*))
    (when (top-level-bound? 'register-signal-handler)
      ((top-level-value 'register-signal-handler) signum
        (lambda (sig) (handler)))))

  (define (remove-signal-handler! signum)
    (set! *signal-handlers*
      (filter-signal (lambda (p) (not (= (car p) signum))) *signal-handlers*)))

  (define (filter-signal pred lst)
    (cond
      ((null? lst) '())
      ((pred (car lst)) (cons (car lst) (filter-signal pred (cdr lst))))
      (else (filter-signal pred (cdr lst)))))

  ) ;; end library
