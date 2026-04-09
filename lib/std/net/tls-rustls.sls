#!chezscheme
;;; (std net tls-rustls) — TLS via Rust rustls FFI
;;;
;;; Wraps the Rust rustls backend (libjerboa_native) for TLS connections.
;;; Supports both standard TLS and mutual TLS (mTLS) where both server
;;; and client present certificates verified against a shared CA.
;;;
;;; Standard TLS:
;;;   Server: (rustls-server-ctx-new cert-path key-path)
;;;   Client: (rustls-connect host port)
;;;
;;; Mutual TLS (mTLS):
;;;   Server: (rustls-server-ctx-new-mtls cert-path key-path client-ca-path)
;;;           Rejects clients without a valid cert signed by client-ca-path.
;;;   Client: (rustls-connect-mtls host port cert-path key-path ca-cert-path)
;;;           Presents client cert; verifies server cert against ca-cert-path.
;;;
;;; For self-signed mTLS, use the same cert as server cert, client cert,
;;; and CA cert — both sides trust and present the same identity.

(library (std net tls-rustls)
  (export
    ;; Server context
    rustls-server-ctx-new
    rustls-server-ctx-new-mtls
    rustls-server-ctx-free

    ;; Accept connections
    rustls-accept

    ;; Client connections
    rustls-connect
    rustls-connect-pinned
    rustls-connect-mtls

    ;; I/O
    rustls-read
    rustls-write
    rustls-flush
    rustls-close

    ;; Utilities
    rustls-set-nonblock
    rustls-get-fd)

  (import (chezscheme))

  ;; Load the Rust native library (dynamic builds).
  ;; In static builds, symbols are pre-registered via Sforeign_symbol.
  (define _native-loaded
    (or (guard (e [#t #f]) (load-shared-object "libjerboa_native.dylib") #t)
        (guard (e [#t #f]) (load-shared-object "libjerboa_native.so") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.dylib") #t)
        (guard (e [#t #f]) (load-shared-object "lib/libjerboa_native.so") #t)
        #t))

  ;; ========== FFI declarations ==========

  ;; Standard TLS server context (no client auth)
  (define c-tls-server-new
    (foreign-procedure "jerboa_tls_server_new"
      (u8* unsigned-64 u8* unsigned-64) unsigned-64))

  ;; mTLS server context (requires client certs signed by given CA)
  (define c-tls-server-new-mtls
    (foreign-procedure "jerboa_tls_server_new_mtls"
      (u8* unsigned-64 u8* unsigned-64 u8* unsigned-64) unsigned-64))

  (define c-tls-server-free
    (foreign-procedure "jerboa_tls_server_free" (unsigned-64) void))

  ;; Accept a TLS connection on an already-accepted TCP fd
  (define c-tls-accept
    (foreign-procedure "jerboa_tls_accept" (unsigned-64 int) unsigned-64))

  ;; Standard TLS client connect (system CA trust)
  (define c-tls-connect
    (foreign-procedure "jerboa_tls_connect"
      (u8* unsigned-64 unsigned-16) unsigned-64))

  ;; TLS client with certificate pinning (no CA verification)
  (define c-tls-connect-pinned
    (foreign-procedure "jerboa_tls_connect_pinned"
      (u8* unsigned-64 unsigned-16 u8* unsigned-64) unsigned-64))

  ;; mTLS client connect (presents client cert, verifies server against CA)
  (define c-tls-connect-mtls
    (foreign-procedure "jerboa_tls_connect_mtls"
      (u8* unsigned-64 unsigned-16
       u8* unsigned-64 u8* unsigned-64 u8* unsigned-64) unsigned-64))

  ;; I/O
  (define c-tls-read
    (foreign-procedure "jerboa_tls_read" (unsigned-64 u8* unsigned-64) int))

  (define c-tls-write
    (foreign-procedure "jerboa_tls_write" (unsigned-64 u8* unsigned-64) int))

  (define c-tls-flush
    (foreign-procedure "jerboa_tls_flush" (unsigned-64) int))

  (define c-tls-close
    (foreign-procedure "jerboa_tls_close" (unsigned-64) void))

  ;; Utilities
  (define c-tls-set-nonblock
    (foreign-procedure "jerboa_tls_set_nonblock" (unsigned-64 int) int))

  (define c-tls-get-fd
    (foreign-procedure "jerboa_tls_get_fd" (unsigned-64) int))

  ;; Error reporting
  (define c-last-error
    (foreign-procedure "jerboa_last_error" (u8* size_t) size_t))

  (define (get-last-error)
    (let ([buf (make-bytevector 512)])
      (let ([len (c-last-error buf 512)])
        (if (> len 0)
          (utf8->string (let ([out (make-bytevector (min len 511))])
            (bytevector-copy! buf 0 out 0 (min len 511)) out))
          "unknown error"))))

  ;; ========== Server context ==========

  (define (rustls-server-ctx-new cert-path key-path)
    ;; Create a TLS server context (no client auth).
    ;; cert-path: PEM file with server certificate chain
    ;; key-path: PEM file with server private key
    (let* ([cert-bv (string->utf8 cert-path)]
           [key-bv (string->utf8 key-path)]
           [handle (c-tls-server-new
                     cert-bv (bytevector-length cert-bv)
                     key-bv (bytevector-length key-bv))])
      (when (= handle 0)
        (error 'rustls-server-ctx-new
          (format "failed to create TLS server context: ~a" (get-last-error))))
      handle))

  (define (rustls-server-ctx-new-mtls cert-path key-path client-ca-path)
    ;; Create a TLS server context that REQUIRES client certificates.
    ;; Clients must present a certificate signed by client-ca-path.
    ;; Connections without a valid client cert are rejected at handshake.
    ;;
    ;; cert-path: PEM file with server certificate chain
    ;; key-path: PEM file with server private key
    ;; client-ca-path: PEM file with CA cert(s) that issued client certs
    ;;
    ;; For self-signed mTLS: use the same cert file for all three paths.
    (let* ([cert-bv (string->utf8 cert-path)]
           [key-bv (string->utf8 key-path)]
           [ca-bv (string->utf8 client-ca-path)]
           [handle (c-tls-server-new-mtls
                     cert-bv (bytevector-length cert-bv)
                     key-bv (bytevector-length key-bv)
                     ca-bv (bytevector-length ca-bv))])
      (when (= handle 0)
        (error 'rustls-server-ctx-new-mtls
          (format "failed to create mTLS server context: ~a" (get-last-error))))
      handle))

  (define (rustls-server-ctx-free handle)
    (c-tls-server-free handle))

  ;; ========== Accept connections ==========

  (define (rustls-accept server-ctx tcp-fd)
    ;; Accept a TLS connection on an already-accepted TCP fd.
    ;; For mTLS server contexts, the client's certificate is verified
    ;; during the handshake — no valid cert = handshake failure.
    ;; Returns a connection handle.
    (let ([handle (c-tls-accept server-ctx tcp-fd)])
      (when (= handle 0)
        (error 'rustls-accept
          (format "TLS accept failed: ~a" (get-last-error))))
      handle))

  ;; ========== Client connections ==========

  (define (rustls-connect host port)
    ;; Connect to a TLS server using system CA trust store.
    ;; No client certificate is presented.
    (let* ([host-bv (string->utf8 host)]
           [handle (c-tls-connect
                     host-bv (bytevector-length host-bv) port)])
      (when (= handle 0)
        (error 'rustls-connect
          (format "TLS connect to ~a:~a failed: ~a" host port (get-last-error))))
      handle))

  (define (rustls-connect-pinned host port pin-sha256)
    ;; Connect with certificate pinning (SHA-256 of server cert DER).
    ;; No CA verification — pin must match exactly.
    (let* ([host-bv (string->utf8 host)]
           [handle (c-tls-connect-pinned
                     host-bv (bytevector-length host-bv) port
                     pin-sha256 (bytevector-length pin-sha256))])
      (when (= handle 0)
        (error 'rustls-connect-pinned
          (format "TLS pinned connect to ~a:~a failed: ~a"
            host port (get-last-error))))
      handle))

  (define (rustls-connect-mtls host port cert-path key-path ca-cert-path)
    ;; Connect with mutual TLS authentication.
    ;; Presents client certificate to the server and verifies the
    ;; server's certificate against ca-cert-path.
    ;;
    ;; cert-path: PEM file with client certificate
    ;; key-path: PEM file with client private key
    ;; ca-cert-path: PEM file with CA cert to verify the server
    ;;
    ;; For self-signed mTLS: use the same cert/key/ca files as the server.
    (let* ([host-bv (string->utf8 host)]
           [cert-bv (string->utf8 cert-path)]
           [key-bv (string->utf8 key-path)]
           [ca-bv (string->utf8 ca-cert-path)]
           [handle (c-tls-connect-mtls
                     host-bv (bytevector-length host-bv) port
                     cert-bv (bytevector-length cert-bv)
                     key-bv (bytevector-length key-bv)
                     ca-bv (bytevector-length ca-bv))])
      (when (= handle 0)
        (error 'rustls-connect-mtls
          (format "mTLS connect to ~a:~a failed: ~a"
            host port (get-last-error))))
      handle))

  ;; ========== I/O ==========

  (define (rustls-read handle buf max-len)
    ;; Read up to max-len bytes. Returns bytes read, 0 on EOF, -1 on error.
    (c-tls-read handle buf max-len))

  (define (rustls-write handle buf len)
    ;; Write len bytes from buf. Returns bytes written or -1 on error.
    (let ([n (c-tls-write handle buf len)])
      (when (> n 0) (c-tls-flush handle))
      n))

  (define (rustls-flush handle)
    (c-tls-flush handle))

  (define (rustls-close handle)
    (c-tls-close handle))

  ;; ========== Utilities ==========

  (define (rustls-set-nonblock handle nonblock?)
    (c-tls-set-nonblock handle (if nonblock? 1 0)))

  (define (rustls-get-fd handle)
    ;; Get the underlying TCP fd (for poll/select).
    (c-tls-get-fd handle))

  ) ;; end library
