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
    route-get route-post route-put route-delete)

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
      [(200) "OK"] [(201) "Created"] [(204) "No Content"]
      [(301) "Moved Permanently"] [(302) "Found"] [(304) "Not Modified"]
      [(400) "Bad Request"] [(401) "Unauthorized"] [(403) "Forbidden"]
      [(404) "Not Found"] [(405) "Method Not Allowed"]
      [(500) "Internal Server Error"] [(502) "Bad Gateway"]
      [(503) "Service Unavailable"]
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

  ;; Simple prefix/exact matching with :param support
  (define (path-match? pattern path)
    (or (string=? pattern path)
        (string=? pattern "*")))

  (define (router-dispatch r req)
    (let ([method (request-method req)]
          [path (request-path-only req)])
      (let loop ([routes (router-routes r)])
        (if (null? routes)
          (respond-text 404 "Not Found")
          (let ([route (car routes)])
            (if (and (string=? (car route) method)
                     (path-match? (cadr route) path))
              ((caddr route) req)
              (loop (cdr routes))))))))

  ;; Convenience route adders
  (define (route-get r path handler) (router-add! r "GET" path handler))
  (define (route-post r path handler) (router-add! r "POST" path handler))
  (define (route-put r path handler) (router-add! r "PUT" path handler))
  (define (route-delete r path handler) (router-add! r "DELETE" path handler))

  ;; ========== Server ==========

  (define-record-type fiber-httpd
    (fields (immutable listen-fd)
            (immutable listen-port)
            (immutable runtime)
            (immutable poller)
            (mutable running?))
    (sealed #t))

  ;; Connection handler: one fiber per connection, keep-alive loop
  (define (handle-connection fd poller handler)
    (let loop ()
      (let ([req (read-request fd poller)])
        (when req
          (let ([resp (guard (exn [#t
                        (respond-text 500
                          (if (message-condition? exn)
                            (condition-message exn)
                            "Internal Server Error"))])
                        (handler req))])
            (when (response? resp)
              (write-response fd poller resp)
              ;; Keep-alive: check Connection header
              (let ([conn (request-header req "connection")])
                (unless (and conn (string=? (string-downcase conn) "close"))
                  (loop))))))))
    (fiber-tcp-close fd))

  ;; Accept loop
  (define (accept-loop listen-fd poller handler)
    (let loop ()
      (guard (exn [#t (void)])  ;; stop on error (e.g., fd closed)
        (let ([client-fd (fiber-tcp-accept listen-fd poller)])
          (fiber-spawn*
            (lambda () (handle-connection client-fd poller handler))
            "http-conn")
          (loop)))))

  ;; Start the server
  (define (fiber-httpd-start port handler)
    (let* ([rt (make-fiber-runtime)]
           [poller (make-io-poller rt)])
      (io-poller-start! poller)
      (let-values ([(listen-fd listen-port) (fiber-tcp-listen "0.0.0.0" port)])
        (let ([srv (make-fiber-httpd listen-fd listen-port rt poller #t)])
          ;; Spawn accept loop
          (fiber-spawn rt
            (lambda () (accept-loop listen-fd poller handler))
            "httpd-accept")
          ;; Run in background thread so caller gets the server handle back
          (fork-thread (lambda () (fiber-runtime-run! rt)))
          srv))))

  (define (fiber-httpd-stop! srv)
    (fiber-httpd-running?-set! srv #f)
    (fiber-tcp-close (fiber-httpd-listen-fd srv))
    (io-poller-stop! (fiber-httpd-poller srv))
    (fiber-runtime-stop! (fiber-httpd-runtime srv)))

) ;; end library
