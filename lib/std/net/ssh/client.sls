#!chezscheme
;;; (std net ssh client) — High-level SSH client API
;;;
;;; Provides ssh-connect, ssh-run, ssh-shell, ssh-sftp, ssh-forward-*
;;; as the primary user-facing interface.
;;;
;;; Uses (std net ssh conditions) for structured error hierarchy.
;;; Uses (std misc custodian) for automatic connection cleanup.
;;; Uses (std misc retry) for exponential backoff on connection failure.
;;; Uses (std misc pool) for SSH connection pooling.
;;; Uses (std contract) for argument validation on public API.
;;; Uses (std misc state-machine) for connection lifecycle management.

(library (std net ssh client)
  (export
    ;; Connection
    ssh-connect               ;; (host #:port #:user #:key-file #:password ...) → ssh-connection
    ssh-disconnect            ;; (conn) → void

    ;; Connection record accessors
    ssh-connection?
    ssh-connection-transport
    ssh-connection-channel-table
    ssh-connection-state       ;; → symbol: 'connecting | 'authenticating | 'established | 'disconnected

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

    ;; Custodian integration
    with-ssh-connection       ;; (host port user key-file password thunk) → result
    ssh-connection-custodian  ;; (conn) → custodian

    ;; Connection pooling
    make-ssh-pool             ;; (host port user key-file password max-size) → pool
    with-pooled-ssh           ;; (pool thunk) → result
    ssh-pool-drain            ;; (pool) → void
    ssh-pool-stats            ;; (pool) → alist
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
          (std net ssh forward)
          (std net ssh conditions)
          (std misc custodian)
          (std misc retry)
          (std misc pool)
          (std contract)
          (std misc state-machine)
          (chez-ssh crypto))

  ;; ---- Connection lifecycle state machine ----
  ;; Tracks the connection through its phases to prevent invalid operations.
  (define (make-connection-sm)
    (make-state-machine 'idle
      `((idle         connect       connecting    ,void)
        (connecting   kex-done      authenticating ,void)
        (authenticating auth-done   established   ,void)
        (established  disconnect    disconnected  ,void)
        (connecting   error         disconnected  ,void)
        (authenticating error       disconnected  ,void)
        (established  error         disconnected  ,void))))

  ;; ---- Connection record ----

  (define-record-type ssh-connection
    (fields
      transport
      channel-table
      host
      port
      user
      sm              ;; state-machine: lifecycle tracking
      cust))          ;; custodian or #f

  (define (ssh-connection-state conn)
    (sm-state (ssh-connection-sm conn)))

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
       (check-argument string? host 'ssh-connect)
       (check-argument integer? port 'ssh-connect)
       (check-argument string? user 'ssh-connect)
       (ssh-connect-internal host port user key-file password)]))

  (define (ssh-connect-internal host port user key-file password)
    (let ([sm (make-connection-sm)]
          [cust (make-custodian)])
      (sm-send! sm 'connect)

      ;; Use retry with exponential backoff for TCP connection.
      ;; Retries 3 times with 1s base delay, 10s max delay on connection failure.
      (let ([fd (retry/backoff
                  (lambda () (ssh-transport-connect host port))
                  (make-retry-policy 3 1.0 10.0))])

        ;; Register fd cleanup with custodian — thunk captures fd in closure
        (custodian-register! cust fd
          (lambda () (guard (e [#t (void)]) (ssh-crypto-tcp-close fd))))

        (let* ([client-ver (ssh-transport-send-version fd)]
               [server-ver (ssh-transport-recv-version fd)]
               [ts (make-transport-state fd server-ver client-ver)]
               [table (make-channel-table)])

          (let ([verifier (ssh-known-hosts-verifier host port)])
            (ssh-kex-perform ts verifier))
          (sm-send! sm 'kex-done)

          (ssh-userauth-request ts)

          (cond
            [key-file
             (let ([seed (load-ed25519-seed key-file)])
               (if seed
                 (ssh-auth-publickey ts user seed)
                 (if password
                   (ssh-auth-password ts user password)
                   (raise-ssh-auth-error 'ssh-connect 'publickey '()
                     (string-append "failed to load key file: " key-file)))))]
            [(find-default-key)
             => (lambda (seed)
                  (ssh-auth-publickey ts user seed))]
            [password
             (ssh-auth-password ts user password)]
            [else
             (raise-ssh-auth-error 'ssh-connect 'none
               '("publickey" "password")
               "no authentication method available (no key file or password)")])
          (sm-send! sm 'auth-done)

          (make-ssh-connection ts table host port user sm cust)))))

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
    (when (eq? (ssh-connection-state conn) 'established)
      (sm-send! (ssh-connection-sm conn) 'disconnect)
      (guard (e [#t (void)])
        (ssh-transport-send-packet (ssh-connection-transport conn)
          (ssh-make-payload SSH_MSG_DISCONNECT
            (ssh-write-uint32 SSH_DISCONNECT_BY_APPLICATION)
            (ssh-write-string "bye")
            (ssh-write-string ""))))
      (ssh-transport-close (ssh-connection-transport conn))
      ;; Shut down the custodian to clean up any registered resources
      (when (ssh-connection-cust conn)
        (custodian-shutdown-all (ssh-connection-cust conn)))))

  ;; ---- Custodian integration ----
  ;; Ensures all SSH resources are cleaned up even on exceptions.

  (define (ssh-connection-custodian conn)
    (ssh-connection-cust conn))

  (define (with-ssh-connection host port user key-file password thunk)
    (let ([conn (ssh-connect host port user key-file password)])
      (dynamic-wind
        (lambda () (void))
        (lambda () (thunk conn))
        (lambda () (ssh-disconnect conn)))))

  ;; ---- Connection pooling ----
  ;; Reuses SSH connections across multiple operations.
  ;; Pool manages connect/disconnect lifecycle automatically.

  (define make-ssh-pool
    (case-lambda
      [(host port user key-file password max-size)
       (make-ssh-pool host port user key-file password max-size #f)]
      [(host port user key-file password max-size idle-timeout)
       (make-pool
         ;; creator: establish a new SSH connection
         (lambda ()
           (ssh-connect host port user key-file password))
         ;; destroyer: disconnect cleanly
         (lambda (conn)
           (guard (e [#t (void)])
             (ssh-disconnect conn)))
         max-size
         idle-timeout)]))

  (define (with-pooled-ssh pool thunk)
    (with-resource pool thunk))

  (define (ssh-pool-drain pool)
    (pool-drain pool))

  (define (ssh-pool-stats pool)
    (pool-stats pool))

  ;; ---- Command execution ----

  (define (ssh-run conn command)
    (check-argument ssh-connection? conn 'ssh-run)
    (check-argument string? command 'ssh-run)
    (ssh-session-exec-simple
      (ssh-connection-transport conn)
      (ssh-connection-channel-table conn)
      command))

  (define (ssh-capture conn command)
    (check-argument ssh-connection? conn 'ssh-capture)
    (check-argument string? command 'ssh-capture)
    (let ([result (ssh-run conn command)])
      (unless (= (car result) 0)
        (raise-ssh-error 'ssh-capture
          (string-append "command failed with exit status "
                         (number->string (car result)))
          command))
      (cdr result)))

  ;; ---- Interactive ----

  (define (ssh-shell conn)
    (check-argument ssh-connection? conn 'ssh-shell)
    (ssh-session-shell
      (ssh-connection-transport conn)
      (ssh-connection-channel-table conn)))

  (define (ssh-exec conn command)
    (check-argument ssh-connection? conn 'ssh-exec)
    (check-argument string? command 'ssh-exec)
    (ssh-session-exec
      (ssh-connection-transport conn)
      (ssh-connection-channel-table conn)
      command))

  ;; ---- SFTP ----

  (define (ssh-sftp conn)
    (check-argument ssh-connection? conn 'ssh-sftp)
    (ssh-sftp-open-session
      (ssh-connection-transport conn)
      (ssh-connection-channel-table conn)))

  (define (ssh-sftp-close conn sftp)
    (check-argument ssh-connection? conn 'ssh-sftp-close)
    (ssh-sftp-close-session
      (ssh-connection-transport conn)
      (ssh-connection-channel-table conn)
      sftp))

  (define (ssh-scp-get conn remote-path local-path)
    (check-argument ssh-connection? conn 'ssh-scp-get)
    (check-argument string? remote-path 'ssh-scp-get)
    (check-argument string? local-path 'ssh-scp-get)
    (let ([sftp (ssh-sftp conn)])
      (ssh-sftp-get sftp remote-path local-path)
      (ssh-sftp-close conn sftp)))

  (define (ssh-scp-put conn local-path remote-path)
    (check-argument ssh-connection? conn 'ssh-scp-put)
    (check-argument string? local-path 'ssh-scp-put)
    (check-argument string? remote-path 'ssh-scp-put)
    (let ([sftp (ssh-sftp conn)])
      (ssh-sftp-put sftp local-path remote-path)
      (ssh-sftp-close conn sftp)))

  ;; ---- Port forwarding ----

  (define ssh-forward-local
    (case-lambda
      [(conn local-port remote-host remote-port)
       (ssh-forward-local conn "127.0.0.1" local-port remote-host remote-port)]
      [(conn bind-addr local-port remote-host remote-port)
       (check-argument ssh-connection? conn 'ssh-forward-local)
       (ssh-forward-local-start
         (ssh-connection-transport conn)
         (ssh-connection-channel-table conn)
         bind-addr local-port remote-host remote-port)]))

  (define ssh-forward-remote
    (case-lambda
      [(conn remote-port)
       (ssh-forward-remote conn "" remote-port)]
      [(conn bind-addr remote-port)
       (check-argument ssh-connection? conn 'ssh-forward-remote)
       (ssh-forward-remote-request
         (ssh-connection-transport conn)
         bind-addr remote-port)]))

  ) ;; end library
