#!chezscheme
;;; :std/markup/html-parser -- Lenient HTML parser producing SXML
;;;
;;; Unlike strict XML/SSAX parsers, this handles real-world HTML:
;;;   - Auto-closes void elements (br, hr, img, input, meta, link, ...)
;;;   - Handles unquoted attribute values
;;;   - Handles missing closing tags
;;;   - Case-insensitive tag names (normalized to lowercase symbols)
;;;   - Handles <!DOCTYPE> declarations
;;;   - Handles HTML entities (&amp; &lt; &gt; &quot; &nbsp; etc.)
;;;   - Handles <script> and <style> as raw text elements
;;;
;;; Output format: (*TOP* (html (head ...) (body ...)))

(library (std markup html-parser)
  (export html->sxml html-parse-string html-parse-port)

  (import (chezscheme))

  ;; ---------- Entity table ----------

  (define *entities*
    '(("amp" . "&") ("lt" . "<") ("gt" . ">") ("quot" . "\"")
      ("apos" . "'") ("nbsp" . "\x00A0;") ("copy" . "\x00A9;")
      ("reg" . "\x00AE;") ("trade" . "\x2122;") ("mdash" . "\x2014;")
      ("ndash" . "\x2013;") ("laquo" . "\x00AB;") ("raquo" . "\x00BB;")
      ("hellip" . "\x2026;") ("bull" . "\x2022;") ("middot" . "\x00B7;")
      ("ldquo" . "\x201C;") ("rdquo" . "\x201D;") ("lsquo" . "\x2018;")
      ("rsquo" . "\x2019;") ("ensp" . "\x2002;") ("emsp" . "\x2003;")
      ("thinsp" . "\x2009;") ("zwnj" . "\x200C;") ("zwj" . "\x200D;")))

  (define (resolve-entity name)
    (cond
      [(assoc name *entities*) => cdr]
      [(and (> (string-length name) 1)
            (char=? (string-ref name 0) #\#))
       (let ([code (if (and (> (string-length name) 2)
                            (char-ci=? (string-ref name 1) #\x))
                     (string->number (substring name 2 (string-length name)) 16)
                     (string->number (substring name 1 (string-length name))))])
         (if (and code (> code 0) (<= code #x10FFFF))
           (string (integer->char code))
           ""))]
      [else (string-append "&" name ";")]))

  ;; ---------- Void / raw-text elements ----------

  (define *void-elements*
    '(area base br col embed hr img input link meta param source track wbr))

  (define (void-element? tag)
    (memq tag *void-elements*))

  (define *raw-text-elements* '(script style))

  (define (raw-text-element? tag)
    (memq tag *raw-text-elements*))

  ;; ---------- Auto-close rules ----------
  ;; When opening <tag>, auto-close <parent> if parent is in the list.

  (define *auto-close-rules*
    '((p        . (p))
      (li       . (li))
      (dt       . (dt dd))
      (dd       . (dt dd))
      (tr       . (tr))
      (td       . (td th))
      (th       . (td th))
      (thead    . (tbody tfoot))
      (tbody    . (tbody tfoot))
      (tfoot    . (tbody))
      (option   . (option))
      (optgroup . (optgroup))))

  (define (should-auto-close? new-tag current-tag)
    (cond
      [(assq new-tag *auto-close-rules*)
       => (lambda (rule) (memq current-tag (cdr rule)))]
      [else #f]))

  ;; ---------- Parser state ----------
  ;; The parser uses a stack of (tag . children) frames.
  ;; children is a reversed list of child nodes (strings and elements).

  (define (make-frame tag) (cons tag '()))
  (define (frame-tag f) (car f))
  (define (frame-children f) (cdr f))
  (define (frame-add-child! f child)
    (set-cdr! f (cons child (cdr f))))

  (define (close-frame frame)
    ;; Build an SXML element from a frame.
    (let ([tag (frame-tag frame)]
          [children (reverse (frame-children frame))])
      (cons tag children)))

  ;; ---------- Main parser ----------

  (define (html-parse-port port)
    (let ([stack (list (make-frame '*TOP*))]
          [buf (open-output-string)])

      (define (peek) (lookahead-char port))
      (define (next) (read-char port))
      (define (eof?) (eof-object? (peek)))

      ;; Flush text buffer into current frame
      (define (flush-text!)
        (let ([text (get-output-string buf)])
          (set! buf (open-output-string))
          (when (> (string-length text) 0)
            (frame-add-child! (car stack) text))))

      ;; Push a new open element onto the stack
      (define (push-element! tag attrs)
        ;; Auto-close if needed
        (when (and (pair? stack) (pair? (cdr stack)))
          (let ([current-tag (frame-tag (car stack))])
            (when (should-auto-close? tag current-tag)
              (pop-element! current-tag))))
        (let ([frame (make-frame tag)])
          ;; Attach attributes if any
          (when (pair? attrs)
            (frame-add-child! frame (cons '@ (reverse attrs))))
          (if (void-element? tag)
            ;; Void element: close immediately, add to parent
            (frame-add-child! (car stack) (close-frame frame))
            ;; Normal element: push onto stack
            (set! stack (cons frame stack)))))

      ;; Pop element, matching tag name. If tag doesn't match,
      ;; search the stack and close intervening elements.
      (define (pop-element! tag)
        (cond
          ;; If we're at the root, ignore
          [(null? (cdr stack)) (void)]
          ;; Current frame matches
          [(eq? (frame-tag (car stack)) tag)
           (let ([elem (close-frame (car stack))])
             (set! stack (cdr stack))
             (frame-add-child! (car stack) elem))]
          ;; Search up the stack for a match
          [else
           (let loop ([depth 1] [s (cdr stack)])
             (cond
               [(null? s) (void)]  ;; No match found, ignore close tag
               [(eq? (frame-tag (car s)) tag)
                ;; Close everything up to and including the match
                (do ([i 0 (+ i 1)])
                    ((> i depth))
                  (when (pair? (cdr stack))
                    (let ([elem (close-frame (car stack))])
                      (set! stack (cdr stack))
                      (frame-add-child! (car stack) elem))))]
               [else (loop (+ depth 1) (cdr s))]))]))

      ;; Read a tag name (letters, digits, hyphens)
      (define (read-tag-name)
        (let ([out (open-output-string)])
          (let loop ()
            (let ([c (peek)])
              (cond
                [(eof-object? c) (get-output-string out)]
                [(or (char-alphabetic? c) (char-numeric? c)
                     (char=? c #\-) (char=? c #\_) (char=? c #\.))
                 (put-char out (char-downcase (next)))
                 (loop)]
                [else (get-output-string out)])))))

      ;; Read attribute name
      (define (read-attr-name)
        (let ([out (open-output-string)])
          (let loop ()
            (let ([c (peek)])
              (cond
                [(eof-object? c) (get-output-string out)]
                [(or (char-alphabetic? c) (char-numeric? c)
                     (char=? c #\-) (char=? c #\_) (char=? c #\.)
                     (char=? c #\:))
                 (put-char out (char-downcase (next)))
                 (loop)]
                [else (get-output-string out)])))))

      ;; Skip whitespace
      (define (skip-ws)
        (let loop ()
          (when (and (not (eof?)) (char-whitespace? (peek)))
            (next)
            (loop))))

      ;; Read attribute value (quoted or unquoted)
      (define (read-attr-value)
        (skip-ws)
        (cond
          [(eof?) ""]
          [(char=? (peek) #\")
           (next) ;; consume opening quote
           (read-until-char #\")]
          [(char=? (peek) #\')
           (next)
           (read-until-char #\')]
          [else
           ;; Unquoted value: read until whitespace or > or /
           (let ([out (open-output-string)])
             (let loop ()
               (let ([c (peek)])
                 (cond
                   [(eof-object? c) (get-output-string out)]
                   [(or (char-whitespace? c) (char=? c #\>) (char=? c #\/))
                    (get-output-string out)]
                   [else (put-char out (next)) (loop)]))))]))

      (define (read-until-char delim)
        (let ([out (open-output-string)])
          (let loop ()
            (cond
              [(eof?) (get-output-string out)]
              [(char=? (peek) delim)
               (next) ;; consume closing delimiter
               (get-output-string out)]
              [(char=? (peek) #\&)
               (put-string out (read-entity))
               (loop)]
              [else (put-char out (next)) (loop)]))))

      ;; Read attributes: returns list of (name value) pairs
      (define (read-attributes)
        (let loop ([attrs '()])
          (skip-ws)
          (cond
            [(eof?) attrs]
            [(or (char=? (peek) #\>) (char=? (peek) #\/))
             attrs]
            [else
             (let ([name (read-attr-name)])
               (if (string=? name "")
                 (begin (next) (loop attrs))  ;; skip unexpected char
                 (begin
                   (skip-ws)
                   (if (and (not (eof?)) (char=? (peek) #\=))
                     (begin
                       (next) ;; consume =
                       (skip-ws)
                       (let ([val (read-attr-value)])
                         (loop (cons (list (string->symbol name) val) attrs))))
                     ;; Boolean attribute (no value)
                     (loop (cons (list (string->symbol name) name) attrs))))))])))

      ;; Read an HTML entity: &name; or &#num; or &#xhex;
      (define (read-entity)
        (next) ;; consume &
        (let ([out (open-output-string)])
          (let loop ([count 0])
            (cond
              [(eof?) (string-append "&" (get-output-string out))]
              [(char=? (peek) #\;)
               (next)
               (resolve-entity (get-output-string out))]
              [(> count 10)
               ;; Too long, not a real entity
               (string-append "&" (get-output-string out))]
              [(or (char-alphabetic? (peek)) (char-numeric? (peek))
                   (char=? (peek) #\#))
               (put-char out (next))
               (loop (+ count 1))]
              [else
               ;; Not terminated by ;, output as-is
               (string-append "&" (get-output-string out))]))))

      ;; Read raw text content for <script> or <style>
      (define (read-raw-text tag-name)
        (let ([close-tag (string-append "</" tag-name ">")]
              [out (open-output-string)]
              [close-len (+ 3 (string-length tag-name))])
          (let loop ()
            (cond
              [(eof?)
               (get-output-string out)]
              [(char=? (peek) #\<)
               ;; Check if this is the closing tag
               (let ([saved (get-output-string out)])
                 (set! out (open-output-string))
                 (put-string out saved)
                 ;; Try to match closing tag
                 (let ([attempt (open-output-string)])
                   (put-char attempt (next)) ;; <
                   (let match-loop ([i 1])
                     (cond
                       [(= i close-len)
                        ;; Check if followed by > or whitespace or eof
                        (get-output-string out)] ;; matched!
                       [(eof?)
                        (put-string out (get-output-string attempt))
                        (get-output-string out)]
                       [else
                        (let ([c (next)])
                          (put-char attempt c)
                          (if (char-ci=? c (string-ref close-tag i))
                            (match-loop (+ i 1))
                            (begin
                              (put-string out (get-output-string attempt))
                              (loop))))]))))]
              [else
               (put-char out (next))
               (loop)]))))

      ;; Read a comment <!-- ... -->
      (define (read-comment)
        ;; We've consumed <!--, now read until -->
        (let loop ([dashes 0])
          (cond
            [(eof?) (void)]
            [(and (>= dashes 2) (char=? (peek) #\>))
             (next) ;; consume >
             (void)]
            [(char=? (peek) #\-)
             (next)
             (loop (+ dashes 1))]
            [else
             (next)
             (loop 0)])))

      ;; Read DOCTYPE declaration
      (define (read-doctype)
        ;; Consume until >
        (let loop ()
          (cond
            [(eof?) (void)]
            [(char=? (peek) #\>)
             (next)
             (void)]
            [else (next) (loop)])))

      ;; Main parse loop
      (define (parse-loop)
        (cond
          [(eof?)
           ;; Flush any remaining text
           (flush-text!)
           ;; Close any remaining open elements
           (let loop ()
             (when (pair? (cdr stack))
               (let ([elem (close-frame (car stack))])
                 (set! stack (cdr stack))
                 (frame-add-child! (car stack) elem))
               (loop)))
           ;; Return the root
           (close-frame (car stack))]
          [(char=? (peek) #\<)
           (flush-text!)
           (next) ;; consume <
           (cond
             [(eof?) (put-char buf #\<) (parse-loop)]
             ;; Comment: <!-- -->
             [(char=? (peek) #\!)
              (next) ;; consume !
              (cond
                [(and (not (eof?)) (char=? (peek) #\-))
                 (next) ;; first -
                 (when (and (not (eof?)) (char=? (peek) #\-))
                   (next)) ;; second -
                 (read-comment)]
                [else
                 ;; DOCTYPE or other declaration
                 (read-doctype)])
              (parse-loop)]
             ;; End tag: </tag>
             [(char=? (peek) #\/)
              (next) ;; consume /
              (let ([name (read-tag-name)])
                ;; Consume until >
                (let eat ()
                  (cond
                    [(eof?) (void)]
                    [(char=? (peek) #\>) (next)]
                    [else (next) (eat)]))
                (unless (string=? name "")
                  (pop-element! (string->symbol name))))
              (parse-loop)]
             ;; Processing instruction or other <? ... >
             [(char=? (peek) #\?)
              (let eat ()
                (cond
                  [(eof?) (void)]
                  [(char=? (peek) #\>) (next)]
                  [else (next) (eat)]))
              (parse-loop)]
             ;; Open tag
             [(char-alphabetic? (peek))
              (let* ([name (read-tag-name)]
                     [attrs (read-attributes)])
                ;; Check for self-closing />
                (skip-ws)
                (let ([self-close? (and (not (eof?)) (char=? (peek) #\/))])
                  (when self-close? (next))
                  ;; Consume >
                  (when (and (not (eof?)) (char=? (peek) #\>))
                    (next))
                  (let ([tag (string->symbol name)])
                    (push-element! tag attrs)
                    ;; Handle raw text elements
                    (when (and (raw-text-element? tag) (not self-close?))
                      (let ([raw (read-raw-text name)])
                        (when (> (string-length raw) 0)
                          (frame-add-child! (car stack) raw))
                        (pop-element! tag))))))
              (parse-loop)]
             ;; Invalid tag start, treat < as text
             [else
              (put-char buf #\<)
              (parse-loop)])]
          ;; Entity
          [(char=? (peek) #\&)
           (flush-text!)
           (let ([entity (read-entity)])
             (frame-add-child! (car stack) entity))
           (parse-loop)]
          ;; Normal text character
          [else
           (put-char buf (next))
           (parse-loop)]))

      (parse-loop)))

  (define (html-parse-string str)
    (html-parse-port (open-input-string str)))

  (define (html->sxml input)
    (cond
      [(string? input) (html-parse-string input)]
      [(input-port? input) (html-parse-port input)]
      [else (error 'html->sxml "expected string or input port" input)]))

  ) ;; end library
