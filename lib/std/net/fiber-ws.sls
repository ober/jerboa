#!chezscheme
;;; (std net fiber-ws) — Fiber-aware WebSocket connections
;;;
;;; Builds on (std net websocket) for frame codec and (std net io) for
;;; fiber-aware TCP I/O. One fiber per WebSocket connection.
;;;
;;; API:
;;;   (make-fiber-ws fd poller)        — wrap an already-upgraded fd
;;;   (fiber-ws? obj)                  — predicate
;;;   (fiber-ws-open? ws)              — is connection open?
;;;   (fiber-ws-recv ws)               — receive message (parks fiber)
;;;                                       returns string, bytevector, or #f (close)
;;;   (fiber-ws-send ws msg)           — send text message
;;;   (fiber-ws-send-binary ws bv)     — send binary message
;;;   (fiber-ws-close ws)              — send close frame and shut down
;;;   (fiber-ws-ping ws)               — send ping (pong auto-handled)
;;;
;;;   (fiber-ws-upgrade req fd poller) — perform WebSocket handshake
;;;                                       req-headers: alist from HTTP request
;;;                                       returns fiber-ws or #f

(library (std net fiber-ws)
  (export
    make-fiber-ws
    fiber-ws?
    fiber-ws-open?
    fiber-ws-recv
    fiber-ws-send
    fiber-ws-send-binary
    fiber-ws-close
    fiber-ws-ping
    fiber-ws-upgrade)

  (import (chezscheme)
          (std fiber)
          (std net io)
          (std net websocket))

  ;; ========== Fiber WebSocket record ==========

  (define-record-type fiber-ws
    (fields
      (immutable fd)
      (immutable poller)
      (mutable open?))
    (sealed #t))

  ;; ========== Low-level I/O ==========

  ;; Read exactly n bytes from fd using fiber-aware I/O.
  (define (read-exact fd buf n poller)
    (let loop ([got 0])
      (if (>= got n) got
        (let* ([remaining (- n got)]
               [tmp (make-bytevector (min 4096 remaining))])
          (let ([rc (fiber-tcp-read fd tmp (min 4096 remaining) poller)])
            (cond
              [(<= rc 0) got]  ;; EOF or error — return partial
              [else
               (bytevector-copy! tmp 0 buf got rc)
               (loop (+ got rc))]))))))

  ;; Read a single WebSocket frame from the fd.
  ;; Returns a ws-frame record or #f on connection close.
  (define (read-ws-frame fd poller)
    ;; Read header: first 2 bytes
    (let ([hdr (make-bytevector 2)])
      (let ([n (read-exact fd hdr 2 poller)])
        (if (< n 2) #f
          (let* ([b0 (bytevector-u8-ref hdr 0)]
                 [b1 (bytevector-u8-ref hdr 1)]
                 [fin? (not (zero? (bitwise-and b0 #x80)))]
                 [opcode (bitwise-and b0 #x0F)]
                 [masked? (not (zero? (bitwise-and b1 #x80)))]
                 [len7 (bitwise-and b1 #x7F)])
            ;; Extended length
            (let ([payload-len
                    (cond
                      [(= len7 126)
                       (let ([ext (make-bytevector 2)])
                         (when (< (read-exact fd ext 2 poller) 2) (void))
                         (bitwise-ior
                           (bitwise-arithmetic-shift-left (bytevector-u8-ref ext 0) 8)
                           (bytevector-u8-ref ext 1)))]
                      [(= len7 127)
                       (let ([ext (make-bytevector 8)])
                         (when (< (read-exact fd ext 8 poller) 8) (void))
                         ;; Use lower 32 bits
                         (bitwise-ior
                           (bitwise-arithmetic-shift-left (bytevector-u8-ref ext 4) 24)
                           (bitwise-arithmetic-shift-left (bytevector-u8-ref ext 5) 16)
                           (bitwise-arithmetic-shift-left (bytevector-u8-ref ext 6) 8)
                           (bytevector-u8-ref ext 7)))]
                      [else len7])])
              ;; Masking key
              (let ([mask-key (if masked?
                                (let ([mk (make-bytevector 4)])
                                  (read-exact fd mk 4 poller)
                                  mk)
                                #f)])
                ;; Payload
                (let ([payload (make-bytevector payload-len)])
                  (when (> payload-len 0)
                    (read-exact fd payload payload-len poller))
                  ;; Unmask if needed
                  (let ([data (if (and masked? mask-key)
                                (ws-unmask-payload payload mask-key)
                                payload)])
                    (make-ws-frame fin? masked? opcode data mask-key))))))))))

  ;; Write a ws-frame over the fd.
  (define (write-ws-frame fd poller frame)
    (let ([encoded (ws-frame-encode frame)])
      (fiber-tcp-write fd encoded (bytevector-length encoded) poller)))

  ;; ========== WebSocket upgrade handshake ==========

  ;; Perform the server-side WebSocket handshake.
  ;; req-headers: alist of (lowercase-name . value) from the HTTP request
  ;; Returns: fiber-ws record, or #f on failure
  (define (fiber-ws-upgrade req-headers fd poller)
    (let ([ws-key (cond [(assoc "sec-websocket-key" req-headers) => cdr]
                        [else #f])])
      (if (not ws-key)
        #f
        (let* ([accept-key (ws-handshake-accept ws-key)]
               [resp-str (string-append
                           "HTTP/1.1 101 Switching Protocols\r\n"
                           "Upgrade: websocket\r\n"
                           "Connection: Upgrade\r\n"
                           "Sec-WebSocket-Accept: " accept-key "\r\n"
                           "\r\n")]
               [resp-bv (string->bytevector resp-str (make-transcoder (utf-8-codec)))])
          (fiber-tcp-write fd resp-bv (bytevector-length resp-bv) poller)
          (make-fiber-ws fd poller #t)))))

  ;; ========== Public API ==========

  ;; Receive a message. Parks the fiber until a frame arrives.
  ;; Returns: string (text), bytevector (binary), or #f (close/error).
  (define (fiber-ws-recv ws)
    (unless (fiber-ws-open? ws)
      (error 'fiber-ws-recv "WebSocket is closed"))
    (let ([frame (read-ws-frame (fiber-ws-fd ws) (fiber-ws-poller ws))])
      (if (not frame)
        (begin (fiber-ws-open?-set! ws #f) #f)
        (let ([opcode (ws-frame-opcode frame)]
              [payload (ws-frame-payload frame)])
          (cond
            [(= opcode ws-opcode-text)
             (bytevector->string payload (make-transcoder (utf-8-codec)))]
            [(= opcode ws-opcode-binary) payload]
            [(= opcode ws-opcode-close)
             ;; Send close back
             (guard (exn [#t (void)])
               (write-ws-frame (fiber-ws-fd ws) (fiber-ws-poller ws) (ws-close-frame)))
             (fiber-ws-open?-set! ws #f)
             #f]
            [(= opcode ws-opcode-ping)
             ;; Auto-pong
             (write-ws-frame (fiber-ws-fd ws) (fiber-ws-poller ws)
               (ws-pong-frame payload))
             (fiber-ws-recv ws)]
            [(= opcode ws-opcode-pong)
             ;; Ignore, keep receiving
             (fiber-ws-recv ws)]
            [else
             ;; Unknown opcode
             (fiber-ws-open?-set! ws #f)
             #f])))))

  ;; Send a text message.
  (define (fiber-ws-send ws msg)
    (unless (fiber-ws-open? ws)
      (error 'fiber-ws-send "WebSocket is closed"))
    (let ([payload (string->bytevector msg (make-transcoder (utf-8-codec)))])
      (write-ws-frame (fiber-ws-fd ws) (fiber-ws-poller ws)
        (ws-text-frame payload))))

  ;; Send a binary message.
  (define (fiber-ws-send-binary ws bv)
    (unless (fiber-ws-open? ws)
      (error 'fiber-ws-send-binary "WebSocket is closed"))
    (write-ws-frame (fiber-ws-fd ws) (fiber-ws-poller ws)
      (ws-binary-frame bv)))

  ;; Send a ping frame.
  (define (fiber-ws-ping ws)
    (when (fiber-ws-open? ws)
      (write-ws-frame (fiber-ws-fd ws) (fiber-ws-poller ws)
        (ws-ping-frame (make-bytevector 0)))))

  ;; Close the WebSocket gracefully.
  (define (fiber-ws-close ws)
    (when (fiber-ws-open? ws)
      (guard (exn [#t (void)])
        (write-ws-frame (fiber-ws-fd ws) (fiber-ws-poller ws) (ws-close-frame)))
      (fiber-ws-open?-set! ws #f)
      (fiber-tcp-close (fiber-ws-fd ws))))

) ;; end library
