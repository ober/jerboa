#!chezscheme
;;; Tests for (std net http2) -- HTTP/2 framing and HPACK

(import (chezscheme) (std net http2))

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

(printf "--- Phase 3b: HTTP/2 ---~%~%")

;;; ======== Frame type constants ========

(test "frame-type-data"          http2-frame-type-data          0)
(test "frame-type-headers"       http2-frame-type-headers        1)
(test "frame-type-settings"      http2-frame-type-settings       4)
(test "frame-type-ping"          http2-frame-type-ping           6)
(test "frame-type-goaway"        http2-frame-type-goaway         7)
(test "frame-type-rst-stream"    http2-frame-type-rst-stream     3)
(test "frame-type-window-update" http2-frame-type-window-update  8)

;;; ======== Data frame encode/decode ========

(test "data-frame-type"
  (let* ([p  (string->utf8 "hello")]
         [f  (make-http2-data-frame 1 p)]
         [d  (http2-frame-decode (http2-frame-encode f))])
    (http2-frame-type d))
  http2-frame-type-data)

(test "data-frame-stream-id"
  (let* ([p (string->utf8 "x")]
         [f (make-http2-data-frame 5 p)]
         [d (http2-frame-decode (http2-frame-encode f))])
    (http2-frame-stream-id d))
  5)

(test "data-frame-payload"
  (let* ([p  (string->utf8 "Hello HTTP/2")]
         [f  (make-http2-data-frame 1 p)]
         [d  (http2-frame-decode (http2-frame-encode f))])
    (utf8->string (http2-frame-payload d)))
  "Hello HTTP/2")

(test "data-frame-frame-size"
  (let* ([p   (make-bytevector 10 0)]
         [f   (make-http2-data-frame 1 p)]
         [enc (http2-frame-encode f)])
    (bytevector-length enc))
  19)  ; 9-byte header + 10-byte payload

;;; ======== Headers frame ========

(test "headers-frame-type"
  (let* ([p (string->utf8 "headers")]
         [f (make-http2-headers-frame 1 p)]
         [d (http2-frame-decode (http2-frame-encode f))])
    (http2-frame-type d))
  http2-frame-type-headers)

(test "headers-frame-stream-id"
  (let* ([p (string->utf8 "h")]
         [f (make-http2-headers-frame 3 p)]
         [d (http2-frame-decode (http2-frame-encode f))])
    (http2-frame-stream-id d))
  3)

;;; ======== Settings frame ========

(test "settings-frame-stream-id-zero"
  (let* ([f (make-http2-settings-frame (make-bytevector 0))]
         [d (http2-frame-decode (http2-frame-encode f))])
    (http2-frame-stream-id d))
  0)

(test "settings-frame-type"
  (let* ([f (make-http2-settings-frame (make-bytevector 0))]
         [d (http2-frame-decode (http2-frame-encode f))])
    (http2-frame-type d))
  http2-frame-type-settings)

;;; ======== Ping frame ========

(test "ping-frame-type"
  (let* ([p (make-bytevector 8 42)]
         [f (make-http2-ping-frame p)]
         [d (http2-frame-decode (http2-frame-encode f))])
    (http2-frame-type d))
  http2-frame-type-ping)

(test "ping-frame-stream-zero"
  (let* ([p (make-bytevector 8 0)]
         [f (make-http2-ping-frame p)]
         [d (http2-frame-decode (http2-frame-encode f))])
    (http2-frame-stream-id d))
  0)

;;; ======== GoAway frame ========

(test "goaway-frame-type"
  (let* ([f (make-http2-goaway-frame 1 0)]
         [d (http2-frame-decode (http2-frame-encode f))])
    (http2-frame-type d))
  http2-frame-type-goaway)

;;; ======== RST_STREAM frame ========

(test "rst-stream-frame-type"
  (let* ([f (make-http2-rst-stream-frame 1 0)]
         [d (http2-frame-decode (http2-frame-encode f))])
    (http2-frame-type d))
  http2-frame-type-rst-stream)

(test "rst-stream-frame-stream-id"
  (let* ([f (make-http2-rst-stream-frame 7 0)]
         [d (http2-frame-decode (http2-frame-encode f))])
    (http2-frame-stream-id d))
  7)

;;; ======== Window update frame ========

(test "window-update-type"
  (let* ([f (make-http2-window-update-frame 0 65535)]
         [d (http2-frame-decode (http2-frame-encode f))])
    (http2-frame-type d))
  http2-frame-type-window-update)

;;; ======== HPACK context ========

(test "hpack-context-type"
  (hpack-context? (make-hpack-context))
  #t)

(test "hpack-context-non-hpack"
  (hpack-context? "not a context")
  #f)

;;; ======== HPACK encode/decode ========

(test "hpack-indexed-method-get"
  (let* ([ctx (make-hpack-context)]
         [enc (hpack-encode ctx (list (cons ":method" "GET")))]
         [dec (hpack-decode ctx enc)])
    (assoc ":method" dec))
  (cons ":method" "GET"))

(test "hpack-indexed-path-slash"
  (let* ([ctx (make-hpack-context)]
         [enc (hpack-encode ctx (list (cons ":path" "/")))]
         [dec (hpack-decode ctx enc)])
    (assoc ":path" dec))
  (cons ":path" "/"))

(test "hpack-literal-header"
  (let* ([ctx (make-hpack-context)]
         [headers (list (cons "x-custom" "value123"))]
         [enc (hpack-encode ctx headers)]
         [dec (hpack-decode ctx enc)])
    (assoc "x-custom" dec))
  (cons "x-custom" "value123"))

(test "hpack-multiple-headers"
  (let* ([ctx (make-hpack-context)]
         [headers (list (cons ":method" "GET") (cons ":path" "/"))]
         [enc (hpack-encode ctx headers)]
         [dec (hpack-decode ctx enc)])
    (length dec))
  2)

;;; Summary

(printf "~%HTTP/2 tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
