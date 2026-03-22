#!chezscheme
;;; :std/net/socks -- SOCKS4/SOCKS5 proxy client
;;;
;;; Connects to a remote host through a SOCKS proxy.
;;; Returns standard Chez Scheme port pairs for transparent use.

(library (std net socks)
  (export socks4-connect socks5-connect socks-connect with-socks-proxy)

  (import (chezscheme))

  ;; ========== Helpers ==========

  (define (string->ip-bytes host)
    ;; Parse "a.b.c.d" -> bytevector of 4 bytes.
    ;; Returns #f if not a valid dotted-quad (i.e. a hostname).
    (let ([parts (string-split host #\.)])
      (and (= (length parts) 4)
           (let ([nums (map string->number parts)])
             (and (for-all (lambda (n) (and n (fixnum? n) (<= 0 n 255))) nums)
                  (u8-list->bytevector nums))))))

  (define (string-split str ch)
    ;; Split string on character.
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(= i (string-length str))
         (reverse (cons (substring str start i) acc))]
        [(char=? (string-ref str i) ch)
         (loop (+ i 1) (+ i 1)
               (cons (substring str start i) acc))]
        [else
         (loop (+ i 1) start acc)])))

  (define (resolve-hostname host)
    ;; Resolve a hostname to an IPv4 address string using getaddrinfo.
    ;; Returns the dotted-quad string.
    (let* ([c-getaddrinfo (foreign-procedure "getaddrinfo"
                            (string string void* void*) int)]
           [c-freeaddrinfo (foreign-procedure "freeaddrinfo" (void*) void)]
           [c-inet-ntop (foreign-procedure "inet_ntop"
                          (int void* u8* int) string)]
           [result-ptr (foreign-alloc 8)])  ;; pointer to struct addrinfo*
      (foreign-set! 'void* result-ptr 0 0)
      (let ([rc (c-getaddrinfo host #f 0 result-ptr)])
        (when (not (= rc 0))
          (foreign-free result-ptr)
          (error 'resolve-hostname "DNS resolution failed" host))
        (let* ([ai (foreign-ref 'void* result-ptr 0)]
               ;; struct addrinfo layout on Linux x86_64:
               ;;   int ai_flags        0
               ;;   int ai_family       4
               ;;   int ai_socktype     8
               ;;   int ai_protocol    12
               ;;   socklen_t ai_addrlen 16
               ;;   struct sockaddr *ai_addr 24 (after padding)
               ;;   char *ai_canonname  32
               ;;   struct addrinfo *ai_next 40
               [ai-family (foreign-ref 'int ai 4)]
               [ai-addr   (foreign-ref 'void* ai 24)])
          ;; We only handle AF_INET (2)
          (unless (= ai-family 2)
            (c-freeaddrinfo ai)
            (foreign-free result-ptr)
            (error 'resolve-hostname "no IPv4 address found" host))
          ;; struct sockaddr_in: sin_family(2) sin_port(2) sin_addr(4)
          ;; sin_addr is at offset 4
          (let ([buf (make-bytevector 16)])  ;; INET_ADDRSTRLEN = 16
            (let ([str (c-inet-ntop 2 (+ ai-addr 4) buf 16)])
              (c-freeaddrinfo ai)
              (foreign-free result-ptr)
              (unless str
                (error 'resolve-hostname "inet_ntop failed" host))
              str))))))

  (define (host->ip-bytes host)
    ;; Return 4-byte IP for a host (dotted-quad or hostname).
    (let ([direct (string->ip-bytes host)])
      (or direct
          (let ([resolved (resolve-hostname host)])
            (or (string->ip-bytes resolved)
                (error 'host->ip-bytes "cannot resolve" host))))))

  ;; ========== Low-level I/O on binary ports ==========

  (define (write-u8 port byte)
    (put-u8 port byte))

  (define (write-u16-be port val)
    (put-u8 port (bitwise-and (bitwise-arithmetic-shift-right val 8) #xFF))
    (put-u8 port (bitwise-and val #xFF)))

  (define (write-bytes port bv)
    (put-bytevector port bv))

  (define (read-u8! port)
    (let ([b (get-u8 port)])
      (when (eof-object? b)
        (error 'socks "unexpected EOF from proxy"))
      b))

  (define (read-bytes! port n)
    (let ([bv (get-bytevector-n port n)])
      (when (or (eof-object? bv) (< (bytevector-length bv) n))
        (error 'socks "short read from proxy"))
      bv))

  ;; ========== SOCKS4 ==========

  (define (socks4-connect proxy-host proxy-port target-host target-port)
    ;; Connect through a SOCKS4 proxy.
    ;; Returns (values input-port output-port).
    (let-values ([(in out) (tcp-connect* proxy-host proxy-port)])
      (guard (exn [#t (close-port in) (close-port out) (raise exn)])
        ;; Resolve target to IP (SOCKS4 requires IP, not hostname)
        (let ([ip (host->ip-bytes target-host)])
          ;; Send connect request:
          ;;   VN (1) = 4
          ;;   CD (1) = 1 (CONNECT)
          ;;   DSTPORT (2) big-endian
          ;;   DSTIP (4)
          ;;   USERID (variable) — empty
          ;;   NULL (1)
          (write-u8 out 4)           ;; VN
          (write-u8 out 1)           ;; CD = CONNECT
          (write-u16-be out target-port)
          (write-bytes out ip)
          (write-u8 out 0)           ;; empty userid + null terminator
          (flush-output-port out)

          ;; Read reply: VN(1) CD(1) DSTPORT(2) DSTIP(4) — 8 bytes
          (let* ([reply (read-bytes! in 8)]
                 [reply-cd (bytevector-u8-ref reply 1)])
            ;; VN should be 0 in reply, CD=90 means granted
            (unless (= reply-cd 90)
              (close-port in)
              (close-port out)
              (error 'socks4-connect
                     "SOCKS4 request rejected"
                     (socks4-error-message reply-cd)))
            (values in out))))))

  (define (socks4-error-message cd)
    (case cd
      [(91) "request rejected or failed"]
      [(92) "cannot connect to identd on client"]
      [(93) "client identd reports different user-id"]
      [else (format "unknown error code ~a" cd)]))

  ;; ========== SOCKS5 ==========

  (define socks5-connect
    (case-lambda
      [(proxy-host proxy-port target-host target-port)
       (socks5-connect proxy-host proxy-port target-host target-port #f #f)]
      [(proxy-host proxy-port target-host target-port username password)
       (let-values ([(in out) (tcp-connect* proxy-host proxy-port)])
         (guard (exn [#t (close-port in) (close-port out) (raise exn)])
           ;; === Greeting ===
           ;; Version(1)=5, NMethods(1), Methods...
           (cond
             [(and username password)
              ;; Offer: no-auth (0) and username/password (2)
              (write-u8 out 5)  ;; VER
              (write-u8 out 2)  ;; NMETHODS
              (write-u8 out 0)  ;; NO AUTH
              (write-u8 out 2)] ;; USERNAME/PASSWORD
             [else
              ;; Offer: no-auth only
              (write-u8 out 5)
              (write-u8 out 1)
              (write-u8 out 0)])
           (flush-output-port out)

           ;; Server chooses method: VER(1) METHOD(1)
           (let* ([ver (read-u8! in)]
                  [method (read-u8! in)])
             (unless (= ver 5)
               (error 'socks5-connect "bad SOCKS version in reply" ver))

             ;; Handle auth method
             (case method
               [(0) (void)]  ;; no auth required
               [(2)
                ;; Username/password auth (RFC 1929)
                (unless (and username password)
                  (error 'socks5-connect
                         "proxy requires auth but no credentials provided"))
                (let ([u-bv (string->utf8 username)]
                      [p-bv (string->utf8 password)])
                  (write-u8 out 1)  ;; auth sub-version
                  (write-u8 out (bytevector-length u-bv))
                  (write-bytes out u-bv)
                  (write-u8 out (bytevector-length p-bv))
                  (write-bytes out p-bv)
                  (flush-output-port out)
                  ;; Read auth reply: VER(1) STATUS(1)
                  (let* ([auth-ver (read-u8! in)]
                         [auth-status (read-u8! in)])
                    (unless (= auth-status 0)
                      (error 'socks5-connect
                             "SOCKS5 authentication failed"))))]
               [(#xFF)
                (error 'socks5-connect
                       "no acceptable authentication method")]
               [else
                (error 'socks5-connect
                       "unsupported auth method" method)])

             ;; === Connect request ===
             ;; VER(1)=5, CMD(1)=1(CONNECT), RSV(1)=0, ATYP(1), DST.ADDR, DST.PORT(2)
             (write-u8 out 5)   ;; VER
             (write-u8 out 1)   ;; CMD = CONNECT
             (write-u8 out 0)   ;; RSV

             ;; Determine address type
             (let ([ip (string->ip-bytes target-host)])
               (cond
                 [ip
                  ;; IPv4
                  (write-u8 out 1)  ;; ATYP = IPv4
                  (write-bytes out ip)]
                 [else
                  ;; Domain name (SOCKS5 supports this — proxy resolves)
                  (let ([domain-bv (string->utf8 target-host)])
                    (write-u8 out 3)  ;; ATYP = DOMAINNAME
                    (write-u8 out (bytevector-length domain-bv))
                    (write-bytes out domain-bv))]))

             (write-u16-be out target-port)
             (flush-output-port out)

             ;; === Read connect reply ===
             ;; VER(1), REP(1), RSV(1), ATYP(1), BND.ADDR(variable), BND.PORT(2)
             (let* ([rep-ver (read-u8! in)]
                    [rep     (read-u8! in)]
                    [_rsv    (read-u8! in)]
                    [atyp    (read-u8! in)])
               (unless (= rep 0)
                 (close-port in) (close-port out)
                 (error 'socks5-connect
                        "SOCKS5 connect failed"
                        (socks5-error-message rep)))
               ;; Skip BND.ADDR based on type
               (case atyp
                 [(1) (read-bytes! in 4)]    ;; IPv4
                 [(3)                         ;; Domain
                  (let ([dlen (read-u8! in)])
                    (read-bytes! in dlen))]
                 [(4) (read-bytes! in 16)]   ;; IPv6
                 [else (error 'socks5-connect "unknown ATYP" atyp)])
               ;; Skip BND.PORT
               (read-bytes! in 2)

               (values in out)))))]))

  (define (socks5-error-message rep)
    (case rep
      [(1) "general SOCKS server failure"]
      [(2) "connection not allowed by ruleset"]
      [(3) "network unreachable"]
      [(4) "host unreachable"]
      [(5) "connection refused"]
      [(6) "TTL expired"]
      [(7) "command not supported"]
      [(8) "address type not supported"]
      [else (format "unknown error ~a" rep)]))

  ;; ========== Auto-detecting connect ==========

  (define socks-connect
    (case-lambda
      [(proxy-host proxy-port target-host target-port)
       (socks-connect proxy-host proxy-port target-host target-port #f #f)]
      [(proxy-host proxy-port target-host target-port username password)
       ;; Try SOCKS5 first; fall back to SOCKS4 on failure.
       (guard (exn
                [#t
                 ;; SOCKS5 failed — try SOCKS4 (no auth support)
                 (socks4-connect proxy-host proxy-port
                                 target-host target-port)])
         (socks5-connect proxy-host proxy-port
                         target-host target-port
                         username password))]))

  ;; ========== Convenience macro ==========

  (define-syntax with-socks-proxy
    (syntax-rules ()
      [(_ ((in out) proxy-host proxy-port target-host target-port) body ...)
       (let-values ([(in out) (socks-connect proxy-host proxy-port
                                             target-host target-port)])
         (dynamic-wind
           (lambda () (void))
           (lambda () body ...)
           (lambda ()
             (close-port in)
             (close-port out))))]
      [(_ ((in out) proxy-host proxy-port target-host target-port
                    username password) body ...)
       (let-values ([(in out) (socks5-connect proxy-host proxy-port
                                              target-host target-port
                                              username password)])
         (dynamic-wind
           (lambda () (void))
           (lambda () body ...)
           (lambda ()
             (close-port in)
             (close-port out))))]))

  ;; ========== TCP connect (direct, using Chez built-in) ==========

  (define (tcp-connect* host port)
    ;; Open a TCP connection, returning binary port pair.
    ;; Uses Chez's built-in tcp-connect which returns textual ports;
    ;; we need binary ports for protocol work.
    ;;
    ;; Chez Scheme's tcp-connect is not available in all builds.
    ;; Use POSIX sockets directly for portability.
    (let* ([c-socket   (foreign-procedure "socket" (int int int) int)]
           [c-connect  (foreign-procedure "connect" (int void* int) int)]
           [c-close    (foreign-procedure "close" (int) int)]
           [c-htons    (foreign-procedure "htons" (unsigned-short) unsigned-short)]
           [c-inet-pton (foreign-procedure "inet_pton" (int string void*) int)]
           [AF_INET 2]
           [SOCK_STREAM 1]
           [SOCKADDR_IN_SIZE 16])
      ;; Resolve hostname to IP if needed
      (let ([ip-str (let ([direct (string->ip-bytes host)])
                      (if direct host (resolve-hostname host)))])
        (let ([fd (c-socket AF_INET SOCK_STREAM 0)])
          (when (< fd 0)
            (error 'tcp-connect* "socket() failed"))
          ;; Build sockaddr_in
          (let ([addr (foreign-alloc SOCKADDR_IN_SIZE)])
            ;; Zero it
            (let lp ([i 0])
              (when (< i SOCKADDR_IN_SIZE)
                (foreign-set! 'unsigned-8 addr i 0)
                (lp (+ i 1))))
            (foreign-set! 'unsigned-short addr 0 AF_INET)
            (foreign-set! 'unsigned-short addr 2 (c-htons port))
            (when (= (c-inet-pton AF_INET ip-str (+ addr 4)) 0)
              (foreign-free addr)
              (c-close fd)
              (error 'tcp-connect* "invalid address" ip-str))
            (let ([rc (c-connect fd addr SOCKADDR_IN_SIZE)])
              (foreign-free addr)
              (when (< rc 0)
                (c-close fd)
                (error 'tcp-connect* "connect() failed" host port)))
            ;; Create binary ports from fd
            (fd->binary-ports fd))))))

  (define (fd->binary-ports fd)
    ;; Wrap a socket FD as binary input + output ports.
    (let ([c-read  (foreign-procedure "read" (int u8* size_t) ssize_t)]
          [c-write (foreign-procedure "write" (int u8* size_t) ssize_t)]
          [c-close (foreign-procedure "close" (int) int)]
          [closed? #f])
      (let ([in (make-custom-binary-input-port
                  "socks-in"
                  (lambda (bv start count)
                    (if closed? 0
                      (let ([buf (make-bytevector count)])
                        (let ([n (c-read fd buf count)])
                          (cond
                            [(> n 0)
                             (bytevector-copy! buf 0 bv start n)
                             n]
                            [else 0])))))
                  #f #f
                  (lambda ()
                    (unless closed?
                      (set! closed? #t)
                      (c-close fd))))]
            [out (make-custom-binary-output-port
                   "socks-out"
                   (lambda (bv start count)
                     (if closed? 0
                       (let ([buf (make-bytevector count)])
                         (bytevector-copy! bv start buf 0 count)
                         (let loop ([written 0])
                           (if (= written count)
                             count
                             (let ([n (c-write fd
                                        (let ([tmp (make-bytevector (- count written))])
                                          (bytevector-copy! buf written tmp 0 (- count written))
                                          tmp)
                                        (- count written))])
                               (if (> n 0)
                                 (loop (+ written n))
                                 count)))))))
                   #f #f #f)])  ;; no close proc — input port handles fd close
        (values in out))))

  ) ;; end library
