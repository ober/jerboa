#!chezscheme
;;; :std/net/udp -- UDP datagram sockets via FFI
;;;
;;; Provides UDP socket operations using POSIX socket API.
;;; All addresses are IPv4 strings, ports are integers.

(library (std net udp)
  (export
    udp-open-socket udp-close-socket
    udp-bind udp-send-to udp-receive-from
    udp-set-broadcast! udp-set-timeout!)

  (import (chezscheme))

  ;; ========== FFI ==========

  (define _libc-loaded
    (let ((v (getenv "JEMACS_STATIC")))
      (if (and v (not (string=? v "")) (not (string=? v "0")))
          #f
          (load-shared-object #f))))

  (define c-socket    (foreign-procedure "socket" (int int int) int))
  (define c-bind      (foreign-procedure "bind" (int void* int) int))
  (define c-close     (foreign-procedure "close" (int) int))
  (define c-sendto    (foreign-procedure "sendto" (int void* size_t int void* int) ssize_t))
  (define c-recvfrom  (foreign-procedure "recvfrom" (int void* size_t int void* void*) ssize_t))
  (define c-setsockopt (foreign-procedure "setsockopt" (int int int void* int) int))
  (define c-htons     (foreign-procedure "htons" (unsigned-short) unsigned-short))
  (define c-ntohs     (foreign-procedure "ntohs" (unsigned-short) unsigned-short))
  (define c-inet-pton (foreign-procedure "inet_pton" (int string void*) int))
  (define c-inet-ntop (foreign-procedure "inet_ntop" (int void* void* int) void*))

  ;; Constants
  (define AF_INET 2)
  (define SOCK_DGRAM 2)
  (define SOL_SOCKET 1)
  (define SO_BROADCAST 6)
  (define SO_RCVTIMEO 20)
  (define SOCKADDR_IN_SIZE 16)
  (define INET_ADDRSTRLEN 16)

  ;; ========== sockaddr_in helpers ==========

  (define (make-sockaddr-in address port)
    (let ([buf (foreign-alloc SOCKADDR_IN_SIZE)])
      ;; Zero the struct
      (let lp ([i 0])
        (when (< i SOCKADDR_IN_SIZE)
          (foreign-set! 'unsigned-8 buf i 0)
          (lp (+ i 1))))
      ;; sin_family = AF_INET
      (foreign-set! 'unsigned-short buf 0 AF_INET)
      ;; sin_port = htons(port)
      (foreign-set! 'unsigned-short buf 2 (c-htons port))
      ;; sin_addr (offset 4)
      (let ([addr-ptr (+ buf 4)])
        (when (= (c-inet-pton AF_INET address addr-ptr) 0)
          (foreign-free buf)
          (error 'make-sockaddr-in "invalid address" address)))
      buf))

  (define (extract-sockaddr-in buf)
    ;; Returns (values address-string port)
    (let ([port (c-ntohs (foreign-ref 'unsigned-short buf 2))]
          [addr-buf (foreign-alloc INET_ADDRSTRLEN)])
      (c-inet-ntop AF_INET (+ buf 4) addr-buf INET_ADDRSTRLEN)
      (let ([addr (let lp ([i 0] [chars '()])
                    (let ([b (foreign-ref 'unsigned-8 addr-buf i)])
                      (if (= b 0)
                        (list->string (reverse chars))
                        (lp (+ i 1) (cons (integer->char b) chars)))))])
        (foreign-free addr-buf)
        (values addr port))))

  ;; ========== Public API ==========

  (define (udp-open-socket)
    (let ([fd (c-socket AF_INET SOCK_DGRAM 0)])
      (when (< fd 0)
        (error 'udp-open-socket "socket() failed"))
      fd))

  (define (udp-close-socket fd)
    (c-close fd))

  (define (udp-bind fd address port)
    (let ([addr (make-sockaddr-in address port)])
      (let ([rc (c-bind fd addr SOCKADDR_IN_SIZE)])
        (foreign-free addr)
        (when (< rc 0)
          (error 'udp-bind "bind() failed" address port)))))

  (define (udp-send-to fd bv address port)
    ;; Send bytevector to address:port. Returns bytes sent.
    (let ([addr (make-sockaddr-in address port)]
          [len (bytevector-length bv)]
          [buf (foreign-alloc (bytevector-length bv))])
      ;; Copy bytevector to foreign memory
      (let lp ([i 0])
        (when (< i len)
          (foreign-set! 'unsigned-8 buf i (bytevector-u8-ref bv i))
          (lp (+ i 1))))
      (let ([n (c-sendto fd buf len 0 addr SOCKADDR_IN_SIZE)])
        (foreign-free buf)
        (foreign-free addr)
        (when (< n 0)
          (error 'udp-send-to "sendto() failed" address port))
        n)))

  (define (udp-receive-from fd max-size)
    ;; Receive up to max-size bytes. Returns (values bytevector sender-addr sender-port).
    (let ([buf (foreign-alloc max-size)]
          [addr (foreign-alloc SOCKADDR_IN_SIZE)]
          [addrlen (foreign-alloc 4)])
      (foreign-set! 'int addrlen 0 SOCKADDR_IN_SIZE)
      (let ([n (c-recvfrom fd buf max-size 0 addr addrlen)])
        (cond
          [(< n 0)
           (foreign-free buf)
           (foreign-free addr)
           (foreign-free addrlen)
           (error 'udp-receive-from "recvfrom() failed")]
          [else
           (let ([bv (make-bytevector n)])
             (let lp ([i 0])
               (when (< i n)
                 (bytevector-u8-set! bv i (foreign-ref 'unsigned-8 buf i))
                 (lp (+ i 1))))
             (foreign-free buf)
             (foreign-free addrlen)
             (let-values ([(sender-addr sender-port) (extract-sockaddr-in addr)])
               (foreign-free addr)
               (values bv sender-addr sender-port)))]))))

  (define (udp-set-broadcast! fd enable?)
    (let ([val (foreign-alloc 4)])
      (foreign-set! 'int val 0 (if enable? 1 0))
      (let ([rc (c-setsockopt fd SOL_SOCKET SO_BROADCAST val 4)])
        (foreign-free val)
        (when (< rc 0)
          (error 'udp-set-broadcast! "setsockopt() failed")))))

  (define (udp-set-timeout! fd seconds)
    ;; Set SO_RCVTIMEO. struct timeval = {long tv_sec, long tv_usec}
    (let* ([tv-size (* 2 (foreign-sizeof 'long))]
           [tv (foreign-alloc tv-size)])
      (foreign-set! 'long tv 0 (exact (floor seconds)))
      (foreign-set! 'long tv (foreign-sizeof 'long)
                    (exact (floor (* (- seconds (floor seconds)) 1000000))))
      (let ([rc (c-setsockopt fd SOL_SOCKET SO_RCVTIMEO tv tv-size)])
        (foreign-free tv)
        (when (< rc 0)
          (error 'udp-set-timeout! "setsockopt() failed")))))

  ) ;; end library
