#!chezscheme
;;; :std/net/s3 -- AWS S3 client (basic operations)
;;;
;;; Implements AWS Signature V4 signing and basic S3 operations
;;; (PUT, GET, DELETE, HEAD, list-bucket) using raw HTTP/1.1
;;; over TCP.  Uses (std crypto digest) for SHA-256 and
;;; (std crypto native) for HMAC-SHA256.

(library (std net s3)
  (export
    make-s3-client s3-put-object s3-get-object s3-delete-object
    s3-list-bucket s3-head-object aws-sigv4-sign)

  (import (chezscheme)
          (std crypto digest)
          (std crypto native))

  ;; ========== S3 Client Record ==========

  (define-record-type s3-client-rec
    (fields
      (immutable access-key)
      (immutable secret-key)
      (immutable region)
      (immutable endpoint))     ;; #f means use default AWS endpoint
    (sealed #t))

  (define make-s3-client
    (case-lambda
      [(access-key secret-key region)
       (make-s3-client-rec access-key secret-key region #f)]
      [(access-key secret-key region endpoint)
       (make-s3-client-rec access-key secret-key region endpoint)]))

  ;; ========== Date/Time Helpers ==========

  (define (current-utc-time)
    ;; Returns (values date-stamp amz-date) as strings.
    ;; date-stamp: "YYYYMMDD"
    ;; amz-date:   "YYYYMMDDTHHMMSSZ"
    (let* ([t (current-time 'time-utc)]
           [d (time-utc->date t 0)]
           [yr  (date-year d)]
           [mo  (date-month d)]
           [dy  (date-day d)]
           [hr  (date-hour d)]
           [mn  (date-minute d)]
           [sc  (date-second d)])
      (values
        (format "~4,'0d~2,'0d~2,'0d" yr mo dy)
        (format "~4,'0d~2,'0d~2,'0dT~2,'0d~2,'0d~2,'0dZ" yr mo dy hr mn sc))))

  ;; ========== Hex Encoding ==========

  (define (bytevector->hex bv)
    (let* ([len (bytevector-length bv)]
           [out (make-string (* len 2))])
      (do ([i 0 (+ i 1)])
          ((= i len) out)
        (let* ([b (bytevector-u8-ref bv i)]
               [hi (bitwise-arithmetic-shift-right b 4)]
               [lo (bitwise-and b #xF)])
          (string-set! out (* i 2)     (hex-digit hi))
          (string-set! out (+ (* i 2) 1) (hex-digit lo))))))

  (define (hex-digit n)
    (string-ref "0123456789abcdef" n))

  (define (hex-string->bytevector str)
    (let* ([len (string-length str)]
           [bv (make-bytevector (quotient len 2))])
      (do ([i 0 (+ i 2)]
           [j 0 (+ j 1)])
          ((>= i len) bv)
        (bytevector-u8-set! bv j
          (+ (* (hex-val (string-ref str i)) 16)
             (hex-val (string-ref str (+ i 1))))))))

  (define (hex-val c)
    (cond
      [(char<=? #\0 c #\9) (- (char->integer c) (char->integer #\0))]
      [(char<=? #\a c #\f) (+ 10 (- (char->integer c) (char->integer #\a)))]
      [(char<=? #\A c #\F) (+ 10 (- (char->integer c) (char->integer #\A)))]
      [else 0]))

  ;; ========== SHA-256 ==========
  ;;
  ;; sha256-bytevector landed in Chez core (Phase 67, Round 12 — 2026-04-26),
  ;; so we no longer round-trip through (std crypto digest) hex strings.

  (define (->bv data)
    (if (bytevector? data) data (string->utf8 data)))

  (define (sha256-bv data)
    (sha256-bytevector (->bv data)))

  (define (sha256-hex data)
    (bytevector->hex (sha256-bv data)))

  ;; ========== HMAC-SHA256 ==========

  (define (hmac-sha256 key data)
    ;; key: bytevector, data: string or bytevector
    ;; Returns bytevector (32 bytes).
    (let ([data-bv (if (string? data) (string->utf8 data) data)])
      (native-hmac-sha256 key data-bv)))

  ;; ========== URI Encoding ==========

  (define (uri-encode str)
    ;; Percent-encode per AWS rules (encode everything except unreserved chars).
    ;; Does NOT encode '/'.
    (let ([out (open-output-string)])
      (string-for-each
        (lambda (c)
          (if (or (char-alphabetic? c)
                  (char-numeric? c)
                  (memv c '(#\- #\_ #\. #\~ #\/)))
            (write-char c out)
            (let ([bv (string->utf8 (string c))])
              (do ([i 0 (+ i 1)])
                  ((= i (bytevector-length bv)))
                (let ([b (bytevector-u8-ref bv i)])
                  (display "%" out)
                  (display (format "~2,'0X" b) out))))))
        str)
      (get-output-string out)))

  (define (uri-encode-component str)
    ;; Like uri-encode but also encodes '/'.
    (let ([out (open-output-string)])
      (string-for-each
        (lambda (c)
          (if (or (char-alphabetic? c)
                  (char-numeric? c)
                  (memv c '(#\- #\_ #\. #\~)))
            (write-char c out)
            (let ([bv (string->utf8 (string c))])
              (do ([i 0 (+ i 1)])
                  ((= i (bytevector-length bv)))
                (let ([b (bytevector-u8-ref bv i)])
                  (display "%" out)
                  (display (format "~2,'0X" b) out))))))
        str)
      (get-output-string out)))

  ;; ========== AWS Signature V4 ==========

  (define (aws-sigv4-sign client method uri query-string headers payload)
    ;; Sign a request using AWS Signature V4.
    ;; HEADERS is an alist of (name . value) — names must be lowercase.
    ;; Returns an alist of headers to add (Authorization, x-amz-date, etc.)
    (let-values ([(date-stamp amz-date) (current-utc-time)])
      (let* ([region     (s3-client-rec-region client)]
             [service    "s3"]
             [access-key (s3-client-rec-access-key client)]
             [secret-key (s3-client-rec-secret-key client)]
             ;; Credential scope
             [scope (format "~a/~a/~a/aws4_request"
                            date-stamp region service)]
             ;; Payload hash
             [payload-hash (sha256-hex (if payload payload ""))]
             ;; Add required headers
             [all-headers (append headers
                            (list (cons "x-amz-date" amz-date)
                                  (cons "x-amz-content-sha256" payload-hash)))]
             ;; Sort headers by name
             [sorted-headers (list-sort
                               (lambda (a b)
                                 (string<? (car a) (car b)))
                               all-headers)]
             ;; Canonical headers
             [canonical-headers
               (apply string-append
                 (map (lambda (h)
                        (format "~a:~a\n"
                                (string-downcase (car h))
                                (string-trim-ws (cdr h))))
                      sorted-headers))]
             ;; Signed headers
             [signed-headers
               (let ([names (map (lambda (h) (string-downcase (car h)))
                                 sorted-headers)])
                 (string-join names ";"))]
             ;; Canonical request
             [canonical-request
               (format "~a\n~a\n~a\n~a\n~a\n~a"
                       method
                       uri
                       (if query-string query-string "")
                       canonical-headers
                       signed-headers
                       payload-hash)]
             ;; String to sign
             [string-to-sign
               (format "AWS4-HMAC-SHA256\n~a\n~a\n~a"
                       amz-date
                       scope
                       (sha256-hex canonical-request))]
             ;; Signing key
             [k-date    (hmac-sha256
                          (string->utf8 (string-append "AWS4" secret-key))
                          date-stamp)]
             [k-region  (hmac-sha256 k-date region)]
             [k-service (hmac-sha256 k-region service)]
             [k-signing (hmac-sha256 k-service "aws4_request")]
             ;; Signature
             [signature (bytevector->hex
                          (hmac-sha256 k-signing string-to-sign))]
             ;; Authorization header
             [auth-header
               (format "AWS4-HMAC-SHA256 Credential=~a/~a, SignedHeaders=~a, Signature=~a"
                       access-key scope signed-headers signature)])
        ;; Return headers to add
        (list (cons "Authorization" auth-header)
              (cons "x-amz-date" amz-date)
              (cons "x-amz-content-sha256" payload-hash)))))

  ;; ========== String Helpers ==========

  (define (string-trim-ws str)
    (let* ([len (string-length str)]
           [start (let lp ([i 0])
                    (if (or (>= i len) (not (char-whitespace? (string-ref str i))))
                      i (lp (+ i 1))))]
           [end (let lp ([i (- len 1)])
                  (if (or (< i start) (not (char-whitespace? (string-ref str i))))
                    (+ i 1) (lp (- i 1))))])
      (substring str start end)))

  (define (string-join strs sep)
    (cond
      [(null? strs) ""]
      [(null? (cdr strs)) (car strs)]
      [else (string-append (car strs) sep
                           (string-join (cdr strs) sep))]))

  ;; string-downcase is provided by (chezscheme)

  ;; ========== HTTP/1.1 via TCP ==========

  (define (s3-endpoint client bucket)
    ;; Returns (values host port use-path-style).
    (let ([ep (s3-client-rec-endpoint client)])
      (cond
        [ep
         ;; Custom endpoint (e.g., MinIO) — use path-style
         (let-values ([(host port) (parse-endpoint ep)])
           (values host port #t))]
        [else
         ;; AWS — virtual-hosted style
         (values (format "~a.s3.~a.amazonaws.com"
                         bucket (s3-client-rec-region client))
                 443
                 #f)])))

  (define (parse-endpoint ep)
    ;; Parse "host:port" or "host" (default 80).
    (let ([colon (let lp ([i 0])
                   (cond
                     [(>= i (string-length ep)) #f]
                     [(char=? (string-ref ep i) #\:) i]
                     [else (lp (+ i 1))]))])
      (if colon
        (values (substring ep 0 colon)
                (string->number (substring ep (+ colon 1) (string-length ep))))
        (values ep 80))))

  ;; Low-level TCP connect (POSIX sockets for binary I/O)
  (define (tcp-connect host port)
    (let* ([c-socket     (foreign-procedure "socket" (int int int) int)]
           [c-connect    (foreign-procedure "connect" (int void* int) int)]
           [c-close      (foreign-procedure "close" (int) int)]
           [c-htons      (foreign-procedure "htons" (unsigned-short) unsigned-short)]
           [c-inet-pton  (foreign-procedure "inet_pton" (int string void*) int)]
           [c-getaddrinfo (foreign-procedure "getaddrinfo" (string string void* void*) int)]
           [c-freeaddrinfo (foreign-procedure "freeaddrinfo" (void*) void)]
           [c-inet-ntop  (foreign-procedure "inet_ntop" (int void* u8* int) string)]
           [AF_INET 2]
           [SOCK_STREAM 1]
           [SOCKADDR_IN_SIZE 16])
      ;; Resolve hostname
      (let ([ip-str (resolve-to-ipv4 host c-getaddrinfo c-freeaddrinfo c-inet-ntop c-inet-pton)])
        (let ([fd (c-socket AF_INET SOCK_STREAM 0)])
          (when (< fd 0)
            (error 'tcp-connect "socket() failed"))
          (let ([addr (foreign-alloc SOCKADDR_IN_SIZE)])
            (let lp ([i 0])
              (when (< i SOCKADDR_IN_SIZE)
                (foreign-set! 'unsigned-8 addr i 0)
                (lp (+ i 1))))
            (foreign-set! 'unsigned-short addr 0 AF_INET)
            (foreign-set! 'unsigned-short addr 2 (c-htons port))
            (when (= (c-inet-pton AF_INET ip-str (+ addr 4)) 0)
              (foreign-free addr) (c-close fd)
              (error 'tcp-connect "invalid address" ip-str))
            (let ([rc (c-connect fd addr SOCKADDR_IN_SIZE)])
              (foreign-free addr)
              (when (< rc 0)
                (c-close fd)
                (error 'tcp-connect "connect() failed" host port)))
            (fd->binary-ports fd c-close))))))

  (define (resolve-to-ipv4 host c-getaddrinfo c-freeaddrinfo c-inet-ntop c-inet-pton)
    ;; Try as dotted-quad first, else DNS resolve.
    (let ([test-buf (foreign-alloc 4)])
      (let ([rc (c-inet-pton 2 host test-buf)])
        (foreign-free test-buf)
        (if (= rc 1)
          host  ;; already an IP
          ;; DNS resolve
          (let ([result-ptr (foreign-alloc 8)])
            (foreign-set! 'void* result-ptr 0 0)
            (let ([rc (c-getaddrinfo host #f 0 result-ptr)])
              (when (not (= rc 0))
                (foreign-free result-ptr)
                (error 'resolve-to-ipv4 "DNS resolution failed" host))
              (let* ([ai (foreign-ref 'void* result-ptr 0)]
                     [ai-family (foreign-ref 'int ai 4)]
                     [ai-addr   (foreign-ref 'void* ai 24)])
                (unless (= ai-family 2)
                  (c-freeaddrinfo ai) (foreign-free result-ptr)
                  (error 'resolve-to-ipv4 "no IPv4 address" host))
                (let ([buf (make-bytevector 16)])
                  (let ([str (c-inet-ntop 2 (+ ai-addr 4) buf 16)])
                    (c-freeaddrinfo ai)
                    (foreign-free result-ptr)
                    (unless str
                      (error 'resolve-to-ipv4 "inet_ntop failed" host))
                    str)))))))))

  (define (fd->binary-ports fd c-close)
    (let ([c-read  (foreign-procedure "read" (int u8* size_t) ssize_t)]
          [c-write (foreign-procedure "write" (int u8* size_t) ssize_t)]
          [closed? #f])
      (let ([in (make-custom-binary-input-port
                  "s3-in"
                  (lambda (bv start count)
                    (if closed? 0
                      (let ([buf (make-bytevector count)])
                        (let ([n (c-read fd buf count)])
                          (cond
                            [(> n 0) (bytevector-copy! buf 0 bv start n) n]
                            [else 0])))))
                  #f #f
                  (lambda ()
                    (unless closed?
                      (set! closed? #t)
                      (c-close fd))))]
            [out (make-custom-binary-output-port
                   "s3-out"
                   (lambda (bv start count)
                     (if closed? 0
                       (let ([buf (make-bytevector count)])
                         (bytevector-copy! bv start buf 0 count)
                         (let loop ([written 0])
                           (if (= written count)
                             count
                             (let ([n (c-write fd
                                        (let ([tmp (make-bytevector (- count written))])
                                          (bytevector-copy! buf written tmp 0 (- count written))
                                          tmp)
                                        (- count written))])
                               (if (> n 0)
                                 (loop (+ written n))
                                 count)))))))
                   #f #f #f)])
        (values in out))))

  ;; ========== HTTP Request/Response ==========

  (define (http-request client method bucket key query-string
                        extra-headers body)
    ;; Send an HTTP/1.1 request and return (values status headers body-string).
    ;; Uses plain HTTP (port 80 or custom endpoint) — NOT HTTPS.
    ;; For production AWS usage, TLS should be layered on top.
    (let-values ([(host port path-style?) (s3-endpoint client bucket)])
      (let* ([uri (if path-style?
                    (string-append "/" bucket "/" (uri-encode key))
                    (string-append "/" (uri-encode key)))]
             [host-header (if (or (= port 80) (= port 443))
                            host
                            (format "~a:~a" host port))]
             [content-length (if body
                               (if (bytevector? body)
                                 (bytevector-length body)
                                 (bytevector-length (string->utf8 body)))
                               0)]
             [base-headers (list (cons "host" host-header)
                                 (cons "content-length"
                                       (number->string content-length)))]
             [headers (append base-headers extra-headers)]
             ;; Sign the request
             [payload (cond
                        [(not body) ""]
                        [(bytevector? body) body]
                        [else body])]
             [auth-headers (aws-sigv4-sign client method uri
                                          (if query-string query-string "")
                                          headers payload)]
             [all-headers (append headers auth-headers)]
             ;; Build the request URI with query string
             [request-uri (if (and query-string (> (string-length query-string) 0))
                            (string-append uri "?" query-string)
                            uri)])
        ;; Open connection
        (let-values ([(in out) (tcp-connect host port)])
          (dynamic-wind
            (lambda () (void))
            (lambda ()
              ;; Send request line
              (send-line out (format "~a ~a HTTP/1.1" method request-uri))
              ;; Send headers
              (for-each
                (lambda (h)
                  (send-line out (format "~a: ~a" (car h) (cdr h))))
                all-headers)
              (send-line out "")  ;; blank line ends headers
              ;; Send body
              (when (and body (> content-length 0))
                (let ([bv (if (bytevector? body) body (string->utf8 body))])
                  (put-bytevector out bv))
                (flush-output-port out))
              (flush-output-port out)
              ;; Read response
              (read-http-response in))
            (lambda ()
              (close-port in)
              (close-port out)))))))

  (define (send-line port str)
    (put-bytevector port (string->utf8 (string-append str "\r\n")))
    (flush-output-port port))

  (define (read-http-response in)
    ;; Returns (values status-code response-headers body-string).
    (let* ([status-line (read-line-crlf in)]
           [status-code (parse-status-code status-line)]
           [headers (read-headers in)]
           [body (read-body in headers)])
      (values status-code headers body)))

  (define (read-line-crlf port)
    ;; Read a line terminated by \r\n from a binary port.
    (let loop ([acc '()])
      (let ([b (get-u8 port)])
        (cond
          [(eof-object? b)
           (if (null? acc)
             ""
             (utf8->string (u8-list->bytevector (reverse acc))))]
          [(= b 13)  ;; CR
           (let ([next (get-u8 port)])
             ;; Consume LF
             (utf8->string (u8-list->bytevector (reverse acc))))]
          [else
           (loop (cons b acc))]))))

  (define (parse-status-code line)
    ;; "HTTP/1.1 200 OK" -> 200
    (let ([parts (string-split-on-space line)])
      (if (>= (length parts) 2)
        (or (string->number (cadr parts)) 0)
        0)))

  (define (string-split-on-space str)
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(= i (string-length str))
         (reverse (cons (substring str start i) acc))]
        [(char=? (string-ref str i) #\space)
         (loop (+ i 1) (+ i 1)
               (cons (substring str start i) acc))]
        [else
         (loop (+ i 1) start acc)])))

  (define (read-headers port)
    ;; Read HTTP headers until blank line.  Returns alist.
    (let loop ([acc '()])
      (let ([line (read-line-crlf port)])
        (if (or (string=? line "") (eof-object? line))
          (reverse acc)
          (let ([colon (string-index line #\:)])
            (if colon
              (let ([name (string-downcase
                            (substring line 0 colon))]
                    [value (string-trim-ws
                             (substring line (+ colon 1)
                                        (string-length line)))])
                (loop (cons (cons name value) acc)))
              (loop acc)))))))

  (define (string-index str ch)
    (let loop ([i 0])
      (cond
        [(= i (string-length str)) #f]
        [(char=? (string-ref str i) ch) i]
        [else (loop (+ i 1))])))

  (define (read-body port headers)
    ;; Read the response body based on Content-Length or chunked encoding.
    (let ([cl (assoc "content-length" headers)]
          [te (assoc "transfer-encoding" headers)])
      (cond
        [(and cl (string->number (cdr cl)))
         => (lambda (len)
              (if (= len 0)
                ""
                (let ([bv (get-bytevector-n port len)])
                  (if (eof-object? bv) "" (utf8->string bv)))))]
        [(and te (string-contains (cdr te) "chunked"))
         (read-chunked-body port)]
        [else
         ;; Read until EOF
         (let ([bv (get-bytevector-all port)])
           (if (eof-object? bv) "" (utf8->string bv)))])))

  (define (string-contains haystack needle)
    (let ([hlen (string-length haystack)]
          [nlen (string-length needle)])
      (let loop ([i 0])
        (cond
          [(> (+ i nlen) hlen) #f]
          [(string=? (substring haystack i (+ i nlen)) needle) #t]
          [else (loop (+ i 1))]))))

  (define (read-chunked-body port)
    ;; Read chunked transfer-encoded body.
    (let loop ([acc '()])
      (let* ([size-line (read-line-crlf port)]
             [size (string->number (string-append "#x"
                      (let ([semi (string-index size-line #\;)])
                        (if semi
                          (substring size-line 0 semi)
                          size-line))))])
        (if (or (not size) (= size 0))
          (begin
            (read-line-crlf port)  ;; trailing CRLF
            (apply string-append (reverse acc)))
          (let ([chunk-bv (get-bytevector-n port size)])
            (read-line-crlf port)  ;; chunk CRLF
            (loop (cons (if (eof-object? chunk-bv) ""
                            (utf8->string chunk-bv))
                        acc)))))))

  ;; ========== S3 Operations ==========

  (define (s3-put-object client bucket key data . args)
    ;; PUT an object.  DATA is a string or bytevector.
    ;; Optional keyword-style args: content-type (defaults to application/octet-stream).
    (let ([content-type (if (and (pair? args) (string? (car args)))
                          (car args)
                          "application/octet-stream")]
          [body (if (string? data) (string->utf8 data) data)])
      (let-values ([(status headers body-str)
                    (http-request client "PUT" bucket key #f
                                 (list (cons "content-type" content-type))
                                 body)])
        (unless (or (= status 200) (= status 204))
          (error 's3-put-object "PUT failed" status body-str))
        (void))))

  (define (s3-get-object client bucket key)
    ;; GET an object.  Returns the body as a string.
    (let-values ([(status headers body-str)
                  (http-request client "GET" bucket key #f '() #f)])
      (unless (= status 200)
        (error 's3-get-object "GET failed" status body-str))
      body-str))

  (define (s3-delete-object client bucket key)
    ;; DELETE an object.
    (let-values ([(status headers body-str)
                  (http-request client "DELETE" bucket key #f '() #f)])
      (unless (or (= status 200) (= status 204))
        (error 's3-delete-object "DELETE failed" status body-str))
      (void)))

  (define (s3-head-object client bucket key)
    ;; HEAD an object.  Returns the response headers as an alist.
    (let-values ([(status headers body-str)
                  (http-request client "HEAD" bucket key #f '() #f)])
      (unless (= status 200)
        (error 's3-head-object "HEAD failed" status body-str))
      headers))

  (define (s3-list-bucket client bucket . args)
    ;; List objects in a bucket.  Optional prefix argument.
    ;; Returns a list of alists, each with 'key, 'size, 'last-modified.
    (let* ([prefix (if (pair? args) (car args) #f)]
           [qs (if prefix
                 (string-append "list-type=2&prefix="
                                (uri-encode-component prefix))
                 "list-type=2")])
      (let-values ([(status headers body-str)
                    (http-request client "GET" bucket "" qs '() #f)])
        (unless (= status 200)
          (error 's3-list-bucket "LIST failed" status body-str))
        (parse-list-bucket-response body-str))))

  ;; ========== Simple XML Parsing for ListBucket ==========

  (define (parse-list-bucket-response xml)
    ;; Extract <Contents> elements from ListBucketResult XML.
    ;; Returns a list of alists.
    (let loop ([pos 0] [results '()])
      (let ([start (xml-find-tag xml "<Contents>" pos)])
        (if (not start)
          (reverse results)
          (let ([end (xml-find-tag xml "</Contents>" start)])
            (if (not end)
              (reverse results)
              (let* ([inner (substring xml (+ start 10) end)]
                     [key (xml-extract-text inner "Key")]
                     [size (xml-extract-text inner "Size")]
                     [modified (xml-extract-text inner "LastModified")])
                (loop (+ end 11)
                      (cons (list (cons 'key key)
                                  (cons 'size (or (and size (string->number size)) 0))
                                  (cons 'last-modified (or modified "")))
                            results)))))))))

  (define (xml-find-tag xml tag pos)
    ;; Find the position of TAG in XML starting from POS.
    (let ([tlen (string-length tag)]
          [xlen (string-length xml)])
      (let loop ([i pos])
        (cond
          [(> (+ i tlen) xlen) #f]
          [(string=? (substring xml i (+ i tlen)) tag) i]
          [else (loop (+ i 1))]))))

  (define (xml-extract-text xml tag-name)
    ;; Extract text content of <TagName>...</TagName>.
    (let* ([open-tag (string-append "<" tag-name ">")]
           [close-tag (string-append "</" tag-name ">")]
           [start (xml-find-tag xml open-tag 0)])
      (and start
           (let ([end (xml-find-tag xml close-tag (+ start (string-length open-tag)))])
             (and end
                  (substring xml
                             (+ start (string-length open-tag))
                             end))))))

  ) ;; end library
