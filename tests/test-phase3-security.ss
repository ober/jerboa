#!chezscheme
;;; test-phase3-security.ss -- Tests for Phase 3 security modules

(import (chezscheme)
        (std net security-headers)
        (std crypto password)
        (std crypto aead)
        (std security auth))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr] [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: ") (write 'expr)
           (display " => ") (write result)
           (display " expected ") (write exp) (newline))))]))

(define-syntax check-error
  (syntax-rules ()
    [(_ expr)
     (guard (exn [#t (set! pass-count (+ pass-count 1))])
       expr
       (set! fail-count (+ fail-count 1))
       (display "FAIL: expected error from ") (write 'expr) (newline))]))

;; ========== Security Headers Tests ==========
(display "  Testing security headers...\n")

(check (pair? default-security-headers) => #t)
(check (and (assoc "X-Frame-Options" default-security-headers) #t) => #t)
(check (and (assoc "Content-Security-Policy" default-security-headers) #t) => #t)

;; apply-security-headers
(let ([result (apply-security-headers '(("Content-Type" . "text/html")))])
  (check (and (assoc "X-Frame-Options" result) #t) => #t)
  (check (and (assoc "Content-Type" result) #t) => #t))

;; Don't override existing headers
(let ([result (apply-security-headers '(("X-Frame-Options" . "SAMEORIGIN")))])
  (check (cdr (assoc "X-Frame-Options" result)) => "SAMEORIGIN"))

;; CSP builder
(check (csp-header 'default-src: "'self'" 'script-src: "'none'")
  => "default-src 'self'; script-src 'none'")

;; HSTS builder
(check (hsts-header 31536000) => "max-age=31536000")
(check (hsts-header 31536000 'include-subdomains 'preload)
  => "max-age=31536000; includeSubDomains; preload")

;; Custom headers
(let ([custom (make-security-headers 'frame: "SAMEORIGIN")])
  (check (cdr (assoc "X-Frame-Options" custom)) => "SAMEORIGIN"))

;; ========== Password Hashing Tests ==========
(display "  Testing password hashing...\n")

;; Basic hash and verify
(let ([hash (password-hash "mypassword" 'iterations: 10000)])
  (check (string? hash) => #t)
  ;; Starts with $pbkdf2-sha256$
  (check (and (> (string-length hash) 15)
              (string=? (substring hash 0 15) "$pbkdf2-sha256$")) => #t)
  ;; Verify correct password
  (check (password-verify "mypassword" hash) => #t)
  ;; Reject wrong password
  (check (password-verify "wrongpassword" hash) => #f))

;; Different passwords produce different hashes
(let ([h1 (password-hash "pass1" 'iterations: 10000)]
      [h2 (password-hash "pass2" 'iterations: 10000)])
  (check (string=? h1 h2) => #f))

;; Same password with different salt produces different hashes
(let ([h1 (password-hash "same" 'iterations: 10000)]
      [h2 (password-hash "same" 'iterations: 10000)])
  (check (string=? h1 h2) => #f))

;; ========== AEAD Tests ==========
(display "  Testing AEAD encryption...\n")

(let ([key (aead-key-generate)])
  (check (bytevector? key) => #t)
  (check (bytevector-length key) => 32)

  ;; Encrypt and decrypt
  (let* ([plaintext #vu8(72 101 108 108 111)]  ;; "Hello"
         [ct (aead-encrypt key plaintext)]
         [pt (aead-decrypt key ct)])
    (check (equal? pt plaintext) => #t))

  ;; String input
  (let* ([ct (aead-encrypt key "Hello World")]
         [pt (aead-decrypt key ct)])
    (check (equal? (utf8->string pt) "Hello World") => #t))

  ;; With AAD
  (let* ([ct (aead-encrypt key "secret" #vu8(1 2 3))]
         [pt (aead-decrypt key ct #vu8(1 2 3))])
    (check (equal? (utf8->string pt) "secret") => #t))

  ;; Wrong key fails
  (let* ([ct (aead-encrypt key "test")]
         [wrong-key (aead-key-generate)])
    (check-error (aead-decrypt wrong-key ct)))

  ;; Tampered ciphertext fails
  (let ([ct (aead-encrypt key "test")])
    (bytevector-u8-set! ct 15 (bitwise-xor (bytevector-u8-ref ct 15) #xff))
    (check-error (aead-decrypt key ct))))

;; ========== Auth Module Tests ==========
(display "  Testing auth module...\n")

;; API key store
(let ([store (make-api-key-store)])
  (check (api-key-store? store) => #t)
  (let ([key (api-key-register! store "user1" '(admin))])
    (check (string? key) => #t)
    (check (= (string-length key) 64) => #t)  ;; 32 bytes = 64 hex chars
    ;; Validate
    (let ([result (api-key-validate store key)])
      (check (pair? result) => #t)
      (check (car result) => "user1")
      (check (cadr result) => '(admin)))
    ;; Invalid key
    (check (api-key-validate store "invalid-key") => #f)
    ;; Revoke
    (api-key-revoke! store key)
    (check (api-key-validate store key) => #f)))

;; Session store
(let ([store (make-session-store 'ttl: 3600)])
  (check (session-store? store) => #t)
  (let ([token (session-create! store "user1" '(read write))])
    (check (string? token) => #t)
    ;; Validate
    (let ([result (session-validate store token)])
      (check (pair? result) => #t)
      (check (car result) => "user1"))
    ;; Destroy
    (session-destroy! store token)
    (check (session-validate store token) => #f)))

;; Rate limiter
(let ([limiter (make-rate-limiter 3 60)])
  (check (rate-limit-check! limiter "192.168.1.1") => #t)  ;; 1st
  (check (rate-limit-check! limiter "192.168.1.1") => #t)  ;; 2nd
  (check (rate-limit-check! limiter "192.168.1.1") => #t)  ;; 3rd
  (check (rate-limit-check! limiter "192.168.1.1") => #f)  ;; 4th — blocked
  ;; Different key is fine
  (check (rate-limit-check! limiter "192.168.1.2") => #t))

;; Auth result
(let ([r (make-auth-result #t "user1" '(admin))])
  (check (auth-result? r) => #t)
  (check (auth-result-authenticated? r) => #t)
  (check (auth-result-identity r) => "user1")
  (check (auth-result-roles r) => '(admin)))

(display "  phase3-security: ")
(display pass-count) (display " passed")
(when (> fail-count 0)
  (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
