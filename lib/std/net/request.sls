#!chezscheme
;;; :std/net/request -- HTTP/HTTPS client
;;;
;;; HTTP/1.1 client supporting both http:// and https:// URLs.
;;; HTTP  uses (std net tcp) — plain TCP with Chez ports.
;;; HTTPS uses (std net tls-rustls) — Rust rustls TLS backend.

(library (std net request)
  (export
    http-get http-post http-put http-delete http-head
    request-status request-text request-content
    request-headers request-header request-close
    parse-url url-parts-scheme url-parts-host url-parts-port url-parts-path
    url-encode build-query-string
    flatten-request-headers
    headers->alist
    alist->headers
    *http-max-header-size* *http-max-header-count*
    *http-max-body-size* *http-max-line-length*)

  (import (chezscheme)
          (std net tcp)
          (std net tls-rustls))

  ;; ========== Safety Limits ==========

  (define *http-max-header-size*  (make-parameter (* 8 1024)))
  (define *http-max-header-count* (make-parameter 100))
  (define *http-max-body-size*    (make-parameter (* 10 1024 1024)))
  (define *http-max-line-length*  (make-parameter (* 8 1024)))

  ;; ========== URL Parsing ==========

  (define-record-type url-parts
    (fields scheme host port path)
    (sealed #t))

  (define (parse-url url)
    (let* ([after-scheme
            (cond
              [(string-prefix? "http://"  url) (cons "http"  (substring url 7 (string-length url)))]
              [(string-prefix? "https://" url) (cons "https" (substring url 8 (string-length url)))]
              [else (cons "http" url)])]
           [scheme (car after-scheme)]
           [rest   (cdr after-scheme)]
           [slash-pos   (string-find rest #\/)]
           [host+port   (if slash-pos (substring rest 0 slash-pos) rest)]
           [path        (if slash-pos (substring rest slash-pos (string-length rest)) "/")]
           [colon-pos   (string-find host+port #\:)]
           [host        (if colon-pos (substring host+port 0 colon-pos) host+port)]
           [port        (if colon-pos
                          (string->number
                            (substring host+port (+ colon-pos 1) (string-length host+port)))
                          (if (string=? scheme "https") 443 80))])
      (make-url-parts scheme host port path)))

  ;; ========== URL Encoding ==========

  (define (url-encode str)
    (let ([out (open-output-string)])
      (string-for-each
        (lambda (c)
          (cond
            [(or (char-alphabetic? c) (char-numeric? c) (memv c '(#\- #\_ #\. #\~)))
             (write-char c out)]
            [else
             (let ([bv (string->utf8 (string c))])
               (let loop ([i 0])
                 (when (< i (bytevector-length bv))
                   (put-string out (format "%~2,'0X" (bytevector-u8-ref bv i)))
                   (loop (+ i 1)))))]))
        str)
      (get-output-string out)))

  (define (build-query-string params)
    (string-join
      (map (lambda (p) (string-append (url-encode (car p)) "=" (url-encode (cdr p)))) params)
      "&"))

  ;; ========== Request/Response ==========

  (define-record-type http-response
    (fields (immutable status-code)
            (immutable header-alist)
            (immutable body)
            (mutable   closed?))
    (sealed #t))

  (define (request-status  resp) (http-response-status-code  resp))
  (define (request-text    resp) (http-response-body         resp))
  (define (request-content resp) (http-response-body         resp))
  (define (request-headers resp) (http-response-header-alist resp))
  (define (request-header  resp name)
    (let ([pair (assoc (string-downcase name) (http-response-header-alist resp))])
      (if pair (cdr pair) #f)))
  (define (request-close resp) (http-response-closed?-set! resp #t))

  (define (flatten-request-headers headers)
    (map (lambda (p) (string-append (car p) ": " (cdr p))) headers))

  ;; ========== HTTP Methods ==========

  (define http-get
    (case-lambda
      [(url)          (http-request "GET" url '() #f)]
      [(url . kwargs) (apply http-request "GET" url kwargs)]))

  (define http-post
    (case-lambda
      [(url)          (http-request "POST" url '() #f)]
      [(url . kwargs) (apply http-request "POST" url kwargs)]))

  (define http-put
    (case-lambda
      [(url)          (http-request "PUT" url '() #f)]
      [(url . kwargs) (apply http-request "PUT" url kwargs)]))

  (define http-delete
    (case-lambda
      [(url)          (http-request "DELETE" url '() #f)]
      [(url . kwargs) (apply http-request "DELETE" url kwargs)]))

  (define http-head
    (case-lambda
      [(url)          (http-request "HEAD" url '() #f)]
      [(url . kwargs) (apply http-request "HEAD" url kwargs)]))

  ;; ========== Core Request — dispatch on scheme ==========

  (define (http-request method url headers-or-kwargs data-or-rest . rest)
    (let* ([headers (if (list? headers-or-kwargs) headers-or-kwargs '())]
           [data    (if (string? data-or-rest) data-or-rest #f)]
           [parsed  (parse-url url)]
           [scheme  (url-parts-scheme parsed)]
           [host    (url-parts-host   parsed)]
           [port    (url-parts-port   parsed)]
           [path    (url-parts-path   parsed)])
      (if (string=? scheme "https")
        (http-request-https method host port path headers data)
        (http-request-http  method host port path headers data))))

  ;; ========== HTTP (plain TCP) ==========

  (define (http-request-http method host port path headers data)
    (let-values ([(in out) (tcp-connect host port)])
      (dynamic-wind
        (lambda () (void))
        (lambda ()
          (send-http-request out method host path headers data)
          (let* ([status-code  (parse-status-code (read-line-crlf in))]
                 [resp-headers (read-headers in)]
                 [body         (read-body in resp-headers)])
            (make-http-response status-code resp-headers body #f)))
        (lambda ()
          (close-port in)
          (close-port out)))))

  (define (send-http-request out method host path headers data)
    (validate-no-crlf! path   'http-request "path")
    (validate-no-crlf! host   'http-request "host")
    (put-string out (string-append method " " path " HTTP/1.1\r\n"))
    (put-string out (string-append "Host: " host "\r\n"))
    (put-string out "Connection: close\r\n")
    (for-each (lambda (h)
                (validate-no-crlf! (car h) 'http-request "header name")
                (validate-no-crlf! (cdr h) 'http-request "header value")
                (put-string out (string-append (car h) ": " (cdr h) "\r\n")))
              headers)
    (when data
      (let ([byte-len (bytevector-length (string->utf8 data))])
        (put-string out (string-append "Content-Length: " (number->string byte-len) "\r\n"))))
    (put-string out "\r\n")
    (when data (put-string out data))
    (flush-output-port out))

  ;; ========== HTTPS (Rust rustls TLS) ==========

  (define (http-request-https method host port path headers data)
    (let ([handle #f])
      (dynamic-wind
        (lambda () (void))
        (lambda ()
          (set! handle (rustls-connect host port))
          (send-https-request handle method host path headers data)
          (let* ([resp-bv   (rustls-read-until-eof handle)]
                 [resp-str  (utf8->string resp-bv)]
                 [resp-port (open-input-string resp-str)]
                 [status    (parse-status-code (read-line-crlf resp-port))]
                 [resp-hdrs (read-headers resp-port)]
                 [body      (read-body resp-port resp-hdrs)])
            (make-http-response status resp-hdrs body #f)))
        (lambda ()
          (when handle
            (guard (e [#t (void)]) (rustls-close handle)))))))

  (define (send-https-request handle method host path headers data)
    (validate-no-crlf! path 'https-request "path")
    (validate-no-crlf! host 'https-request "host")
    (let ([out (open-output-string)])
      (put-string out (string-append method " " path " HTTP/1.1\r\n"))
      (put-string out (string-append "Host: " host "\r\n"))
      (put-string out "Connection: close\r\n")
      (for-each (lambda (h)
                  (validate-no-crlf! (car h) 'https-request "header name")
                  (validate-no-crlf! (cdr h) 'https-request "header value")
                  (put-string out (string-append (car h) ": " (cdr h) "\r\n")))
                headers)
      (when data
        (let ([byte-len (bytevector-length (string->utf8 data))])
          (put-string out (string-append "Content-Length: " (number->string byte-len) "\r\n"))))
      (put-string out "\r\n")
      ;; Flush headers
      (let ([hdrs-bv (string->utf8 (get-output-string out))])
        (rustls-write handle hdrs-bv (bytevector-length hdrs-bv)))
      ;; Send body separately (avoids double UTF-8 encode for Content-Length calc)
      (when data
        (let ([body-bv (string->utf8 data)])
          (rustls-write handle body-bv (bytevector-length body-bv))))))

  (define (rustls-read-until-eof handle)
    (let ([buf (make-bytevector 32768)])
      (let loop ([chunks '()])
        (let ([n (rustls-read handle buf 32768)])
          (if (<= n 0)
            (bytevector-concat (reverse chunks))
            (let ([chunk (make-bytevector n)])
              (bytevector-copy! buf 0 chunk 0 n)
              (loop (cons chunk chunks))))))))

  (define (bytevector-concat bvs)
    (let* ([total  (apply + (map bytevector-length bvs))]
           [result (make-bytevector total 0)])
      (let loop ([offset 0] [bvs bvs])
        (if (null? bvs)
          result
          (let* ([bv  (car bvs)]
                 [len (bytevector-length bv)])
            (bytevector-copy! bv 0 result offset len)
            (loop (+ offset len) (cdr bvs)))))))

  ;; ========== Response Parsing ==========

  (define (parse-status-code line)
    (if (and (string? line) (> (string-length line) 12))
      (or (string->number (substring line 9 12)) 0)
      0))

  (define (read-line-crlf port)
    (let ([out (open-output-string)] [max-len (*http-max-line-length*)])
      (let loop ([len 0])
        (when (> len max-len)
          (error 'http-request "HTTP line too long" len))
        (let ([c (read-char port)])
          (cond
            [(eof-object? c) (get-output-string out)]
            [(char=? c #\return)
             (let ([next (read-char port)])
               (if (and (char? next) (char=? next #\newline))
                 (get-output-string out)
                 (begin
                   (write-char c out)
                   (unless (eof-object? next) (write-char next out))
                   (loop (+ len 2)))))]
            [else (write-char c out) (loop (+ len 1))])))))

  (define (read-headers port)
    (let ([max-count (*http-max-header-count*)]
          [max-size  (*http-max-header-size*)])
      (let loop ([headers '()] [count 0])
        (when (> count max-count)
          (error 'http-request "too many response headers" count))
        (let ([line (read-line-crlf port)])
          (when (and (string? line) (> (string-length line) max-size))
            (error 'http-request "response header too long" (string-length line)))
          (if (or (equal? line "") (eof-object? line))
            (reverse headers)
            (let ([colon-pos (string-find line #\:)])
              (if colon-pos
                (let ([key (string-downcase (substring line 0 colon-pos))]
                      [val (string-trim-left
                             (substring line (+ colon-pos 1) (string-length line)))])
                  (loop (cons (cons key val) headers) (+ count 1)))
                (loop headers count))))))))

  (define (read-body port headers)
    (let* ([max-body  (*http-max-body-size*)]
           [cl        (assoc "content-length"    headers)]
           [chunked?  (let ([te (assoc "transfer-encoding" headers)])
                        (and te (string-contains (cdr te) "chunked")))])
      (cond
        ;; Chunked transfer encoding
        [chunked?
         (read-chunked-body port max-body)]
        ;; Content-Length present
        [cl
         (let ([len (string->number (cdr cl))])
           (cond
             [(not len)       ""]
             [(<= len 0)      ""]
             [(> len max-body)
              (error 'http-request "Content-Length exceeds max body size" len max-body)]
             [else
              (let ([buf (get-string-n port len)])
                (if (eof-object? buf) "" buf))]))]
        ;; No content-length, no chunked — read until EOF
        [else
         (let ([out (open-output-string)])
           (let loop ([total 0])
             (when (> total max-body)
               (error 'http-request "body exceeds max size" max-body))
             (let ([c (read-char port)])
               (if (eof-object? c)
                 (get-output-string out)
                 (begin (write-char c out) (loop (+ total 1)))))))])))

  (define (read-chunked-body port max-body)
    ;; Decode HTTP/1.1 chunked transfer encoding.
    ;; Format: <hex-size>\r\n<data>\r\n ... 0\r\n\r\n
    (let ([out (open-output-string)] [total 0])
      (let loop ()
        (let* ([size-line (read-line-crlf port)]
               ;; Strip chunk extensions (e.g. "a;ext=val" → "a")
               [semi-pos  (string-find size-line #\;)]
               [hex-str   (if semi-pos
                            (substring size-line 0 semi-pos)
                            size-line)]
               [chunk-len (string->number (string-trim hex-str) 16)])
          (cond
            [(not chunk-len) ""]               ;; malformed
            [(= chunk-len 0) (get-output-string out)]  ;; last chunk
            [else
             (when (> (+ total chunk-len) max-body)
               (error 'http-request "chunked body exceeds max size" max-body))
             (let ([chunk (get-string-n port chunk-len)])
               (unless (eof-object? chunk)
                 (put-string out chunk)
                 (set! total (+ total chunk-len))))
             ;; Consume trailing \r\n after chunk data
             (read-line-crlf port)
             (loop)])))))

  ;; ========== Helpers ==========

  (define (validate-no-crlf! s who field)
    (when (or (string-find s #\return) (string-find s #\newline))
      (error who (string-append field " contains CRLF (possible injection)") s)))

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

  (define (string-trim str)
    (let* ([len   (string-length str)]
           [start (let loop ([i 0])
                    (if (and (< i len) (char-whitespace? (string-ref str i)))
                      (loop (+ i 1)) i))]
           [end   (let loop ([i len])
                    (if (and (> i start) (char-whitespace? (string-ref str (- i 1))))
                      (loop (- i 1)) i))])
      (substring str start end)))

  (define (string-contains str needle)
    (let ([slen (string-length str)]
          [nlen (string-length needle)])
      (let loop ([i 0])
        (cond
          [(> (+ i nlen) slen) #f]
          [(string=? (substring str i (+ i nlen)) needle) i]
          [else (loop (+ i 1))]))))

  (define (headers->alist header-strings)
    (map (lambda (s)
           (let ([colon-pos (string-find s #\:)])
             (if colon-pos
               (cons (substring s 0 colon-pos)
                     (string-trim-left (substring s (+ colon-pos 1) (string-length s))))
               (cons s ""))))
         header-strings))

  (define (alist->headers alist)
    (map (lambda (p) (string-append (car p) ": " (cdr p))) alist))

  (define (string-join lst sep)
    (cond
      [(null? lst) ""]
      [(null? (cdr lst)) (car lst)]
      [else (let loop ([rest (cdr lst)] [acc (car lst)])
              (if (null? rest) acc
                (loop (cdr rest) (string-append acc sep (car rest)))))]))

  ) ;; end library
