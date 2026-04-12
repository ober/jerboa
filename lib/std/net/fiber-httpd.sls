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

  ;; ========== HTTP Parser ==========
  ;;
  ;; Reads HTTP/1.1 requests from a raw fd using fiber-aware I/O.
  ;; Returns a request record or #f on connection close/error.

  (define *max-header-size* 8192)
  (define *max-body-size*   (* 10 1024 1024))  ;; 10MB

  ;; Read bytes from fd into a bytevector buffer, growing as needed.
  ;; Returns (values buf filled) where filled is total bytes in buf.
  ;; Reads until we find \r\n\r\n (end of headers) or hit max.
  (define (read-until-headers fd poller)
    (let ([buf (make-bytevector *max-header-size*)]
          [tmp (make-bytevector 4096)])
      (let loop ([filled 0])
        (if (>= filled *max-header-size*)
          (values buf filled)  ;; hit limit
          (let ([n (fiber-tcp-read fd tmp
                     (min 4096 (- *max-header-size* filled))
                     poller)])
            (cond
              [(<= n 0) (values buf filled)]  ;; EOF or error
              [else
               (bytevector-copy! tmp 0 buf filled n)
               (let ([total (+ filled n)])
                 ;; Check for \r\n\r\n
                 (if (header-complete? buf total)
                   (values buf total)
                   (loop total)))]))))))

  (define (header-complete? buf len)
    (let loop ([i 0])
      (cond
        [(> (+ i 3) len) #f]
        [(and (= (bytevector-u8-ref buf i) 13)       ;; \r
              (= (bytevector-u8-ref buf (+ i 1)) 10)  ;; \n
              (= (bytevector-u8-ref buf (+ i 2)) 13)  ;; \r
              (= (bytevector-u8-ref buf (+ i 3)) 10))  ;; \n
         #t]
        [else (loop (+ i 1))])))

  ;; Find the offset of \r\n\r\n in buffer
  (define (find-header-end buf len)
    (let loop ([i 0])
      (cond
        [(> (+ i 3) len) len]
        [(and (= (bytevector-u8-ref buf i) 13)
              (= (bytevector-u8-ref buf (+ i 1)) 10)
              (= (bytevector-u8-ref buf (+ i 2)) 13)
              (= (bytevector-u8-ref buf (+ i 3)) 10))
         (+ i 4)]
        [else (loop (+ i 1))])))

  ;; Parse the header portion into a request record.
  (define (parse-request-headers buf header-end)
    (let* ([header-str (utf8->string
                         (let ([b (make-bytevector header-end)])
                           (bytevector-copy! buf 0 b 0 header-end) b))]
           [lines (string-split-crlf header-str)])
      (if (null? lines) #f
        (let ([req-line (car lines)]
              [header-lines (cdr lines)])
          (let ([parts (string-split-spaces req-line)])
            (if (< (length parts) 3) #f
              (let ([method (car parts)]
                    [path (cadr parts)]
                    [version (caddr parts)]
                    [headers (parse-headers header-lines)])
                (make-request method path version headers #f))))))))

  (define (string-split-crlf s)
    (let loop ([start 0] [acc '()])
      (let ([idx (string-search s "\r\n" start)])
        (if idx
          (let ([line (substring s start idx)])
            (if (= (string-length line) 0)
              (reverse acc)
              (loop (+ idx 2) (cons line acc))))
          (let ([rest (substring s start (string-length s))])
            (reverse (if (= (string-length rest) 0) acc (cons rest acc))))))))

  (define (string-search s needle start)
    (let ([slen (string-length s)]
          [nlen (string-length needle)])
      (let loop ([i start])
        (cond
          [(> (+ i nlen) slen) #f]
          [(string=? (substring s i (+ i nlen)) needle) i]
          [else (loop (+ i 1))]))))

  (define (string-split-spaces s)
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(= i (string-length s))
         (reverse (if (= start i) acc
                    (cons (substring s start i) acc)))]
        [(char=? (string-ref s i) #\space)
         (loop (+ i 1) (+ i 1)
           (if (= start i) acc (cons (substring s start i) acc)))]
        [else (loop (+ i 1) start acc)])))

  (define (parse-headers lines)
    (let loop ([ls lines] [acc '()])
      (if (null? ls) (reverse acc)
        (let* ([line (car ls)]
               [colon (string-index line #\:)])
          (if colon
            (let ([name (string-downcase (substring line 0 colon))]
                  [value (string-trim-left (substring line (+ colon 1) (string-length line)))])
              (loop (cdr ls) (cons (cons name value) acc)))
            (loop (cdr ls) acc))))))

  (define (string-trim-left s)
    (let loop ([i 0])
      (if (and (< i (string-length s)) (char=? (string-ref s i) #\space))
        (loop (+ i 1))
        (substring s i (string-length s)))))

  ;; Read the body based on Content-Length
  (define (read-body fd poller buf header-end filled content-length)
    (if (or (not content-length) (= content-length 0))
      #f
      (let* ([already-have (- filled header-end)]
             [need (- content-length already-have)]
             [body-buf (make-bytevector content-length)])
        ;; Copy what we already have
        (when (> already-have 0)
          (bytevector-copy! buf header-end body-buf 0
            (min already-have content-length)))
        ;; Read the rest
        (when (> need 0)
          (let loop ([got already-have])
            (when (< got content-length)
              (let ([tmp (make-bytevector (min 4096 (- content-length got)))])
                (let ([n (fiber-tcp-read fd tmp
                           (min 4096 (- content-length got)) poller)])
                  (when (> n 0)
                    (bytevector-copy! tmp 0 body-buf got n)
                    (loop (+ got n))))))))
        (utf8->string body-buf))))

  ;; Full request read
  (define (read-request fd poller)
    (let-values ([(buf filled) (read-until-headers fd poller)])
      (if (= filled 0) #f  ;; connection closed
        (let ([header-end (find-header-end buf filled)])
          (let ([req (parse-request-headers buf header-end)])
            (if (not req) #f
              (let ([cl-str (request-header req "content-length")])
                (let ([content-length (and cl-str (string->number cl-str))])
                  (let ([body (read-body fd poller buf header-end filled content-length)])
                    (make-request (request-method req) (request-path req)
                                  (request-version req) (request-headers req)
                                  body))))))))))

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

  (define (write-response fd poller resp)
    (let* ([status (response-status resp)]
           [headers (response-headers resp)]
           [body (response-body resp)]
           [body-bv (cond
                      [(not body) (make-bytevector 0)]
                      [(string? body)
                       (string->bytevector body (make-transcoder (utf-8-codec)))]
                      [(bytevector? body) body]
                      [else (string->bytevector (format "~a" body)
                              (make-transcoder (utf-8-codec)))])]
           [status-line (format "HTTP/1.1 ~a ~a\r\n" status (status-text status))]
           ;; Build header string
           [header-str
             (let ([h (string-append
                        status-line
                        (format "Content-Length: ~a\r\n" (bytevector-length body-bv))
                        (apply string-append
                          (map (lambda (hdr)
                                 (format "~a: ~a\r\n" (car hdr) (cdr hdr)))
                               headers))
                        "\r\n")])
               h)]
           [header-bv (string->bytevector header-str (make-transcoder (utf-8-codec)))])
      ;; Write headers
      (fiber-tcp-write fd header-bv (bytevector-length header-bv) poller)
      ;; Write body
      (when (> (bytevector-length body-bv) 0)
        (fiber-tcp-write fd body-bv (bytevector-length body-bv) poller))))

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

  ;; Connection handler: one fiber per connection, keep-alive loop
  (define (handle-connection fd poller handler metrics)
    (let ([ws-upgraded? #f])
      (let loop ()
        (let ([req (read-request fd poller)])
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
                 (write-response fd poller resp)
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
