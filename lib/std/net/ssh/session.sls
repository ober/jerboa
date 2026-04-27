#!chezscheme
;;; (std net ssh session) — SSH session channels (RFC 4254 §6)
;;;
;;; Exec, shell/PTY, and subsystem requests on session channels.
;;; Pure protocol logic — no FFI.

(library (std net ssh session)
  (export
    ssh-session-exec           ;; (ts table command) → channel
    ssh-session-shell          ;; (ts table) → channel
    ssh-session-request-pty    ;; (ts table channel #:term #:cols #:rows) → void
    ssh-session-subsystem      ;; (ts table channel subsystem-name) → void
    ssh-session-exec-simple    ;; (ts table command) → (exit-status . output-string)
    )

  (import (chezscheme)
          (std net ssh wire)
          (std net ssh transport)
          (std net ssh channel)
          (std net ssh conditions))

  ;; bytevector-append is in (chezscheme) core — no shim needed.

  ;; ---- Exec ----

  (define (ssh-session-exec ts table command)
    (let ([ch (ssh-channel-open-session ts table)])
      (ssh-transport-send-packet ts
        (ssh-make-payload SSH_MSG_CHANNEL_REQUEST
          (ssh-write-uint32 (ssh-channel-remote-id ch))
          (ssh-write-string "exec")
          (ssh-write-boolean #t)
          (ssh-write-string command)))
      (ssh-channel-dispatch-until ts table
        (lambda () #t))
      ch))

  ;; ---- Shell ----

  (define (ssh-session-shell ts table)
    (let ([ch (ssh-channel-open-session ts table)])
      (ssh-session-request-pty ts table ch)
      (ssh-transport-send-packet ts
        (ssh-make-payload SSH_MSG_CHANNEL_REQUEST
          (ssh-write-uint32 (ssh-channel-remote-id ch))
          (ssh-write-string "shell")
          (ssh-write-boolean #t)))
      ch))

  ;; ---- PTY request ----

  (define ssh-session-request-pty
    (case-lambda
      [(ts table ch) (ssh-session-request-pty ts table ch "xterm" 80 24)]
      [(ts table ch term cols rows)
       (let ([modes (make-bytevector 1 0)])
         (ssh-transport-send-packet ts
           (ssh-make-payload SSH_MSG_CHANNEL_REQUEST
             (ssh-write-uint32 (ssh-channel-remote-id ch))
             (ssh-write-string "pty-req")
             (ssh-write-boolean #t)
             (ssh-write-string term)
             (ssh-write-uint32 cols)
             (ssh-write-uint32 rows)
             (ssh-write-uint32 0)
             (ssh-write-uint32 0)
             (ssh-write-string modes))))]))

  ;; ---- Subsystem ----

  (define (ssh-session-subsystem ts table ch subsystem-name)
    (ssh-transport-send-packet ts
      (ssh-make-payload SSH_MSG_CHANNEL_REQUEST
        (ssh-write-uint32 (ssh-channel-remote-id ch))
        (ssh-write-string "subsystem")
        (ssh-write-boolean #t)
        (ssh-write-string subsystem-name))))

  ;; ---- Simple exec (convenience) ----

  (define (ssh-session-exec-simple ts table command)
    (let ([ch (ssh-session-exec ts table command)])
      (let loop ([chunks '()])
        (let ([data (ssh-channel-read ts table ch)])
          (if data
            (loop (cons data chunks))
            (begin
              (let drain ()
                (unless (ssh-channel-closed? ch)
                  (ssh-channel-dispatch ts table)
                  (drain)))
              (ssh-channel-close ts ch)
              (let* ([all-data (apply bytevector-append (reverse chunks))]
                     [output (utf8->string all-data)]
                     [status (or (ssh-channel-exit-status ch) -1)])
                (cons status output))))))))

  ) ;; end library
