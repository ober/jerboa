;;; Test fiber-native HTTP/1.1 server.
;;; Tests Phase 2 of green-wins: fiber-httpd with real TCP connections.

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

;; Helper: send raw HTTP request over a fiber-aware TCP connection
;; and read the full response. Accumulates reads until headers + full body.
(define (http-request-raw fd poller method path body)
  (let* ([body-bv (if body
                    (string->bytevector body (make-transcoder (utf-8-codec)))
                    #f)]
         [req-str (string-append
                    method " " path " HTTP/1.1\r\n"
                    "Host: localhost\r\n"
                    (if body-bv
                      (string-append "Content-Length: "
                        (number->string (bytevector-length body-bv))
                        "\r\n")
                      "")
                    "Connection: close\r\n"
                    "\r\n")]
         [req-bv (string->bytevector req-str (make-transcoder (utf-8-codec)))])
    ;; Send request
    (fiber-tcp-write fd req-bv (bytevector-length req-bv) poller)
    ;; Send body if present
    (when body-bv
      (fiber-tcp-write fd body-bv (bytevector-length body-bv) poller))
    ;; Read response — accumulate into a growing buffer
    (let ([buf (make-bytevector 16384)]
          [tmp (make-bytevector 4096)])
      (let loop ([total 0])
        (let ([n (fiber-tcp-read fd tmp (min 4096 (- 16384 total)) poller)])
          (cond
            [(<= n 0)
             ;; EOF — return accumulated data
             (bytevector->string
               (let ([b (make-bytevector total)])
                 (bytevector-copy! buf 0 b 0 total) b)
               (make-transcoder (utf-8-codec)))]
            [else
             (bytevector-copy! tmp 0 buf total n)
             (let ([new-total (+ total n)])
               ;; Check if we have full headers
               (let ([hdr-end (find-crlf-crlf buf new-total)])
                 (if hdr-end
                   ;; Parse Content-Length and check if body is complete
                   (let ([cl (extract-content-length buf hdr-end)])
                     (if (>= new-total (+ hdr-end (or cl 0)))
                       ;; Full response received
                       (bytevector->string
                         (let ([b (make-bytevector new-total)])
                           (bytevector-copy! buf 0 b 0 new-total) b)
                         (make-transcoder (utf-8-codec)))
                       (loop new-total)))
                   (loop new-total))))])))))) ;; keep reading

;; Find \r\n\r\n in bytevector, return offset after it (start of body)
(define (find-crlf-crlf buf len)
  (let loop ([i 0])
    (cond
      [(> (+ i 3) len) #f]
      [(and (= (bytevector-u8-ref buf i) 13)
            (= (bytevector-u8-ref buf (+ i 1)) 10)
            (= (bytevector-u8-ref buf (+ i 2)) 13)
            (= (bytevector-u8-ref buf (+ i 3)) 10))
       (+ i 4)]
      [else (loop (+ i 1))])))

;; Extract Content-Length value from headers in bytevector
(define (extract-content-length buf header-end)
  (let* ([hdr-str (bytevector->string
                    (let ([b (make-bytevector header-end)])
                      (bytevector-copy! buf 0 b 0 header-end) b)
                    (make-transcoder (utf-8-codec)))]
         [lc (string-downcase hdr-str)])
    (let ([idx (string-search-helper lc "content-length:" 0)])
      (if idx
        (let* ([start (+ idx 15)]  ;; skip "content-length:"
               [end (string-search-helper hdr-str "\r\n" start)])
          (and end (string->number (string-trim-ws (substring hdr-str start end)))))
        0))))

(define (string-trim-ws s)
  (let ([len (string-length s)])
    (let ([start (let loop ([i 0])
                   (if (and (< i len) (char=? (string-ref s i) #\space))
                     (loop (+ i 1)) i))])
      (substring s start len))))

;; Helper: parse response status code from raw response
(define (response-status-code resp)
  (let ([space1 (string-index-helper resp #\space 0)])
    (when space1
      (let ([space2 (string-index-helper resp #\space (+ space1 1))])
        (when space2
          (string->number (substring resp (+ space1 1) space2)))))))

;; Helper: extract response body (after \r\n\r\n)
(define (response-body-text resp)
  (let ([idx (string-search-helper resp "\r\n\r\n" 0)])
    (if idx
      (substring resp (+ idx 4) (string-length resp))
      "")))

(define (string-index-helper s ch start)
  (let loop ([i start])
    (cond
      [(= i (string-length s)) #f]
      [(char=? (string-ref s i) ch) i]
      [else (loop (+ i 1))])))

(define (string-search-helper s needle start)
  (let ([slen (string-length s)]
        [nlen (string-length needle)])
    (let loop ([i start])
      (cond
        [(> (+ i nlen) slen) #f]
        [(string=? (substring s i (+ i nlen)) needle) i]
        [else (loop (+ i 1))]))))

;; =========================================================================
;; Test 1: Request record accessors
;; =========================================================================

(test "request record accessors"
  (let ([req (make-request "GET" "/hello?name=world" "HTTP/1.1"
              '(("host" . "localhost") ("content-type" . "text/plain"))
              "body-data")])
    (assert-equal (request-method req) "GET" "method")
    (assert-equal (request-path req) "/hello?name=world" "path")
    (assert-equal (request-version req) "HTTP/1.1" "version")
    (assert-equal (request-header req "host") "localhost" "header")
    (assert-equal (request-header req "content-type") "text/plain" "ct header")
    (assert-equal (request-header req "missing") #f "missing header")
    (assert-equal (request-body req) "body-data" "body")
    (assert-equal (request-path-only req) "/hello" "path-only")
    (assert-equal (request-query-string req) "name=world" "query-string")))

;; =========================================================================
;; Test 2: Response helpers
;; =========================================================================

(test "response helpers"
  (let ([r1 (respond 200 '(("X-Custom" . "yes")) "ok")])
    (assert-true (response? r1) "is response")
    (assert-equal (response-status r1) 200 "status")
    (assert-equal (response-body r1) "ok" "body"))

  (let ([r2 (respond-text 201 "created")])
    (assert-equal (response-status r2) 201 "text status")
    (assert-equal (response-body r2) "created" "text body"))

  (let ([r3 (respond-json 200 "{\"key\":\"val\"}")])
    (assert-equal (response-status r3) 200 "json status"))

  (let ([r4 (respond-html 200 "<h1>Hi</h1>")])
    (assert-equal (response-status r4) 200 "html status")))

;; =========================================================================
;; Test 3: Router
;; =========================================================================

(test "router dispatch"
  (let ([r (make-router)])
    (route-get r "/" (lambda (req) (respond-text 200 "home")))
    (route-get r "/hello" (lambda (req) (respond-text 200 "hello")))
    (route-post r "/data" (lambda (req) (respond-text 201 "created")))

    ;; Match GET /
    (let ([resp (router-dispatch r (make-request "GET" "/" "HTTP/1.1" '() #f))])
      (assert-equal (response-status resp) 200 "GET / status")
      (assert-equal (response-body resp) "home" "GET / body"))

    ;; Match GET /hello
    (let ([resp (router-dispatch r (make-request "GET" "/hello" "HTTP/1.1" '() #f))])
      (assert-equal (response-status resp) 200 "GET /hello status")
      (assert-equal (response-body resp) "hello" "GET /hello body"))

    ;; Match POST /data
    (let ([resp (router-dispatch r (make-request "POST" "/data" "HTTP/1.1" '() #f))])
      (assert-equal (response-status resp) 201 "POST /data status"))

    ;; 404 for unmatched route
    (let ([resp (router-dispatch r (make-request "GET" "/nope" "HTTP/1.1" '() #f))])
      (assert-equal (response-status resp) 404 "404 status"))))

;; =========================================================================
;; Test 4: Live HTTP server — single request
;; =========================================================================

(test "live HTTP server — single request"
  (let ([rt (make-fiber-runtime 4)])
    (with-io-poller rt poller
      (let-values ([(listen-fd listen-port) (fiber-tcp-listen "127.0.0.1" 0)])
        ;; Server fiber: accept one connection and handle it
        (fiber-spawn rt
          (lambda ()
            (let ([client-fd (fiber-tcp-accept listen-fd poller)])
              ;; Read request
              (let ([buf (make-bytevector 4096)])
                (let ([n (fiber-tcp-read client-fd buf 4096 poller)])
                  ;; Send a simple HTTP response
                  (let* ([resp-body "Hello from fiber-httpd!"]
                         [resp-str (string-append
                                     "HTTP/1.1 200 OK\r\n"
                                     "Content-Length: " (number->string (string-length resp-body)) "\r\n"
                                     "Connection: close\r\n"
                                     "\r\n"
                                     resp-body)]
                         [resp-bv (string->bytevector resp-str (make-transcoder (utf-8-codec)))])
                    (fiber-tcp-write client-fd resp-bv (bytevector-length resp-bv) poller))))
              (fiber-tcp-close client-fd)))
          "test-server")

        ;; Client fiber: connect, send GET, read response
        (fiber-spawn rt
          (lambda ()
            (fiber-sleep 20)
            (let ([fd (fiber-tcp-connect "127.0.0.1" listen-port poller)])
              (let ([resp (http-request-raw fd poller "GET" "/" #f)])
                (assert-true (> (string-length resp) 0) "got response")
                (assert-equal (response-status-code resp) 200 "status 200")
                (assert-equal (response-body-text resp) "Hello from fiber-httpd!"
                  "body matches"))
              (fiber-tcp-close fd)))
          "test-client")

        (fiber-runtime-run! rt)
        (fiber-tcp-close listen-fd)))))

;; =========================================================================
;; Test 5: Full fiber-httpd-start / stop cycle with real HTTP
;; =========================================================================

(test "fiber-httpd-start/stop with real requests"
  (let* ([handler (lambda (req)
                    (cond
                      [(string=? (request-path req) "/ping")
                       (respond-text 200 "pong")]
                      [(string=? (request-path req) "/echo")
                       (respond-text 200 (or (request-body req) ""))]
                      [else
                       (respond-text 404 "not found")]))]
         [srv (fiber-httpd-start 0 handler)]
         [port (fiber-httpd-listen-port srv)])

    ;; Give server a moment to start
    (sleep (make-time 'time-duration 100000000 0))  ;; 100ms

    ;; Use a separate fiber runtime for the client side
    (let ([rt (make-fiber-runtime 2)])
      (with-io-poller rt poller
        ;; Client: GET /ping
        (fiber-spawn rt
          (lambda ()
            (let ([fd (fiber-tcp-connect "127.0.0.1" port poller)])
              (let ([resp (http-request-raw fd poller "GET" "/ping" #f)])
                (assert-equal (response-status-code resp) 200 "/ping status")
                (assert-equal (response-body-text resp) "pong" "/ping body"))
              (fiber-tcp-close fd)))
          "client-ping")

        (fiber-runtime-run! rt)))

    ;; Stop the server
    (fiber-httpd-stop! srv)))

;; =========================================================================
;; Test 6: Multiple concurrent HTTP requests
;; =========================================================================

(test "10 concurrent HTTP requests"
  (let* ([handler (lambda (req)
                    (respond-text 200
                      (string-append "reply-" (request-path req))))]
         [srv (fiber-httpd-start 0 handler)]
         [port (fiber-httpd-listen-port srv)]
         [num-clients 10]
         [results (make-vector num-clients #f)])

    (sleep (make-time 'time-duration 100000000 0))  ;; 100ms

    (let ([rt (make-fiber-runtime 4)])
      (with-io-poller rt poller
        (do ([i 0 (+ i 1)])
          ((= i num-clients))
          (let ([idx i])
            (fiber-spawn rt
              (lambda ()
                (let ([fd (fiber-tcp-connect "127.0.0.1" port poller)])
                  (let ([resp (http-request-raw fd poller "GET"
                                (string-append "/req-" (number->string idx)) #f)])
                    (let ([body (response-body-text resp)])
                      (vector-set! results idx
                        (string=? body (string-append "reply-/req-" (number->string idx))))))
                  (fiber-tcp-close fd)))
              (string-append "client-" (number->string idx)))))

        (fiber-runtime-run! rt)))

    (fiber-httpd-stop! srv)

    ;; Verify all clients got correct responses
    (let ([ok (do ([i 0 (+ i 1)] [c 0 (+ c (if (vector-ref results i) 1 0))])
               ((= i num-clients) c))])
      (assert-equal ok num-clients "all clients got correct responses"))))

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
