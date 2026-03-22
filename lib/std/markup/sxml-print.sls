#!chezscheme
;;; :std/markup/sxml-print -- SXML serialization to HTML, XML, and plain text
;;;
;;; Properly escapes text content and attribute values.
;;; HTML mode: void elements (br, hr, img, etc.) have no closing tag.
;;; XML mode: empty elements self-close, all others get closing tags.

(library (std markup sxml-print)
  (export
    sxml->html
    sxml->xml
    sxml->string)

  (import (chezscheme))

  ;; --- Escaping ---

  (define (escape-text str)
    (let ((port (open-output-string)))
      (string-for-each
        (lambda (c)
          (cond
            ((char=? c #\<) (display "&lt;" port))
            ((char=? c #\>) (display "&gt;" port))
            ((char=? c #\&) (display "&amp;" port))
            (else (display c port))))
        str)
      (get-output-string port)))

  (define (escape-attr str)
    (let ((port (open-output-string)))
      (string-for-each
        (lambda (c)
          (cond
            ((char=? c #\<) (display "&lt;" port))
            ((char=? c #\>) (display "&gt;" port))
            ((char=? c #\&) (display "&amp;" port))
            ((char=? c #\") (display "&quot;" port))
            (else (display c port))))
        str)
      (get-output-string port)))

  (define (value->string v)
    (cond
      ((string? v) v)
      ((symbol? v) (symbol->string v))
      ((number? v) (number->string v))
      ((boolean? v) (if v "true" "false"))
      (else (format "~a" v))))

  ;; --- SXML accessors (local, minimal) ---

  (define (element? x)
    (and (pair? x) (symbol? (car x))))

  (define (element-name elem)
    (car elem))

  (define (element-attrs elem)
    (if (and (pair? (cdr elem))
             (pair? (cadr elem))
             (eq? (caadr elem) '@))
      (cdadr elem)
      '()))

  (define (element-children elem)
    (let ((rest (cdr elem)))
      (if (and (pair? rest)
               (pair? (car rest))
               (eq? (caar rest) '@))
        (cdr rest)
        rest)))

  ;; --- HTML void elements ---

  (define *html-void-elements*
    '(area base br col embed hr img input link meta param source track wbr))

  ;; --- Attribute serialization ---

  (define (write-attrs attrs port)
    (for-each
      (lambda (attr)
        (when (pair? attr)
          (display #\space port)
          (display (car attr) port)
          (when (pair? (cdr attr))
            (display "=\"" port)
            (display (escape-attr (value->string (cadr attr))) port)
            (display #\" port))))
      attrs))

  ;; --- HTML serialization ---

  (define (write-html node port)
    (cond
      ((string? node)
       (display (escape-text node) port))
      ((number? node)
       (display node port))
      ((element? node)
       (let ((tag (element-name node))
             (attrs (element-attrs node))
             (children (element-children node)))
         (cond
           ;; Special SXML nodes
           ((eq? tag '*top*)
            (for-each (lambda (c) (write-html c port)) children))
           ((eq? tag '*comment*)
            (display "<!--" port)
            (for-each (lambda (c) (display c port)) children)
            (display "-->" port))
           ((eq? tag '*PI*)
            (display "<?" port)
            (when (pair? children)
              (display (car children) port)
              (when (pair? (cdr children))
                (display #\space port)
                (display (cadr children) port)))
            (display "?>" port))
           ;; HTML void element
           ((memq tag *html-void-elements*)
            (display #\< port)
            (display tag port)
            (write-attrs attrs port)
            (display ">" port))
           ;; Regular element
           (else
            (display #\< port)
            (display tag port)
            (write-attrs attrs port)
            (display #\> port)
            (for-each (lambda (c) (write-html c port)) children)
            (display "</" port)
            (display tag port)
            (display #\> port)))))
      ((pair? node)
       ;; List of nodes (fragment)
       (for-each (lambda (c) (write-html c port)) node))
      (else
       (display (escape-text (value->string node)) port))))

  ;; --- XML serialization ---

  (define (write-xml-node node port)
    (cond
      ((string? node)
       (display (escape-text node) port))
      ((number? node)
       (display node port))
      ((element? node)
       (let ((tag (element-name node))
             (attrs (element-attrs node))
             (children (element-children node)))
         (cond
           ((eq? tag '*top*)
            (for-each (lambda (c) (write-xml-node c port)) children))
           ((eq? tag '*comment*)
            (display "<!--" port)
            (for-each (lambda (c) (display c port)) children)
            (display "-->" port))
           ((eq? tag '*PI*)
            (display "<?" port)
            (when (pair? children)
              (display (car children) port)
              (when (pair? (cdr children))
                (display #\space port)
                (display (cadr children) port)))
            (display "?>" port))
           ;; Empty element: self-closing
           ((null? children)
            (display #\< port)
            (display tag port)
            (write-attrs attrs port)
            (display "/>" port))
           ;; Element with children: opening + closing tags
           (else
            (display #\< port)
            (display tag port)
            (write-attrs attrs port)
            (display #\> port)
            (for-each (lambda (c) (write-xml-node c port)) children)
            (display "</" port)
            (display tag port)
            (display #\> port)))))
      ((pair? node)
       (for-each (lambda (c) (write-xml-node c port)) node))
      (else
       (display (escape-text (value->string node)) port))))

  ;; --- Plain text extraction ---

  (define (extract-text node)
    (cond
      ((string? node) node)
      ((number? node) (number->string node))
      ((element? node)
       (apply string-append
              (map extract-text (element-children node))))
      ((pair? node)
       (apply string-append (map extract-text node)))
      (else "")))

  ;; --- Public API ---

  ;; Serialize SXML to an HTML string.
  ;; Void elements (br, hr, img, etc.) do not get closing tags.
  (define (sxml->html sxml)
    (let ((port (open-output-string)))
      (write-html sxml port)
      (get-output-string port)))

  ;; Serialize SXML to an XML string.
  ;; Empty elements self-close; all others get proper closing tags.
  (define (sxml->xml sxml)
    (let ((port (open-output-string)))
      (write-xml-node sxml port)
      (get-output-string port)))

  ;; Extract just the text content from SXML (no markup).
  (define (sxml->string sxml)
    (extract-text sxml))

  ) ;; end library
