#!chezscheme
;;; test-lsp.ss -- Tests for (std lsp) -- Language Server Protocol 2.0

(import (except (chezscheme) make-hash-table hash-table? iota 1+ 1-)
        (jerboa runtime)
        (std lsp)
        (std text json)
        (only (std misc string) string-prefix?))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define-syntax test-pred
  (syntax-rules ()
    [(_ name pred expr)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (pred got)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: predicate failed on ~s~%" name got)))))]))

(printf "--- (std lsp) tests ---~%~%")

;;;; ===== Position / Range / Location types =====

(test "make-position line"
  (position-line (make-position 5 10))
  5)

(test "position-character"
  (position-character (make-position 5 10))
  10)

(test "make-range start"
  (position-line (range-start (make-range (make-position 1 0) (make-position 1 5))))
  1)

(test "make-range end"
  (position-character (range-end (make-range (make-position 0 0) (make-position 0 7))))
  7)

(test "make-location uri"
  (location-uri (make-location "file:///foo.ss" (make-range (make-position 0 0) (make-position 0 0))))
  "file:///foo.ss")

(test "location-range"
  (position-line (range-start (location-range (make-location "uri" (make-range (make-position 3 0) (make-position 3 5))))))
  3)

;;;; ===== JSON-RPC message formatters =====

(test "format-lsp-response jsonrpc field"
  (let* ([resp (format-lsp-response 1 "ok")]
         [obj  (string->json-object resp)])
    (hashtable-ref obj "jsonrpc" #f))
  "2.0")

(test "format-lsp-response id"
  (let* ([resp (format-lsp-response 42 "result")]
         [obj  (string->json-object resp)])
    (hashtable-ref obj "id" #f))
  42)

(test "format-lsp-response result"
  (let* ([resp (format-lsp-response 1 "my-result")]
         [obj  (string->json-object resp)])
    (hashtable-ref obj "result" #f))
  "my-result")

(test "format-lsp-error code"
  (let* ([resp (format-lsp-error 1 -32600 "Bad request")]
         [obj  (string->json-object resp)])
    (let ([err (hashtable-ref obj "error" #f)])
      (hashtable-ref err "code" #f)))
  -32600)

(test "format-lsp-error message"
  (let* ([resp (format-lsp-error 1 -32601 "Not found")]
         [obj  (string->json-object resp)])
    (let ([err (hashtable-ref obj "error" #f)])
      (hashtable-ref err "message" #f)))
  "Not found")

(test "format-lsp-notification method"
  (let* ([notif (format-lsp-notification "textDocument/publishDiagnostics" '())]
         [obj   (string->json-object notif)])
    (hashtable-ref obj "method" #f))
  "textDocument/publishDiagnostics")

(test "format-lsp-notification no id"
  (let* ([notif (format-lsp-notification "window/showMessage" '())]
         [obj   (string->json-object notif)])
    (hashtable-ref obj "id" #f))
  #f)

;;;; ===== parse-lsp-message =====

(test "parse-lsp-message returns hashtable"
  (hashtable? (parse-lsp-message "{\"method\":\"initialize\",\"id\":1}"))
  #t)

(test "parse-lsp-message extracts method"
  (let ([obj (parse-lsp-message "{\"method\":\"shutdown\",\"id\":2}")])
    (hashtable-ref obj "method" #f))
  "shutdown")

;;;; ===== read/write-lsp-message =====

(test "write-lsp-message has Content-Length header"
  (let* ([port (open-output-string)]
         [msg  (let ([ht (make-hashtable equal-hash equal?)])
                 (hashtable-set! ht "method" "ping")
                 ht)])
    (write-lsp-message port msg)
    (string-prefix? "Content-Length:" (get-output-string port)))
  #t)

(test "write-lsp-message body follows header"
  (let* ([port (open-output-string)]
         [msg  (let ([ht (make-hashtable equal-hash equal?)])
                 (hashtable-set! ht "x" "y")
                 ht)])
    (write-lsp-message port msg)
    ;; body appears after \r\n\r\n
    (let ([s (get-output-string port)])
      (> (string-length s) 20)))
  #t)

(test "read-lsp-message round-trip"
  (let* ([body "{\"method\":\"ping\",\"id\":99}"]
         [framed (string-append "Content-Length: "
                                (number->string (string-length body))
                                "\r\n\r\n"
                                body)]
         [in-port (open-input-string framed)]
         [obj (read-lsp-message in-port)])
    (hashtable-ref obj "method" #f))
  "ping")

(test "read-lsp-message with extra headers"
  (let* ([body "{\"id\":1}"]
         [framed (string-append "Content-Length: "
                                (number->string (string-length body))
                                "\r\n"
                                "Content-Type: application/json\r\n"
                                "\r\n"
                                body)]
         [in-port (open-input-string framed)]
         [obj (read-lsp-message in-port)])
    (hashtable-ref obj "id" #f))
  1)

(test "read-lsp-message extracts correct id"
  (let* ([body "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"test\"}"]
         [framed (string-append "Content-Length: "
                                (number->string (string-length body))
                                "\r\n\r\n"
                                body)]
         [obj (read-lsp-message (open-input-string framed))])
    (hashtable-ref obj "id" #f))
  7)

;;;; ===== Document store =====

(test "document-store-open! and get"
  (let ([store (make-document-store)])
    (document-store-open! store "file:///test.ss" "(define x 42)")
    (document-store-get store "file:///test.ss"))
  "(define x 42)")

(test "document-store-update!"
  (let ([store (make-document-store)])
    (document-store-open! store "file:///test.ss" "old")
    (document-store-update! store "file:///test.ss" "new")
    (document-store-get store "file:///test.ss"))
  "new")

(test "document-store-close!"
  (let ([store (make-document-store)])
    (document-store-open! store "file:///test.ss" "content")
    (document-store-close! store "file:///test.ss")
    (document-store-get store "file:///test.ss"))
  #f)

(test "document-store-get missing"
  (document-store-get (make-document-store) "file:///missing.ss")
  #f)

(test "document-store multiple uris"
  (let ([store (make-document-store)])
    (document-store-open! store "file:///a.ss" "aaa")
    (document-store-open! store "file:///b.ss" "bbb")
    (list (document-store-get store "file:///a.ss")
          (document-store-get store "file:///b.ss")))
  '("aaa" "bbb"))

;;;; ===== analyze-document =====

(test "analyze-document finds define"
  (let ([syms (analyze-document "(define foo 42)")])
    (assoc "foo" syms))
  '("foo" 0))

(test "analyze-document finds multiple defines"
  (let ([syms (analyze-document "(define a 1)\n(define b 2)\n(define c 3)")])
    (length syms))
  3)

(test "analyze-document finds define with parens (function)"
  (let ([syms (analyze-document "(define (my-func x) x)")])
    (assoc "my-func" syms))
  '("my-func" 0))

(test "analyze-document finds define-record-type"
  (let ([syms (analyze-document "(define-record-type point (fields x y))")])
    (assoc "point" syms))
  '("point" 0))

(test "analyze-document line numbers"
  (let ([syms (analyze-document "line0\n(define alpha 1)\n(define beta 2)")])
    (and (equal? (assoc "alpha" syms) '("alpha" 1))
         (equal? (assoc "beta"  syms) '("beta"  2))))
  #t)

(test "analyze-document empty string"
  (analyze-document "")
  '())

(test "analyze-document no defines"
  (analyze-document "(+ 1 2)")
  '())

;;;; ===== find-completions =====

(test "find-completions exact prefix"
  (find-completions "my-f" '("my-func" "my-field" "other"))
  '("my-func" "my-field"))

(test "find-completions case-insensitive"
  (find-completions "MY-F" '("my-func" "other"))
  '("my-func"))

(test "find-completions empty prefix returns all"
  (length (find-completions "" '("a" "b" "c")))
  3)

(test "find-completions no match"
  (find-completions "zzz" '("aaa" "bbb"))
  '())

(test "find-completions with pair symbols"
  (find-completions "foo" '(("foo-bar" 0) ("foo-baz" 1) ("other" 2)))
  '(("foo-bar" 0) ("foo-baz" 1)))

;;;; ===== find-definition =====

(define (lsp-range? x)
  ;; Check that x has a valid range-start (it was created by make-range)
  (guard (e [#t #f])
    (and (lsp-position? (range-start x))
         (lsp-position? (range-end x)))))

(define (lsp-position? x)
  (guard (e [#t #f])
    (integer? (position-line x))))

(test "find-definition finds symbol"
  (let* ([docs (list (cons "file:///a.ss" "(define my-func 42)"))]
         [loc  (find-definition "my-func" docs)])
    (and loc (location-uri loc)))
  "file:///a.ss")

(test "find-definition returns #f for unknown"
  (find-definition "nonexistent" (list (cons "f.ss" "(define foo 1)")))
  #f)

(test "find-definition searches multiple docs"
  (let* ([docs (list (cons "a.ss" "(define alpha 1)")
                     (cons "b.ss" "(define beta 2)"))]
         [loc  (find-definition "beta" docs)])
    (and loc (location-uri loc)))
  "b.ss")

(test "find-definition returns location with range"
  (let* ([docs (list (cons "x.ss" "(define my-sym 99)"))]
         [loc  (find-definition "my-sym" docs)])
    (and loc (lsp-range? (location-range loc))))
  #t)

;;;; ===== lsp-capabilities =====

(test-pred "lsp-capabilities returns hashtable"
  hashtable?
  (lsp-capabilities))

(test "lsp-capabilities has completionProvider"
  (hashtable? (hashtable-ref (lsp-capabilities) "completionProvider" #f))
  #t)

(test "lsp-capabilities has hoverProvider"
  (hashtable-ref (lsp-capabilities) "hoverProvider" #f)
  #t)

;;;; ===== make-lsp-server / handle-initialize =====

(test-pred "make-lsp-server returns server"
  lsp-server?
  (make-lsp-server))

(test "lsp-server-running? initially false"
  (lsp-server-running? (make-lsp-server))
  #f)

(test "handle-initialize returns capabilities"
  (let* ([server (make-lsp-server)]
         [result (handle-initialize server (make-hashtable equal-hash equal?))])
    (hashtable? (hashtable-ref result "capabilities" #f)))
  #t)

(test "handle-initialize serverInfo name"
  (let* ([server (make-lsp-server)]
         [result (handle-initialize server (make-hashtable equal-hash equal?))]
         [info   (hashtable-ref result "serverInfo" #f)])
    (hashtable-ref info "name" #f))
  "jerboa-lsp")

(test "handle-initialize serverInfo version"
  (let* ([server (make-lsp-server)]
         [result (handle-initialize server (make-hashtable equal-hash equal?))]
         [info   (hashtable-ref result "serverInfo" #f)])
    (string? (hashtable-ref info "version" #f)))
  #t)

;;;; ===== lsp-handle-message dispatch =====

(define (make-msg method id params)
  (let ([ht (make-hashtable equal-hash equal?)])
    (hashtable-set! ht "method" method)
    (when id (hashtable-set! ht "id" id))
    (hashtable-set! ht "params" params)
    ht))

(test "lsp-handle-message initialize returns id"
  (let* ([server (make-lsp-server)]
         [msg    (make-msg "initialize" 1 (make-hashtable equal-hash equal?))]
         [resp   (lsp-handle-message server msg)]
         [obj    (string->json-object resp)])
    (hashtable-ref obj "id" #f))
  1)

(test "lsp-handle-message shutdown returns id"
  (let* ([server (make-lsp-server)]
         [msg    (make-msg "shutdown" 2 (make-hashtable equal-hash equal?))]
         [resp   (lsp-handle-message server msg)]
         [obj    (string->json-object resp)])
    (hashtable-ref obj "id" #f))
  2)

(test "lsp-handle-message unknown method -> error"
  (let* ([server (make-lsp-server)]
         [msg    (make-msg "nonexistent/method" 5 (make-hashtable equal-hash equal?))]
         [resp   (lsp-handle-message server msg)]
         [obj    (string->json-object resp)])
    (hashtable? (hashtable-ref obj "error" #f)))
  #t)

(test "lsp-handle-message initialized notification -> #f"
  (let* ([server (make-lsp-server)]
         [msg    (make-msg "initialized" #f (make-hashtable equal-hash equal?))])
    (lsp-handle-message server msg))
  #f)

(test "lsp-handle-message exit -> #f"
  (let* ([server (make-lsp-server)]
         [msg    (make-msg "exit" #f (make-hashtable equal-hash equal?))])
    (lsp-handle-message server msg))
  #f)

(test "lsp-handle-message didOpen stores document"
  (let* ([server (make-lsp-server)]
         [params (let ([ht (make-hashtable equal-hash equal?)])
                   (let ([td (make-hashtable equal-hash equal?)])
                     (hashtable-set! td "uri" "file:///foo.ss")
                     (hashtable-set! td "text" "(define x 1)")
                     (hashtable-set! ht "textDocument" td))
                   ht)]
         [msg (make-msg "textDocument/didOpen" #f params)])
    (lsp-handle-message server msg)
    ;; verify via the exported document-store-get using the server's store
    ;; We test indirectly by checking completion works after open
    (let* ([pos-ht (let ([h (make-hashtable equal-hash equal?)])
                     (hashtable-set! h "line" 0)
                     (hashtable-set! h "character" 7)
                     h)]
           [cparams (let ([h (make-hashtable equal-hash equal?)])
                      (let ([td (make-hashtable equal-hash equal?)])
                        (hashtable-set! td "uri" "file:///foo.ss")
                        (hashtable-set! h "textDocument" td))
                      (hashtable-set! h "position" pos-ht)
                      h)]
           [cmsg    (make-msg "textDocument/completion" 3 cparams)]
           [cresp   (lsp-handle-message server cmsg)]
           [cobj    (string->json-object cresp)])
      (hashtable? (hashtable-ref cobj "result" #f)))
  )
  #t)

;;;; ===== Summary =====

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
