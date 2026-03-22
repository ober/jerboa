#!chezscheme
;;; :std/text/yaml/writer -- YAML emitter with roundtrip support
;;;
;;; Walks a yaml-node AST and produces YAML text, preserving styles,
;;; comments, and formatting from the original parse.

(library (std text yaml writer)
  (export yaml-emit-string yaml-emit-port)
  (import (chezscheme)
          (std text yaml nodes))

  ;; ---------------------------------------------------------------------------
  ;; Main entry points
  ;; ---------------------------------------------------------------------------

  (define (yaml-emit-string docs)
    (let ((port (open-output-string)))
      (yaml-emit-port docs port)
      (get-output-string port)))

  (define (yaml-emit-port docs port)
    (cond
      ((yaml-document? docs)
       (emit-document docs port))
      ((and (list? docs) (not (null? docs)))
       (let loop ((ds docs) (first? #t))
         (when (pair? ds)
           (unless first? (newline port))
           (emit-document (car ds) port)
           (loop (cdr ds) #f))))
      ((yaml-node? docs)
       ;; Bare node, wrap in document
       (emit-node docs port 0 #t)
       (newline port))
      (else
       (error 'yaml-emit "expected yaml-document or list of documents" docs))))

  ;; ---------------------------------------------------------------------------
  ;; Document emission
  ;; ---------------------------------------------------------------------------

  (define (emit-document doc port)
    ;; Pre-comments
    (emit-comment-lines (yaml-document-pre-comments doc) port)
    ;; Document start marker
    (when (yaml-document-has-start? doc)
      (display "---" port)
      (newline port))
    ;; Root node
    (when (yaml-document-root doc)
      (let ((root (yaml-document-root doc)))
        (emit-node root port 0 #t)
        ;; Block collections already emit trailing newlines; scalars and flow don't
        (when (or (yaml-scalar? root)
                  (and (yaml-mapping? root) (eq? (yaml-mapping-style root) 'flow))
                  (and (yaml-sequence? root) (eq? (yaml-sequence-style root) 'flow)))
          (newline port))))
    ;; Document end marker
    (when (yaml-document-has-end? doc)
      (display "..." port)
      (newline port))
    ;; End comments
    (emit-comment-lines (yaml-document-end-comments doc) port))

  ;; ---------------------------------------------------------------------------
  ;; Comment emission
  ;; ---------------------------------------------------------------------------

  (define (emit-comment-lines comments port)
    (for-each
     (lambda (c)
       (if (string=? c "")
           (newline port)  ;; blank line
           (begin (display c port) (newline port))))
     comments))

  (define (emit-eol-comment eol port)
    (when eol
      (display eol port)))

  ;; ---------------------------------------------------------------------------
  ;; Node emission
  ;; ---------------------------------------------------------------------------

  ;; `indent`: current indentation level (number of spaces)
  ;; `top?`: whether this is at the top of the document (no indent prefix needed)
  (define (emit-node node port indent top?)
    (cond
      ((yaml-scalar? node)   (emit-scalar node port indent top?))
      ((yaml-mapping? node)  (emit-mapping node port indent top?))
      ((yaml-sequence? node) (emit-sequence node port indent top?))
      ((yaml-alias? node)    (emit-alias node port indent top?))
      ((not node)            (display "null" port))
      (else (error 'yaml-emit "unknown node type" node))))

  ;; ---------------------------------------------------------------------------
  ;; Scalar emission
  ;; ---------------------------------------------------------------------------

  (define (emit-scalar node port indent top?)
    (emit-comment-lines (yaml-scalar-pre-comments node) port)
    (let ((val (yaml-scalar-value node))
          (style (yaml-scalar-style node))
          (anchor (yaml-scalar-anchor node))
          (tag (yaml-scalar-tag node)))
      ;; Anchor and tag
      (when anchor
        (display "&" port)
        (display anchor port)
        (display " " port))
      (when tag
        (display tag port)
        (display " " port))
      ;; Value
      (case style
        ((plain)
         (display val port))
        ((single-quoted)
         (display "'" port)
         (display (string-replace-all val "'" "''") port)
         (display "'" port))
        ((double-quoted)
         (display "\"" port)
         (display (escape-double-quoted val) port)
         (display "\"" port))
        ((literal)
         (emit-block-scalar node port indent #\|))
        ((folded)
         (emit-block-scalar node port indent #\>))
        (else
         (display val port)))))

  (define (emit-block-scalar node port indent indicator)
    (let ((val (yaml-scalar-value node)))
      (display indicator port)
      ;; Determine chomp indicator
      (cond
        ((and (> (string-length val) 0)
              (char=? (string-ref val (- (string-length val) 1)) #\newline))
         ;; Ends with newline -- could be clip (default) or keep
         ;; Check if multiple trailing newlines
         (let ((trimmed (string-trim-trailing-nls val)))
           (if (> (- (string-length val) (string-length trimmed)) 1)
               (display "+" port)  ;; keep
               (void))))  ;; clip is default
        ((> (string-length val) 0)
         (display "-" port)))  ;; strip trailing newline
      ;; Split into lines and emit
      (let ((lines (string-split-newlines val))
            (ind-str (make-indent-string (+ indent 2))))
        (for-each
         (lambda (line)
           (newline port)
           (if (string=? line "")
               (void)  ;; blank line in block scalar
               (begin
                 (display ind-str port)
                 (display line port))))
         lines))))

  (define (string-trim-trailing-nls s)
    (let loop ((i (- (string-length s) 1)))
      (cond
        ((< i 0) "")
        ((char=? (string-ref s i) #\newline) (loop (- i 1)))
        (else (substring s 0 (+ i 1))))))

  (define (string-split-newlines s)
    (let ((len (string-length s)))
      (let loop ((i 0) (start 0) (acc '()))
        (cond
          ((>= i len)
           (reverse (if (> i start)
                        (cons (substring s start i) acc)
                        acc)))
          ((char=? (string-ref s i) #\newline)
           (loop (+ i 1) (+ i 1) (cons (substring s start i) acc)))
          (else (loop (+ i 1) start acc))))))

  ;; ---------------------------------------------------------------------------
  ;; Mapping emission
  ;; ---------------------------------------------------------------------------

  (define (emit-mapping node port indent top?)
    (let ((pairs (yaml-mapping-pairs node))
          (style (yaml-mapping-style node))
          (anchor (yaml-mapping-anchor node))
          (tag (yaml-mapping-tag node)))
      (case style
        ((flow) (emit-flow-mapping node port indent))
        (else   (emit-block-mapping node port indent top?)))))

  (define (emit-block-mapping node port indent top?)
    (let ((pairs (yaml-mapping-pairs node))
          (anchor (yaml-mapping-anchor node))
          (tag (yaml-mapping-tag node))
          (ind-str (make-indent-string indent)))
      ;; Mapping-level pre-comments
      (emit-comment-lines (yaml-mapping-pre-comments node) port)
      ;; Anchor/tag on mapping
      (when (or anchor tag)
        (display ind-str port)
        (when anchor (display "&" port) (display anchor port) (display " " port))
        (when tag (display tag port) (display " " port))
        (newline port))
      ;; Entries
      (for-each
       (lambda (pair)
         (let ((key (car pair))
               (val (cdr pair)))
           ;; Key pre-comments
           (when (yaml-node? key)
             (emit-comment-lines (yaml-scalar-pre-comments* key) port))
           ;; Key
           (display ind-str port)
           (emit-key key port)
           (display ":" port)
           ;; Value
           (cond
             ;; Block collection value -- on next line
             ((and (yaml-node? val)
                   (or (and (yaml-mapping? val) (eq? (yaml-mapping-style val) 'block))
                       (and (yaml-sequence? val) (eq? (yaml-sequence-style val) 'block))))
              ;; EOL comment on the key line
              (emit-eol-comment (yaml-scalar-eol-comment* key) port)
              (newline port)
              (emit-node val port (+ indent 2) #f))
             ;; Block scalar value -- indicator on same line, content indented
             ((and (yaml-scalar? val)
                   (memq (yaml-scalar-style val) '(literal folded)))
              (display " " port)
              (emit-scalar val port indent #f)
              (newline port))
             ;; Inline value
             (else
              (display " " port)
              (emit-node val port (+ indent 2) #f)
              (emit-eol-comment (node-eol-comment val) port)
              (newline port)))))
       pairs)
      ;; Post-comments (trailing comments in the mapping)
      (emit-comment-lines (yaml-mapping-post-comments node) port)))

  (define (emit-key node port)
    (cond
      ((yaml-scalar? node)
       (let ((val (yaml-scalar-value node))
             (style (yaml-scalar-style node))
             (anchor (yaml-scalar-anchor node)))
         (when anchor
           (display "&" port)
           (display anchor port)
           (display " " port))
         (case style
           ((single-quoted)
            (display "'" port)
            (display (string-replace-all val "'" "''") port)
            (display "'" port))
           ((double-quoted)
            (display "\"" port)
            (display (escape-double-quoted val) port)
            (display "\"" port))
           (else (display val port)))))
      (else
       (display "?" port)
       (display " " port)
       (emit-node node port 0 #f))))

  ;; Extract pre-comments from any node type.
  (define (yaml-scalar-pre-comments* node)
    (cond
      ((yaml-scalar? node)   (yaml-scalar-pre-comments node))
      ((yaml-mapping? node)  (yaml-mapping-pre-comments node))
      ((yaml-sequence? node) (yaml-sequence-pre-comments node))
      ((yaml-alias? node)    (yaml-alias-pre-comments node))
      (else '())))

  ;; Extract eol-comment from a key node (scalars only for now).
  (define (yaml-scalar-eol-comment* node)
    (cond
      ((yaml-scalar? node) (yaml-scalar-eol-comment node))
      (else #f)))

  ;; Extract eol-comment from any node.
  (define (node-eol-comment node)
    (cond
      ((yaml-scalar? node)   (yaml-scalar-eol-comment node))
      ((yaml-mapping? node)  (yaml-mapping-eol-comment node))
      ((yaml-sequence? node) (yaml-sequence-eol-comment node))
      ((yaml-alias? node)    (yaml-alias-eol-comment node))
      (else #f)))

  (define (emit-flow-mapping node port indent)
    (let ((pairs (yaml-mapping-pairs node))
          (anchor (yaml-mapping-anchor node))
          (tag (yaml-mapping-tag node)))
      (when anchor (display "&" port) (display anchor port) (display " " port))
      (when tag (display tag port) (display " " port))
      (display "{" port)
      (let loop ((ps pairs) (first? #t))
        (when (pair? ps)
          (unless first? (display ", " port))
          (let ((key (caar ps))
                (val (cdar ps)))
            (emit-flow-value key port)
            (display ": " port)
            (emit-flow-value val port))
          (loop (cdr ps) #f)))
      (display "}" port)))

  ;; ---------------------------------------------------------------------------
  ;; Sequence emission
  ;; ---------------------------------------------------------------------------

  (define (emit-sequence node port indent top?)
    (let ((style (yaml-sequence-style node)))
      (case style
        ((flow) (emit-flow-sequence node port indent))
        (else   (emit-block-sequence node port indent top?)))))

  (define (emit-block-sequence node port indent top?)
    (let ((items (yaml-sequence-items node))
          (anchor (yaml-sequence-anchor node))
          (tag (yaml-sequence-tag node))
          (ind-str (make-indent-string indent)))
      ;; Sequence-level pre-comments
      (emit-comment-lines (yaml-sequence-pre-comments node) port)
      ;; Anchor/tag
      (when (or anchor tag)
        (display ind-str port)
        (when anchor (display "&" port) (display anchor port) (display " " port))
        (when tag (display tag port) (display " " port))
        (newline port))
      ;; Items
      (for-each
       (lambda (item)
         ;; Item pre-comments
         (emit-comment-lines (yaml-scalar-pre-comments* item) port)
         ;; "- " prefix
         (display ind-str port)
         (display "- " port)
         ;; Value
         (cond
           ;; Block collection -- on next line(s) after "- "
           ((and (yaml-mapping? item) (eq? (yaml-mapping-style item) 'block))
            ;; For compact notation: mapping starts on same line as "-"
            ;; Check if the first key has no pre-comments
            (let ((pairs (yaml-mapping-pairs item)))
              (if (and (pair? pairs)
                       (null? (yaml-scalar-pre-comments* (caar pairs))))
                  ;; Compact: first entry on same line as -
                  (emit-compact-mapping item port (+ indent 2))
                  ;; Full: entries start on next line
                  (begin
                    (newline port)
                    (emit-node item port (+ indent 2) #f)))))
           ((and (yaml-sequence? item) (eq? (yaml-sequence-style item) 'block))
            (newline port)
            (emit-node item port (+ indent 2) #f))
           ;; Block scalar
           ((and (yaml-scalar? item)
                 (memq (yaml-scalar-style item) '(literal folded)))
            (emit-scalar item port (+ indent 2) #f)
            (newline port))
           ;; Inline value
           (else
            (emit-inline-value item port)
            (emit-eol-comment (node-eol-comment item) port)
            (newline port))))
       items)
      ;; Post-comments
      (emit-comment-lines (yaml-sequence-post-comments node) port)))

  ;; Emit a mapping in compact block notation (first entry on same line as "- ").
  (define (emit-compact-mapping node port indent)
    (let ((pairs (yaml-mapping-pairs node))
          (ind-str (make-indent-string indent)))
      (let loop ((ps pairs) (first? #t))
        (when (pair? ps)
          (let ((key (caar ps))
                (val (cdar ps)))
            (unless first?
              (display ind-str port))
            (emit-key key port)
            (display ":" port)
            (cond
              ((and (yaml-node? val)
                    (or (and (yaml-mapping? val) (eq? (yaml-mapping-style val) 'block))
                        (and (yaml-sequence? val) (eq? (yaml-sequence-style val) 'block))))
               (emit-eol-comment (yaml-scalar-eol-comment* key) port)
               (newline port)
               (emit-node val port (+ indent 2) #f))
              ((and (yaml-scalar? val)
                    (memq (yaml-scalar-style val) '(literal folded)))
               (display " " port)
               (emit-scalar val port indent #f)
               (newline port))
              (else
               (display " " port)
               (emit-inline-value val port)
               (emit-eol-comment (node-eol-comment val) port)
               (newline port))))
          (loop (cdr ps) #f)))))

  ;; Emit a value inline (no indentation prefix).
  (define (emit-inline-value node port)
    (cond
      ((yaml-scalar? node)
       (let ((val (yaml-scalar-value node))
             (style (yaml-scalar-style node))
             (anchor (yaml-scalar-anchor node))
             (tag (yaml-scalar-tag node)))
         (when anchor (display "&" port) (display anchor port) (display " " port))
         (when tag (display tag port) (display " " port))
         (case style
           ((plain) (display val port))
           ((single-quoted)
            (display "'" port)
            (display (string-replace-all val "'" "''") port)
            (display "'" port))
           ((double-quoted)
            (display "\"" port)
            (display (escape-double-quoted val) port)
            (display "\"" port))
           (else (display val port)))))
      ((yaml-mapping? node)
       (emit-flow-mapping node port 0))
      ((yaml-sequence? node)
       (emit-flow-sequence node port 0))
      ((yaml-alias? node)
       (display "*" port)
       (display (yaml-alias-name node) port))
      (else
       (display "null" port))))

  (define (emit-flow-sequence node port indent)
    (let ((items (yaml-sequence-items node))
          (anchor (yaml-sequence-anchor node))
          (tag (yaml-sequence-tag node)))
      (when anchor (display "&" port) (display anchor port) (display " " port))
      (when tag (display tag port) (display " " port))
      (display "[" port)
      (let loop ((is items) (first? #t))
        (when (pair? is)
          (unless first? (display ", " port))
          (emit-flow-value (car is) port)
          (loop (cdr is) #f)))
      (display "]" port)))

  ;; Emit a value in flow context.
  (define (emit-flow-value node port)
    (cond
      ((yaml-scalar? node)
       (let ((val (yaml-scalar-value node))
             (style (yaml-scalar-style node)))
         (case style
           ((single-quoted)
            (display "'" port)
            (display (string-replace-all val "'" "''") port)
            (display "'" port))
           ((double-quoted)
            (display "\"" port)
            (display (escape-double-quoted val) port)
            (display "\"" port))
           (else (display val port)))))
      ((yaml-mapping? node) (emit-flow-mapping node port 0))
      ((yaml-sequence? node) (emit-flow-sequence node port 0))
      ((yaml-alias? node)
       (display "*" port)
       (display (yaml-alias-name node) port))
      (else (display "null" port))))

  ;; ---------------------------------------------------------------------------
  ;; Alias emission
  ;; ---------------------------------------------------------------------------

  (define (emit-alias node port indent top?)
    (emit-comment-lines (yaml-alias-pre-comments node) port)
    (unless top? (display (make-indent-string indent) port))
    (display "*" port)
    (display (yaml-alias-name node) port)
    (emit-eol-comment (yaml-alias-eol-comment node) port))

  ;; ---------------------------------------------------------------------------
  ;; String utilities
  ;; ---------------------------------------------------------------------------

  (define (make-indent-string n)
    (make-string n #\space))

  (define (string-replace-all s old new)
    (let ((slen (string-length s))
          (olen (string-length old)))
      (if (zero? olen) s
          (let ((out (open-output-string)))
            (let loop ((i 0))
              (cond
                ((> (+ i olen) slen)
                 (display (substring s i slen) out)
                 (get-output-string out))
                ((string=? old (substring s i (+ i olen)))
                 (display new out)
                 (loop (+ i olen)))
                (else
                 (display (string-ref s i) out)
                 (loop (+ i 1)))))))))

  (define (escape-double-quoted s)
    (let ((out (open-output-string)))
      (string-for-each
       (lambda (ch)
         (cond
           ((char=? ch #\") (display "\\\"" out))
           ((char=? ch #\\) (display "\\\\" out))
           ((char=? ch #\newline) (display "\\n" out))
           ((char=? ch #\tab) (display "\\t" out))
           ((char=? ch #\return) (display "\\r" out))
           ((char=? ch #\nul) (display "\\0" out))
           ((char=? ch #\alarm) (display "\\a" out))
           ((char=? ch #\backspace) (display "\\b" out))
           (else (display ch out))))
       s)
      (get-output-string out)))

) ;; end library
