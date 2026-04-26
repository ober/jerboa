#!chezscheme
;;; (std net io) — Fiber-Aware I/O Core
;;;
;;; Integrates Linux epoll with the fiber scheduler so that socket I/O
;;; parks fibers instead of blocking OS threads. This is the foundation
;;; for high-scalability networking.
;;;
;;; Architecture:
;;;   - A dedicated poller thread runs epoll_wait in a loop
;;;   - Each fd maps to a poll-desc holding parked reader/writer fibers
;;;   - fiber-wait-readable/writable park the current fiber and register
;;;     with epoll; the poller wakes them via wake-fiber!
;;;   - Uses edge-triggered epoll (EPOLLET) — one notification per state
;;;     change, matching Go's proven netpoller model
;;;   - An eventfd wakes the poller when new fds are registered
;;;
;;; API:
;;;   (make-io-poller rt)              — create poller for a fiber runtime
;;;   (io-poller-start! poller)        — start poller thread
;;;   (io-poller-stop! poller)         — stop poller thread
;;;   (fiber-wait-readable fd poller)  — park fiber until fd is readable
;;;   (fiber-wait-writable fd poller)  — park fiber until fd is writable
;;;   (poller-register-fd! poller fd events) — register fd with epoll
;;;   (poller-unregister-fd! poller fd)      — remove fd from epoll
;;;
;;;   (fiber-tcp-accept srv poller)    — accept, parking fiber on EAGAIN
;;;   (fiber-tcp-read fd buf n poller) — read, parking fiber on EAGAIN
;;;   (fiber-tcp-write fd buf n poller)— write, parking fiber on EAGAIN
;;;   (fiber-tcp-connect addr port poller) — non-blocking connect
;;;
;;;   (with-io-poller rt body ...)     — convenience macro

(library (std net io)
  (export
    ;; Poller lifecycle
    make-io-poller
    io-poller?
    io-poller-start!
    io-poller-stop!

    ;; Core primitives
    fiber-wait-readable
    fiber-wait-writable
    poller-register-fd!
    poller-unregister-fd!

    ;; Fiber-aware TCP operations
    fiber-tcp-accept
    fiber-tcp-read
    fiber-tcp-write
    fiber-tcp-writev2
    fiber-tcp-connect

    ;; Convenience
    with-io-poller
    fiber-tcp-listen
    fiber-tcp-close)

  (import (chezscheme)
          (std fiber)
          (std os epoll-native))

  ;; ========== FFI for raw socket ops ==========

  (define _libc-loaded
    (let ((v (getenv "JEMACS_STATIC")))
      (if (and v (not (string=? v "")) (not (string=? v "0")))
          #f
          (load-shared-object #f))))

  (define c-socket    (foreign-procedure "socket" (int int int) int))
  (define c-bind      (foreign-procedure "bind" (int void* int) int))
  (define c-listen    (foreign-procedure "listen" (int int) int))
  (define c-accept    (foreign-procedure "accept" (int void* void*) int))
  (define c-connect   (foreign-procedure "connect" (int void* int) int))
  (define c-close     (foreign-procedure "close" (int) int))
  (define c-setsockopt (foreign-procedure "setsockopt" (int int int void* int) int))
  (define c-read      (foreign-procedure "read" (int u8* size_t) ssize_t))
  (define c-write     (foreign-procedure "write" (int u8* size_t) ssize_t))
  (define c-writev2   (foreign-procedure "jerboa_writev2" (int u8* size_t u8* size_t) ssize_t))
  (define c-htons     (foreign-procedure "htons" (unsigned-short) unsigned-short))
  (define c-inet-pton (foreign-procedure "inet_pton" (int string void*) int))
  (define c-getsockname (foreign-procedure "getsockname" (int void* void*) int))
  (define c-fcntl     (foreign-procedure "fcntl" (int int int) int))

  ;; errno
  (define c-errno-location
    (cond
      ((foreign-entry? "__errno_location")
       (foreign-procedure "__errno_location" () void*))
      ((foreign-entry? "__error")
       (foreign-procedure "__error" () void*))
      ((foreign-entry? "__errno")
       (foreign-procedure "__errno" () void*))
      (else (foreign-procedure "__errno_location" () void*))))
  (define (get-errno) (foreign-ref 'int (c-errno-location) 0))

  (define EINTR 4)
  (define EAGAIN 11)
  (define EINPROGRESS 115)

  ;; Constants
  (define AF_INET 2)
  (define SOCK_STREAM 1)
  (define SOCK_NONBLOCK #x800)
  (define SOL_SOCKET 1)
  (define SO_REUSEADDR 2)
  (define SO_REUSEPORT 15)
  (define SOCKADDR_IN_SIZE 16)
  (define F_GETFL 3)
  (define F_SETFL 4)
  (define O_NONBLOCK #x800)

  (define (set-nonblocking! fd)
    (let ([flags (c-fcntl fd F_GETFL 0)])
      (c-fcntl fd F_SETFL (bitwise-ior flags O_NONBLOCK))))

  ;; ========== sockaddr_in helpers ==========

  (define (make-sockaddr-in address port)
    (let ([buf (foreign-alloc SOCKADDR_IN_SIZE)])
      (do ([i 0 (fx+ i 1)]) ((fx= i SOCKADDR_IN_SIZE))
        (foreign-set! 'unsigned-8 buf i 0))
      (foreign-set! 'unsigned-short buf 0 AF_INET)
      (foreign-set! 'unsigned-short buf 2 (c-htons port))
      (when (= (c-inet-pton AF_INET address (+ buf 4)) 0)
        (foreign-free buf)
        (error 'make-sockaddr-in "invalid address" address))
      buf))

  (define (sockaddr-in-port buf)
    (let ([hi (foreign-ref 'unsigned-8 buf 2)]
          [lo (foreign-ref 'unsigned-8 buf 3)])
      (+ (* hi 256) lo)))

  ;; ========== Poll descriptor ==========
  ;;
  ;; Maps an fd to the fibers waiting on it.

  (define-record-type poll-desc
    (fields
      (immutable fd)
      (mutable events)          ;; currently registered epoll events
      (mutable reader-fiber)    ;; fiber parked for read, or #f
      (mutable writer-fiber)    ;; fiber parked for write, or #f
      (mutable error?)          ;; set #t on EPOLLERR/EPOLLHUP
      (immutable pd-mutex))     ;; protects reader/writer fields
    (protocol
      (lambda (new)
        (lambda (fd)
          (new fd 0 #f #f #f (make-mutex))))))

  ;; ========== FD table ==========
  ;;
  ;; Growable vector mapping fd -> poll-desc or #f.
  ;; fd values on Linux are small non-negative integers.

  (define-record-type fd-table
    (fields
      (mutable vec)
      (mutable size)
      (immutable ft-mutex))
    (protocol
      (lambda (new)
        (lambda ()
          (new (make-vector 4096 #f) 4096 (make-mutex))))))

  (define (ft-ensure-capacity! ft fd)
    (when (fx>= fd (fd-table-size ft))
      (let* ([old-sz (fd-table-size ft)]
             [new-sz (fx* 2 (fxmax old-sz (fx+ fd 1)))]
             [old-vec (fd-table-vec ft)]
             [new-vec (make-vector new-sz #f)])
        (do ([i 0 (fx+ i 1)]) ((fx= i old-sz))
          (vector-set! new-vec i (vector-ref old-vec i)))
        (fd-table-vec-set! ft new-vec)
        (fd-table-size-set! ft new-sz))))

  (define (ft-ref ft fd)
    (if (fx< fd (fd-table-size ft))
      (vector-ref (fd-table-vec ft) fd)
      #f))

  (define (ft-set! ft fd pd)
    (ft-ensure-capacity! ft fd)
    (vector-set! (fd-table-vec ft) fd pd))

  (define (ft-remove! ft fd)
    (when (fx< fd (fd-table-size ft))
      (vector-set! (fd-table-vec ft) fd #f)))

  ;; ========== IO Poller ==========

  (define-record-type io-poller
    (fields
      (immutable epfd)         ;; epoll file descriptor
      (immutable wakefd)       ;; eventfd for waking the poller
      (immutable fdt)          ;; fd-table
      (immutable runtime)      ;; fiber-runtime (for wake-fiber!)
      (mutable poller-thread)  ;; OS thread handle
      (mutable running?))      ;; shutdown flag
    (protocol
      (lambda (new)
        (lambda (rt)
          (let ([epfd (epoll-create)]
                [wakefd (eventfd-create)]
                [fdt (make-fd-table)])
            ;; Register the wakefd with epoll so epoll_wait unblocks
            ;; when we signal it
            (epoll-add! epfd wakefd (bitwise-ior EPOLLIN EPOLLET))
            (new epfd wakefd fdt rt #f #f))))))

  ;; ========== Poller thread ==========

  (define *max-events* 256)

  (define (poller-loop poller)
    (let ([epfd (io-poller-epfd poller)]
          [wakefd (io-poller-wakefd poller)]
          [fdt (io-poller-fdt poller)])
      (let loop ()
        (when (io-poller-running? poller)
          ;; Block until events (or wakefd signal).
          ;; Use 100ms timeout as safety net so we re-check running?.
          ;; epoll_wait can return -1/EINTR on Termux when a signal
          ;; arrives mid-syscall; treat that as an empty event list and
          ;; re-enter the loop instead of letting the poller die.
          (let ([events (guard (exn [#t '()])
                          (epoll-wait epfd *max-events* 100))])
            (for-each
              (lambda (ev)
                (let ([fd (car ev)]
                      [mask (cdr ev)])
                  (cond
                    ;; wakefd — just drain it, new registrations handled next iteration
                    [(fx= fd wakefd) (eventfd-drain wakefd)]
                    ;; Real fd — look up poll-desc and wake parked fibers
                    [else
                     (let ([pd (with-mutex (fd-table-ft-mutex fdt) (ft-ref fdt fd))])
                       (when pd
                         (let ([pdmx (poll-desc-pd-mutex pd)])
                           (mutex-acquire pdmx)
                           ;; Error/hangup — wake both reader and writer
                           (when (or (not (zero? (bitwise-and mask EPOLLERR)))
                                     (not (zero? (bitwise-and mask EPOLLHUP))))
                             (poll-desc-error?-set! pd #t))
                           ;; Readable — wake reader
                           (when (or (not (zero? (bitwise-and mask EPOLLIN)))
                                     (poll-desc-error? pd))
                             (let ([rf (poll-desc-reader-fiber pd)])
                               (when rf
                                 (poll-desc-reader-fiber-set! pd #f)
                                 (mutex-release pdmx)
                                 (wake-fiber! rf)
                                 (mutex-acquire pdmx))))
                           ;; Writable — wake writer
                           (when (or (not (zero? (bitwise-and mask EPOLLOUT)))
                                     (poll-desc-error? pd))
                             (let ([wf (poll-desc-writer-fiber pd)])
                               (when wf
                                 (poll-desc-writer-fiber-set! pd #f)
                                 (mutex-release pdmx)
                                 (wake-fiber! wf)
                                 (mutex-acquire pdmx))))
                           (mutex-release pdmx))))])))
              events))
          (loop)))))

  (define (io-poller-start! poller)
    (io-poller-running?-set! poller #t)
    (io-poller-poller-thread-set! poller
      (fork-thread (lambda () (poller-loop poller)))))

  (define (io-poller-stop! poller)
    (io-poller-running?-set! poller #f)
    (eventfd-signal (io-poller-wakefd poller))
    ;; Give poller thread time to exit
    (sleep (make-time 'time-duration 100000000 0))
    (epoll-close (io-poller-epfd poller))
    (c-close (io-poller-wakefd poller)))

  ;; ========== Register/unregister fds ==========

  (define (poller-register-fd! poller fd events)
    (let ([fdt (io-poller-fdt poller)]
          [epfd (io-poller-epfd poller)])
      (let ([pd (make-poll-desc fd)])
        (poll-desc-events-set! pd events)
        (with-mutex (fd-table-ft-mutex fdt)
          (ft-set! fdt fd pd))
        (epoll-add! epfd fd (bitwise-ior events EPOLLET))
        (eventfd-signal (io-poller-wakefd poller))
        pd)))

  (define (poller-unregister-fd! poller fd)
    (let ([fdt (io-poller-fdt poller)]
          [epfd (io-poller-epfd poller)])
      (guard (e [#t (void)])  ;; ignore if fd already removed
        (epoll-remove! epfd fd))
      (with-mutex (fd-table-ft-mutex fdt)
        (ft-remove! fdt fd))))

  ;; ========== Internal: ensure fd is registered, get its poll-desc ==========

  ;; ensure-poll-desc! — register fd with epoll if not already tracked.
  ;; Uses level-triggered mode (no EPOLLET, no ONESHOT).
  ;; The poller fires repeatedly while an fd is ready — if no fiber
  ;; is registered, the event is simply ignored. When a fiber IS
  ;; registered, it gets woken on the next poller iteration.
  (define (ensure-poll-desc! poller fd)
    (let ([fdt (io-poller-fdt poller)])
      (with-mutex (fd-table-ft-mutex fdt)
        (or (ft-ref fdt fd)
            (let ([pd (make-poll-desc fd)])
              (ft-set! fdt fd pd)
              ;; Edge-triggered: one notification per data-arrival transition.
            ;; Re-arm via epoll_modify before each park closes the race window.
            (epoll-add! (io-poller-epfd poller) fd
                (bitwise-ior EPOLLIN EPOLLOUT EPOLLET))
              pd)))))

  ;; ========== fiber-wait-readable / fiber-wait-writable ==========
  ;;
  ;; Strategy: Edge-triggered epoll (EPOLLET). The kernel fires once per
  ;; state transition (data arrives / send buffer drains). Before parking,
  ;; we call epoll_modify to re-arm the fd — this forces an immediate
  ;; notification if the fd is already ready, closing the EAGAIN→park race.
  ;; This mirrors Go's netpoller model.

  (define (fiber-wait-readable fd poller)
    (let ([f (fiber-self)]
          [pd (ensure-poll-desc! poller fd)])
      (fiber-check-cancelled!)
      (let ([pdmx (poll-desc-pd-mutex pd)]
            [gate (box 'channel)])
        ;; Register fiber as reader under lock
        (mutex-acquire pdmx)
        (poll-desc-reader-fiber-set! pd f)
        (mutex-release pdmx)
        ;; Re-arm: if fd became readable between EAGAIN and now,
        ;; this epoll_modify causes an immediate EPOLLIN on next epoll_wait.
        (epoll-modify! (io-poller-epfd poller) fd
          (bitwise-ior EPOLLIN EPOLLOUT EPOLLET))
        ;; Signal poller thread to break out of epoll_wait
        (eventfd-signal (io-poller-wakefd poller))
        ;; Park the fiber
        (fiber-gate-set! f gate)
        (set-timer 1)
        (spin-until-gate gate)
        (fiber-gate-set! f #f)
        (fiber-check-cancelled!)
        (void))))

  (define (fiber-wait-writable fd poller)
    (let ([f (fiber-self)]
          [pd (ensure-poll-desc! poller fd)])
      (fiber-check-cancelled!)
      (let ([pdmx (poll-desc-pd-mutex pd)]
            [gate (box 'channel)])
        ;; Register fiber as writer under lock
        (mutex-acquire pdmx)
        (poll-desc-writer-fiber-set! pd f)
        (mutex-release pdmx)
        ;; Re-arm for write readiness
        (epoll-modify! (io-poller-epfd poller) fd
          (bitwise-ior EPOLLIN EPOLLOUT EPOLLET))
        ;; Signal poller
        (eventfd-signal (io-poller-wakefd poller))
        ;; Park the fiber
        (fiber-gate-set! f gate)
        (set-timer 1)
        (spin-until-gate gate)
        (fiber-gate-set! f #f)
        (fiber-check-cancelled!)
        (void))))

  ;; ========== Fiber-aware TCP operations ==========

  ;; ---------- fiber-tcp-listen ----------

  (define fiber-tcp-listen
    (case-lambda
      [(address port) (fiber-tcp-listen address port 4096)]
      [(address port backlog)
       (let ([fd (c-socket AF_INET SOCK_STREAM 0)])
         (when (< fd 0) (error 'fiber-tcp-listen "socket() failed"))
         ;; SO_REUSEADDR + SO_REUSEPORT
         (let ([one (foreign-alloc 4)])
           (foreign-set! 'int one 0 1)
           (c-setsockopt fd SOL_SOCKET SO_REUSEADDR one 4)
           (c-setsockopt fd SOL_SOCKET SO_REUSEPORT one 4)
           (foreign-free one))
         ;; Bind
         (let ([addr (make-sockaddr-in address port)])
           (let ([rc (c-bind fd addr SOCKADDR_IN_SIZE)])
             (foreign-free addr)
             (when (< rc 0) (c-close fd)
               (error 'fiber-tcp-listen "bind() failed" address port))))
         ;; Listen
         (when (< (c-listen fd backlog) 0)
           (c-close fd)
           (error 'fiber-tcp-listen "listen() failed"))
         ;; Non-blocking
         (set-nonblocking! fd)
         ;; Get actual port
         (let ([buf (foreign-alloc SOCKADDR_IN_SIZE)]
               [len (foreign-alloc 4)])
           (foreign-set! 'int len 0 SOCKADDR_IN_SIZE)
           (c-getsockname fd buf len)
           (let ([p (sockaddr-in-port buf)])
             (foreign-free buf)
             (foreign-free len)
             (values fd p))))]))

  (define (fiber-tcp-close fd)
    (c-close fd)
    (void))

  ;; ---------- fiber-tcp-accept ----------
  ;;
  ;; Non-blocking accept. On EAGAIN, parks the fiber until the listen
  ;; fd becomes readable. Returns client fd (already non-blocking).

  (define (fiber-tcp-accept listen-fd poller)
    (let loop ()
      (let ([client-fd (c-accept listen-fd 0 0)])
        (cond
          [(fx>= client-fd 0)
           (set-nonblocking! client-fd)
           client-fd]
          [(let ([e (get-errno)]) (or (= e EAGAIN) (= e EINTR)))
           (fiber-wait-readable listen-fd poller)
           (loop)]
          [else (error 'fiber-tcp-accept "accept() failed" (get-errno))]))))

  ;; ---------- fiber-tcp-read ----------
  ;;
  ;; Read up to n bytes into bytevector buf starting at offset 0.
  ;; Returns number of bytes read (0 = EOF, negative = error).
  ;; Parks fiber on EAGAIN.

  (define (fiber-tcp-read fd buf n poller)
    (let loop ()
      (let ([rc (c-read fd buf n)])
        (cond
          [(fx> rc 0) rc]
          [(fx= rc 0) 0]  ;; EOF
          [(let ([e (get-errno)]) (or (= e EAGAIN) (= e EINTR)))
           (fiber-wait-readable fd poller)
           (loop)]
          [else rc]))))  ;; error

  ;; ---------- fiber-tcp-write ----------
  ;;
  ;; Write n bytes from bytevector buf. Returns total bytes written.
  ;; Parks fiber on EAGAIN. Loops until all bytes sent or error.

  (define (fiber-tcp-write fd buf n poller)
    (let loop ([written 0])
      (if (fx= written n) written
        (let* ([remaining (fx- n written)]
               [tmp (if (fx= written 0) buf
                      (let ([b (make-bytevector remaining)])
                        (bytevector-copy! buf written b 0 remaining) b))]
               [rc (c-write fd tmp remaining)])
          (cond
            [(fx> rc 0) (loop (fx+ written rc))]
            [(let ([e (get-errno)]) (or (= e EAGAIN) (= e EINTR)))
             (fiber-wait-writable fd poller)
             (loop written)]
            [else written])))))  ;; partial write on error

  ;; ---------- fiber-tcp-writev2 ----------
  ;;
  ;; Write hdr-bv (hdr-n bytes) + body-bv in a single writev syscall.
  ;; body-bv may be #f or zero-length for header-only responses.
  ;; The common case (small responses) completes in one syscall.
  ;; Partial writes fall back to position-tracked loop.

  (define (fiber-tcp-writev2 fd hdr-bv hdr-n body-bv poller)
    (let* ([body-n (if (and body-bv (fx> (bytevector-length body-bv) 0))
                       (bytevector-length body-bv) 0)]
           [total  (fx+ hdr-n body-n)]
           [dummy  (make-bytevector 0)]
           [b2     (if (fx> body-n 0) body-bv dummy)]
           ;; First attempt: combined writev
           [rc0    (c-writev2 fd hdr-bv hdr-n b2 body-n)])
      (cond
        ;; Everything sent in one shot (common case)
        [(fx= rc0 total) rc0]
        ;; EAGAIN / EINTR on first try — park and fall through to loop
        [(or (fx<= rc0 0)
             (let ([e (get-errno)]) (or (= e EAGAIN) (= e EINTR))))
         (when (fx<= rc0 0)
           (fiber-wait-writable fd poller))
         (let loop ([sent (fxmax rc0 0)])
           (if (fx= sent total)
             sent
             (let* ([h-off (fxmin sent hdr-n)]
                    [b-off (fxmax 0 (fx- sent hdr-n))]
                    [h-rem (fx- hdr-n h-off)]
                    [b-rem (fx- body-n b-off)]
                    [buf   (if (fx> h-rem 0)
                               (if (fx= h-off 0) hdr-bv
                                   (let ([t (make-bytevector h-rem)])
                                     (bytevector-copy! hdr-bv h-off t 0 h-rem) t))
                               (if (fx= b-off 0) body-bv
                                   (let ([t (make-bytevector b-rem)])
                                     (bytevector-copy! body-bv b-off t 0 b-rem) t)))]
                    [n     (if (fx> h-rem 0) h-rem b-rem)]
                    [rc    (c-write fd buf n)])
               (cond
                 [(fx> rc 0) (loop (fx+ sent rc))]
                 [(let ([e (get-errno)]) (or (= e EAGAIN) (= e EINTR)))
                  (fiber-wait-writable fd poller)
                  (loop sent)]
                 [else sent]))))]
        ;; Partial write — continue from where writev left off
        [else
         (let loop ([sent rc0])
           (if (fx= sent total)
             sent
             (let* ([h-off (fxmin sent hdr-n)]
                    [b-off (fxmax 0 (fx- sent hdr-n))]
                    [h-rem (fx- hdr-n h-off)]
                    [b-rem (fx- body-n b-off)]
                    [buf   (if (fx> h-rem 0)
                               (if (fx= h-off 0) hdr-bv
                                   (let ([t (make-bytevector h-rem)])
                                     (bytevector-copy! hdr-bv h-off t 0 h-rem) t))
                               (if (fx= b-off 0) body-bv
                                   (let ([t (make-bytevector b-rem)])
                                     (bytevector-copy! body-bv b-off t 0 b-rem) t)))]
                    [n     (if (fx> h-rem 0) h-rem b-rem)]
                    [rc    (c-write fd buf n)])
               (cond
                 [(fx> rc 0) (loop (fx+ sent rc))]
                 [(let ([e (get-errno)]) (or (= e EAGAIN) (= e EINTR)))
                  (fiber-wait-writable fd poller)
                  (loop sent)]
                 [else sent]))))])))

  ;; ---------- fiber-tcp-connect ----------
  ;;
  ;; Non-blocking connect. Parks fiber while connect is in progress.
  ;; Returns the connected fd.

  (define (fiber-tcp-connect address port poller)
    (let ([fd (c-socket AF_INET SOCK_STREAM 0)])
      (when (< fd 0) (error 'fiber-tcp-connect "socket() failed"))
      (set-nonblocking! fd)
      (let ([addr (make-sockaddr-in address port)])
        (let ([rc (c-connect fd addr SOCKADDR_IN_SIZE)])
          (foreign-free addr)
          (cond
            [(fx>= rc 0) fd]  ;; connected immediately
            [(= (get-errno) EINPROGRESS)
             ;; Connection in progress — wait for writable
             (fiber-wait-writable fd poller)
             ;; Check SO_ERROR to see if connect succeeded
             (let ([err-buf (foreign-alloc 4)]
                   [len-buf (foreign-alloc 4)])
               (foreign-set! 'int len-buf 0 4)
               (c-setsockopt fd SOL_SOCKET 0 err-buf 0) ;; dummy — use getsockopt
               ;; Use getsockopt SO_ERROR to check
               (let ([getsockopt (foreign-procedure "getsockopt"
                                   (int int int void* void*) int)])
                 (getsockopt fd SOL_SOCKET 4 err-buf len-buf) ;; SO_ERROR = 4
                 (let ([err (foreign-ref 'int err-buf 0)])
                   (foreign-free err-buf)
                   (foreign-free len-buf)
                   (when (not (zero? err))
                     (c-close fd)
                     (error 'fiber-tcp-connect "connect() failed" address port err))
                   fd)))]
            [else
             (c-close fd)
             (error 'fiber-tcp-connect "connect() failed" address port)])))))

  ;; ========== Convenience ==========

  (define-syntax with-io-poller
    (syntax-rules ()
      [(_ rt poller-var body ...)
       (let ([poller-var (make-io-poller rt)])
         (io-poller-start! poller-var)
         (guard (exn [#t (io-poller-stop! poller-var) (raise exn)])
           (let ([result (begin body ...)])
             (io-poller-stop! poller-var)
             result)))]))

) ;; end library
