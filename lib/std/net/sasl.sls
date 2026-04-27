#!chezscheme
;;; :std/net/sasl -- SASL authentication mechanisms
;;;
;;; Implements the PLAIN mechanism (RFC 4616) with a general-purpose
;;; context/state-machine API suitable for multi-step mechanisms.

(library (std net sasl)
  (export
    sasl-plain sasl-plain-encode
    make-sasl-context sasl-step sasl-complete?)

  (import (chezscheme))

  ;; base64-encode comes from (chezscheme) core (Phase 66, Round 12).

  ;; ========== PLAIN mechanism (RFC 4616) ==========

  (define (sasl-plain-encode authzid authcid password)
    ;; Encode PLAIN credentials:  authzid \0 authcid \0 password
    ;; Returns a base64-encoded string.
    (let* ([az-bv (string->utf8 (if authzid authzid ""))]
           [ac-bv (string->utf8 authcid)]
           [pw-bv (string->utf8 password)]
           [total (+ (bytevector-length az-bv) 1
                     (bytevector-length ac-bv) 1
                     (bytevector-length pw-bv))]
           [buf (make-bytevector total 0)])
      ;; authzid
      (bytevector-copy! az-bv 0 buf 0 (bytevector-length az-bv))
      (let ([pos (bytevector-length az-bv)])
        ;; NUL separator already 0
        (let ([pos (+ pos 1)])
          ;; authcid
          (bytevector-copy! ac-bv 0 buf pos (bytevector-length ac-bv))
          (let ([pos (+ pos (bytevector-length ac-bv))])
            ;; NUL separator already 0
            (let ([pos (+ pos 1)])
              ;; password
              (bytevector-copy! pw-bv 0 buf pos (bytevector-length pw-bv))))))
      (base64-encode buf)))

  (define (sasl-plain authcid password)
    ;; Convenience: encode PLAIN with empty authzid.
    (sasl-plain-encode "" authcid password))

  ;; ========== General SASL context (state machine) ==========
  ;;
  ;; Supports multi-step authentication mechanisms.  Each mechanism is
  ;; a procedure that takes (context server-challenge) and returns
  ;; (values response-bytes done?).

  ;; Internal record type (different name to avoid constructor clash)
  (define-record-type sasl-ctx
    (fields
      (immutable mechanism)     ;; symbol: PLAIN, etc.
      (immutable step-proc)     ;; (context challenge) -> (values response done?)
      (mutable state)           ;; mechanism-specific state
      (mutable done))           ;; #t when auth is finished
    (sealed #t))

  ;; Public API
  (define (sasl-complete? ctx)
    (sasl-ctx-done ctx))

  (define (make-sasl-context mechanism . args)
    (case mechanism
      [(PLAIN plain)
       ;; args: authcid password [authzid]
       (unless (>= (length args) 2)
         (error 'make-sasl-context
                "PLAIN requires authcid and password"))
       (let* ([authcid  (car args)]
              [password (cadr args)]
              [authzid  (if (>= (length args) 3) (caddr args) "")]
              [encoded  (sasl-plain-encode authzid authcid password)])
         (make-sasl-ctx
           'PLAIN
           (make-plain-step-proc encoded)
           'initial
           #f))]
      [else
       (error 'make-sasl-context "unsupported mechanism" mechanism)]))

  (define (make-plain-step-proc encoded)
    ;; PLAIN is a single-step mechanism: send the encoded credentials
    ;; on the first call, then mark complete.
    (lambda (ctx challenge)
      (case (sasl-ctx-state ctx)
        [(initial)
         (sasl-ctx-state-set! ctx 'sent)
         (sasl-ctx-done-set! ctx #t)
         (values (string->utf8 encoded) #t)]
        [(sent)
         (error 'sasl-step "PLAIN mechanism already complete")]
        [else
         (error 'sasl-step "invalid state" (sasl-ctx-state ctx))])))

  (define (sasl-step ctx challenge)
    ;; Advance the authentication state machine.
    ;; CHALLENGE is a bytevector from the server (or #f for initial step).
    ;; Returns (values response-bytevector done?).
    ((sasl-ctx-step-proc ctx) ctx challenge))

  ) ;; end library
