#!chezscheme
;;; :std/web/rack -- Middleware/handler composable web interface
;;;
;;; Provides a Rack-style composable handler architecture.
;;; A handler is (lambda (request) response).
;;; A request is a hashtable with keys: method, uri, headers, body, env.
;;; A response is (status-code headers body).
;;; Middleware wraps handlers to add cross-cutting concerns.

(library (std web rack)
  (export
    make-app
    rack-handler
    wrap-middleware
    rack-run
    rack-request
    rack-response
    compose-middleware)

  (import (chezscheme))

  ;; ========== FFI for TCP (same approach as std/net/tcp) ==========

  (define _libc-loaded
    (let ((v (getenv "JEMACS_STATIC")))
      (if (and v (not (string=? v "")) (not (string=? v "0")))
          #f
          (load-shared-object #f))))

  (define c-socket    (foreign-procedure "socket" (int int int) int))
  (define c-bind      (foreign-procedure "bind" (int void* int) int))
  (define c-listen    (foreign-procedure "listen" (int int) int))
  (define c-accept    (foreign-procedure "accept" (int void* void*) int))
  (define c-close     (foreign-procedure "close" (int) int))
  (define c-setsockopt (foreign-procedure "setsockopt" (int int int void* int) int))
  (define c-read      (foreign-procedure "read" (int void* size_t) ssize_t))
  (define c-write     (foreign-procedure "write" (int void* size_t) ssize_t))
  (define c-htons     (foreign-procedure "htons" (unsigned-short) unsigned-short))
  (define c-inet-pton (foreign-procedure "inet_pton" (int string void*) int))
  (define c-fcntl     (foreign-procedure "fcntl" (int int int) int))
  (define c-errno-location
    (if (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb))
      (foreign-procedure "__error" () void*)
      (foreign-procedure "__errno_location" () void*)))
  (define (get-errno) (foreign-ref 'int (c-errno-location) 0))

  (define AF_INET 2)
  (define SOCK_STREAM 1)
  (define SOL_SOCKET (if *freebsd?* #xffff 1))
  (define SO_REUSEADDR (if *freebsd?* 4 2))
  (define INADDR_ANY 0)
  (define SOCKADDR_IN_SIZE 16)
  (define *freebsd?* (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb)))
  (define EINTR 4)
  (define EAGAIN (if *freebsd?* 35 11))
  (define F_GETFL 3)
  (define F_SETFL 4)
  (define O_NONBLOCK
    (if (memq (machine-type) '(a6fb ta6fb i3fb ti3fb arm64fb)) #x4 #x800))

  (define *retry-delay* (make-time 'time-duration 10000000 0))

  (define (set-nonblocking! fd)
    (let ([flags (c-fcntl fd F_GETFL 0)])
      (c-fcntl fd F_SETFL (bitwise-ior flags O_NONBLOCK))))

  ;; ========== Request construction ==========

  ;; Create a request hashtable from parsed HTTP components.
  (define (rack-request method uri headers body)
    (let ((ht (make-hashtable string-hash string=?)))
      (hashtable-set! ht "method" method)
      (hashtable-set! ht "uri" uri)
      (hashtable-set! ht "headers" headers)
      (hashtable-set! ht "body" body)
      (hashtable-set! ht "env" (make-hashtable string-hash string=?))
      ht))

  ;; ========== Response construction ==========

  ;; Create a response: (status headers body)
  (define (rack-response status headers body)
    (list status headers body))

  ;; ========== Middleware composition ==========

  ;; A middleware is a procedure: (lambda (handler) (lambda (request) response))
  ;; wrap-middleware wraps a handler with a single middleware.
  (define (wrap-middleware handler middleware)
    (middleware handler))

  ;; Apply a chain of middleware to a handler.
  ;; Middleware are applied in order: first middleware is outermost.
  ;; (compose-middleware handler m1 m2 m3)
  ;; is equivalent to (m1 (m2 (m3 handler)))
  ;; so m1 runs first on the request, m3 runs last (closest to handler).
  (define (compose-middleware handler . middlewares)
    (fold-right (lambda (mw h) (mw h)) handler middlewares))

  ;; ========== Application ==========

  ;; An app record: handler + middleware list, resolved to a final handler.
  (define-record-type rack-app
    (fields handler middlewares resolved))

  ;; Construct an app from a handler and middleware list.
  (define (make-app handler . middlewares)
    (let ((resolved (apply compose-middleware handler middlewares)))
      (make-rack-app handler middlewares resolved)))

  ;; Get the resolved handler from an app (with all middleware applied).
  (define (rack-handler thing)
    (if (rack-app? thing)
        (rack-app-resolved thing)
        thing))

  ;; ========== HTTP server (rack-run) ==========

  ;; Simple HTTP/1.0 server loop.
  ;; Listens on the given port and dispatches requests to the handler.
  (define (rack-run handler port)
    (let ((effective-handler (rack-handler handler))
          (server-fd (tcp-listen-fd "0.0.0.0" port)))
      (dynamic-wind
        (lambda () #f)
        (lambda ()
          (let loop ()
            (let ((client-fd (tcp-accept-fd server-fd)))
              (when (>= client-fd 0)
                (guard (exn
                        (#t (c-close client-fd)))
                  (handle-http-connection client-fd effective-handler)
                  (c-close client-fd)))
              (loop))))
        (lambda ()
          (c-close server-fd)))))

  ;; ========== TCP helpers ==========

  (define (make-sockaddr-in address port)
    (let ((buf (make-bytevector SOCKADDR_IN_SIZE 0)))
      ;; sin_family = AF_INET
      (if *freebsd?*
          (begin
            (bytevector-u8-set! buf 0 16)        ;; sin_len = sizeof(sockaddr_in)
            (bytevector-u8-set! buf 1 AF_INET))  ;; sin_family (uint8)
          (bytevector-u16-set! buf 0 AF_INET (native-endianness)))
      ;; sin_port (offset 2, network byte order)
      (bytevector-u16-set! buf 2 (c-htons port) (native-endianness))
      ;; sin_addr (offset 4)
      (if (string=? address "0.0.0.0")
          (bytevector-u32-set! buf 4 INADDR_ANY (native-endianness))
          (c-inet-pton AF_INET address
                       (ftype-pointer-address
                         (make-ftype-pointer unsigned-32
                           (+ (foreign-ref 'void* (bytevector->pointer buf) 0)
                              4)))))
      buf))

  (define (bytevector->pointer bv)
    (#%$object-address bv (+ (foreign-sizeof 'ptr) 1)))

  (define (tcp-listen-fd address port)
    (let ((fd (c-socket AF_INET SOCK_STREAM 0)))
      (when (< fd 0)
        (error 'rack-run "socket() failed"))
      ;; SO_REUSEADDR
      (let ((one (make-bytevector 4 0)))
        (bytevector-s32-set! one 0 1 (native-endianness))
        (c-setsockopt fd SOL_SOCKET SO_REUSEADDR
                      (bytevector->pointer one) 4))
      (let* ((addr (make-sockaddr-in address port))
             (ret (c-bind fd (bytevector->pointer addr) SOCKADDR_IN_SIZE)))
        (when (< ret 0)
          (c-close fd)
          (error 'rack-run "bind() failed" port)))
      (let ((ret (c-listen fd 128)))
        (when (< ret 0)
          (c-close fd)
          (error 'rack-run "listen() failed")))
      fd))

  (define (tcp-accept-fd server-fd)
    (let ((addr (make-bytevector SOCKADDR_IN_SIZE 0))
          (len-buf (make-bytevector 4 0)))
      (bytevector-s32-set! len-buf 0 SOCKADDR_IN_SIZE (native-endianness))
      (let retry ()
        (let ((fd (c-accept server-fd
                            (bytevector->pointer addr)
                            (bytevector->pointer len-buf))))
          (if (< fd 0)
              (let ((err (get-errno)))
                (if (or (= err EINTR) (= err EAGAIN))
                    (begin (sleep *retry-delay*) (retry))
                    (error 'rack-run "accept() failed" err)))
              fd)))))

  ;; ========== HTTP parsing and response ==========

  ;; Read all available data from fd into a string
  (define (read-all-from-fd fd)
    (let ((buf (make-bytevector 8192)))
      (let loop ((chunks '()) (total 0))
        (let ((n (c-read fd buf 8192)))
          (cond
            ((> n 0)
             (let ((chunk (make-bytevector n)))
               (bytevector-copy! buf 0 chunk 0 n)
               (loop (cons chunk chunks) (+ total n))))
            ((and (< n 0) (= (get-errno) EINTR))
             (loop chunks total))
            (else
             ;; Combine chunks
             (let ((result (make-bytevector total)))
               (let combine ((cs (reverse chunks)) (pos 0))
                 (if (null? cs)
                     (utf8->string result)
                     (let ((c (car cs)))
                       (bytevector-copy! c 0 result pos (bytevector-length c))
                       (combine (cdr cs) (+ pos (bytevector-length c)))))))))))))

  ;; Parse a raw HTTP request string into a rack-request.
  (define (parse-http-request raw)
    (let ((lines (split-lines raw)))
      (if (null? lines)
          (rack-request "GET" "/" '() "")
          (let* ((request-line (car lines))
                 (parts (split-spaces request-line))
                 (method (if (>= (length parts) 1) (car parts) "GET"))
                 (uri (if (>= (length parts) 2) (cadr parts) "/"))
                 (header-lines (take-headers (cdr lines)))
                 (headers (map parse-header-line header-lines))
                 (body (extract-body raw)))
            (rack-request method uri headers body)))))

  ;; Take lines until empty line
  (define (take-headers lines)
    (let lp ((ls lines) (acc '()))
      (if (or (null? ls) (string=? (car ls) "") (string=? (car ls) "\r"))
          (reverse acc)
          (lp (cdr ls) (cons (car ls) acc)))))

  ;; Parse "Name: value" into (name . value)
  (define (parse-header-line line)
    (let ((pos (string-index-of line #\:)))
      (if pos
          (cons (substring line 0 pos)
                (string-trim-left (substring line (+ pos 1) (string-length line))))
          (cons line ""))))

  ;; Extract body after double CRLF
  (define (extract-body raw)
    (let ((pos (string-search raw "\r\n\r\n")))
      (if pos
          (substring raw (+ pos 4) (string-length raw))
          (let ((pos2 (string-search raw "\n\n")))
            (if pos2
                (substring raw (+ pos2 2) (string-length raw))
                "")))))

  ;; Serialize an HTTP response and write it to fd
  (define (send-http-response fd response)
    (let* ((status (car response))
           (headers (cadr response))
           (body (caddr response))
           (body-bytes (if (bytevector? body) body (string->utf8 body)))
           (status-line (string-append "HTTP/1.0 "
                                       (number->string status) " "
                                       (status-reason status) "\r\n"))
           (header-str (apply string-append
                              (map (lambda (h)
                                     (string-append (car h) ": " (cdr h) "\r\n"))
                                   headers)))
           (content-length (string-append "Content-Length: "
                                          (number->string (bytevector-length body-bytes))
                                          "\r\n"))
           (full-header (string-append status-line header-str content-length "\r\n"))
           (header-bytes (string->utf8 full-header)))
      (write-all fd header-bytes)
      (write-all fd body-bytes)))

  (define (write-all fd bv)
    (let ((len (bytevector-length bv)))
      (let lp ((pos 0))
        (when (< pos len)
          (let ((n (c-write fd
                            (bytevector->pointer-offset bv pos)
                            (- len pos))))
            (cond
              ((> n 0) (lp (+ pos n)))
              ((and (< n 0) (= (get-errno) EINTR)) (lp pos))
              (else (void))))))))

  ;; Get a pointer into a bytevector at offset
  (define (bytevector->pointer-offset bv offset)
    (+ (bytevector->pointer bv) offset))

  ;; HTTP status reason phrases
  (define (status-reason code)
    (case code
      ((200) "OK")
      ((201) "Created")
      ((204) "No Content")
      ((301) "Moved Permanently")
      ((302) "Found")
      ((304) "Not Modified")
      ((400) "Bad Request")
      ((401) "Unauthorized")
      ((403) "Forbidden")
      ((404) "Not Found")
      ((405) "Method Not Allowed")
      ((500) "Internal Server Error")
      ((502) "Bad Gateway")
      ((503) "Service Unavailable")
      (else "Unknown")))

  ;; Handle a single HTTP connection
  (define (handle-http-connection client-fd handler)
    (let* ((raw (read-all-from-fd client-fd))
           (request (parse-http-request raw))
           (response (guard (exn
                             (#t (rack-response 500
                                   '(("Content-Type" . "text/plain"))
                                   "Internal Server Error")))
                       (handler request))))
      (send-http-response client-fd response)))

  ;; ========== String utilities ==========

  (define (split-lines text)
    (let ((len (string-length text)))
      (let lp ((i 0) (start 0) (acc '()))
        (cond
          ((>= i len)
           (reverse (if (> i start)
                        (cons (substring text start i) acc)
                        acc)))
          ((and (char=? (string-ref text i) #\return)
                (< (+ i 1) len)
                (char=? (string-ref text (+ i 1)) #\newline))
           (lp (+ i 2) (+ i 2) (cons (substring text start i) acc)))
          ((char=? (string-ref text i) #\newline)
           (lp (+ i 1) (+ i 1) (cons (substring text start i) acc)))
          (else (lp (+ i 1) start acc))))))

  (define (split-spaces text)
    (let ((len (string-length text)))
      (let lp ((i 0) (start 0) (acc '()))
        (cond
          ((>= i len)
           (reverse (if (> i start)
                        (cons (substring text start i) acc)
                        acc)))
          ((char=? (string-ref text i) #\space)
           (lp (+ i 1) (+ i 1)
               (if (> i start)
                   (cons (substring text start i) acc)
                   acc)))
          (else (lp (+ i 1) start acc))))))

  (define (string-index-of str ch)
    (let ((len (string-length str)))
      (let lp ((i 0))
        (cond
          ((>= i len) #f)
          ((char=? (string-ref str i) ch) i)
          (else (lp (+ i 1)))))))

  (define (string-trim-left str)
    (let ((len (string-length str)))
      (let lp ((i 0))
        (cond
          ((>= i len) "")
          ((or (char=? (string-ref str i) #\space)
               (char=? (string-ref str i) #\tab))
           (lp (+ i 1)))
          (else (substring str i len))))))

  (define (string-search haystack needle)
    (let ((hlen (string-length haystack))
          (nlen (string-length needle)))
      (let lp ((i 0))
        (cond
          ((> (+ i nlen) hlen) #f)
          ((string-match-at? haystack needle i) i)
          (else (lp (+ i 1)))))))

  (define (string-match-at? haystack needle pos)
    (let ((nlen (string-length needle)))
      (let lp ((j 0))
        (cond
          ((>= j nlen) #t)
          ((char=? (string-ref haystack (+ pos j))
                   (string-ref needle j))
           (lp (+ j 1)))
          (else #f)))))

  ) ;; end library
