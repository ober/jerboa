#!chezscheme
;;; (std misc highlight) — Syntax highlighting for Scheme source code
;;;
;;; Tokenizes Scheme source and applies ANSI color codes or returns SXML.
;;;
;;; (highlight-scheme "(define x 42)")  => colored ANSI string
;;; (highlight-scheme/sxml "(if #t \"yes\")")  => SXML with categories
;;; (highlight-to-port code port)
;;; (with-theme my-theme (lambda () (highlight-scheme code)))

(library (std misc highlight)
  (export highlight-scheme
          highlight-scheme/sxml
          highlight-to-port
          make-theme
          with-theme
          default-theme
          token-categories)
  (import (chezscheme))

  ;; ========== Token categories ==========

  (define token-categories
    '(keyword string number comment boolean paren symbol char whitespace))

  ;; ========== ANSI escape helpers ==========

  (define esc "\x1b;")

  (define (ansi . codes)
    (string-append esc "[" (apply string-append codes) "m"))

  (define ansi-reset (ansi "0"))

  ;; ========== Themes ==========

  ;; A theme is an alist of (category . ansi-code-string)
  (define default-theme
    `((keyword  . ,(ansi "1;34"))    ; bold blue
      (string   . ,(ansi "32"))      ; green
      (number   . ,(ansi "36"))      ; cyan
      (comment  . ,(ansi "2"))       ; dim/gray
      (boolean  . ,(ansi "35"))      ; magenta
      (paren    . ,(ansi "0"))       ; default
      (symbol   . ,(ansi "0"))       ; default
      (char     . ,(ansi "33"))      ; yellow
      (whitespace . #f)))            ; no styling

  (define current-theme (make-parameter default-theme))

  (define (make-theme alist)
    ;; alist of (category . ansi-string-or-#f)
    ;; Fills in defaults for missing categories
    (map (lambda (default)
           (let ([override (assq (car default) alist)])
             (if override override default)))
         default-theme))

  (define-syntax with-theme
    (syntax-rules ()
      [(_ theme body ...)
       (parameterize ([current-theme theme])
         body ...)]))

  ;; ========== Keywords ==========

  (define scheme-keywords
    '("define" "define-syntax" "define-record-type" "define-condition-type"
      "lambda" "let" "let*" "letrec" "letrec*" "let-values" "let*-values"
      "if" "cond" "case" "when" "unless" "and" "or" "not"
      "begin" "do" "set!"
      "quote" "quasiquote" "unquote" "unquote-splicing"
      "syntax-rules" "syntax-case" "with-syntax"
      "import" "export" "library"
      "define-library" "include" "include-ci"
      "guard" "raise" "with-exception-handler"
      "call-with-current-continuation" "call/cc"
      "call-with-values" "values" "receive"
      "dynamic-wind" "parameterize" "make-parameter"
      "else" "=>" "..."
      "define-macro" "define-structure" "define-record"
      "syntax" "datum->syntax" "syntax->datum"
      "match" "for-each" "map" "apply"))

  (define keyword-set
    (let ([ht (make-hashtable string-hash string=?)])
      (for-each (lambda (kw) (hashtable-set! ht kw #t)) scheme-keywords)
      ht))

  (define (keyword? s)
    (hashtable-ref keyword-set s #f))

  ;; ========== Lexer ==========

  ;; A token is (category . text)
  ;; The lexer scans through the string character by character.

  (define (delimiter? c)
    (or (char-whitespace? c)
        (memv c '(#\( #\) #\[ #\] #\{ #\} #\" #\; #\#))))

  (define (initial? c)
    (or (char-alphabetic? c)
        (memv c '(#\! #\$ #\% #\& #\* #\/ #\: #\< #\= #\> #\? #\^ #\_ #\~))))

  (define (subsequent? c)
    (or (initial? c)
        (char-numeric? c)
        (memv c '(#\+ #\- #\. #\@))))

  (define (tokenize str)
    (let ([len (string-length str)]
          [tokens '()])

      (define (emit! cat text)
        (set! tokens (cons (cons cat text) tokens)))

      (define (substring* start end)
        (substring str start end))

      (define (scan-whitespace i)
        (let loop ([j i])
          (if (and (< j len) (char-whitespace? (string-ref str j)))
              (loop (+ j 1))
              (begin (emit! 'whitespace (substring* i j))
                     j))))

      (define (scan-line-comment i)
        ;; i points to the ;
        (let loop ([j i])
          (if (or (>= j len) (char=? (string-ref str j) #\newline))
              (begin (emit! 'comment (substring* i j))
                     j)
              (loop (+ j 1)))))

      (define (scan-block-comment i)
        ;; i points to the # before |
        (let loop ([j (+ i 2)] [depth 1])
          (cond
            [(>= j len)
             (emit! 'comment (substring* i j))
             j]
            [(and (< (+ j 1) len)
                  (char=? (string-ref str j) #\|)
                  (char=? (string-ref str (+ j 1)) #\#))
             (if (= depth 1)
                 (begin (emit! 'comment (substring* i (+ j 2)))
                        (+ j 2))
                 (loop (+ j 2) (- depth 1)))]
            [(and (< (+ j 1) len)
                  (char=? (string-ref str j) #\#)
                  (char=? (string-ref str (+ j 1)) #\|))
             (loop (+ j 2) (+ depth 1))]
            [else (loop (+ j 1) depth)])))

      (define (scan-string i)
        ;; i points to opening "
        (let loop ([j (+ i 1)])
          (cond
            [(>= j len)
             (emit! 'string (substring* i j))
             j]
            [(char=? (string-ref str j) #\\)
             ;; skip escaped char
             (loop (+ j 2))]
            [(char=? (string-ref str j) #\")
             (emit! 'string (substring* i (+ j 1)))
             (+ j 1)]
            [else (loop (+ j 1))])))

      (define (scan-symbol i)
        (let loop ([j i])
          (if (and (< j len) (not (delimiter? (string-ref str j))))
              (loop (+ j 1))
              (let ([text (substring* i j)])
                (cond
                  [(keyword? text) (emit! 'keyword text)]
                  [else (emit! 'symbol text)])
                j))))

      (define (number-text? s)
        ;; Check if the text looks like a Scheme number
        (let ([len (string-length s)])
          (and (> len 0)
               (or
                ;; Starts with digit
                (char-numeric? (string-ref s 0))
                ;; Starts with + or - followed by digit or .
                (and (>= len 2)
                     (memv (string-ref s 0) '(#\+ #\-))
                     (or (char-numeric? (string-ref s 1))
                         (char=? (string-ref s 1) #\.)))
                ;; Starts with . followed by digit
                (and (>= len 2)
                     (char=? (string-ref s 0) #\.)
                     (char-numeric? (string-ref s 1)))))))

      (define (scan-number-or-symbol i)
        ;; Collect the full token, then decide if it's a number
        (let loop ([j i])
          (if (and (< j len) (not (delimiter? (string-ref str j))))
              (loop (+ j 1))
              (let ([text (substring* i j)])
                (cond
                  [(number-text? text) (emit! 'number text)]
                  [(keyword? text) (emit! 'keyword text)]
                  [else (emit! 'symbol text)])
                j))))

      (define (scan-hash i)
        ;; i points to #
        (cond
          ;; Past end
          [(>= (+ i 1) len)
           (emit! 'symbol "#")
           (+ i 1)]
          ;; Block comment #| ... |#
          [(char=? (string-ref str (+ i 1)) #\|)
           (scan-block-comment i)]
          ;; Boolean #t, #f, #true, #false
          [(memv (string-ref str (+ i 1)) '(#\t #\f #\T #\F))
           (let loop ([j (+ i 2)])
             (if (and (< j len) (char-alphabetic? (string-ref str j)))
                 (loop (+ j 1))
                 (let ([text (substring* i j)])
                   (if (member text '("#t" "#f" "#true" "#false"
                                      "#T" "#F" "#TRUE" "#FALSE"))
                       (emit! 'boolean text)
                       ;; Could be something like #test — treat as symbol
                       (emit! 'symbol text))
                   j)))]
          ;; Character literal #\x
          [(char=? (string-ref str (+ i 1)) #\\)
           (cond
             ;; #\<name> like #\space, #\newline
             [(>= (+ i 2) len)
              (emit! 'char (substring* i (+ i 2)))
              (+ i 2)]
             [else
              (let loop ([j (+ i 2)])
                (if (and (< j len) (not (delimiter? (string-ref str j))))
                    (loop (+ j 1))
                    (let ([end (max (+ i 3) j)])
                      ;; At minimum take #\<char>
                      (let ([actual-end (if (> j (+ i 2)) j (min (+ i 3) len))])
                        (emit! 'char (substring* i actual-end))
                        actual-end))))])]
          ;; Datum comment #;
          [(char=? (string-ref str (+ i 1)) #\;)
           (emit! 'comment "#;")
           (+ i 2)]
          ;; Reader directives like #!chezscheme, #!eof, #!r6rs
          [(char=? (string-ref str (+ i 1)) #\!)
           (let loop ([j (+ i 2)])
             (if (and (< j len)
                      (not (char-whitespace? (string-ref str j)))
                      (not (delimiter? (string-ref str j))))
                 (loop (+ j 1))
                 (begin (emit! 'comment (substring* i j))
                        j)))]
          ;; Vector #(
          [(char=? (string-ref str (+ i 1)) #\()
           (emit! 'paren "#(")
           (+ i 2)]
          ;; Bytevector #vu8(
          [(and (>= (+ i 4) len)
                (char=? (string-ref str (+ i 1)) #\v))
           ;; scan to (
           (let loop ([j (+ i 1)])
             (cond
               [(>= j len)
                (emit! 'symbol (substring* i j))
                j]
               [(char=? (string-ref str j) #\()
                (emit! 'paren (substring* i (+ j 1)))
                (+ j 1)]
               [else (loop (+ j 1))]))]
          ;; Numeric prefix #e, #i, #b, #o, #d, #x
          [(memv (string-ref str (+ i 1)) '(#\e #\i #\b #\o #\d #\x
                                             #\E #\I #\B #\O #\D #\X))
           ;; Scan the full number
           (let loop ([j (+ i 2)])
             (if (and (< j len) (not (delimiter? (string-ref str j))))
                 (loop (+ j 1))
                 (begin (emit! 'number (substring* i j))
                        j)))]
          ;; Fallback
          [else
           (let loop ([j (+ i 1)])
             (if (and (< j len) (not (delimiter? (string-ref str j))))
                 (loop (+ j 1))
                 (begin (emit! 'symbol (substring* i j))
                        j)))]))

      ;; Main scan loop
      (let loop ([i 0])
        (when (< i len)
          (let ([c (string-ref str i)])
            (cond
              [(char-whitespace? c)
               (loop (scan-whitespace i))]
              [(char=? c #\;)
               (loop (scan-line-comment i))]
              [(char=? c #\")
               (loop (scan-string i))]
              [(or (char=? c #\() (char=? c #\))
                   (char=? c #\[) (char=? c #\])
                   (char=? c #\{) (char=? c #\}))
               (emit! 'paren (string c))
               (loop (+ i 1))]
              [(char=? c #\#)
               (loop (scan-hash i))]
              [(char=? c #\')
               (emit! 'keyword "'")
               (loop (+ i 1))]
              [(char=? c #\`)
               (emit! 'keyword "`")
               (loop (+ i 1))]
              [(and (char=? c #\,)
                    (< (+ i 1) len)
                    (char=? (string-ref str (+ i 1)) #\@))
               (emit! 'keyword ",@")
               (loop (+ i 2))]
              [(char=? c #\,)
               (emit! 'keyword ",")
               (loop (+ i 1))]
              [(or (char-numeric? c)
                   (and (memv c '(#\+ #\-))
                        (< (+ i 1) len)
                        (or (char-numeric? (string-ref str (+ i 1)))
                            (char=? (string-ref str (+ i 1)) #\.))))
               (loop (scan-number-or-symbol i))]
              [(and (char=? c #\.)
                    (< (+ i 1) len)
                    (char-numeric? (string-ref str (+ i 1))))
               (loop (scan-number-or-symbol i))]
              [else
               (loop (scan-symbol i))]))))

      (reverse tokens)))

  ;; ========== Rendering ==========

  (define (theme-color theme category)
    (let ([entry (assq category theme)])
      (if entry (cdr entry) #f)))

  (define (tokens->ansi-string tokens theme)
    (let ([port (open-output-string)])
      (for-each
        (lambda (tok)
          (let ([cat (car tok)]
                [text (cdr tok)])
            (let ([color (theme-color theme cat)])
              (when (and color (not (eq? cat 'whitespace)))
                (display color port))
              (display text port)
              (when (and color (not (eq? cat 'whitespace)))
                (display ansi-reset port)))))
        tokens)
      (get-output-string port)))

  (define (tokens->sxml tokens)
    ;; Returns (highlight (span (@ (class "category")) "text") ...)
    `(highlight
       ,@(map (lambda (tok)
                (let ([cat (car tok)]
                      [text (cdr tok)])
                  (if (eq? cat 'whitespace)
                      text
                      `(span (@ (class ,(symbol->string cat))) ,text))))
              tokens)))

  ;; ========== Public API ==========

  (define (highlight-scheme code)
    (let ([tokens (tokenize code)])
      (tokens->ansi-string tokens (current-theme))))

  (define (highlight-scheme/sxml code)
    (let ([tokens (tokenize code)])
      (tokens->sxml tokens)))

  (define highlight-to-port
    (case-lambda
      [(code port)
       (display (highlight-scheme code) port)]
      [(code port theme)
       (with-theme theme
         (display (highlight-scheme code) port))]))

) ;; end library
