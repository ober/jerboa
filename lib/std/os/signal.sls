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
  (define libc (guard (e [#t #f]) (load-shared-object "libc.so.6")))

  ;; POSIX kill(pid, sig)
  (define kill (foreign-procedure "kill" (int int) int))

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

  (define signal-names
    '((1 . "SIGHUP") (2 . "SIGINT") (3 . "SIGQUIT") (4 . "SIGILL")
      (5 . "SIGTRAP") (6 . "SIGABRT") (8 . "SIGFPE") (9 . "SIGKILL")
      (10 . "SIGUSR1") (11 . "SIGSEGV") (12 . "SIGUSR2") (13 . "SIGPIPE")
      (14 . "SIGALRM") (15 . "SIGTERM") (17 . "SIGCHLD") (18 . "SIGCONT")
      (19 . "SIGSTOP") (20 . "SIGTSTP") (21 . "SIGTTIN") (22 . "SIGTTOU")
      (23 . "SIGURG") (24 . "SIGXCPU") (25 . "SIGXFSZ") (26 . "SIGVTALRM")
      (27 . "SIGPROF") (28 . "SIGWINCH") (29 . "SIGIO") (31 . "SIGSYS")))

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
