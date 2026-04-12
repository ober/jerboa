;;; Tests for Phase 4: Production hardening
;;; Tests semaphore, metrics, health check, and max-connections.

(import (chezscheme))
(import (std fiber))
(import (std net io))
(import (std net fiber-httpd))

(define test-count 0)
(define pass-count 0)

(define-syntax test
  (syntax-rules ()
    [(_ name body ...)
     (begin
       (set! test-count (+ test-count 1))
       (guard (exn [#t
         (display "FAIL: ") (display name) (newline)
         (display "  Error: ")
         (display (if (message-condition? exn) (condition-message exn) exn))
         (newline)])
         body ...
         (set! pass-count (+ pass-count 1))
         (display "PASS: ") (display name) (newline)))]))

(define-syntax assert-equal
  (syntax-rules ()
    [(_ got expected msg)
     (unless (equal? got expected)
       (error 'assert msg (list 'got: got 'expected: expected)))]))

(define-syntax assert-true
  (syntax-rules ()
    [(_ val msg)
     (unless val (error 'assert msg))]))

;; Helper: simple single-read HTTP request
(define (http-get fd poller path)
  (let* ([req-str (string-append
                    "GET " path " HTTP/1.1\r\n"
                    "Host: localhost\r\nConnection: close\r\n\r\n")]
         [req-bv (string->bytevector req-str (make-transcoder (utf-8-codec)))])
    (fiber-tcp-write fd req-bv (bytevector-length req-bv) poller)
    (let ([buf (make-bytevector 8192)]
          [tmp (make-bytevector 4096)])
      (let loop ([total 0])
        (let ([n (fiber-tcp-read fd tmp (min 4096 (- 8192 total)) poller)])
          (cond
            [(<= n 0)
             (bytevector->string
               (let ([b (make-bytevector total)])
                 (bytevector-copy! buf 0 b 0 total) b)
               (make-transcoder (utf-8-codec)))]
            [else
             (bytevector-copy! tmp 0 buf total n)
             (loop (+ total n))]))))))

(define (response-body-text resp)
  (let ([idx (string-search-raw resp "\r\n\r\n" 0)])
    (if idx
      (substring resp (+ idx 4) (string-length resp))
      "")))

(define (response-status-code resp)
  (let ([sp1 (string-index-raw resp #\space 0)])
    (and sp1
      (let ([sp2 (string-index-raw resp #\space (+ sp1 1))])
        (and sp2 (string->number (substring resp (+ sp1 1) sp2)))))))

(define (string-search-raw s needle start)
  (let ([slen (string-length s)]
        [nlen (string-length needle)])
    (let loop ([i start])
      (cond
        [(> (+ i nlen) slen) #f]
        [(string=? (substring s i (+ i nlen)) needle) i]
        [else (loop (+ i 1))]))))

(define (string-index-raw s ch start)
  (let loop ([i start])
    (cond
      [(= i (string-length s)) #f]
      [(char=? (string-ref s i) ch) i]
      [else (loop (+ i 1))])))

;; =========================================================================
;; Test 1: Fiber semaphore — basic acquire/release
;; =========================================================================

(test "semaphore: basic acquire/release"
  (let ([rt (make-fiber-runtime 2)]
        [sem (make-fiber-semaphore 2)]
        [results (make-vector 3 #f)])
    (fiber-spawn rt
      (lambda ()
        (fiber-semaphore-acquire! sem)
        (vector-set! results 0 #t)
        (fiber-semaphore-release! sem))
      "f1")
    (fiber-spawn rt
      (lambda ()
        (fiber-semaphore-acquire! sem)
        (vector-set! results 1 #t)
        (fiber-semaphore-release! sem))
      "f2")
    (fiber-spawn rt
      (lambda ()
        (fiber-semaphore-acquire! sem)
        (vector-set! results 2 #t)
        (fiber-semaphore-release! sem))
      "f3")
    (fiber-runtime-run! rt)
    (assert-true (vector-ref results 0) "fiber 1 ran")
    (assert-true (vector-ref results 1) "fiber 2 ran")
    (assert-true (vector-ref results 2) "fiber 3 ran")))

;; =========================================================================
;; Test 2: Fiber semaphore — try-acquire
;; =========================================================================

(test "semaphore: try-acquire"
  (let ([rt (make-fiber-runtime 2)]
        [sem (make-fiber-semaphore 1)]
        [r1 (box #f)]
        [r2 (box #f)])
    (fiber-spawn rt
      (lambda ()
        ;; First acquire should succeed
        (set-box! r1 (fiber-semaphore-try-acquire! sem))
        ;; Second should fail (only 1 permit)
        (set-box! r2 (fiber-semaphore-try-acquire! sem))
        (fiber-semaphore-release! sem))
      "try-fiber")
    (fiber-runtime-run! rt)
    (assert-true (unbox r1) "first try-acquire succeeds")
    (assert-true (not (unbox r2)) "second try-acquire fails")))

;; =========================================================================
;; Test 3: Metrics tracking
;; =========================================================================

(test "metrics: connections and requests tracked"
  (let* ([handler (lambda (req) (respond-text 200 "ok"))]
         [srv (fiber-httpd-start 0 handler)]
         [port (fiber-httpd-listen-port srv)]
         [m (fiber-httpd-metrics srv)])

    (sleep (make-time 'time-duration 100000000 0))

    ;; Send 3 requests
    (let ([rt (make-fiber-runtime 2)])
      (with-io-poller rt poller
        (do ([i 0 (+ i 1)])
          ((= i 3))
          (fiber-spawn rt
            (lambda ()
              (let ([fd (fiber-tcp-connect "127.0.0.1" port poller)])
                (http-get fd poller "/test")
                (fiber-tcp-close fd)))
            (string-append "req-" (number->string i))))
        (fiber-runtime-run! rt)))

    ;; Give server time to process
    (sleep (make-time 'time-duration 100000000 0))

    (let ([total (httpd-metrics-connections-total m)]
          [reqs (httpd-metrics-requests-total m)])
      (fiber-httpd-stop! srv)
      (assert-equal total 3 "3 connections total")
      (assert-equal reqs 3 "3 requests total"))))

;; =========================================================================
;; Test 4: Health check endpoint
;; =========================================================================

(test "health check endpoint"
  (let* ([base-handler (lambda (req) (respond-text 200 "app"))]
         [srv (fiber-httpd-start 0 base-handler)]
         [port (fiber-httpd-listen-port srv)]
         [wrapped (wrap-health-check base-handler srv)])
    ;; Note: wrap-health-check returns a new handler, but we need to start
    ;; the server with it. For this test, start a new server with wrapped handler.
    (fiber-httpd-stop! srv)

    (let* ([srv2 (fiber-httpd-start 0 (wrap-health-check base-handler srv))])
      ;; Actually the srv reference is for the old server — metrics won't match.
      ;; Let me just verify the wrap works by calling it directly.
      (fiber-httpd-stop! srv2))

    ;; Test the handler function directly
    (let ([health-req (make-request "GET" "/health" "HTTP/1.1" '() #f)]
          [app-req (make-request "GET" "/app" "HTTP/1.1" '() #f)])
      ;; Health check response
      (let ([resp (wrapped health-req)])
        (assert-equal (response-status resp) 200 "health status 200")
        (assert-true (string? (response-body resp)) "health body is string"))
      ;; Regular request
      (let ([resp (wrapped app-req)])
        (assert-equal (response-body resp) "app" "regular handler works")))))

;; =========================================================================
;; Test 5: Metrics endpoint
;; =========================================================================

(test "metrics endpoint"
  (let* ([handler (lambda (req) (respond-text 200 "ok"))]
         [srv (fiber-httpd-start 0 handler)]
         [wrapped (wrap-metrics-endpoint handler srv)])
    (fiber-httpd-stop! srv)

    (let ([metrics-req (make-request "GET" "/metrics" "HTTP/1.1" '() #f)])
      (let ([resp (wrapped metrics-req)])
        (assert-equal (response-status resp) 200 "metrics status 200")
        (let ([body (response-body resp)])
          (assert-true (string? body) "metrics body is string")
          (assert-true (> (string-length body) 0) "metrics body non-empty"))))))

;; =========================================================================
;; Test 6: Max connections (admission control)
;; =========================================================================

(test "max-connections admission control"
  (let* ([handler (lambda (req)
                    ;; Slow handler — holds the connection
                    (fiber-sleep 50)
                    (respond-text 200 "ok"))]
         [srv (fiber-httpd-start* 0 handler 3)]  ;; max 3 concurrent
         [port (fiber-httpd-listen-port srv)])

    (sleep (make-time 'time-duration 100000000 0))

    ;; Send 5 requests — only 3 should be active simultaneously
    (let ([rt (make-fiber-runtime 4)]
          [results (make-vector 5 #f)])
      (with-io-poller rt poller
        (do ([i 0 (+ i 1)])
          ((= i 5))
          (let ([idx i])
            (fiber-spawn rt
              (lambda ()
                (let ([fd (fiber-tcp-connect "127.0.0.1" port poller)])
                  (let ([resp (http-get fd poller "/slow")])
                    (vector-set! results idx
                      (= (response-status-code resp) 200)))
                  (fiber-tcp-close fd)))
              (string-append "slow-" (number->string idx)))))
        (fiber-runtime-run! rt))

      ;; All 5 should eventually complete (just not all at once)
      (fiber-httpd-stop! srv)
      (let ([ok (do ([i 0 (+ i 1)] [c 0 (+ c (if (vector-ref results i) 1 0))])
                 ((= i 5) c))])
        (assert-equal ok 5 "all 5 eventually served")))))

;; =========================================================================
;; Summary
;; =========================================================================
(newline)
(display "=========================================") (newline)
(display "Results: ") (display pass-count) (display "/")
(display test-count) (display " passed") (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
