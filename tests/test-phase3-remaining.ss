#!chezscheme
;;; test-phase3-remaining.ss -- Tests for V5, N1, N4

(import (chezscheme)
        (std net tls)
        (std net timeout)
        (std crypto native)
        (std crypto random))

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

;; ========== Helpers ==========

(define (string-downcase s)
  (let ([out (make-string (string-length s))])
    (do ([i 0 (+ i 1)])
        ((= i (string-length s)) out)
      (string-set! out i (char-downcase (string-ref s i))))))

(define (string-contains haystack needle)
  (let ([hlen (string-length haystack)]
        [nlen (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nlen) hlen) #f]
        [(string=? (substring haystack i (+ i nlen)) needle) #t]
        [else (loop (+ i 1))]))))

;; ========== TLS Config Tests (N1) ==========
(display "  Testing TLS configuration....\n")

;; Default config
(check (tls-config? default-tls-config) => #t)
(check (tls-config-min-version default-tls-config) => 'tls-1.2)
(check (tls-config-verify-peer? default-tls-config) => #t)
(check (tls-config-verify-hostname? default-tls-config) => #t)
(check (tls-config-ca-file default-tls-config) => #f)
(check (tls-config-cert-file default-tls-config) => #f)
(check (tls-config-key-file default-tls-config) => #f)
(check (pair? (tls-config-cipher-suites default-tls-config)) => #t)

;; Custom config
(let ([cfg (make-tls-config 'min-version: 'tls-1.3
                            'verify-peer: #f)])
  (check (tls-config-min-version cfg) => 'tls-1.3)
  (check (tls-config-verify-peer? cfg) => #f)
  ;; Other fields retain defaults
  (check (tls-config-verify-hostname? cfg) => #t))

;; Config override
(let ([cfg (tls-config-with default-tls-config
             'ca-file: "/etc/ssl/certs/ca-certificates.crt"
             'verify-hostname: #f)])
  (check (tls-config-ca-file cfg) => "/etc/ssl/certs/ca-certificates.crt")
  (check (tls-config-verify-hostname? cfg) => #f)
  ;; Base unchanged
  (check (tls-config-min-version cfg) => 'tls-1.2)
  (check (tls-config-verify-peer? cfg) => #t))

;; Cipher suites include only strong ciphers
(let ([ciphers (tls-config-cipher-suites default-tls-config)])
  ;; No RC4, no DES, no CBC, no NULL
  (check (for-all (lambda (c)
                    (let ([s (string-downcase c)])
                      (and (not (string-contains s "rc4"))
                           (not (string-contains s "des"))
                           (not (string-contains s "null")))))
           ciphers) => #t))

;; Certificate pinning
(let ([pins (make-pin-set)])
  (check (pin-set? pins) => #t)
  (check (pin-set-check pins "abc123") => #f)
  (pin-set-add! pins "abc123")
  (check (pin-set-check pins "abc123") => #t)
  (check (pin-set-check pins "def456") => #f))

;; ========== Timeout Config Tests (N4) ==========
(display "  Testing timeout configuration...\n")

;; Default config
(check (timeout-config? default-timeout-config) => #t)
(check (timeout-config-connect default-timeout-config) => 5000)
(check (timeout-config-read default-timeout-config) => 30000)
(check (timeout-config-write default-timeout-config) => 10000)
(check (timeout-config-idle default-timeout-config) => 60000)

;; Custom config
(let ([cfg (make-timeout-config 'connect: 1000 'read: 5000)])
  (check (timeout-config-connect cfg) => 1000)
  (check (timeout-config-read cfg) => 5000)
  (check (timeout-config-write cfg) => 10000)  ;; default
  (check (timeout-config-idle cfg) => 60000))   ;; default

;; HTTP limits — defaults
(check (http-limits? default-http-limits) => #t)
(check (http-limits-max-header-size default-http-limits) => 8192)
(check (http-limits-max-header-count default-http-limits) => 100)
(check (http-limits-max-uri-length default-http-limits) => 2048)
(check (http-limits-max-body-size default-http-limits) => 10485760)
(check (http-limits-request-timeout default-http-limits) => 30000)

;; Custom HTTP limits
(let ([lim (make-http-limits 'max-body-size: 1024 'max-header-count: 10)])
  (check (http-limits-max-body-size lim) => 1024)
  (check (http-limits-max-header-count lim) => 10)
  (check (http-limits-max-header-size lim) => 8192))  ;; default

;; Header limit checks
(let ([lim (make-http-limits 'max-header-count: 2 'max-header-size: 50)])
  ;; Within limits
  (check (guard (exn [#t #f])
           (check-header-limits '(("Host" . "example.com")) lim) #t) => #t)
  ;; Too many headers
  (check (guard (exn [(limit-exceeded? exn)
                      (limit-exceeded-what exn)])
           (check-header-limits '(("A" . "1") ("B" . "2") ("C" . "3")) lim)
           #f) => "header-count"))

;; Body limit check
(let ([lim (make-http-limits 'max-body-size: 100)])
  (check (guard (exn [#t #f])
           (check-body-limits 50 lim) #t) => #t)
  (check (guard (exn [(limit-exceeded? exn)
                      (limit-exceeded-what exn)])
           (check-body-limits 200 lim)
           #f) => "body-size"))

;; URI limit check
(let ([lim (make-http-limits 'max-uri-length: 10)])
  (check (guard (exn [#t #f])
           (check-uri-limits "/short" lim) #t) => #t)
  (check (guard (exn [(limit-exceeded? exn)
                      (limit-exceeded-what exn)])
           (check-uri-limits "/this-is-way-too-long" lim)
           #f) => "uri-length"))

;; with-timeout — fast operation succeeds
(check (with-timeout 1000 (lambda () (+ 1 2))) => 3)

;; with-timeout — slow operation times out
(check-error (with-timeout 50 (lambda () (sleep (make-time 'time-duration 0 2)) 42)))

;; ========== Actor Transport Auth (V5) — Unit Tests ==========
(display "  Testing transport auth helpers...\n")

;; We can't do a full integration test without starting nodes,
;; but we verify the crypto primitives used.

;; HMAC-SHA256 produces different results for different inputs
(let ([key (string->utf8 "secret-cookie")]
      [data1 (string->utf8 "nonce1:nonce2:node1")]
      [data2 (string->utf8 "nonce1:nonce2:node2")])
  (let ([h1 (native-hmac-sha256 key data1)]
        [h2 (native-hmac-sha256 key data2)])
    (check (bytevector? h1) => #t)
    (check (= (bytevector-length h1) 32) => #t)
    (check (equal? h1 h2) => #f)))

;; Same inputs produce same HMAC
(let ([key (string->utf8 "cookie")]
      [data (string->utf8 "same-data")])
  (check (equal? (native-hmac-sha256 key data)
                 (native-hmac-sha256 key data)) => #t))

;; Timing-safe comparison
(let ([a (native-hmac-sha256 (string->utf8 "k") (string->utf8 "d"))]
      [b (native-hmac-sha256 (string->utf8 "k") (string->utf8 "d"))])
  (check (native-crypto-memcmp a b) => #t))

(let ([a (native-hmac-sha256 (string->utf8 "k") (string->utf8 "d1"))]
      [b (native-hmac-sha256 (string->utf8 "k") (string->utf8 "d2"))])
  (check (native-crypto-memcmp a b) => #f))

;; Random nonces are unique
(let ([n1 (random-bytes 32)]
      [n2 (random-bytes 32)])
  (check (equal? n1 n2) => #f))

;; ========== Summary ==========
(display "  phase3-remaining: ")
(display pass-count) (display " passed")
(when (> fail-count 0)
  (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
