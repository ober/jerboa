#!chezscheme
;;; :std/net/socks5-server -- SOCKS5 proxy server
;;;
;;; Implements RFC 1928 SOCKS5 proxy with optional username/password auth (RFC 1929).
;;; Runs a listener thread that accepts connections and spawns relay threads.
;;;
;;; Uses ffi-shim functions exclusively — no raw libc foreign-procedures, no
;;; hardcoded platform constants.  Works on Linux, FreeBSD, macOS, Android.
;;;
;;; API:
;;;   (socks5-start port)                          → handle (no auth, random port if 0)
;;;   (socks5-start port user pass bind-addr)      → handle (with auth)
;;;   (socks5-stop handle)                         → void
;;;   (socks5-port handle)                         → integer
;;;   (socks5-stats handle)                        → string
;;;   (socks5-set-proxy-env! handle)               → void (sets ALL_PROXY etc.)
;;;   (socks5-unset-proxy-env!)                    → void

(library (std net socks5-server)
  (export socks5-start socks5-stop socks5-port socks5-stats
          socks5-set-proxy-env! socks5-unset-proxy-env!)

  (import (chezscheme))

  ;; ========== FFI (all through ffi-shim — portable) ==========

  (define c-listen-tcp-addr
    (foreign-procedure "ffi_stream_listen_tcp_addr" (string int int) int))
  (define c-connect-tcp
    (foreign-procedure "ffi_stream_connect_tcp" (string int) int))
  (define c-accept
    (foreign-procedure "ffi_stream_accept" (int) int))
  (define c-accept-nb
    (foreign-procedure "ffi_stream_accept_nonblock" (int) int))
  (define c-set-nonblock
    (foreign-procedure "ffi_set_nonblock" (int) int))
  (define c-clear-nonblock
    (foreign-procedure "ffi_clear_nonblock" (int) int))
  (define c-close
    (foreign-procedure "ffi_stream_close" (int) void))
  (define c-poll1
    (foreign-procedure "ffi_poll_readable_ms" (int int) int))
  (define c-poll2
    (foreign-procedure "ffi_poll2" (int int int) int))
  (define c-getsockname-port
    (foreign-procedure "ffi_getsockname_port" (int) int))
  (define c-bv-read-exact
    (foreign-procedure "ffi_bv_read_exact" (int u8* int int) int))
  (define c-bv-write-all
    (foreign-procedure "ffi_bv_write_all" (int u8* int int) int))
  (define c-bv-recv
    (foreign-procedure "ffi_bv_recv" (int u8* int int) int))
  (define c-bv-write
    (foreign-procedure "ffi_bv_write" (int u8* int int) int))

  ;; ========== Utilities ==========

  (define (read-bytes fd n)
    ;; Read exactly n bytes, returning bytevector or #f
    (let ([buf (make-bytevector n 0)])
      (if (>= (c-bv-read-exact fd buf 0 n) 0)
          buf
          #f)))

  (define (write-bytes fd bv)
    ;; Write all bytes, return #t on success
    (>= (c-bv-write-all fd bv 0 (bytevector-length bv)) 0))

  (define (make-bv . bytes)
    (u8-list->bytevector bytes))

  ;; ========== SOCKS5 Protocol ==========

  (define (bytevector-contains bv val)
    (let loop ([i 0])
      (cond
        [(= i (bytevector-length bv)) #f]
        [(= (bytevector-u8-ref bv i) val) #t]
        [else (loop (+ i 1))])))

  (define (handle-greeting fd auth?)
    (let ([hdr (read-bytes fd 2)])
      (and hdr
           (= (bytevector-u8-ref hdr 0) 5)  ;; SOCKS5
           (let* ([nmethods (bytevector-u8-ref hdr 1)]
                  [methods (read-bytes fd nmethods)])
             (and methods
                  (if auth?
                      (if (bytevector-contains methods 2)
                          (write-bytes fd (make-bv 5 2))
                          (begin (write-bytes fd (make-bv 5 #xff)) #f))
                      (if (bytevector-contains methods 0)
                          (write-bytes fd (make-bv 5 0))
                          (begin (write-bytes fd (make-bv 5 #xff)) #f))))))))

  (define (handle-auth fd username password)
    ;; RFC 1929: VER=1 ULEN USER PLEN PASS → VER STATUS (0=success)
    (let ([ver (read-bytes fd 1)])
      (and ver (= (bytevector-u8-ref ver 0) 1)
           (let ([ulen-bv (read-bytes fd 1)])
             (and ulen-bv
                  (let* ([ulen (bytevector-u8-ref ulen-bv 0)]
                         [user (read-bytes fd ulen)])
                    (and user
                         (let ([plen-bv (read-bytes fd 1)])
                           (and plen-bv
                                (let* ([plen (bytevector-u8-ref plen-bv 0)]
                                       [pass (read-bytes fd plen)])
                                  (and pass
                                       (let ([u (utf8->string user)]
                                             [p (utf8->string pass)])
                                         (if (and (string=? u username)
                                                  (string=? p password))
                                             (write-bytes fd (u8-list->bytevector '(1 0)))
                                             (begin
                                               (write-bytes fd (u8-list->bytevector '(1 1)))
                                               #f))))))))))))))

  (define (handle-request fd)
    ;; Parse CONNECT request, return (values host port) or (values #f #f)
    (let ([hdr (read-bytes fd 4)])
      (if (not hdr)
          (values #f #f)
          (let ([ver (bytevector-u8-ref hdr 0)]
                [cmd (bytevector-u8-ref hdr 1)]
                [atyp (bytevector-u8-ref hdr 3)])
            (if (not (and (= ver 5) (= cmd 1)))  ;; Only CONNECT
                (begin
                  (write-bytes fd (u8-list->bytevector '(5 7 0 1 0 0 0 0 0 0)))
                  (values #f #f))
                (case atyp
                  [(1)  ;; IPv4
                   (let ([addr-bv (read-bytes fd 4)]
                         [port-bv (read-bytes fd 2)])
                     (if (or (not addr-bv) (not port-bv))
                         (values #f #f)
                         (let ([a (bytevector-u8-ref addr-bv 0)]
                               [b (bytevector-u8-ref addr-bv 1)]
                               [c (bytevector-u8-ref addr-bv 2)]
                               [d (bytevector-u8-ref addr-bv 3)]
                               [p (bytevector-u16-ref port-bv 0 (endianness big))])
                           (values (format "~a.~a.~a.~a" a b c d) p))))]
                  [(3)  ;; Domain name
                   (let ([len-bv (read-bytes fd 1)])
                     (and len-bv
                          (let* ([len (bytevector-u8-ref len-bv 0)]
                                 [name-bv (read-bytes fd len)]
                                 [port-bv (read-bytes fd 2)])
                            (if (or (not name-bv) (not port-bv))
                                (values #f #f)
                                (values (utf8->string name-bv)
                                        (bytevector-u16-ref port-bv 0 (endianness big)))))))]
                  [else
                   (write-bytes fd (u8-list->bytevector '(5 8 0 1 0 0 0 0 0 0)))
                   (values #f #f)]))))))

  (define (send-reply fd rep)
    (write-bytes fd (u8-list->bytevector (list 5 rep 0 1 0 0 0 0 0 0))))

  ;; ========== Relay ==========

  (define (relay-data client-fd target-fd)
    ;; Bidirectional relay using ffi_poll2 + ffi_bv_recv/ffi_bv_write
    (let ([buf (make-bytevector 8192 0)])
      (let loop ()
        (let ([mask (c-poll2 client-fd target-fd 60000)])
          (when (> mask 0)
            (let ([ok #t])
              ;; client → target  (bit 0)
              (when (> (fxlogand mask 1) 0)
                (let ([r (c-bv-recv client-fd buf 0 8192)])
                  (if (<= r 0)
                      (set! ok #f)
                      (when (< (c-bv-write-all target-fd buf 0 r) 0)
                        (set! ok #f)))))
              ;; target → client  (bit 1)
              (when (and ok (> (fxlogand mask 2) 0))
                (let ([r (c-bv-recv target-fd buf 0 8192)])
                  (if (<= r 0)
                      (set! ok #f)
                      (when (< (c-bv-write-all client-fd buf 0 r) 0)
                        (set! ok #f)))))
              ;; HUP/ERR bits: 4 = fd1, 8 = fd2
              (when (and ok
                         (= (fxlogand mask 4) 0)
                         (= (fxlogand mask 8) 0))
                (loop))))))))

  ;; ========== Handle a single client ==========

  (define (handle-client client-fd auth-info stats-box)
    (guard (e [#t (c-close client-fd)])
      (let ([auth? (and auth-info #t)])
        (when (handle-greeting client-fd auth?)
          (when (or (not auth?)
                    (handle-auth client-fd (car auth-info) (cdr auth-info)))
            (let-values ([(host port) (handle-request client-fd)])
              (when (and host port)
                (let ([target-fd (c-connect-tcp host port)])
                  (if (< target-fd 0)
                      (send-reply client-fd 5)  ;; connection refused
                      (begin
                        (send-reply client-fd 0)  ;; success
                        (let ([cur (unbox stats-box)])
                          (set-box! stats-box
                            (cons (+ (car cur) 1) (cdr cur))))
                        (relay-data client-fd target-fd)
                        (c-close target-fd)))))))
          (c-close client-fd)))))

  ;; ========== Server ==========

  (define (make-handle fd stop stats port thd)
    (vector fd stop stats port thd))
  (define (handle-fd h)    (vector-ref h 0))
  (define (handle-stop h)  (vector-ref h 1))
  (define (handle-stats h) (vector-ref h 2))
  (define (handle-port* h) (vector-ref h 3))
  (define (handle-thd h)   (vector-ref h 4))

  (define (server-loop listener-fd stop-box auth-info stats-box)
    (c-set-nonblock listener-fd)
    (let loop ()
      (unless (unbox stop-box)
        (let ([ready (c-poll1 listener-fd 500)])
          (when (> ready 0)
            (let ([client-fd (c-accept listener-fd)])
              (when (>= client-fd 0)
                (fork-thread
                  (lambda ()
                    (handle-client client-fd auth-info stats-box)))))))
        (loop))))

  (define socks5-start
    (case-lambda
      [(port)
       (start-server port #f "127.0.0.1")]
      [(port username password bind-addr)
       (start-server port (cons username password) bind-addr)]))

  (define (start-server port auth-info bind-addr)
    (let ([fd (c-listen-tcp-addr bind-addr port 128)])
      (when (< fd 0)
        (error 'socks5-start (format "failed to listen on ~a:~a (errno ~a)"
                                     bind-addr port (- fd))))
      (let* ([actual-port (c-getsockname-port fd)]
             [stop-box (box #f)]
             [stats-box (box (cons 0 0))]
             [thd (fork-thread
                    (lambda ()
                      (server-loop fd stop-box auth-info stats-box)))])
        (make-handle fd stop-box stats-box actual-port thd))))

  (define (socks5-stop handle)
    (set-box! (handle-stop handle) #t)
    (sleep (make-time 'time-duration 0 1))
    (c-close (handle-fd handle)))

  (define (socks5-port handle)
    (handle-port* handle))

  (define (socks5-stats handle)
    (let ([s (unbox (handle-stats handle))])
      (format "connections: ~a" (car s))))

  (define (socks5-set-proxy-env! handle)
    (let ([port (socks5-port handle)])
      (putenv "ALL_PROXY" (format "socks5h://127.0.0.1:~a" port))
      (putenv "all_proxy" (format "socks5h://127.0.0.1:~a" port))
      (putenv "http_proxy" (format "socks5h://127.0.0.1:~a" port))
      (putenv "https_proxy" (format "socks5h://127.0.0.1:~a" port))
      (putenv "HTTP_PROXY" (format "socks5h://127.0.0.1:~a" port))
      (putenv "HTTPS_PROXY" (format "socks5h://127.0.0.1:~a" port))))

  (define (socks5-unset-proxy-env!)
    (putenv "ALL_PROXY" "")
    (putenv "all_proxy" "")
    (putenv "http_proxy" "")
    (putenv "https_proxy" "")
    (putenv "HTTP_PROXY" "")
    (putenv "HTTPS_PROXY" ""))

) ;; end library
