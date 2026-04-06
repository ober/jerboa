#!chezscheme
;;; (std net socks5-server) — SOCKS5 proxy server via Rust FFI
;;;
;;; Starts a local SOCKS5 proxy server (RFC 1928) backed by the Rust
;;; implementation in libjerboa_native.  Supports no-auth and
;;; username/password authentication (RFC 1929).
;;;
;;; Usage:
;;;   (import (std net socks5-server))
;;;
;;;   ;; Start a proxy on a random port, no auth
;;;   (define proxy (socks5-start))
;;;   (socks5-port proxy)        ;; → actual port number
;;;
;;;   ;; Start on specific port with auth
;;;   (define proxy (socks5-start 1080 "user" "pass"))
;;;
;;;   ;; Set *_PROXY env vars for child processes
;;;   (socks5-set-proxy-env! proxy)
;;;
;;;   ;; Unset proxy env vars
;;;   (socks5-unset-proxy-env!)
;;;
;;;   ;; Get stats
;;;   (socks5-stats proxy)       ;; → "active:0 total:5"
;;;
;;;   ;; Stop
;;;   (socks5-stop proxy)

(library (std net socks5-server)
  (export
    socks5-start
    socks5-stop
    socks5-port
    socks5-stats
    socks5-set-proxy-env!
    socks5-unset-proxy-env!)

  (import (chezscheme))

  ;; Load native library (dynamic builds).
  ;; In static builds, symbols are pre-registered via Sforeign_symbol.
  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "libjerboa_native.dylib") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.dylib") #t)
        #t))

  ;; ========== FFI declarations ==========

  (define c-socks5-start
    (foreign-procedure "jerboa_socks5_server_start"
      (u8* size_t unsigned-16 u8* size_t u8* size_t) unsigned-64))

  (define c-socks5-stop
    (foreign-procedure "jerboa_socks5_server_stop"
      (unsigned-64) int))

  (define c-socks5-port
    (foreign-procedure "jerboa_socks5_server_port"
      (unsigned-64) unsigned-16))

  (define c-socks5-stats
    (foreign-procedure "jerboa_socks5_server_stats"
      (unsigned-64 u8* size_t) int))

  (define c-last-error
    (foreign-procedure "jerboa_last_error" (u8* size_t) size_t))

  ;; ========== Error helper ==========

  (define (subbytevector bv start end)
    (let* ([n (- end start)]
           [result (make-bytevector n)])
      (bytevector-copy! bv start result 0 n)
      result))

  (define (get-last-error)
    (let ([buf (make-bytevector 512)])
      (let ([len (c-last-error buf 512)])
        (if (> len 0)
          (utf8->string (subbytevector buf 0 (min len 511)))
          "unknown error"))))

  ;; ========== Public API ==========

  ;; (socks5-start)               → handle  ; random port, no auth
  ;; (socks5-start port)          → handle  ; specific port, no auth
  ;; (socks5-start port user pw)  → handle  ; specific port, user/pass auth
  ;; (socks5-start port user pw bind-addr) → handle
  (define socks5-start
    (case-lambda
      [()
       (socks5-start* "127.0.0.1" 0 #f #f)]
      [(port)
       (socks5-start* "127.0.0.1" port #f #f)]
      [(port username password)
       (socks5-start* "127.0.0.1" port username password)]
      [(port username password bind-addr)
       (socks5-start* bind-addr port username password)]))

  (define (socks5-start* bind-addr port username password)
    (let* ([addr-bv (string->utf8 bind-addr)]
           [user-bv (if username (string->utf8 username) (make-bytevector 0))]
           [pass-bv (if password (string->utf8 password) (make-bytevector 0))]
           [handle (c-socks5-start
                     addr-bv (bytevector-length addr-bv)
                     port
                     user-bv (if username (bytevector-length user-bv) 0)
                     pass-bv (if password (bytevector-length pass-bv) 0))])
      (when (= handle 0)
        (error 'socks5-start (get-last-error)))
      handle))

  ;; Stop a running SOCKS5 proxy server.
  (define (socks5-stop handle)
    (let ([rc (c-socks5-stop handle)])
      (when (< rc 0)
        (error 'socks5-stop (get-last-error)))))

  ;; Get the actual bound port.
  (define (socks5-port handle)
    (let ([p (c-socks5-port handle)])
      (when (= p 0)
        (error 'socks5-port (get-last-error)))
      p))

  ;; Get stats string: "active:N total:N"
  (define (socks5-stats handle)
    (let* ([buf (make-bytevector 256)]
           [n (c-socks5-stats handle buf 256)])
      (if (> n 0)
        (utf8->string (subbytevector buf 0 n))
        "")))

  ;; ========== Proxy environment variables ==========

  ;; All the environment variable names that programs check for proxy config.
  (define *proxy-env-vars*
    '("HTTP_PROXY" "http_proxy"
      "HTTPS_PROXY" "https_proxy"
      "ALL_PROXY" "all_proxy"
      "SOCKS_PROXY" "socks_proxy"
      "SOCKS5_PROXY" "socks5_proxy"))

  ;; Set all proxy env vars to point to the running SOCKS5 proxy.
  ;; Uses socks5h:// scheme (h = proxy resolves DNS, standard for SOCKS5).
  (define (socks5-set-proxy-env! handle)
    (let* ([port (socks5-port handle)]
           [url (string-append "socks5h://127.0.0.1:" (number->string port))])
      (for-each
        (lambda (var) (putenv var url))
        *proxy-env-vars*)))

  ;; Unset all proxy env vars.
  (define (socks5-unset-proxy-env!)
    (for-each
      (lambda (var) (putenv var ""))
      *proxy-env-vars*))

) ;; end library
