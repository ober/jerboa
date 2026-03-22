#!chezscheme
;;; :std/net/json-rpc -- JSON-RPC 2.0 protocol helpers
;;;
;;; Build and parse JSON-RPC 2.0 request/response objects.
;;; Includes a simple HTTP-based RPC caller.
;;;
;;; JSON-RPC 2.0 spec: https://www.jsonrpc.org/specification

(library (std net json-rpc)
  (export
    json-rpc-request json-rpc-notification
    json-rpc-response json-rpc-error-response
    json-rpc-parse parse-json-rpc-response
    json-rpc-call batch-call
    make-json-rpc-error json-rpc-error?)

  (import (except (chezscheme) make-hash-table hash-table? iota 1+ 1-)
          (jerboa runtime)
          (std text json)
          (std net tcp))

  ;; ========== Error record ==========

  (define-record-type json-rpc-error
    (fields code message data)
    (sealed #t))

  ;; ========== Standard error codes ==========

  (define *parse-error*      -32700)
  (define *invalid-request*  -32600)
  (define *method-not-found* -32601)
  (define *invalid-params*   -32602)
  (define *internal-error*   -32603)

  ;; ========== Building requests ==========

  (define json-rpc-request
    (case-lambda
      [(method params id)
       (let ([ht (make-hash-table)])
         (hash-put! ht "jsonrpc" "2.0")
         (hash-put! ht "method" method)
         (when params (hash-put! ht "params" params))
         (hash-put! ht "id" id)
         ht)]
      [(method params)
       (json-rpc-request method params 1)]))

  (define json-rpc-notification
    (case-lambda
      [(method params)
       (let ([ht (make-hash-table)])
         (hash-put! ht "jsonrpc" "2.0")
         (hash-put! ht "method" method)
         (when params (hash-put! ht "params" params))
         ht)]
      [(method)
       (json-rpc-notification method #f)]))

  ;; ========== Building responses ==========

  (define (json-rpc-response id result)
    (let ([ht (make-hash-table)])
      (hash-put! ht "jsonrpc" "2.0")
      (hash-put! ht "result" result)
      (hash-put! ht "id" id)
      ht))

  (define json-rpc-error-response
    (case-lambda
      [(id code message)
       (json-rpc-error-response id code message #f)]
      [(id code message data)
       (let ([ht (make-hash-table)]
             [err (make-hash-table)])
         (hash-put! err "code" code)
         (hash-put! err "message" message)
         (when data (hash-put! err "data" data))
         (hash-put! ht "jsonrpc" "2.0")
         (hash-put! ht "error" err)
         (hash-put! ht "id" id)
         ht)]))

  ;; ========== Parsing ==========

  (define (json-rpc-parse str)
    ;; Parse a JSON-RPC 2.0 message string into a hash table.
    (string->json-object str))

  (define (parse-json-rpc-response str)
    ;; Parse response and return result or raise error.
    (let ([obj (string->json-object str)])
      (cond
        [(hash-key? obj "error")
         (let ([err (hash-ref obj "error")])
           (raise (make-json-rpc-error
                    (hash-ref err "code")
                    (hash-ref err "message")
                    (if (hash-key? err "data")
                      (hash-ref err "data")
                      #f))))]
        [(hash-key? obj "result")
         (hash-ref obj "result")]
        [else
         (error 'parse-json-rpc-response
                "invalid JSON-RPC response: no result or error")])))

  ;; ========== RPC calls over HTTP ==========

  (define json-rpc-call
    (case-lambda
      [(url method params)
       (json-rpc-call url method params 1)]
      [(url method params id)
       (let* ([req (json-rpc-request method params id)]
              [body (json-object->string req)]
              [response (http-json-post url body)])
         (parse-json-rpc-response response))]))

  (define (batch-call url requests)
    ;; Send a batch of JSON-RPC requests. Each request is a hash table.
    ;; Returns list of parsed responses.
    (let* ([body (json-object->string requests)]
           [response (http-json-post url body)])
      (string->json-object response)))

  ;; ========== HTTP transport (minimal) ==========

  (define (http-json-post url body)
    ;; Minimal HTTP POST for JSON-RPC. Parses URL, sends request, returns body.
    (let-values ([(scheme host port path) (parse-simple-url url)])
      (let-values ([(in out) (tcp-connect host port)])
        (dynamic-wind
          (lambda () (void))
          (lambda ()
            (display (format "POST ~a HTTP/1.1\r\n" path) out)
            (display (format "Host: ~a\r\n" host) out)
            (display "Content-Type: application/json\r\n" out)
            (display (format "Content-Length: ~a\r\n"
                       (bytevector-length (string->utf8 body))) out)
            (display "Connection: close\r\n" out)
            (display "\r\n" out)
            (display body out)
            (flush-output-port out)
            ;; Read response — skip headers, return body
            (let loop ()
              (let ([line (read-line-crlf in)])
                (cond
                  [(eof-object? line) ""]
                  [(string=? line "") (read-rest in)]
                  [else (loop)]))))
          (lambda ()
            (close-port in)
            (close-port out))))))

  ;; ========== Internal helpers ==========

  (define (parse-simple-url url)
    (let* ([rest (cond
                   [(string-prefix? "http://" url)
                    (substring url 7 (string-length url))]
                   [else url])]
           [slash-pos (string-find rest #\/)]
           [host+port (if slash-pos (substring rest 0 slash-pos) rest)]
           [path (if slash-pos
                   (substring rest slash-pos (string-length rest))
                   "/")]
           [colon-pos (string-find host+port #\:)]
           [host (if colon-pos
                   (substring host+port 0 colon-pos)
                   host+port)]
           [port (if colon-pos
                   (string->number (substring host+port (+ colon-pos 1)
                                    (string-length host+port)))
                   80)])
      (values "http" host port path)))

  (define (string-prefix? prefix str)
    (and (>= (string-length str) (string-length prefix))
         (string=? (substring str 0 (string-length prefix)) prefix)))

  (define (string-find str ch)
    (let ([len (string-length str)])
      (let lp ([i 0])
        (cond
          [(= i len) #f]
          [(char=? (string-ref str i) ch) i]
          [else (lp (+ i 1))]))))

  (define (read-line-crlf port)
    (let loop ([chars '()])
      (let ([ch (read-char port)])
        (cond
          [(eof-object? ch)
           (if (null? chars) ch (list->string (reverse chars)))]
          [(char=? ch #\newline)
           (list->string (reverse chars))]
          [(char=? ch #\return) (loop chars)]
          [else (loop (cons ch chars))]))))

  (define (read-rest port)
    (let ([out (open-output-string)])
      (let loop ()
        (let ([ch (read-char port)])
          (unless (eof-object? ch)
            (write-char ch out)
            (loop))))
      (get-output-string out)))

  ) ;; end library
