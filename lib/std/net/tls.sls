#!chezscheme
;;; (std net tls) — TLS hardening wrapper
;;;
;;; Secure defaults for TLS connections.
;;; Wraps (std net ssl) with hardened configuration:
;;; - Minimum TLS 1.2
;;; - Strong cipher suites only
;;; - Peer verification enabled by default
;;; - Certificate pinning support

(library (std net tls)
  (export
    ;; Configuration
    make-tls-config
    tls-config?
    tls-config-min-version
    tls-config-cipher-suites
    tls-config-verify-peer?
    tls-config-verify-hostname?
    tls-config-ca-file
    tls-config-cert-file
    tls-config-key-file
    default-tls-config

    ;; Config builder
    tls-config-with

    ;; Secure connections
    tls-connect
    tls-listen
    tls-accept
    tls-close
    tls-read
    tls-write

    ;; Certificate pinning
    make-pin-set
    pin-set?
    pin-set-add!
    pin-set-check)

  (import (chezscheme)
          (std crypto native))

  ;; ========== TLS Configuration ==========

  (define-record-type (tls-config %make-tls-config tls-config?)
    (sealed #t)
    (fields
      (immutable min-version tls-config-min-version)       ;; 'tls-1.2 or 'tls-1.3
      (immutable cipher-suites tls-config-cipher-suites)   ;; list of cipher names
      (immutable verify-peer? tls-config-verify-peer?)     ;; #t/#f
      (immutable verify-hostname? tls-config-verify-hostname?) ;; #t/#f
      (immutable ca-file tls-config-ca-file)               ;; string or #f
      (immutable cert-file tls-config-cert-file)           ;; string or #f
      (immutable key-file tls-config-key-file)))           ;; string or #f

  ;; Strong default cipher suites (TLS 1.3 + TLS 1.2 AEAD-only)
  (define *default-cipher-suites*
    '("TLS_AES_256_GCM_SHA384"
      "TLS_CHACHA20_POLY1305_SHA256"
      "TLS_AES_128_GCM_SHA256"
      "ECDHE-ECDSA-AES256-GCM-SHA384"
      "ECDHE-RSA-AES256-GCM-SHA384"
      "ECDHE-ECDSA-CHACHA20-POLY1305"
      "ECDHE-RSA-CHACHA20-POLY1305"
      "ECDHE-ECDSA-AES128-GCM-SHA256"
      "ECDHE-RSA-AES128-GCM-SHA256"))

  (define (make-tls-config . opts)
    ;; Keyword-style options:
    ;; min-version: 'tls-1.2 (default) or 'tls-1.3
    ;; cipher-suites: list of cipher strings
    ;; verify-peer: #t (default)
    ;; verify-hostname: #t (default)
    ;; ca-file: path or #f
    ;; cert-file: path or #f
    ;; key-file: path or #f
    (let loop ([o opts]
               [min-ver 'tls-1.2]
               [ciphers *default-cipher-suites*]
               [verify-p #t]
               [verify-h #t]
               [ca #f]
               [cert #f]
               [key #f])
      (if (or (null? o) (null? (cdr o)))
        (%make-tls-config min-ver ciphers verify-p verify-h ca cert key)
        (let ([k (car o)] [v (cadr o)])
          (loop (cddr o)
                (if (eq? k 'min-version:) v min-ver)
                (if (eq? k 'cipher-suites:) v ciphers)
                (if (eq? k 'verify-peer:) v verify-p)
                (if (eq? k 'verify-hostname:) v verify-h)
                (if (eq? k 'ca-file:) v ca)
                (if (eq? k 'cert-file:) v cert)
                (if (eq? k 'key-file:) v key))))))

  (define default-tls-config
    (%make-tls-config 'tls-1.2 *default-cipher-suites* #t #t #f #f #f))

  (define (tls-config-with base . opts)
    ;; Create a new config based on base with overrides.
    (let loop ([o opts]
               [min-ver (tls-config-min-version base)]
               [ciphers (tls-config-cipher-suites base)]
               [verify-p (tls-config-verify-peer? base)]
               [verify-h (tls-config-verify-hostname? base)]
               [ca (tls-config-ca-file base)]
               [cert (tls-config-cert-file base)]
               [key (tls-config-key-file base)])
      (if (or (null? o) (null? (cdr o)))
        (%make-tls-config min-ver ciphers verify-p verify-h ca cert key)
        (let ([k (car o)] [v (cadr o)])
          (loop (cddr o)
                (if (eq? k 'min-version:) v min-ver)
                (if (eq? k 'cipher-suites:) v ciphers)
                (if (eq? k 'verify-peer:) v verify-p)
                (if (eq? k 'verify-hostname:) v verify-h)
                (if (eq? k 'ca-file:) v ca)
                (if (eq? k 'cert-file:) v cert)
                (if (eq? k 'key-file:) v key))))))

  ;; ========== TLS Version Validation ==========

  (define (valid-tls-version? v)
    (memq v '(tls-1.2 tls-1.3)))

  (define (tls-version->string v)
    (case v
      [(tls-1.2) "TLSv1.2"]
      [(tls-1.3) "TLSv1.3"]
      [else (error 'tls-version->string "unsupported version" v)]))

  ;; ========== OpenSSL FFI for TLS context ==========

  (define _ssl-loaded
    (or (guard (e [#t #f]) (load-shared-object "libssl.so") #t)
        (guard (e [#t #f]) (load-shared-object "libssl.so.3") #t)))

  (define c-TLS_client_method
    (if _ssl-loaded (foreign-procedure "TLS_client_method" () uptr) (lambda () 0)))
  (define c-TLS_server_method
    (if _ssl-loaded (foreign-procedure "TLS_server_method" () uptr) (lambda () 0)))
  (define c-SSL_CTX_new
    (if _ssl-loaded (foreign-procedure "SSL_CTX_new" (uptr) uptr) (lambda (m) 0)))
  (define c-SSL_CTX_free
    (if _ssl-loaded (foreign-procedure "SSL_CTX_free" (uptr) void) (lambda (c) (void))))
  ;; SSL_CTX_set_min_proto_version is a macro: SSL_CTX_ctrl(ctx, SSL_CTRL_SET_MIN_PROTO_VERSION, ver, NULL)
  (define c-SSL_CTX_ctrl
    (if _ssl-loaded (foreign-procedure "SSL_CTX_ctrl" (uptr int long uptr) long) (lambda args 0)))
  (define SSL_CTRL_SET_MIN_PROTO_VERSION 123)
  (define (c-SSL_CTX_set_min_proto_version ctx ver)
    (c-SSL_CTX_ctrl ctx SSL_CTRL_SET_MIN_PROTO_VERSION ver 0))
  (define c-SSL_CTX_set_cipher_list
    (if _ssl-loaded (foreign-procedure "SSL_CTX_set_cipher_list" (uptr string) int) (lambda args 0)))
  (define c-SSL_CTX_set_ciphersuites
    (if _ssl-loaded (foreign-procedure "SSL_CTX_set_ciphersuites" (uptr string) int) (lambda args 0)))
  (define c-SSL_CTX_set_verify
    (if _ssl-loaded (foreign-procedure "SSL_CTX_set_verify" (uptr int uptr) void) (lambda args (void))))
  (define c-SSL_CTX_load_verify_locations
    (if _ssl-loaded (foreign-procedure "SSL_CTX_load_verify_locations" (uptr string uptr) int) (lambda args 0)))
  (define c-SSL_CTX_use_certificate_file
    (if _ssl-loaded (foreign-procedure "SSL_CTX_use_certificate_file" (uptr string int) int) (lambda args 0)))
  (define c-SSL_CTX_use_PrivateKey_file
    (if _ssl-loaded (foreign-procedure "SSL_CTX_use_PrivateKey_file" (uptr string int) int) (lambda args 0)))

  ;; TLS version constants
  (define TLS1_2_VERSION #x0303)
  (define TLS1_3_VERSION #x0304)

  ;; SSL_VERIFY_* constants
  (define SSL_VERIFY_NONE 0)
  (define SSL_VERIFY_PEER 1)
  (define SSL_VERIFY_FAIL_IF_NO_PEER_CERT 2)

  ;; SSL_FILETYPE_PEM
  (define SSL_FILETYPE_PEM 1)

  (define (ensure-ssl! who)
    (unless _ssl-loaded
      (error who "libssl not available — install OpenSSL")))

  ;; ========== TLS Context Setup ==========

  (define (make-ssl-ctx config server?)
    ;; Create and configure an SSL_CTX from a tls-config.
    (ensure-ssl! 'make-ssl-ctx)
    (let ([ctx (c-SSL_CTX_new (if server? (c-TLS_server_method) (c-TLS_client_method)))])
      (when (= ctx 0)
        (error 'make-ssl-ctx "SSL_CTX_new failed"))
      ;; Set minimum version
      (let ([min-ver (case (tls-config-min-version config)
                       [(tls-1.2) TLS1_2_VERSION]
                       [(tls-1.3) TLS1_3_VERSION]
                       [else TLS1_2_VERSION])])
        (c-SSL_CTX_set_min_proto_version ctx min-ver))
      ;; Set cipher suites
      (let ([ciphers (tls-config-cipher-suites config)])
        (when (pair? ciphers)
          ;; TLS 1.2 cipher list
          (let ([tls12 (filter-map
                         (lambda (c) (and (not (string-prefix? "TLS_" c)) c))
                         ciphers)])
            (when (pair? tls12)
              (c-SSL_CTX_set_cipher_list ctx (join-strings tls12 ":"))))
          ;; TLS 1.3 ciphersuites
          (let ([tls13 (filter-map
                         (lambda (c) (and (string-prefix? "TLS_" c) c))
                         ciphers)])
            (when (pair? tls13)
              (c-SSL_CTX_set_ciphersuites ctx (join-strings tls13 ":"))))))
      ;; Peer verification
      (when (tls-config-verify-peer? config)
        (c-SSL_CTX_set_verify ctx
          (bitwise-ior SSL_VERIFY_PEER
                       (if server? SSL_VERIFY_FAIL_IF_NO_PEER_CERT 0))
          0))
      ;; CA file
      (when (tls-config-ca-file config)
        (c-SSL_CTX_load_verify_locations ctx (tls-config-ca-file config) 0))
      ;; Certificate + key
      (when (tls-config-cert-file config)
        (c-SSL_CTX_use_certificate_file ctx (tls-config-cert-file config) SSL_FILETYPE_PEM))
      (when (tls-config-key-file config)
        (c-SSL_CTX_use_PrivateKey_file ctx (tls-config-key-file config) SSL_FILETYPE_PEM))
      ctx))

  ;; ========== TLS Connection Record ==========

  (define-record-type (tls-conn make-tls-conn tls-conn?)
    (sealed #t)
    (fields
      (immutable ctx %tls-conn-ctx)     ;; SSL_CTX*
      (immutable ssl %tls-conn-ssl)     ;; SSL* (0 for server-only)
      (immutable fd %tls-conn-fd)       ;; underlying socket fd
      (mutable closed? %tls-conn-closed? %tls-conn-set-closed!)))

  ;; SSL object management
  (define c-SSL_new
    (if _ssl-loaded (foreign-procedure "SSL_new" (uptr) uptr) (lambda (c) 0)))
  (define c-SSL_set_fd
    (if _ssl-loaded (foreign-procedure "SSL_set_fd" (uptr int) int) (lambda args 0)))
  (define c-SSL_connect
    (if _ssl-loaded (foreign-procedure "SSL_connect" (uptr) int) (lambda (s) -1)))
  (define c-SSL_accept
    (if _ssl-loaded (foreign-procedure "SSL_accept" (uptr) int) (lambda (s) -1)))
  (define c-SSL_read
    (if _ssl-loaded (foreign-procedure "SSL_read" (uptr u8* int) int) (lambda args -1)))
  (define c-SSL_write
    (if _ssl-loaded (foreign-procedure "SSL_write" (uptr u8* int) int) (lambda args -1)))
  (define c-SSL_shutdown
    (if _ssl-loaded (foreign-procedure "SSL_shutdown" (uptr) int) (lambda (s) 0)))
  (define c-SSL_free
    (if _ssl-loaded (foreign-procedure "SSL_free" (uptr) void) (lambda (s) (void))))

  ;; Socket FFI
  (define c-socket (foreign-procedure "socket" (int int int) int))
  (define c-connect-raw (foreign-procedure "connect" (int void* int) int))
  (define c-close (foreign-procedure "close" (int) int))
  (define c-htons (foreign-procedure "htons" (unsigned-short) unsigned-short))
  (define c-inet-pton (foreign-procedure "inet_pton" (int string void*) int))
  (define c-bind (foreign-procedure "bind" (int void* int) int))
  (define c-listen-raw (foreign-procedure "listen" (int int) int))
  (define c-accept-raw (foreign-procedure "accept" (int void* void*) int))
  (define c-setsockopt (foreign-procedure "setsockopt" (int int int void* int) int))

  (define AF_INET 2)
  (define SOCK_STREAM 1)
  (define SOL_SOCKET 1)
  (define SO_REUSEADDR 2)
  (define SOCKADDR_IN_SIZE 16)

  (define (make-sockaddr-in* address port)
    (let ([buf (foreign-alloc SOCKADDR_IN_SIZE)])
      (let lp ([i 0])
        (when (< i SOCKADDR_IN_SIZE)
          (foreign-set! 'unsigned-8 buf i 0)
          (lp (+ i 1))))
      (foreign-set! 'unsigned-short buf 0 AF_INET)
      (foreign-set! 'unsigned-short buf 2 (c-htons port))
      (when (= (c-inet-pton AF_INET address (+ buf 4)) 0)
        (foreign-free buf)
        (error 'tls-connect "invalid address" address))
      buf))

  ;; ========== Public API ==========

  (define (tls-connect host port . opts)
    ;; Connect to a TLS server.
    ;; Returns a tls-conn record.
    (ensure-ssl! 'tls-connect)
    (let ([config (if (and (pair? opts) (tls-config? (car opts)))
                    (car opts)
                    default-tls-config)])
      (let ([ctx (make-ssl-ctx config #f)]
            [fd (c-socket AF_INET SOCK_STREAM 0)])
        (when (< fd 0)
          (c-SSL_CTX_free ctx)
          (error 'tls-connect "socket() failed"))
        (let ([addr (make-sockaddr-in* host port)])
          (let ([rc (c-connect-raw fd addr SOCKADDR_IN_SIZE)])
            (foreign-free addr)
            (when (< rc 0)
              (c-close fd)
              (c-SSL_CTX_free ctx)
              (error 'tls-connect "connect() failed" host port))))
        (let ([ssl (c-SSL_new ctx)])
          (when (= ssl 0)
            (c-close fd)
            (c-SSL_CTX_free ctx)
            (error 'tls-connect "SSL_new failed"))
          (c-SSL_set_fd ssl fd)
          (let ([rc (c-SSL_connect ssl)])
            (when (<= rc 0)
              (c-SSL_free ssl)
              (c-close fd)
              (c-SSL_CTX_free ctx)
              (error 'tls-connect "SSL handshake failed" host port))
            (make-tls-conn ctx ssl fd #f))))))

  (define (tls-listen address port . opts)
    ;; Create a TLS server socket.
    ;; Returns a tls-conn representing the listen socket.
    (ensure-ssl! 'tls-listen)
    (let ([config (if (and (pair? opts) (tls-config? (car opts)))
                    (car opts)
                    default-tls-config)])
      (let ([ctx (make-ssl-ctx config #t)]
            [fd (c-socket AF_INET SOCK_STREAM 0)])
        (when (< fd 0)
          (c-SSL_CTX_free ctx)
          (error 'tls-listen "socket() failed"))
        (let ([one (foreign-alloc 4)])
          (foreign-set! 'int one 0 1)
          (c-setsockopt fd SOL_SOCKET SO_REUSEADDR one 4)
          (foreign-free one))
        (let ([addr (make-sockaddr-in* address port)])
          (let ([rc (c-bind fd addr SOCKADDR_IN_SIZE)])
            (foreign-free addr)
            (when (< rc 0)
              (c-close fd)
              (c-SSL_CTX_free ctx)
              (error 'tls-listen "bind() failed" address port))))
        (when (< (c-listen-raw fd 128) 0)
          (c-close fd)
          (c-SSL_CTX_free ctx)
          (error 'tls-listen "listen() failed"))
        (make-tls-conn ctx 0 fd #f))))

  (define (tls-accept server-conn)
    ;; Accept a new TLS client on a tls-listen socket.
    ;; Returns a new tls-conn.
    (let ([client-fd (c-accept-raw (%tls-conn-fd server-conn) 0 0)])
      (when (< client-fd 0)
        (error 'tls-accept "accept() failed"))
      (let ([ssl (c-SSL_new (%tls-conn-ctx server-conn))])
        (when (= ssl 0)
          (c-close client-fd)
          (error 'tls-accept "SSL_new failed"))
        (c-SSL_set_fd ssl client-fd)
        (let ([rc (c-SSL_accept ssl)])
          (when (<= rc 0)
            (c-SSL_free ssl)
            (c-close client-fd)
            (error 'tls-accept "SSL handshake failed"))
          (make-tls-conn (%tls-conn-ctx server-conn) ssl client-fd #f)))))

  (define (tls-read conn buf len)
    ;; Read up to len bytes. Returns bytes read or 0 on EOF.
    (if (%tls-conn-closed? conn) 0
      (let ([n (c-SSL_read (%tls-conn-ssl conn) buf len)])
        (if (<= n 0) 0 n))))

  (define (tls-write conn bv)
    ;; Write bytevector.
    (unless (%tls-conn-closed? conn)
      (let ([n (c-SSL_write (%tls-conn-ssl conn) bv (bytevector-length bv))])
        (when (<= n 0)
          (error 'tls-write "SSL_write failed")))))

  (define (tls-close conn)
    ;; Gracefully close a TLS connection.
    (unless (%tls-conn-closed? conn)
      (%tls-conn-set-closed! conn #t)
      (let ([ssl (%tls-conn-ssl conn)])
        (when (> ssl 0)
          (c-SSL_shutdown ssl)
          (c-SSL_free ssl)))
      (c-close (%tls-conn-fd conn))))

  ;; ========== Certificate Pinning ==========

  (define-record-type (pin-set %make-pin-set pin-set?)
    (sealed #t)
    (fields
      (immutable pins %pin-set-pins)     ;; hashtable: sha256-hex -> #t
      (immutable mutex %pin-set-mutex)))

  (define (make-pin-set)
    (%make-pin-set
      (make-hashtable string-hash string=?)
      (make-mutex)))

  (define (pin-set-add! ps sha256-hex)
    ;; Add a SHA-256 pin (hex-encoded).
    (with-mutex (%pin-set-mutex ps)
      (hashtable-set! (%pin-set-pins ps) sha256-hex #t)))

  (define (pin-set-check ps sha256-hex)
    ;; Check if a certificate pin is in the set.
    (with-mutex (%pin-set-mutex ps)
      (hashtable-ref (%pin-set-pins ps) sha256-hex #f)))

  ;; ========== Helpers ==========

  (define (string-prefix? prefix str)
    (and (>= (string-length str) (string-length prefix))
         (string=? (substring str 0 (string-length prefix)) prefix)))

  (define (filter-map f lst)
    (let loop ([l lst] [acc '()])
      (if (null? l) (reverse acc)
        (let ([v (f (car l))])
          (loop (cdr l) (if v (cons v acc) acc))))))

  (define (join-strings lst sep)
    (cond
      [(null? lst) ""]
      [(null? (cdr lst)) (car lst)]
      [else (let loop ([rest (cdr lst)] [acc (car lst)])
              (if (null? rest) acc
                (loop (cdr rest) (string-append acc sep (car rest)))))]))

  ) ;; end library
