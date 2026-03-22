#!chezscheme
;;; (std net ssh forward) — SSH port forwarding (RFC 4254 §7)
;;;
;;; Local (-L) and remote (-R) port forwarding.
;;; Uses (chez-ssh crypto) for TCP listen/accept/read/write/close.

(library (std net ssh forward)
  (export
    ;; Forward listener record
    make-forward-listener
    forward-listener?
    forward-listener-local-port
    forward-listener-remote-host
    forward-listener-remote-port

    ;; Local forwarding
    ssh-forward-local-start
    ssh-forward-local-stop

    ;; Remote forwarding
    ssh-forward-remote-request
    ssh-forward-remote-cancel
    )

  (import (chezscheme)
          (std net ssh wire)
          (std net ssh transport)
          (std net ssh channel)
          (chez-ssh crypto))

  ;; ---- Forward listener record ----

  (define-record-type forward-listener
    (fields
      local-port
      remote-host
      remote-port
      listen-fd
      (mutable thread)
      (mutable running?))
    (protocol
      (lambda (new)
        (lambda (local-port remote-host remote-port listen-fd)
          (new local-port remote-host remote-port listen-fd #f #t)))))

  ;; ---- Local forwarding ----

  (define (ssh-forward-local-start ts table bind-addr local-port remote-host remote-port)
    (let ([listen-fd (ssh-crypto-tcp-listen (or bind-addr "127.0.0.1") local-port)])
      (when (< listen-fd 0)
        (error 'ssh-forward-local-start "failed to listen" bind-addr local-port))
      (let ([listener (make-forward-listener local-port remote-host remote-port listen-fd)])
        (forward-listener-thread-set! listener
          (fork-thread
            (lambda ()
              (local-forward-accept-loop ts table listener))))
        listener)))

  (define (local-forward-accept-loop ts table listener)
    (let loop ()
      (when (forward-listener-running? listener)
        (let ([client-fd (ssh-crypto-tcp-accept (forward-listener-listen-fd listener))])
          (when (>= client-fd 0)
            (guard (e [#t (ssh-crypto-tcp-close client-fd)])
              (let ([ch (ssh-channel-open-direct-tcpip ts table
                          (forward-listener-remote-host listener)
                          (forward-listener-remote-port listener)
                          "127.0.0.1" 0)])
                (fork-thread
                  (lambda ()
                    (forward-relay ts table ch client-fd))))))
          (loop)))))

  (define (forward-relay ts table ch client-fd)
    (let ([ch->fd-thread
           (fork-thread
             (lambda ()
               (let loop ()
                 (let ([data (ssh-channel-read ts table ch)])
                   (when data
                     (let ([rc (ssh-crypto-tcp-write client-fd data (bytevector-length data))])
                       (when (> rc 0) (loop))))))))])

      (let loop ()
        (let* ([buf (make-bytevector 32768)]
               [n (ssh-crypto-tcp-read client-fd buf 32768)])
          (when (> n 0)
            (let ([data (make-bytevector n)])
              (bytevector-copy! buf 0 data 0 n)
              (ssh-channel-send-data ts ch data)
              (loop)))))

      (ssh-channel-send-eof ts ch)
      (ssh-channel-close ts ch)
      (ssh-crypto-tcp-close client-fd)))

  (define (ssh-forward-local-stop listener)
    (forward-listener-running?-set! listener #f)
    (ssh-crypto-tcp-close (forward-listener-listen-fd listener)))

  ;; ---- Remote forwarding ----

  (define (ssh-forward-remote-request ts bind-addr remote-port)
    (ssh-transport-send-packet ts
      (ssh-make-payload SSH_MSG_GLOBAL_REQUEST
        (ssh-write-string "tcpip-forward")
        (ssh-write-boolean #t)
        (ssh-write-string (or bind-addr ""))
        (ssh-write-uint32 remote-port)))
    (let ([reply (ssh-transport-recv-packet ts)])
      (case (bytevector-u8-ref reply 0)
        [(81)  ;; SSH_MSG_REQUEST_SUCCESS
         (if (= remote-port 0)
           (let ([r (ssh-read-uint32 reply 1)])
             (car r))
           remote-port)]
        [(82)  ;; SSH_MSG_REQUEST_FAILURE
         (error 'ssh-forward-remote-request "server rejected forwarding request")]
        [else
         (error 'ssh-forward-remote-request "unexpected response"
                (bytevector-u8-ref reply 0))])))

  (define (ssh-forward-remote-cancel ts bind-addr remote-port)
    (ssh-transport-send-packet ts
      (ssh-make-payload SSH_MSG_GLOBAL_REQUEST
        (ssh-write-string "cancel-tcpip-forward")
        (ssh-write-boolean #t)
        (ssh-write-string (or bind-addr ""))
        (ssh-write-uint32 remote-port)))
    (let ([reply (ssh-transport-recv-packet ts)])
      (unless (= (bytevector-u8-ref reply 0) 81)
        (error 'ssh-forward-remote-cancel "cancel failed"))))

  ) ;; end library
