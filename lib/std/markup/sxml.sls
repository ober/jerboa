#!chezscheme
;;; :std/markup/sxml -- SXML representation and manipulation
;;;
;;; SXML represents XML as S-expressions:
;;;   (tag (@ (attr val) ...) child ...)
;;; Text content is plain strings.  Elements are lists starting with a symbol.

(library (std markup sxml)
  (export
    sxml:element?
    sxml:element-name
    sxml:attributes
    sxml:children
    sxml:text?
    sxml:attr
    sxml:set-attr
    sxml:add-child
    sxml:remove-attr
    sxml:content
    make-element)

  (import (chezscheme))

  ;; An SXML element is a list whose car is a symbol (the tag name).
  (define (sxml:element? x)
    (and (pair? x) (symbol? (car x))))

  ;; Return the tag name symbol of an element.
  (define (sxml:element-name elem)
    (car elem))

  ;; Return the attribute alist from the (@ ...) block, or '() if none.
  ;; Each attribute is (name value).
  (define (sxml:attributes elem)
    (if (and (pair? (cdr elem))
             (pair? (cadr elem))
             (eq? (caadr elem) '@))
      (cdadr elem)
      '()))

  ;; Return children: everything after the tag and optional (@ ...) block.
  ;; Children are element nodes and text strings.
  (define (sxml:children elem)
    (let ((rest (cdr elem)))
      (if (and (pair? rest)
               (pair? (car rest))
               (eq? (caar rest) '@))
        (cdr rest)
        rest)))

  ;; A text node is simply a string.
  (define (sxml:text? x)
    (string? x))

  ;; Look up an attribute value by name (a symbol).
  ;; Returns the value string, or #f if not found.
  (define (sxml:attr elem name)
    (let loop ((attrs (sxml:attributes elem)))
      (cond
        ((null? attrs) #f)
        ((and (pair? (car attrs))
              (eq? (caar attrs) name))
         (if (pair? (cdar attrs))
           (cadar attrs)
           #t))  ;; boolean attribute (no value)
        (else (loop (cdr attrs))))))

  ;; Set or add an attribute.  Returns a new element with the attribute
  ;; set to the given value.  If the attribute already exists, it is replaced.
  (define (sxml:set-attr elem name value)
    (let* ((tag (sxml:element-name elem))
           (old-attrs (sxml:attributes elem))
           (children (sxml:children elem))
           (new-attrs
            (let loop ((attrs old-attrs) (acc '()) (found? #f))
              (cond
                ((null? attrs)
                 (if found?
                   (reverse acc)
                   (reverse (cons (list name value) acc))))
                ((and (pair? (car attrs)) (eq? (caar attrs) name))
                 (loop (cdr attrs)
                       (cons (list name value) acc)
                       #t))
                (else
                 (loop (cdr attrs)
                       (cons (car attrs) acc)
                       found?))))))
      (make-element tag new-attrs children)))

  ;; Add a child node (element or text) at the end.
  ;; Returns a new element.
  (define (sxml:add-child elem child)
    (let ((tag (sxml:element-name elem))
          (attrs (sxml:attributes elem))
          (children (sxml:children elem)))
      (make-element tag attrs (append children (list child)))))

  ;; Remove an attribute by name.  Returns a new element.
  (define (sxml:remove-attr elem name)
    (let* ((tag (sxml:element-name elem))
           (attrs (sxml:attributes elem))
           (children (sxml:children elem))
           (new-attrs (filter (lambda (a)
                                (not (and (pair? a) (eq? (car a) name))))
                              attrs)))
      (make-element tag new-attrs children)))

  ;; Extract all text content from an element, concatenated depth-first.
  (define (sxml:content elem)
    (cond
      ((string? elem) elem)
      ((sxml:element? elem)
       (apply string-append
              (map sxml:content (sxml:children elem))))
      (else "")))

  ;; Construct an SXML element from tag, attribute alist, and children list.
  ;; attrs is a list of (name value) pairs; can be '() for no attributes.
  ;; children is a list of elements and/or strings.
  (define (make-element tag attrs children)
    (if (null? attrs)
      (cons tag children)
      (cons tag (cons (cons '@ attrs) children))))

  ) ;; end library
