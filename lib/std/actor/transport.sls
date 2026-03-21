#!chezscheme
;;; (std actor transport) — Distributed actor transport
;;;
;;; Extends send to work across network nodes via TCP.
;;; Uses (std net tcp-raw) for TCP: fd-based POSIX sockets, no SSL dependency.
;;;
;;; Message framing: [4 bytes big-endian length][N bytes fasl-encoded body]
;;; Authentication: HMAC-SHA256 challenge-response with per-connection nonce.
;;;   1. Client sends (hello node-id nonce)
;;;   2. Server sends (challenge server-nonce)
;;;   3. Client sends HMAC-SHA256(cookie, client-nonce || server-nonce || node-id)
;;;   4. Server verifies, sends HMAC-SHA256(cookie, server-nonce || client-nonce || node-id)
;;;   5. Client verifies — mutual authentication complete
;;;
;;; Wire into the system at startup:
;;;   (start-node! "127.0.0.1" 9000 "my-secret-cookie")
;;;   (start-node-server! 9000)
;;;   (set-remote-send-handler!
;;;     (lambda (actor msg)
;;;       (transport-remote-send! actor msg)))

(library (std actor transport)
  (export
    ;; Node identity
    start-node!
    current-node-id

    ;; Server
    start-node-server!

    ;; Remote refs
    make-remote-actor-ref

    ;; Wiring hook
    transport-remote-send!

    ;; Connection management
    drop-connection!
    transport-shutdown!

    ;; Serialization (exposed for testing)
    message->bytes
    bytes->message
  )
  (import (chezscheme)
          (std actor core)
          (std net tcp-raw)
          (std crypto native)
          (std crypto random))

  ;; -------- 7A: Serialization --------

  ;; Serialize msg to a framed bytevector: [4-byte BE length][fasl body]
  (define (message->bytes msg)
    (let-values ([(port get-bytes) (open-bytevector-output-port)])
      (fasl-write msg port)
      (let* ([body  (get-bytes)]
             [n     (bytevector-length body)]
             [frame (make-bytevector (fx+ 4 n))])
        (bytevector-u8-set! frame 0 (fxlogand (fxsra n 24) #xFF))
        (bytevector-u8-set! frame 1 (fxlogand (fxsra n 16) #xFF))
        (bytevector-u8-set! frame 2 (fxlogand (fxsra n  8) #xFF))
        (bytevector-u8-set! frame 3 (fxlogand  n           #xFF))
        (bytevector-copy! body 0 frame 4 n)
        frame)))

  ;; Deserialize from a framed bytevector (strips the 4-byte header).
  (define (bytes->message frame)
    (when (< (bytevector-length frame) 4)
      (error 'bytes->message "frame too short"))
    (let ([n (fx+ (fx+ (fx+ (fxsll (bytevector-u8-ref frame 0) 24)
                             (fxsll (bytevector-u8-ref frame 1) 16))
                        (fxsll (bytevector-u8-ref frame 2) 8))
                  (bytevector-u8-ref frame 3))])
      (let ([body (make-bytevector n)])
        (bytevector-copy! frame 4 body 0 n)
        (fasl-read (open-bytevector-input-port body)))))

  ;; Read exactly n bytes from fd; error on short read or EOF.
  (define (read-exact fd n)
    (let ([buf (make-bytevector n 0)])
      (let loop ([offset 0])
        (if (fx= offset n)
          buf
          (let ([got (tcp-read fd buf (fx- n offset))])
            ;; tcp-read fills from the start of buf; we need to handle partial reads
            ;; by reading into a temporary buffer and copying
            (if (or (not got) (fx<= got 0))
              (error 'read-exact "connection closed")
              (loop (fx+ offset got))))))))

  ;; read-exact that handles partial reads properly (offset into buf)
  (define (read-exact-into-buf fd buf offset n)
    (let loop ([pos offset] [remaining n])
      (if (fx= remaining 0)
        buf
        (let ([tmp (make-bytevector remaining 0)])
          (let ([got (tcp-read fd tmp remaining)])
            (if (or (not got) (fx<= got 0))
              (error 'read-exact "connection closed")
              (begin
                (bytevector-copy! tmp 0 buf pos got)
                (loop (fx+ pos got) (fx- remaining got)))))))))

  ;; Read one framed message from an fd.
  (define (read-framed-message fd)
    (let ([header (make-bytevector 4 0)])
      (read-exact-into-buf fd header 0 4)
      (let ([n (fx+ (fx+ (fx+ (fxsll (bytevector-u8-ref header 0) 24)
                               (fxsll (bytevector-u8-ref header 1) 16))
                          (fxsll (bytevector-u8-ref header 2) 8))
                    (bytevector-u8-ref header 3))])
        (let ([body (make-bytevector n 0)])
          (read-exact-into-buf fd body 0 n)
          (fasl-read (open-bytevector-input-port body))))))

  ;; Write one framed message to an fd.
  (define (write-framed-message fd msg)
    (tcp-write fd (message->bytes msg)))

  ;; -------- 7B: Node identity --------

  (define *node-id*     (make-parameter #f))
  (define *node-cookie* (make-parameter #f))

  (define (current-node-id) (*node-id*))

  ;; Initialize this process as a named node; returns "host:port".
  (define (start-node! host port cookie)
    (let ([id (string-append host ":" (number->string port))])
      (*node-id* id)
      (*node-cookie* cookie)
      id))

  ;; Parse "host:port" searching from the right (safe for IPv6).
  (define (node-id->host+port node-id)
    (let loop ([i (fx- (string-length node-id) 1)])
      (cond
        [(fx< i 0)
         (error 'node-id->host+port "no colon in node-id" node-id)]
        [(char=? (string-ref node-id i) #\:)
         (values (substring node-id 0 i)
                 (string->number (substring node-id (fx+ i 1)
                                            (string-length node-id))))]
        [else (loop (fx- i 1))])))

  ;; -------- 7C: HMAC-SHA256 Authentication --------

  (define NONCE_SIZE 32)  ;; 256-bit nonces

  ;; Compute HMAC-SHA256(cookie, nonce1 || nonce2 || node-id)
  (define (auth-hmac cookie nonce1 nonce2 node-id)
    (let* ([id-bv (string->utf8 node-id)]
           [data (make-bytevector (+ NONCE_SIZE NONCE_SIZE (bytevector-length id-bv)))])
      (bytevector-copy! nonce1 0 data 0 NONCE_SIZE)
      (bytevector-copy! nonce2 0 data NONCE_SIZE NONCE_SIZE)
      (bytevector-copy! id-bv 0 data (* 2 NONCE_SIZE) (bytevector-length id-bv))
      (native-hmac-sha256 (string->utf8 cookie) data)))

  ;; -------- 7D: Connection pool --------

  ;; *connections*: node-id → #(fd write-mutex)
  (define *connections* (make-hashtable string-hash string=?))
  (define *conn-mutex*  (make-mutex))

  ;; Get or open a connection to node-id.
  (define (get-connection! node-id)
    (with-mutex *conn-mutex*
      (or (hashtable-ref *connections* node-id #f)
          (let ([conn (open-connection! node-id)])
            (hashtable-set! *connections* node-id conn)
            conn))))

  ;; Remove a connection from the pool (forces reconnect on next use).
  (define (drop-connection! node-id)
    (with-mutex *conn-mutex*
      (let ([conn (hashtable-ref *connections* node-id #f)])
        (when conn
          (guard (exn [#t (void)])
            (tcp-close (vector-ref conn 0))))
        (hashtable-delete! *connections* node-id))))

  ;; Open a new TCP connection and complete HMAC-SHA256 challenge-response.
  ;; Returns #(fd write-mutex).
  (define (open-connection! node-id)
    (let-values ([(host port) (node-id->host+port node-id)])
      (let ([fd           (tcp-connect host port)]
            [write-mutex  (make-mutex)]
            [client-nonce (random-bytes NONCE_SIZE)])
        ;; Step 1: Send hello with our nonce
        (with-mutex write-mutex
          (write-framed-message fd (list 'hello (current-node-id) client-nonce)))
        ;; Step 2: Receive server challenge nonce
        (let ([resp (read-framed-message fd)])
          (unless (and (pair? resp) (eq? (car resp) 'challenge)
                       (pair? (cdr resp)) (bytevector? (cadr resp))
                       (= (bytevector-length (cadr resp)) NONCE_SIZE))
            (tcp-close fd)
            (error 'open-connection! "bad challenge from server" node-id))
          (let ([server-nonce (cadr resp)])
            ;; Step 3: Send our auth proof
            (let ([proof (auth-hmac (*node-cookie*) client-nonce server-nonce node-id)])
              (with-mutex write-mutex
                (write-framed-message fd (list 'auth proof)))
              ;; Step 4: Verify server's mutual auth proof
              (let ([auth-resp (read-framed-message fd)])
                (unless (and (pair? auth-resp) (eq? (car auth-resp) 'ok)
                             (pair? (cdr auth-resp)) (bytevector? (cadr auth-resp)))
                  (tcp-close fd)
                  (error 'open-connection! "handshake rejected" node-id))
                (let ([server-proof (cadr auth-resp)]
                      [expected (auth-hmac (*node-cookie*) server-nonce client-nonce
                                           (current-node-id))])
                  (unless (native-crypto-memcmp server-proof expected)
                    (tcp-close fd)
                    (error 'open-connection! "server auth failed — possible MITM" node-id))
                  (vector fd write-mutex))))))))))

  ;; -------- 7E: Remote send --------

  ;; Send msg to a remote actor. Called via set-remote-send-handler!.
  (define (transport-remote-send! actor msg)
    (let ([node-id  (actor-ref-node actor)]
          [actor-id (actor-ref-id   actor)])
      (guard (exn [#t
                   (drop-connection! node-id)
                   (raise exn)])
        (let ([conn (get-connection! node-id)])
          (let ([fd           (vector-ref conn 0)]
                [write-mutex  (vector-ref conn 1)])
            (with-mutex write-mutex
              (write-framed-message fd (list 'send actor-id msg))))))))

  ;; -------- 7F: Server --------

  ;; Accept connections on listen-port and dispatch messages to local actors.
  ;; Runs in background threads — returns immediately.
  (define (start-node-server! listen-port)
    (fork-thread
      (lambda ()
        (let ([listen-fd (tcp-listen listen-port)])
          (let loop ()
            (let-values ([(client-fd _addr) (tcp-accept listen-fd)])
              (when client-fd
                (fork-thread (lambda () (handle-client! client-fd))))
              (loop)))))))

  ;; Handle one incoming connection: HMAC-SHA256 challenge-response then dispatch.
  (define (handle-client! fd)
    (guard (exn [#t
                 (guard (e [#t (void)]) (tcp-close fd))])
      (let ([hello (read-framed-message fd)])
        (if (not (and (pair? hello)
                      (eq? (car hello) 'hello)
                      (>= (length hello) 3)
                      (string? (cadr hello))
                      (bytevector? (caddr hello))
                      (= (bytevector-length (caddr hello)) NONCE_SIZE)))
          (begin
            (write-framed-message fd '(error "bad hello"))
            (tcp-close fd))
          (let* ([peer-id      (cadr  hello)]
                 [client-nonce (caddr hello)]
                 [server-nonce (random-bytes NONCE_SIZE)])
            ;; Step 2: Send challenge with our nonce
            (write-framed-message fd (list 'challenge server-nonce))
            ;; Step 3: Receive client's auth proof
            (let ([auth-msg (read-framed-message fd)])
              (if (not (and (pair? auth-msg) (eq? (car auth-msg) 'auth)
                            (pair? (cdr auth-msg)) (bytevector? (cadr auth-msg))))
                (begin
                  (write-framed-message fd '(error "bad auth"))
                  (tcp-close fd))
                (let* ([their-proof (cadr auth-msg)]
                       [expected (auth-hmac (*node-cookie*) client-nonce server-nonce peer-id)])
                  (if (not (native-crypto-memcmp their-proof expected))
                    (begin
                      (write-framed-message fd '(error "auth failed"))
                      (tcp-close fd))
                    ;; Step 4: Send our mutual auth proof
                    (let ([our-proof (auth-hmac (*node-cookie*) server-nonce client-nonce
                                                (current-node-id))])
                      (write-framed-message fd (list 'ok our-proof))
                      (let loop ()
                        (let ([msg (guard (exn [#t 'eof])
                                     (read-framed-message fd))])
                          (unless (eq? msg 'eof)
                            (dispatch-remote-message! msg)
                            (loop))))
                      (tcp-close fd))))))))))))

  ;; Dispatch an inbound message to a local actor.
  ;; Expected wire format: (send local-actor-id payload)
  (define (dispatch-remote-message! msg)
    (when (and (pair? msg)
               (eq? (car msg) 'send)
               (pair? (cdr msg))
               (pair? (cddr msg)))
      (let ([actor-id (cadr  msg)]
            [payload  (caddr msg)])
        (let ([actor (lookup-local-actor actor-id)])
          (when actor
            (send actor payload))))))

  ;; -------- 7G: Shutdown --------

  ;; Close all open connections gracefully.
  (define (transport-shutdown!)
    (with-mutex *conn-mutex*
      (let ([ids (vector->list (hashtable-keys *connections*))])
        (for-each
          (lambda (id)
            (let ([conn (hashtable-ref *connections* id #f)])
              (when conn
                (guard (exn [#t (void)])
                  (tcp-close (vector-ref conn 0)))))
            (hashtable-delete! *connections* id))
          ids))))

  ) ;; end library
