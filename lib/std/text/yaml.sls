#!chezscheme
;;; :std/text/yaml -- YAML parsing and emitting with roundtrip support
;;;
;;; Pure Scheme implementation. No external dependencies.
;;;
;;; Two modes:
;;;   Simple:    yaml-load / yaml-dump    — returns plain Scheme values
;;;   Roundtrip: yaml-read / yaml-write   — returns/consumes AST nodes
;;;
;;; Roundtrip mode preserves comments, key ordering, scalar styles,
;;; and block/flow formatting through load-modify-save cycles.
;;;
;;; YAML ↔ Scheme mapping (simple mode):
;;;   mapping  → alist (or hashtable via yaml-key-format)
;;;   sequence → list
;;;   scalar   → string, number, boolean, or (void) for null
;;;   alias    → resolved target value

(library (std text yaml)
  (export
    ;; Simple mode (backward compatible)
    yaml-load yaml-load-string
    yaml-dump yaml-dump-string
    yaml-key-format
    safe-yaml-load-string
    *yaml-max-input-size*
    *yaml-max-depth*

    ;; Roundtrip mode
    yaml-read yaml-read-string
    yaml-write yaml-write-string

    ;; Node types (re-exported from nodes)
    make-yaml-scalar yaml-scalar? yaml-scalar-value yaml-scalar-style
    yaml-scalar-tag yaml-scalar-anchor yaml-scalar-pre-comments yaml-scalar-eol-comment
    make-yaml-mapping yaml-mapping? yaml-mapping-pairs yaml-mapping-pairs-set!
    yaml-mapping-style yaml-mapping-tag yaml-mapping-anchor
    yaml-mapping-pre-comments yaml-mapping-eol-comment
    yaml-mapping-post-comments yaml-mapping-post-comments-set!
    make-yaml-sequence yaml-sequence? yaml-sequence-items yaml-sequence-items-set!
    yaml-sequence-style yaml-sequence-tag yaml-sequence-anchor
    yaml-sequence-pre-comments yaml-sequence-eol-comment
    yaml-sequence-post-comments yaml-sequence-post-comments-set!
    make-yaml-alias yaml-alias? yaml-alias-name
    make-yaml-document yaml-document? yaml-document-root yaml-document-root-set!
    yaml-document-pre-comments yaml-document-end-comments
    yaml-document-has-start? yaml-document-has-end?
    yaml-node?

    ;; Node manipulation
    yaml-mapping-ref yaml-mapping-set! yaml-mapping-delete!
    yaml-mapping-keys yaml-mapping-has-key?
    yaml-sequence-ref yaml-sequence-length yaml-sequence-append!

    ;; Conversion between nodes and plain Scheme values
    yaml->scheme scheme->yaml

    ;; Multi-path access
    yaml-ref yaml-set!
    )

  (import (chezscheme)
          (std text yaml nodes)
          (std text yaml reader)
          (std text yaml writer))

  ;; ---------------------------------------------------------------------------
  ;; Parameters
  ;; ---------------------------------------------------------------------------

  (define *yaml-max-input-size* (make-parameter (* 10 1024 1024)))  ;; 10MB
  (define *yaml-max-depth* (make-parameter 512))
  ;; 'string (default) or 'symbol -- controls key representation in simple mode
  (define yaml-key-format (make-parameter 'string))

  ;; ---------------------------------------------------------------------------
  ;; Roundtrip API
  ;; ---------------------------------------------------------------------------

  (define yaml-read
    (case-lambda
      (()    (yaml-read (current-input-port)))
      ((port)
       (let ((str (get-string-all port)))
         (yaml-read-string str)))))

  (define (yaml-read-string str)
    (check-input-size 'yaml-read-string str)
    (let ((docs (yaml-parse-string str)))
      (if (and (pair? docs) (null? (cdr docs)))
          (car docs)
          docs)))

  (define yaml-write
    (case-lambda
      ((doc)      (yaml-write doc (current-output-port)))
      ((doc port) (yaml-emit-port (if (list? doc) doc (list doc)) port))))

  (define (yaml-write-string doc)
    (yaml-emit-string (if (and (list? doc) (not (null? doc))
                               (yaml-document? (car doc)))
                          doc
                          (list doc))))

  ;; ---------------------------------------------------------------------------
  ;; Simple API (backward compatible)
  ;; ---------------------------------------------------------------------------

  (define yaml-load
    (case-lambda
      (()    (yaml-load (current-input-port)))
      ((port)
       (let ((str (get-string-all port)))
         (yaml-load-string str)))))

  (define (yaml-load-string str)
    (check-input-size 'yaml-load-string str)
    (let ((docs (yaml-parse-string str)))
      (cond
        ((null? docs) (void))
        ((null? (cdr docs))
         (let ((doc (car docs)))
           (if (yaml-document-root doc)
               (yaml->scheme (yaml-document-root doc))
               (void))))
        (else
         (map (lambda (doc)
                (if (yaml-document-root doc)
                    (yaml->scheme (yaml-document-root doc))
                    (void)))
              docs)))))

  (define (safe-yaml-load-string str)
    (check-input-size 'safe-yaml-load-string str)
    (yaml-load-string str))

  (define yaml-dump
    (case-lambda
      ((val)      (yaml-dump val (current-output-port)))
      ((val port) (yaml-emit-port (list (make-yaml-document (scheme->yaml val) '() '() #f #f))
                                  port))))

  (define (yaml-dump-string val)
    (yaml-emit-string (list (make-yaml-document (scheme->yaml val) '() '() #f #f))))

  ;; ---------------------------------------------------------------------------
  ;; Input validation
  ;; ---------------------------------------------------------------------------

  (define (check-input-size who str)
    (when (> (string-length str) (*yaml-max-input-size*))
      (error who "YAML input exceeds maximum size"
             (string-length str) (*yaml-max-input-size*))))

  ;; ---------------------------------------------------------------------------
  ;; Node manipulation
  ;; ---------------------------------------------------------------------------

  ;; Look up a key in a yaml-mapping node.
  ;; Returns the value node or #f.
  (define (yaml-mapping-ref node key)
    (let ((key-str (if (string? key) key (format "~a" key))))
      (let loop ((pairs (yaml-mapping-pairs node)))
        (cond
          ((null? pairs) #f)
          ((and (yaml-scalar? (caar pairs))
                (string=? (yaml-scalar-value (caar pairs)) key-str))
           (cdar pairs))
          (else (loop (cdr pairs)))))))

  ;; Set a key in a yaml-mapping. If key exists, replace value; otherwise append.
  ;; `val` can be a yaml-node or a plain Scheme value (auto-converted).
  (define (yaml-mapping-set! node key val)
    (let* ((key-str (if (string? key) key (format "~a" key)))
           (val-node (if (yaml-node? val) val (scheme->yaml val)))
           (pairs (yaml-mapping-pairs node))
           (found #f)
           (new-pairs
            (map (lambda (pair)
                   (if (and (not found)
                            (yaml-scalar? (car pair))
                            (string=? (yaml-scalar-value (car pair)) key-str))
                       (begin (set! found #t) (cons (car pair) val-node))
                       pair))
                 pairs)))
      (if found
          (yaml-mapping-pairs-set! node new-pairs)
          ;; Append new entry
          (yaml-mapping-pairs-set!
           node
           (append pairs
                   (list (cons (make-yaml-scalar key-str 'plain #f #f '() #f)
                               val-node)))))))

  ;; Delete a key from a yaml-mapping. Returns #t if found.
  (define (yaml-mapping-delete! node key)
    (let* ((key-str (if (string? key) key (format "~a" key)))
           (pairs (yaml-mapping-pairs node))
           (new-pairs
            (filter (lambda (pair)
                      (not (and (yaml-scalar? (car pair))
                                (string=? (yaml-scalar-value (car pair)) key-str))))
                    pairs)))
      (let ((deleted? (not (= (length new-pairs) (length pairs)))))
        (yaml-mapping-pairs-set! node new-pairs)
        deleted?)))

  ;; List all keys (as strings) in a mapping.
  (define (yaml-mapping-keys node)
    (map (lambda (pair)
           (if (yaml-scalar? (car pair))
               (yaml-scalar-value (car pair))
               ""))
         (yaml-mapping-pairs node)))

  ;; Check if a key exists.
  (define (yaml-mapping-has-key? node key)
    (not (not (yaml-mapping-ref node key))))

  ;; Access sequence items.
  (define (yaml-sequence-ref node index)
    (list-ref (yaml-sequence-items node) index))

  (define (yaml-sequence-length node)
    (length (yaml-sequence-items node)))

  ;; Append to a sequence.
  (define (yaml-sequence-append! node val)
    (let ((val-node (if (yaml-node? val) val (scheme->yaml val))))
      (yaml-sequence-items-set! node
                                (append (yaml-sequence-items node) (list val-node)))))

  ;; ---------------------------------------------------------------------------
  ;; Multi-path access: (yaml-ref doc "key1" "key2" 0 ...)
  ;; ---------------------------------------------------------------------------

  (define (yaml-ref node . keys)
    (let loop ((n node) (ks keys))
      (cond
        ((null? ks) n)
        ((not n) #f)
        ((yaml-document? n)
         (loop (yaml-document-root n) ks))
        ((yaml-mapping? n)
         (loop (yaml-mapping-ref n (car ks)) (cdr ks)))
        ((yaml-sequence? n)
         (if (integer? (car ks))
             (loop (yaml-sequence-ref n (car ks)) (cdr ks))
             #f))
        (else #f))))

  ;; (yaml-set! node key1 key2 ... val) — set the value at the key path.
  ;; Last argument is the value, everything between node and val are keys.
  (define (yaml-set! node . args)
    (when (< (length args) 2)
      (error 'yaml-set! "need at least one key and a value"))
    (let* ((rargs (reverse args))
           (val (car rargs))
           (keys (reverse (cdr rargs))))
      (let loop ((n node) (ks keys))
        (cond
          ((null? (cdr ks))
           ;; Last key -- do the set
           (cond
             ((yaml-document? n)
              (if (eq? (car ks) 'root)
                  (yaml-document-root-set! n (if (yaml-node? val) val (scheme->yaml val)))
                  (let ((root (yaml-document-root n)))
                    (when (yaml-mapping? root)
                      (yaml-mapping-set! root (car ks) val)))))
             ((yaml-mapping? n)
              (yaml-mapping-set! n (car ks) val))
             (else (error 'yaml-set! "cannot set on this node type" n))))
          (else
           (cond
             ;; Document: unwrap to root without consuming a key
             ((yaml-document? n)
              (let ((root (yaml-document-root n)))
                (when root (loop root ks))))
             ;; Mapping/sequence: navigate using current key
             (else
              (let ((child (cond
                             ((yaml-mapping? n) (yaml-mapping-ref n (car ks)))
                             ((yaml-sequence? n)
                              (if (integer? (car ks))
                                  (yaml-sequence-ref n (car ks))
                                  #f))
                             (else #f))))
                (when child (loop child (cdr ks)))))))))))

  ;; ---------------------------------------------------------------------------
  ;; Node ↔ Scheme value conversion
  ;; ---------------------------------------------------------------------------

  ;; Convert a yaml-node tree to plain Scheme values.
  (define (yaml->scheme node)
    (yaml->scheme* node 0 (make-hashtable string-hash string=?)))

  (define (yaml->scheme* node depth anchors)
    (when (> depth (*yaml-max-depth*))
      (error 'yaml->scheme "maximum nesting depth exceeded" depth))
    (cond
      ((not node) (void))
      ((yaml-scalar? node)
       (let ((val (yaml-scalar-value node))
             (tag (yaml-scalar-tag node))
             (anchor (yaml-scalar-anchor node)))
         (let ((result (resolve-scalar val tag)))
           (when anchor (hashtable-set! anchors anchor result))
           result)))
      ((yaml-mapping? node)
       (let ((anchor (yaml-mapping-anchor node))
             (result
              (map (lambda (pair)
                     (let ((k (yaml->scheme* (car pair) (+ depth 1) anchors))
                           (v (yaml->scheme* (cdr pair) (+ depth 1) anchors)))
                       (let ((key (case (yaml-key-format)
                                    ((symbol) (if (string? k) (string->symbol k) k))
                                    (else k))))
                         (cons key v))))
                   (yaml-mapping-pairs node))))
         (when anchor (hashtable-set! anchors anchor result))
         result))
      ((yaml-sequence? node)
       (let ((anchor (yaml-sequence-anchor node))
             (result
              (map (lambda (item)
                     (yaml->scheme* item (+ depth 1) anchors))
                   (yaml-sequence-items node))))
         (when anchor (hashtable-set! anchors anchor result))
         result))
      ((yaml-alias? node)
       (let ((target (hashtable-ref anchors (yaml-alias-name node) #f)))
         (or target (void))))
      (else (void))))

  ;; Resolve a scalar string to the appropriate Scheme type.
  (define (resolve-scalar val tag)
    (cond
      ;; Explicit tags
      ((and tag (string=? tag "!!str")) val)
      ((and tag (string=? tag "!!int")) (or (string->number val) val))
      ((and tag (string=? tag "!!float")) (or (string->number val) val))
      ((and tag (string=? tag "!!bool")) (resolve-bool val))
      ((and tag (string=? tag "!!null")) (void))
      ;; Auto-resolve
      ((string=? val "") (void))
      ((string=? val "~") (void))
      ((string=? val "null") (void))
      ((string=? val "Null") (void))
      ((string=? val "NULL") (void))
      ;; Booleans
      ((or (string=? val "true") (string=? val "True") (string=? val "TRUE")) #t)
      ((or (string=? val "false") (string=? val "False") (string=? val "FALSE")) #f)
      ((or (string=? val "yes") (string=? val "Yes") (string=? val "YES")) #t)
      ((or (string=? val "no") (string=? val "No") (string=? val "NO")) #f)
      ((or (string=? val "on") (string=? val "On") (string=? val "ON")) #t)
      ((or (string=? val "off") (string=? val "Off") (string=? val "OFF")) #f)
      ;; Special floats
      ((or (string=? val ".inf") (string=? val ".Inf") (string=? val ".INF")) +inf.0)
      ((or (string=? val "-.inf") (string=? val "-.Inf") (string=? val "-.INF")) -inf.0)
      ((or (string=? val ".nan") (string=? val ".NaN") (string=? val ".NAN")) +nan.0)
      ;; Integers
      ((string->yaml-int val) => (lambda (n) n))
      ;; Floats
      ((string->yaml-float val) => (lambda (n) n))
      ;; Default: string
      (else val)))

  (define (resolve-bool val)
    (cond
      ((or (string=? val "true") (string=? val "True") (string=? val "TRUE")
           (string=? val "yes") (string=? val "Yes") (string=? val "YES")
           (string=? val "on") (string=? val "On") (string=? val "ON")) #t)
      (else #f)))

  ;; Parse YAML integer formats: decimal, hex (0x), octal (0o), binary (0b).
  (define (string->yaml-int s)
    (let ((len (string-length s)))
      (cond
        ((zero? len) #f)
        ;; Hex: 0x...
        ((and (> len 2) (char=? (string-ref s 0) #\0)
              (or (char=? (string-ref s 1) #\x) (char=? (string-ref s 1) #\X)))
         (string->number (substring s 2 len) 16))
        ;; Octal: 0o...
        ((and (> len 2) (char=? (string-ref s 0) #\0)
              (or (char=? (string-ref s 1) #\o) (char=? (string-ref s 1) #\O)))
         (string->number (substring s 2 len) 8))
        ;; Binary: 0b...
        ((and (> len 2) (char=? (string-ref s 0) #\0)
              (or (char=? (string-ref s 1) #\b) (char=? (string-ref s 1) #\B)))
         (string->number (substring s 2 len) 2))
        ;; Signed decimal
        ((or (char-numeric? (string-ref s 0))
             (and (> len 1)
                  (or (char=? (string-ref s 0) #\+) (char=? (string-ref s 0) #\-))
                  (char-numeric? (string-ref s 1))))
         (let ((n (string->number s)))
           (and n (integer? n) (exact? n) n)))
        (else #f))))

  ;; Parse YAML float formats.
  (define (string->yaml-float s)
    (let ((len (string-length s)))
      (cond
        ((zero? len) #f)
        ((or (string-contains-char? s #\.)
             (string-contains-char? s #\e)
             (string-contains-char? s #\E))
         (let ((n (string->number s)))
           (and n (number? n) (inexact n))))
        (else #f))))

  (define (string-contains-char? s ch)
    (let ((len (string-length s)))
      (let loop ((i 0))
        (cond
          ((>= i len) #f)
          ((char=? (string-ref s i) ch) #t)
          (else (loop (+ i 1)))))))

  ;; Convert a plain Scheme value to a yaml-node tree.
  (define (scheme->yaml val)
    (cond
      ((string? val)
       (if (needs-quoting? val)
           (make-yaml-scalar val 'double-quoted #f #f '() #f)
           (make-yaml-scalar val 'plain #f #f '() #f)))
      ((symbol? val)
       (scheme->yaml (symbol->string val)))
      ((boolean? val)
       (make-yaml-scalar (if val "true" "false") 'plain #f #f '() #f))
      ((eq? val (void))
       (make-yaml-scalar "null" 'plain #f #f '() #f))
      ((integer? val)
       (make-yaml-scalar (number->string val) 'plain #f #f '() #f))
      ((number? val)
       (make-yaml-scalar (number->string (inexact val)) 'plain #f #f '() #f))
      ((list? val)
       (if (and (pair? val) (pair? (car val)))
           ;; alist -> mapping
           (make-yaml-mapping
            (map (lambda (pair)
                   (cons (scheme->yaml (car pair))
                         (scheme->yaml (cdr pair))))
                 val)
            'block #f #f '() #f '())
           ;; list -> sequence
           (make-yaml-sequence
            (map scheme->yaml val)
            'block #f #f '() #f '())))
      ((vector? val)
       (make-yaml-sequence
        (map scheme->yaml (vector->list val))
        'block #f #f '() #f '()))
      ((hashtable? val)
       (let-values (((keys vals) (hashtable-entries val)))
         (make-yaml-mapping
          (let loop ((i 0) (acc '()))
            (if (>= i (vector-length keys))
                (reverse acc)
                (loop (+ i 1)
                      (cons (cons (scheme->yaml (vector-ref keys i))
                                  (scheme->yaml (vector-ref vals i)))
                            acc))))
          'block #f #f '() #f '())))
      (else
       (make-yaml-scalar (format "~a" val) 'plain #f #f '() #f))))

  ;; Check if a string value needs quoting to avoid ambiguity.
  (define (needs-quoting? s)
    (or (string=? s "")
        (string=? s "~")
        (string=? s "null") (string=? s "Null") (string=? s "NULL")
        (string=? s "true") (string=? s "True") (string=? s "TRUE")
        (string=? s "false") (string=? s "False") (string=? s "FALSE")
        (string=? s "yes") (string=? s "Yes") (string=? s "YES")
        (string=? s "no") (string=? s "No") (string=? s "NO")
        (string=? s "on") (string=? s "On") (string=? s "ON")
        (string=? s "off") (string=? s "Off") (string=? s "OFF")
        (string=? s ".inf") (string=? s ".Inf") (string=? s ".INF")
        (string=? s "-.inf") (string=? s "-.Inf") (string=? s "-.INF")
        (string=? s ".nan") (string=? s ".NaN") (string=? s ".NAN")
        (and (> (string-length s) 0)
             (or (memv (string-ref s 0) '(#\{ #\[ #\* #\& #\! #\| #\> #\' #\" #\% #\@ #\`))
                 (string-contains-char? s #\:)
                 (string-contains-char? s #\#)))
        (string->number s)))

  ;; ---------------------------------------------------------------------------
  ;; Utility
  ;; ---------------------------------------------------------------------------


) ;; end library
