#!/usr/bin/env scheme-script
#!chezscheme
;;; Tests for Phase 6: Supply Chain and Distributed Security
;;; Modules: verify, sbom, reproducible (provenance), cluster-security

(import (chezscheme)
        (jerboa lock)
        (std build verify)
        (std build sbom)
        (std build reproducible)
        (std actor cluster-security))

(define pass-count 0)
(define fail-count 0)

(define (test name expr)
  (guard (exn
    [#t (set! fail-count (+ fail-count 1))
        (display "FAIL: ") (display name) (newline)
        (display "  Exception: ") (display (condition-message exn)) (newline)])
    (if expr
      (begin (set! pass-count (+ pass-count 1))
             (display "PASS: ") (display name) (newline))
      (begin (set! fail-count (+ fail-count 1))
             (display "FAIL: ") (display name) (newline)))))

(display "=== Phase 6: Supply Chain and Distributed Security Tests ===") (newline)

;; ========== S1: Dependency Verification ==========
(display "--- S1: Dependency Verification ---") (newline)

(test "verify: result record creation"
  (let ([r (verify-dependency "test-pkg" "abc123" "/nonexistent/path")])
    (and (verification-result? r)
         (equal? (verification-result-name r) "test-pkg")
         (eq? (verification-result-status r) 'missing))))

(test "verify: verify real file"
  (let ([tmp "/tmp/jerboa-test-verify"])
    (call-with-output-file tmp
      (lambda (p) (display "hello world" p))
      'replace)
    (let ([hash (file-sha256-hex tmp)])
      (delete-file tmp)
      (and (string? hash) (= (string-length hash) 64)))))

(test "verify: hash mismatch detection"
  (let ([tmp "/tmp/jerboa-test-verify2"])
    (call-with-output-file tmp
      (lambda (p) (display "test data" p))
      'replace)
    (let ([r (verify-dependency "pkg" "0000000000000000000000000000000000000000000000000000000000000000" tmp)])
      (delete-file tmp)
      (eq? (verification-result-status r) 'mismatch))))

(test "verify: hash match detection"
  (let ([tmp "/tmp/jerboa-test-verify3"])
    (call-with-output-file tmp
      (lambda (p) (display "verify me" p))
      'replace)
    (let* ([hash (file-sha256-hex tmp)]
           [r (verify-dependency "pkg" hash tmp)])
      (delete-file tmp)
      (eq? (verification-result-status r) 'ok))))

(test "verify: batch verification with lockfile"
  (let ([lf (make-lockfile (list (make-lock-entry "missing-pkg" "1.0" "abc" '())))])
    (let ([results (verify-all-dependencies lf "/nonexistent")])
      (and (= (length results) 1)
           (eq? (verification-result-status (car results)) 'missing)))))

(test "verify: lockfile-verify-report"
  (let ([lf (make-lockfile (list (make-lock-entry "pkg1" "1.0" "abc" '())))])
    (let ([report (lockfile-verify-report lf "/nonexistent")])
      (and (= (cdr (assq 'total report)) 1)
           (= (cdr (assq 'failed report)) 1)))))

(test "verify: verify-lockfile! abort mode"
  (let ([lf (make-lockfile (list (make-lock-entry "pkg1" "1.0" "abc" '())))])
    (guard (exn [#t #t])
      (verify-lockfile! lf "/nonexistent" 'abort)
      #f)))

(test "verify: verify-lockfile! warn mode"
  (let ([lf (make-lockfile (list (make-lock-entry "pkg1" "1.0" "abc" '())))])
    (not (verify-lockfile! lf "/nonexistent" 'warn))))

;; ========== S2: SBOM Generation ==========
(display "--- S2: SBOM Generation ---") (newline)

(test "sbom: create SBOM"
  (let ([s (make-sbom "myapp" "1.0.0")])
    (and (sbom? s)
         (equal? (sbom-project s) "myapp")
         (equal? (sbom-version s) "1.0.0"))))

(test "sbom: add component"
  (let ([s (make-sbom "myapp" "1.0.0")])
    (sbom-add-component! s (make-component "chez-ssl" "1.2.0" 'library))
    (= (length (sbom-components s)) 1)))

(test "sbom: component with hash and license"
  (let ([c (make-component "mylib" "2.0" 'library
             'hash: "abc123" 'license: "Apache-2.0")])
    (and (equal? (component-hash c) "abc123")
         (equal? (component-license c) "Apache-2.0"))))

(test "sbom: find component"
  (let ([s (make-sbom "myapp" "1.0.0")])
    (sbom-add-component! s (make-component "lib-a" "1.0" 'library))
    (sbom-add-component! s (make-component "lib-b" "2.0" 'c-library))
    (let ([found (sbom-find-component s "lib-a")])
      (and found (equal? (component-name found) "lib-a")))))

(test "sbom: find nonexistent component"
  (let ([s (make-sbom "myapp" "1.0.0")])
    (not (sbom-find-component s "nope"))))

(test "sbom: add build info"
  (let ([s (make-sbom "myapp" "1.0.0")])
    (sbom-add-build-info! s 'scheme-version "10.4.0")
    (sbom-add-build-info! s 'platform "linux")
    (= (length (sbom-build-info s)) 2)))

(test "sbom: roundtrip serialization"
  (let ([s (make-sbom "myapp" "1.0.0")])
    (sbom-add-component! s (make-component "lib-a" "1.0" 'library
                             'hash: "abc123" 'license: "MIT"))
    (sbom-add-build-info! s 'compiler "chez")
    (let* ([sexp (sbom->sexp s)]
           [s2 (sexp->sbom sexp)])
      (and (equal? (sbom-project s2) "myapp")
           (equal? (sbom-version s2) "1.0.0")))))

(test "sbom: write and read"
  (let ([s (make-sbom "test" "0.1")])
    (sbom-add-component! s (make-component "dep1" "1.0" 'library))
    (let ([tmp "/tmp/jerboa-test-sbom"])
      (call-with-output-file tmp
        (lambda (p) (sbom-write s p))
        'replace)
      (let ([s2 (call-with-input-file tmp sbom-read)])
        (delete-file tmp)
        (equal? (sbom-project s2) "test")))))

(test "sbom: detect-c-deps from string"
  (let ([deps (detect-c-deps "/nonexistent")])
    (list? deps)))

(test "sbom: component types"
  (let ([c1 (make-component "a" "1" 'library)]
        [c2 (make-component "b" "1" 'c-library)]
        [c3 (make-component "c" "1" 'application)])
    (and (eq? (component-type c1) 'library)
         (eq? (component-type c2) 'c-library)
         (eq? (component-type c3) 'application))))

;; ========== S3: Reproducible Build Provenance ==========
(display "--- S3: Provenance Tracking ---") (newline)

(test "provenance: create record"
  (let ([p (make-provenance "abc123" "builder-1" "def456")])
    (and (provenance? p)
         (equal? (provenance-source-hash p) "abc123")
         (equal? (provenance-builder-id p) "builder-1")
         (equal? (provenance-output-hash p) "def456"))))

(test "provenance: with timestamp"
  (let ([p (make-provenance "abc" "b1" "def" 'timestamp: 1234567890)])
    (= (provenance-build-timestamp p) 1234567890)))

(test "provenance: without timestamp for reproducibility"
  (let ([p (make-provenance "abc" "b1" "def")])
    (not (provenance-build-timestamp p))))

(test "provenance: roundtrip serialization"
  (let ([p (make-provenance "src-hash" "my-machine" "out-hash"
             'timestamp: 9999)])
    (let* ([sexp (provenance->sexp p)]
           [p2 (sexp->provenance sexp)])
      (and (equal? (provenance-source-hash p2) "src-hash")
           (equal? (provenance-builder-id p2) "my-machine")))))

(test "provenance: write and read"
  (let ([p (make-provenance "aaa" "bbb" "ccc")]
        [tmp "/tmp/jerboa-test-prov"])
    (call-with-output-file tmp
      (lambda (port) (provenance-write p port))
      'replace)
    (let ([p2 (call-with-input-file tmp provenance-read)])
      (delete-file tmp)
      (equal? (provenance-source-hash p2) "aaa"))))

(test "provenance: verify matching source"
  (let ([p (make-provenance "expected-hash" "b1" "out")])
    (verify-provenance p "expected-hash")))

(test "provenance: verify mismatched source"
  (let ([p (make-provenance "actual-hash" "b1" "out")])
    (not (verify-provenance p "wrong-hash"))))

;; ========== D1: Encrypted Transport Config ==========
(display "--- D1: Encrypted Transport ---") (newline)

(test "d1: create node TLS config"
  (let ([c (make-node-tls-config
             'certificate: "/etc/node.crt"
             'private-key: "/etc/node.key"
             'ca-certificate: "/etc/ca.crt"
             'verify-peer: #t)])
    (and (node-tls-config? c)
         (equal? (node-tls-config-certificate c) "/etc/node.crt")
         (node-tls-config-verify-peer? c))))

(test "d1: default verify-peer is true"
  (let ([c (make-node-tls-config 'certificate: "cert")])
    (node-tls-config-verify-peer? c)))

;; ========== D2: Message Authentication ==========
(display "--- D2: Message Authentication ---") (newline)

(test "d2: create authenticated message"
  (let ([m (make-authenticated-message "node-1" 1 '(hello world) "secret-key")])
    (and (authenticated-message? m)
         (equal? (authenticated-message-sender m) "node-1")
         (= (authenticated-message-sequence m) 1)
         (equal? (authenticated-message-payload m) '(hello world))
         (string? (authenticated-message-hmac m)))))

(test "d2: verify valid message"
  (let ([m (make-authenticated-message "node-1" 1 "payload" "key")])
    (verify-message-auth m "key")))

(test "d2: reject tampered message"
  (let ([m (make-authenticated-message "node-1" 1 "payload" "key")])
    (not (verify-message-auth m "wrong-key"))))

(test "d2: replay window accepts new messages"
  (let ([w (make-replay-window 100)]
        [m1 (make-authenticated-message "n1" 1 "a" "k")]
        [m2 (make-authenticated-message "n1" 2 "b" "k")])
    (and (replay-window-check! w m1)
         (replay-window-check! w m2))))

(test "d2: replay window rejects replayed sequence"
  (let ([w (make-replay-window 100)]
        [m1 (make-authenticated-message "n1" 1 "a" "k")]
        [m2 (make-authenticated-message "n1" 1 "b" "k")])  ;; same seq
    (replay-window-check! w m1)
    (not (replay-window-check! w m2))))

(test "d2: replay window tracks per-sender"
  (let ([w (make-replay-window 100)]
        [m1 (make-authenticated-message "n1" 1 "a" "k")]
        [m2 (make-authenticated-message "n2" 1 "b" "k")])  ;; different sender, same seq
    (and (replay-window-check! w m1)
         (replay-window-check! w m2))))

;; ========== D3: Capability Delegation ==========
(display "--- D3: Capability Delegation ---") (newline)

(test "d3: create delegation token"
  (let ([t (make-delegation-token 'fs '(read) "node-2" "signing-key")])
    (and (delegation-token? t)
         (eq? (delegation-token-capability-type t) 'fs)
         (equal? (delegation-token-permissions t) '(read))
         (equal? (delegation-token-target-node t) "node-2"))))

(test "d3: verify valid token"
  (let ([t (make-delegation-token 'fs '(read write) "node-2" "key")])
    (verify-delegation-token t "key")))

(test "d3: reject token with wrong key"
  (let ([t (make-delegation-token 'fs '(read) "node-2" "key")])
    (not (verify-delegation-token t "wrong-key"))))

(test "d3: token with expiry in future"
  (let* ([future (+ (time-second (current-time 'time-utc)) 3600)]
         [t (make-delegation-token 'net '(connect) "node-3" "key" future)])
    (and (= (delegation-token-expiry t) future)
         (verify-delegation-token t "key"))))

(test "d3: token with expired timestamp"
  (let* ([past (- (time-second (current-time 'time-utc)) 3600)]
         [t (make-delegation-token 'net '(connect) "node-3" "key" past)])
    (not (verify-delegation-token t "key"))))

;; ========== D4: Cluster Policies ==========
(display "--- D4: Cluster Policies ---") (newline)

(test "d4: create cluster policy"
  (let ([p (make-cluster-policy
             'auth-method: 'mutual-tls
             'node-roles: '(("node-1" . coordinator) ("node-2" . worker))
             'role-permissions: '((coordinator . (spawn-actor kill-actor read-state write-state))
                                  (worker . (spawn-actor read-state)))
             'allowed-connections: '((coordinator . (worker)) (worker . (coordinator)))
             'max-message-rate: 5000)])
    (and (cluster-policy? p)
         (eq? (cluster-policy-auth-method p) 'mutual-tls)
         (= (cluster-policy-max-message-rate p) 5000))))

(test "d4: node has permission"
  (let ([p (make-cluster-policy
             'node-roles: '(("node-1" . coordinator))
             'role-permissions: '((coordinator . (spawn-actor kill-actor))))])
    (node-has-permission? p "node-1" 'kill-actor)))

(test "d4: node lacks permission"
  (let ([p (make-cluster-policy
             'node-roles: '(("node-1" . worker))
             'role-permissions: '((worker . (spawn-actor read-state))))])
    (not (node-has-permission? p "node-1" 'kill-actor))))

(test "d4: unknown node has no permissions"
  (let ([p (make-cluster-policy
             'node-roles: '(("node-1" . coordinator))
             'role-permissions: '((coordinator . (all))))])
    (not (node-has-permission? p "unknown-node" 'anything))))

(test "d4: connection allowed"
  (let ([p (make-cluster-policy
             'node-roles: '(("n1" . coordinator) ("n2" . worker))
             'allowed-connections: '((coordinator . (worker)) (worker . (coordinator))))])
    (connection-allowed? p "n1" "n2")))

(test "d4: connection denied"
  (let ([p (make-cluster-policy
             'node-roles: '(("n1" . worker) ("n2" . worker))
             'allowed-connections: '((coordinator . (worker)) (worker . (coordinator))))])
    (not (connection-allowed? p "n1" "n2"))))

(test "d4: default max message size is 1MB"
  (let ([p (make-cluster-policy)])
    (= (cluster-policy-max-message-size p) (* 1 1024 1024))))

;; ========== Summary ==========
(newline)
(display "=== Results ===") (newline)
(display "Passed: ") (display pass-count) (newline)
(display "Failed: ") (display fail-count) (newline)
(when (> fail-count 0)
  (exit 1))
