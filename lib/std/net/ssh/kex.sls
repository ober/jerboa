#!chezscheme
;;; (std net ssh kex) — SSH key exchange
;;;
;;; Implements curve25519-sha256 key exchange (RFC 8731),
;;; algorithm negotiation, and key derivation (RFC 4253 §7.2).
;;;
;;; FFI operations imported from (chez-ssh crypto).
;;; Uses (std net ssh conditions) for structured error hierarchy.

(library (std net ssh kex)
  (export
    ssh-kex-perform          ;; full kex handshake
    ssh-kex-build-kexinit    ;; build our KEXINIT payload
    ssh-kex-parse-kexinit    ;; parse server's KEXINIT
    ssh-kex-negotiate        ;; negotiate algorithms
    ssh-kex-derive-keys      ;; derive cipher/MAC keys from shared secret
    ssh-kex-activate-keys    ;; install derived keys into transport
    )

  (import (chezscheme)
          (std net ssh wire)
          (std net ssh transport)
          (std net ssh conditions)
          (chez-ssh crypto))

  ;; ---- Helpers ----
  ;; bytevector-append is in (chezscheme) core — no shim needed.

  (define (bytevector->uint bv)
    (let loop ([i 0] [n 0])
      (if (>= i (bytevector-length bv))
        n
        (loop (+ i 1)
              (bitwise-ior (bitwise-arithmetic-shift-left n 8)
                           (bytevector-u8-ref bv i))))))

  ;; ---- Algorithm lists (in preference order) ----
  (define KEX-ALGORITHMS '("curve25519-sha256" "curve25519-sha256@libssh.org"))
  (define HOST-KEY-ALGORITHMS '("ssh-ed25519"))
  (define CIPHER-ALGORITHMS '("chacha20-poly1305@openssh.com" "aes256-ctr"))
  (define MAC-ALGORITHMS '("hmac-sha2-256"))
  (define COMPRESS-ALGORITHMS '("none"))

  ;; ---- KEXINIT ----

  (define (ssh-kex-build-kexinit)
    (let ([cookie (make-bytevector 16)])
      (ssh-crypto-random-bytes cookie 16)
      (ssh-make-payload SSH_MSG_KEXINIT
        cookie
        (ssh-write-name-list KEX-ALGORITHMS)
        (ssh-write-name-list HOST-KEY-ALGORITHMS)
        (ssh-write-name-list CIPHER-ALGORITHMS)
        (ssh-write-name-list CIPHER-ALGORITHMS)
        (ssh-write-name-list MAC-ALGORITHMS)
        (ssh-write-name-list MAC-ALGORITHMS)
        (ssh-write-name-list COMPRESS-ALGORITHMS)
        (ssh-write-name-list COMPRESS-ALGORITHMS)
        (ssh-write-name-list '())
        (ssh-write-name-list '())
        (ssh-write-boolean #f)
        (ssh-write-uint32 0))))

  (define (ssh-kex-parse-kexinit payload)
    (let* ([off 1]
           [off (+ off 16)]
           [r1 (ssh-read-name-list payload off)]
           [kex-algos (car r1)] [off (cdr r1)]
           [r2 (ssh-read-name-list payload off)]
           [host-key-algos (car r2)] [off (cdr r2)]
           [r3 (ssh-read-name-list payload off)]
           [cipher-c2s (car r3)] [off (cdr r3)]
           [r4 (ssh-read-name-list payload off)]
           [cipher-s2c (car r4)] [off (cdr r4)]
           [r5 (ssh-read-name-list payload off)]
           [mac-c2s (car r5)] [off (cdr r5)]
           [r6 (ssh-read-name-list payload off)]
           [mac-s2c (car r6)] [off (cdr r6)]
           [r7 (ssh-read-name-list payload off)]
           [compress-c2s (car r7)] [off (cdr r7)]
           [r8 (ssh-read-name-list payload off)]
           [compress-s2c (car r8)] [off (cdr r8)])
      `((kex . ,kex-algos)
        (host-key . ,host-key-algos)
        (cipher-c2s . ,cipher-c2s)
        (cipher-s2c . ,cipher-s2c)
        (mac-c2s . ,mac-c2s)
        (mac-s2c . ,mac-s2c)
        (compress-c2s . ,compress-c2s)
        (compress-s2c . ,compress-s2c))))

  ;; ---- Algorithm negotiation ----

  (define (negotiate-one client-list server-list name)
    (let loop ([cl client-list])
      (cond
        [(null? cl)
         (raise-ssh-kex-error 'ssh-kex-negotiate 'negotiate
           (string-append "no common " name " algorithm")
           client-list server-list)]
        [(member (car cl) server-list) (car cl)]
        [else (loop (cdr cl))])))

  (define (ssh-kex-negotiate server-kexinit-parsed)
    (let ([get (lambda (key) (cdr (assq key server-kexinit-parsed)))])
      (let* ([kex (negotiate-one KEX-ALGORITHMS (get 'kex) "kex")]
             [host-key (negotiate-one HOST-KEY-ALGORITHMS (get 'host-key) "host-key")]
             [cipher-c2s (negotiate-one CIPHER-ALGORITHMS (get 'cipher-c2s) "cipher-c2s")]
             [cipher-s2c (negotiate-one CIPHER-ALGORITHMS (get 'cipher-s2c) "cipher-s2c")]
             [mac-c2s (if (string=? cipher-c2s "chacha20-poly1305@openssh.com")
                        ""
                        (negotiate-one MAC-ALGORITHMS (get 'mac-c2s) "mac-c2s"))]
             [mac-s2c (if (string=? cipher-s2c "chacha20-poly1305@openssh.com")
                        ""
                        (negotiate-one MAC-ALGORITHMS (get 'mac-s2c) "mac-s2c"))]
             [comp-c2s (negotiate-one COMPRESS-ALGORITHMS (get 'compress-c2s) "compress-c2s")]
             [comp-s2c (negotiate-one COMPRESS-ALGORITHMS (get 'compress-s2c) "compress-s2c")])
        (make-negotiated-algorithms kex host-key cipher-c2s cipher-s2c
                                    mac-c2s mac-s2c comp-c2s comp-s2c))))

  ;; ---- Key derivation (RFC 4253 §7.2) ----

  (define (derive-key shared-secret-mpint-bv exchange-hash session-id letter needed-bytes)
    (let* ([data (bytevector-append
                   shared-secret-mpint-bv
                   exchange-hash
                   (make-bytevector 1 letter)
                   session-id)]
           [hash-out (make-bytevector 32)])
      (ssh-crypto-sha256 data (bytevector-length data) hash-out)
      (if (<= needed-bytes 32)
        (let ([result (make-bytevector needed-bytes)])
          (bytevector-copy! hash-out 0 result 0 needed-bytes)
          result)
        (let loop ([acc hash-out])
          (if (>= (bytevector-length acc) needed-bytes)
            (let ([result (make-bytevector needed-bytes)])
              (bytevector-copy! acc 0 result 0 needed-bytes)
              result)
            (let* ([ext-data (bytevector-append shared-secret-mpint-bv exchange-hash acc)]
                   [next (make-bytevector 32)])
              (ssh-crypto-sha256 ext-data (bytevector-length ext-data) next)
              (loop (bytevector-append acc next))))))))

  (define (ssh-kex-derive-keys shared-secret exchange-hash session-id algorithms)
    (let* ([K-mpint (ssh-write-mpint (bytevector->uint shared-secret))]
           [cipher-c2s (negotiated-algorithms-cipher-c2s algorithms)]
           [cipher-s2c (negotiated-algorithms-cipher-s2c algorithms)]
           [chacha-c2s? (string=? cipher-c2s "chacha20-poly1305@openssh.com")]
           [chacha-s2c? (string=? cipher-s2c "chacha20-poly1305@openssh.com")]
           [cipher-key-len-c2s (if chacha-c2s? 64 32)]
           [cipher-key-len-s2c (if chacha-s2c? 64 32)]
           [iv-len-c2s (if chacha-c2s? 0 16)]
           [iv-len-s2c (if chacha-s2c? 0 16)]
           [mac-key-len 32]
           [iv-c2s (if (> iv-len-c2s 0)
                     (derive-key K-mpint exchange-hash session-id
                       (char->integer #\A) iv-len-c2s)
                     #f)]
           [iv-s2c (if (> iv-len-s2c 0)
                     (derive-key K-mpint exchange-hash session-id
                       (char->integer #\B) iv-len-s2c)
                     #f)]
           [key-c2s (derive-key K-mpint exchange-hash session-id
                      (char->integer #\C) cipher-key-len-c2s)]
           [key-s2c (derive-key K-mpint exchange-hash session-id
                      (char->integer #\D) cipher-key-len-s2c)]
           [mac-c2s (if chacha-c2s? #f
                      (derive-key K-mpint exchange-hash session-id
                        (char->integer #\E) mac-key-len))]
           [mac-s2c (if chacha-s2c? #f
                      (derive-key K-mpint exchange-hash session-id
                        (char->integer #\F) mac-key-len))])
      (values iv-c2s iv-s2c key-c2s key-s2c mac-c2s mac-s2c)))

  ;; ---- Activate keys ----

  (define (ssh-kex-activate-keys ts algorithms
                                  iv-c2s iv-s2c key-c2s key-s2c mac-c2s mac-s2c)
    (let ([cipher-c2s (negotiated-algorithms-cipher-c2s algorithms)]
          [cipher-s2c (negotiated-algorithms-cipher-s2c algorithms)])
      (let ([send-cs (make-cipher-for cipher-c2s key-c2s iv-c2s mac-c2s)])
        (transport-state-send-cipher-set! ts send-cs))
      (let ([recv-cs (make-cipher-for cipher-s2c key-s2c iv-s2c mac-s2c)])
        (transport-state-recv-cipher-set! ts recv-cs))
      (transport-state-algorithms-set! ts algorithms)
      (transport-state-bytes-sent-set! ts 0)
      (transport-state-bytes-received-set! ts 0)
      (transport-state-packets-sent-set! ts 0)
      (transport-state-packets-received-set! ts 0)))

  (define (make-cipher-for cipher-name key iv mac-key)
    (cond
      [(string=? cipher-name "chacha20-poly1305@openssh.com")
       (make-cipher-state cipher-name key #f #f #f)]
      [(string=? cipher-name "aes256-ctr")
       (let ([ctx-buf (make-bytevector 512)])
         (let ([rc (ssh-crypto-aes256-ctr-init key iv ctx-buf 512)])
           (when (< rc 0)
             (raise-ssh-kex-error 'ssh-kex-activate-keys 'ecdh
               "AES-256-CTR cipher init failed"))
           (make-cipher-state cipher-name key mac-key iv ctx-buf)))]
      [else
       (raise-ssh-kex-error 'ssh-kex-activate-keys 'negotiate
         (string-append "unsupported cipher: " cipher-name))]))

  ;; ---- Exchange hash computation ----

  (define (compute-exchange-hash client-version server-version
                                  client-kexinit server-kexinit
                                  host-key-blob
                                  client-ephemeral-pub server-ephemeral-pub
                                  shared-secret)
    (let* ([K-mpint (ssh-write-mpint (bytevector->uint shared-secret))]
           [data (bytevector-append
                   (ssh-write-string client-version)
                   (ssh-write-string server-version)
                   (ssh-write-string client-kexinit)
                   (ssh-write-string server-kexinit)
                   (ssh-write-string host-key-blob)
                   (ssh-write-string client-ephemeral-pub)
                   (ssh-write-string server-ephemeral-pub)
                   K-mpint)]
           [hash-out (make-bytevector 32)])
      (ssh-crypto-sha256 data (bytevector-length data) hash-out)
      hash-out))

  ;; ---- Verify host key signature ----

  (define (verify-host-key-signature host-key-blob exchange-hash signature-blob)
    (let* ([r1 (ssh-read-string host-key-blob 0)]
           [key-type (utf8->string (car r1))]
           [off1 (cdr r1)])
      (unless (string=? key-type "ssh-ed25519")
        (raise-ssh-host-key-error 'verify-host-key 'unsupported #f
          (string-append "unsupported host key type: " key-type)))
      (let* ([r2 (ssh-read-string host-key-blob off1)]
             [pubkey (car r2)]
             [r3 (ssh-read-string signature-blob 0)]
             [sig-type (utf8->string (car r3))]
             [off3 (cdr r3)])
        (unless (string=? sig-type "ssh-ed25519")
          (raise-ssh-host-key-error 'verify-host-key 'unsupported #f
            (string-append "signature type mismatch: " sig-type)))
        (let* ([r4 (ssh-read-string signature-blob off3)]
               [sig (car r4)])
          (when (not (= (bytevector-length pubkey) 32))
            (raise-ssh-host-key-error 'verify-host-key 'unsupported #f
              "invalid pubkey length (expected 32)"))
          (when (not (= (bytevector-length sig) 64))
            (raise-ssh-host-key-error 'verify-host-key 'unsupported #f
              "invalid signature length (expected 64)"))
          (let ([rc (ssh-crypto-ed25519-verify pubkey exchange-hash
                                      (bytevector-length exchange-hash) sig)])
            (= rc 0))))))

  ;; ---- Full key exchange ----

  (define (ssh-kex-perform ts host-key-verifier)
    (let ([client-kexinit (ssh-kex-build-kexinit)])
      (transport-state-client-kexinit-set! ts client-kexinit)
      (ssh-transport-send-packet ts client-kexinit)

      (let ([server-kexinit (ssh-transport-recv-packet ts)])
        (unless (= (bytevector-u8-ref server-kexinit 0) SSH_MSG_KEXINIT)
          (raise-ssh-protocol-error 'ssh-kex-perform
            SSH_MSG_KEXINIT (bytevector-u8-ref server-kexinit 0)
            "expected KEXINIT from server"))
        (transport-state-server-kexinit-set! ts server-kexinit)

        (let* ([server-parsed (ssh-kex-parse-kexinit server-kexinit)]
               [algorithms (ssh-kex-negotiate server-parsed)])
          (transport-state-algorithms-set! ts algorithms)

          (let ([client-priv (make-bytevector 32)]
                [client-pub (make-bytevector 32)])
            (let ([rc (ssh-crypto-curve25519-keygen client-priv client-pub)])
              (when (< rc 0)
                (raise-ssh-kex-error 'ssh-kex-perform 'ecdh
                  "Curve25519 keygen failed"))

              (ssh-transport-send-packet ts
                (ssh-make-payload SSH_MSG_KEX_ECDH_INIT
                  (ssh-write-string client-pub)))

              (let ([reply (ssh-transport-recv-packet ts)])
                (unless (= (bytevector-u8-ref reply 0) SSH_MSG_KEX_ECDH_REPLY)
                  (raise-ssh-protocol-error 'ssh-kex-perform
                    SSH_MSG_KEX_ECDH_REPLY (bytevector-u8-ref reply 0)
                    "expected KEX_ECDH_REPLY from server"))

                (let* ([off 1]
                       [r1 (ssh-read-string reply off)]
                       [host-key-blob (car r1)] [off (cdr r1)]
                       [r2 (ssh-read-string reply off)]
                       [server-pub (car r2)] [off (cdr r2)]
                       [r3 (ssh-read-string reply off)]
                       [signature (car r3)])

                  (let ([secret-buf (make-bytevector 32)]
                        [secret-len-buf (make-bytevector 4 0)])
                    (let ([rc (ssh-crypto-curve25519-shared-secret client-priv server-pub
                                                          secret-buf secret-len-buf)])
                      (when (< rc 0)
                        (raise-ssh-kex-error 'ssh-kex-perform 'ecdh
                          "ECDH shared secret computation failed"))

                      (let ([H (compute-exchange-hash
                                 (transport-state-client-version ts)
                                 (transport-state-server-version ts)
                                 client-kexinit server-kexinit
                                 host-key-blob
                                 client-pub server-pub
                                 secret-buf)])

                        (unless (host-key-verifier host-key-blob)
                          (raise-ssh-host-key-error 'ssh-kex-perform 'rejected
                            (ssh-host-key-fingerprint* host-key-blob)
                            "host key rejected by verifier"))

                        (unless (verify-host-key-signature host-key-blob H signature)
                          (raise-ssh-host-key-error 'ssh-kex-perform 'rejected
                            (ssh-host-key-fingerprint* host-key-blob)
                            "host key signature verification failed"))

                        (unless (transport-state-session-id ts)
                          (transport-state-session-id-set! ts H))

                        (ssh-transport-send-packet ts
                          (ssh-make-payload SSH_MSG_NEWKEYS))

                        (let ([newkeys (ssh-transport-recv-packet ts)])
                          (unless (= (bytevector-u8-ref newkeys 0) SSH_MSG_NEWKEYS)
                            (raise-ssh-protocol-error 'ssh-kex-perform
                              SSH_MSG_NEWKEYS (bytevector-u8-ref newkeys 0)
                              "expected NEWKEYS from server"))

                          (let-values ([(iv-c2s iv-s2c key-c2s key-s2c mac-c2s mac-s2c)
                                        (ssh-kex-derive-keys secret-buf H
                                          (transport-state-session-id ts) algorithms)])
                            (ssh-kex-activate-keys ts algorithms
                              iv-c2s iv-s2c key-c2s key-s2c mac-c2s mac-s2c))

                          (bytevector-fill! client-priv 0)
                          (bytevector-fill! secret-buf 0)

                          H))))))))))))

  ;; Simple SHA-256 fingerprint for condition reporting (no base64 needed)
  (define (ssh-host-key-fingerprint* host-key-blob)
    (let ([hash (make-bytevector 32)])
      (ssh-crypto-sha256 host-key-blob (bytevector-length host-key-blob) hash)
      (let loop ([i 0] [acc '()])
        (if (>= i (min 8 (bytevector-length hash)))
          (apply string-append (reverse acc))
          (let ([b (bytevector-u8-ref hash i)])
            (loop (+ i 1)
                  (cons (string-append
                          (if (null? acc) "" ":")
                          (if (< b 16) "0" "")
                          (number->string b 16))
                        acc)))))))

  ) ;; end library
