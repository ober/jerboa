#!chezscheme
;;; (std lsp) -- Language Server Protocol 2.0 implementation
;;;
;;; JSON-RPC 2.0 over stdio using Content-Length framing.
;;; Provides code intelligence (completion, hover, definition, references)
;;; for Jerboa/Chez Scheme code.

(library (std lsp)
  (export
    ;; Server lifecycle
    make-lsp-server
    lsp-server?
    lsp-server-start!
    lsp-server-stop!
    lsp-server-running?
    ;; Message handling
    lsp-handle-message
    lsp-send-notification
    ;; Capabilities
    lsp-capabilities
    ;; Request handlers (called by lsp-handle-message)
    handle-initialize
    handle-shutdown
    handle-text-document-completion
    handle-text-document-hover
    handle-text-document-definition
    handle-text-document-references
    handle-text-document-document-symbol
    handle-workspace-symbol
    handle-text-document-diagnostic
    ;; Document store
    make-document-store
    document-store-open!
    document-store-update!
    document-store-close!
    document-store-get
    ;; Analysis (simple, symbol-based)
    analyze-document
    find-completions
    find-definition
    ;; JSON-RPC
    parse-lsp-message
    format-lsp-response
    format-lsp-error
    format-lsp-notification
    read-lsp-message
    write-lsp-message
    ;; Position types
    make-position make-range make-location
    position-line position-character
    range-start range-end
    location-uri location-range)

  (import (except (chezscheme) make-hash-table hash-table? iota 1+ 1-)
          (jerboa runtime)
          (std text json)
          (only (std misc string) string-prefix? string-suffix?))

  ;; Helper: create an equal?-keyed hashtable (for JSON objects with string keys)
  (define (make-equal-hashtable)
    (make-hashtable equal-hash equal?))

  ;;;; ===== Position / Range / Location types =====

  (define-record-type lsp-position
    (fields line character))

  (define-record-type lsp-range
    (fields start end))

  (define-record-type lsp-location
    (fields uri range))

  (define (make-position line character)
    (make-lsp-position line character))

  (define (make-range start end)
    (make-lsp-range start end))

  (define (make-location uri range)
    (make-lsp-location uri range))

  (define (position-line p) (lsp-position-line p))
  (define (position-character p) (lsp-position-character p))
  (define (range-start r) (lsp-range-start r))
  (define (range-end r) (lsp-range-end r))
  (define (location-uri l) (lsp-location-uri l))
  (define (location-range l) (lsp-location-range l))

  ;;;; ===== Simple JSON helpers =====

  ;; Build a JSON object (hashtable) from key-value pairs
  (define (json-obj . pairs)
    (let ([ht (make-equal-hashtable)])
      (let loop ([ps pairs])
        (when (pair? ps)
          (hashtable-set! ht (car ps) (cadr ps))
          (loop (cddr ps))))
      ht))

  ;; Get a value from a JSON hashtable, returning default if absent
  (define (json-get ht key . default)
    (if (hashtable? ht)
      (let ([v (hashtable-ref ht key (if (null? default) #f (car default)))])
        v)
      (if (null? default) #f (car default))))

  ;;;; ===== JSON-RPC message framing =====

  ;; Read an LSP message: "Content-Length: N\r\n\r\n<body>"
  (define (read-lsp-message port)
    (let loop ([content-length #f])
      (let ([line (read-lsp-header-line port)])
        (cond
          [(eof-object? line) (eof-object)]
          [(string=? line "")
           ;; blank line ends headers
           (if content-length
             (let ([buf (make-string content-length)])
               (let ([n (get-string-n! port buf 0 content-length)])
                 (if (or (eof-object? n) (< n content-length))
                   (error 'read-lsp-message "short read" n content-length)
                   (string->json-object buf))))
             (error 'read-lsp-message "no Content-Length header"))]
          [(string-prefix? "Content-Length: " line)
           (let ([len-str (substring line 16 (string-length line))])
             (loop (string->number (string-trim-right len-str))))]
          [else
           ;; ignore other headers (Content-Type, etc.)
           (loop content-length)]))))

  ;; Read a single header line, stripping \r\n or \n
  (define (read-lsp-header-line port)
    (let loop ([chars '()])
      (let ([ch (read-char port)])
        (cond
          [(eof-object? ch)
           (if (null? chars) (eof-object) (list->string (reverse chars)))]
          [(char=? ch #\newline)
           ;; strip trailing \r if present
           (let ([s (list->string (reverse chars))])
             (if (and (> (string-length s) 0)
                      (char=? (string-ref s (- (string-length s) 1)) #\return))
               (substring s 0 (- (string-length s) 1))
               s))]
          [else (loop (cons ch chars))]))))

  ;; Write an LSP message with Content-Length framing
  (define (write-lsp-message port json-obj-or-string)
    (let ([body (if (string? json-obj-or-string)
                  json-obj-or-string
                  (json-object->string json-obj-or-string))])
      ;; Use UTF-8 byte length for Content-Length
      (let ([byte-len (bytevector-length (string->utf8 body))])
        (display (format "Content-Length: ~a\r\n\r\n" byte-len) port)
        (display body port)
        (flush-output-port port))))

  ;; Parse an LSP message (JSON string -> hashtable)
  (define (parse-lsp-message str)
    (string->json-object str))

  ;;;; ===== JSON-RPC response formatters =====

  (define (format-lsp-response id result)
    (json-object->string
      (json-obj "jsonrpc" "2.0"
                "id" id
                "result" result)))

  (define (format-lsp-error id code message)
    (json-object->string
      (json-obj "jsonrpc" "2.0"
                "id" id
                "error" (json-obj "code" code "message" message))))

  (define (format-lsp-notification method params)
    (json-object->string
      (json-obj "jsonrpc" "2.0"
                "method" method
                "params" params)))

  ;;;; ===== Document store =====

  (define-record-type document-store-rec
    (fields (mutable docs)))

  (define (make-document-store)
    (make-document-store-rec (make-equal-hashtable)))

  (define (document-store-open! store uri text)
    (hashtable-set! (document-store-rec-docs store) uri text))

  (define (document-store-update! store uri text)
    (hashtable-set! (document-store-rec-docs store) uri text))

  (define (document-store-close! store uri)
    (hashtable-delete! (document-store-rec-docs store) uri))

  (define (document-store-get store uri)
    (hashtable-ref (document-store-rec-docs store) uri #f))

  ;;;; ===== Document analysis =====

  ;; Scan text for top-level definitions, return list of (name line) pairs
  (define (analyze-document text)
    (let ([port (open-input-string text)]
          [results '()]
          [line 0])
      (let loop ()
        (let ([ch (read-char port)])
          (cond
            [(eof-object? ch) (reverse results)]
            [(char=? ch #\newline)
             (set! line (+ line 1))
             (loop)]
            [(char=? ch #\()
             ;; check for define/defstruct/defeffect/etc.
             (let ([word (read-identifier port)])
               (when (member word '("define" "define-record-type" "define-syntax"
                                    "defstruct" "defeffect" "library" "defmodule"
                                    "define-values" "define-condition-type"))
                 ;; skip whitespace and read the name
                 (skip-whitespace-inline port)
                 (let ([name (read-identifier-or-paren port)])
                   (when (and name (> (string-length name) 0))
                     (set! results (cons (list name line) results)))))
             (loop))]
            [else (loop)])))
      ))

  (define (read-identifier port)
    (let loop ([chars '()])
      (let ([ch (peek-char port)])
        (if (and (char? ch)
                 (not (char-whitespace? ch))
                 (not (memv ch '(#\( #\) #\[ #\] #\" #\; #\, #\` #\'))))
          (begin (read-char port) (loop (cons ch chars)))
          (list->string (reverse chars))))))

  (define (read-identifier-or-paren port)
    (let ([ch (peek-char port)])
      (cond
        [(eof-object? ch) ""]
        [(char=? ch #\() (read-char port) (read-identifier port)]
        [else (read-identifier port)])))

  (define (skip-whitespace-inline port)
    (let loop ()
      (let ([ch (peek-char port)])
        (when (and (char? ch) (char-whitespace? ch) (not (char=? ch #\newline)))
          (read-char port)
          (loop)))))

  ;; Find completions: filter known symbols by prefix (case-insensitive)
  (define (find-completions prefix known-symbols)
    (let ([prefix-lower (string-downcase prefix)]
          [prefix-len (string-length prefix)])
      (filter (lambda (sym)
                (let ([s (if (pair? sym) (car sym) sym)])
                  (and (>= (string-length s) prefix-len)
                       (string=? (string-downcase (substring s 0 prefix-len))
                                 prefix-lower))))
              known-symbols)))

  ;; Find definition of a symbol across documents
  ;; Returns a location or #f
  (define (find-definition symbol documents)
    ;; documents: list of (uri . text) pairs
    (let loop ([docs documents])
      (if (null? docs)
        #f
        (let* ([doc (car docs)]
               [uri (car doc)]
               [text (cdr doc)]
               [syms (analyze-document text)])
          (let ([found (assoc symbol syms)])
            (if found
              (let* ([line (cadr found)]
                     [pos (make-position line 0)]
                     [rng (make-range pos pos)])
                (make-location uri rng))
              (loop (cdr docs))))))))

  ;;;; ===== LSP Capabilities =====

  (define (lsp-capabilities)
    (json-obj
      "textDocumentSync" 1        ;; incremental sync = 1, full = 1
      "completionProvider" (json-obj "triggerCharacters" '("(" " "))
      "hoverProvider" #t
      "definitionProvider" #t
      "referencesProvider" #t
      "documentSymbolProvider" #t
      "workspaceSymbolProvider" #t
      "diagnosticProvider" (json-obj
                             "identifier" "jerboa-lsp"
                             "interFileDependencies" #f
                             "workspaceDiagnostics" #f)))

  ;;;; ===== LSP Server record =====

  (define-record-type lsp-server-rec
    (fields
      (mutable running?)
      (mutable doc-store)
      (mutable in-port)
      (mutable out-port)
      (mutable initialized?)
      (mutable known-symbols)
      (mutable thread-id)))

  (define (make-lsp-server)
    (make-lsp-server-rec
      #f                         ;; running?
      (make-document-store)      ;; doc-store
      (current-input-port)       ;; in-port
      (current-output-port)      ;; out-port
      #f                         ;; initialized?
      '()                        ;; known-symbols
      #f))                       ;; thread-id

  (define (lsp-server? x) (lsp-server-rec? x))
  (define (lsp-server-running? s) (lsp-server-rec-running? s))

  ;; Start the LSP server in background thread
  (define (lsp-server-start! server)
    (lsp-server-rec-running?-set! server #t)
    (let ([tid (fork-thread
                 (lambda ()
                   (guard (exn [#t (void)])
                     (let loop ()
                       (when (lsp-server-rec-running? server)
                         (let ([msg (guard (e [#t #f])
                                      (read-lsp-message (lsp-server-rec-in-port server)))])
                           (when (and msg (hashtable? msg))
                             (let ([resp (lsp-handle-message server msg)])
                               (when resp
                                 (write-lsp-message
                                   (lsp-server-rec-out-port server)
                                   resp))))
                           (when (lsp-server-rec-running? server)
                             (loop))))))))])
      (lsp-server-rec-thread-id-set! server tid)))

  (define (lsp-server-stop! server)
    (lsp-server-rec-running?-set! server #f))

  ;; Send a notification from server to client
  (define (lsp-send-notification server method params)
    (write-lsp-message
      (lsp-server-rec-out-port server)
      (format-lsp-notification method params)))

  ;;;; ===== Message dispatch =====

  (define (lsp-handle-message server msg)
    (let ([method (json-get msg "method")]
          [id     (json-get msg "id")]
          [params (json-get msg "params" (json-obj))])
      (cond
        [(not method)
         ;; response to our request — ignore
         #f]
        [(string=? method "initialize")
         (format-lsp-response id (handle-initialize server params))]
        [(string=? method "initialized")
         ;; notification, no response
         #f]
        [(string=? method "shutdown")
         (format-lsp-response id (handle-shutdown server))]
        [(string=? method "exit")
         (lsp-server-stop! server)
         #f]
        [(string=? method "textDocument/didOpen")
         (let* ([td (json-get params "textDocument")]
                [uri  (json-get td "uri")]
                [text (json-get td "text" "")])
           (document-store-open! (lsp-server-rec-doc-store server) uri text)
           (lsp-update-symbols! server text))
         #f]
        [(string=? method "textDocument/didChange")
         (let* ([td (json-get params "textDocument")]
                [uri (json-get td "uri")]
                [changes (json-get params "contentChanges" '())])
           (when (pair? changes)
             (let ([text (json-get (car changes) "text" "")])
               (document-store-update! (lsp-server-rec-doc-store server) uri text)
               (lsp-update-symbols! server text))))
         #f]
        [(string=? method "textDocument/didClose")
         (let* ([td (json-get params "textDocument")]
                [uri (json-get td "uri")])
           (document-store-close! (lsp-server-rec-doc-store server) uri))
         #f]
        [(string=? method "textDocument/completion")
         (format-lsp-response id (handle-text-document-completion server params))]
        [(string=? method "textDocument/hover")
         (format-lsp-response id (handle-text-document-hover server params))]
        [(string=? method "textDocument/definition")
         (format-lsp-response id (handle-text-document-definition server params))]
        [(string=? method "textDocument/references")
         (format-lsp-response id (handle-text-document-references server params))]
        [(string=? method "textDocument/documentSymbol")
         (format-lsp-response id (handle-text-document-document-symbol server params))]
        [(string=? method "workspace/symbol")
         (format-lsp-response id (handle-workspace-symbol server params))]
        [(string=? method "textDocument/diagnostic")
         (format-lsp-response id (handle-text-document-diagnostic server params))]
        [else
         ;; method not found
         (if id
           (format-lsp-error id -32601 (format "Method not found: ~a" method))
           #f)])))

  ;; Update known symbols from document text
  (define (lsp-update-symbols! server text)
    (let ([syms (analyze-document text)])
      (let ([existing (lsp-server-rec-known-symbols server)])
        (lsp-server-rec-known-symbols-set! server
          (lsp-merge-symbols existing syms)))))

  (define (lsp-merge-symbols existing new-syms)
    (let loop ([syms new-syms] [acc existing])
      (if (null? syms)
        acc
        (let ([name (caar syms)])
          (if (assoc name acc)
            (loop (cdr syms) acc)
            (loop (cdr syms) (cons (car syms) acc)))))))

  ;;;; ===== Request handlers =====

  (define (handle-initialize server params)
    (lsp-server-rec-initialized?-set! server #t)
    (json-obj "capabilities" (lsp-capabilities)
              "serverInfo" (json-obj "name" "jerboa-lsp" "version" "2.0.0")))

  (define (handle-shutdown server)
    (lsp-server-rec-running?-set! server #f)
    (void))

  (define (handle-text-document-completion server params)
    (let* ([td  (json-get params "textDocument")]
           [uri (json-get td "uri")]
           [pos (json-get params "position")]
           [line (json-get pos "line" 0)]
           [char (json-get pos "character" 0)]
           [text (document-store-get (lsp-server-rec-doc-store server) uri)]
           [prefix (if text (extract-word-before text line char) "")]
           [known (lsp-server-rec-known-symbols server)]
           [matches (find-completions prefix (map car known))])
      (json-obj
        "isIncomplete" #f
        "items" (map (lambda (sym)
                       (json-obj "label" sym
                                 "kind" 3  ;; Function
                                 "insertText" sym))
                     matches))))

  (define (handle-text-document-hover server params)
    (let* ([td  (json-get params "textDocument")]
           [uri (json-get td "uri")]
           [pos (json-get params "position")]
           [line (json-get pos "line" 0)]
           [char (json-get pos "character" 0)]
           [text (document-store-get (lsp-server-rec-doc-store server) uri)]
           [word (if text (extract-word-at text line char) "")])
      (if (string=? word "")
        (void)
        (json-obj "contents" (json-obj "kind" "markdown"
                                       "value" (format "**~a**\n\nJerboa symbol" word))))))

  (define (handle-text-document-definition server params)
    (let* ([td  (json-get params "textDocument")]
           [uri (json-get td "uri")]
           [pos (json-get params "position")]
           [line (json-get pos "line" 0)]
           [char (json-get pos "character" 0)]
           [text (document-store-get (lsp-server-rec-doc-store server) uri)]
           [word (if text (extract-word-at text line char) "")]
           [store (lsp-server-rec-doc-store server)]
           [all-docs (hashtable->alist (document-store-rec-docs store))]
           [loc (find-definition word all-docs)])
      (if loc
        (json-obj
          "uri"   (location-uri loc)
          "range" (range->json (location-range loc)))
        (void))))

  (define (handle-text-document-references server params)
    (let* ([td  (json-get params "textDocument")]
           [uri (json-get td "uri")]
           [pos (json-get params "position")]
           [line (json-get pos "line" 0)]
           [char (json-get pos "character" 0)]
           [text (document-store-get (lsp-server-rec-doc-store server) uri)]
           [word (if text (extract-word-at text line char) "")]
           [store (lsp-server-rec-doc-store server)]
           [all-docs (hashtable->alist (document-store-rec-docs store))])
      (if (string=? word "")
        '()
        (find-references word all-docs))))

  (define (handle-text-document-document-symbol server params)
    (let* ([td  (json-get params "textDocument")]
           [uri (json-get td "uri")]
           [text (document-store-get (lsp-server-rec-doc-store server) uri)])
      (if text
        (map (lambda (sym)
               (let* ([name (car sym)]
                      [line (cadr sym)]
                      [pos  (make-position line 0)]
                      [rng  (make-range pos pos)])
                 (json-obj "name" name
                           "kind" 12  ;; Function
                           "range" (range->json rng)
                           "selectionRange" (range->json rng))))
             (analyze-document text))
        '())))

  (define (handle-workspace-symbol server params)
    (let* ([query (json-get params "query" "")]
           [known (lsp-server-rec-known-symbols server)]
           [matches (if (string=? query "")
                      known
                      (filter (lambda (sym)
                                (string-contains-ci (car sym) query))
                              known))])
      (map (lambda (sym)
             (let* ([name (car sym)]
                    [line (cadr sym)]
                    [pos  (make-position line 0)]
                    [rng  (make-range pos pos)])
               (json-obj "name" name
                         "kind" 12
                         "location" (json-obj "uri" "" "range" (range->json rng)))))
           matches)))

  (define (handle-text-document-diagnostic server params)
    (let* ([td  (json-get params "textDocument")]
           [uri (json-get td "uri")]
           [text (document-store-get (lsp-server-rec-doc-store server) uri)])
      ;; simple: no diagnostics for now
      (json-obj "kind" "full" "items" '())))

  ;;;; ===== Helpers =====

  (define (hashtable->alist ht)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let ([n (vector-length keys)])
        (let loop ([i 0] [acc '()])
          (if (= i n)
            acc
            (loop (+ i 1)
                  (cons (cons (vector-ref keys i) (vector-ref vals i)) acc)))))))

  (define (range->json r)
    (json-obj "start" (pos->json (lsp-range-start r))
              "end"   (pos->json (lsp-range-end r))))

  (define (pos->json p)
    (json-obj "line"      (lsp-position-line p)
              "character" (lsp-position-character p)))

  ;; Extract the word (identifier) at a given line/char position in text
  (define (extract-word-at text line char)
    (let ([lines (string-split-lines text)])
      (if (>= line (length lines))
        ""
        (let ([ln (list-ref lines line)])
          (if (>= char (string-length ln))
            ""
            (let* ([start (find-word-start ln char)]
                   [end   (find-word-end   ln char)])
              (substring ln start end)))))))

  ;; Extract the word just before cursor (for completion)
  (define (extract-word-before text line char)
    (let ([lines (string-split-lines text)])
      (if (>= line (length lines))
        ""
        (let ([ln (list-ref lines line)])
          (let ([end (min char (string-length ln))])
            (let ([start (find-word-start ln (max 0 (- end 1)))])
              (substring ln start end)))))))

  (define (find-word-start str pos)
    (let loop ([i pos])
      (if (or (= i 0)
              (identifier-char? (string-ref str (- i 1))))
        (if (= i 0)
          0
          (if (identifier-char? (string-ref str (- i 1)))
            (loop (- i 1))
            i))
        i)))

  (define (find-word-end str pos)
    (let ([len (string-length str)])
      (let loop ([i pos])
        (if (or (= i len)
                (not (identifier-char? (string-ref str i))))
          i
          (loop (+ i 1))))))

  (define (identifier-char? ch)
    (and (char? ch)
         (or (char-alphabetic? ch)
             (char-numeric? ch)
             (memv ch '(#\- #\_ #\! #\? #\/ #\* #\+ #\= #\< #\> #\. #\@ #\$)))))

  (define (string-split-lines str)
    (let loop ([chars (string->list str)] [current '()] [lines '()])
      (cond
        [(null? chars)
         (reverse (cons (list->string (reverse current)) lines))]
        [(char=? (car chars) #\newline)
         (loop (cdr chars) '() (cons (list->string (reverse current)) lines))]
        [else
         (loop (cdr chars) (cons (car chars) current) lines)])))

  (define (string-contains-ci haystack needle)
    (let ([h (string-downcase haystack)]
          [n (string-downcase needle)]
          [hlen (string-length haystack)]
          [nlen (string-length needle)])
      (if (= nlen 0) #t
        (let loop ([i 0])
          (cond
            [(> (+ i nlen) hlen) #f]
            [(string=? (substring h i (+ i nlen)) n) #t]
            [else (loop (+ i 1))])))))

  ;; Find all references to a symbol in documents
  (define (find-references symbol docs)
    (let loop ([docs docs] [acc '()])
      (if (null? docs)
        (reverse acc)
        (let* ([doc (car docs)]
               [uri (car doc)]
               [text (cdr doc)]
               [refs (find-symbol-occurrences symbol uri text)])
          (loop (cdr docs) (append (reverse refs) acc))))))

  (define (find-symbol-occurrences symbol uri text)
    (let ([lines (string-split-lines text)]
          [slen (string-length symbol)])
      (let loop ([lnum 0] [lns lines] [acc '()])
        (if (null? lns)
          acc
          (let ([ln (car lns)])
            (let inner ([i 0] [acc acc])
              (let ([found (string-search ln symbol i)])
                (if found
                  (let* ([pos  (make-position lnum found)]
                         [endp (make-position lnum (+ found slen))]
                         [rng  (make-range pos endp)]
                         [loc  (json-obj "uri" uri "range" (range->json rng))])
                    (inner (+ found 1) (cons loc acc)))
                  (loop (+ lnum 1) (cdr lns) acc)))))))))

  (define (string-search haystack needle start)
    (let ([hlen (string-length haystack)]
          [nlen (string-length needle)])
      (let loop ([i start])
        (cond
          [(> (+ i nlen) hlen) #f]
          [(string=? (substring haystack i (+ i nlen)) needle) i]
          [else (loop (+ i 1))]))))

  (define (string-trim-right str)
    (let loop ([i (- (string-length str) 1)])
      (if (< i 0)
        ""
        (if (char-whitespace? (string-ref str i))
          (loop (- i 1))
          (substring str 0 (+ i 1))))))

  ) ;; end library
