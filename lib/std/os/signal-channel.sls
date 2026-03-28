#!chezscheme
;;; (std os signal-channel) — Channel-based signal delivery
;;;
;;; Track 25: Delivers signals as messages to typed channels that can
;;; be selected alongside other event sources. Uses a dedicated signal
;;; thread with sigwait() for race-free delivery.

(library (std os signal-channel)
  (export
    make-signal-channel
    signal-channel?
    signal-channel-recv
    signal-channel-try-recv
    signal-channel-close!
    signal-channel-signals
    signal-number->name
    start-signal-thread!
    stop-signal-thread!)

  (import (chezscheme))

  ;; ========== Low-level FFI ==========

  (define _libc (or (guard (e [#t #f]) (load-shared-object "libc.so.7"))
                    (guard (e [#t #f]) (load-shared-object "libc.so.6"))
                    (guard (e [#t #f]) (load-shared-object "libc.so"))))
  (define _libc2 (guard (e [#t #f]) (load-shared-object "")))

  (define *freebsd?* (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb)))
  (define SIGSET_SIZE (if *freebsd?* 16 128))  ;; sizeof(sigset_t): FreeBSD=16, Linux=128
  (define c-sigemptyset  (foreign-procedure "sigemptyset" (void*) int))
  (define c-sigaddset    (foreign-procedure "sigaddset" (void* int) int))
  (define c-sigprocmask  (foreign-procedure "sigprocmask" (int void* void*) int))
  (define c-sigwait      (foreign-procedure "sigwait" (void* void*) int))
  (define SIG_BLOCK 0)

  ;; ========== Signal Name Mapping ==========

  (define *signal-names*
    '((1 . "HUP") (2 . "INT") (3 . "QUIT") (4 . "ILL") (5 . "TRAP")
      (6 . "ABRT") (8 . "FPE") (9 . "KILL") (10 . "USR1") (11 . "SEGV")
      (12 . "USR2") (13 . "PIPE") (14 . "ALRM") (15 . "TERM")
      (17 . "CHLD") (18 . "CONT") (19 . "STOP") (20 . "TSTP")
      (21 . "TTIN") (22 . "TTOU") (23 . "URG") (24 . "XCPU")
      (25 . "XFSZ") (26 . "VTALRM") (27 . "PROF") (28 . "WINCH")
      (29 . "IO") (31 . "SYS")))

  (define (signal-number->name num)
    (let ([entry (assv num *signal-names*)])
      (if entry (cdr entry) (number->string num))))

  ;; ========== Signal Channel ==========

  (define-record-type signal-channel
    (fields
      (immutable signals)     ;; list of signal numbers
      (immutable queue-mutex)
      (immutable queue-cond)
      (mutable queue)         ;; list of received signal numbers
      (mutable closed?))
    (protocol
      (lambda (new)
        (lambda (signals)
          (let ([ch (new signals (make-mutex) (make-condition) '() #f)])
            (register-channel! ch)
            ch)))))

  ;; Channel registry for the signal thread
  (define *channels-mutex* (make-mutex))
  (define *channels* '())
  (define *signal-thread* #f)
  (define *signal-running* #f)

  (define (register-channel! ch)
    (with-mutex *channels-mutex*
      (set! *channels* (cons ch *channels*))))

  (define (unregister-channel! ch)
    (with-mutex *channels-mutex*
      (set! *channels*
        (filter-not (lambda (c) (eq? c ch)) *channels*))))

  (define (filter-not pred lst)
    (let lp ([lst lst] [result '()])
      (if (null? lst) (reverse result)
        (lp (cdr lst)
            (if (pred (car lst)) result (cons (car lst) result))))))

  ;; ========== Channel Operations ==========

  (define (signal-channel-recv ch)
    ;; Block until a signal is available
    (mutex-acquire (signal-channel-queue-mutex ch))
    (let lp ()
      (cond
        [(pair? (signal-channel-queue ch))
         (let ([sig (car (signal-channel-queue ch))])
           (signal-channel-queue-set! ch (cdr (signal-channel-queue ch)))
           (mutex-release (signal-channel-queue-mutex ch))
           sig)]
        [(signal-channel-closed? ch)
         (mutex-release (signal-channel-queue-mutex ch))
         #f]
        [else
         (condition-wait (signal-channel-queue-cond ch)
                         (signal-channel-queue-mutex ch))
         (lp)])))

  (define (signal-channel-try-recv ch)
    ;; Non-blocking: return signal number or #f
    (mutex-acquire (signal-channel-queue-mutex ch))
    (let ([result (if (pair? (signal-channel-queue ch))
                    (let ([sig (car (signal-channel-queue ch))])
                      (signal-channel-queue-set! ch (cdr (signal-channel-queue ch)))
                      sig)
                    #f)])
      (mutex-release (signal-channel-queue-mutex ch))
      result))

  (define (signal-channel-close! ch)
    (signal-channel-closed?-set! ch #t)
    (condition-broadcast (signal-channel-queue-cond ch))
    (unregister-channel! ch))

  (define (enqueue-signal! ch signum)
    (mutex-acquire (signal-channel-queue-mutex ch))
    (signal-channel-queue-set! ch
      (append (signal-channel-queue ch) (list signum)))
    (condition-signal (signal-channel-queue-cond ch))
    (mutex-release (signal-channel-queue-mutex ch)))

  ;; ========== Signal Thread ==========

  (define (all-registered-signals)
    ;; Collect all signal numbers from all channels
    (with-mutex *channels-mutex*
      (let lp ([chs *channels*] [sigs '()])
        (if (null? chs) (deduplicate sigs)
          (lp (cdr chs)
              (append (signal-channel-signals (car chs)) sigs))))))

  (define (deduplicate lst)
    (let lp ([lst lst] [seen '()] [result '()])
      (if (null? lst) (reverse result)
        (if (memv (car lst) seen)
          (lp (cdr lst) seen result)
          (lp (cdr lst) (cons (car lst) seen) (cons (car lst) result))))))

  (define (start-signal-thread!)
    ;; Start the background signal thread
    (unless *signal-running*
      (set! *signal-running* #t)
      (let ([sigs (all-registered-signals)])
        ;; Block these signals in all threads
        (when (pair? sigs)
          (block-signals sigs))
        ;; Start signal waiter thread
        (set! *signal-thread*
          (fork-thread
            (lambda ()
              (signal-thread-loop)))))))

  (define (stop-signal-thread!)
    (set! *signal-running* #f)
    ;; Send SIGUSR1 to unblock sigwait if needed
    (guard (e [#t (void)])
      (when *signal-running*
        ((foreign-procedure "kill" (int int) int)
         ((foreign-procedure "getpid" () int)) 10))))  ;; SIGUSR1

  (define (block-signals sigs)
    (let ([set (foreign-alloc SIGSET_SIZE)])
      (dynamic-wind
        void
        (lambda ()
          (c-sigemptyset set)
          (for-each (lambda (s) (c-sigaddset set s)) sigs)
          (c-sigprocmask SIG_BLOCK set 0))
        (lambda () (foreign-free set)))))

  (define (signal-thread-loop)
    (let ([set (foreign-alloc SIGSET_SIZE)]
          [sig-buf (foreign-alloc 4)])
      (dynamic-wind
        void
        (lambda ()
          (let lp ()
            (when *signal-running*
              ;; Rebuild signal set each iteration (channels may change)
              (let ([sigs (all-registered-signals)])
                (when (pair? sigs)
                  (c-sigemptyset set)
                  (for-each (lambda (s) (c-sigaddset set s)) sigs)
                  (let ([rc (c-sigwait set sig-buf)])
                    (when (= rc 0)
                      (let ([signum (foreign-ref 'int sig-buf 0)])
                        ;; Dispatch to all channels interested in this signal
                        (with-mutex *channels-mutex*
                          (for-each
                            (lambda (ch)
                              (when (memv signum (signal-channel-signals ch))
                                (enqueue-signal! ch signum)))
                            *channels*)))))))
              (lp))))
        (lambda ()
          (foreign-free set)
          (foreign-free sig-buf)))))

  ) ;; end library
