#!chezscheme
;;; :std/os/signalfd -- Linux signalfd(2) for signal-as-file-descriptor delivery
;;;
;;; Converts signals into readable file descriptor events, suitable for
;;; use with epoll/poll/select. Linux-specific (signalfd is not POSIX).
;;;
;;; Usage:
;;;   (let ([sfd (make-signalfd (list SIGINT SIGTERM))])
;;;     (let loop ()
;;;       (let ([sig (signalfd-read sfd)])
;;;         (printf "got signal ~a\n" sig)
;;;         (unless (= sig SIGTERM) (loop))))
;;;     (signalfd-close sfd))

(library (std os signalfd)
  (export
    make-signalfd
    signalfd-read
    signalfd-close
    signalfd-fd
    SFD_CLOEXEC
    SFD_NONBLOCK)

  (import (chezscheme))

  ;; Load libc
  (define _libc (or (guard (e [#t #f]) (load-shared-object "libc.so.7"))
                    (guard (e [#t #f]) (load-shared-object "libc.so.6"))
                    (guard (e [#t #f]) (load-shared-object "libc.so"))))

  ;; ========== Platform Check ==========

  (define (assert-linux who)
    (unless (memq (machine-type) '(a6le ta6le i3le ti3le arm32le tarm32le
                                    arm64le tarm64le rv64le trv64le))
      (error who "signalfd is Linux-specific" (machine-type))))

  ;; ========== Constants ==========

  (define *freebsd?* (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb)))
  (define SFD_CLOEXEC  (if *freebsd?* #x100000 #x80000))   ;; same as O_CLOEXEC
  (define SFD_NONBLOCK (if *freebsd?* #x4      #x800))      ;; same as O_NONBLOCK

  (define SIGSET_SIZE (if *freebsd?* 16 128))  ;; sizeof(sigset_t): FreeBSD=16, Linux=128
  (define SIGNALFD_SIGINFO_SIZE 128)  ;; sizeof(struct signalfd_siginfo)
  (define SIG_BLOCK 0)

  ;; ========== FFI ==========

  (define c-signalfd    (foreign-procedure "signalfd" (int void* int) int))
  (define c-read        (foreign-procedure "read" (int void* size_t) ssize_t))
  (define c-close       (foreign-procedure "close" (int) int))
  (define c-sigemptyset (foreign-procedure "sigemptyset" (void*) int))
  (define c-sigaddset   (foreign-procedure "sigaddset" (void* int) int))
  (define c-sigprocmask (foreign-procedure "sigprocmask" (int void* void*) int))

  ;; errno access
  (define c-errno-location
    (let ((mt (symbol->string (machine-type))))

      (if (or (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb))

              (and (>= (string-length mt) 3)

                   (string=? (substring mt (- (string-length mt) 3) (string-length mt)) "osx")))

        (foreign-procedure "__error" () void*)

        (foreign-procedure "__errno_location" () void*))))
  (define (get-errno) (foreign-ref 'int (c-errno-location) 0))
  (define EINTR 4)
  (define EAGAIN (if *freebsd?* 35 11))

  ;; ========== signalfd record ==========

  (define-record-type signalfd-obj
    (fields
      (immutable fd)
      (immutable signals)       ;; list of signal numbers being watched
      (mutable open?))
    (sealed #t))

  ;; ========== Public API ==========

  (define make-signalfd
    (case-lambda
      [(signals) (make-signalfd signals (bitwise-ior SFD_CLOEXEC SFD_NONBLOCK))]
      [(signals flags)
       (assert-linux 'make-signalfd)
       (unless (and (list? signals) (pair? signals))
         (error 'make-signalfd "signals must be a non-empty list of signal numbers"
                signals))
       ;; Build sigset_t
       (let ([sigset (foreign-alloc SIGSET_SIZE)])
         (dynamic-wind
           void
           (lambda ()
             (c-sigemptyset sigset)
             (for-each
               (lambda (sig)
                 (unless (and (fixnum? sig) (> sig 0) (< sig 65))
                   (error 'make-signalfd "invalid signal number" sig))
                 (c-sigaddset sigset sig))
               signals)
             ;; Block these signals so they are delivered via signalfd
             ;; rather than default signal handlers
             (let ([rc (c-sigprocmask SIG_BLOCK sigset 0)])
               (when (< rc 0)
                 (error 'make-signalfd "sigprocmask failed" (get-errno))))
             ;; Create signalfd (-1 means create new fd)
             (let ([fd (c-signalfd -1 sigset flags)])
               (when (< fd 0)
                 (error 'make-signalfd "signalfd() failed" (get-errno)))
               (make-signalfd-obj fd signals #t)))
           (lambda () (foreign-free sigset))))]))

  (define (signalfd-fd sfd)
    ;; Return the raw file descriptor number for use with epoll/poll.
    (signalfd-obj-fd sfd))

  (define (signalfd-read sfd)
    ;; Read one signal from the signalfd.
    ;; Returns the signal number (ssi_signo, uint32 at offset 0).
    ;; Blocks if no signal pending (unless SFD_NONBLOCK was set).
    ;; Returns #f on EOF or if the fd was closed.
    (unless (signalfd-obj-open? sfd)
      (error 'signalfd-read "signalfd is closed"))
    (let ([buf (foreign-alloc SIGNALFD_SIGINFO_SIZE)])
      (dynamic-wind
        void
        (lambda ()
          (let loop ()
            (let ([n (c-read (signalfd-obj-fd sfd) buf SIGNALFD_SIGINFO_SIZE)])
              (cond
                [(= n SIGNALFD_SIGINFO_SIZE)
                 ;; ssi_signo is the first uint32 field
                 (foreign-ref 'unsigned-32 buf 0)]
                [(and (< n 0) (= (get-errno) EINTR))
                 (loop)]
                [(and (< n 0) (= (get-errno) EAGAIN))
                 #f]  ;; no signal pending (non-blocking mode)
                [(= n 0)
                 #f]  ;; EOF
                [else
                 (error 'signalfd-read "read failed" (get-errno))]))))
        (lambda () (foreign-free buf)))))

  (define (signalfd-close sfd)
    ;; Close the signalfd file descriptor.
    (when (signalfd-obj-open? sfd)
      (c-close (signalfd-obj-fd sfd))
      (signalfd-obj-open?-set! sfd #f)))

  ) ;; end library
