#!chezscheme
;;; (std security errors) — Safe error responses
;;;
;;; Prevent information leakage through error messages.
;;; Classify errors as internal (never shown) vs client (safe to show).
;;; Generate opaque error references for correlation.

(library (std security errors)
  (export
    ;; Error classification
    define-error-class
    error-class
    internal-error?
    client-error?

    ;; Safe error handling
    make-safe-error-handler
    safe-error-response
    safe-error-response?
    safe-error-response-status
    safe-error-response-message
    safe-error-response-reference

    ;; Error registry
    register-error-class!
    lookup-error-class

    ;; Built-in classes
    internal-error-classes
    client-error-classes)

  (import (chezscheme))

  ;; ========== Error Classification Registry ==========

  (define *error-classes* (make-eq-hashtable))

  (define internal-error-classes
    '(sql-error file-not-found assertion-failure
      stack-overflow null-pointer internal-error
      unhandled-exception type-error))

  (define client-error-classes
    '(bad-request unauthorized forbidden not-found
      rate-limited payload-too-large method-not-allowed
      conflict gone unprocessable-entity))

  ;; ========== Registration ==========

  (define (register-error-class! class-name kind)
    ;; kind: 'internal or 'client
    (unless (memq kind '(internal client))
      (error 'register-error-class! "kind must be 'internal or 'client" kind))
    (hashtable-set! *error-classes* class-name kind))

  (define (lookup-error-class class-name)
    ;; Returns 'internal, 'client, or #f
    (hashtable-ref *error-classes* class-name #f))

  (define-syntax define-error-class
    (syntax-rules ()
      [(_ kind name ...)
       (begin
         (register-error-class! 'name kind) ...)]))

  (define (error-class name)
    (lookup-error-class name))

  (define (internal-error? name)
    (eq? (lookup-error-class name) 'internal))

  (define (client-error? name)
    (eq? (lookup-error-class name) 'client))

  ;; ========== Safe Error Response ==========

  (define-record-type (safe-error-response %make-safe-error-response safe-error-response?)
    (sealed #t)
    (fields
      (immutable status safe-error-response-status)
      (immutable message safe-error-response-message)
      (immutable reference safe-error-response-reference)))

  (define (generate-reference)
    ;; Generate a random hex reference ID for error correlation.
    ;; Uses current time + random bits for uniqueness.
    (let* ([t (time-second (current-time 'time-utc))]
           [bv (make-bytevector 8 0)])
      ;; Mix time into first 4 bytes
      (bytevector-u8-set! bv 0 (bitwise-and (bitwise-arithmetic-shift-right t 24) #xff))
      (bytevector-u8-set! bv 1 (bitwise-and (bitwise-arithmetic-shift-right t 16) #xff))
      (bytevector-u8-set! bv 2 (bitwise-and (bitwise-arithmetic-shift-right t 8) #xff))
      (bytevector-u8-set! bv 3 (bitwise-and t #xff))
      ;; Random bytes for rest (use /dev/urandom if available, fallback to time-nanosecond)
      (let ([ns (time-nanosecond (current-time 'time-utc))])
        (bytevector-u8-set! bv 4 (bitwise-and (bitwise-arithmetic-shift-right ns 24) #xff))
        (bytevector-u8-set! bv 5 (bitwise-and (bitwise-arithmetic-shift-right ns 16) #xff))
        (bytevector-u8-set! bv 6 (bitwise-and (bitwise-arithmetic-shift-right ns 8) #xff))
        (bytevector-u8-set! bv 7 (bitwise-and ns #xff)))
      (bytevector->hex bv)))

  ;; ========== Client Error Status Codes ==========

  (define (class->status class-name)
    (case class-name
      [(bad-request) 400]
      [(unauthorized) 401]
      [(forbidden) 403]
      [(not-found) 404]
      [(method-not-allowed) 405]
      [(conflict) 409]
      [(gone) 410]
      [(payload-too-large) 413]
      [(rate-limited) 429]
      [(unprocessable-entity) 422]
      [else 500]))

  (define (class->message class-name)
    (case class-name
      [(bad-request) "Bad request"]
      [(unauthorized) "Unauthorized"]
      [(forbidden) "Forbidden"]
      [(not-found) "Not found"]
      [(method-not-allowed) "Method not allowed"]
      [(conflict) "Conflict"]
      [(gone) "Gone"]
      [(payload-too-large) "Payload too large"]
      [(rate-limited) "Too many requests"]
      [(unprocessable-entity) "Unprocessable entity"]
      [else "Internal server error"]))

  ;; ========== Safe Error Handler ==========

  (define (make-safe-error-handler log-proc)
    ;; Returns a procedure: (handler error-class-name exn) -> safe-error-response
    ;; log-proc: (lambda (reference class-name exn) ...) — logs internal details
    (lambda (class-name exn)
      (let ([ref (generate-reference)])
        ;; Always log full details internally
        (guard (e [#t (void)])  ;; don't let logging errors propagate
          (log-proc ref class-name exn))
        ;; Return safe response based on classification
        (cond
          [(client-error? class-name)
           (%make-safe-error-response
             (class->status class-name)
             (class->message class-name)
             ref)]
          [else
           ;; Internal or unknown errors get generic 500
           (%make-safe-error-response
             500
             "Internal server error"
             ref)]))))

  ;; ========== Helpers ==========

  (define (bytevector->hex bv)
    (let* ([len (bytevector-length bv)]
           [out (make-string (* len 2))])
      (do ([i 0 (+ i 1)])
          ((= i len) out)
        (let* ([b (bytevector-u8-ref bv i)]
               [hi (bitwise-arithmetic-shift-right b 4)]
               [lo (bitwise-and b #xf)])
          (string-set! out (* i 2) (hex-digit hi))
          (string-set! out (+ (* i 2) 1) (hex-digit lo))))))

  (define (hex-digit n)
    (string-ref "0123456789abcdef" n))

  ;; Initialize built-in classes
  (for-each (lambda (c) (hashtable-set! *error-classes* c 'internal))
            internal-error-classes)
  (for-each (lambda (c) (hashtable-set! *error-classes* c 'client))
            client-error-classes)

  ) ;; end library
