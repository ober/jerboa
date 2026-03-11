#!chezscheme
;;; Tests for (std net websocket) -- WebSocket protocol (RFC 6455)

(import (chezscheme) (std net websocket))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(printf "--- Phase 3b: WebSocket ---~%~%")

;;; ======== Opcode constants ========

(test "opcode-continuation" ws-opcode-continuation 0)
(test "opcode-text"         ws-opcode-text         1)
(test "opcode-binary"       ws-opcode-binary        2)
(test "opcode-close"        ws-opcode-close         8)
(test "opcode-ping"         ws-opcode-ping          9)
(test "opcode-pong"         ws-opcode-pong          10)

;;; ======== Frame construction ========

(test "text-frame-opcode"
  (ws-frame-opcode (ws-text-frame (string->utf8 "hi")))
  ws-opcode-text)

(test "binary-frame-opcode"
  (ws-frame-opcode (ws-binary-frame (make-bytevector 4 0)))
  ws-opcode-binary)

(test "close-frame-opcode"
  (ws-frame-opcode (ws-close-frame))
  ws-opcode-close)

(test "ping-frame-opcode"
  (ws-frame-opcode (ws-ping-frame (string->utf8 "ping")))
  ws-opcode-ping)

(test "pong-frame-opcode"
  (ws-frame-opcode (ws-pong-frame (string->utf8 "pong")))
  ws-opcode-pong)

(test "text-frame-fin"
  (ws-frame-fin? (ws-text-frame (string->utf8 "hello")))
  #t)

(test "text-frame-not-masked"
  (ws-frame-masked? (ws-text-frame (string->utf8 "hello")))
  #f)

;;; ======== Frame encode/decode round-trip ========

(test "encode-decode-text"
  (let* ([payload (string->utf8 "Hello, WebSocket!")]
         [frame   (ws-text-frame payload)]
         [enc     (ws-frame-encode frame)]
         [dec     (ws-frame-decode enc)])
    (utf8->string (ws-frame-payload dec)))
  "Hello, WebSocket!")

(test "encode-decode-fin"
  (let* ([frame (ws-text-frame (string->utf8 "test"))]
         [dec   (ws-frame-decode (ws-frame-encode frame))])
    (ws-frame-fin? dec))
  #t)

(test "encode-decode-opcode"
  (let* ([frame (ws-binary-frame (make-bytevector 3 99))]
         [dec   (ws-frame-decode (ws-frame-encode frame))])
    (ws-frame-opcode dec))
  ws-opcode-binary)

(test "encode-decode-empty-payload"
  (let* ([frame (ws-close-frame)]
         [dec   (ws-frame-decode (ws-frame-encode frame))])
    (bytevector-length (ws-frame-payload dec)))
  0)

;;; ======== Large payload (16-bit extended length) ========

(test "encode-decode-large-payload"
  (let* ([payload (make-bytevector 200 42)]
         [frame   (ws-binary-frame payload)]
         [dec     (ws-frame-decode (ws-frame-encode frame))]
         [got     (ws-frame-payload dec)])
    (and (= (bytevector-length got) 200)
         (= (bytevector-u8-ref got 0) 42)
         (= (bytevector-u8-ref got 199) 42)))
  #t)

;;; ======== Masked frame ========

(test "encode-decode-masked"
  (let* ([mask    (make-bytevector 4)]
         [_ (bytevector-u8-set! mask 0 37)]
         [_ (bytevector-u8-set! mask 1 196)]
         [_ (bytevector-u8-set! mask 2 168)]
         [_ (bytevector-u8-set! mask 3 116)]
         [payload (string->utf8 "masked data")]
         [frame   (make-ws-frame #t #t ws-opcode-text payload mask)]
         [enc     (ws-frame-encode frame)]
         [dec     (ws-frame-decode enc)])
    (utf8->string (ws-frame-payload dec)))
  "masked data")

(test "masked-frame-flag"
  (let* ([mask    (make-bytevector 4 1)]
         [frame   (make-ws-frame #t #t ws-opcode-text (string->utf8 "x") mask)]
         [dec     (ws-frame-decode (ws-frame-encode frame))])
    (ws-frame-masked? dec))
  #t)

;;; ======== Masking/unmasking ========

(test "mask-unmask-roundtrip"
  (let* ([payload  (string->utf8 "Hello")]
         [mask     (make-bytevector 4)]
         [_ (bytevector-u8-set! mask 0 12)]
         [_ (bytevector-u8-set! mask 1 34)]
         [_ (bytevector-u8-set! mask 2 56)]
         [_ (bytevector-u8-set! mask 3 78)]
         [masked   (ws-mask-payload payload mask)]
         [unmasked (ws-unmask-payload masked mask)])
    (equal? payload unmasked))
  #t)

(test "mask-changes-payload"
  (let* ([payload (string->utf8 "A")]
         [mask    (make-bytevector 4 255)]
         [masked  (ws-mask-payload payload mask)])
    ;; 65 XOR 255 = 190
    (bytevector-u8-ref masked 0))
  190)

;;; ======== Handshake ========

(test "handshake-key-not-empty"
  (string? (ws-handshake-key))
  #t)

(test "handshake-accept-rfc-vector"
  (ws-handshake-accept "dGhlIHNhbXBsZSBub25jZQ==")
  "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")

(test "handshake-valid-rfc-vector"
  (ws-handshake-valid? "dGhlIHNhbXBsZSBub25jZQ==" "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
  #t)

(test "handshake-invalid"
  (ws-handshake-valid? "dGhlIHNhbXBsZSBub25jZQ==" "wrongvalue")
  #f)

(test "handshake-key-accept-roundtrip"
  (let ([key (ws-handshake-key)])
    (ws-handshake-valid? key (ws-handshake-accept key)))
  #t)

;;; Summary

(printf "~%WebSocket tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
