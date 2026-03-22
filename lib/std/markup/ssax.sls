#!chezscheme
;;; :std/markup/ssax -- SAX-style XML parser producing SXML
;;; Handles elements, attributes, text, CDATA, PIs, comments, entities,
;;; numeric char refs, self-closing tags, and basic namespaces.
;;; Main entry: (ssax:xml->sxml port-or-string) -> SXML

(library (std markup ssax)
  (export ssax:xml->sxml ssax:make-parser
          ssax:make-pi-parser ssax:make-elem-parser)
  (import (chezscheme))

  ;; --- Parser state with line/col tracking ---
  (define-record-type parse-state
    (fields (mutable port) (mutable line) (mutable col) (mutable prev-col)))

  (define (make-pstate port) (make-parse-state port 1 1 1))

  (define (parse-error ps msg . args)
    (error 'ssax:xml->sxml
           (format "~a at line ~a, column ~a~a" msg
                   (parse-state-line ps) (parse-state-col ps)
                   (if (null? args) "" (format " (~a)" (car args))))))

  (define (peek ps) (lookahead-char (parse-state-port ps)))

  (define (advance! ps)
    (let ((c (read-char (parse-state-port ps))))
      (when (char? c)
        (parse-state-prev-col-set! ps (parse-state-col ps))
        (if (char=? c #\newline)
          (begin (parse-state-line-set! ps (+ 1 (parse-state-line ps)))
                 (parse-state-col-set! ps 1))
          (parse-state-col-set! ps (+ 1 (parse-state-col ps)))))
      c))

  (define (expect-char! ps expected)
    (let ((c (advance! ps)))
      (unless (and (char? c) (char=? c expected))
        (parse-error ps (format "expected '~a' but got ~a" expected
                                (if (eof-object? c) "EOF" (format "'~a'" c)))))
      c))

  (define (expect-string! ps str)
    (string-for-each (lambda (ch) (expect-char! ps ch)) str))

  ;; --- Character predicates ---
  (define (name-start-char? c)
    (and (char? c) (or (char-alphabetic? c) (char=? c #\_) (char=? c #\:))))
  (define (name-char? c)
    (and (char? c) (or (char-alphabetic? c) (char-numeric? c)
                       (char=? c #\_) (char=? c #\:)
                       (char=? c #\-) (char=? c #\.))))
  (define (whitespace? c)
    (and (char? c) (or (char=? c #\space) (char=? c #\tab)
                       (char=? c #\newline) (char=? c #\return))))

  ;; --- Low-level readers ---
  (define (skip-whitespace! ps)
    (let loop () (when (whitespace? (peek ps)) (advance! ps) (loop))))

  (define (read-name ps)
    (let ((c (peek ps)))
      (unless (name-start-char? c)
        (parse-error ps "expected name start character"
                     (if (eof-object? c) "EOF" (format "'~a'" c))))
      (let ((out (open-output-string)))
        (let loop () (when (name-char? (peek ps))
                       (write-char (advance! ps) out) (loop)))
        (get-output-string out))))

  ;; --- Entity/reference resolution ---
  (define (resolve-entity name)
    (cond ((string=? name "amp") #\&) ((string=? name "lt") #\<)
          ((string=? name "gt") #\>) ((string=? name "quot") #\")
          ((string=? name "apos") #\') (else #f)))

  (define (read-char-ref ps)
    ;; After "&#"; read decimal or &#xHH; hex reference
    (let ((c (peek ps)))
      (if (and (char? c) (char=? c #\x))
        (begin (advance! ps)
          (let ((out (open-output-string)))
            (let loop ()
              (let ((c (peek ps)))
                (when (and (char? c) (or (char-numeric? c)
                           (memv (char-downcase c) '(#\a #\b #\c #\d #\e #\f))))
                  (write-char (advance! ps) out) (loop))))
            (let ((s (get-output-string out)))
              (when (string=? s "") (parse-error ps "empty hex char reference"))
              (expect-char! ps #\;)
              (integer->char (string->number s 16)))))
        (let ((out (open-output-string)))
          (let loop ()
            (let ((c (peek ps)))
              (when (and (char? c) (char-numeric? c))
                (write-char (advance! ps) out) (loop))))
          (let ((s (get-output-string out)))
            (when (string=? s "") (parse-error ps "empty decimal char reference"))
            (expect-char! ps #\;)
            (integer->char (string->number s 10)))))))

  (define (read-reference ps out)
    ;; After '&': entity name or char ref
    (let ((c (peek ps)))
      (if (and (char? c) (char=? c #\#))
        (begin (advance! ps) (write-char (read-char-ref ps) out))
        (let ((name (read-name ps)))
          (expect-char! ps #\;)
          (let ((ch (resolve-entity name)))
            (if ch (write-char ch out)
                (parse-error ps (format "unknown entity '&~a;'" name))))))))

  ;; --- Attribute parsing ---
  (define (read-attr-value ps)
    (let ((q (advance! ps)))
      (unless (or (char=? q #\") (char=? q #\'))
        (parse-error ps "expected quote for attribute value"))
      (let ((out (open-output-string)))
        (let loop ()
          (let ((c (peek ps)))
            (cond ((eof-object? c) (parse-error ps "unexpected EOF in attr value"))
                  ((char=? c q) (advance! ps) (get-output-string out))
                  ((char=? c #\&) (advance! ps) (read-reference ps out) (loop))
                  (else (write-char (advance! ps) out) (loop))))))))

  (define (read-attributes ps)
    (let loop ((attrs '()))
      (skip-whitespace! ps)
      (let ((c (peek ps)))
        (cond ((or (eof-object? c) (char=? c #\>) (char=? c #\/) (char=? c #\?))
               (reverse attrs))
              (else (let ((name (read-name ps)))
                      (skip-whitespace! ps) (expect-char! ps #\=) (skip-whitespace! ps)
                      (loop (cons (list (string->symbol name) (read-attr-value ps))
                                  attrs))))))))

  ;; --- Comment: after "<!--", read until "-->" ---
  (define (read-comment ps)
    (let ((out (open-output-string)))
      (let loop ()
        (let ((c (advance! ps)))
          (cond ((eof-object? c) (parse-error ps "unexpected EOF in comment"))
                ((char=? c #\-)
                 (if (and (char? (peek ps)) (char=? (peek ps) #\-))
                   (begin (advance! ps) (expect-char! ps #\>) (get-output-string out))
                   (begin (write-char c out) (loop))))
                (else (write-char c out) (loop)))))))

  ;; --- CDATA: after "<![CDATA[", read until "]]>" ---
  (define (read-cdata ps)
    (let ((out (open-output-string)))
      (let loop ()
        (let ((c (advance! ps)))
          (cond ((eof-object? c) (parse-error ps "unexpected EOF in CDATA"))
                ((char=? c #\])
                 (if (and (char? (peek ps)) (char=? (peek ps) #\]))
                   (begin (advance! ps)
                     (if (and (char? (peek ps)) (char=? (peek ps) #\>))
                       (begin (advance! ps) (get-output-string out))
                       (begin (write-char #\] out) (write-char #\] out) (loop))))
                   (begin (write-char c out) (loop))))
                (else (write-char c out) (loop)))))))

  ;; --- Processing instruction: after "<?", read target + content until "?>" ---
  (define (read-pi ps)
    (let ((target (read-name ps)))
      (skip-whitespace! ps)
      (let ((out (open-output-string)))
        (let loop ()
          (let ((c (advance! ps)))
            (cond ((eof-object? c) (parse-error ps "unexpected EOF in PI"))
                  ((char=? c #\?)
                   (if (and (char? (peek ps)) (char=? (peek ps) #\>))
                     (begin (advance! ps)
                       (let ((s (get-output-string out)))
                         (if (string=? s "") (list '*PI* target) (list '*PI* target s))))
                     (begin (write-char c out) (loop))))
                  (else (write-char c out) (loop))))))))

  (define (xml-declaration? pi)
    (and (pair? pi) (eq? (car pi) '*PI*) (pair? (cdr pi))
         (string-ci=? (cadr pi) "xml")))

  ;; --- Text: read until '<' or EOF, resolving entities ---
  (define (read-text ps)
    (let ((out (open-output-string)))
      (let loop ()
        (let ((c (peek ps)))
          (cond ((or (eof-object? c) (char=? c #\<)) (get-output-string out))
                ((char=? c #\&) (advance! ps) (read-reference ps out) (loop))
                (else (write-char (advance! ps) out) (loop)))))))

  ;; --- Element parsing ---
  (define (read-element ps)
    (let* ((tag-name (read-name ps)) (attrs (read-attributes ps)))
      (skip-whitespace! ps)
      (let ((c (peek ps)))
        (cond ((and (char? c) (char=? c #\/))       ; self-closing
               (advance! ps) (expect-char! ps #\>)
               (let ((t (string->symbol tag-name)))
                 (if (null? attrs) (list t) (list t (cons '@ attrs)))))
              ((and (char? c) (char=? c #\>))        ; opening tag
               (advance! ps)
               (let* ((t (string->symbol tag-name)) (ch (read-children ps tag-name)))
                 (if (null? attrs) (cons t ch) (cons t (cons (cons '@ attrs) ch)))))
              (else (parse-error ps (format "unexpected char in element '~a'" tag-name)))))))

  (define (read-children ps parent)
    (let loop ((children '()))
      (let ((c (peek ps)))
        (cond
          ((eof-object? c)
           (parse-error ps (format "unexpected EOF, expected </~a>" parent)))
          ((char=? c #\<)
           (advance! ps)
           (let ((c2 (peek ps)))
             (cond
               ((and (char? c2) (char=? c2 #\/))    ; closing tag
                (advance! ps)
                (let ((name (read-name ps)))
                  (skip-whitespace! ps) (expect-char! ps #\>)
                  (unless (string=? name parent)
                    (parse-error ps (format "mismatched tag: expected </~a> got </~a>"
                                           parent name)))
                  (reverse children)))
               ((and (char? c2) (char=? c2 #\!))    ; comment or CDATA
                (advance! ps)
                (let ((c3 (peek ps)))
                  (cond ((and (char? c3) (char=? c3 #\-))
                         (advance! ps) (expect-char! ps #\-)
                         (loop (cons (list '*comment* (read-comment ps)) children)))
                        ((and (char? c3) (char=? c3 #\[))
                         (expect-string! ps "[CDATA[")
                         (loop (cons (read-cdata ps) children)))
                        (else (parse-error ps "unexpected <! sequence")))))
               ((and (char? c2) (char=? c2 #\?))    ; PI
                (advance! ps) (loop (cons (read-pi ps) children)))
               ((name-start-char? c2)                ; child element
                (loop (cons (read-element ps) children)))
               (else (parse-error ps "unexpected character after '<'")))))
          (else
           (let ((text (read-text ps)))
             (if (string=? text "") (loop children)
                 (loop (cons text children)))))))))

  ;; --- Document-level parsing ---
  (define (read-document ps)
    (let loop ((nodes '()))
      (skip-whitespace! ps)
      (let ((c (peek ps)))
        (cond
          ((eof-object? c)
           (cons '*TOP* (filter (lambda (n) (not (and (pair? n) (xml-declaration? n))))
                                (reverse nodes))))
          ((char=? c #\<)
           (advance! ps)
           (let ((c2 (peek ps)))
             (cond ((and (char? c2) (char=? c2 #\?))
                    (advance! ps) (loop (cons (read-pi ps) nodes)))
                   ((and (char? c2) (char=? c2 #\!))
                    (advance! ps)
                    (let ((c3 (peek ps)))
                      (cond ((and (char? c3) (char=? c3 #\-))
                             (advance! ps) (expect-char! ps #\-)
                             (loop (cons (list '*comment* (read-comment ps)) nodes)))
                            ((and (char? c3) (char=? c3 #\D))
                             (read-doctype ps) (loop nodes))
                            (else (parse-error ps "unexpected <! at document level")))))
                   ((name-start-char? c2) (loop (cons (read-element ps) nodes)))
                   (else (parse-error ps "unexpected char at document level")))))
          (else (read-text ps) (loop nodes))))))

  ;; Skip DOCTYPE declaration, handling nested [] for internal subset.
  (define (read-doctype ps)
    (let loop ((depth 0))
      (let ((c (advance! ps)))
        (cond ((eof-object? c) (parse-error ps "unexpected EOF in DOCTYPE"))
              ((char=? c #\[) (loop (+ depth 1)))
              ((char=? c #\]) (loop (- depth 1)))
              ((and (char=? c #\>) (= depth 0)) (void))
              (else (loop depth))))))

  ;; --- Public API ---
  (define (ssax:xml->sxml input)
    (let ((port (if (string? input) (open-input-string input) input)))
      (read-document (make-pstate port))))

  ;; Customizable parser with callbacks (plist of event-name handler-proc):
  ;;   'new-level-seed  : (tag attrs ns expected-content seed) -> seed
  ;;   'finish-element  : (tag attrs ns parent-seed seed) -> seed
  ;;   'char-data-handler : (string1 string2 seed) -> seed
  ;;   'pi : (port pi-tag seed) -> seed
  (define (ssax:make-parser . handlers)
    (let ((alist (plist->alist handlers)))
      (lambda (port seed)
        (parse-with-handlers (make-pstate port) alist seed))))

  (define (ssax:make-pi-parser handler)
    (lambda (port pi-tag seed) (handler pi-tag seed)))

  (define (ssax:make-elem-parser handler)
    (lambda (tag attrs ns ec seed) (handler tag attrs seed)))

  ;; --- Handler-based parsing internals ---
  (define (plist->alist pl)
    (let loop ((pl pl) (acc '()))
      (if (or (null? pl) (null? (cdr pl))) (reverse acc)
          (loop (cddr pl) (cons (cons (car pl) (cadr pl)) acc)))))

  (define (get-handler alist key default)
    (let ((p (assq key alist))) (if p (cdr p) default)))

  (define (parse-with-handlers ps handlers seed)
    (let ((nl (get-handler handlers 'new-level-seed (lambda (t a ns ec s) '())))
          (fin (get-handler handlers 'finish-element (lambda (t a ns ps s) ps)))
          (cd (get-handler handlers 'char-data-handler (lambda (s1 s2 s) s)))
          (pi (get-handler handlers 'pi (lambda (p t s) s))))
      (walk-sxml (read-document ps) seed nl fin cd pi)))

  (define (walk-sxml node seed nl fin cd pi)
    (cond
      ((string? node) (cd node "" seed))
      ((and (pair? node) (eq? (car node) '*TOP*))
       (let loop ((ch (cdr node)) (s seed))
         (if (null? ch) s (loop (cdr ch) (walk-sxml (car ch) s nl fin cd pi)))))
      ((and (pair? node) (eq? (car node) '*PI*))
       (if (pair? (cdr node)) (pi #f (cadr node) seed) seed))
      ((and (pair? node) (eq? (car node) '*comment*)) seed)
      ((and (pair? node) (symbol? (car node)))
       (let* ((tag (car node))
              (has-@ (and (pair? (cdr node)) (pair? (cadr node))
                          (eq? (caadr node) '@)))
              (attrs (if has-@ (cdadr node) '()))
              (children (if has-@ (cddr node) (cdr node)))
              (cs (nl tag attrs '() 'any seed)))
         (fin tag attrs '() seed
              (let loop ((ch children) (s cs))
                (if (null? ch) s
                    (loop (cdr ch) (walk-sxml (car ch) s nl fin cd pi)))))))
      (else seed)))

  ) ;; end library
