#!chezscheme
;;; (std net fiber-ws) — Fiber-aware WebSocket connections
;;;
;;; Builds on (std net websocket) for frame codec and (std net io) for
;;; fiber-aware TCP I/O. One fiber per WebSocket connection.
;;;
;;; API:
;;;   (make-fiber-ws fd poller open?)        — wrap an upgraded fd (server)
;;;   (fiber-ws? obj)                        — predicate
;;;   (fiber-ws-open? ws)                    — is connection open?
;;;   (fiber-ws-client? ws)                  — is this a client connection?
;;;   (fiber-ws-recv ws)                     — receive message (parks fiber)
;;;                                             returns string, bytevector, or #f
;;;   (fiber-ws-send ws msg)                 — send text message
;;;   (fiber-ws-send-binary ws bv)           — send binary message
;;;   (fiber-ws-close ws)                    — send close frame and shut down
;;;   (fiber-ws-ping ws)                     — send ping (pong auto-handled)
;;;
;;;   (fiber-ws-upgrade req fd poller)       — server-side handshake
;;;   (fiber-ws-connect host port path poller) — client-side handshake
;;;
;;; Per RFC 6455, client→server frames MUST be masked, server→client
;;; frames MUST NOT be. fiber-ws tracks the role and does the right
;;; thing automatically on outbound frames.

(library (std net fiber-ws)
  (export
    make-fiber-ws
    fiber-ws?
    fiber-ws-open?
    fiber-ws-client?
    fiber-ws-recv
    fiber-ws-send
    fiber-ws-send-binary
    fiber-ws-close
    fiber-ws-ping
    fiber-ws-upgrade
    fiber-ws-connect)

  (import (chezscheme)
          (std fiber)
          (std net io)
          (std net websocket))

  ;; ========== Fiber WebSocket record ==========

  (define-record-type fiber-ws
    (fields
      (immutable fd)
      (immutable poller)
      (immutable client?)
      (mutable open?))
    (protocol
      (lambda (new)
        (case-lambda
          [(fd poller open?)         (new fd poller #f open?)]
          [(fd poller client? open?) (new fd poller client? open?)])))
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
  (define (read-ws-frame fd poller)
    (let ([hdr (make-bytevector 2)])
      (let ([n (read-exact fd hdr 2 poller)])
        (if (< n 2) #f
          (let* ([b0 (bytevector-u8-ref hdr 0)]
                 [b1 (bytevector-u8-ref hdr 1)]
                 [fin? (not (zero? (bitwise-and b0 #x80)))]
                 [opcode (bitwise-and b0 #x0F)]
                 [masked? (not (zero? (bitwise-and b1 #x80)))]
                 [len7 (bitwise-and b1 #x7F)])
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
                         (bitwise-ior
                           (bitwise-arithmetic-shift-left (bytevector-u8-ref ext 4) 24)
                           (bitwise-arithmetic-shift-left (bytevector-u8-ref ext 5) 16)
                           (bitwise-arithmetic-shift-left (bytevector-u8-ref ext 6) 8)
                           (bytevector-u8-ref ext 7)))]
                      [else len7])])
              (let ([mask-key (if masked?
                                (let ([mk (make-bytevector 4)])
                                  (read-exact fd mk 4 poller)
                                  mk)
                                #f)])
                (let ([payload (make-bytevector payload-len)])
                  (when (> payload-len 0)
                    (read-exact fd payload payload-len poller))
                  (let ([data (if (and masked? mask-key)
                                (ws-unmask-payload payload mask-key)
                                payload)])
                    (make-ws-frame fin? masked? opcode data mask-key))))))))))

  ;; Generate a 4-byte mask key (required for client-side frames).
  (define (random-mask-key)
    (let ([mk (make-bytevector 4)])
      (do ([i 0 (+ i 1)])
          ((= i 4) mk)
        (bytevector-u8-set! mk i (random 256)))))

  ;; If the connection is client-side, rebuild the frame with masking
  ;; turned on and a fresh random key.
  (define (maybe-mask-frame ws frame)
    (cond
      [(fiber-ws-client? ws)
       (make-ws-frame
         (ws-frame-fin?    frame)
         #t
         (ws-frame-opcode  frame)
         (ws-frame-payload frame)
         (random-mask-key))]
      [else frame]))

  ;; Write a ws-frame over the fd, masking if this is a client connection.
  (define (write-ws-frame-via ws frame)
    (let* ([f       (maybe-mask-frame ws frame)]
           [encoded (ws-frame-encode f)])
      (fiber-tcp-write (fiber-ws-fd ws) encoded
                       (bytevector-length encoded)
                       (fiber-ws-poller ws))))

  ;; ========== Server-side handshake ==========

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
          (make-fiber-ws fd poller #f #t)))))

  ;; ========== Client-side handshake ==========

  ;; Read one CRLF-terminated line from fd. Returns the line WITHOUT
  ;; the trailing \r\n, or #f on EOF/short read.
  (define (read-http-line fd poller)
    (define buf (make-bytevector 4096))
    (define one (make-bytevector 1))
    (let loop ([i 0])
      (cond
        [(>= i 4096) (error 'fiber-ws-connect "HTTP line too long")]
        [else
         (let ([rc (fiber-tcp-read fd one 1 poller)])
           (cond
             [(<= rc 0) #f]
             [else
              (let ([b (bytevector-u8-ref one 0)])
                (bytevector-u8-set! buf i b)
                (cond
                  [(and (>= i 1)
                        (= b #x0a)
                        (= (bytevector-u8-ref buf (- i 1)) #x0d))
                   (let ([line-bv (make-bytevector (- i 1))])
                     (bytevector-copy! buf 0 line-bv 0 (- i 1))
                     (utf8->string line-bv))]
                  [else (loop (+ i 1))]))]))])))

  ;; Lowercase ASCII (good enough for HTTP header names).
  (define (ascii-downcase s)
    (let* ([n (string-length s)] [out (make-string n)])
      (do ([i 0 (+ i 1)])
          ((= i n) out)
        (let ([c (string-ref s i)])
          (string-set! out i
            (if (and (char>=? c #\A) (char<=? c #\Z))
              (integer->char (+ (char->integer c) 32))
              c))))))

  ;; Read HTTP status line + headers until the blank line.
  ;; Returns (values status-int headers-alist) where headers have
  ;; lowercase keys.
  (define (read-http-response fd poller)
    (let ([status-line (read-http-line fd poller)])
      (unless status-line
        (error 'fiber-ws-connect "no HTTP response"))
      (let* ([sp (cond [(string-index status-line #\space) => values]
                       [else (error 'fiber-ws-connect
                                    "malformed status line" status-line)])]
             [rest (substring status-line (+ sp 1) (string-length status-line))]
             [sp2 (cond [(string-index rest #\space) => values]
                        [else (string-length rest)])]
             [code-str (substring rest 0 sp2)]
             [code (or (string->number code-str)
                       (error 'fiber-ws-connect "bad status code" code-str))])
        (let loop ([hdrs '()])
          (let ([line (read-http-line fd poller)])
            (cond
              [(or (not line) (string=? line ""))
               (values code (reverse hdrs))]
              [else
               (let ([colon (string-index line #\:)])
                 (cond
                   [(not colon) (loop hdrs)]
                   [else
                    (let* ([k (ascii-downcase (substring line 0 colon))]
                           [v0 (substring line (+ colon 1) (string-length line))]
                           ;; trim leading spaces
                           [v (let lp ([i 0])
                                (cond
                                  [(>= i (string-length v0)) ""]
                                  [(char=? (string-ref v0 i) #\space)
                                   (lp (+ i 1))]
                                  [else (substring v0 i (string-length v0))]))])
                      (loop (cons (cons k v) hdrs)))]))]))))))

  ;; Find first occurrence of char in string; return index or #f.
  (define (string-index s c)
    (let ([n (string-length s)])
      (let loop ([i 0])
        (cond
          [(>= i n) #f]
          [(char=? (string-ref s i) c) i]
          [else (loop (+ i 1))]))))

  ;; Open a WebSocket client connection.
  ;;   host    — server hostname or IP
  ;;   port    — server port
  ;;   path    — request path (e.g. "/socket")
  ;;   poller  — fiber I/O poller
  ;; Returns a fiber-ws or raises on handshake failure.
  (define (fiber-ws-connect host port path poller)
    (let ([fd (fiber-tcp-connect host port poller)])
      (guard (exn [#t (fiber-tcp-close fd) (raise exn)])
        (let* ([key (ws-handshake-key)]
               [req (string-append
                      "GET " path " HTTP/1.1\r\n"
                      "Host: " host ":"
                      (number->string port) "\r\n"
                      "Upgrade: websocket\r\n"
                      "Connection: Upgrade\r\n"
                      "Sec-WebSocket-Key: " key "\r\n"
                      "Sec-WebSocket-Version: 13\r\n"
                      "\r\n")]
               [req-bv (string->bytevector req (make-transcoder (utf-8-codec)))])
          (fiber-tcp-write fd req-bv (bytevector-length req-bv) poller)
          (let-values ([(status headers) (read-http-response fd poller)])
            (unless (= status 101)
              (error 'fiber-ws-connect "server refused upgrade" status))
            (let ([accept (cond
                            [(assoc "sec-websocket-accept" headers) => cdr]
                            [else (error 'fiber-ws-connect
                                         "missing Sec-WebSocket-Accept")])])
              (unless (ws-handshake-valid? key accept)
                (error 'fiber-ws-connect
                       "Sec-WebSocket-Accept mismatch" accept))
              (make-fiber-ws fd poller #t #t)))))))

  ;; ========== Public API ==========

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
             (guard (exn [#t (void)])
               (write-ws-frame-via ws (ws-close-frame)))
             (fiber-ws-open?-set! ws #f)
             #f]
            [(= opcode ws-opcode-ping)
             (write-ws-frame-via ws (ws-pong-frame payload))
             (fiber-ws-recv ws)]
            [(= opcode ws-opcode-pong)
             (fiber-ws-recv ws)]
            [else
             (fiber-ws-open?-set! ws #f)
             #f])))))

  (define (fiber-ws-send ws msg)
    (unless (fiber-ws-open? ws)
      (error 'fiber-ws-send "WebSocket is closed"))
    (let ([payload (string->bytevector msg (make-transcoder (utf-8-codec)))])
      (write-ws-frame-via ws (ws-text-frame payload))))

  (define (fiber-ws-send-binary ws bv)
    (unless (fiber-ws-open? ws)
      (error 'fiber-ws-send-binary "WebSocket is closed"))
    (write-ws-frame-via ws (ws-binary-frame bv)))

  (define (fiber-ws-ping ws)
    (when (fiber-ws-open? ws)
      (write-ws-frame-via ws (ws-ping-frame (make-bytevector 0)))))

  (define (fiber-ws-close ws)
    (when (fiber-ws-open? ws)
      (guard (exn [#t (void)])
        (write-ws-frame-via ws (ws-close-frame)))
      (fiber-ws-open?-set! ws #f)
      (fiber-tcp-close (fiber-ws-fd ws))))

) ;; end library
