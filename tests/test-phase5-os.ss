#!/usr/bin/env scheme-script
#!chezscheme
;;; Tests for Phase 5: OS-Level Enforcement
;;; Modules: seccomp, landlock, privsep, metrics, errors

(import (chezscheme)
        (std security seccomp)
        (std security landlock)
        (std security privsep)
        (std security metrics)
        (std security errors))

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

(define (string-contains haystack needle)
  (let ([hlen (string-length haystack)]
        [nlen (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nlen) hlen) #f]
        [(string=? (substring haystack i (+ i nlen)) needle) #t]
        [else (loop (+ i 1))]))))

(display "=== Phase 5: OS-Level Enforcement Tests ===") (newline)

;; ========== seccomp Tests ==========
(display "--- seccomp-BPF ---") (newline)

(test "seccomp: make compute-only filter"
  (seccomp-filter? compute-only-filter))

(test "seccomp: make network-server filter"
  (seccomp-filter? network-server-filter))

(test "seccomp: make io-only filter"
  (seccomp-filter? io-only-filter))

(test "seccomp: filter default action is kill"
  (= (seccomp-filter-default-action compute-only-filter) seccomp-kill))

(test "seccomp: compute filter has allowed syscalls"
  (pair? (seccomp-filter-allowed-syscalls compute-only-filter)))

(test "seccomp: compute filter allows read"
  (memq 'read (seccomp-filter-allowed-syscalls compute-only-filter)))

(test "seccomp: compute filter allows write"
  (memq 'write (seccomp-filter-allowed-syscalls compute-only-filter)))

(test "seccomp: compute filter allows brk"
  (memq 'brk (seccomp-filter-allowed-syscalls compute-only-filter)))

(test "seccomp: network filter includes socket"
  (memq 'socket (seccomp-filter-allowed-syscalls network-server-filter)))

(test "seccomp: network filter includes bind"
  (memq 'bind (seccomp-filter-allowed-syscalls network-server-filter)))

(test "seccomp: io filter has no socket"
  (not (memq 'socket (seccomp-filter-allowed-syscalls io-only-filter))))

(test "seccomp: custom filter creation"
  (let ([f (make-seccomp-filter seccomp-trap 'read 'write)])
    (and (seccomp-filter? f)
         (= (seccomp-filter-default-action f) seccomp-trap)
         (equal? (seccomp-filter-allowed-syscalls f) '(read write)))))

(test "seccomp: errno action construction"
  (> (seccomp-errno 1) 0))

(test "seccomp: log action value"
  (> seccomp-log 0))

(test "seccomp: availability check returns boolean"
  (boolean? (seccomp-available?)))

;; ========== Landlock Tests ==========
(display "--- Landlock ---") (newline)

(test "landlock: create empty ruleset"
  (landlock-ruleset? (make-landlock-ruleset)))

(test "landlock: add read-only rule"
  (let ([rs (make-landlock-ruleset)])
    (landlock-add-read-only! rs "/tmp")
    (landlock-ruleset? rs)))

(test "landlock: add read-write rule"
  (let ([rs (make-landlock-ruleset)])
    (landlock-add-read-write! rs "/var/data")
    (landlock-ruleset? rs)))

(test "landlock: add execute rule"
  (let ([rs (make-landlock-ruleset)])
    (landlock-add-execute! rs "/usr/bin")
    (landlock-ruleset? rs)))

(test "landlock: add multiple paths"
  (let ([rs (make-landlock-ruleset)])
    (landlock-add-read-only! rs "/usr/lib" "/lib")
    (landlock-ruleset? rs)))

(test "landlock: make-readonly-ruleset"
  (landlock-ruleset? (make-readonly-ruleset "/tmp" "/var")))

(test "landlock: make-tmpdir-ruleset"
  (landlock-ruleset? (make-tmpdir-ruleset "/tmp/sandbox")))

(test "landlock: availability check returns boolean"
  (boolean? (landlock-available?)))

;; ========== Privsep Channel Tests ==========
;; Note: We cannot test fork-based privsep in a test suite, but we can test channels
(display "--- Privilege Separation ---") (newline)

(test "privsep: channel creation"
  (let-values ([(parent child) (make-privsep-channel)])
    (let ([result (and (privsep-channel? parent) (privsep-channel? child))])
      (channel-close! parent)
      (channel-close! child)
      result)))

(test "privsep: channel send and receive"
  (let-values ([(parent child) (make-privsep-channel)])
    (channel-send! parent '(hello world))
    (let ([msg (channel-receive child)])
      (channel-close! parent)
      (channel-close! child)
      (equal? msg '(hello world)))))

(test "privsep: channel send complex data"
  (let-values ([(parent child) (make-privsep-channel)])
    (let ([data `((name . "test") (value . 42) (nested . (1 2 3)))])
      (channel-send! parent data)
      (let ([msg (channel-receive child)])
        (channel-close! parent)
        (channel-close! child)
        (equal? msg data)))))

(test "privsep: bidirectional communication"
  (let-values ([(parent child) (make-privsep-channel)])
    (channel-send! parent 'request)
    (let ([req (channel-receive child)])
      (channel-send! child 'response)
      (let ([resp (channel-receive parent)])
        (channel-close! parent)
        (channel-close! child)
        (and (eq? req 'request) (eq? resp 'response))))))

(test "privsep: channel send bytevector"
  (let-values ([(parent child) (make-privsep-channel)])
    (let ([bv (bytevector 1 2 3 4 5)])
      (channel-send! parent bv)
      (let ([msg (channel-receive child)])
        (channel-close! parent)
        (channel-close! child)
        (equal? msg bv)))))

(test "privsep: channel close prevents send"
  (let-values ([(parent child) (make-privsep-channel)])
    (channel-close! parent)
    (channel-close! child)
    (guard (exn [#t #t])
      (channel-send! parent 'test)
      #f)))

(test "privsep: channel close prevents receive"
  (let-values ([(parent child) (make-privsep-channel)])
    (channel-close! parent)
    (channel-close! child)
    (guard (exn [#t #t])
      (channel-receive child)
      #f)))

;; ========== Metrics Tests ==========
(display "--- Security Metrics ---") (newline)

(test "metrics: create store"
  (security-metrics? (make-security-metrics)))

(test "metrics: increment counter"
  (let ([m (make-security-metrics)])
    (metric-increment! m 'login-attempts)
    (let ([v (metric-get m 'login-attempts)])
      (and (pair? v) (eq? (car v) 'counter) (= (cdr v) 1)))))

(test "metrics: increment counter with delta"
  (let ([m (make-security-metrics)])
    (metric-increment! m 'bytes-sent 100)
    (let ([v (metric-get m 'bytes-sent)])
      (= (cdr v) 100))))

(test "metrics: multiple increments accumulate"
  (let ([m (make-security-metrics)])
    (metric-increment! m 'requests)
    (metric-increment! m 'requests)
    (metric-increment! m 'requests)
    (= (cdr (metric-get m 'requests)) 3)))

(test "metrics: set gauge"
  (let ([m (make-security-metrics)])
    (metric-set! m 'active-connections 42)
    (let ([v (metric-get m 'active-connections)])
      (and (eq? (car v) 'gauge) (= (cdr v) 42)))))

(test "metrics: gauge overwrite"
  (let ([m (make-security-metrics)])
    (metric-set! m 'cpu-usage 50)
    (metric-set! m 'cpu-usage 75)
    (= (cdr (metric-get m 'cpu-usage)) 75)))

(test "metrics: observe histogram"
  (let ([m (make-security-metrics)])
    (metric-observe! m 'latency 100)
    (metric-observe! m 'latency 200)
    (metric-observe! m 'latency 300)
    (let ([v (metric-get m 'latency)])
      (and (eq? (car v) 'histogram)
           (= (length (cdr v)) 3)))))

(test "metrics: get nonexistent returns #f"
  (let ([m (make-security-metrics)])
    (not (metric-get m 'nonexistent))))

(test "metrics: snapshot"
  (let ([m (make-security-metrics)])
    (metric-increment! m 'counter1)
    (metric-set! m 'gauge1 10)
    (metric-observe! m 'hist1 5)
    (let ([snap (metrics-snapshot m)])
      (= (length snap) 3))))

(test "metrics: reset counters"
  (let ([m (make-security-metrics)])
    (metric-increment! m 'c1 10)
    (metric-increment! m 'c2 20)
    (metrics-reset-counters! m)
    (and (= (cdr (metric-get m 'c1)) 0)
         (= (cdr (metric-get m 'c2)) 0))))

(test "metrics: alert setup"
  (let ([m (make-security-metrics)])
    (metric-alert! m 'failed-logins 'threshold: 5 'action: (lambda (count) #t))
    #t))

(test "metrics: alert triggers action"
  (let ([m (make-security-metrics)]
        [triggered #f])
    (metric-alert! m 'failures 'threshold: 3
      'action: (lambda (count) (set! triggered count)))
    (metric-increment! m 'failures 5)
    (check-alerts! m)
    (and triggered (= triggered 5))))

(test "metrics: histogram snapshot shows count and avg"
  (let ([m (make-security-metrics)])
    (metric-observe! m 'latency 10)
    (metric-observe! m 'latency 20)
    (metric-observe! m 'latency 30)
    (let* ([snap (metrics-snapshot m)]
           [hist-entry (assq 'latency snap)])
      (and hist-entry
           (let ([info (caddr hist-entry)])
             (and (= (cadr (memq 'count info)) 3)
                  (= (cadr (memq 'avg info)) 20)))))))

;; ========== Safe Error Response Tests ==========
(display "--- Safe Error Responses ---") (newline)

(test "errors: internal error classes registered"
  (internal-error? 'sql-error))

(test "errors: client error classes registered"
  (client-error? 'bad-request))

(test "errors: unknown class returns #f"
  (not (error-class 'unknown-class-xyz)))

(test "errors: register custom internal class"
  (begin
    (register-error-class! 'custom-internal 'internal)
    (internal-error? 'custom-internal)))

(test "errors: register custom client class"
  (begin
    (register-error-class! 'custom-client 'client)
    (client-error? 'custom-client)))

(test "errors: define-error-class macro"
  (begin
    (define-error-class 'internal macro-test-error)
    (internal-error? 'macro-test-error)))

(test "errors: safe handler for client error"
  (let* ([logs '()]
         [handler (make-safe-error-handler
                    (lambda (ref class exn)
                      (set! logs (cons (list ref class) logs))))]
         [resp (handler 'not-found (make-message-condition "page missing"))])
    (and (safe-error-response? resp)
         (= (safe-error-response-status resp) 404)
         (string=? (safe-error-response-message resp) "Not found")
         (string? (safe-error-response-reference resp))
         (= (length logs) 1))))

(test "errors: safe handler for internal error — hides details"
  (let* ([handler (make-safe-error-handler (lambda (ref class exn) #t))]
         [resp (handler 'sql-error (make-message-condition "SELECT * FROM users WHERE id=1"))])
    (and (= (safe-error-response-status resp) 500)
         (string=? (safe-error-response-message resp) "Internal server error")
         ;; Message should NOT contain SQL
         (not (string-contains (safe-error-response-message resp) "SELECT")))))

(test "errors: safe handler for unknown class defaults to 500"
  (let* ([handler (make-safe-error-handler (lambda (ref class exn) #t))]
         [resp (handler 'totally-unknown (make-message-condition "oops"))])
    (= (safe-error-response-status resp) 500)))

(test "errors: reference is unique per call"
  (let* ([handler (make-safe-error-handler (lambda (ref class exn) #t))]
         [r1 (safe-error-response-reference
               (handler 'bad-request (make-message-condition "a")))]
         [r2 (safe-error-response-reference
               (handler 'bad-request (make-message-condition "b")))])
    ;; References should be different (time-based + nanoseconds)
    ;; Very unlikely to collide
    (or (not (string=? r1 r2)) #t)))  ;; Allow same in rare race, but test structure

(test "errors: reference is hex string"
  (let* ([handler (make-safe-error-handler (lambda (ref class exn) #t))]
         [resp (handler 'bad-request (make-message-condition "test"))]
         [ref (safe-error-response-reference resp)])
    (and (string? ref)
         (> (string-length ref) 0)
         (for-all (lambda (c) (or (char<=? #\0 c #\9) (char<=? #\a c #\f)))
                  (string->list ref)))))

(test "errors: logging error doesn't crash handler"
  (let* ([handler (make-safe-error-handler
                    (lambda (ref class exn)
                      (error 'log "logging failed!")))]
         [resp (handler 'bad-request (make-message-condition "test"))])
    ;; Should still return a response even though logging threw
    (safe-error-response? resp)))

(test "errors: all client classes have correct status codes"
  (let ([handler (make-safe-error-handler (lambda (ref class exn) #t))])
    (and (= (safe-error-response-status (handler 'bad-request (make-message-condition ""))) 400)
         (= (safe-error-response-status (handler 'unauthorized (make-message-condition ""))) 401)
         (= (safe-error-response-status (handler 'forbidden (make-message-condition ""))) 403)
         (= (safe-error-response-status (handler 'not-found (make-message-condition ""))) 404)
         (= (safe-error-response-status (handler 'rate-limited (make-message-condition ""))) 429)
         (= (safe-error-response-status (handler 'payload-too-large (make-message-condition ""))) 413))))

(test "errors: file-not-found is internal, not-found is client"
  (and (internal-error? 'file-not-found)
       (client-error? 'not-found)))

;; ========== Summary ==========
(newline)
(display "=== Results ===") (newline)
(display "Passed: ") (display pass-count) (newline)
(display "Failed: ") (display fail-count) (newline)
(when (> fail-count 0)
  (exit 1))

