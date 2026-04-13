#!chezscheme
;;; reader.sls -- Gerbil-compatible reader for Jerboa
;;;
;;; Default mode:
;;;   [...] → (list ...)       — Clojure-style vector literal (always)
;;;   {@} → method dispatch    — {method obj args...} → (~ obj 'method args...)
;;;   #{...} → set literal     — (hash-set item ...) (always)
;;;   @expr → (deref expr)     — Clojure-style deref (always)
;;;   :pkg/mod → (pkg mod)     — Gerbil module-path shorthand
;;;   name: → keyword          — trailing-colon keyword
;;;
;;; Clojure reader mode  (reader-cloj-mode) → #t :
;;;   {}  → hash map literal   — {k1 v1 ...} → (plist->hash-table (list k1 v1 ...))
;;;   #() → anonymous function — #(+ % 1) → (fn-literal + % 1)
;;;   :name → keyword          — leading-colon Clojure keyword
;;;   nil → #f, true → #t, false → #f
;;;
;;; Activation: put  #!cloj  at the top of any .ss file, or call
;;;   (reader-cloj-mode #t) programmatically.

(library (jerboa reader)
  (export
    jerboa-read
    jerboa-read-all
    jerboa-read-file
    jerboa-read-string
    reader-cloj-mode
    *max-read-depth*
    *max-block-comment-depth*
    *max-string-length*
    *max-list-length*
    *max-symbol-length*
    source-location source-location?
    source-location-path source-location-line source-location-column
    make-source-location
    annotated-datum annotated-datum?
    annotated-datum-value annotated-datum-source
    make-annotated-datum)

  (import (chezscheme))

  (define *max-read-depth* (make-parameter 1000))
  (define *max-block-comment-depth* (make-parameter 1000))
  (define *max-string-length* (make-parameter (* 10 1024 1024)))  ;; 10MB default
  (define *max-list-length* (make-parameter 1000000))             ;; 1M elements default
  (define *max-symbol-length* (make-parameter 4096))              ;; 4KB default

  ;; When #t, enables Clojure reader syntax:
  ;;   {}  → hash map,  #() → anonymous fn,  :name → keyword,
  ;;   nil → #f,  true → #t,  false → #f
  ;; Activated by  #!cloj  directive or  (reader-cloj-mode #t)  call.
  (define reader-cloj-mode (make-parameter #f))

  ;;;; Source locations
  (define-record-type source-location
    (fields path line column)
    (sealed #t))

  (define-record-type annotated-datum
    (fields value source)
    (sealed #t))

  ;;;; Reader state
  (define-record-type reader-state
    (fields
      port
      (mutable line)
      (mutable column)
      (mutable path)
      (mutable peeked))
    (sealed #t))

  (define (make-reader port . path)
    (make-reader-state port 1 0 (if (null? path) #f (car path)) #f))

  ;;;; Character I/O with tracking

  (define (reader-peek rs)
    (or (reader-state-peeked rs)
        (let ((ch (read-char (reader-state-port rs))))
          (reader-state-peeked-set! rs ch)
          ch)))

  (define (reader-next! rs)
    (let ((ch (or (reader-state-peeked rs)
                  (read-char (reader-state-port rs)))))
      (reader-state-peeked-set! rs #f)
      (when (char? ch)
        (if (char=? ch #\newline)
            (begin
              (reader-state-line-set! rs (fx+ (reader-state-line rs) 1))
              (reader-state-column-set! rs 0))
            (reader-state-column-set! rs (fx+ (reader-state-column rs) 1))))
      ch))

  (define (reader-location rs)
    (make-source-location
      (reader-state-path rs)
      (reader-state-line rs)
      (reader-state-column rs)))

  (define (annotate rs value loc)
    (if (reader-state-path rs)
        (make-annotated-datum value loc)
        value))

  ;;;; Character classification

  (define (delimiter? ch)
    (or (eof-object? ch)
        (char-whitespace? ch)
        (memv ch '(#\( #\) #\[ #\] #\{ #\} #\" #\; #\,))))

  (define (initial-ident? ch)
    (and (char? ch)
         (or (char-alphabetic? ch)
             (memv ch '(#\! #\$ #\% #\& #\* #\/ #\: #\< #\= #\> #\? #\^ #\_ #\~
                        #\+ #\- #\. #\@)))))

  (define (subsequent-ident? ch)
    (and (char? ch)
         (or (char-alphabetic? ch)
             (char-numeric? ch)
             (memv ch '(#\! #\$ #\% #\& #\* #\/ #\: #\< #\= #\> #\? #\^ #\_ #\~
                        #\+ #\- #\. #\@ #\#)))))

  ;;;; Comment skipping

  (define (skip-whitespace! rs)
    (let loop ()
      (let ((ch (reader-peek rs)))
        (cond
          ((eof-object? ch) (void))
          ((char-whitespace? ch)
           (reader-next! rs)
           (loop))
          ((char=? ch #\;)
           (skip-line-comment! rs)
           (loop))
          (else (void))))))

  (define (skip-line-comment! rs)
    (let loop ()
      (let ((ch (reader-next! rs)))
        (unless (or (eof-object? ch) (char=? ch #\newline))
          (loop)))))

  (define (skip-block-comment! rs depth)
    (let loop ((depth depth))
      (when (fx> depth 0)
        (when (fx> depth (*max-block-comment-depth*))
          (error 'jerboa-read "block comment nesting depth exceeded"
                 depth (*max-block-comment-depth*)))
        (let ((ch (reader-next! rs)))
          (cond
            ((eof-object? ch)
             (error 'jerboa-read "unterminated block comment"))
            ((char=? ch #\#)
             (let ((ch2 (reader-peek rs)))
               (if (and (char? ch2) (char=? ch2 #\|))
                   (begin (reader-next! rs) (loop (fx+ depth 1)))
                   (loop depth))))
            ((char=? ch #\|)
             (let ((ch2 (reader-peek rs)))
               (if (and (char? ch2) (char=? ch2 #\#))
                   (begin (reader-next! rs) (loop (fx- depth 1)))
                   (loop depth))))
            (else (loop depth)))))))

  ;;;; Main reader dispatch

  (define read-datum
    (case-lambda
      ((rs) (read-datum rs 0))
      ((rs depth)
       (when (> depth (*max-read-depth*))
         (error 'jerboa-read "maximum nesting depth exceeded"
                depth (*max-read-depth*)))
       (read-datum-impl rs depth))))

  (define (read-datum-impl rs depth)
    (skip-whitespace! rs)
    (let ((loc (reader-location rs))
          (ch (reader-peek rs)))
      (cond
        ((eof-object? ch) (eof-object))

        ;; Lists
        ((char=? ch #\()
         (reader-next! rs)
         (annotate rs (read-list rs #\) (+ depth 1)) loc))

        ;; Square brackets → (list ...) — Clojure-compatible vector literal
        ;; [1 2 3] reads as (list 1 2 3), enabling persistent-vector semantics
        ;; and Clojure-style let/for binding vectors.
        ((char=? ch #\[)
         (reader-next! rs)
         (annotate rs (cons 'list (read-list rs #\] (+ depth 1))) loc))

        ;; Curly braces:
        ;;   cloj mode  → hash map literal  {k1 v1 ...} → (plist->hash-table (list k1 v1 ...))
        ;;   default    → method dispatch   {method obj args...} → (~ obj 'method args...)
        ((char=? ch #\{)
         (reader-next! rs)
         (let ((items (read-list rs #\} (+ depth 1))))
           (if (reader-cloj-mode)
               ;; Clojure hash map literal
               (if (null? items)
                   (annotate rs '(make-hash-table) loc)
                   (begin
                     (when (odd? (length items))
                       (error 'jerboa-read
                         "map literal {} requires an even number of forms (key value ...)"
                         (length items)))
                     (annotate rs
                       (list 'plist->hash-table (cons 'list items))
                       loc)))
               ;; Default: Jerboa method dispatch
               (cond
                 ((null? items)
                  (error 'jerboa-read "empty method dispatch {}"))
                 ((null? (cdr items))
                  (error 'jerboa-read "method dispatch needs at least {method obj}"))
                 (else
                  (let ((method (car items)) (obj (cadr items)) (args (cddr items)))
                    (annotate rs
                      (cons* '~ obj (list 'quote method) args)
                      loc)))))))

        ;; Closing delimiters
        ((or (char=? ch #\)) (char=? ch #\]) (char=? ch #\}))
         (error 'jerboa-read "unexpected closing delimiter" ch
                (reader-state-line rs) (reader-state-column rs)))

        ;; String
        ((char=? ch #\")
         (reader-next! rs)
         (annotate rs (read-string-literal rs) loc))

        ;; Quote
        ((char=? ch #\')
         (reader-next! rs)
         (annotate rs (list 'quote (read-datum rs (+ depth 1))) loc))

        ;; Quasiquote
        ((char=? ch #\`)
         (reader-next! rs)
         (annotate rs (list 'quasiquote (read-datum rs (+ depth 1))) loc))

        ;; Unquote / unquote-splicing
        ((char=? ch #\,)
         (reader-next! rs)
         (let ((ch2 (reader-peek rs)))
           (if (and (char? ch2) (char=? ch2 #\@))
               (begin
                 (reader-next! rs)
                 (annotate rs (list 'unquote-splicing (read-datum rs (+ depth 1))) loc))
               (annotate rs (list 'unquote (read-datum rs (+ depth 1))) loc))))

        ;; @ → Clojure-style deref: @atom → (deref atom)
        ((char=? ch #\@)
         (reader-next! rs)
         (annotate rs (list 'deref (read-datum rs (+ depth 1))) loc))

        ;; Hash dispatch
        ((char=? ch #\#)
         (reader-next! rs)
         (read-hash rs loc depth))

        ;; Number or symbol starting with + or -
        ((or (char=? ch #\+) (char=? ch #\-))
         (read-number-or-symbol rs loc))

        ;; Number
        ((char-numeric? ch)
         (annotate rs (read-number rs) loc))

        ;; Symbol or keyword
        ((or (initial-ident? ch) (char=? ch #\|))
         (read-symbol-or-keyword rs loc))

        (else
         (reader-next! rs)
         (error 'jerboa-read "unexpected character" ch)))))

  ;;;; List reader

  (define read-list
    (case-lambda
      ((rs close-char) (read-list rs close-char 0))
      ((rs close-char depth) (read-list-impl rs close-char depth))))

  (define (read-list-impl rs close-char depth)
    (let loop ((acc '()) (count 0))
      (when (> count (*max-list-length*))
        (error 'jerboa-read "list exceeds maximum element count"
               count (*max-list-length*)))
      (skip-whitespace! rs)
      (let ((hash-datum (handle-hash-comments! rs)))
        (if hash-datum
          (loop (cons hash-datum acc) (fx+ count 1))
      (let ((ch (reader-peek rs)))
        (cond
          ((eof-object? ch)
           (error 'jerboa-read "unterminated list"))
          ((char=? ch close-char)
           (reader-next! rs)
           (reverse acc))
          ;; Dot for dotted pairs
          ((char=? ch #\.)
           (reader-next! rs)
           (let ((ch2 (reader-peek rs)))
             (cond
               ((delimiter? ch2)
                ;; Dotted pair
                (skip-whitespace! rs)
                (let ((tail (read-datum rs depth)))
                  (skip-whitespace! rs)
                  (let ((ch3 (reader-next! rs)))
                    (unless (and (char? ch3) (char=? ch3 close-char))
                      (error 'jerboa-read "expected closing delimiter after dot")))
                  (let build ((items acc) (result tail))
                    (if (null? items) result
                        (build (cdr items) (cons (car items) result))))))
               (else
                ;; Symbol starting with .
                (reader-state-peeked-set! rs ch2)
                (let ((loc (reader-location rs)))
                  (let ((sym (read-symbol-chars rs #\.)))
                    (loop (cons (annotate rs sym loc) acc) (fx+ count 1))))))))
          (else
           (let ((datum (read-datum rs depth)))
             (if (eof-object? datum)
                 (error 'jerboa-read "unterminated list")
                 (loop (cons datum acc) (fx+ count 1)))))))))))

  ;; Handle #| and #; comments inside lists.
  (define (handle-hash-comments! rs)
    (let ((ch (reader-peek rs)))
      (if (and (char? ch) (char=? ch #\#))
        (let ((loc (reader-location rs)))
          (reader-next! rs)
          (let ((ch2 (reader-peek rs)))
            (cond
              ((and (char? ch2) (char=? ch2 #\|))
               (reader-next! rs)
               (skip-block-comment! rs 1)
               (skip-whitespace! rs)
               (handle-hash-comments! rs))
              ((and (char? ch2) (char=? ch2 #\;))
               (reader-next! rs)
               (skip-whitespace! rs)
               (read-datum rs 0) ;; discard
               (skip-whitespace! rs)
               (handle-hash-comments! rs))
              (else
               (read-hash rs loc 0)))))
        #f)))

  ;;;; Hash dispatch (#)

  (define read-hash
    (case-lambda
      ((rs loc) (read-hash rs loc 0))
      ((rs loc depth) (read-hash-impl rs loc depth))))

  (define (read-hash-impl rs loc depth)
    (let ((ch (reader-peek rs)))
      (cond
        ((eof-object? ch) (error 'jerboa-read "unexpected EOF after #"))

        ;; #t, #f, #true, #false
        ((or (char=? ch #\t) (char=? ch #\T))
         (reader-next! rs)
         (let ((ch2 (reader-peek rs)))
           (cond
             ((or (eof-object? ch2) (delimiter? ch2))
              (annotate rs #t loc))
             ((char-alphabetic? ch2)
              (let ((rest (read-symbol-chars rs #\t)))
                (if (memq rest '(true True TRUE))
                    (annotate rs #t loc)
                    (error 'jerboa-read "invalid # syntax" rest))))
             (else (annotate rs #t loc)))))

        ((or (char=? ch #\f) (char=? ch #\F))
         (reader-next! rs)
         (let ((ch2 (reader-peek rs)))
           (cond
             ((or (eof-object? ch2) (delimiter? ch2))
              (annotate rs #f loc))
             ((char-alphabetic? ch2)
              (let ((rest (read-symbol-chars rs #\f)))
                (if (memq rest '(false False FALSE))
                    (annotate rs #f loc)
                    (error 'jerboa-read "invalid # syntax" rest))))
             (else (annotate rs #f loc)))))

        ;; #( — vector (default) or anonymous function (cloj mode)
        ;; cloj: #(+ % 1) → reads (+ % 1) as one form → (fn-literal (+ % 1))
        ;;       → (lambda (%1) (+ %1 1))
        ;; The ( is NOT consumed in cloj mode — read-datum reads the whole list.
        ((char=? ch #\()
         (if (reader-cloj-mode)
             (let ((body (read-datum rs (+ depth 1))))
               (annotate rs (list 'fn-literal body) loc))
             (begin
               (reader-next! rs)
               (let ((items (read-list rs #\) (+ depth 1))))
                 (annotate rs (list->vector items) loc)))))

        ;; #u8( bytevector
        ((char=? ch #\u)
         (reader-next! rs)
         (let ((ch2 (reader-next! rs)))
           (unless (and (char? ch2) (char=? ch2 #\8))
             (error 'jerboa-read "expected #u8("))
           (let ((ch3 (reader-next! rs)))
             (unless (and (char? ch3) (char=? ch3 #\())
               (error 'jerboa-read "expected #u8("))
             (let ((items (read-list rs #\) (+ depth 1))))
               (let ((raw-items (map (lambda (x)
                                       (if (annotated-datum? x)
                                         (annotated-datum-value x)
                                         x))
                                     items)))
                 ;; Validate all elements are valid u8 values (0-255)
                 (for-each (lambda (x)
                             (unless (and (fixnum? x) (fx>= x 0) (fx<= x 255))
                               (error 'jerboa-read
                                 "invalid bytevector element (must be 0-255)" x)))
                           raw-items)
                 (annotate rs (apply bytevector raw-items) loc))))))

        ;; #\ character
        ((char=? ch #\\)
         (reader-next! rs)
         (annotate rs (read-character rs) loc))

        ;; #! hash-bang
        ((char=? ch #\!)
         (reader-next! rs)
         (read-hash-bang rs loc depth))

        ;; #| block comment
        ((char=? ch #\|)
         (reader-next! rs)
         (skip-block-comment! rs 1)
         (read-datum rs depth))

        ;; #; datum comment
        ((char=? ch #\;)
         (reader-next! rs)
         (skip-whitespace! rs)
         (read-datum rs depth) ;; discard
         (read-datum rs depth)) ;; read real

        ;; #& box
        ((char=? ch #\&)
         (reader-next! rs)
         (annotate rs (box (read-datum rs (+ depth 1))) loc))

        ;; #' syntax quote
        ((char=? ch #\')
         (reader-next! rs)
         (annotate rs (list 'syntax (read-datum rs (+ depth 1))) loc))

        ;; #` syntax quasiquote
        ((char=? ch #\`)
         (reader-next! rs)
         (annotate rs (list 'quasisyntax (read-datum rs (+ depth 1))) loc))

        ;; #, syntax unquote
        ((char=? ch #\,)
         (reader-next! rs)
         (let ((ch2 (reader-peek rs)))
           (if (and (char? ch2) (char=? ch2 #\@))
               (begin
                 (reader-next! rs)
                 (annotate rs (list 'unsyntax-splicing (read-datum rs (+ depth 1))) loc))
               (annotate rs (list 'unsyntax (read-datum rs (+ depth 1))) loc))))

        ;; #x hex, #o octal, #b binary, #d decimal number
        ((or (char=? ch #\x) (char=? ch #\X))
         (reader-next! rs)
         (let ((str (read-number-chars rs)))
           (annotate rs (string->number (string-append "#x" str)) loc)))

        ((or (char=? ch #\o) (char=? ch #\O))
         (reader-next! rs)
         (let ((str (read-number-chars rs)))
           (annotate rs (string->number (string-append "#o" str)) loc)))

        ((or (char=? ch #\b) (char=? ch #\B))
         (reader-next! rs)
         (let ((str (read-number-chars rs)))
           (annotate rs (string->number (string-append "#b" str)) loc)))

        ((or (char=? ch #\d) (char=? ch #\D))
         (reader-next! rs)
         (let ((str (read-number-chars rs)))
           (annotate rs (string->number (string-append "#d" str)) loc)))

        ;; #< heredoc string (#<<DELIM ... DELIM)
        ((char=? ch #\<)
         (reader-next! rs)
         (let ((ch2 (reader-peek rs)))
           (if (and (char? ch2) (char=? ch2 #\<))
             (begin
               (reader-next! rs)
               (let ((delim (let dloop ((chars '()))
                              (let ((c (reader-peek rs)))
                                (cond
                                  ((or (eof-object? c) (char=? c #\newline) (char=? c #\return))
                                   (when (and (char? c) (or (char=? c #\newline) (char=? c #\return)))
                                     (reader-next! rs)
                                     (when (char=? c #\return)
                                       (let ((c2 (reader-peek rs)))
                                         (when (and (char? c2) (char=? c2 #\newline))
                                           (reader-next! rs)))))
                                   (list->string (reverse chars)))
                                  (else
                                   (reader-next! rs)
                                   (dloop (cons c chars))))))))
                 (define (build-heredoc-result lines)
                  (annotate rs
                    (let ((all (reverse lines)))
                      (if (null? all) ""
                        (let lp ((strs all) (acc (car all)))
                          (if (null? (cdr strs)) acc
                            (lp (cdr strs)
                                (string-append acc "\n" (cadr strs)))))))
                    loc))
                (let hloop ((lines '()))
                   (let lloop ((chars '()))
                     (let ((c (reader-next! rs)))
                       (cond
                         ((eof-object? c)
                          ;; Check if accumulated chars match delimiter
                          (let ((line (list->string (reverse chars))))
                            (if (string=? line delim)
                              (build-heredoc-result lines)
                              (error 'jerboa-read "unterminated heredoc"))))
                         ((or (char=? c #\newline) (char=? c #\return))
                          (when (char=? c #\return)
                            (let ((c2 (reader-peek rs)))
                              (when (and (char? c2) (char=? c2 #\newline))
                                (reader-next! rs))))
                          (let ((line (list->string (reverse chars))))
                            (if (string=? line delim)
                              (build-heredoc-result lines)
                              (hloop (cons line lines)))))
                         (else
                          (lloop (cons c chars)))))))))
             (error 'jerboa-read "invalid # dispatch" ch))))

        ;; #{...} → Clojure-style set literal
        ;; #{1 2 3} → (hash-set 1 2 3)
        ((char=? ch #\{)
         (reader-next! rs)
         (let ((items (read-list rs #\} (+ depth 1))))
           (annotate rs (cons 'hash-set items) loc)))

        ;; #r"..." raw string — backslashes are literal, no escape processing.
        ;; Only \" is handled so you can embed a double-quote inside.
        ((char=? ch #\r)
         (reader-next! rs)
         (let ((ch2 (reader-peek rs)))
           (unless (and (char? ch2) (char=? ch2 #\"))
             (error 'jerboa-read "expected \" after #r"))
           (reader-next! rs)  ;; consume opening "
           (annotate rs (read-raw-string rs) loc)))

        (else
         (error 'jerboa-read "invalid # dispatch" ch)))))

  ;; read-raw-string: read until closing ", passing all chars through verbatim.
  ;; \" is the only escape recognised — it produces a literal double-quote.
  (define (read-raw-string rs)
    (let loop ((chars '()))
      (let ((ch (reader-next! rs)))
        (cond
          ((eof-object? ch)
           (error 'jerboa-read "unterminated raw string"))
          ((char=? ch #\")
           (list->string (reverse chars)))
          ((and (char=? ch #\\)
                (let ((next (reader-peek rs)))
                  (and (char? next) (char=? next #\"))))
           ;; \" inside raw string → literal quote char
           (reader-next! rs)
           (loop (cons #\" chars)))
          (else
           (loop (cons ch chars)))))))

  ;; Read chars that could be part of a number literal
  (define (read-number-chars rs)
    (let loop ((acc '()))
      (let ((ch (reader-peek rs)))
        (if (and (char? ch)
                 (or (char-numeric? ch)
                     (and (char>=? ch #\a) (char<=? ch #\f))
                     (and (char>=? ch #\A) (char<=? ch #\F))
                     (char=? ch #\+) (char=? ch #\-)))
          (begin (reader-next! rs) (loop (cons ch acc)))
          (list->string (reverse acc))))))

  ;;;; Hash-bang reader

  (define (read-hash-bang rs loc depth)
    (let ((ch (reader-peek rs)))
      (cond
        ((or (eof-object? ch) (delimiter? ch))
         (error 'jerboa-read "incomplete #!"))
        (else
         (let ((name (read-hash-bang-name rs)))
           (case name
             ((void)     (annotate rs (void) loc))
             ((eof)      (annotate rs (eof-object) loc))
             ((optional) (annotate rs (void) loc))  ; placeholder
             ;; #!cloj — activate Clojure reader mode for the rest of this file
             ;; skips the directive itself, continues reading the next datum
             ((cloj)
              (reader-cloj-mode #t)
              (read-datum rs depth))
             (else
              (annotate rs (list (string->symbol "#!") name) loc))))))))

  (define (read-hash-bang-name rs)
    (let loop ((chars '()))
      (let ((ch (reader-peek rs)))
        (cond
          ((or (eof-object? ch) (delimiter? ch))
           (string->symbol (list->string (reverse chars))))
          (else
           (reader-next! rs)
           (loop (cons ch chars)))))))

  ;;;; Character reader

  (define (read-character rs)
    (let ((ch (reader-next! rs)))
      (cond
        ((eof-object? ch) (error 'jerboa-read "unexpected EOF in character"))
        ((or (eof-object? (reader-peek rs)) (delimiter? (reader-peek rs)))
         ch)
        (else
         (let loop ((chars (list ch)))
           (let ((ch2 (reader-peek rs)))
             (cond
               ((or (eof-object? ch2) (delimiter? ch2))
                (let ((name (string-downcase (list->string (reverse chars)))))
                  (cond
                    ((string=? name "space")     #\space)
                    ((string=? name "newline")   #\newline)
                    ((string=? name "tab")       #\tab)
                    ((string=? name "return")    #\return)
                    ((string=? name "nul")       #\nul)
                    ((string=? name "null")      #\nul)
                    ((string=? name "backspace") #\backspace)
                    ((string=? name "delete")    #\delete)
                    ((string=? name "escape")    #\x1B)
                    ((string=? name "alarm")     #\alarm)
                    ((string=? name "linefeed")  #\newline)
                    ((and (fx= (string-length name) 1))
                     (string-ref name 0))
                    ((and (fx>= (string-length name) 2)
                          (char=? (string-ref name 0) #\x))
                     (let ((n (string->number (substring name 1 (string-length name)) 16)))
                       (if n (integer->char n)
                           (error 'jerboa-read "invalid character name" name))))
                    (else
                     (error 'jerboa-read "unknown character name" name)))))
               (else
                (reader-next! rs)
                (loop (cons ch2 chars))))))))))

  ;;;; String reader

  (define (read-string-literal rs)
    (let loop ((chars '()) (len 0))
      (when (> len (*max-string-length*))
        (error 'jerboa-read "string literal exceeds maximum length"
               len (*max-string-length*)))
      (let ((ch (reader-next! rs)))
        (cond
          ((eof-object? ch) (error 'jerboa-read "unterminated string"))
          ((char=? ch #\") (list->string (reverse chars)))
          ((char=? ch #\\)
           (let ((esc (reader-next! rs)))
             (cond
               ((eof-object? esc) (error 'jerboa-read "unterminated string escape"))
               ((char=? esc #\n) (loop (cons #\newline chars) (fx+ len 1)))
               ((char=? esc #\t) (loop (cons #\tab chars) (fx+ len 1)))
               ((char=? esc #\r) (loop (cons #\return chars) (fx+ len 1)))
               ((char=? esc #\\) (loop (cons #\\ chars) (fx+ len 1)))
               ((char=? esc #\") (loop (cons #\" chars) (fx+ len 1)))
               ((char=? esc #\a) (loop (cons #\alarm chars) (fx+ len 1)))
               ((char=? esc #\b) (loop (cons #\backspace chars) (fx+ len 1)))
               ((char=? esc #\0) (loop (cons #\nul chars) (fx+ len 1)))
               ((char=? esc #\x)
                (let hex-loop ((hex-chars '()))
                  (let ((hch (reader-peek rs)))
                    (cond
                      ((and (char? hch) (char=? hch #\;))
                       (reader-next! rs)
                       (let ((n (string->number (list->string (reverse hex-chars)) 16)))
                         (if n (loop (cons (integer->char n) chars) (fx+ len 1))
                             (error 'jerboa-read "invalid hex escape"))))
                      ((and (char? hch)
                            (or (char-numeric? hch)
                                (memv (char-downcase hch) '(#\a #\b #\c #\d #\e #\f))))
                       (reader-next! rs)
                       (hex-loop (cons hch hex-chars)))
                      (else
                       (if (null? hex-chars)
                           (error 'jerboa-read "empty hex escape")
                           (let ((n (string->number (list->string (reverse hex-chars)) 16)))
                             (if n (loop (cons (integer->char n) chars) (fx+ len 1))
                                 (error 'jerboa-read "invalid hex escape")))))))))
               (else (loop (cons esc chars) (fx+ len 1))))))
          (else (loop (cons ch chars) (fx+ len 1)))))))

  ;;;; Number reader

  (define (read-number rs)
    (let loop ((chars '()))
      (let ((ch (reader-peek rs)))
        (cond
          ((or (eof-object? ch) (delimiter? ch))
           (let ((s (list->string (reverse chars))))
             (or (string->number s)
                 (string->symbol s))))
          (else
           (reader-next! rs)
           (loop (cons ch chars)))))))

  ;;;; Number-or-symbol

  (define (read-number-or-symbol rs loc)
    (let ((ch (reader-next! rs)))
      (let ((ch2 (reader-peek rs)))
        (cond
          ((or (eof-object? ch2) (delimiter? ch2))
           (annotate rs (string->symbol (string ch)) loc))
          ((char-numeric? ch2)
           (let loop ((chars (list ch)))
             (let ((c (reader-peek rs)))
               (cond
                 ((or (eof-object? c) (delimiter? c))
                  (let ((s (list->string (reverse chars))))
                    (annotate rs (or (string->number s) (string->symbol s)) loc)))
                 (else
                  (reader-next! rs)
                  (loop (cons c chars)))))))
          (else
           (let ((sym (read-symbol-chars rs ch)))
             (let ((s (symbol->string sym)))
               (cond
                 ((string->number s) => (lambda (n) (annotate rs n loc)))
                 (else (annotate rs sym loc))))))))))

  ;;;; Symbol/keyword reader

  (define (read-symbol-or-keyword rs loc)
    (let ((ch (reader-peek rs)))
      (cond
        ((and (char? ch) (char=? ch #\|))
         (reader-next! rs)
         (annotate rs (read-pipe-symbol rs) loc))
        (else
         (let ((sym (read-symbol-chars rs #f)))
           (let ((s (symbol->string sym)))
             (cond
               ;; keyword: syntax → keyword object
               ((and (fx> (string-length s) 1)
                     (char=? (string-ref s (fx- (string-length s) 1)) #\:))
                (let ((kw-name (substring s 0 (fx- (string-length s) 1))))
                  (annotate rs (string->keyword kw-name) loc)))
               ;; Leading-colon handling differs by mode:
               ;;   cloj mode : :name → keyword (Clojure-style)
               ;;   default   : :pkg/mod → (pkg mod) Gerbil module-path
               ((and (fx> (string-length s) 1)
                     (char=? (string-ref s 0) #\:))
                (if (reader-cloj-mode)
                    (let ((kw-name (substring s 1 (string-length s))))
                      (annotate rs (string->keyword kw-name) loc))
                    (let ((path (substring s 1 (string-length s))))
                      (annotate rs (module-path->list path) loc))))
               ;; Clojure literal booleans / nil (only in cloj mode)
               ((and (reader-cloj-mode) (eq? sym 'nil))
                (annotate rs #f loc))
               ((and (reader-cloj-mode) (eq? sym 'true))
                (annotate rs #t loc))
               ((and (reader-cloj-mode) (eq? sym 'false))
                (annotate rs #f loc))
               (else
                (annotate rs sym loc)))))))))

  ;; Convert "std/sort" → (std sort), "std/text/json" → (std text json)
  (define (module-path->list path)
    (let ((parts (string-split-simple path #\/)))
      (map string->symbol parts)))

  (define (string-split-simple str ch)
    (let ((len (string-length str)))
      (let loop ((i 0) (start 0) (acc '()))
        (cond
          ((fx= i len)
           (reverse (cons (substring str start len) acc)))
          ((char=? (string-ref str i) ch)
           (loop (fx+ i 1) (fx+ i 1) (cons (substring str start i) acc)))
          (else
           (loop (fx+ i 1) start acc))))))

  (define (read-symbol-chars rs prefix-char)
    (let loop ((chars (if prefix-char (list prefix-char) '())) (len (if prefix-char 1 0)))
      (when (> len (*max-symbol-length*))
        (error 'jerboa-read "symbol exceeds maximum length"
               len (*max-symbol-length*)))
      (let ((ch (reader-peek rs)))
        (cond
          ((or (eof-object? ch) (delimiter? ch))
           (string->symbol (list->string (reverse chars))))
          ((subsequent-ident? ch)
           (reader-next! rs)
           (loop (cons ch chars) (fx+ len 1)))
          (else
           (string->symbol (list->string (reverse chars))))))))

  (define (read-pipe-symbol rs)
    (let loop ((chars '()))
      (let ((ch (reader-next! rs)))
        (cond
          ((eof-object? ch) (error 'jerboa-read "unterminated pipe symbol"))
          ((char=? ch #\|) (string->symbol (list->string (reverse chars))))
          ((char=? ch #\\)
           (let ((esc (reader-next! rs)))
             (cond
               ((eof-object? esc) (error 'jerboa-read "unterminated pipe symbol escape"))
               (else (loop (cons esc chars))))))
          (else (loop (cons ch chars)))))))

  ;;;; Keyword support (Chez native)
  ;; Chez 10 has native keyword support via string->keyword

  (define (string->keyword s)
    ;; Use a tagged symbol: #:name
    (string->symbol (string-append "#:" s)))

  (define (keyword->string kw)
    (let ((s (symbol->string kw)))
      (if (and (fx>= (string-length s) 2)
               (char=? (string-ref s 0) #\#)
               (char=? (string-ref s 1) #\:))
        (substring s 2 (string-length s))
        s)))

  (define (keyword? v)
    (and (symbol? v)
         (let ((s (symbol->string v)))
           (and (fx>= (string-length s) 2)
                (char=? (string-ref s 0) #\#)
                (char=? (string-ref s 1) #\:)))))

  ;;;; Public API

  (define jerboa-read
    (case-lambda
      (() (jerboa-read (current-input-port)))
      ((port) (jerboa-read port #f))
      ((port path)
       (let ((rs (make-reader port path)))
         (read-datum rs)))))

  (define (jerboa-read-all port . path)
    (let ((rs (make-reader port (if (null? path) #f (car path)))))
      (let loop ((acc '()))
        (let ((datum (read-datum rs)))
          (if (eof-object? datum)
              (reverse acc)
              (loop (cons datum acc)))))))

  (define (jerboa-read-file filename)
    (call-with-input-file filename
      (lambda (port)
        (jerboa-read-all port filename))))

  (define (jerboa-read-string str . path)
    (let ((port (open-input-string str)))
      (jerboa-read-all port (if (null? path) #f (car path)))))

  ) ;; end library
