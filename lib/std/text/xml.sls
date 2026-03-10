#!chezscheme
;;; :std/text/xml -- SXML serialization to XML text

(library (std text xml)
  (export
    write-xml print-sxml->xml
    sxml-e sxml-attributes sxml-attribute-e sxml-children)

  (import (chezscheme))

  ;; --- XML escaping ---

  (define (xml-escape-string str in-attribute?)
    (let ((port (open-output-string)))
      (string-for-each
        (lambda (c)
          (cond
            ((char=? c #\<) (display "&lt;" port))
            ((char=? c #\>) (display "&gt;" port))
            ((char=? c #\&) (display "&amp;" port))
            ((and in-attribute? (char=? c #\"))
             (display "&quot;" port))
            ((and in-attribute? (char=? c #\'))
             (display "&apos;" port))
            (else (display c port))))
        str)
      (get-output-string port)))

  (define (write-escaped thing port in-attribute?)
    (cond
      ((string? thing)
       (display (xml-escape-string thing in-attribute?) port))
      ((char? thing)
       (display (xml-escape-string (string thing) in-attribute?) port))
      ((number? thing)
       (display thing port))
      ((symbol? thing)
       (display (xml-escape-string (symbol->string thing) in-attribute?) port))
      (else
       (display thing port))))

  ;; --- SXML node accessors ---

  (define (sxml-e node)
    (if (pair? node) (car node) '*TEXT*))

  (define (sxml-attributes node)
    (if (and (pair? node)
             (pair? (cdr node))
             (pair? (cadr node))
             (eq? (caadr node) '@))
      (cdadr node)
      #f))

  (define (sxml-attribute-e node key)
    (let ((attrs (sxml-attributes node)))
      (if attrs
        (let lp ((attrs attrs))
          (cond
            ((null? attrs) #f)
            ((and (pair? (car attrs))
                  (eq? (caar attrs) key))
             (if (pair? (cdar attrs))
               (cadar attrs)
               #t))
            (else (lp (cdr attrs)))))
        #f)))

  (define (sxml-children node)
    (if (pair? node)
      (let ((rest (cdr node)))
        (if (and (pair? rest)
                 (pair? (car rest))
                 (eq? (caar rest) '@))
          (cdr rest)
          rest))
      '()))

  ;; --- HTML void elements (self-closing) ---

  (define *void-tags*
    '(area base br col embed hr img input link meta param source track wbr))

  ;; --- SXML serialization ---

  (define (write-sxml-attribute attr port)
    (when (pair? attr)
      (display #\space port)
      (display (car attr) port)
      (display "=\"" port)
      (if (pair? (cdr attr))
        (write-escaped (cadr attr) port #t)
        (display (car attr) port))  ;; boolean attribute
      (display #\" port)))

  (define (write-sxml-node sxml port indent level)
    (cond
      ((string? sxml)
       (write-escaped sxml port #f))
      ((number? sxml)
       (display sxml port))
      ((and (pair? sxml) (symbol? (car sxml)))
       (let ((tag (car sxml)))
         (cond
           ;; Special tags
           ((eq? tag '*comment*)
            (display "<!-- " port)
            (for-each (lambda (c) (display c port)) (cdr sxml))
            (display " -->" port))
           ((eq? tag '*cdata*)
            (display "<![CDATA[" port)
            (for-each (lambda (c) (display c port)) (cdr sxml))
            (display "]]>" port))
           ((eq? tag '*top*)
            (for-each (lambda (c) (write-sxml-node c port indent level))
                      (cdr sxml)))
           ((eq? tag '*unencoded*)
            (for-each (lambda (c) (display c port)) (cdr sxml)))
           ((eq? tag '*PI*)
            ;; Processing instruction: (*PI* target "content")
            (display "<?" port)
            (when (pair? (cdr sxml))
              (display (cadr sxml) port)
              (when (pair? (cddr sxml))
                (display #\space port)
                (display (caddr sxml) port)))
            (display "?>" port))
           (else
            ;; Regular element
            (let ((attrs (sxml-attributes sxml))
                  (children (sxml-children sxml)))
              ;; Indentation
              (when (and indent (> level 0))
                (newline port)
                (do ((i 0 (+ i 1)))
                    ((>= i (* level indent)))
                  (display #\space port)))
              ;; Opening tag
              (display #\< port)
              (display tag port)
              ;; Attributes
              (when attrs
                (for-each (lambda (attr)
                            (write-sxml-attribute attr port))
                          attrs))
              (cond
                ;; Self-closing void tag
                ((and (null? children) (memq tag *void-tags*))
                 (display " />" port))
                ;; Empty non-void tag
                ((null? children)
                 (display " />" port))
                (else
                 (display #\> port)
                 ;; Children
                 (for-each (lambda (child)
                             (write-sxml-node child port indent (+ level 1)))
                           children)
                 ;; Closing tag
                 (when (and indent
                           (pair? children)
                           (pair? (car children)))  ;; has element children
                   (newline port)
                   (do ((i 0 (+ i 1)))
                       ((>= i (* level indent)))
                     (display #\space port)))
                 (display "</" port)
                 (display tag port)
                 (display #\> port))))))))
      ((pair? sxml)
       ;; List of nodes
       (for-each (lambda (s) (write-sxml-node s port indent level))
                 sxml))
      (else
       (write-escaped (format "~a" sxml) port #f))))

  ;; --- Public API ---

  (define write-xml
    (case-lambda
      ((sxml) (write-sxml-node sxml (current-output-port) #f 0))
      ((sxml port) (write-sxml-node sxml port #f 0))))

  (define print-sxml->xml
    (case-lambda
      ((sxml) (write-sxml-node sxml (current-output-port) 1 0))
      ((sxml port) (write-sxml-node sxml port 1 0))))

  ) ;; end library
