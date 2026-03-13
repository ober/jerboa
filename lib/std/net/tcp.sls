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

(library (std net tcp)
  (export
    tcp-listen tcp-accept tcp-close
    tcp-connect
    tcp-server? tcp-server-port
    with-tcp-server)

  (import (chezscheme))

  ;; ========== FFI ==========

  ;; Load libc for POSIX socket functions
  (define load-libc (load-shared-object #f))

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

  ;; Constants
  (define AF_INET 2)
  (define SOCK_STREAM 1)
  (define SOL_SOCKET 1)
  (define SO_REUSEADDR 2)
  (define SOCKADDR_IN_SIZE 16)  ;; sizeof(struct sockaddr_in) on Linux

  ;; ========== sockaddr_in helpers ==========

  (define (make-sockaddr-in address port)
    ;; Build a struct sockaddr_in in foreign memory
    (let ([buf (foreign-alloc SOCKADDR_IN_SIZE)])
      ;; Zero the struct
      (let lp ([i 0])
        (when (< i SOCKADDR_IN_SIZE)
          (foreign-set! 'unsigned-8 buf i 0)
          (lp (+ i 1))))
      ;; sin_family = AF_INET (offset 0, 2 bytes)
      (foreign-set! 'unsigned-short buf 0 AF_INET)
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
    (let ([client-fd (c-accept (tcp-server-fd srv) 0 0)])
      (when (< client-fd 0)
        (error 'tcp-accept "accept() failed"))
      (fd->ports client-fd "tcp-client")))

  (define (tcp-close srv)
    (c-close (tcp-server-fd srv)))

  ;; ========== TCP Client ==========

  (define (tcp-connect address port)
    ;; Connect to a TCP server. Returns (values input-port output-port).
    (let ([fd (c-socket AF_INET SOCK_STREAM 0)])
      (when (< fd 0)
        (error 'tcp-connect "socket() failed"))
      (let ([addr (make-sockaddr-in address port)])
        (let ([rc (c-connect fd addr SOCKADDR_IN_SIZE)])
          (foreign-free addr)
          (when (< rc 0)
            (c-close fd)
            (error 'tcp-connect "connect() failed" address port))))
      (fd->ports fd "tcp-connection")))

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
    (let ([in (make-custom-binary-input-port
                (string-append name "-in")
                (lambda (bv start count)
                  ;; read callback
                  (let ([buf (make-bytevector count)])
                    (let ([n (c-read fd buf count)])
                      (if (<= n 0)
                        0  ;; EOF
                        (begin
                          (bytevector-copy! buf 0 bv start n)
                          n)))))
                #f  ;; get-position
                #f  ;; set-position!
                (lambda () (c-close fd)))]
          [out (make-custom-binary-output-port
                 (string-append name "-out")
                 (lambda (bv start count)
                   ;; write callback
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
                           (if (<= n 0)
                             written
                             (lp (+ written n))))))))
                 #f  ;; get-position
                 #f  ;; set-position!
                 #f)])  ;; don't double-close
      (values
        (transcoded-port in (make-transcoder (utf-8-codec)
                              (eol-style none)
                              (error-handling-mode replace)))
        (transcoded-port out (make-transcoder (utf-8-codec)
                               (eol-style none)
                               (error-handling-mode replace))))))

  ) ;; end library
