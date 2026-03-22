#!chezscheme
;;; (std protobuf grammar) -- .proto file parser
;;;
;;; Recursive-descent parser for proto3 .proto files.
;;; Tokenizes the input then parses into Scheme records:
;;;   proto-file, proto-message, proto-field, proto-enum, proto-service
;;;
;;; Handles: syntax, package, import, message (with nesting), enum,
;;; service, oneof, repeated/optional labels, line and block comments.
;;;
;;; Usage:
;;;   (import (std protobuf grammar))
;;;   (define pf (read-proto-string "syntax = \"proto3\"; message Foo { int32 x = 1; }"))
;;;   (proto-file-syntax pf) => "proto3"

(library (std protobuf grammar)
  (export
    read-proto-file read-proto-string
    proto-file? proto-file-syntax proto-file-package
    proto-file-imports proto-file-messages proto-file-enums
    proto-file-services
    proto-message? proto-message-name proto-message-fields
    proto-field? proto-field-name proto-field-number
    proto-field-type proto-field-label
    proto-enum? proto-enum-name proto-enum-values
    proto-service? proto-service-name proto-service-methods)

  (import (chezscheme))

  ;; ========== Record types ==========

  (define-record-type proto-file
    (fields syntax package imports messages enums services))

  (define-record-type proto-message
    (fields name fields))

  (define-record-type proto-field
    (fields name number type label))

  (define-record-type proto-enum
    (fields name values))

  ;; enum value: (name . number)
  ;; service method: (name input-type output-type)

  (define-record-type proto-service
    (fields name methods))

  ;; ========== Tokenizer ==========
  ;;
  ;; Token types:
  ;;   (ident . "foo")
  ;;   (string . "bar")
  ;;   (number . 42)
  ;;   (punct . #\;)
  ;;   (punct . #\{)  etc.

  (define (char-ident-start? c)
    (or (char-alphabetic? c) (char=? c #\_)))

  (define (char-ident? c)
    (or (char-alphabetic? c) (char-numeric? c)
        (char=? c #\_) (char=? c #\.)))

  (define (proto-whitespace? c)
    (or (char=? c #\space) (char=? c #\tab)
        (char=? c #\newline) (char=? c #\return)))

  (define (tokenize str)
    ;; Returns a list of tokens from string str.
    (let ([len (string-length str)])
      (let loop ([i 0] [tokens '()])
        (if (>= i len)
            (reverse tokens)
            (let ([c (string-ref str i)])
              (cond
                ;; Whitespace -- skip
                [(proto-whitespace? c)
                 (loop (+ i 1) tokens)]

                ;; Line comment
                [(and (char=? c #\/)
                      (< (+ i 1) len)
                      (char=? (string-ref str (+ i 1)) #\/))
                 (let skip ([j (+ i 2)])
                   (if (or (>= j len) (char=? (string-ref str j) #\newline))
                       (loop (if (>= j len) j (+ j 1)) tokens)
                       (skip (+ j 1))))]

                ;; Block comment
                [(and (char=? c #\/)
                      (< (+ i 1) len)
                      (char=? (string-ref str (+ i 1)) #\*))
                 (let skip ([j (+ i 2)])
                   (cond
                     [(>= j len)
                      (error 'tokenize "unterminated block comment")]
                     [(and (char=? (string-ref str j) #\*)
                           (< (+ j 1) len)
                           (char=? (string-ref str (+ j 1)) #\/))
                      (loop (+ j 2) tokens)]
                     [else (skip (+ j 1))]))]

                ;; String literal
                [(char=? c #\")
                 (let build ([j (+ i 1)] [chars '()])
                   (cond
                     [(>= j len)
                      (error 'tokenize "unterminated string literal")]
                     [(char=? (string-ref str j) #\\)
                      (if (>= (+ j 1) len)
                          (error 'tokenize "unterminated escape in string")
                          (let ([esc (string-ref str (+ j 1))])
                            (build (+ j 2)
                                   (cons (case esc
                                           [(#\n) #\newline]
                                           [(#\t) #\tab]
                                           [(#\\) #\\]
                                           [(#\") #\"]
                                           [else esc])
                                         chars))))]
                     [(char=? (string-ref str j) #\")
                      (loop (+ j 1)
                            (cons (cons 'string (list->string (reverse chars)))
                                  tokens))]
                     [else
                      (build (+ j 1) (cons (string-ref str j) chars))]))]

                ;; Number (integers, including negative)
                [(or (char-numeric? c)
                     (and (char=? c #\-)
                          (< (+ i 1) len)
                          (char-numeric? (string-ref str (+ i 1)))))
                 (let build ([j (if (char=? c #\-) (+ i 1) i)] [start i])
                   (if (and (< j len) (char-numeric? (string-ref str j)))
                       (build (+ j 1) start)
                       (loop j
                             (cons (cons 'number
                                         (string->number (substring str start j)))
                                   tokens))))]

                ;; Identifier / keyword
                [(char-ident-start? c)
                 (let build ([j (+ i 1)])
                   (if (and (< j len) (char-ident? (string-ref str j)))
                       (build (+ j 1))
                       (loop j
                             (cons (cons 'ident (substring str i j))
                                   tokens))))]

                ;; Punctuation
                [(memv c '(#\{ #\} #\( #\) #\; #\= #\, #\< #\> #\[ #\]))
                 (loop (+ i 1) (cons (cons 'punct c) tokens))]

                [else
                 (error 'tokenize
                        (string-append "unexpected character: "
                                       (string c)
                                       " at position "
                                       (number->string i)))]))))))

  ;; ========== Parser helpers ==========

  ;; Parser state: a mutable cell wrapping the token list.
  ;; We use a simple box (one-element vector) so parsers can consume tokens.

  (define (make-parser-state tokens)
    (vector tokens))

  (define (parser-tokens ps)
    (vector-ref ps 0))

  (define (parser-tokens-set! ps tokens)
    (vector-set! ps 0 tokens))

  (define (parser-peek ps)
    (let ([ts (parser-tokens ps)])
      (if (null? ts) #f (car ts))))

  (define (parser-advance! ps)
    (let ([ts (parser-tokens ps)])
      (when (null? ts)
        (error 'parser "unexpected end of input"))
      (let ([tok (car ts)])
        (parser-tokens-set! ps (cdr ts))
        tok)))

  (define (parser-eof? ps)
    (null? (parser-tokens ps)))

  (define (parser-expect-punct! ps ch)
    (let ([tok (parser-advance! ps)])
      (unless (and (eq? (car tok) 'punct) (char=? (cdr tok) ch))
        (error 'parser
               (string-append "expected '"
                              (string ch)
                              "' but got "
                              (token->string tok))))))

  (define (parser-expect-ident! ps)
    (let ([tok (parser-advance! ps)])
      (unless (eq? (car tok) 'ident)
        (error 'parser
               (string-append "expected identifier but got "
                              (token->string tok))))
      (cdr tok)))

  (define (parser-expect-string! ps)
    (let ([tok (parser-advance! ps)])
      (unless (eq? (car tok) 'string)
        (error 'parser
               (string-append "expected string but got "
                              (token->string tok))))
      (cdr tok)))

  (define (parser-expect-number! ps)
    (let ([tok (parser-advance! ps)])
      (unless (eq? (car tok) 'number)
        (error 'parser
               (string-append "expected number but got "
                              (token->string tok))))
      (cdr tok)))

  (define (parser-peek-punct? ps ch)
    (let ([tok (parser-peek ps)])
      (and tok (eq? (car tok) 'punct) (char=? (cdr tok) ch))))

  (define (parser-peek-ident? ps name)
    (let ([tok (parser-peek ps)])
      (and tok (eq? (car tok) 'ident) (string=? (cdr tok) name))))

  (define (token->string tok)
    (if (not tok)
        "EOF"
        (case (car tok)
          [(ident)  (string-append "identifier '" (cdr tok) "'")]
          [(string) (string-append "string \"" (cdr tok) "\"")]
          [(number) (string-append "number " (number->string (cdr tok)))]
          [(punct)  (string-append "'" (string (cdr tok)) "'")]
          [else     "unknown token"])))

  ;; ========== Standard proto types ==========

  (define *proto-standard-types*
    '("int32" "int64" "uint32" "uint64" "sint32" "sint64"
      "fixed32" "fixed64" "sfixed32" "sfixed64"
      "bool" "string" "bytes" "float" "double"))

  ;; ========== Parse field type ==========
  ;; A field type is an identifier, possibly dotted (e.g. "google.protobuf.Timestamp"),
  ;; or a map type: map<KeyType, ValueType>.

  (define (parse-field-type! ps)
    (let ([tok (parser-peek ps)])
      (cond
        ;; map<K, V>
        [(and tok (eq? (car tok) 'ident) (string=? (cdr tok) "map"))
         (parser-advance! ps)
         (parser-expect-punct! ps #\<)
         (let* ([key-type (parser-expect-ident! ps)]
                [_ (parser-expect-punct! ps #\,)]
                [val-type (parse-field-type! ps)])
           (parser-expect-punct! ps #\>)
           (string-append "map<" key-type ", " val-type ">"))]
        ;; Normal type (possibly dotted)
        [(and tok (eq? (car tok) 'ident))
         (parser-expect-ident! ps)]
        [else
         (error 'parser
                (string-append "expected type but got "
                               (token->string tok)))])))

  ;; ========== Parse enum ==========

  (define (parse-enum! ps)
    (parser-expect-ident! ps) ; consume "enum"
    (let ([name (parser-expect-ident! ps)])
      (parser-expect-punct! ps #\{)
      (let loop ([values '()])
        (cond
          [(parser-peek-punct? ps #\})
           (parser-advance! ps)
           ;; Optional trailing semicolon
           (when (parser-peek-punct? ps #\;)
             (parser-advance! ps))
           (make-proto-enum name (reverse values))]
          ;; option ... ; -- skip options inside enums
          [(parser-peek-ident? ps "option")
           (skip-option! ps)
           (loop values)]
          ;; reserved ... ; -- skip reserved
          [(parser-peek-ident? ps "reserved")
           (skip-to-semicolon! ps)
           (loop values)]
          [else
           (let* ([vname (parser-expect-ident! ps)]
                  [_ (parser-expect-punct! ps #\=)]
                  [vnum (parser-expect-number! ps)])
             ;; skip optional [deprecated = true] etc.
             (when (parser-peek-punct? ps #\[)
               (skip-brackets! ps))
             (parser-expect-punct! ps #\;)
             (loop (cons (cons vname vnum) values)))]))))

  ;; ========== Parse message ==========

  (define (parse-message! ps)
    (parser-expect-ident! ps) ; consume "message"
    (let ([name (parser-expect-ident! ps)])
      (parser-expect-punct! ps #\{)
      (let loop ([fields '()])
        (cond
          [(parser-peek-punct? ps #\})
           (parser-advance! ps)
           ;; Optional trailing semicolon
           (when (parser-peek-punct? ps #\;)
             (parser-advance! ps))
           (make-proto-message name (reverse fields))]

          ;; Nested message -- parse and add as a field with label 'message
          [(parser-peek-ident? ps "message")
           (let ([nested (parse-message! ps)])
             (loop (cons (make-proto-field
                           (proto-message-name nested)
                           0
                           nested
                           'message)
                         fields)))]

          ;; Nested enum -- parse and add as a field with label 'enum
          [(parser-peek-ident? ps "enum")
           (let ([nested (parse-enum! ps)])
             (loop (cons (make-proto-field
                           (proto-enum-name nested)
                           0
                           nested
                           'enum)
                         fields)))]

          ;; oneof block
          [(parser-peek-ident? ps "oneof")
           (let ([oneof-fields (parse-oneof! ps)])
             (loop (append (reverse oneof-fields) fields)))]

          ;; option ... ; -- skip
          [(parser-peek-ident? ps "option")
           (skip-option! ps)
           (loop fields)]

          ;; reserved ... ; -- skip
          [(parser-peek-ident? ps "reserved")
           (skip-to-semicolon! ps)
           (loop fields)]

          ;; extensions ... ; -- skip
          [(parser-peek-ident? ps "extensions")
           (skip-to-semicolon! ps)
           (loop fields)]

          ;; map field or regular field
          [else
           (let ([field (parse-field! ps)])
             (loop (cons field fields)))]))))

  ;; ========== Parse oneof ==========

  (define (parse-oneof! ps)
    (parser-expect-ident! ps) ; consume "oneof"
    (let ([oneof-name (parser-expect-ident! ps)])
      (parser-expect-punct! ps #\{)
      (let loop ([fields '()])
        (cond
          [(parser-peek-punct? ps #\})
           (parser-advance! ps)
           (reverse fields)]
          ;; option ... ; -- skip
          [(parser-peek-ident? ps "option")
           (skip-option! ps)
           (loop fields)]
          [else
           (let* ([ftype (parse-field-type! ps)]
                  [fname (parser-expect-ident! ps)]
                  [_ (parser-expect-punct! ps #\=)]
                  [fnum (parser-expect-number! ps)])
             ;; skip optional field options [...]
             (when (parser-peek-punct? ps #\[)
               (skip-brackets! ps))
             (parser-expect-punct! ps #\;)
             (loop (cons (make-proto-field fname fnum ftype
                                           (string->symbol
                                             (string-append "oneof:" oneof-name)))
                         fields)))]))))

  ;; ========== Parse field ==========

  (define (parse-field! ps)
    (let* ([tok (parser-peek ps)]
           [label
            (cond
              [(and tok (eq? (car tok) 'ident)
                    (string=? (cdr tok) "repeated"))
               (parser-advance! ps)
               'repeated]
              [(and tok (eq? (car tok) 'ident)
                    (string=? (cdr tok) "optional"))
               (parser-advance! ps)
               'optional]
              [(and tok (eq? (car tok) 'ident)
                    (string=? (cdr tok) "required"))
               (parser-advance! ps)
               'required]
              [else 'singular])]
           [ftype (parse-field-type! ps)]
           [fname (parser-expect-ident! ps)]
           [_ (parser-expect-punct! ps #\=)]
           [fnum (parser-expect-number! ps)])
      ;; skip optional field options [...]
      (when (parser-peek-punct? ps #\[)
        (skip-brackets! ps))
      (parser-expect-punct! ps #\;)
      (make-proto-field fname fnum ftype label)))

  ;; ========== Parse service ==========

  (define (parse-service! ps)
    (parser-expect-ident! ps) ; consume "service"
    (let ([name (parser-expect-ident! ps)])
      (parser-expect-punct! ps #\{)
      (let loop ([methods '()])
        (cond
          [(parser-peek-punct? ps #\})
           (parser-advance! ps)
           ;; Optional trailing semicolon
           (when (parser-peek-punct? ps #\;)
             (parser-advance! ps))
           (make-proto-service name (reverse methods))]

          ;; option ... ; -- skip
          [(parser-peek-ident? ps "option")
           (skip-option! ps)
           (loop methods)]

          ;; rpc MethodName (InputType) returns (OutputType) { ... } or ;
          [(parser-peek-ident? ps "rpc")
           (parser-advance! ps) ; consume "rpc"
           (let* ([mname (parser-expect-ident! ps)]
                  [_ (parser-expect-punct! ps #\()]
                  ;; handle optional "stream" keyword
                  [input-stream?
                   (and (parser-peek-ident? ps "stream")
                        (begin (parser-advance! ps) #t))]
                  [input-type (parse-field-type! ps)]
                  [_ (parser-expect-punct! ps #\))]
                  [_ (let ([tok (parser-advance! ps)])
                       (unless (and (eq? (car tok) 'ident)
                                    (string=? (cdr tok) "returns"))
                         (error 'parser "expected 'returns' in rpc")))]
                  [_ (parser-expect-punct! ps #\()]
                  [output-stream?
                   (and (parser-peek-ident? ps "stream")
                        (begin (parser-advance! ps) #t))]
                  [output-type (parse-field-type! ps)]
                  [_ (parser-expect-punct! ps #\))])
             ;; rpc body: either semicolon or { options }
             (cond
               [(parser-peek-punct? ps #\;)
                (parser-advance! ps)]
               [(parser-peek-punct? ps #\{)
                (parser-advance! ps)
                (let skip-body ()
                  (cond
                    [(parser-peek-punct? ps #\})
                     (parser-advance! ps)]
                    [else
                     (parser-advance! ps)
                     (skip-body)]))]
               [else (void)])
             (loop (cons (list mname input-type output-type) methods)))]

          [else
           ;; skip unknown tokens
           (parser-advance! ps)
           (loop methods)]))))

  ;; ========== Skip helpers ==========

  (define (skip-option! ps)
    ;; Skip "option ... ;"
    (parser-advance! ps) ; consume "option"
    (skip-to-semicolon! ps))

  (define (skip-to-semicolon! ps)
    (let loop ()
      (let ([tok (parser-advance! ps)])
        (unless (and (eq? (car tok) 'punct) (char=? (cdr tok) #\;))
          ;; If we hit a nested { }, skip the block
          (when (and (eq? (car tok) 'punct) (char=? (cdr tok) #\{))
            (skip-braces! ps))
          (loop)))))

  (define (skip-braces! ps)
    ;; Skip until matching }. Opening { already consumed.
    (let loop ([depth 1])
      (when (> depth 0)
        (let ([tok (parser-advance! ps)])
          (cond
            [(and (eq? (car tok) 'punct) (char=? (cdr tok) #\{))
             (loop (+ depth 1))]
            [(and (eq? (car tok) 'punct) (char=? (cdr tok) #\}))
             (loop (- depth 1))]
            [else (loop depth)])))))

  (define (skip-brackets! ps)
    ;; Skip [...] including nested brackets.
    (parser-expect-punct! ps #\[)
    (let loop ([depth 1])
      (when (> depth 0)
        (let ([tok (parser-advance! ps)])
          (cond
            [(and (eq? (car tok) 'punct) (char=? (cdr tok) #\[))
             (loop (+ depth 1))]
            [(and (eq? (car tok) 'punct) (char=? (cdr tok) #\]))
             (loop (- depth 1))]
            [else (loop depth)])))))

  ;; ========== Top-level parser ==========

  (define (parse-proto tokens)
    (let ([ps (make-parser-state tokens)])
      (let loop ([syntax #f]
                 [package #f]
                 [imports '()]
                 [messages '()]
                 [enums '()]
                 [services '()])
        (if (parser-eof? ps)
            (make-proto-file
              (or syntax "proto3")
              (or package "")
              (reverse imports)
              (reverse messages)
              (reverse enums)
              (reverse services))
            (let ([tok (parser-peek ps)])
              (cond
                ;; syntax = "proto3";
                [(parser-peek-ident? ps "syntax")
                 (parser-advance! ps)
                 (parser-expect-punct! ps #\=)
                 (let ([s (parser-expect-string! ps)])
                   (parser-expect-punct! ps #\;)
                   (loop s package imports messages enums services))]

                ;; package foo.bar;
                [(parser-peek-ident? ps "package")
                 (parser-advance! ps)
                 (let ([pkg (parser-expect-ident! ps)])
                   (parser-expect-punct! ps #\;)
                   (loop syntax pkg imports messages enums services))]

                ;; import "file.proto";
                ;; import public "file.proto";
                ;; import weak "file.proto";
                [(parser-peek-ident? ps "import")
                 (parser-advance! ps)
                 ;; skip optional "public" or "weak"
                 (when (or (parser-peek-ident? ps "public")
                           (parser-peek-ident? ps "weak"))
                   (parser-advance! ps))
                 (let ([path (parser-expect-string! ps)])
                   (parser-expect-punct! ps #\;)
                   (loop syntax package (cons path imports)
                         messages enums services))]

                ;; option ... ; (top-level options, skip)
                [(parser-peek-ident? ps "option")
                 (skip-option! ps)
                 (loop syntax package imports messages enums services)]

                ;; message
                [(parser-peek-ident? ps "message")
                 (let ([msg (parse-message! ps)])
                   (loop syntax package imports
                         (cons msg messages) enums services))]

                ;; enum
                [(parser-peek-ident? ps "enum")
                 (let ([en (parse-enum! ps)])
                   (loop syntax package imports
                         messages (cons en enums) services))]

                ;; service
                [(parser-peek-ident? ps "service")
                 (let ([svc (parse-service! ps)])
                   (loop syntax package imports
                         messages enums (cons svc services)))]

                ;; semicolons at top level -- skip
                [(parser-peek-punct? ps #\;)
                 (parser-advance! ps)
                 (loop syntax package imports messages enums services)]

                [else
                 (error 'parser
                        (string-append
                          "unexpected top-level token: "
                          (token->string tok)))]))))))

  ;; ========== Public API ==========

  (define (read-proto-string str)
    (parse-proto (tokenize str)))

  (define (read-proto-file path)
    (let ([content (call-with-input-file path
                     (lambda (port)
                       (get-string-all port)))])
      (read-proto-string content)))

) ;; end library
