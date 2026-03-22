#!chezscheme
;;; jerboa/prelude -- One-import-to-rule-them-all
;;;
;;; (import (jerboa prelude)) gives you all of Gerbil's user-facing API:
;;; - Core macros: def, defstruct, defmethod, match, try/catch, etc.
;;; - Runtime: hash tables, method dispatch, keywords
;;; - Standard library: sort, format, JSON, paths, strings, lists, etc.
;;; - FFI: c-lambda, define-c-lambda

(library (jerboa prelude)
  (export
    ;; ---- Core macros ----
    def def* defrule defrules
    defstruct defclass defmethod
    match match/strict
    define-match-type define-sealed-hierarchy define-active-pattern
    try catch finally
    while until

    ;; hash constructors
    hash-literal hash-eq-literal
    let-hash

    ;; ---- Runtime ----
    ~ bind-method! call-method
    make-hash-table make-hash-table-eq
    hash-ref hash-get hash-put! hash-update! hash-remove!
    hash-key? hash->list hash->plist hash-for-each hash-map hash-fold
    hash-find hash-keys hash-values hash-copy hash-clear!
    hash-merge hash-merge! hash-length hash-table?
    list->hash-table plist->hash-table
    keyword? keyword->string string->keyword make-keyword
    error-message error-irritants error-trace
    displayln 1+ 1-
    iota last-pair
    *method-tables*
    register-struct-type! *struct-types*
    struct-predicate struct-field-ref struct-field-set!
    struct-type-info

    ;; ---- std/sort ----
    sort sort! stable-sort stable-sort!

    ;; ---- std/format ----
    format printf fprintf eprintf

    ;; ---- std/error ----
    Error ContractViolation

    ;; ---- std/sugar ----
    chain chain-and assert!

    ;; ---- std/text/json ----
    read-json write-json json-object->string string->json-object

    ;; ---- std/os/path ----
    path-expand path-normalize path-directory path-strip-directory
    path-extension path-strip-extension
    path-join path-absolute?

    ;; ---- std/misc/string ----
    string-split string-join string-trim
    string-prefix? string-suffix?
    string-contains string-index
    string-empty?

    ;; ---- std/misc/list ----
    flatten unique snoc
    take drop
    every any
    filter-map
    group-by
    zip

    ;; ---- std/misc/alist ----
    agetq agetv aget
    asetq! asetv! aset!
    pgetq pgetv pget
    alist->hash-table

    ;; ---- std/misc/ports ----
    read-all-as-string read-all-as-lines
    read-file-string read-file-lines
    write-file-string
    with-input-from-string with-output-to-string

    ;; ---- FFI ----
    c-lambda define-c-lambda
    begin-ffi c-declare)

  (import
    (except (chezscheme)
            make-hash-table hash-table?
            sort sort!
            printf fprintf
            path-extension path-absolute?
            with-input-from-string with-output-to-string
            iota 1+ 1-)
    (only (jerboa core)
      def def* defrule defrules
      defstruct defclass defmethod
      try catch finally
      while until
      hash-literal hash-eq-literal
      let-hash)
    (only (std match2)
      match match/strict
      define-match-type define-sealed-hierarchy define-active-pattern)
    (jerboa runtime)
    (jerboa ffi)
    (std sort)
    (std format)
    (except (std error) error-message error-irritants error-trace error?
                       with-exception-handler)
    (except (std sugar) try catch finally while until
                       hash-literal hash-eq-literal let-hash
                       defrule defrules)
    (std text json)
    (std os path)
    (std misc string)
    (std misc list)
    (std misc alist)
    (std misc ports))

  ) ;; end library
