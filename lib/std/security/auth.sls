#!chezscheme
;;; (std security auth) — Authentication framework
;;;
;;; Provides token-based authentication with:
;;; - API key validation
;;; - Session tokens with expiry
;;; - Bearer token middleware pattern
;;; - Rate limiting for auth attempts

(library (std security auth)
  (export
    ;; API keys
    make-api-key-store
    api-key-store?
    api-key-register!
    api-key-validate
    api-key-revoke!

    ;; Session tokens
    make-session-store
    session-store?
    session-create!
    session-validate
    session-destroy!
    session-cleanup!

    ;; Auth middleware pattern
    make-auth-middleware
    make-auth-result
    auth-result?
    auth-result-authenticated?
    auth-result-identity
    auth-result-roles

    ;; Rate limiting
    make-rate-limiter
    rate-limit-check!)

  (import (chezscheme)
          (std crypto random)
          (std crypto compare))

  ;; ========== API Key Store ==========

  (define-record-type (api-key-store %make-api-key-store api-key-store?)
    (sealed #t)
    (fields
      (immutable keys %api-key-store-keys)     ;; hashtable: key-hash -> (identity roles)
      (immutable mutex %api-key-store-mutex)))

  (define (make-api-key-store)
    (%make-api-key-store
      (make-hashtable string-hash string=?)
      (make-mutex)))

  (define (api-key-register! store identity roles)
    ;; Register a new API key. Returns the key string.
    (let ([key (random-token 32)])  ;; 64-char hex string
      (with-mutex (%api-key-store-mutex store)
        (hashtable-set! (%api-key-store-keys store) key
          (list identity roles)))
      key))

  (define (api-key-validate store key)
    ;; Validate an API key. Returns (identity roles) or #f.
    ;; Uses timing-safe comparison.
    (with-mutex (%api-key-store-mutex store)
      (let ([keys (%api-key-store-keys store)])
        ;; Must check all keys to prevent timing leaks
        (let-values ([(ks vs) (hashtable-entries keys)])
          (let loop ([i 0] [found #f])
            (if (>= i (vector-length ks))
              found
              (let ([stored-key (vector-ref ks i)]
                    [entry (vector-ref vs i)])
                (if (timing-safe-string=? key stored-key)
                  (loop (+ i 1) entry)
                  (loop (+ i 1) found)))))))))

  (define (api-key-revoke! store key)
    (with-mutex (%api-key-store-mutex store)
      (hashtable-delete! (%api-key-store-keys store) key)))

  ;; ========== Session Store ==========

  (define-record-type (session-store make-session-store* session-store?)
    (sealed #t)
    (fields
      (immutable sessions %session-store-sessions)  ;; hashtable: token -> (identity roles expiry)
      (immutable mutex %session-store-mutex)
      (immutable default-ttl %session-store-ttl)))   ;; seconds

  (define (make-session-store . opts)
    (let ([ttl (if (and (pair? opts) (pair? (cdr opts)) (eq? (car opts) 'ttl:))
                 (cadr opts)
                 3600)])  ;; Default: 1 hour
      (make-session-store*
        (make-hashtable string-hash string=?)
        (make-mutex)
        ttl)))

  (define (session-create! store identity roles)
    ;; Create a new session. Returns the session token.
    (let ([token (random-token 32)]
          [expiry (+ (time-second (current-time 'time-utc))
                     (%session-store-ttl store))])
      (with-mutex (%session-store-mutex store)
        (hashtable-set! (%session-store-sessions store) token
          (list identity roles expiry)))
      token))

  (define (session-validate store token)
    ;; Validate a session token. Returns (identity roles) or #f.
    (with-mutex (%session-store-mutex store)
      (let ([entry (hashtable-ref (%session-store-sessions store) token #f)])
        (if entry
          (let ([expiry (caddr entry)])
            (if (> (time-second (current-time 'time-utc)) expiry)
              (begin
                (hashtable-delete! (%session-store-sessions store) token)
                #f)
              (list (car entry) (cadr entry))))
          #f))))

  (define (session-destroy! store token)
    (with-mutex (%session-store-mutex store)
      (hashtable-delete! (%session-store-sessions store) token)))

  (define (session-cleanup! store)
    ;; Remove all expired sessions.
    (with-mutex (%session-store-mutex store)
      (let ([sessions (%session-store-sessions store)]
            [now (time-second (current-time 'time-utc))])
        (let-values ([(ks vs) (hashtable-entries sessions)])
          (do ([i 0 (+ i 1)])
              ((= i (vector-length ks)))
            (let ([expiry (caddr (vector-ref vs i))])
              (when (> now expiry)
                (hashtable-delete! sessions (vector-ref ks i)))))))))

  ;; ========== Auth Result ==========

  (define-record-type (auth-result make-auth-result auth-result?)
    (fields
      (immutable authenticated? auth-result-authenticated?)
      (immutable identity auth-result-identity)
      (immutable roles auth-result-roles)))

  ;; ========== Auth Middleware ==========

  (define (make-auth-middleware validator)
    ;; Create an auth middleware function.
    ;; validator: (lambda (token) -> (identity roles) | #f)
    ;; Returns: (lambda (handler) -> wrapped-handler)
    (lambda (handler)
      (lambda (request)
        (let* ([auth-header (extract-auth-header request)]
               [token (and auth-header (extract-bearer-token auth-header))]
               [result (if token (validator token) #f)])
          (if result
            (handler (cons (cons 'auth (make-auth-result #t (car result) (cadr result)))
                           request))
            (list 401 '(("WWW-Authenticate" . "Bearer")) "Unauthorized"))))))

  (define (extract-auth-header request)
    ;; Extract Authorization header from request alist.
    (let loop ([r request])
      (cond
        [(null? r) #f]
        [(and (pair? (car r)) (equal? (caar r) 'authorization))
         (cdar r)]
        [(and (pair? (car r)) (equal? (caar r) "Authorization"))
         (cdar r)]
        [else (loop (cdr r))])))

  (define (extract-bearer-token header)
    ;; Extract token from "Bearer <token>" header value.
    (let ([prefix "Bearer "])
      (if (and (>= (string-length header) (string-length prefix))
               (string=? (substring header 0 (string-length prefix)) prefix))
        (substring header (string-length prefix) (string-length header))
        #f)))

  ;; ========== Rate Limiter ==========

  (define-record-type (rate-limiter make-rate-limiter* rate-limiter?)
    (sealed #t)
    (fields
      (immutable attempts %rl-attempts)     ;; hashtable: key -> (count window-start)
      (immutable mutex %rl-mutex)
      (immutable max-attempts %rl-max)
      (immutable window-seconds %rl-window)))

  (define (make-rate-limiter max-attempts window-seconds)
    (make-rate-limiter*
      (make-hashtable string-hash string=?)
      (make-mutex)
      max-attempts
      window-seconds))

  (define (rate-limit-check! limiter key)
    ;; Check if a key (e.g., IP address) is within rate limits.
    ;; Returns #t if allowed, #f if rate-limited.
    (with-mutex (%rl-mutex limiter)
      (let* ([now (time-second (current-time 'time-utc))]
             [attempts (%rl-attempts limiter)]
             [entry (hashtable-ref attempts key #f)])
        (cond
          [(not entry)
           ;; First attempt
           (hashtable-set! attempts key (list 1 now))
           #t]
          [(> (- now (cadr entry)) (%rl-window limiter))
           ;; Window expired, reset
           (hashtable-set! attempts key (list 1 now))
           #t]
          [(< (car entry) (%rl-max limiter))
           ;; Within limits
           (hashtable-set! attempts key (list (+ (car entry) 1) (cadr entry)))
           #t]
          [else #f]))))  ;; Rate limited

  ) ;; end library
