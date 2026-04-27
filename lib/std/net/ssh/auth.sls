#!chezscheme
;;; (std net ssh auth) — SSH user authentication (RFC 4252)
;;;
;;; Supports: publickey (ed25519), password, keyboard-interactive
;;;
;;; FFI operations imported from (chez-ssh crypto).
;;; Uses (std net ssh conditions) for structured error hierarchy.

(library (std net ssh auth)
  (export
    ssh-auth-publickey      ;; (ts username seed-bv) → #t or error
    ssh-auth-password       ;; (ts username password) → #t or error
    ssh-auth-interactive    ;; (ts username response-callback) → #t or error
    ssh-userauth-request    ;; request ssh-userauth service
    )

  (import (chezscheme)
          (std net ssh wire)
          (std net ssh transport)
          (std net ssh conditions)
          (chez-ssh crypto))

  ;; bytevector-append is in (chezscheme) core — no shim needed.

  ;; ---- Service request ----

  (define (ssh-userauth-request ts)
    (ssh-transport-send-packet ts
      (ssh-make-payload SSH_MSG_SERVICE_REQUEST
        (ssh-write-string "ssh-userauth")))
    (let ([reply (ssh-transport-recv-packet ts)])
      (unless (= (bytevector-u8-ref reply 0) SSH_MSG_SERVICE_ACCEPT)
        (raise-ssh-auth-error 'ssh-userauth-request 'none '()
          "ssh-userauth service request denied"))
      #t))

  ;; ---- Public key authentication ----

  (define (ssh-auth-publickey ts username seed-bv)
    (let ([pubkey (make-bytevector 32)])
      (ssh-crypto-ed25519-derive-pubkey seed-bv pubkey)

      (let* ([key-type "ssh-ed25519"]
             [pubkey-blob (bytevector-append
                            (ssh-write-string key-type)
                            (ssh-write-string pubkey))]
             [session-id (transport-state-session-id ts)])

        (let* ([sig-data (bytevector-append
                           (ssh-write-string session-id)
                           (ssh-write-byte SSH_MSG_USERAUTH_REQUEST)
                           (ssh-write-string username)
                           (ssh-write-string "ssh-connection")
                           (ssh-write-string "publickey")
                           (ssh-write-boolean #t)
                           (ssh-write-string key-type)
                           (ssh-write-string pubkey-blob))]
               [sig (make-bytevector 64)]
               [rc (ssh-crypto-ed25519-sign seed-bv sig-data (bytevector-length sig-data) sig)])
          (when (< rc 0)
            (raise-ssh-auth-error 'ssh-auth-publickey 'publickey '()
              "Ed25519 signing failed"))

          (let ([sig-blob (bytevector-append
                            (ssh-write-string key-type)
                            (ssh-write-string sig))])

            (ssh-transport-send-packet ts
              (ssh-make-payload SSH_MSG_USERAUTH_REQUEST
                (ssh-write-string username)
                (ssh-write-string "ssh-connection")
                (ssh-write-string "publickey")
                (ssh-write-boolean #t)
                (ssh-write-string key-type)
                (ssh-write-string pubkey-blob)
                (ssh-write-string sig-blob)))

            (handle-auth-response ts 'publickey))))))

  ;; ---- Password authentication ----

  (define (ssh-auth-password ts username password)
    (ssh-transport-send-packet ts
      (ssh-make-payload SSH_MSG_USERAUTH_REQUEST
        (ssh-write-string username)
        (ssh-write-string "ssh-connection")
        (ssh-write-string "password")
        (ssh-write-boolean #f)
        (ssh-write-string password)))
    (handle-auth-response ts 'password))

  ;; ---- Keyboard-interactive authentication ----

  (define (ssh-auth-interactive ts username response-callback)
    (ssh-transport-send-packet ts
      (ssh-make-payload SSH_MSG_USERAUTH_REQUEST
        (ssh-write-string username)
        (ssh-write-string "ssh-connection")
        (ssh-write-string "keyboard-interactive")
        (ssh-write-string "")
        (ssh-write-string "")))

    (let loop ()
      (let ([reply (ssh-transport-recv-packet ts)])
        (case (bytevector-u8-ref reply 0)
          [(52) #t]  ;; SSH_MSG_USERAUTH_SUCCESS
          [(51)      ;; SSH_MSG_USERAUTH_FAILURE
           (raise-ssh-auth-error 'ssh-auth-interactive 'keyboard-interactive '()
             "keyboard-interactive authentication failed")]
          [(60)      ;; SSH_MSG_USERAUTH_INFO_REQUEST
           (let* ([off 1]
                  [r1 (ssh-read-string reply off)]
                  [name (utf8->string (car r1))] [off (cdr r1)]
                  [r2 (ssh-read-string reply off)]
                  [instruction (utf8->string (car r2))] [off (cdr r2)]
                  [r3 (ssh-read-string reply off)]
                  [_lang (car r3)] [off (cdr r3)]
                  [r4 (ssh-read-uint32 reply off)]
                  [num-prompts (car r4)] [off (cdr r4)])
             (let prompt-loop ([i 0] [off off] [prompts '()])
               (if (>= i num-prompts)
                 (let* ([prompts (reverse prompts)]
                        [responses (response-callback name instruction prompts)])
                   (let ([parts (map (lambda (r) (ssh-write-string r)) responses)])
                     (ssh-transport-send-packet ts
                       (apply ssh-make-payload SSH_MSG_USERAUTH_INFO_RESPONSE
                         (ssh-write-uint32 num-prompts)
                         parts)))
                   (loop))
                 (let* ([r (ssh-read-string reply off)]
                        [prompt-text (utf8->string (car r))] [off (cdr r)]
                        [r2 (ssh-read-boolean reply off)]
                        [echo? (car r2)] [off (cdr r2)])
                   (prompt-loop (+ i 1) off
                     (cons (cons prompt-text echo?) prompts))))))]
          [else
           (raise-ssh-protocol-error 'ssh-auth-interactive
             "userauth response" (bytevector-u8-ref reply 0)
             "unexpected message during keyboard-interactive auth")]))))

  ;; ---- Response handler ----

  (define (handle-auth-response ts method)
    (let ([reply (ssh-transport-recv-packet ts)])
      (case (bytevector-u8-ref reply 0)
        [(52) #t]    ;; SSH_MSG_USERAUTH_SUCCESS
        [(51)        ;; SSH_MSG_USERAUTH_FAILURE
         (let* ([off 1]
                [r (ssh-read-name-list reply off)]
                [methods (car r)])
           (raise-ssh-auth-error 'ssh-auth method methods
             (string-append (symbol->string method) " authentication failed")))]
        [else
         (raise-ssh-protocol-error 'ssh-auth
           "success or failure" (bytevector-u8-ref reply 0)
           "unexpected auth response")])))

  ) ;; end library
