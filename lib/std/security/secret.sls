#!chezscheme
;;; (std security secret) — Lifetime-scoped secrets
;;;
;;; Combines affine types with automatic memory wiping for cryptographic material.
;;; Secrets are automatically zeroed when they leave scope, even on exception.
;;;
;;; (with-secret ([key (derive-key password salt)])
;;;   (encrypt key plaintext))
;;; ;; key is zeroed here

(library (std security secret)
  (export
    make-secret
    secret?
    secret-use
    secret-peek
    secret-consumed?
    with-secret
    wipe-bytevector!)

  (import (chezscheme))

  ;; ========== Memory Wiping ==========

  (define (wipe-bytevector! bv)
    ;; Zero out a bytevector's contents.
    (when (bytevector? bv)
      (let ([n (bytevector-length bv)])
        (do ([i 0 (+ i 1)])
            ((= i n))
          (bytevector-u8-set! bv i 0)))))

  ;; ========== Secret Record ==========

  (define-record-type (secret %make-secret secret?)
    (sealed #t)
    (opaque #t)
    (nongenerative std-security-secret)
    (fields
      (immutable value %secret-value)       ;; the secret bytevector
      (mutable consumed? secret-consumed? %secret-set-consumed!)))

  (define (make-secret bv)
    ;; Wrap a bytevector as a secret. The bytevector will be zeroed on consume.
    (unless (bytevector? bv)
      (error 'make-secret "secret must be a bytevector" bv))
    (%make-secret bv #f))

  (define (secret-use s)
    ;; Consume the secret — returns the value and marks as consumed.
    ;; After consumption, the original bytevector is wiped.
    (unless (secret? s)
      (error 'secret-use "not a secret"))
    (when (secret-consumed? s)
      (error 'secret-use "secret already consumed — use-after-wipe"))
    (%secret-set-consumed! s #t)
    (let* ([val (%secret-value s)]
           ;; Make a copy for the caller — original will be wiped
           [copy (let ([bv (make-bytevector (bytevector-length val))])
                   (bytevector-copy! val 0 bv 0 (bytevector-length val))
                   bv)])
      (wipe-bytevector! val)
      copy))

  (define (secret-peek s)
    ;; Read the secret without consuming it. Use with care — the value
    ;; is still valid after peek but will be wiped when the secret scope exits.
    (unless (secret? s)
      (error 'secret-peek "not a secret"))
    (when (secret-consumed? s)
      (error 'secret-peek "secret already consumed"))
    (%secret-value s))

  ;; ========== Scoped Secret ==========

  (define-syntax with-secret
    ;; (with-secret ([name expr] ...) body ...)
    ;; Each expr must produce a bytevector which is wrapped as a secret.
    ;; On scope exit (normal or exception), all secrets are wiped.
    (syntax-rules ()
      [(_ ([name expr]) body ...)
       (let ([bv expr])
         (unless (bytevector? bv)
           (error 'with-secret "expression must produce a bytevector"))
         (let ([name (make-secret bv)])
           (dynamic-wind
             (lambda () (void))
             (lambda () body ...)
             (lambda ()
               (unless (secret-consumed? name)
                 (%secret-set-consumed! name #t)
                 (wipe-bytevector! (%secret-value name)))))))]
      [(_ ([name1 expr1] [name2 expr2] rest ...) body ...)
       (with-secret ([name1 expr1])
         (with-secret ([name2 expr2] rest ...)
           body ...))]))

  ) ;; end library
