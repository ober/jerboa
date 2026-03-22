#!chezscheme
;;; :std/lsp/server -- Minimal LSP server over stdio (JSON-RPC 2.0)

(library (std lsp server)
  (export start-lsp-server handle-request
          lsp-respond lsp-notify make-lsp-state lsp-state?)
  (import (chezscheme) (std text json) (std lsp symbols))

  (define-record-type lsp-state
    (fields (mutable files)      ;; uri-string -> text-string
            (mutable root-path)  ;; string or #f
            (mutable shutdown?)) ;; boolean
    (protocol
     (lambda (new)
       (lambda () (new (make-hashtable string-hash string=?) #f #f)))))

  ;; ---- JSON-RPC message I/O ----

  (define (read-header port)
    (let loop ([content-length #f])
      (let ([line (get-line port)])
        (cond
         [(eof-object? line) #f]
         [(or (string=? line "") (string=? line "\r")) content-length]
         [else (loop (or (parse-content-length line) content-length))]))))

  (define (parse-content-length line)
    (let ([prefix "Content-Length: "])
      (and (>= (string-length line) (string-length prefix))
           (string=? prefix (substring line 0 (string-length prefix)))
           (let* ([rest (substring line (string-length prefix)
                                   (string-length line))]
                  [rest (if (and (> (string-length rest) 0)
                                (char=? #\return
                                        (string-ref rest (- (string-length rest) 1))))
                            (substring rest 0 (- (string-length rest) 1))
                            rest)])
             (string->number rest)))))

  (define (read-message port)
    (let ([len (read-header port)])
      (and len
           (let ([buf (get-bytevector-n (standard-input-port) len)])
             (and (bytevector? buf)
                  (string->json-object (utf8->string buf)))))))

  (define (send-message port obj)
    (let* ([body (json-object->string obj)]
           [bv (string->utf8 body)]
           [len (bytevector-length bv)])
      (display (string-append "Content-Length: " (number->string len)
                              "\r\n\r\n") port)
      (put-bytevector (standard-output-port) bv)
      (flush-output-port port)
      (flush-output-port (standard-output-port))))

  ;; ---- Response helpers ----

  (define (lsp-respond port id result)
    (let ([resp (make-hashtable string-hash string=?)])
      (hashtable-set! resp "jsonrpc" "2.0")
      (hashtable-set! resp "id" id)
      (hashtable-set! resp "result" result)
      (send-message port resp)))

  (define (lsp-notify port method params)
    (let ([msg (make-hashtable string-hash string=?)])
      (hashtable-set! msg "jsonrpc" "2.0")
      (hashtable-set! msg "method" method)
      (hashtable-set! msg "params" params)
      (send-message port msg)))

  (define (lsp-respond-error port id code message)
    (let ([resp (make-hashtable string-hash string=?)]
          [err (make-hashtable string-hash string=?)])
      (hashtable-set! err "code" code) (hashtable-set! err "message" message)
      (hashtable-set! resp "jsonrpc" "2.0") (hashtable-set! resp "id" id)
      (hashtable-set! resp "error" err)
      (send-message port resp)))

  (define (jref obj key . default)
    (if (hashtable? obj)
        (hashtable-ref obj key (if (null? default) #f (car default)))
        (if (null? default) #f (car default))))

  ;; ---- Method handlers ----

  (define (make-json-obj . pairs)
    (let ([ht (make-hashtable string-hash string=?)])
      (let loop ([p pairs])
        (unless (null? p)
          (hashtable-set! ht (car p) (cadr p))
          (loop (cddr p))))
      ht))

  (define (handle-initialize state params)
    (lsp-state-root-path-set! state (jref params "rootPath"))
    (make-json-obj
     "capabilities"
     (make-json-obj
      "textDocumentSync" (make-json-obj "openClose" #t "change" 1)
      "completionProvider" (make-json-obj "triggerCharacters" '("(" " " "-"))
      "hoverProvider" #t)
     "serverInfo" (make-json-obj "name" "jerboa-lsp" "version" "0.1.0")))

  (define (handle-did-open state params)
    (let* ([td (jref params "textDocument")]
           [uri (jref td "uri")]
           [text (jref td "text")])
      (when (and uri text)
        (hashtable-set! (lsp-state-files state) uri text)))
    (void))

  (define (handle-did-change state params)
    (let* ([td (jref params "textDocument")]
           [uri (jref td "uri")]
           [changes (jref params "contentChanges")])
      (when (and uri (pair? changes))
        ;; Full sync: take the last change's text
        (let ([text (jref (car (reverse changes)) "text")])
          (when text
            (hashtable-set! (lsp-state-files state) uri text)))))
    (void))

  (define (handle-did-close state params)
    (let* ([td (jref params "textDocument")]
           [uri (jref td "uri")])
      (when uri
        (hashtable-delete! (lsp-state-files state) uri)))
    (void))

  (define (handle-completion state params)
    ;; Extract word under cursor from document text
    (let* ([td (jref params "textDocument")]
           [uri (jref td "uri")]
           [pos (jref params "position")]
           [line-num (jref pos "line" 0)]
           [col (jref pos "character" 0)]
           [text (hashtable-ref (lsp-state-files state)
                                (or uri "") #f)]
           [prefix (if text (extract-word text line-num col) "")])
      (let ([matches (symbol-db-complete prefix)])
        (map (lambda (m)
               (let ([item (make-hashtable string-hash string=?)])
                 (hashtable-set! item "label" (car m))
                 (hashtable-set! item "kind" 3) ;; Function
                 (hashtable-set! item "detail" (cadr m))
                 (hashtable-set! item "documentation" (caddr m))
                 item))
             matches))))

  (define (handle-hover state params)
    (let* ([td (jref params "textDocument")]
           [uri (jref td "uri")]
           [pos (jref params "position")]
           [line-num (jref pos "line" 0)]
           [col (jref pos "character" 0)]
           [text (hashtable-ref (lsp-state-files state)
                                (or uri "") #f)]
           [word (if text (extract-word text line-num col) "")])
      (let ([info (symbol-db-lookup word)])
        (if info
            (let ([result (make-hashtable string-hash string=?)]
                  [contents (make-hashtable string-hash string=?)])
              (hashtable-set! contents "kind" "markdown")
              (hashtable-set! contents "value"
                              (string-append "**" word "** — "
                                             (car info) "\n\n"
                                             (cdr info)))
              (hashtable-set! result "contents" contents)
              result)
            ;; no info — return null
            (void)))))

  ;; ---- Text helpers ----

  (define (extract-word text line-num col)
    ;; Get the symbol-like word ending at (line, col) in text.
    (let* ([lines (string-split text #\newline)]
           [line (if (< line-num (length lines))
                     (list-ref lines line-num)
                     "")]
           [c (min col (string-length line))])
      ;; Walk backwards from col to find start of word
      (let loop ([i (- c 1)] [chars '()])
        (if (or (< i 0)
                (let ([ch (string-ref line i)])
                  (or (char-whitespace? ch)
                      (memv ch '(#\( #\) #\[ #\] #\{ #\} #\' #\` #\, #\;)))))
            (list->string chars)
            (loop (- i 1) (cons (string-ref line i) chars))))))

  (define (string-split str ch)
    (let ([len (string-length str)])
      (let loop ([i 0] [start 0] [result '()])
        (cond
         [(= i len)
          (reverse (cons (substring str start len) result))]
         [(char=? (string-ref str i) ch)
          (loop (+ i 1) (+ i 1)
                (cons (substring str start i) result))]
         [else
          (loop (+ i 1) start result)]))))

  ;; ---- Main dispatch ----

  (define (handle-request state method params)
    (cond
     [(string=? method "initialize")
      (handle-initialize state params)]
     [(string=? method "initialized") (void)]
     [(string=? method "shutdown")
      (lsp-state-shutdown?-set! state #t)
      (void)]  ;; return null
     [(string=? method "textDocument/didOpen")
      (handle-did-open state params) (void)]
     [(string=? method "textDocument/didChange")
      (handle-did-change state params) (void)]
     [(string=? method "textDocument/didClose")
      (handle-did-close state params) (void)]
     [(string=? method "textDocument/completion")
      (handle-completion state params)]
     [(string=? method "textDocument/hover")
      (handle-hover state params)]
     [else #f]))

  ;; ---- Server loop ----

  (define (start-lsp-server)
    (let ([state (make-lsp-state)]
          [in (current-input-port)]
          [out (current-output-port)])
      (let loop ()
        (let ([msg (read-message in)])
          (when msg
            (let ([method (jref msg "method")]
                  [id (jref msg "id")]
                  [params (jref msg "params"
                                (make-hashtable string-hash string=?))])
              (cond
               ;; exit notification
               [(and method (string=? method "exit"))
                (exit (if (lsp-state-shutdown? state) 0 1))]
               ;; request (has id)
               [(and method id)
                (let ([result (handle-request state method params)])
                  (if result
                      (lsp-respond out id result)
                      ;; method not found
                      (lsp-respond-error out id -32601
                                         (string-append
                                          "Method not found: "
                                          method))))
                (loop)]
               ;; notification (no id)
               [method
                (handle-request state method params)
                (loop)]
               ;; unknown message shape
               [else (loop)])))))))

  ) ;; end library
