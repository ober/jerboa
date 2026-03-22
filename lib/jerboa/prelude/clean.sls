#!chezscheme
;;; (jerboa prelude clean) — Conflict-free prelude for use with (chezscheme)
;;;
;;; Provides all Gerbil-compatible APIs from (jerboa prelude) that do NOT
;;; conflict with (chezscheme) exports.  Users can write:
;;;
;;;   (import (chezscheme) (jerboa prelude clean))
;;;
;;; without needing any (except ...) clauses.
;;;
;;; Excluded (conflicts with Chez): sort, sort!, format, printf, fprintf,
;;; iota, 1+, 1-, path-extension, path-absolute?, make-hash-table,
;;; hash-table?, with-input-from-string, with-output-to-string,
;;; box, box?, unbox, set-box!

(library (jerboa prelude clean)
  (export
    ;; ---- Core macros ----
    def def* defrule defrules
    defstruct defclass defmethod
    match
    try catch finally
    while until
    hash-literal hash-eq-literal
    let-hash

    ;; ---- Runtime (no make-hash-table, hash-table?, 1+, 1-, iota) ----
    ~ bind-method! call-method
    make-hash-table-eq
    hash-ref hash-get hash-put! hash-update! hash-remove!
    hash-key? hash->list hash->plist hash-for-each hash-map hash-fold
    hash-find hash-keys hash-values hash-copy hash-clear!
    hash-merge hash-merge! hash-length
    list->hash-table plist->hash-table
    keyword? keyword->string string->keyword make-keyword
    error-message error-irritants error-trace
    displayln
    last-pair
    *method-tables*
    register-struct-type! *struct-types*
    struct-predicate struct-field-ref struct-field-set!
    struct-type-info

    ;; ---- std/sort (no sort, sort!) ----
    stable-sort stable-sort!

    ;; ---- std/format (no format, printf, fprintf) ----
    eprintf

    ;; ---- std/error ----
    Error ContractViolation

    ;; ---- std/sugar ----
    chain chain-and assert!

    ;; ---- std/text/json ----
    read-json write-json json-object->string string->json-object

    ;; ---- std/os/path (no path-extension, path-absolute?) ----
    path-expand path-normalize path-directory path-strip-directory
    path-strip-extension path-join

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

    ;; ---- std/misc/ports (no with-input-from-string, with-output-to-string) ----
    read-all-as-string read-all-as-lines
    read-file-string read-file-lines
    write-file-string

    ;; ---- FFI ----
    c-lambda define-c-lambda
    begin-ffi c-declare)

  (import
    (only (jerboa core)
      def def* defrule defrules
      defstruct defclass defmethod
      match
      try catch finally
      while until
      hash-literal hash-eq-literal
      let-hash)
    (only (jerboa runtime)
      ~ bind-method! call-method
      make-hash-table-eq
      hash-ref hash-get hash-put! hash-update! hash-remove!
      hash-key? hash->list hash->plist hash-for-each hash-map hash-fold
      hash-find hash-keys hash-values hash-copy hash-clear!
      hash-merge hash-merge! hash-length
      list->hash-table plist->hash-table
      keyword? keyword->string string->keyword make-keyword
      error-message error-irritants error-trace
      displayln
      last-pair
      *method-tables*
      register-struct-type! *struct-types*
      struct-predicate struct-field-ref struct-field-set!
      struct-type-info)
    (only (jerboa ffi) c-lambda define-c-lambda begin-ffi c-declare)
    (only (std sort) stable-sort stable-sort!)
    (only (std format) eprintf)
    (only (std error) Error ContractViolation)
    (only (std sugar) chain chain-and assert!)
    (only (std text json) read-json write-json json-object->string string->json-object)
    (only (std os path) path-expand path-normalize path-directory path-strip-directory
                        path-strip-extension path-join)
    (only (std misc string) string-split string-join string-trim
                            string-prefix? string-suffix?
                            string-contains string-index
                            string-empty?)
    (only (std misc list) flatten unique snoc take drop every any
                          filter-map group-by zip)
    (only (std misc alist) agetq agetv aget asetq! asetv! aset! pgetq pgetv pget
                           alist->hash-table)
    (only (std misc ports) read-all-as-string read-all-as-lines
                           read-file-string read-file-lines
                           write-file-string))

  ) ;; end library
