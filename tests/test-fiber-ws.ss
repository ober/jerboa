;;; Tests for Phase 5: Fiber-aware WebSocket
;;; Tests handshake, send/recv, ping/pong, close.

(import (chezscheme))
(import (std fiber))
(import (std net io))
(import (std net websocket))
(import (std net fiber-ws))
(import (std net fiber-httpd))
(import (std text base64))
(import (std crypto native-rust))

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

;; Helper: send raw WS upgrade request, read 101 response
(define (ws-client-upgrade fd poller)
  (let* ([ws-key (u8vector->base64-string (rust-random-bytes 16))]
         [req-str (string-append
                    "GET /ws HTTP/1.1\r\n"
                    "Host: localhost\r\n"
                    "Upgrade: websocket\r\n"
                    "Connection: Upgrade\r\n"
                    "Sec-WebSocket-Key: " ws-key "\r\n"
                    "Sec-WebSocket-Version: 13\r\n"
                    "\r\n")]
         [req-bv (string->bytevector req-str (make-transcoder (utf-8-codec)))])
    (fiber-tcp-write fd req-bv (bytevector-length req-bv) poller)
    ;; Read 101 response
    (let ([buf (make-bytevector 4096)])
      (let ([n (fiber-tcp-read fd buf 4096 poller)])
        (> n 0)))))

;; Helper: send a masked text frame (client→server must be masked)
(define (ws-client-send-text fd poller msg)
  (let* ([payload (string->bytevector msg (make-transcoder (utf-8-codec)))]
         [mask-key (rust-random-bytes 4)]
         [frame (make-ws-frame #t #t ws-opcode-text payload mask-key)]
         [encoded (ws-frame-encode frame)])
    (fiber-tcp-write fd encoded (bytevector-length encoded) poller)))

;; Helper: read a server frame and return payload as string
(define (ws-client-recv-text fd poller)
  (let ([buf (make-bytevector 4096)])
    (let ([n (fiber-tcp-read fd buf 4096 poller)])
      (if (<= n 0) #f
        (let* ([bv (let ([b (make-bytevector n)])
                     (bytevector-copy! buf 0 b 0 n) b)]
               [frame (ws-frame-decode bv)])
          (bytevector->string (ws-frame-payload frame)
            (make-transcoder (utf-8-codec))))))))

;; Helper: send masked close frame
(define (ws-client-close fd poller)
  (let* ([frame (make-ws-frame #t #t ws-opcode-close
                  (make-bytevector 0) (rust-random-bytes 4))]
         [encoded (ws-frame-encode frame)])
    (fiber-tcp-write fd encoded (bytevector-length encoded) poller)))

;; Standard WS echo handler for httpd
(define (make-ws-echo-httpd-handler)
  (lambda (req)
    (let ([upgrade (request-header req "upgrade")])
      (if (and upgrade (string=? (string-downcase upgrade) "websocket"))
        (make-websocket-response
          (lambda (fd poller req)
            (let ([ws (fiber-ws-upgrade (request-headers req) fd poller)])
              (when ws
                (let loop ()
                  (let ([msg (fiber-ws-recv ws)])
                    (when msg
                      (if (string? msg)
                        (fiber-ws-send ws msg)
                        (fiber-ws-send-binary ws msg))
                      (loop))))
                (fiber-ws-close ws)))))
        (respond-text 200 "not a websocket")))))

;; =========================================================================
;; Test 1: WebSocket handshake key computation (RFC 6455 test vector)
;; =========================================================================

(test "ws handshake accept key"
  (let ([accept (ws-handshake-accept "dGhlIHNhbXBsZSBub25jZQ==")])
    (assert-equal accept "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" "RFC 6455 test vector")))

;; =========================================================================
;; Test 2: WebSocket frame encode/decode round-trip
;; =========================================================================

(test "ws frame encode/decode round-trip"
  (let* ([payload (string->bytevector "Hello" (make-transcoder (utf-8-codec)))]
         [frame (ws-text-frame payload)]
         [encoded (ws-frame-encode frame)]
         [decoded (ws-frame-decode encoded)])
    (assert-true (ws-frame-fin? decoded) "FIN set")
    (assert-equal (ws-frame-opcode decoded) ws-opcode-text "opcode text")
    (assert-equal (ws-frame-payload decoded) payload "payload matches")))

;; =========================================================================
;; Test 3: Masked frame round-trip
;; =========================================================================

(test "ws masked frame round-trip"
  (let* ([payload (string->bytevector "Masked!" (make-transcoder (utf-8-codec)))]
         [mask-key (make-bytevector 4)])
    (bytevector-u8-set! mask-key 0 #x37)
    (bytevector-u8-set! mask-key 1 #xFA)
    (bytevector-u8-set! mask-key 2 #x21)
    (bytevector-u8-set! mask-key 3 #x3D)
    (let* ([frame (make-ws-frame #t #t ws-opcode-text payload mask-key)]
           [encoded (ws-frame-encode frame)]
           [decoded (ws-frame-decode encoded)])
      (assert-true (ws-frame-masked? decoded) "masked")
      (assert-equal (ws-frame-payload decoded) payload "unmasked correctly"))))

;; =========================================================================
;; Test 4: Full WebSocket echo via fiber-httpd
;; =========================================================================

(test "WebSocket echo through fiber-httpd"
  (let* ([handler (make-ws-echo-httpd-handler)]
         [srv (fiber-httpd-start 0 handler)]
         [port (fiber-httpd-listen-port srv)]
         [result-box (box #f)])

    (sleep (make-time 'time-duration 100000000 0))

    (let ([rt (make-fiber-runtime 2)])
      (with-io-poller rt poller
        (fiber-spawn rt
          (lambda ()
            (let ([fd (fiber-tcp-connect "127.0.0.1" port poller)])
              (ws-client-upgrade fd poller)
              (ws-client-send-text fd poller "hello-ws")
              (let ([reply (ws-client-recv-text fd poller)])
                (set-box! result-box reply))
              (ws-client-close fd poller)
              (fiber-tcp-close fd)))
          "ws-client")
        (fiber-runtime-run! rt)))

    (fiber-httpd-stop! srv)
    (assert-equal (unbox result-box) "hello-ws" "echo round-trip")))

;; =========================================================================
;; Test 5: Multiple WebSocket messages
;; =========================================================================

(test "5 sequential WebSocket messages"
  (let* ([handler (lambda (req)
                    (let ([upgrade (request-header req "upgrade")])
                      (if (and upgrade (string=? (string-downcase upgrade) "websocket"))
                        (make-websocket-response
                          (lambda (fd poller req)
                            (let ([ws (fiber-ws-upgrade (request-headers req) fd poller)])
                              (when ws
                                (let loop ()
                                  (let ([msg (fiber-ws-recv ws)])
                                    (when msg
                                      (fiber-ws-send ws (string-append "echo:" msg))
                                      (loop))))
                                (fiber-ws-close ws)))))
                        (respond-text 200 "http"))))]
         [srv (fiber-httpd-start 0 handler)]
         [port (fiber-httpd-listen-port srv)]
         [results (make-vector 5 #f)])

    (sleep (make-time 'time-duration 100000000 0))

    (let ([rt (make-fiber-runtime 2)])
      (with-io-poller rt poller
        (fiber-spawn rt
          (lambda ()
            (let ([fd (fiber-tcp-connect "127.0.0.1" port poller)])
              (ws-client-upgrade fd poller)
              (do ([i 0 (+ i 1)])
                ((= i 5))
                (let ([msg (string-append "msg-" (number->string i))])
                  (ws-client-send-text fd poller msg)
                  (let ([reply (ws-client-recv-text fd poller)])
                    (vector-set! results i
                      (and reply (string=? reply (string-append "echo:" msg)))))))
              (ws-client-close fd poller)
              (fiber-tcp-close fd)))
          "ws-multi")
        (fiber-runtime-run! rt)))

    (fiber-httpd-stop! srv)

    (do ([i 0 (+ i 1)])
      ((= i 5))
      (assert-true (vector-ref results i)
        (string-append "message " (number->string i))))))

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
