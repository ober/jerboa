#!chezscheme
;;; :std/net/request -- HTTP client
;;;
;;; Basic HTTP/1.1 client using (std net tcp).
;;; Supports http:// URLs. For https://, use with chez-https external library.

(library (std net request)
  (export
    http-get http-post http-put http-delete http-head
    request-status request-text request-content
    request-headers request-header request-close
    parse-url url-parts-scheme url-parts-host url-parts-port url-parts-path
    url-encode build-query-string
    flatten-request-headers)

  (import (chezscheme)
          (std net tcp))

  ;; ========== URL Parsing ==========

  (define-record-type url-parts
    (fields scheme host port path)
    (sealed #t))

  (define (parse-url url)
    ;; Returns a url-parts record: (scheme host port path)
    (let* ([after-scheme
            (cond
              [(string-prefix? "http://" url)
               (cons "http" (substring url 7 (string-length url)))]
              [(string-prefix? "https://" url)
               (cons "https" (substring url 8 (string-length url)))]
              [else (cons "http" url)])]
           [scheme (car after-scheme)]
           [rest (cdr after-scheme)]
           [slash-pos (string-find rest #\/)]
           [host+port (if slash-pos (substring rest 0 slash-pos) rest)]
           [path (if slash-pos (substring rest slash-pos (string-length rest)) "/")]
           [colon-pos (string-find host+port #\:)]
           [host (if colon-pos
                   (substring host+port 0 colon-pos)
                   host+port)]
           [port (if colon-pos
                   (string->number (substring host+port (+ colon-pos 1)
                                    (string-length host+port)))
                   (if (string=? scheme "https") 443 80))])
      (make-url-parts scheme host port path)))

  ;; ========== URL Encoding ==========

  (define (url-encode str)
    (let ([out (open-output-string)])
      (string-for-each
        (lambda (c)
          (cond
            [(or (char-alphabetic? c) (char-numeric? c)
                 (memv c '(#\- #\_ #\. #\~)))
             (write-char c out)]
            [else
             (let ([bv (string->bytevector (string c)
                         (make-transcoder (utf-8-codec)))])
               (let loop ([i 0])
                 (when (< i (bytevector-length bv))
                   (put-string out (format "%~2,'0X" (bytevector-u8-ref bv i)))
                   (loop (+ i 1)))))]))
        str)
      (get-output-string out)))

  (define (build-query-string params)
    ;; params: alist of (key . value) pairs
    (let ([parts (map (lambda (p)
                        (string-append (url-encode (car p)) "="
                                       (url-encode (cdr p))))
                      params)])
      (string-join parts "&")))

  ;; ========== Request/Response ==========

  (define-record-type http-response
    (fields
      (immutable status-code)
      (immutable header-alist)
      (immutable body)
      (mutable closed?))
    (sealed #t))

  (define (request-status resp) (http-response-status-code resp))
  (define (request-text resp) (http-response-body resp))
  (define (request-content resp) (http-response-body resp))
  (define (request-headers resp) (http-response-header-alist resp))
  (define (request-header resp name)
    (let ([pair (assoc (string-downcase name)
                       (http-response-header-alist resp))])
      (if pair (cdr pair) #f)))
  (define (request-close resp)
    (http-response-closed?-set! resp #t))

  (define (flatten-request-headers headers)
    ;; Convert alist to flat list: ((k . v) ...) → ("k: v" ...)
    (map (lambda (p)
           (string-append (car p) ": " (cdr p)))
         headers))

  ;; ========== HTTP Methods ==========

  (define http-get
    (case-lambda
      [(url) (http-request "GET" url '() #f)]
      [(url . kwargs) (apply http-request "GET" url kwargs)]))

  (define http-post
    (case-lambda
      [(url) (http-request "POST" url '() #f)]
      [(url . kwargs) (apply http-request "POST" url kwargs)]))

  (define http-put
    (case-lambda
      [(url) (http-request "PUT" url '() #f)]
      [(url . kwargs) (apply http-request "PUT" url kwargs)]))

  (define http-delete
    (case-lambda
      [(url) (http-request "DELETE" url '() #f)]
      [(url . kwargs) (apply http-request "DELETE" url kwargs)]))

  (define http-head
    (case-lambda
      [(url) (http-request "HEAD" url '() #f)]
      [(url . kwargs) (apply http-request "HEAD" url kwargs)]))

  ;; ========== Core Request ==========

  (define (http-request method url headers-or-kwargs data-or-rest . rest)
    (let* ([headers (if (list? headers-or-kwargs)
                      headers-or-kwargs
                      '())]
           [data (if (string? data-or-rest) data-or-rest #f)]
           [parsed (parse-url url)]
           [scheme (url-parts-scheme parsed)]
           [host (url-parts-host parsed)]
           [port (url-parts-port parsed)]
           [path (url-parts-path parsed)])
      (when (string=? scheme "https")
        (error 'http-request
          "HTTPS not supported — use chez-https external library" url))
      (let-values ([(in out) (tcp-connect host port)])
        (dynamic-wind
          (lambda () (void))
          (lambda ()
            ;; Send request line
            (put-string out (string-append method " " path " HTTP/1.1\r\n"))
            (put-string out (string-append "Host: " host "\r\n"))
            (put-string out "Connection: close\r\n")
            ;; Send custom headers
            (for-each (lambda (h)
                        (put-string out (string-append (car h) ": " (cdr h) "\r\n")))
                      headers)
            ;; Send body if present
            (when data
              (put-string out (string-append "Content-Length: "
                               (number->string (string-length data)) "\r\n")))
            (put-string out "\r\n")
            (when data (put-string out data))
            (flush-output-port out)
            ;; Read response
            (let* ([status-line (read-line-crlf in)]
                   [status-code (parse-status-code status-line)]
                   [resp-headers (read-headers in)]
                   [body (read-body in resp-headers)])
              (make-http-response status-code resp-headers body #f)))
          (lambda ()
            (close-port in)
            (close-port out))))))

  ;; ========== Response Parsing ==========

  (define (parse-status-code line)
    ;; "HTTP/1.1 200 OK" → 200
    (if (and (string? line) (> (string-length line) 12))
      (let ([code-str (substring line 9 12)])
        (or (string->number code-str) 0))
      0))

  (define (read-line-crlf port)
    ;; Read until \r\n
    (let ([out (open-output-string)])
      (let loop ()
        (let ([c (read-char port)])
          (cond
            [(eof-object? c) (get-output-string out)]
            [(char=? c #\return)
             (let ([next (read-char port)])
               (if (and (char? next) (char=? next #\newline))
                 (get-output-string out)
                 (begin (write-char c out)
                        (unless (eof-object? next) (write-char next out))
                        (loop))))]
            [else (write-char c out) (loop)])))))

  (define (read-headers port)
    ;; Read headers until empty line, return alist
    (let loop ([headers '()])
      (let ([line (read-line-crlf port)])
        (if (or (string=? line "") (eof-object? line))
          (reverse headers)
          (let ([colon-pos (string-find line #\:)])
            (if colon-pos
              (let ([key (string-downcase (substring line 0 colon-pos))]
                    [val (string-trim-left
                           (substring line (+ colon-pos 1) (string-length line)))])
                (loop (cons (cons key val) headers)))
              (loop headers)))))))

  (define (read-body port headers)
    ;; Read body based on Content-Length or until EOF
    (let ([cl (assoc "content-length" headers)])
      (if cl
        (let ([len (string->number (cdr cl))])
          (if (and len (> len 0))
            (let ([buf (get-string-n port len)])
              (if (eof-object? buf) "" buf))
            ""))
        ;; No content-length — read until EOF
        (let ([out (open-output-string)])
          (let loop ()
            (let ([c (read-char port)])
              (if (eof-object? c)
                (get-output-string out)
                (begin (write-char c out) (loop)))))))))

  ;; ========== Helpers ==========

  (define (string-prefix? prefix str)
    (and (>= (string-length str) (string-length prefix))
         (string=? (substring str 0 (string-length prefix)) prefix)))

  (define (string-find str ch)
    (let ([len (string-length str)])
      (let loop ([i 0])
        (cond
          [(>= i len) #f]
          [(char=? (string-ref str i) ch) i]
          [else (loop (+ i 1))]))))

  (define (string-trim-left str)
    (let ([len (string-length str)])
      (let loop ([i 0])
        (cond
          [(>= i len) ""]
          [(char-whitespace? (string-ref str i)) (loop (+ i 1))]
          [else (substring str i len)]))))

  (define (string-join lst sep)
    (cond
      [(null? lst) ""]
      [(null? (cdr lst)) (car lst)]
      [else (let loop ([rest (cdr lst)] [acc (car lst)])
              (if (null? rest) acc
                (loop (cdr rest) (string-append acc sep (car rest)))))]))

  ) ;; end library
