#!chezscheme
;;; (std net ssh channel) — SSH channel multiplexing (RFC 4254)
;;;
;;; Channel open/close, data transfer, window management,
;;; and packet dispatch loop.
;;; Pure protocol logic — no FFI.
;;;
;;; Uses (std net ssh conditions) for structured error hierarchy.
;;; Uses (std misc event) for composable channel data events.

(library (std net ssh channel)
  (export
    ;; Channel record
    make-ssh-channel
    ssh-channel?
    ssh-channel-local-id
    ssh-channel-remote-id
    ssh-channel-remote-id-set!
    ssh-channel-local-window
    ssh-channel-local-window-set!
    ssh-channel-remote-window
    ssh-channel-remote-window-set!
    ssh-channel-remote-max-packet
    ssh-channel-remote-max-packet-set!
    ssh-channel-data-queue
    ssh-channel-data-queue-set!
    ssh-channel-stderr-queue
    ssh-channel-stderr-queue-set!
    ssh-channel-eof?
    ssh-channel-eof?-set!
    ssh-channel-closed?
    ssh-channel-closed?-set!
    ssh-channel-exit-status
    ssh-channel-exit-status-set!
    ssh-channel-exit-signal
    ssh-channel-exit-signal-set!

    ;; Channel table (transport-level)
    make-channel-table
    channel-table-get
    channel-table-put!
    channel-table-remove!
    channel-table-next-id
    channel-table-alloc-id

    ;; Channel operations
    ssh-channel-open-session
    ssh-channel-open-direct-tcpip
    ssh-channel-send-data
    ssh-channel-send-eof
    ssh-channel-close
    ssh-channel-read
    ssh-channel-read-stderr

    ;; Dispatch
    ssh-channel-dispatch
    ssh-channel-dispatch-until

    ;; Event integration — composable channel data events
    ssh-channel-data-event
    ssh-channel-stderr-event
    )

  (import (chezscheme)
          (std net ssh wire)
          (std net ssh transport)
          (std net ssh conditions)
          (std misc event))

  ;; ---- Constants ----
  (define INITIAL-WINDOW-SIZE (* 2 1024 1024))   ;; 2 MB
  (define MAX-PACKET-SIZE 32768)                  ;; 32 KB

  ;; ---- Channel record ----

  (define-record-type ssh-channel
    (fields
      local-id
      (mutable remote-id)
      (mutable local-window)
      (mutable remote-window)
      (mutable remote-max-packet)
      (mutable data-queue)
      (mutable stderr-queue)
      (mutable eof?)
      (mutable closed?)
      (mutable exit-status)
      (mutable exit-signal))
    (protocol
      (lambda (new)
        (lambda (local-id)
          (new local-id #f INITIAL-WINDOW-SIZE 0 0 '() '() #f #f #f #f)))))

  ;; ---- Channel table ----

  (define-record-type channel-table
    (fields
      (mutable channels)
      (mutable next-id))
    (protocol
      (lambda (new)
        (lambda ()
          (new '() 0)))))

  (define (channel-table-get table local-id)
    (cond
      [(assv local-id (channel-table-channels table)) => cdr]
      [else #f]))

  (define (channel-table-put! table channel)
    (channel-table-channels-set! table
      (cons (cons (ssh-channel-local-id channel) channel)
            (channel-table-channels table))))

  (define (channel-table-remove! table local-id)
    (channel-table-channels-set! table
      (remp (lambda (p) (= (car p) local-id))
            (channel-table-channels table))))

  (define (channel-table-alloc-id table)
    (let ([id (channel-table-next-id table)])
      (channel-table-next-id-set! table (+ id 1))
      id))

  ;; ---- Channel open ----

  (define (ssh-channel-open-session ts table)
    (let* ([local-id (channel-table-alloc-id table)]
           [ch (make-ssh-channel local-id)])
      (channel-table-put! table ch)
      (ssh-transport-send-packet ts
        (ssh-make-payload SSH_MSG_CHANNEL_OPEN
          (ssh-write-string "session")
          (ssh-write-uint32 local-id)
          (ssh-write-uint32 INITIAL-WINDOW-SIZE)
          (ssh-write-uint32 MAX-PACKET-SIZE)))
      (ssh-channel-dispatch-until ts table
        (lambda () (or (ssh-channel-remote-id ch) (ssh-channel-closed? ch))))
      (when (ssh-channel-closed? ch)
        (raise-ssh-channel-error 'ssh-channel-open-session local-id
          "session channel open failed"))
      ch))

  (define (ssh-channel-open-direct-tcpip ts table host port orig-host orig-port)
    (let* ([local-id (channel-table-alloc-id table)]
           [ch (make-ssh-channel local-id)])
      (channel-table-put! table ch)
      (ssh-transport-send-packet ts
        (ssh-make-payload SSH_MSG_CHANNEL_OPEN
          (ssh-write-string "direct-tcpip")
          (ssh-write-uint32 local-id)
          (ssh-write-uint32 INITIAL-WINDOW-SIZE)
          (ssh-write-uint32 MAX-PACKET-SIZE)
          (ssh-write-string host)
          (ssh-write-uint32 port)
          (ssh-write-string orig-host)
          (ssh-write-uint32 orig-port)))
      (ssh-channel-dispatch-until ts table
        (lambda () (or (ssh-channel-remote-id ch) (ssh-channel-closed? ch))))
      (when (ssh-channel-closed? ch)
        (raise-ssh-channel-error 'ssh-channel-open-direct-tcpip local-id
          "direct-tcpip channel open failed"))
      ch))

  ;; ---- Channel data ----

  (define (ssh-channel-send-data ts ch data)
    (let ([bv (if (string? data) (string->utf8 data) data)])
      (let loop ([off 0])
        (when (< off (bytevector-length bv))
          (let* ([remaining (- (bytevector-length bv) off)]
                 [send-size (min remaining
                                 (ssh-channel-remote-max-packet ch)
                                 (ssh-channel-remote-window ch))])
            (when (<= send-size 0)
              (raise-ssh-channel-error 'ssh-channel-send-data
                (ssh-channel-local-id ch)
                "remote window exhausted"))
            (let ([chunk (make-bytevector send-size)])
              (bytevector-copy! bv off chunk 0 send-size)
              (ssh-transport-send-packet ts
                (ssh-make-payload SSH_MSG_CHANNEL_DATA
                  (ssh-write-uint32 (ssh-channel-remote-id ch))
                  (ssh-write-string chunk)))
              (ssh-channel-remote-window-set! ch
                (- (ssh-channel-remote-window ch) send-size))
              (loop (+ off send-size))))))))

  (define (ssh-channel-send-eof ts ch)
    (ssh-transport-send-packet ts
      (ssh-make-payload SSH_MSG_CHANNEL_EOF
        (ssh-write-uint32 (ssh-channel-remote-id ch)))))

  (define (ssh-channel-close ts ch)
    (unless (ssh-channel-closed? ch)
      (ssh-transport-send-packet ts
        (ssh-make-payload SSH_MSG_CHANNEL_CLOSE
          (ssh-write-uint32 (ssh-channel-remote-id ch))))
      (ssh-channel-closed?-set! ch #t)))

  ;; ---- Channel read ----

  (define (ssh-channel-read ts table ch)
    (let loop ()
      (cond
        [(pair? (ssh-channel-data-queue ch))
         (let ([data (car (ssh-channel-data-queue ch))])
           (ssh-channel-data-queue-set! ch (cdr (ssh-channel-data-queue ch)))
           (let ([adjust (bytevector-length data)])
             (ssh-channel-local-window-set! ch
               (+ (ssh-channel-local-window ch) adjust))
             (ssh-transport-send-packet ts
               (ssh-make-payload SSH_MSG_CHANNEL_WINDOW_ADJUST
                 (ssh-write-uint32 (ssh-channel-remote-id ch))
                 (ssh-write-uint32 adjust))))
           data)]
        [(ssh-channel-eof? ch) #f]
        [(ssh-channel-closed? ch) #f]
        [else
         (ssh-channel-dispatch ts table)
         (loop)])))

  (define (ssh-channel-read-stderr ts table ch)
    (let loop ()
      (cond
        [(pair? (ssh-channel-stderr-queue ch))
         (let ([data (car (ssh-channel-stderr-queue ch))])
           (ssh-channel-stderr-queue-set! ch (cdr (ssh-channel-stderr-queue ch)))
           data)]
        [(ssh-channel-eof? ch) #f]
        [(ssh-channel-closed? ch) #f]
        [else
         (ssh-channel-dispatch ts table)
         (loop)])))

  ;; ---- Event integration ----
  ;; These create composable events for non-blocking channel data polling.
  ;; Use with (sync (choice (ssh-channel-data-event ch) (timer-event 5000)))
  ;; to wait for data with a timeout.
  ;;
  ;; Note: events only fire on already-buffered data. The caller must ensure
  ;; data is being pumped into the queue via ssh-channel-dispatch.

  (define (ssh-channel-data-event ch)
    (make-event
      (lambda ()
        (cond
          [(pair? (ssh-channel-data-queue ch))
           (values #t (car (ssh-channel-data-queue ch)))]
          [(or (ssh-channel-eof? ch) (ssh-channel-closed? ch))
           (values #t #f)]
          [else
           (values #f #f)]))))

  (define (ssh-channel-stderr-event ch)
    (make-event
      (lambda ()
        (cond
          [(pair? (ssh-channel-stderr-queue ch))
           (values #t (car (ssh-channel-stderr-queue ch)))]
          [(or (ssh-channel-eof? ch) (ssh-channel-closed? ch))
           (values #t #f)]
          [else
           (values #f #f)]))))

  ;; ---- Dispatch ----

  (define (find-channel-by-local-id table local-id)
    (channel-table-get table local-id))

  (define (ssh-channel-dispatch ts table)
    (let* ([pkt (ssh-transport-recv-packet ts)]
           [msg-type (bytevector-u8-ref pkt 0)])
      (case msg-type
        [(91)  ;; SSH_MSG_CHANNEL_OPEN_CONFIRMATION
         (let* ([off 1]
                [r1 (ssh-read-uint32 pkt off)]
                [local-id (car r1)] [off (cdr r1)]
                [r2 (ssh-read-uint32 pkt off)]
                [remote-id (car r2)] [off (cdr r2)]
                [r3 (ssh-read-uint32 pkt off)]
                [remote-window (car r3)] [off (cdr r3)]
                [r4 (ssh-read-uint32 pkt off)]
                [remote-max-packet (car r4)])
           (let ([ch (find-channel-by-local-id table local-id)])
             (when ch
               (ssh-channel-remote-id-set! ch remote-id)
               (ssh-channel-remote-window-set! ch remote-window)
               (ssh-channel-remote-max-packet-set! ch remote-max-packet))))]

        [(92)  ;; SSH_MSG_CHANNEL_OPEN_FAILURE
         (let* ([off 1]
                [r1 (ssh-read-uint32 pkt off)]
                [local-id (car r1)])
           (let ([ch (find-channel-by-local-id table local-id)])
             (when ch
               (ssh-channel-closed?-set! ch #t))))]

        [(93)  ;; SSH_MSG_CHANNEL_WINDOW_ADJUST
         (let* ([off 1]
                [r1 (ssh-read-uint32 pkt off)]
                [local-id (car r1)] [off (cdr r1)]
                [r2 (ssh-read-uint32 pkt off)]
                [adjust (car r2)])
           (let ([ch (find-channel-by-local-id table local-id)])
             (when ch
               (ssh-channel-remote-window-set! ch
                 (+ (ssh-channel-remote-window ch) adjust)))))]

        [(94)  ;; SSH_MSG_CHANNEL_DATA
         (let* ([off 1]
                [r1 (ssh-read-uint32 pkt off)]
                [local-id (car r1)] [off (cdr r1)]
                [r2 (ssh-read-string pkt off)]
                [data (car r2)])
           (let ([ch (find-channel-by-local-id table local-id)])
             (when ch
               (ssh-channel-data-queue-set! ch
                 (append (ssh-channel-data-queue ch) (list data)))
               (ssh-channel-local-window-set! ch
                 (- (ssh-channel-local-window ch) (bytevector-length data))))))]

        [(95)  ;; SSH_MSG_CHANNEL_EXTENDED_DATA
         (let* ([off 1]
                [r1 (ssh-read-uint32 pkt off)]
                [local-id (car r1)] [off (cdr r1)]
                [r2 (ssh-read-uint32 pkt off)]
                [data-type (car r2)] [off (cdr r2)]
                [r3 (ssh-read-string pkt off)]
                [data (car r3)])
           (let ([ch (find-channel-by-local-id table local-id)])
             (when ch
               (ssh-channel-stderr-queue-set! ch
                 (append (ssh-channel-stderr-queue ch) (list data))))))]

        [(96)  ;; SSH_MSG_CHANNEL_EOF
         (let* ([off 1]
                [r1 (ssh-read-uint32 pkt off)]
                [local-id (car r1)])
           (let ([ch (find-channel-by-local-id table local-id)])
             (when ch
               (ssh-channel-eof?-set! ch #t))))]

        [(97)  ;; SSH_MSG_CHANNEL_CLOSE
         (let* ([off 1]
                [r1 (ssh-read-uint32 pkt off)]
                [local-id (car r1)])
           (let ([ch (find-channel-by-local-id table local-id)])
             (when ch
               (ssh-channel-closed?-set! ch #t)
               (unless (ssh-channel-eof? ch)
                 (ssh-channel-eof?-set! ch #t)))))]

        [(98)  ;; SSH_MSG_CHANNEL_REQUEST
         (let* ([off 1]
                [r1 (ssh-read-uint32 pkt off)]
                [local-id (car r1)] [off (cdr r1)]
                [r2 (ssh-read-string pkt off)]
                [req-type (utf8->string (car r2))] [off (cdr r2)]
                [r3 (ssh-read-boolean pkt off)]
                [want-reply (car r3)] [off (cdr r3)])
           (let ([ch (find-channel-by-local-id table local-id)])
             (when ch
               (cond
                 [(string=? req-type "exit-status")
                  (let ([r (ssh-read-uint32 pkt off)])
                    (ssh-channel-exit-status-set! ch (car r)))]
                 [(string=? req-type "exit-signal")
                  (let* ([r (ssh-read-string pkt off)]
                         [signal-name (utf8->string (car r))])
                    (ssh-channel-exit-signal-set! ch signal-name))]
                 [else (void)])
               (when want-reply
                 (ssh-transport-send-packet ts
                   (ssh-make-payload SSH_MSG_CHANNEL_FAILURE
                     (ssh-write-uint32 (ssh-channel-remote-id ch))))))))]

        [(99)  ;; SSH_MSG_CHANNEL_SUCCESS
         (void)]

        [(100) ;; SSH_MSG_CHANNEL_FAILURE
         (void)]

        [(80)  ;; SSH_MSG_GLOBAL_REQUEST
         (let* ([off 1]
                [r1 (ssh-read-string pkt off)]
                [_req-name (car r1)] [off (cdr r1)]
                [r2 (ssh-read-boolean pkt off)]
                [want-reply (car r2)])
           (when want-reply
             (ssh-transport-send-packet ts
               (ssh-make-payload SSH_MSG_REQUEST_FAILURE))))]

        [(2)   ;; SSH_MSG_IGNORE
         (void)]

        [(4)   ;; SSH_MSG_DEBUG
         (void)]

        [(1)   ;; SSH_MSG_DISCONNECT
         (raise-ssh-error 'ssh-channel-dispatch "server sent disconnect")]

        [else
         (void)])))

  (define (ssh-channel-dispatch-until ts table pred)
    (let loop ()
      (unless (pred)
        (ssh-channel-dispatch ts table)
        (loop))))

  ) ;; end library
