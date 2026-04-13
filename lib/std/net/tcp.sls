#!chezscheme
;;; :std/net/tcp -- TCP client and server sockets
;;;
;;; Provides Gerbil-compatible TCP networking:
;;;   (tcp-listen address port)       → server socket
;;;   (tcp-accept server)             → (values input-port output-port)
;;;   (tcp-connect address port)      → (values input-port output-port)
;;;   (tcp-close server)              → void
;;;
;;; Ports are standard Chez Scheme binary ports transcoded to UTF-8.
;;; Use with-tcp-server for automatic cleanup.
;;;
;;; GC SAFETY: All blocking I/O uses non-blocking sockets with Chez-native
;;; sleep for retry delays. This ensures threads can participate in Chez's
;;; stop-the-world GC rendezvous (foreign calls like accept/read/poll block
;;; the thread from responding to GC signals).

(library (std net tcp)
  (export
    tcp-listen tcp-accept tcp-close
    tcp-connect
    tcp-server? tcp-server-port
    with-tcp-server
    ;; Binary-port variants — for protocols that need raw bytevector I/O
    ;; (e.g. FASL framing). Same semantics as tcp-accept/tcp-connect but
    ;; returns (values binary-input-port binary-output-port) with no
    ;; UTF-8 transcoder.
    tcp-accept-binary tcp-connect-binary)

  (import (chezscheme))

  ;; ========== FFI ==========

  ;; Load libc for POSIX socket functions
  (define _libc-loaded
    (let ((v (getenv "JEMACS_STATIC")))
      (if (and v (not (string=? v "")) (not (string=? v "0")))
          #f  ; symbols already in static binary
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
  (define c-htons     (foreign-procedure "htons" (unsigned-short) unsigned-short))
  (define c-inet-pton (foreign-procedure "inet_pton" (int string void*) int))
  (define c-getsockname (foreign-procedure "getsockname" (int void* void*) int))

  ;; fcntl for non-blocking mode
  (define c-fcntl     (foreign-procedure "fcntl" (int int int) int))

  ;; errno access for EINTR retry
  ;; Symbol naming varies by libc:
  ;;   glibc / musl (Linux)  → __errno_location
  ;;   FreeBSD / macOS       → __error
  ;;   bionic (Android)      → __errno
  ;; We can't rely on machine-type alone (tarm64le covers both Linux and
  ;; Android), so probe with foreign-entry? at load time.
  (define c-errno-location
    (let ((mt (symbol->string (machine-type))))
      (cond
        ((or (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb))
             (and (>= (string-length mt) 3)
                  (string=? (substring mt (- (string-length mt) 3) (string-length mt)) "osx")))
         (foreign-procedure "__error" () void*))
        ((foreign-entry? "__errno_location")
         (foreign-procedure "__errno_location" () void*))
        ((foreign-entry? "__errno")
         (foreign-procedure "__errno" () void*))
        (else
         (foreign-procedure "__errno_location" () void*)))))
  (define (get-errno) (foreign-ref 'int (c-errno-location) 0))
  (define EINTR 4)
  (define *freebsd?* (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb)))
  (define EAGAIN (if *freebsd?* 35 11))

  ;; fcntl constants
  (define F_GETFL 3)
  (define F_SETFL 4)
  (define O_NONBLOCK
    (if (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb)) #x4 #x800))

  ;; Constants
  (define AF_INET 2)
  (define SOCK_STREAM 1)
  (define SOL_SOCKET   (if *freebsd?* #xffff 1))
  (define SO_REUSEADDR (if *freebsd?* 4 2))
  (define SOCKADDR_IN_SIZE 16)  ;; sizeof(struct sockaddr_in) on Linux

  ;; GC-safe retry delay: 10ms via Chez's sleep (not a foreign call).
  ;; Chez's sleep uses condition variables that respond to GC signals.
  (define *retry-delay* (make-time 'time-duration 10000000 0))

  (define (set-nonblocking! fd)
    (let ([flags (c-fcntl fd F_GETFL 0)])
      (c-fcntl fd F_SETFL (bitwise-ior flags O_NONBLOCK))))

  ;; ========== sockaddr_in helpers ==========

  (define (make-sockaddr-in address port)
    ;; Build a struct sockaddr_in in foreign memory
    (let ([buf (foreign-alloc SOCKADDR_IN_SIZE)])
      ;; Zero the struct
      (let lp ([i 0])
        (when (< i SOCKADDR_IN_SIZE)
          (foreign-set! 'unsigned-8 buf i 0)
          (lp (+ i 1))))
      ;; sin_family = AF_INET
      ;; FreeBSD sockaddr_in has sin_len (uint8) at offset 0, sin_family (uint8) at offset 1
      ;; Linux sockaddr_in has sin_family (uint16) at offset 0
      (if *freebsd?*
        (begin
          (foreign-set! 'unsigned-8 buf 0 16)        ;; sin_len = sizeof(sockaddr_in)
          (foreign-set! 'unsigned-8 buf 1 AF_INET))  ;; sin_family (uint8)
        (foreign-set! 'unsigned-short buf 0 AF_INET)) ;; sin_family (uint16)
      ;; sin_port = htons(port) (offset 2, 2 bytes)
      (foreign-set! 'unsigned-short buf 2 (c-htons port))
      ;; sin_addr (offset 4, 4 bytes) — parse address string
      (let ([addr-ptr (+ buf 4)])
        (when (= (c-inet-pton AF_INET address addr-ptr) 0)
          (foreign-free buf)
          (error 'make-sockaddr-in "invalid address" address)))
      buf))

  (define (sockaddr-in-port buf)
    ;; Extract port from sockaddr_in (in host byte order)
    ;; sin_port is at offset 2, in network byte order
    (let ([hi (foreign-ref 'unsigned-8 buf 2)]
          [lo (foreign-ref 'unsigned-8 buf 3)])
      (+ (* hi 256) lo)))

  ;; ========== TCP Server ==========

  (define-record-type tcp-server
    (fields
      (immutable fd)
      (mutable port-num))   ;; actual port (useful when 0 = OS-assigned)
    (sealed #t))

  (define tcp-listen
    (case-lambda
      [(address port)
       (tcp-listen address port 128)]
      [(address port backlog)
       (let ([fd (c-socket AF_INET SOCK_STREAM 0)])
         (when (< fd 0)
           (error 'tcp-listen "socket() failed"))
         ;; SO_REUSEADDR
         (let ([one (foreign-alloc 4)])
           (foreign-set! 'int one 0 1)
           (c-setsockopt fd SOL_SOCKET SO_REUSEADDR one 4)
           (foreign-free one))
         ;; Bind
         (let ([addr (make-sockaddr-in address port)])
           (let ([rc (c-bind fd addr SOCKADDR_IN_SIZE)])
             (foreign-free addr)
             (when (< rc 0)
               (c-close fd)
               (error 'tcp-listen "bind() failed" address port))))
         ;; Listen
         (when (< (c-listen fd backlog) 0)
           (c-close fd)
           (error 'tcp-listen "listen() failed"))
         ;; Set non-blocking for GC-safe accept loop
         (set-nonblocking! fd)
         ;; Get actual port (important when port=0)
         (let ([actual-port
                (let ([buf (foreign-alloc SOCKADDR_IN_SIZE)]
                      [len (foreign-alloc 4)])
                  (foreign-set! 'int len 0 SOCKADDR_IN_SIZE)
                  (c-getsockname fd buf len)
                  (let ([p (sockaddr-in-port buf)])
                    (foreign-free buf)
                    (foreign-free len)
                    p))])
           (make-tcp-server fd actual-port)))]))

  (define (tcp-server-port srv)
    (tcp-server-port-num srv))

  (define (tcp-accept srv)
    ;; Accept a connection. Returns (values input-port output-port).
    ;; Uses non-blocking accept + Chez sleep for GC safety.
    ;; The listen socket is set non-blocking in tcp-listen.
    (let ([fd (tcp-server-fd srv)])
      (let loop ()
        (let ([client-fd (c-accept fd 0 0)])
          (cond
            [(>= client-fd 0) (fd->ports client-fd "tcp-client")]
            [(let ([e (get-errno)]) (or (= e EINTR) (= e EAGAIN)))
             ;; No connection pending — sleep via Chez (GC-safe), then retry
             (sleep *retry-delay*)
             (loop)]
            [else (error 'tcp-accept "accept() failed")])))))

  (define (tcp-close srv)
    (c-close (tcp-server-fd srv)))

  ;; ========== TCP Client ==========

  (define (tcp-connect address port)
    ;; Connect to a TCP server. Returns (values input-port output-port).
    ;; Retries on EINTR (caused by GC stop-the-world interrupting connect()).
    (let ([fd (c-socket AF_INET SOCK_STREAM 0)])
      (when (< fd 0)
        (error 'tcp-connect "socket() failed"))
      (let ([addr (make-sockaddr-in address port)])
        (let loop ()
          (let ([rc (c-connect fd addr SOCKADDR_IN_SIZE)])
            (cond
              [(>= rc 0)
               (foreign-free addr)
               (fd->ports fd "tcp-connection")]
              [(= (get-errno) EINTR) (loop)]
              [else
               (foreign-free addr)
               (c-close fd)
               (error 'tcp-connect "connect() failed" address port)]))))))

  ;; ========== Convenience ==========

  (define-syntax with-tcp-server
    (syntax-rules ()
      [(_ (var address port) body body* ...)
       (let ([var (tcp-listen address port)])
         (dynamic-wind
           (lambda () (void))
           (lambda () body body* ...)
           (lambda () (tcp-close var))))]))

  ;; ========== Internal: FD → Ports ==========

  (define (fd->ports fd name)
    ;; Wrap a socket FD as a pair of transcoded text ports.
    ;; IMPORTANT: Both ports share the same fd. A closed? flag prevents:
    ;; 1. Double-close: Chez calls close handler on both close-port AND GC finalization
    ;; 2. Read/write after close: returns EOF/0 instead of operating on reused fd
    ;;
    ;; Client sockets use non-blocking I/O with Chez-native sleep for GC safety.
    (set-nonblocking! fd)
    (let ([closed? #f])
      (let ([in (make-custom-binary-input-port
                  (string-append name "-in")
                  (lambda (bv start count)
                    (if closed? 0
                      (let ([buf (make-bytevector count)])
                        (let retry ()
                          (let ([n (c-read fd buf count)])
                            (cond
                              [(> n 0)
                               (bytevector-copy! buf 0 bv start n)
                               n]
                              [(and (< n 0)
                                    (let ([e (get-errno)])
                                      (or (= e EINTR) (= e EAGAIN))))
                               ;; No data yet — sleep via Chez (GC-safe), then retry
                               (sleep *retry-delay*)
                               (retry)]
                              [else 0]))))))
                  #f  ;; get-position
                  #f  ;; set-position!
                  (lambda ()
                    (unless closed?
                      (set! closed? #t)
                      (c-close fd))))]
            [out (make-custom-binary-output-port
                   (string-append name "-out")
                   (lambda (bv start count)
                     (if closed? 0
                       (let ([buf (make-bytevector count)])
                         (bytevector-copy! bv start buf 0 count)
                         (let lp ([written 0])
                           (if (= written count)
                             count
                             (let ([n (c-write fd
                                        (let ([tmp (make-bytevector (- count written))])
                                          (bytevector-copy! buf written tmp 0 (- count written))
                                          tmp)
                                        (- count written))])
                               (cond
                                 [(> n 0) (lp (+ written n))]
                                 [(and (< n 0)
                                       (let ([e (get-errno)])
                                         (or (= e EINTR) (= e EAGAIN))))
                                  ;; Socket buffer full — sleep briefly, retry
                                  (sleep *retry-delay*)
                                  (lp written)]
                                 [else written])))))))
                   #f  ;; get-position
                   #f  ;; set-position!
                   #f)])  ;; no close handler — fd closed via input port only
        (values
          (transcoded-port in (make-transcoder (utf-8-codec)
                                (eol-style none)
                                (error-handling-mode replace)))
          (transcoded-port out (make-transcoder (utf-8-codec)
                                 (eol-style none)
                                 (error-handling-mode replace)))))))

  ;; ========== Binary-Port Variants ==========

  (define (fd->binary-ports fd name)
    ;; Like fd->ports but returns raw binary ports (no UTF-8 transcoder).
    ;; Use for protocols that need put-bytevector / get-bytevector-n, e.g.
    ;; FASL-framed Raft transport messages.
    (set-nonblocking! fd)
    (let ([closed? #f])
      (let ([in (make-custom-binary-input-port
                  (string-append name "-bin-in")
                  (lambda (bv start count)
                    (if closed? 0
                      (let ([buf (make-bytevector count)])
                        (let retry ()
                          (let ([n (c-read fd buf count)])
                            (cond
                              [(> n 0)
                               (bytevector-copy! buf 0 bv start n)
                               n]
                              [(and (< n 0)
                                    (let ([e (get-errno)])
                                      (or (= e EINTR) (= e EAGAIN))))
                               (sleep *retry-delay*)
                               (retry)]
                              [else 0]))))))
                  #f #f
                  (lambda ()
                    (unless closed?
                      (set! closed? #t)
                      (c-close fd))))]
            [out (make-custom-binary-output-port
                   (string-append name "-bin-out")
                   (lambda (bv start count)
                     (if closed? 0
                       (let ([buf (make-bytevector count)])
                         (bytevector-copy! bv start buf 0 count)
                         (let lp ([written 0])
                           (if (= written count)
                             count
                             (let ([n (c-write fd
                                        (let ([tmp (make-bytevector (- count written))])
                                          (bytevector-copy! buf written tmp 0 (- count written))
                                          tmp)
                                        (- count written))])
                               (cond
                                 [(> n 0) (lp (+ written n))]
                                 [(and (< n 0)
                                       (let ([e (get-errno)])
                                         (or (= e EINTR) (= e EAGAIN))))
                                  (sleep *retry-delay*)
                                  (lp written)]
                                 [else written])))))))
                   #f #f #f)])
        (values in out))))

  (define (tcp-accept-binary srv)
    ;; Like tcp-accept but returns (values binary-input-port binary-output-port).
    (let ([fd (tcp-server-fd srv)])
      (let loop ()
        (let ([client-fd (c-accept fd 0 0)])
          (cond
            [(>= client-fd 0) (fd->binary-ports client-fd "tcp-client")]
            [(let ([e (get-errno)]) (or (= e EINTR) (= e EAGAIN)))
             (sleep *retry-delay*)
             (loop)]
            [else (error 'tcp-accept-binary "accept() failed")])))))

  (define (tcp-connect-binary address port)
    ;; Like tcp-connect but returns (values binary-input-port binary-output-port).
    (let ([fd (c-socket AF_INET SOCK_STREAM 0)])
      (when (< fd 0)
        (error 'tcp-connect-binary "socket() failed"))
      (let ([addr (make-sockaddr-in address port)])
        (let loop ()
          (let ([rc (c-connect fd addr SOCKADDR_IN_SIZE)])
            (cond
              [(>= rc 0)
               (foreign-free addr)
               (fd->binary-ports fd "tcp-connection")]
              [(= (get-errno) EINTR) (loop)]
              [else
               (foreign-free addr)
               (c-close fd)
               (error 'tcp-connect-binary "connect() failed" address port)]))))))

  ) ;; end library
