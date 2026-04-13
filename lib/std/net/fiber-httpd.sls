#!chezscheme
;;; (std net fiber-httpd) — Fiber-Native HTTP/1.1 Server
;;;
;;; One fiber per connection, epoll-backed accept loop.
;;; Zero external dependencies — pure Scheme HTTP parser.
;;;
;;; API:
;;;   (fiber-httpd-start port handler)     — start server, returns control record
;;;   (fiber-httpd-start* opts handler)    — start with options
;;;   (fiber-httpd-stop! server)           — graceful shutdown
;;;
;;;   handler: (lambda (req) ...) → response
;;;   request:  (method path version headers body)
;;;   response: (status headers body)
;;;
;;;   (make-request method path version headers body)
;;;   (request-method req) (request-path req) (request-version req)
;;;   (request-headers req) (request-body req)
;;;   (request-header req name)
;;;
;;;   (respond status headers body)
;;;   (respond-text status text)
;;;   (respond-json status json-string)
;;;
;;;   (make-router) (router-add! r method path handler) (router-dispatch r req)
;;;   (GET path handler) (POST path handler) ...

(library (std net fiber-httpd)
  (export
    ;; Server lifecycle
    fiber-httpd-start
    fiber-httpd-start*
    fiber-httpd-stop!
    fiber-httpd?
    fiber-httpd-listen-port

    ;; Request record
    make-request request? request-method request-path request-version
    request-headers request-body request-header
    request-query-string request-path-only

    ;; Response helpers
    respond respond-text respond-json respond-html
    response? response-status response-headers response-body

    ;; Router
    make-router router-add! router-dispatch
    route-get route-post route-put route-delete
    route-param current-route-params

    ;; Metrics / production
    fiber-httpd-metrics
    httpd-metrics?
    httpd-metrics-connections-active
    httpd-metrics-connections-total
    httpd-metrics-requests-total
    httpd-metrics-errors-total
    httpd-metrics-start-time

    ;; Middleware
    wrap-health-check
    wrap-metrics-endpoint

    ;; WebSocket integration
    make-websocket-response
    websocket-response?
    websocket-response-handler)

  (import (chezscheme)
          (std fiber)
          (std net io))

  ;; ========== FFI: Rust HTTP parser ==========
  ;; jerboa_http_parse is in libjerboa_native.so (loaded by epoll-native via io)

  (define c-http-parse
    (foreign-procedure "jerboa_http_parse" (u8* size_t u8*) int))

  ;; Parse-out buffer layout (270 bytes):
  ;; [0-3]   i32 status  (>0=header_end, 0=partial, -1=error)
  ;; [4-5]   u16 method_start   [6-7]  u16 method_len
  ;; [8-9]   u16 path_start     [10-11] u16 path_len
  ;; [12]    u8  version        [13]    u8  nheaders
  ;; [14..270] 32 * [name_start:u16, name_len:u16, val_start:u16, val_len:u16]

  ;; ========== Request record ==========

  (define-record-type request
    (fields method path version headers body)
    (sealed #t))

  (define (request-header req name)
    (let ([entry (assoc name (request-headers req))])
      (and entry (cdr entry))))

  (define (request-path-only req)
    (let ([p (request-path req)])
      (let ([idx (string-index p #\?)])
        (if idx (substring p 0 idx) p))))

  (define (request-query-string req)
    (let ([p (request-path req)])
      (let ([idx (string-index p #\?)])
        (if idx (substring p (+ idx 1) (string-length p)) ""))))

  (define (string-index s ch)
    (let loop ([i 0])
      (cond
        [(= i (string-length s)) #f]
        [(char=? (string-ref s i) ch) i]
        [else (loop (+ i 1))])))

  ;; ========== Response record ==========

  (define-record-type response
    (fields status headers body)
    (sealed #t))

  (define (respond status headers body)
    (make-response status headers body))

  (define (respond-text status text)
    (make-response status
      '(("Content-Type" . "text/plain; charset=utf-8"))
      text))

  (define (respond-json status json-str)
    (make-response status
      '(("Content-Type" . "application/json"))
      json-str))

  (define (respond-html status html)
    (make-response status
      '(("Content-Type" . "text/html; charset=utf-8"))
      html))

  ;; ========== WebSocket response ==========
  ;;
  ;; When a handler returns a websocket-response, the connection handler
  ;; performs the WebSocket handshake and calls the ws-handler with
  ;; (fd poller req) so it can create a fiber-ws and run a WS loop.
  ;; The handler proc receives (fd poller req).

  (define-record-type websocket-response
    (fields (immutable handler))   ;; (lambda (fd poller req) ...)
    (sealed #t))

  ;; ========== HTTP Parser (Rust-backed) ==========
  ;;
  ;; Reads HTTP/1.1 requests using the Rust httparse crate for header parsing.
  ;; hdr-buf (8192 bytes) and parse-out (270 bytes) are per-connection allocations
  ;; passed in from handle-connection — zero per-request allocation on the hot path.

  (define *max-header-size* 8192)
  (define *max-body-size*   (* 10 1024 1024))  ;; 10MB

  ;; Extract a sub-bytevector [start, start+len)
  (define (bv-sub bv start len)
    (let ([out (make-bytevector len)])
      (bytevector-copy! bv start out 0 len)
      out))

  ;; Read the body using Content-Length, using bytes already buffered after header_end.
  (define (read-body fd poller hdr-buf header-end filled content-length)
    (if (or (not content-length) (= content-length 0))
      #f
      (let* ([already-have (- filled header-end)]
             [body-buf (make-bytevector content-length)])
        (when (> already-have 0)
          (bytevector-copy! hdr-buf header-end body-buf 0
            (min already-have content-length)))
        (let loop ([got already-have])
          (when (< got content-length)
            (let ([tmp (make-bytevector (min 4096 (- content-length got)))])
              (let ([n (fiber-tcp-read fd tmp
                         (min 4096 (- content-length got)) poller)])
                (when (> n 0)
                  (bytevector-copy! tmp 0 body-buf got n)
                  (loop (+ got n)))))))
        (utf8->string body-buf))))

  ;; Build alist of (lowercase-name . value) pairs from parse-out offsets into hdr-buf.
  (define (extract-headers hdr-buf parse-out nhdrs)
    (let loop ([i 0] [acc '()])
      (if (fx>= i nhdrs)
        (reverse acc)
        (let* ([base (fx+ 14 (fx* i 8))]
               [ns   (bytevector-u16-native-ref parse-out base)]
               [nl   (bytevector-u16-native-ref parse-out (fx+ base 2))]
               [vs   (bytevector-u16-native-ref parse-out (fx+ base 4))]
               [vl   (bytevector-u16-native-ref parse-out (fx+ base 6))]
               [name (string-downcase (utf8->string (bv-sub hdr-buf ns nl)))]
               [val  (utf8->string (bv-sub hdr-buf vs vl))])
          (loop (fx+ i 1) (cons (cons name val) acc))))))

  ;; Read a full HTTP/1.1 request. hdr-buf (8192) and parse-out (270) are
  ;; caller-provided per-connection buffers — no allocation on the common path.
  (define (read-request fd poller hdr-buf parse-out)
    (let ([tmp (make-bytevector 4096)])
      (let loop ([filled 0])
        (if (>= filled *max-header-size*)
          #f
          (let ([n (fiber-tcp-read fd tmp
                     (min 4096 (- *max-header-size* filled))
                     poller)])
            (cond
              [(<= n 0) #f]  ;; EOF / error
              [else
               (bytevector-copy! tmp 0 hdr-buf filled n)
               (let ([total (+ filled n)])
                 (c-http-parse hdr-buf total parse-out)
                 (let ([status (bytevector-s32-native-ref parse-out 0)])
                   (cond
                     ;; Complete — status is the header_end byte offset
                     [(> status 0)
                      (let* ([header-end status]
                             [ms    (bytevector-u16-native-ref parse-out 4)]
                             [ml    (bytevector-u16-native-ref parse-out 6)]
                             [ps    (bytevector-u16-native-ref parse-out 8)]
                             [pl    (bytevector-u16-native-ref parse-out 10)]
                             [nhdrs (bytevector-u8-ref parse-out 13)]
                             [method  (utf8->string (bv-sub hdr-buf ms ml))]
                             [path    (utf8->string (bv-sub hdr-buf ps pl))]
                             [headers (extract-headers hdr-buf parse-out nhdrs)]
                             [cl-str  (let ([e (assoc "content-length" headers)])
                                        (and e (cdr e)))]
                             [cl      (and cl-str (string->number cl-str))]
                             [body    (read-body fd poller hdr-buf header-end total cl)])
                        (make-request method path "HTTP/1.1" headers body))]
                     ;; Partial — need more data
                     [(= status 0) (loop total)]
                     ;; Parse error
                     [else #f])))]))))))

  ;; ========== HTTP Response Writer ==========

  (define (status-text code)
    (case code
      [(200) "OK"] [(201) "Created"] [(202) "Accepted"]
      [(204) "No Content"]
      [(301) "Moved Permanently"] [(302) "Found"] [(304) "Not Modified"]
      [(400) "Bad Request"] [(401) "Unauthorized"] [(403) "Forbidden"]
      [(404) "Not Found"] [(405) "Method Not Allowed"]
      [(409) "Conflict"]
      [(500) "Internal Server Error"] [(502) "Bad Gateway"]
      [(503) "Service Unavailable"] [(504) "Gateway Timeout"]
      [else "Unknown"]))

  ;; ========== HTTP Response Writer (pre-allocated buffer + writev) ==========
  ;;
  ;; Writes response headers directly into a caller-provided bytevector
  ;; (no string allocation), then sends headers+body in one writev syscall.

  ;; Write decimal integer n into bv at pos. Returns new pos.
  (define (write-decimal! bv pos n)
    (if (fx= n 0)
      (begin (bytevector-u8-set! bv pos 48) (fx+ pos 1))
      (let* ([s (number->string n)]
             [len (string-length s)])
        (do ([i 0 (fx+ i 1)]) ((fx= i len))
          (bytevector-u8-set! bv (fx+ pos i)
            (char->integer (string-ref s i))))
        (fx+ pos len))))

  ;; Write ASCII string s into bv at pos. Returns new pos.
  (define (write-ascii! bv pos s)
    (let ([len (string-length s)])
      (do ([i 0 (fx+ i 1)]) ((fx= i len))
        (bytevector-u8-set! bv (fx+ pos i)
          (char->integer (string-ref s i))))
      (fx+ pos len)))

  ;; Write CRLF at pos. Returns new pos.
  (define (write-crlf! bv pos)
    (bytevector-u8-set! bv pos 13)
    (bytevector-u8-set! bv (fx+ pos 1) 10)
    (fx+ pos 2))

  ;; Fill resp-buf with the HTTP status line + headers block (no body).
  ;; Returns number of bytes written.
  (define (fill-response-headers! resp-buf status headers body-len)
    (let* ([pos (write-ascii! resp-buf 0 "HTTP/1.1 ")]
           [pos (write-decimal! resp-buf pos status)]
           [pos (begin (bytevector-u8-set! resp-buf pos 32) (fx+ pos 1))]
           [pos (write-ascii! resp-buf pos (status-text status))]
           [pos (write-crlf! resp-buf pos)]
           [pos (write-ascii! resp-buf pos "Content-Length: ")]
           [pos (write-decimal! resp-buf pos body-len)]
           [pos (write-crlf! resp-buf pos)]
           [pos (let lp ([hs headers] [p pos])
                  (if (null? hs) p
                    (let* ([h (car hs)]
                           [p (write-ascii! resp-buf p (car h))]
                           [p (begin (bytevector-u8-set! resp-buf p 58)
                                     (bytevector-u8-set! resp-buf (fx+ p 1) 32)
                                     (fx+ p 2))]
                           [p (write-ascii! resp-buf p (cdr h))]
                           [p (write-crlf! resp-buf p)])
                      (lp (cdr hs) p))))]
           [pos (write-crlf! resp-buf pos)])
      pos))

  ;; Write response: fills resp-buf with headers, sends headers+body via writev2.
  ;; resp-buf is a per-connection 4096-byte buffer (from handle-connection).
  (define (write-response fd poller resp resp-buf)
    (let* ([status   (response-status resp)]
           [headers  (response-headers resp)]
           [body     (response-body resp)]
           [body-bv  (cond
                       [(not body) #f]
                       [(string? body)
                        (string->bytevector body (make-transcoder (utf-8-codec)))]
                       [(bytevector? body) body]
                       [else (string->bytevector (format "~a" body)
                               (make-transcoder (utf-8-codec)))])]
           [body-len (if body-bv (bytevector-length body-bv) 0)]
           [hdr-len  (fill-response-headers! resp-buf status headers body-len)])
      (fiber-tcp-writev2 fd resp-buf hdr-len body-bv poller)))

  ;; ========== Router ==========

  (define-record-type router
    (fields (mutable routes))  ;; list of (method path-pattern handler)
    (protocol
      (lambda (new) (lambda () (new '())))))

  (define (router-add! r method path handler)
    (router-routes-set! r
      (cons (list method path handler) (router-routes r))))

  ;; Path parameter matching: /hooks/:type matches /hooks/payment
  ;; Returns alist of (name . value) on match, #f on mismatch.

  (define (split-path-segments p)
    (let ([segs (split-on-slash p)])
      (if (and (not (null? segs)) (string=? (car segs) ""))
        (cdr segs) segs)))

  (define (split-on-slash s)
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(= i (string-length s))
         (reverse (cons (substring s start i) acc))]
        [(char=? (string-ref s i) #\/)
         (loop (+ i 1) (+ i 1) (cons (substring s start i) acc))]
        [else (loop (+ i 1) start acc)])))

  (define (match-path-pattern pattern path)
    (if (string=? pattern "*")
      '()
      (let ([pat-segs (split-path-segments pattern)]
            [path-segs (split-path-segments path)])
        (and (= (length pat-segs) (length path-segs))
             (let loop ([ps pat-segs] [xs path-segs] [params '()])
               (cond
                 [(null? ps) (reverse params)]
                 [(and (> (string-length (car ps)) 0)
                       (char=? (string-ref (car ps) 0) #\:))
                  (loop (cdr ps) (cdr xs)
                    (cons (cons (substring (car ps) 1 (string-length (car ps)))
                                (car xs))
                          params))]
                 [(string=? (car ps) (car xs))
                  (loop (cdr ps) (cdr xs) params)]
                 [else #f]))))))

  (define current-route-params (make-parameter '()))

  (define (route-param req name)
    (let ([entry (assoc name (current-route-params))])
      (and entry (cdr entry))))

  (define (router-dispatch r req)
    (let ([method (request-method req)]
          [path (request-path-only req)])
      (let loop ([routes (router-routes r)])
        (if (null? routes)
          (respond-text 404 "Not Found")
          (let* ([route (car routes)]
                 [params (and (string=? (car route) method)
                              (match-path-pattern (cadr route) path))])
            (if params
              (parameterize ([current-route-params params])
                ((caddr route) req))
              (loop (cdr routes))))))))

  ;; Convenience route adders
  (define (route-get r path handler) (router-add! r "GET" path handler))
  (define (route-post r path handler) (router-add! r "POST" path handler))
  (define (route-put r path handler) (router-add! r "PUT" path handler))
  (define (route-delete r path handler) (router-add! r "DELETE" path handler))

  ;; ========== Metrics ==========

  (define-record-type httpd-metrics
    (fields
      (mutable connections-active)   ;; current open connections
      (mutable connections-total)    ;; total connections accepted
      (mutable requests-total)       ;; total requests served
      (mutable errors-total)         ;; total 5xx responses
      (immutable start-time)         ;; (current-time) at server start
      (immutable metrics-mutex))
    (protocol
      (lambda (new)
        (lambda ()
          (new 0 0 0 0 (current-time) (make-mutex))))))

  (define (metrics-inc-active! m)
    (with-mutex (httpd-metrics-metrics-mutex m)
      (httpd-metrics-connections-active-set! m
        (+ (httpd-metrics-connections-active m) 1))
      (httpd-metrics-connections-total-set! m
        (+ (httpd-metrics-connections-total m) 1))))

  (define (metrics-dec-active! m)
    (with-mutex (httpd-metrics-metrics-mutex m)
      (httpd-metrics-connections-active-set! m
        (max 0 (- (httpd-metrics-connections-active m) 1)))))

  (define (metrics-inc-requests! m)
    (with-mutex (httpd-metrics-metrics-mutex m)
      (httpd-metrics-requests-total-set! m
        (+ (httpd-metrics-requests-total m) 1))))

  (define (metrics-inc-errors! m)
    (with-mutex (httpd-metrics-metrics-mutex m)
      (httpd-metrics-errors-total-set! m
        (+ (httpd-metrics-errors-total m) 1))))

  ;; ========== Server ==========

  (define-record-type fiber-httpd
    (fields (immutable listen-fd)
            (immutable listen-port)
            (immutable runtime)
            (immutable poller)
            (mutable running?)
            (mutable accept-fiber)
            (immutable metrics)
            (immutable max-connections)   ;; #f = unlimited
            (immutable conn-semaphore))   ;; fiber-semaphore or #f
    (sealed #t))

  ;; Connection handler: one fiber per connection, keep-alive loop.
  ;; Per-connection buffers are allocated once here and reused across
  ;; all keep-alive requests on this connection.
  (define (handle-connection fd poller handler metrics)
    (let ([hdr-buf   (make-bytevector 8192)]    ;; request header read buffer
          [parse-out (make-bytevector 270 0)]   ;; Rust HTTP parse result
          [resp-buf  (make-bytevector 4096 0)]  ;; response header write buffer
          [ws-upgraded? #f])
      (let loop ()
        (let ([req (read-request fd poller hdr-buf parse-out)])
          (when req
            (metrics-inc-requests! metrics)
            (let ([resp (guard (exn [#t
                          (metrics-inc-errors! metrics)
                          (respond-text 500
                            (if (message-condition? exn)
                              (condition-message exn)
                              "Internal Server Error"))])
                          (handler req))])
              (cond
                [(websocket-response? resp)
                 ;; WebSocket upgrade — hand off fd to WS handler
                 ;; The WS handler owns the fd now; don't close it here
                 (set! ws-upgraded? #t)
                 (guard (exn [#t (void)])
                   ((websocket-response-handler resp) fd poller req))]
                [(response? resp)
                 ;; Track 5xx errors
                 (when (>= (response-status resp) 500)
                   (metrics-inc-errors! metrics))
                 (write-response fd poller resp resp-buf)
                 ;; Keep-alive: check Connection header
                 (let ([conn (request-header req "connection")])
                   (unless (and conn (string=? (string-downcase conn) "close"))
                     (loop)))]
                ;; If resp is something else, just close
                [else (void)])))))
      ;; Only close fd if not handed off to WebSocket
      (unless ws-upgraded?
        (fiber-tcp-close fd))))

  ;; Accept loop with optional admission control
  (define (accept-loop listen-fd poller handler server)
    (let ([metrics (fiber-httpd-metrics server)]
          [sem (fiber-httpd-conn-semaphore server)])
      (guard (exn [#t (void)])  ;; catch cancellation and all errors
        (let loop ()
          (when (fiber-httpd-running? server)
            ;; Backpressure: if max-connections set, acquire permit
            (when sem (fiber-semaphore-acquire! sem))
            (let ([client-fd (fiber-tcp-accept listen-fd poller)])
              (metrics-inc-active! metrics)
              (fiber-spawn*
                (lambda ()
                  (guard (exn [#t (void)])  ;; ensure cleanup
                    (handle-connection client-fd poller handler metrics))
                  (metrics-dec-active! metrics)
                  (when sem (fiber-semaphore-release! sem)))
                "http-conn")
              (loop)))))))

  ;; Start server with defaults
  (define (fiber-httpd-start port handler)
    (fiber-httpd-start* port handler #f))

  ;; Start server with max-connections limit.
  ;; max-conn: #f = unlimited, integer = max concurrent connections
  (define (fiber-httpd-start* port handler max-conn)
    (let* ([rt (make-fiber-runtime)]
           [poller (make-io-poller rt)]
           [metrics (make-httpd-metrics)]
           [sem (and max-conn (> max-conn 0)
                     (make-fiber-semaphore max-conn))])
      (io-poller-start! poller)
      (let-values ([(listen-fd listen-port) (fiber-tcp-listen "0.0.0.0" port)])
        (let ([srv (make-fiber-httpd listen-fd listen-port rt poller #t #f
                     metrics max-conn sem)])
          ;; Spawn accept loop
          (let ([af (fiber-spawn rt
                      (lambda () (accept-loop listen-fd poller handler srv))
                      "httpd-accept")])
            (fiber-httpd-accept-fiber-set! srv af))
          ;; Run in background thread so caller gets the server handle back
          (fork-thread (lambda () (fiber-runtime-run! rt)))
          srv))))

  (define (fiber-httpd-stop! srv)
    (fiber-httpd-running?-set! srv #f)
    ;; Cancel the accept fiber — this wakes it from its parked state
    (let ([af (fiber-httpd-accept-fiber srv)])
      (when af (fiber-cancel! af)))
    ;; Close listen fd
    (fiber-tcp-close (fiber-httpd-listen-fd srv))
    ;; Stop runtime — marks running? = #f and wakes run queue
    (fiber-runtime-stop! (fiber-httpd-runtime srv))
    ;; Stop poller — shuts down the poller thread
    (io-poller-stop! (fiber-httpd-poller srv))
    ;; Give background thread time to exit
    (sleep (make-time 'time-duration 150000000 0)))

  ;; ========== Middleware helpers ==========

  ;; Wrap a handler to serve /health automatically
  (define (wrap-health-check handler server)
    (lambda (req)
      (if (and (string=? (request-method req) "GET")
               (string=? (request-path-only req) "/health"))
        (let ([m (fiber-httpd-metrics server)])
          (respond-json 200
            (format "{\"status\":\"ok\",\"connections\":~a,\"requests\":~a}"
              (httpd-metrics-connections-active m)
              (httpd-metrics-requests-total m))))
        (handler req))))

  ;; Wrap a handler to serve /metrics in a simple text format
  (define (wrap-metrics-endpoint handler server)
    (lambda (req)
      (if (and (string=? (request-method req) "GET")
               (string=? (request-path-only req) "/metrics"))
        (let* ([m (fiber-httpd-metrics server)]
               [uptime (let ([now (time-second (current-time))]
                             [start (time-second (httpd-metrics-start-time m))])
                         (- now start))])
          (respond-text 200
            (format (string-append
                      "# Jerboa fiber-httpd metrics\n"
                      "connections_active ~a\n"
                      "connections_total ~a\n"
                      "requests_total ~a\n"
                      "errors_total ~a\n"
                      "uptime_seconds ~a\n")
              (httpd-metrics-connections-active m)
              (httpd-metrics-connections-total m)
              (httpd-metrics-requests-total m)
              (httpd-metrics-errors-total m)
              uptime)))
        (handler req))))

) ;; end library
