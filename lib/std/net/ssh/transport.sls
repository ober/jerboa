#!chezscheme
;;; (std net ssh transport) — SSH transport layer
;;;
;;; TCP connect, version exchange, packet framing (encrypt/decrypt),
;;; sequence numbers, and rekey support.
;;;
;;; FFI operations are imported from (chez-ssh crypto).
;;; Uses (std net ssh conditions) for structured error hierarchy.
;;; Uses (std misc guardian-pool) for TCP fd cleanup on GC.

(library (std net ssh transport)
  (export
    ;; Transport state
    make-transport-state
    transport-state?
    transport-state-fd
    transport-state-session-id
    transport-state-session-id-set!
    transport-state-server-version
    transport-state-client-version
    transport-state-send-seqno
    transport-state-send-seqno-set!
    transport-state-recv-seqno
    transport-state-recv-seqno-set!
    transport-state-send-cipher
    transport-state-recv-cipher
    transport-state-send-cipher-set!
    transport-state-recv-cipher-set!
    transport-state-send-mac-key
    transport-state-recv-mac-key
    transport-state-send-mac-key-set!
    transport-state-recv-mac-key-set!
    transport-state-client-kexinit
    transport-state-client-kexinit-set!
    transport-state-server-kexinit
    transport-state-server-kexinit-set!
    transport-state-algorithms
    transport-state-algorithms-set!
    transport-state-bytes-sent
    transport-state-bytes-sent-set!
    transport-state-bytes-received
    transport-state-bytes-received-set!
    transport-state-packets-sent
    transport-state-packets-sent-set!
    transport-state-packets-received
    transport-state-packets-received-set!

    ;; Cipher state
    make-cipher-state
    cipher-state?
    cipher-state-name
    cipher-state-key
    cipher-state-mac-key
    cipher-state-iv
    cipher-state-ctx

    ;; Negotiated algorithms
    make-negotiated-algorithms
    negotiated-algorithms?
    negotiated-algorithms-kex
    negotiated-algorithms-host-key
    negotiated-algorithms-cipher-c2s
    negotiated-algorithms-cipher-s2c
    negotiated-algorithms-mac-c2s
    negotiated-algorithms-mac-s2c
    negotiated-algorithms-compress-c2s
    negotiated-algorithms-compress-s2c

    ;; Connection and I/O
    ssh-transport-connect
    ssh-transport-close
    ssh-transport-send-version
    ssh-transport-recv-version
    ssh-transport-send-packet
    ssh-transport-recv-packet

    ;; Rekey thresholds
    ssh-transport-needs-rekey?

    ;; Low-level TCP I/O
    ssh-tcp-read-exact
    ssh-tcp-write-all

    ;; Guardian pool for fd cleanup
    ssh-transport-fd-pool
    )

  (import (chezscheme)
          (std net ssh wire)
          (std net ssh conditions)
          (std misc guardian-pool)
          (chez-ssh crypto))

  ;; ---- Constants ----
  (define CLIENT-VERSION "SSH-2.0-jerboa-ssh_1.0")
  (define MAX-PACKET-SIZE 262144)   ;; 256 KB
  (define REKEY-BYTES-THRESHOLD (* 1024 1024 1024))  ;; 1 GB
  (define REKEY-PACKETS-THRESHOLD (* 1024 1024))      ;; 1M packets

  ;; ---- Guardian pool for TCP fds ----
  ;; Safety net: when transport states are GC'd without explicit close,
  ;; the guardian pool closes their TCP fds to prevent fd leaks.
  (define ssh-transport-fd-pool
    (make-guardian-pool
      (lambda (ts)
        (guard (e [#t (void)])
          (ssh-crypto-tcp-close (transport-state-fd ts))))))

  ;; ---- Records ----

  (define-record-type cipher-state
    (fields
      name       ;; string: "chacha20-poly1305@openssh.com" or "aes256-ctr"
      key        ;; bytevector: cipher key (64 for chacha, 32 for aes)
      mac-key    ;; bytevector or #f: HMAC key (for aes256-ctr)
      iv         ;; bytevector or #f: IV (for aes256-ctr)
      ctx))      ;; bytevector or #f: AES context buffer

  (define-record-type negotiated-algorithms
    (fields
      kex             ;; string
      host-key        ;; string
      cipher-c2s      ;; string
      cipher-s2c      ;; string
      mac-c2s         ;; string
      mac-s2c         ;; string
      compress-c2s    ;; string
      compress-s2c))  ;; string

  (define-record-type transport-state
    (fields
      fd                ;; int: TCP socket fd
      (mutable session-id)      ;; bytevector or #f
      server-version    ;; string
      client-version    ;; string
      (mutable send-seqno)      ;; int
      (mutable recv-seqno)      ;; int
      (mutable send-cipher)     ;; cipher-state or #f
      (mutable recv-cipher)     ;; cipher-state or #f
      (mutable send-mac-key)    ;; bytevector or #f
      (mutable recv-mac-key)    ;; bytevector or #f
      (mutable client-kexinit)  ;; bytevector or #f (raw KEXINIT payload)
      (mutable server-kexinit)  ;; bytevector or #f
      (mutable algorithms)      ;; negotiated-algorithms or #f
      (mutable bytes-sent)      ;; int
      (mutable bytes-received)  ;; int
      (mutable packets-sent)    ;; int
      (mutable packets-received)) ;; int
    (protocol
      (lambda (new)
        (lambda (fd server-version client-version)
          (let ([ts (new fd #f server-version client-version
                         0 0 #f #f #f #f #f #f #f 0 0 0 0)])
            (guardian-pool-register ssh-transport-fd-pool ts)
            ts)))))

  ;; ---- Low-level TCP I/O ----

  (define (ssh-tcp-read-exact fd n)
    (let ([buf (make-bytevector n)])
      (let loop ([off 0])
        (if (>= off n)
          buf
          (let* ([remaining (- n off)]
                 [tmp (make-bytevector remaining)]
                 [got (ssh-crypto-tcp-read fd tmp remaining)])
            (when (<= got 0)
              (raise-ssh-error 'ssh-tcp-read-exact "connection closed" off n))
            (bytevector-copy! tmp 0 buf off got)
            (loop (+ off got)))))))

  (define (ssh-tcp-write-all fd bv)
    (let ([rc (ssh-crypto-tcp-write fd bv (bytevector-length bv))])
      (when (< rc 0)
        (raise-ssh-error 'ssh-tcp-write-all "write failed"))
      rc))

  ;; ---- Connection ----

  (define (ssh-transport-connect host port)
    (let ([fd (ssh-crypto-tcp-connect host port)])
      (when (< fd 0)
        (raise-ssh-connection-error 'ssh-transport-connect host port
          "TCP connection failed"))
      (ssh-crypto-tcp-set-nodelay fd 1)
      fd))

  (define (ssh-transport-close ts)
    (ssh-crypto-tcp-close (transport-state-fd ts)))

  ;; ---- Version exchange ----

  (define (ssh-transport-send-version fd)
    (let ([line (string-append CLIENT-VERSION "\r\n")])
      (ssh-tcp-write-all fd (string->utf8 line))
      CLIENT-VERSION))

  (define (ssh-transport-recv-version fd)
    (let loop ([lines-read 0])
      (when (> lines-read 20)
        (raise-ssh-protocol-error 'ssh-transport-recv-version
          "SSH version string" "excess banner lines"
          "too many banner lines before SSH version"))
      (let line-loop ([acc '()] [count 0])
        (when (> count 255)
          (raise-ssh-protocol-error 'ssh-transport-recv-version
            "line <=255 bytes" "line too long"
            "version line exceeds 255 bytes"))
        (let* ([tmp (make-bytevector 1)]
               [got (ssh-crypto-tcp-read fd tmp 1)])
          (when (<= got 0)
            (raise-ssh-error 'ssh-transport-recv-version
              "connection closed during version exchange"))
          (let ([ch (bytevector-u8-ref tmp 0)])
            (cond
              [(= ch 10)  ;; \n — end of line
               (let* ([bytes (u8-list->bytevector (reverse acc))]
                      [line (utf8->string bytes)]
                      [line (if (and (> (string-length line) 0)
                                     (char=? (string-ref line (- (string-length line) 1)) #\return))
                              (substring line 0 (- (string-length line) 1))
                              line)])
                 (if (and (>= (string-length line) 8)
                          (string=? (substring line 0 4) "SSH-"))
                   line
                   (loop (+ lines-read 1))))]
              [else
               (line-loop (cons ch acc) (+ count 1))]))))))

  ;; ---- Packet framing ----

  ;; -- Unencrypted packets --

  (define (send-packet-unencrypted ts payload)
    (let* ([plen (bytevector-length payload)]
           [block-size 8]
           [min-pad 4]
           [base (+ 5 plen)]
           [padding-len (let ([rem (modulo base block-size)])
                          (let ([pad (if (= rem 0) 0 (- block-size rem))])
                            (if (< pad min-pad) (+ pad block-size) pad)))]
           [packet-length (+ 1 plen padding-len)]
           [total (+ 4 packet-length)]
           [pkt (make-bytevector total)])
      (let ([hdr (ssh-write-uint32 packet-length)])
        (bytevector-copy! hdr 0 pkt 0 4))
      (bytevector-u8-set! pkt 4 padding-len)
      (bytevector-copy! payload 0 pkt 5 plen)
      (let ([pad (make-bytevector padding-len)])
        (ssh-crypto-random-bytes pad padding-len)
        (bytevector-copy! pad 0 pkt (+ 5 plen) padding-len))
      (ssh-tcp-write-all (transport-state-fd ts) pkt)
      (transport-state-send-seqno-set! ts
        (bitwise-and (+ (transport-state-send-seqno ts) 1) #xFFFFFFFF))
      (transport-state-bytes-sent-set! ts
        (+ (transport-state-bytes-sent ts) total))
      (transport-state-packets-sent-set! ts
        (+ (transport-state-packets-sent ts) 1))))

  (define (recv-packet-unencrypted ts)
    (let* ([fd (transport-state-fd ts)]
           [hdr (ssh-tcp-read-exact fd 4)]
           [pkt-len (car (ssh-read-uint32 hdr 0))])
      (when (or (< pkt-len 2) (> pkt-len MAX-PACKET-SIZE))
        (raise-ssh-protocol-error 'ssh-transport-recv-packet
          "valid packet length" pkt-len
          "invalid unencrypted packet length"))
      (let* ([data (ssh-tcp-read-exact fd pkt-len)]
             [pad-len (bytevector-u8-ref data 0)]
             [payload-len (- pkt-len 1 pad-len)]
             [payload (make-bytevector payload-len)])
        (when (< payload-len 0)
          (raise-ssh-protocol-error 'ssh-transport-recv-packet
            "valid padding" pad-len
            "invalid padding in unencrypted packet"))
        (bytevector-copy! data 1 payload 0 payload-len)
        (transport-state-recv-seqno-set! ts
          (bitwise-and (+ (transport-state-recv-seqno ts) 1) #xFFFFFFFF))
        (transport-state-bytes-received-set! ts
          (+ (transport-state-bytes-received ts) (+ 4 pkt-len)))
        (transport-state-packets-received-set! ts
          (+ (transport-state-packets-received ts) 1))
        payload)))

  ;; -- ChaCha20-Poly1305 encrypted packets --

  (define (send-packet-chacha20 ts payload)
    (let* ([plen (bytevector-length payload)]
           [block-size 8]
           [min-pad 4]
           [base (+ 1 plen)]
           [padding-len (let ([rem (modulo base block-size)])
                          (let ([pad (if (= rem 0) 0 (- block-size rem))])
                            (if (< pad min-pad) (+ pad block-size) pad)))]
           [packet-length (+ 1 plen padding-len)]
           [plain (make-bytevector (+ 4 packet-length))]
           [seqno (transport-state-send-seqno ts)]
           [key (cipher-state-key (transport-state-send-cipher ts))])
      (let ([hdr (ssh-write-uint32 packet-length)])
        (bytevector-copy! hdr 0 plain 0 4))
      (bytevector-u8-set! plain 4 padding-len)
      (bytevector-copy! payload 0 plain 5 plen)
      (let ([pad (make-bytevector padding-len)])
        (ssh-crypto-random-bytes pad padding-len)
        (bytevector-copy! pad 0 plain (+ 5 plen) padding-len))
      (let* ([out-buf (make-bytevector (+ (bytevector-length plain) 16))]
             [out-len-buf (make-bytevector 4 0)]
             [rc (ssh-crypto-chacha20-poly1305-encrypt key seqno
                   plain (bytevector-length plain) out-buf out-len-buf)])
        (when (< rc 0)
          (raise-ssh-error 'ssh-transport-send-packet
            "ChaCha20-Poly1305 encryption failed"))
        (let ([out-len (car (ssh-read-uint32 out-len-buf 0))])
          (let ([final (make-bytevector out-len)])
            (bytevector-copy! out-buf 0 final 0 out-len)
            (ssh-tcp-write-all (transport-state-fd ts) final)
            (transport-state-send-seqno-set! ts
              (bitwise-and (+ seqno 1) #xFFFFFFFF))
            (transport-state-bytes-sent-set! ts
              (+ (transport-state-bytes-sent ts) out-len))
            (transport-state-packets-sent-set! ts
              (+ (transport-state-packets-sent ts) 1)))))))

  (define (recv-packet-chacha20 ts)
    (let* ([fd (transport-state-fd ts)]
           [seqno (transport-state-recv-seqno ts)]
           [key (cipher-state-key (transport-state-recv-cipher ts))]
           [enc-len-bytes (ssh-tcp-read-exact fd 4)]
           [len-buf (make-bytevector 4)]
           [rc (ssh-crypto-chacha20-poly1305-decrypt-length key seqno enc-len-bytes len-buf)])
      (when (< rc 0)
        (raise-ssh-protocol-error 'ssh-transport-recv-packet
          "valid encrypted length" "decryption failure"
          "ChaCha20 length decryption failed"))
      (let* ([pkt-len (car (ssh-read-uint32 len-buf 0))])
        (when (or (< pkt-len 2) (> pkt-len MAX-PACKET-SIZE))
          (raise-ssh-protocol-error 'ssh-transport-recv-packet
            "valid packet length" pkt-len
            "invalid encrypted packet length"))
        (let* ([enc-payload+tag (ssh-tcp-read-exact fd (+ pkt-len 16))]
               [full-ct (make-bytevector (+ 4 pkt-len 16))]
               [out-buf (make-bytevector (+ 4 pkt-len))]
               [out-len-buf (make-bytevector 4 0)])
          (bytevector-copy! enc-len-bytes 0 full-ct 0 4)
          (bytevector-copy! enc-payload+tag 0 full-ct 4 (+ pkt-len 16))
          (let ([rc2 (ssh-crypto-chacha20-poly1305-decrypt key seqno
                       full-ct (bytevector-length full-ct) out-buf out-len-buf)])
            (when (< rc2 0)
              (raise-ssh-protocol-error 'ssh-transport-recv-packet
                "authenticated ciphertext" "decryption/auth failure"
                "ChaCha20-Poly1305 decryption failed"))
            (let* ([pad-len (bytevector-u8-ref out-buf 4)]
                   [payload-len (- pkt-len 1 pad-len)]
                   [payload (make-bytevector payload-len)])
              (when (< payload-len 0)
                (raise-ssh-protocol-error 'ssh-transport-recv-packet
                  "valid padding" "invalid padding"
                  "invalid padding in decrypted ChaCha20 packet"))
              (bytevector-copy! out-buf 5 payload 0 payload-len)
              (transport-state-recv-seqno-set! ts
                (bitwise-and (+ seqno 1) #xFFFFFFFF))
              (transport-state-bytes-received-set! ts
                (+ (transport-state-bytes-received ts) (+ 4 pkt-len 16)))
              (transport-state-packets-received-set! ts
                (+ (transport-state-packets-received ts) 1))
              payload))))))

  ;; -- AES-256-CTR + HMAC-SHA2-256 encrypted packets --

  (define (send-packet-aes256-ctr ts payload)
    (let* ([plen (bytevector-length payload)]
           [block-size 16]
           [min-pad 4]
           [base (+ 5 plen)]
           [padding-len (let ([rem (modulo base block-size)])
                          (let ([pad (if (= rem 0) 0 (- block-size rem))])
                            (if (< pad min-pad) (+ pad block-size) pad)))]
           [packet-length (+ 1 plen padding-len)]
           [plain (make-bytevector (+ 4 packet-length))]
           [seqno (transport-state-send-seqno ts)]
           [cipher (transport-state-send-cipher ts)])
      (let ([hdr (ssh-write-uint32 packet-length)])
        (bytevector-copy! hdr 0 plain 0 4))
      (bytevector-u8-set! plain 4 padding-len)
      (bytevector-copy! payload 0 plain 5 plen)
      (let ([pad (make-bytevector padding-len)])
        (ssh-crypto-random-bytes pad padding-len)
        (bytevector-copy! pad 0 plain (+ 5 plen) padding-len))
      (let* ([mac-data-len (+ 4 (bytevector-length plain))]
             [mac-data (make-bytevector mac-data-len)]
             [seqno-bv (ssh-write-uint32 seqno)]
             [mac-out (make-bytevector 32)])
        (bytevector-copy! seqno-bv 0 mac-data 0 4)
        (bytevector-copy! plain 0 mac-data 4 (bytevector-length plain))
        (let ([mac-key (cipher-state-mac-key cipher)])
          (when mac-key
            (ssh-crypto-hmac-sha256 mac-key (bytevector-length mac-key)
                           mac-data mac-data-len mac-out)))
        (let* ([enc-buf (make-bytevector (bytevector-length plain))]
               [ctx-buf (cipher-state-ctx cipher)]
               [enc-len (ssh-crypto-aes256-ctr-process ctx-buf plain (bytevector-length plain) enc-buf)])
          (when (< enc-len 0)
            (raise-ssh-error 'ssh-transport-send-packet
              "AES-256-CTR encryption failed"))
          (ssh-tcp-write-all (transport-state-fd ts) enc-buf)
          (when (cipher-state-mac-key cipher)
            (ssh-tcp-write-all (transport-state-fd ts) mac-out))
          (transport-state-send-seqno-set! ts
            (bitwise-and (+ seqno 1) #xFFFFFFFF))
          (transport-state-bytes-sent-set! ts
            (+ (transport-state-bytes-sent ts) (+ (bytevector-length enc-buf) 32)))
          (transport-state-packets-sent-set! ts
            (+ (transport-state-packets-sent ts) 1))))))

  (define (recv-packet-aes256-ctr ts)
    (let* ([fd (transport-state-fd ts)]
           [seqno (transport-state-recv-seqno ts)]
           [cipher (transport-state-recv-cipher ts)]
           [ctx-buf (cipher-state-ctx cipher)]
           [enc-first (ssh-tcp-read-exact fd 16)]
           [dec-first (make-bytevector 16)]
           [_ (let ([rc (ssh-crypto-aes256-ctr-process ctx-buf enc-first 16 dec-first)])
                (when (< rc 0)
                  (raise-ssh-protocol-error 'ssh-transport-recv-packet
                    "decryptable data" "decryption failure"
                    "AES-256-CTR first-block decryption failed")))]
           [pkt-len (car (ssh-read-uint32 dec-first 0))])
      (when (or (< pkt-len 2) (> pkt-len MAX-PACKET-SIZE))
        (raise-ssh-protocol-error 'ssh-transport-recv-packet
          "valid packet length" pkt-len
          "invalid AES-256-CTR packet length"))
      (let* ([total-encrypted (+ 4 pkt-len)]
             [remaining (- total-encrypted 16)])
        (let* ([dec-rest (if (> remaining 0)
                           (let* ([enc-rest (ssh-tcp-read-exact fd remaining)]
                                  [dec-buf (make-bytevector remaining)]
                                  [rc (ssh-crypto-aes256-ctr-process ctx-buf enc-rest remaining dec-buf)])
                             (when (< rc 0)
                               (raise-ssh-protocol-error 'ssh-transport-recv-packet
                                 "decryptable data" "decryption failure"
                                 "AES-256-CTR rest decryption failed"))
                             dec-buf)
                           (make-bytevector 0))]
               [full (make-bytevector total-encrypted)]
               [_ (begin
                    (bytevector-copy! dec-first 0 full 0 16)
                    (when (> remaining 0)
                      (bytevector-copy! dec-rest 0 full 16 remaining)))]
               [mac-received (ssh-tcp-read-exact fd 32)]
               [mac-data-len (+ 4 total-encrypted)]
               [mac-data (make-bytevector mac-data-len)]
               [seqno-bv (ssh-write-uint32 seqno)]
               [mac-expected (make-bytevector 32)])
          (bytevector-copy! seqno-bv 0 mac-data 0 4)
          (bytevector-copy! full 0 mac-data 4 total-encrypted)
          (let ([mac-key (cipher-state-mac-key cipher)])
            (when mac-key
              (ssh-crypto-hmac-sha256 mac-key (bytevector-length mac-key)
                             mac-data mac-data-len mac-expected)
              (unless (bytevector=? mac-received mac-expected)
                (raise-ssh-protocol-error 'ssh-transport-recv-packet
                  "valid MAC" "MAC mismatch"
                  "HMAC-SHA2-256 verification failed"))))
          (let* ([pad-len (bytevector-u8-ref full 4)]
                 [payload-len (- pkt-len 1 pad-len)]
                 [payload (make-bytevector payload-len)])
            (when (< payload-len 0)
              (raise-ssh-protocol-error 'ssh-transport-recv-packet
                "valid padding" "invalid padding"
                "invalid padding in decrypted AES packet"))
            (bytevector-copy! full 5 payload 0 payload-len)
            (transport-state-recv-seqno-set! ts
              (bitwise-and (+ seqno 1) #xFFFFFFFF))
            (transport-state-bytes-received-set! ts
              (+ (transport-state-bytes-received ts) (+ total-encrypted 32)))
            (transport-state-packets-received-set! ts
              (+ (transport-state-packets-received ts) 1))
            payload)))))

  ;; ---- Packet dispatch ----

  (define (ssh-transport-send-packet ts payload)
    (let* ([cipher (transport-state-send-cipher ts)]
           [cipher-name (and cipher (cipher-state-name cipher))])
      (cond
        [(and cipher-name (string=? cipher-name "chacha20-poly1305@openssh.com"))
         (send-packet-chacha20 ts payload)]
        [(and cipher-name (string=? cipher-name "aes256-ctr"))
         (send-packet-aes256-ctr ts payload)]
        [else
         (send-packet-unencrypted ts payload)])))

  (define (ssh-transport-recv-packet ts)
    (let* ([cipher (transport-state-recv-cipher ts)]
           [cipher-name (and cipher (cipher-state-name cipher))])
      (cond
        [(and cipher-name (string=? cipher-name "chacha20-poly1305@openssh.com"))
         (recv-packet-chacha20 ts)]
        [(and cipher-name (string=? cipher-name "aes256-ctr"))
         (recv-packet-aes256-ctr ts)]
        [else
         (recv-packet-unencrypted ts)])))

  ;; ---- Rekey check ----

  (define (ssh-transport-needs-rekey? ts)
    (or (> (transport-state-bytes-sent ts) REKEY-BYTES-THRESHOLD)
        (> (transport-state-bytes-received ts) REKEY-BYTES-THRESHOLD)
        (> (transport-state-packets-sent ts) REKEY-PACKETS-THRESHOLD)
        (> (transport-state-packets-received ts) REKEY-PACKETS-THRESHOLD)))

  ) ;; end library
