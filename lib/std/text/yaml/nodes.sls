#!chezscheme
;;; :std/text/yaml/nodes -- YAML AST node types for roundtrip support
;;;
;;; Every node carries metadata for preserving comments, formatting,
;;; and style through load-modify-save cycles.

(library (std text yaml nodes)
  (export
    ;; Scalar
    make-yaml-scalar yaml-scalar?
    yaml-scalar-value yaml-scalar-style yaml-scalar-tag yaml-scalar-anchor
    yaml-scalar-pre-comments yaml-scalar-eol-comment
    ;; Mapping
    make-yaml-mapping yaml-mapping?
    yaml-mapping-pairs yaml-mapping-pairs-set!
    yaml-mapping-style yaml-mapping-tag yaml-mapping-anchor
    yaml-mapping-pre-comments yaml-mapping-eol-comment
    yaml-mapping-post-comments yaml-mapping-post-comments-set!
    ;; Sequence
    make-yaml-sequence yaml-sequence?
    yaml-sequence-items yaml-sequence-items-set!
    yaml-sequence-style yaml-sequence-tag yaml-sequence-anchor
    yaml-sequence-pre-comments yaml-sequence-eol-comment
    yaml-sequence-post-comments yaml-sequence-post-comments-set!
    ;; Alias
    make-yaml-alias yaml-alias?
    yaml-alias-name yaml-alias-pre-comments yaml-alias-eol-comment
    ;; Document
    make-yaml-document yaml-document?
    yaml-document-root yaml-document-root-set!
    yaml-document-pre-comments yaml-document-end-comments
    yaml-document-has-start? yaml-document-has-end?
    ;; Predicates
    yaml-node?)

  (import (chezscheme))

  ;; A scalar value with preserved style.
  ;; value: the raw string text (before type resolution)
  ;; style: plain | single-quoted | double-quoted | literal | folded
  ;; tag/anchor: string or #f
  ;; pre-comments: list of strings (full comment/blank lines before this node)
  ;; eol-comment: string or #f (text after value on same line, e.g. "  # note")
  (define-record-type yaml-scalar
    (fields value style tag anchor pre-comments eol-comment))

  ;; An ordered mapping (preserves key insertion order).
  ;; pairs: list of (key-node . value-node) -- key carries entry pre-comments
  ;; style: block | flow
  ;; post-comments: trailing comments inside the collection (after last entry)
  (define-record-type yaml-mapping
    (fields (mutable pairs) style tag anchor
            pre-comments eol-comment (mutable post-comments)))

  ;; An ordered sequence.
  ;; items: list of yaml-node -- each carries its entry pre-comments
  ;; style: block | flow
  ;; post-comments: trailing comments inside the collection
  (define-record-type yaml-sequence
    (fields (mutable items) style tag anchor
            pre-comments eol-comment (mutable post-comments)))

  ;; A YAML alias (*name).
  (define-record-type yaml-alias
    (fields name pre-comments eol-comment))

  ;; A YAML document (one per --- block).
  ;; pre-comments: comments before the document start marker
  ;; end-comments: comments after the document content
  ;; has-start?/has-end?: whether explicit --- / ... markers were present
  (define-record-type yaml-document
    (fields (mutable root) pre-comments end-comments has-start? has-end?))

  (define (yaml-node? x)
    (or (yaml-scalar? x)
        (yaml-mapping? x)
        (yaml-sequence? x)
        (yaml-alias? x)))

) ;; end library
