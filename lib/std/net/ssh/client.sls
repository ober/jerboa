#!chezscheme
;;; (std net ssh client) — High-level SSH client API
;;;
;;; Provides ssh-connect, ssh-run, ssh-shell, ssh-sftp, ssh-forward-*
;;; as the primary user-facing interface.
;;; Pure protocol logic — all FFI goes through (chez-ssh crypto).

(library (std net ssh client)
  (export
    ;; Connection
    ssh-connect               ;; (host #:port #:user #:key-file #:password ...) → ssh-connection
    ssh-disconnect            ;; (conn) → void

    ;; Connection record accessors
    ssh-connection?
    ssh-connection-transport
    ssh-connection-channel-table

    ;; Command execution
    ssh-run                   ;; (conn command) → (exit-status . output)
    ssh-capture               ;; (conn command) → output-string (errors on non-zero exit)

    ;; Interactive shell
    ssh-shell                 ;; (conn) → channel
    ssh-exec                  ;; (conn command) → channel

    ;; SFTP
    ssh-sftp                  ;; (conn) → sftp-session
    ssh-sftp-close            ;; (conn sftp) → void
    ssh-scp-get               ;; (conn remote local) → void
    ssh-scp-put               ;; (conn local remote) → void

    ;; Port forwarding
    ssh-forward-local         ;; (conn local-port remote-host remote-port ...) → listener
    ssh-forward-remote        ;; (conn remote-port ...) → allocated-port
    )

  (import (chezscheme)
          (std net ssh wire)
          (std net ssh transport)
          (std net ssh kex)
          (std net ssh known-hosts)
          (std net ssh auth)
          (std net ssh channel)
          (std net ssh session)
          (std net ssh sftp)
          (std net ssh forward))

  ;; ---- Connection record ----

  (define-record-type ssh-connection
    (fields
      transport
      channel-table
      host
      port
      user))

  ;; ---- Connect ----

  (define ssh-connect
    (case-lambda
      [(host)
       (ssh-connect host 22 (or (getenv "USER") "root") #f #f)]
      [(host port)
       (ssh-connect host port (or (getenv "USER") "root") #f #f)]
      [(host port user)
       (ssh-connect host port user #f #f)]
      [(host port user key-file)
       (ssh-connect host port user key-file #f)]
      [(host port user key-file password)
       (ssh-connect-internal host port user key-file password)]))

  (define (ssh-connect-internal host port user key-file password)
    (let ([fd (ssh-transport-connect host port)])

      (let* ([client-ver (ssh-transport-send-version fd)]
             [server-ver (ssh-transport-recv-version fd)]
             [ts (make-transport-state fd server-ver client-ver)]
             [table (make-channel-table)])

        (let ([verifier (ssh-known-hosts-verifier host port)])
          (ssh-kex-perform ts verifier))

        (ssh-userauth-request ts)

        (cond
          [key-file
           (let ([seed (load-ed25519-seed key-file)])
             (if seed
               (ssh-auth-publickey ts user seed)
               (if password
                 (ssh-auth-password ts user password)
                 (error 'ssh-connect "failed to load key file" key-file))))]
          [(find-default-key)
           => (lambda (seed)
                (ssh-auth-publickey ts user seed))]
          [password
           (ssh-auth-password ts user password)]
          [else
           (error 'ssh-connect
                  "no authentication method available (no key file or password)")])

        (make-ssh-connection ts table host port user))))

  ;; ---- Key loading ----

  (define (load-ed25519-seed path)
    (guard (e [#t #f])
      (let* ([expanded (if (and (> (string-length path) 0)
                               (char=? (string-ref path 0) #\~))
                         (string-append (or (getenv "HOME") "")
                                       (substring path 1 (string-length path)))
                         path)]
             [port (open-file-input-port expanded)]
             [data (get-bytevector-all port)])
        (close-port port)
        (if (eof-object? data)
          #f
          (parse-openssh-ed25519-seed data)))))

  (define (parse-openssh-ed25519-seed data)
    (let ([text (if (bytevector? data) (utf8->string data) data)])
      (let* ([begin-marker "-----BEGIN OPENSSH PRIVATE KEY-----"]
             [end-marker "-----END OPENSSH PRIVATE KEY-----"]
             [begin-pos (string-search text begin-marker)]
             [end-pos (and begin-pos (string-search text end-marker))])
        (if (not (and begin-pos end-pos))
          #f
          (let* ([b64-start (+ begin-pos (string-length begin-marker))]
                 [b64-text (substring text b64-start end-pos)]
                 [b64-clean (list->string
                              (filter (lambda (c) (not (char-whitespace? c)))
                                      (string->list b64-text)))]
                 [decoded (base64-decode-simple b64-clean)])
            (extract-ed25519-seed-from-decoded decoded))))))

  (define (string-search haystack needle)
    (let ([hlen (string-length haystack)]
          [nlen (string-length needle)])
      (let loop ([i 0])
        (cond
          [(> (+ i nlen) hlen) #f]
          [(string=? (substring haystack i (+ i nlen)) needle) i]
          [else (loop (+ i 1))]))))

  (define (extract-ed25519-seed-from-decoded bv)
    (guard (e [#t #f])
      (let loop ([off 0])
        (let ([magic "openssh-key-v1"])
          (when (< (bytevector-length bv) 15) (error 'parse "too short"))
          (let ([off 15])
            (let* ([r (read-ssh-string bv off)] [cipher (car r)] [off (cdr r)])
              (when (not (string=? (utf8->string cipher) "none"))
                (error 'parse "encrypted key"))
              (let* ([r (read-ssh-string bv off)] [off (cdr r)])
                (let* ([r (read-ssh-string bv off)] [off (cdr r)])
                  (let* ([r (read-uint32 bv off)] [nkeys (car r)] [off (cdr r)])
                    (let* ([r (read-ssh-string bv off)] [off (cdr r)])
                      (let* ([r (read-ssh-string bv off)]
                             [priv-blob (car r)])
                        (let* ([off 0]
                               [r (read-uint32 priv-blob off)] [off (cdr r)]
                               [r (read-uint32 priv-blob off)] [off (cdr r)]
                               [r (read-ssh-string priv-blob off)]
                               [kt (utf8->string (car r))] [off (cdr r)])
                          (unless (string=? kt "ssh-ed25519")
                            (error 'parse "not ed25519"))
                          (let* ([r (read-ssh-string priv-blob off)] [off (cdr r)])
                            (let* ([r (read-ssh-string priv-blob off)]
                                   [privkey (car r)])
                              (when (< (bytevector-length privkey) 32)
                                (error 'parse "privkey too short"))
                              (let ([seed (make-bytevector 32)])
                                (bytevector-copy! privkey 0 seed 0 32)
                                seed)))))))))))))))

  (define (read-uint32 bv off)
    (cons (bitwise-ior
            (bitwise-arithmetic-shift-left (bytevector-u8-ref bv off) 24)
            (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ off 1)) 16)
            (bitwise-arithmetic-shift-left (bytevector-u8-ref bv (+ off 2)) 8)
            (bytevector-u8-ref bv (+ off 3)))
          (+ off 4)))

  (define (read-ssh-string bv off)
    (let* ([r (read-uint32 bv off)]
           [len (car r)]
           [off (cdr r)]
           [data (make-bytevector len)])
      (bytevector-copy! bv off data 0 len)
      (cons data (+ off len))))

  (define (base64-decode-simple s)
    (let ([table (make-vector 128 -1)]
          [chars "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"])
      (do ([i 0 (+ i 1)])
        ((>= i 64))
        (vector-set! table (char->integer (string-ref chars i)) i))
      (let ([vals (let loop ([i 0] [acc '()])
                    (if (>= i (string-length s))
                      (reverse acc)
                      (let ([c (string-ref s i)])
                        (if (char=? c #\=)
                          (reverse acc)
                          (let ([v (and (< (char->integer c) 128)
                                       (vector-ref table (char->integer c)))])
                            (if (and v (>= v 0))
                              (loop (+ i 1) (cons v acc))
                              (loop (+ i 1) acc)))))))])
        (let* ([nvals (length vals)]
               [nbytes (- (quotient (* nvals 3) 4)
                          (cond [(= (modulo nvals 4) 2) 1]
                                [(= (modulo nvals 4) 3) 0]
                                [else 0]))])
          (let loop ([vs vals] [acc '()])
            (cond
              [(null? vs)
               (u8-list->bytevector (reverse acc))]
              [(>= (length vs) 4)
               (let ([a (car vs)] [b (cadr vs)] [c (caddr vs)] [d (cadddr vs)])
                 (loop (cddddr vs)
                       (cons (bitwise-and #xff (bitwise-ior (bitwise-arithmetic-shift-left c 6) d))
                         (cons (bitwise-and #xff (bitwise-ior (bitwise-arithmetic-shift-left b 4)
                                                              (bitwise-arithmetic-shift-right c 2)))
                           (cons (bitwise-and #xff (bitwise-ior (bitwise-arithmetic-shift-left a 2)
                                                                (bitwise-arithmetic-shift-right b 4)))
                             acc)))))]
              [(= (length vs) 3)
               (let ([a (car vs)] [b (cadr vs)] [c (caddr vs)])
                 (let ([acc (cons (bitwise-and #xff (bitwise-ior (bitwise-arithmetic-shift-left b 4)
                                                                (bitwise-arithmetic-shift-right c 2)))
                              (cons (bitwise-and #xff (bitwise-ior (bitwise-arithmetic-shift-left a 2)
                                                                   (bitwise-arithmetic-shift-right b 4)))
                                acc))])
                   (u8-list->bytevector (reverse acc))))]
              [(= (length vs) 2)
               (let ([a (car vs)] [b (cadr vs)])
                 (let ([acc (cons (bitwise-and #xff (bitwise-ior (bitwise-arithmetic-shift-left a 2)
                                                                (bitwise-arithmetic-shift-right b 4)))
                              acc)])
                   (u8-list->bytevector (reverse acc))))]
              [else
               (u8-list->bytevector (reverse acc))]))))))

  (define (find-default-key)
    (let ([home (or (getenv "HOME") "")])
      (let loop ([files (list
                          (string-append home "/.ssh/id_ed25519"))])
        (cond
          [(null? files) #f]
          [(file-exists? (car files))
           (load-ed25519-seed (car files))]
          [else (loop (cdr files))]))))

  ;; ---- Disconnect ----

  (define (ssh-disconnect conn)
    (guard (e [#t (void)])
      (ssh-transport-send-packet (ssh-connection-transport conn)
        (ssh-make-payload SSH_MSG_DISCONNECT
          (ssh-write-uint32 SSH_DISCONNECT_BY_APPLICATION)
          (ssh-write-string "bye")
          (ssh-write-string ""))))
    (ssh-transport-close (ssh-connection-transport conn)))

  ;; ---- Command execution ----

  (define (ssh-run conn command)
    (ssh-session-exec-simple
      (ssh-connection-transport conn)
      (ssh-connection-channel-table conn)
      command))

  (define (ssh-capture conn command)
    (let ([result (ssh-run conn command)])
      (unless (= (car result) 0)
        (error 'ssh-capture
               (string-append "command failed with exit status "
                              (number->string (car result)))
               command))
      (cdr result)))

  ;; ---- Interactive ----

  (define (ssh-shell conn)
    (ssh-session-shell
      (ssh-connection-transport conn)
      (ssh-connection-channel-table conn)))

  (define (ssh-exec conn command)
    (ssh-session-exec
      (ssh-connection-transport conn)
      (ssh-connection-channel-table conn)
      command))

  ;; ---- SFTP ----

  (define (ssh-sftp conn)
    (ssh-sftp-open-session
      (ssh-connection-transport conn)
      (ssh-connection-channel-table conn)))

  (define (ssh-sftp-close conn sftp)
    (ssh-sftp-close-session
      (ssh-connection-transport conn)
      (ssh-connection-channel-table conn)
      sftp))

  (define (ssh-scp-get conn remote-path local-path)
    (let ([sftp (ssh-sftp conn)])
      (ssh-sftp-get sftp remote-path local-path)
      (ssh-sftp-close conn sftp)))

  (define (ssh-scp-put conn local-path remote-path)
    (let ([sftp (ssh-sftp conn)])
      (ssh-sftp-put sftp local-path remote-path)
      (ssh-sftp-close conn sftp)))

  ;; ---- Port forwarding ----

  (define ssh-forward-local
    (case-lambda
      [(conn local-port remote-host remote-port)
       (ssh-forward-local conn "127.0.0.1" local-port remote-host remote-port)]
      [(conn bind-addr local-port remote-host remote-port)
       (ssh-forward-local-start
         (ssh-connection-transport conn)
         (ssh-connection-channel-table conn)
         bind-addr local-port remote-host remote-port)]))

  (define ssh-forward-remote
    (case-lambda
      [(conn remote-port)
       (ssh-forward-remote conn "" remote-port)]
      [(conn bind-addr remote-port)
       (ssh-forward-remote-request
         (ssh-connection-transport conn)
         bind-addr remote-port)]))

  ) ;; end library
