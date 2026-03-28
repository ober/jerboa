#!chezscheme
;;; (std net tcp-raw) — Raw fd-based TCP, chez-ssl compatible API
;;;
;;; Provides tcp-connect, tcp-listen, tcp-accept, tcp-close, tcp-read, tcp-write
;;; with the same signatures as (chez-ssl)'s plain TCP functions.
;;; No external library dependency — uses POSIX sockets via Chez FFI.

(library (std net tcp-raw)
  (export
    tcp-connect tcp-listen tcp-accept tcp-close
    tcp-read tcp-write tcp-write-string tcp-read-all
    tcp-set-timeout)

  (import (chezscheme))

  ;; ========== FFI ==========

  ;; Load libc so POSIX socket functions are available at compile time.
  ;; Without this, compile-library fails because foreign-procedure can't
  ;; resolve "socket" etc. during ahead-of-time compilation.
  (define _libc
    (or (guard (e [#t #f]) (load-shared-object "libc.so.7"))
        (guard (e [#t #f]) (load-shared-object "libc.so.6"))
        (guard (e [#t #f]) (load-shared-object "libc.so"))))

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

  ;; errno
  (define c-errno-location
    (if (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb))
      (foreign-procedure "__error" () void*)
      (foreign-procedure "__errno_location" () void*)))
  (define (get-errno) (foreign-ref 'int (c-errno-location) 0))
  (define EINTR 4)

  ;; Constants
  (define AF_INET 2)
  (define SOCK_STREAM 1)
  (define SOL_SOCKET 1)
  (define SO_REUSEADDR 2)
  (define SO_RCVTIMEO 20)
  (define SO_SNDTIMEO 21)
  (define SOCKADDR_IN_SIZE 16)

  ;; ========== sockaddr_in ==========

  (define (make-sockaddr-in address port)
    (let ([buf (foreign-alloc SOCKADDR_IN_SIZE)])
      (let lp ([i 0])
        (when (< i SOCKADDR_IN_SIZE)
          (foreign-set! 'unsigned-8 buf i 0)
          (lp (+ i 1))))
      (foreign-set! 'unsigned-short buf 0 AF_INET)
      (foreign-set! 'unsigned-short buf 2 (c-htons port))
      (let ([addr-ptr (+ buf 4)])
        (when (= (c-inet-pton AF_INET address addr-ptr) 0)
          (foreign-free buf)
          (error 'make-sockaddr-in "invalid address" address)))
      buf))

  ;; ========== API (chez-ssl compatible) ==========

  (define (tcp-connect host port)
    ;; Returns fd (integer), not ports
    (let ([fd (c-socket AF_INET SOCK_STREAM 0)])
      (when (< fd 0)
        (error 'tcp-connect "socket() failed"))
      (let ([addr (make-sockaddr-in host port)])
        (let loop ()
          (let ([rc (c-connect fd addr SOCKADDR_IN_SIZE)])
            (cond
              [(>= rc 0)
               (foreign-free addr)
               fd]
              [(= (get-errno) EINTR) (loop)]
              [else
               (foreign-free addr)
               (c-close fd)
               (error 'tcp-connect "connect() failed" host port)]))))))

  (define tcp-listen
    (case-lambda
      [(port)        (tcp-listen port 128)]
      [(port backlog)
       (let ([fd (c-socket AF_INET SOCK_STREAM 0)])
         (when (< fd 0)
           (error 'tcp-listen "socket() failed"))
         ;; SO_REUSEADDR
         (let ([one (foreign-alloc 4)])
           (foreign-set! 'int one 0 1)
           (c-setsockopt fd SOL_SOCKET SO_REUSEADDR one 4)
           (foreign-free one))
         ;; Bind to 0.0.0.0:port
         (let ([addr (make-sockaddr-in "0.0.0.0" port)])
           (let ([rc (c-bind fd addr SOCKADDR_IN_SIZE)])
             (foreign-free addr)
             (when (< rc 0)
               (c-close fd)
               (error 'tcp-listen "bind() failed" port))))
         ;; Listen
         (when (< (c-listen fd backlog) 0)
           (c-close fd)
           (error 'tcp-listen "listen() failed"))
         fd)]))

  (define (tcp-accept listen-fd)
    ;; Returns (values client-fd addr-string)
    (let loop ()
      (let ([client-fd (c-accept listen-fd 0 0)])
        (cond
          [(>= client-fd 0)
           (values client-fd "")]
          [(= (get-errno) EINTR) (loop)]
          [else (error 'tcp-accept "accept() failed")]))))

  (define (tcp-close fd)
    (c-close fd))

  (define (tcp-read fd buf len)
    ;; Read up to len bytes into bytevector buf. Returns bytes read.
    (let loop ()
      (let ([n (c-read fd buf len)])
        (cond
          [(>= n 0) n]
          [(= (get-errno) EINTR) (loop)]
          [else -1]))))

  (define (tcp-write fd bv)
    ;; Write entire bytevector to fd
    (let ([total (bytevector-length bv)])
      (let loop ([offset 0])
        (when (< offset total)
          (let ([buf (if (= offset 0) bv
                       (let ([tmp (make-bytevector (- total offset))])
                         (bytevector-copy! bv offset tmp 0 (- total offset))
                         tmp))])
            (let ([n (c-write fd buf (- total offset))])
              (cond
                [(> n 0) (loop (+ offset n))]
                [(= (get-errno) EINTR) (loop offset)]
                [else (error 'tcp-write "write failed")])))))))

  (define (tcp-write-string fd str)
    (tcp-write fd (string->utf8 str)))

  (define (tcp-read-all fd)
    ;; Read all available data, return bytevector
    (let ([chunks '()] [total 0])
      (let loop ()
        (let ([buf (make-bytevector 4096)])
          (let ([n (tcp-read fd buf 4096)])
            (cond
              [(> n 0)
               (set! chunks (cons (cons buf n) chunks))
               (set! total (+ total n))
               (loop)]
              [else
               ;; Assemble result
               (let ([result (make-bytevector total)])
                 (let lp ([cs (reverse chunks)] [off 0])
                   (unless (null? cs)
                     (let ([bv (caar cs)] [n (cdar cs)])
                       (bytevector-copy! bv 0 result off n)
                       (lp (cdr cs) (+ off n)))))
                 result)]))))))

  (define (tcp-set-timeout fd read-secs write-secs)
    ;; Set SO_RCVTIMEO and SO_SNDTIMEO via struct timeval
    (let ([tv (foreign-alloc 16)])  ;; sizeof(struct timeval)
      ;; Read timeout
      (foreign-set! 'long tv 0 read-secs)
      (foreign-set! 'long tv 8 0)
      (c-setsockopt fd SOL_SOCKET SO_RCVTIMEO tv 16)
      ;; Write timeout
      (foreign-set! 'long tv 0 write-secs)
      (c-setsockopt fd SOL_SOCKET SO_SNDTIMEO tv 16)
      (foreign-free tv)))

  ) ;; end library
