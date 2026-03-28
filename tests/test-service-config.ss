#!chezscheme
;;; test-service-config.ss — Tests for (std service config)

(import (chezscheme) (std service config))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr]
           [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: ")
           (write 'expr)
           (display " => ")
           (write result)
           (display " expected ")
           (write exp)
           (newline))))]))

(define-syntax check-true
  (syntax-rules ()
    [(_ expr)
     (if expr
       (set! pass-count (+ pass-count 1))
       (begin
         (set! fail-count (+ fail-count 1))
         (display "FAIL: ")
         (write 'expr)
         (display " => #f (expected #t)\n")))]))

(display "=== Service Config Tests ===\n")

;; ========== Default Config ==========

(check-true (service-config? default-service-config))
(check (service-config-user default-service-config) => #f)
(check (service-config-group default-service-config) => #f)
(check (service-config-memory-limit default-service-config) => #f)
(check (service-config-file-limit default-service-config) => #f)
(check (service-config-nofile-limit default-service-config) => #f)
(check (service-config-nproc-limit default-service-config) => #f)
(check (service-config-env-dir default-service-config) => #f)
(check (service-config-sandbox-read default-service-config) => '())
(check (service-config-sandbox-write default-service-config) => '())
(check (service-config-sandbox-exec default-service-config) => '())
(check (service-config-seccomp? default-service-config) => #f)

;; ========== make-service-config ==========

(let ([c (make-service-config
           "dns" "dns" 67108864 1048576 1024 64
           "/etc/dns/env"
           '("/etc/dns") '("/var/log/dns") '("/usr/bin")
           #t)])
  (check-true (service-config? c))
  (check (service-config-user c) => "dns")
  (check (service-config-group c) => "dns")
  (check (service-config-memory-limit c) => 67108864)
  (check (service-config-file-limit c) => 1048576)
  (check (service-config-nofile-limit c) => 1024)
  (check (service-config-nproc-limit c) => 64)
  (check (service-config-env-dir c) => "/etc/dns/env")
  (check (service-config-sandbox-read c) => '("/etc/dns"))
  (check (service-config-sandbox-write c) => '("/var/log/dns"))
  (check (service-config-sandbox-exec c) => '("/usr/bin"))
  (check (service-config-seccomp? c) => #t))

;; ========== load-service-config from file ==========

(define test-dir "/tmp/test-service-config")

;; Create test service directory
(when (file-exists? test-dir)
  (for-each (lambda (f)
              (let ([p (string-append test-dir "/" f)])
                (when (file-exists? p) (delete-file p))))
    '("config.scm" "run"))
  (delete-directory test-dir))
(mkdir test-dir)

;; Test: no config.scm → default
(let ([c (load-service-config test-dir)])
  (check-true (service-config? c))
  (check (service-config-user c) => #f)
  (check (service-config-memory-limit c) => #f))

;; Test: write a config.scm and load it
(call-with-output-file (string-append test-dir "/config.scm")
  (lambda (p)
    (write '((user . "www")
             (group . "www")
             (memory-limit . 134217728)
             (nofile-limit . 256)
             (sandbox-read . ("/var/www" "/etc/ssl"))
             (sandbox-write . ("/var/log/www"))
             (seccomp . #t))
           p))
  'replace)

(let ([c (load-service-config test-dir)])
  (check-true (service-config? c))
  (check (service-config-user c) => "www")
  (check (service-config-group c) => "www")
  (check (service-config-memory-limit c) => 134217728)
  (check (service-config-file-limit c) => #f)
  (check (service-config-nofile-limit c) => 256)
  (check (service-config-nproc-limit c) => #f)
  (check (service-config-sandbox-read c) => '("/var/www" "/etc/ssl"))
  (check (service-config-sandbox-write c) => '("/var/log/www"))
  (check (service-config-seccomp? c) => #t))

;; Test: invalid config.scm → default
(call-with-output-file (string-append test-dir "/config.scm")
  (lambda (p)
    (display "this is not valid scheme" p))
  'replace)

(let ([c (load-service-config test-dir)])
  (check-true (service-config? c))
  (check (service-config-user c) => #f))

;; Test: non-alist → default
(call-with-output-file (string-append test-dir "/config.scm")
  (lambda (p)
    (write 42 p))
  'replace)

(let ([c (load-service-config test-dir)])
  (check-true (service-config? c))
  (check (service-config-user c) => #f))

;; Test: partial config — only some fields
(call-with-output-file (string-append test-dir "/config.scm")
  (lambda (p)
    (write '((user . "sshd")
             (nproc-limit . 10))
           p))
  'replace)

(let ([c (load-service-config test-dir)])
  (check (service-config-user c) => "sshd")
  (check (service-config-group c) => #f)
  (check (service-config-nproc-limit c) => 10)
  (check (service-config-memory-limit c) => #f))

;; Cleanup
(delete-file (string-append test-dir "/config.scm"))
(delete-directory test-dir)

;; ========== Summary ==========

(display (format "\nService config tests: ~a passed, ~a failed\n"
           pass-count fail-count))
(when (> fail-count 0) (exit 1))
