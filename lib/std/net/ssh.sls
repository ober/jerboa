#!chezscheme
;;; (std net ssh) — SSH client for Jerboa
;;;
;;; Convenience re-export of the SSH client API.
;;; For low-level access, import individual modules:
;;;   (std net ssh wire)       — wire format primitives
;;;   (std net ssh transport)  — transport layer
;;;   (std net ssh kex)        — key exchange
;;;   (std net ssh auth)       — authentication
;;;   (std net ssh channel)    — channel multiplexing
;;;   (std net ssh session)    — exec/shell/pty
;;;   (std net ssh sftp)       — SFTP file operations
;;;   (std net ssh known-hosts) — host key verification
;;;   (std net ssh forward)    — port forwarding
;;;   (std net ssh client)     — high-level client API
;;;   (std net ssh conditions) — SSH error condition hierarchy

(library (std net ssh)
  (export
    ;; Connection
    ssh-connect
    ssh-disconnect
    ssh-connection?
    ssh-connection-transport
    ssh-connection-channel-table
    ssh-connection-state

    ;; Command execution
    ssh-run
    ssh-capture

    ;; Interactive
    ssh-exec
    ssh-shell

    ;; SFTP
    ssh-sftp
    ssh-sftp-close
    ssh-scp-get
    ssh-scp-put
    ssh-sftp-open
    ssh-sftp-close-handle
    ssh-sftp-read
    ssh-sftp-write
    ssh-sftp-stat
    ssh-sftp-fstat
    ssh-sftp-setstat
    ssh-sftp-remove
    ssh-sftp-rename
    ssh-sftp-mkdir
    ssh-sftp-rmdir
    ssh-sftp-list-directory
    ssh-sftp-realpath
    ssh-sftp-get
    ssh-sftp-put
    make-sftp-attrs
    sftp-attrs?
    sftp-attrs-size
    sftp-attrs-uid
    sftp-attrs-gid
    sftp-attrs-permissions
    sftp-attrs-atime
    sftp-attrs-mtime
    SSH_FXF_READ
    SSH_FXF_WRITE
    SSH_FXF_APPEND
    SSH_FXF_CREAT
    SSH_FXF_TRUNC
    SSH_FXF_EXCL

    ;; Port forwarding
    ssh-forward-local
    ssh-forward-remote
    ssh-forward-local-stop
    forward-listener?
    forward-listener-local-port
    forward-listener-remote-host
    forward-listener-remote-port

    ;; Host key verification
    ssh-known-hosts-verify
    ssh-known-hosts-add
    ssh-known-hosts-verifier
    ssh-host-key-fingerprint

    ;; Custodian integration
    with-ssh-connection
    ssh-connection-custodian

    ;; Connection pooling
    make-ssh-pool
    with-pooled-ssh
    ssh-pool-drain
    ssh-pool-stats

    ;; Error conditions (re-exported for callers to catch)
    &ssh-error ssh-error? ssh-error-operation
    &ssh-connection-error ssh-connection-error?
    &ssh-auth-error ssh-auth-error?
    &ssh-kex-error ssh-kex-error?
    &ssh-protocol-error ssh-protocol-error?
    &ssh-host-key-error ssh-host-key-error?
    &ssh-channel-error ssh-channel-error?
    &ssh-sftp-error ssh-sftp-error?
    &ssh-timeout-error ssh-timeout-error?

    ;; Channel events (for composable async patterns)
    ssh-channel-data-event
    ssh-channel-stderr-event
    )

  (import (std net ssh client)
          (std net ssh sftp)
          (std net ssh forward)
          (std net ssh known-hosts)
          (std net ssh conditions)
          (std net ssh channel))

  ) ;; end library
