#!chezscheme
;;; (std net ring) — Ring-style HTTP middleware for fiber-httpd
;;;
;;; Clojure Ring represents requests and responses as maps and
;;; middleware as function composition (handler → handler). This
;;; module bridges fiber-httpd's request/response records with
;;; Ring-style alists and provides a standard middleware library.
;;;
;;; Request alist keys:
;;;   request-method  — string: "GET", "POST", etc.
;;;   uri             — string: full path including query string
;;;   path            — string: path without query string
;;;   query-string    — string: query string (or "")
;;;   headers         — alist of (name . value)
;;;   body            — string or #f
;;;   scheme          — symbol: 'http or 'https
;;;   server-port     — integer
;;;
;;; Response alist:
;;;   status          — integer: HTTP status code
;;;   headers         — alist of (name . value)
;;;   body            — string
;;;
;;; Middleware pattern:
;;;   (define (wrap-foo handler)
;;;     (lambda (req) ... (handler req) ...))
;;;
;;; Compose with ring-app:
;;;   (ring-app my-handler wrap-logging wrap-json wrap-cors)

(library (std net ring)
  (export
    ;; Conversion
    request->ring
    ring->response

    ;; Middleware composition
    ring-app
    wrap-ring

    ;; Standard middleware
    wrap-json-body
    wrap-json-response
    wrap-params
    wrap-cookies
    wrap-session
    wrap-cors
    wrap-content-type
    wrap-not-modified
    wrap-head
    wrap-exception
    wrap-static

    ;; Ring response helpers
    ring-response
    ring-redirect
    ring-not-found)

  (import (chezscheme)
          (std net fiber-httpd)
          (std text json))

  ;; =========================================================================
  ;; Alist helpers
  ;; =========================================================================

  (define (alist-ref alist key . default)
    (let ([entry (assoc key alist)])
      (if entry
        (cdr entry)
        (if (pair? default) (car default) #f))))

  (define (alist-set alist key val)
    (cons (cons key val)
          (remp (lambda (p) (equal? (car p) key)) alist)))

  (define (alist-update alist key fn . default)
    (let ([old (apply alist-ref alist key default)])
      (alist-set alist key (fn old))))

  (define (alist-remove alist key)
    (remp (lambda (p) (equal? (car p) key)) alist))

  (define (alist-merge base overlay)
    (fold-left (lambda (acc pair)
                 (alist-set acc (car pair) (cdr pair)))
               base overlay))

  ;; =========================================================================
  ;; Request/Response conversion
  ;; =========================================================================

  (define (request->ring req)
    (list
      (cons 'request-method (request-method req))
      (cons 'uri           (request-path req))
      (cons 'path          (request-path-only req))
      (cons 'query-string  (request-query-string req))
      (cons 'headers       (or (request-headers req) '()))
      (cons 'body          (or (request-body req) #f))
      (cons 'scheme        'http)))

  (define (ring->response ring-resp)
    (respond
      (alist-ref ring-resp 'status 200)
      (alist-ref ring-resp 'headers '())
      (alist-ref ring-resp 'body "")))

  ;; =========================================================================
  ;; Ring response helpers
  ;; =========================================================================

  (define (ring-response status body . header-pairs)
    (list (cons 'status status)
          (cons 'headers header-pairs)
          (cons 'body body)))

  (define (ring-redirect url)
    (list (cons 'status 302)
          (cons 'headers (list (cons "Location" url)))
          (cons 'body "")))

  (define (ring-not-found)
    (list (cons 'status 404)
          (cons 'headers '(("Content-Type" . "text/plain")))
          (cons 'body "Not Found")))

  ;; =========================================================================
  ;; Middleware composition
  ;; =========================================================================

  ;; (ring-app handler mw1 mw2 ...) — compose middleware right to left.
  ;; Each middleware wraps the handler: (mw (mw2 (mw1 handler)))
  (define (ring-app handler . middleware)
    (fold-left (lambda (h mw) (mw h)) handler middleware))

  ;; (wrap-ring ring-handler) — adapt a Ring-style handler (alist in,
  ;; alist out) to work with fiber-httpd (record in, record out).
  ;; Use this to bridge Ring middleware chains into fiber-httpd.
  (define (wrap-ring ring-handler)
    (lambda (req)
      (ring->response (ring-handler (request->ring req)))))

  ;; =========================================================================
  ;; wrap-json-body — Parse JSON request body into 'json-body key
  ;; =========================================================================

  (define (wrap-json-body handler)
    (lambda (req)
      (let ([content-type (alist-ref (alist-ref req 'headers '())
                                     "Content-Type" "")])
        (if (and (alist-ref req 'body)
                 (%string-contains content-type "application/json"))
          (guard (exn [#t (handler req)])
            (let ([parsed (string->json-object (alist-ref req 'body))])
              (handler (alist-set req 'json-body parsed))))
          (handler req)))))

  (define (%string-contains s sub)
    (let ([slen (string-length s)]
          [nlen (string-length sub)])
      (let loop ([i 0])
        (cond
          [(> (+ i nlen) slen) #f]
          [(string=? (substring s i (+ i nlen)) sub) i]
          [else (loop (+ i 1))]))))

  ;; =========================================================================
  ;; wrap-json-response — Serialize response body as JSON
  ;; =========================================================================

  (define (wrap-json-response handler)
    (lambda (req)
      (let ([resp (handler req)])
        (let ([body (alist-ref resp 'body)])
          (cond
            [(or (pair? body) (hashtable? body))
             ;; Body is a data structure — serialize to JSON
             (let ([json-str (json-object->string body)]
                   [headers (alist-ref resp 'headers '())])
               (alist-set
                 (alist-set resp 'body json-str)
                 'headers
                 (alist-set headers "Content-Type" "application/json")))]
            [else resp])))))

  ;; Chez's hashtable? is already available from (chezscheme)

  ;; =========================================================================
  ;; wrap-params — Parse query params into 'params key
  ;; =========================================================================

  (define (wrap-params handler)
    (lambda (req)
      (let* ([qs (alist-ref req 'query-string "")]
             [params (parse-query-string qs)])
        (handler (alist-set req 'params params)))))

  (define (parse-query-string qs)
    (if (or (not qs) (string=? qs ""))
      '()
      (let ([pairs (string-split-char qs #\&)])
        (filter-map
          (lambda (pair)
            (let ([idx (string-index-of pair #\=)])
              (if idx
                (cons (substring pair 0 idx)
                      (url-decode (substring pair (+ idx 1) (string-length pair))))
                (cons pair ""))))
          pairs))))

  (define (string-split-char s ch)
    (let loop ([start 0] [acc '()])
      (let ([idx (string-index-from s ch start)])
        (if idx
          (loop (+ idx 1) (cons (substring s start idx) acc))
          (reverse (cons (substring s start (string-length s)) acc))))))

  (define (string-index-from s ch start)
    (let loop ([i start])
      (cond
        [(= i (string-length s)) #f]
        [(char=? (string-ref s i) ch) i]
        [else (loop (+ i 1))])))

  (define (string-index-of s ch)
    (string-index-from s ch 0))

  (define (url-decode s)
    ;; Basic URL decoding: %XX → char, + → space
    (let ([len (string-length s)])
      (let loop ([i 0] [acc '()])
        (cond
          [(= i len) (list->string (reverse acc))]
          [(and (char=? (string-ref s i) #\%)
                (<= (+ i 2) len))
           (let ([hi (hex-digit (string-ref s (+ i 1)))]
                 [lo (hex-digit (string-ref s (+ i 2)))])
             (if (and hi lo)
               (loop (+ i 3) (cons (integer->char (+ (* hi 16) lo)) acc))
               (loop (+ i 1) (cons #\% acc))))]
          [(char=? (string-ref s i) #\+)
           (loop (+ i 1) (cons #\space acc))]
          [else (loop (+ i 1) (cons (string-ref s i) acc))]))))

  (define (hex-digit ch)
    (cond
      [(and (char>=? ch #\0) (char<=? ch #\9))
       (- (char->integer ch) (char->integer #\0))]
      [(and (char>=? ch #\a) (char<=? ch #\f))
       (+ 10 (- (char->integer ch) (char->integer #\a)))]
      [(and (char>=? ch #\A) (char<=? ch #\F))
       (+ 10 (- (char->integer ch) (char->integer #\A)))]
      [else #f]))

  (define (filter-map f lst)
    (let loop ([l lst] [acc '()])
      (if (null? l) (reverse acc)
        (let ([v (f (car l))])
          (if v (loop (cdr l) (cons v acc))
                (loop (cdr l) acc))))))

  ;; =========================================================================
  ;; wrap-cookies — Parse/set cookies
  ;; =========================================================================

  (define (wrap-cookies handler)
    (lambda (req)
      (let* ([headers (alist-ref req 'headers '())]
             [cookie-header (alist-ref headers "Cookie" "")]
             [cookies (parse-cookies cookie-header)]
             [resp (handler (alist-set req 'cookies cookies))])
        ;; Check if handler set 'set-cookies on the response
        (let ([set-cookies (alist-ref resp 'set-cookies '())])
          (if (null? set-cookies)
            resp
            ;; Add Set-Cookie headers
            (let ([resp-headers (alist-ref resp 'headers '())])
              (alist-set
                (alist-remove resp 'set-cookies)
                'headers
                (append resp-headers
                        (map (lambda (c)
                               (cons "Set-Cookie" (format-cookie c)))
                             set-cookies)))))))))

  (define (parse-cookies header)
    (if (string=? header "")
      '()
      (filter-map
        (lambda (part)
          (let ([trimmed (string-trim-both part)])
            (let ([idx (string-index-of trimmed #\=)])
              (if idx
                (cons (substring trimmed 0 idx)
                      (substring trimmed (+ idx 1) (string-length trimmed)))
                #f))))
        (string-split-char header #\;))))

  (define (format-cookie c)
    ;; c is an alist: ((name . val) (path . "/") (max-age . 3600) ...)
    (let ([name (alist-ref c 'name "")]
          [value (alist-ref c 'value "")]
          [path (alist-ref c 'path #f)]
          [max-age (alist-ref c 'max-age #f)]
          [http-only (alist-ref c 'http-only #f)]
          [secure (alist-ref c 'secure #f)])
      (string-append
        name "=" value
        (if path (string-append "; Path=" path) "")
        (if max-age (string-append "; Max-Age=" (number->string max-age)) "")
        (if http-only "; HttpOnly" "")
        (if secure "; Secure" ""))))

  (define (string-trim-both s)
    (let* ([len (string-length s)]
           [start (let loop ([i 0])
                    (if (and (< i len) (char-whitespace? (string-ref s i)))
                      (loop (+ i 1)) i))]
           [end (let loop ([i (- len 1)])
                  (if (and (>= i start) (char-whitespace? (string-ref s i)))
                    (loop (- i 1)) (+ i 1)))])
      (substring s start end)))

  ;; =========================================================================
  ;; wrap-session — In-memory session management
  ;; =========================================================================

  (define (wrap-session handler . opts)
    (let ([store (make-hashtable string-hash string=?)]
          [cookie-name (if (and (pair? opts) (pair? (car opts)))
                         (alist-ref (car opts) 'cookie-name "jsessionid")
                         "jsessionid")])
      (lambda (req)
        (let* ([cookies (alist-ref req 'cookies '())]
               [sid (alist-ref cookies cookie-name #f)]
               [session (if (and sid (hashtable-contains? store sid))
                          (hashtable-ref store sid '())
                          '())]
               [new-sid (or sid (generate-session-id))]
               [resp (handler (alist-set req 'session session))])
          ;; Save updated session from response
          (let ([updated-session (alist-ref resp 'session #f)])
            (when updated-session
              (hashtable-set! store new-sid updated-session)))
          ;; Set session cookie if new
          (if (not sid)
            (let ([resp-headers (alist-ref resp 'headers '())])
              (alist-set resp 'headers
                (cons (cons "Set-Cookie"
                            (string-append cookie-name "=" new-sid
                                           "; Path=/; HttpOnly"))
                      resp-headers)))
            resp)))))

  (define (generate-session-id)
    ;; Simple random session ID
    (let loop ([i 0] [acc '()])
      (if (= i 32)
        (list->string acc)
        (loop (+ i 1)
              (cons (string-ref "0123456789abcdef" (random 16)) acc)))))

  ;; =========================================================================
  ;; wrap-cors — CORS headers
  ;; =========================================================================

  (define wrap-cors
    (case-lambda
      [(handler) (wrap-cors handler "*")]
      [(handler allowed-origin)
       (lambda (req)
         (let ([method (alist-ref req 'request-method "GET")])
           (if (string=? method "OPTIONS")
             ;; Preflight
             (list (cons 'status 204)
                   (cons 'headers
                     (list (cons "Access-Control-Allow-Origin" allowed-origin)
                           (cons "Access-Control-Allow-Methods" "GET, POST, PUT, DELETE, OPTIONS")
                           (cons "Access-Control-Allow-Headers" "Content-Type, Authorization")
                           (cons "Access-Control-Max-Age" "86400")))
                   (cons 'body ""))
             ;; Normal request — add CORS headers to response
             (let ([resp (handler req)]
                   [cors-headers
                     (list (cons "Access-Control-Allow-Origin" allowed-origin))])
               (alist-set resp 'headers
                 (append (alist-ref resp 'headers '()) cors-headers))))))]))

  ;; =========================================================================
  ;; wrap-content-type — Set default content-type
  ;; =========================================================================

  (define wrap-content-type
    (case-lambda
      [(handler) (wrap-content-type handler "application/octet-stream")]
      [(handler default-type)
       (lambda (req)
         (let ([resp (handler req)])
           (let ([headers (alist-ref resp 'headers '())])
             (if (alist-ref headers "Content-Type" #f)
               resp
               (alist-set resp 'headers
                 (cons (cons "Content-Type" default-type) headers))))))]))

  ;; =========================================================================
  ;; wrap-not-modified — 304 responses via ETag
  ;; =========================================================================

  (define (wrap-not-modified handler)
    (lambda (req)
      (let ([resp (handler req)])
        (let ([etag (alist-ref (alist-ref resp 'headers '()) "ETag" #f)]
              [if-none-match (alist-ref (alist-ref req 'headers '())
                                        "If-None-Match" #f)])
          (if (and etag if-none-match (string=? etag if-none-match)
                   (= (alist-ref resp 'status 200) 200))
            (list (cons 'status 304) (cons 'headers '()) (cons 'body ""))
            resp)))))

  ;; =========================================================================
  ;; wrap-head — Convert HEAD to GET, strip body from response
  ;; =========================================================================

  (define (wrap-head handler)
    (lambda (req)
      (if (string=? (alist-ref req 'request-method "") "HEAD")
        (let ([resp (handler (alist-set req 'request-method "GET"))])
          (alist-set resp 'body ""))
        (handler req))))

  ;; =========================================================================
  ;; wrap-exception — Catch exceptions, return 500
  ;; =========================================================================

  (define wrap-exception
    (case-lambda
      [(handler) (wrap-exception handler #f)]
      [(handler log-fn)
       (lambda (req)
         (guard (exn [#t
           (when log-fn (log-fn exn req))
           (list (cons 'status 500)
                 (cons 'headers '(("Content-Type" . "text/plain")))
                 (cons 'body "Internal Server Error"))])
           (handler req)))]))

  ;; =========================================================================
  ;; wrap-static — Serve static files from a directory
  ;; =========================================================================

  (define (wrap-static prefix dir)
    (lambda (handler)
      (lambda (req)
        (let ([path (alist-ref req 'path "")])
          (if (and (>= (string-length path) (string-length prefix))
                   (string=? (substring path 0 (string-length prefix)) prefix))
            (let ([file-path (string-append dir
                              (substring path (string-length prefix)
                                        (string-length path)))])
              (if (file-exists? file-path)
                (let ([body (call-with-input-file file-path
                              (lambda (p)
                                (get-string-all p)))]
                      [ct (mime-type file-path)])
                  (list (cons 'status 200)
                        (cons 'headers (list (cons "Content-Type" ct)))
                        (cons 'body body)))
                (handler req)))
            (handler req))))))

  (define (mime-type path)
    (let ([ext (%file-extension path)])
      (cond
        [(not ext) "application/octet-stream"]
        [(string=? ext "html") "text/html; charset=utf-8"]
        [(string=? ext "css")  "text/css"]
        [(string=? ext "js")   "application/javascript"]
        [(string=? ext "json") "application/json"]
        [(string=? ext "png")  "image/png"]
        [(string=? ext "jpg")  "image/jpeg"]
        [(string=? ext "gif")  "image/gif"]
        [(string=? ext "svg")  "image/svg+xml"]
        [(string=? ext "ico")  "image/x-icon"]
        [(string=? ext "txt")  "text/plain"]
        [(string=? ext "xml")  "application/xml"]
        [(string=? ext "pdf")  "application/pdf"]
        [(string=? ext "woff2") "font/woff2"]
        [else "application/octet-stream"])))

  (define (%file-extension path)
    (let loop ([i (- (string-length path) 1)])
      (cond
        [(< i 0) #f]
        [(char=? (string-ref path i) #\.)
         (substring path (+ i 1) (string-length path))]
        [(char=? (string-ref path i) #\/) #f]
        [else (loop (- i 1))])))

) ;; end library
