#!chezscheme
;;; (std net ssh conditions) — SSH-specific error condition types
;;;
;;; Structured error hierarchy for SSH protocol errors,
;;; built on (std error conditions).

(library (std net ssh conditions)
  (export
    ;; Base SSH condition
    &ssh-error
    make-ssh-error
    ssh-error?
    ssh-error-operation

    ;; Connection errors
    &ssh-connection-error
    make-ssh-connection-error
    ssh-connection-error?
    ssh-connection-error-host
    ssh-connection-error-port

    ;; Authentication errors
    &ssh-auth-error
    make-ssh-auth-error
    ssh-auth-error?
    ssh-auth-error-method
    ssh-auth-error-available-methods

    ;; Key exchange errors
    &ssh-kex-error
    make-ssh-kex-error
    ssh-kex-error?
    ssh-kex-error-phase

    ;; Protocol errors (unexpected messages, invalid packets)
    &ssh-protocol-error
    make-ssh-protocol-error
    ssh-protocol-error?
    ssh-protocol-error-expected
    ssh-protocol-error-received

    ;; Host key errors
    &ssh-host-key-error
    make-ssh-host-key-error
    ssh-host-key-error?
    ssh-host-key-error-reason
    ssh-host-key-error-fingerprint

    ;; Channel errors
    &ssh-channel-error
    make-ssh-channel-error
    ssh-channel-error?
    ssh-channel-error-channel-id

    ;; SFTP errors
    &ssh-sftp-error
    make-ssh-sftp-error
    ssh-sftp-error?
    ssh-sftp-error-code
    ssh-sftp-error-path

    ;; Timeout errors
    &ssh-timeout-error
    make-ssh-timeout-error
    ssh-timeout-error?
    ssh-timeout-error-seconds

    ;; Convenience raisers
    raise-ssh-error
    raise-ssh-connection-error
    raise-ssh-auth-error
    raise-ssh-kex-error
    raise-ssh-protocol-error
    raise-ssh-host-key-error
    raise-ssh-channel-error
    raise-ssh-sftp-error
    raise-ssh-timeout-error
    )

  (import (chezscheme))

  ;; ---- Base SSH condition ----
  (define-condition-type &ssh-error &serious
    make-ssh-error ssh-error?
    (operation ssh-error-operation))    ;; symbol: which operation failed

  ;; ---- Connection errors ----
  (define-condition-type &ssh-connection-error &ssh-error
    make-ssh-connection-error ssh-connection-error?
    (host ssh-connection-error-host)    ;; string
    (port ssh-connection-error-port))   ;; integer

  ;; ---- Authentication errors ----
  (define-condition-type &ssh-auth-error &ssh-error
    make-ssh-auth-error ssh-auth-error?
    (method ssh-auth-error-method)                ;; symbol: 'publickey, 'password, etc.
    (available-methods ssh-auth-error-available-methods))  ;; list of strings

  ;; ---- Key exchange errors ----
  (define-condition-type &ssh-kex-error &ssh-error
    make-ssh-kex-error ssh-kex-error?
    (phase ssh-kex-error-phase))        ;; symbol: 'negotiate, 'ecdh, 'verify, etc.

  ;; ---- Protocol errors ----
  (define-condition-type &ssh-protocol-error &ssh-error
    make-ssh-protocol-error ssh-protocol-error?
    (expected ssh-protocol-error-expected)   ;; what we expected
    (received ssh-protocol-error-received))  ;; what we got

  ;; ---- Host key errors ----
  (define-condition-type &ssh-host-key-error &ssh-error
    make-ssh-host-key-error ssh-host-key-error?
    (reason ssh-host-key-error-reason)           ;; 'rejected, 'changed, 'unsupported
    (fingerprint ssh-host-key-error-fingerprint)) ;; string or #f

  ;; ---- Channel errors ----
  (define-condition-type &ssh-channel-error &ssh-error
    make-ssh-channel-error ssh-channel-error?
    (channel-id ssh-channel-error-channel-id))   ;; integer or #f

  ;; ---- SFTP errors ----
  (define-condition-type &ssh-sftp-error &ssh-error
    make-ssh-sftp-error ssh-sftp-error?
    (code ssh-sftp-error-code)       ;; integer: SFTP status code
    (path ssh-sftp-error-path))      ;; string or #f

  ;; ---- Timeout errors ----
  (define-condition-type &ssh-timeout-error &ssh-error
    make-ssh-timeout-error ssh-timeout-error?
    (seconds ssh-timeout-error-seconds))  ;; number

  ;; ---- Convenience raisers ----

  (define (raise-ssh-error operation msg . irritants)
    (raise (condition
             (make-ssh-error operation)
             (make-message-condition msg)
             (if (null? irritants)
               (make-irritants-condition '())
               (make-irritants-condition irritants)))))

  (define (raise-ssh-connection-error operation host port msg)
    (raise (condition
             (make-ssh-connection-error operation host port)
             (make-message-condition msg))))

  (define (raise-ssh-auth-error operation method available msg)
    (raise (condition
             (make-ssh-auth-error operation method available)
             (make-message-condition msg))))

  (define (raise-ssh-kex-error operation phase msg . irritants)
    (raise (condition
             (make-ssh-kex-error operation phase)
             (make-message-condition msg)
             (if (null? irritants)
               (make-irritants-condition '())
               (make-irritants-condition irritants)))))

  (define (raise-ssh-protocol-error operation expected received msg)
    (raise (condition
             (make-ssh-protocol-error operation expected received)
             (make-message-condition msg))))

  (define (raise-ssh-host-key-error operation reason fingerprint msg)
    (raise (condition
             (make-ssh-host-key-error operation reason fingerprint)
             (make-message-condition msg))))

  (define (raise-ssh-channel-error operation channel-id msg)
    (raise (condition
             (make-ssh-channel-error operation channel-id)
             (make-message-condition msg))))

  (define (raise-ssh-sftp-error operation code path msg)
    (raise (condition
             (make-ssh-sftp-error operation code path)
             (make-message-condition msg))))

  (define (raise-ssh-timeout-error operation seconds msg)
    (raise (condition
             (make-ssh-timeout-error operation seconds)
             (make-message-condition msg))))

  ) ;; end library
