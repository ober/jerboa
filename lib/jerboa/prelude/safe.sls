#!chezscheme
;;; (jerboa prelude safe) — Safe-by-default prelude
;;;
;;; Import this instead of (jerboa prelude) to get safety for free.
;;; All dangerous APIs are replaced with contract-checked, timeout-enforced,
;;; resource-safe equivalents under the STANDARD names:
;;;
;;;   (import (jerboa prelude safe))
;;;   (with-resource ([db (sqlite-open "test.db")])
;;;     (sqlite-exec db "CREATE TABLE t(x)")
;;;     (sqlite-query db "SELECT * FROM t"))
;;;
;;; The safe versions:
;;; - Validate arguments before FFI calls
;;; - Return structured error conditions instead of bare (error ...)
;;; - Support automatic resource cleanup via with-resource
;;; - Enforce timeouts on blocking operations
;;; - Reject unsafe FASL deserialization
;;; - Do NOT export raw FFI forms (c-lambda, foreign-procedure, etc.)

(library (jerboa prelude safe)
  (export
    ;; ---- Everything from (jerboa prelude) EXCEPT raw FFI ----
    ;; Core macros
    def def* defrule defrules
    defstruct defclass defmethod
    match
    try catch finally
    while until

    ;; hash constructors
    hash-literal hash-eq-literal
    let-hash

    ;; Runtime
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

    ;; std/sort
    sort sort! stable-sort stable-sort!

    ;; std/format
    format printf fprintf eprintf

    ;; std/error
    Error ContractViolation

    ;; std/sugar
    chain chain-and assert!

    ;; std/text/json — safe wrappers under standard names
    read-json write-json json-object->string string->json-object

    ;; std/os/path
    path-expand path-normalize path-directory path-strip-directory
    path-extension path-strip-extension
    path-join path-absolute?

    ;; std/misc/string
    string-split string-join string-trim
    string-prefix? string-suffix?
    string-contains string-index
    string-empty?

    ;; std/misc/list
    flatten unique snoc
    take drop
    every any
    filter-map
    group-by
    zip

    ;; std/misc/alist
    agetq agetv aget
    asetq! asetv! aset!
    pgetq pgetv pget
    alist->hash-table

    ;; std/misc/ports
    read-all-as-string read-all-as-lines
    read-file-string read-file-lines
    write-file-string
    with-input-from-string with-output-to-string

    ;; ---- Safe APIs under STANDARD names ----

    ;; SQLite (safe wrappers, renamed to standard names)
    sqlite-open sqlite-close sqlite-exec sqlite-execute sqlite-query
    sqlite-prepare sqlite-finalize sqlite-step sqlite-bind

    ;; TCP (safe wrappers, renamed to standard names)
    tcp-connect tcp-listen tcp-accept tcp-close
    tcp-read tcp-write tcp-write-string

    ;; File I/O (safe wrappers, renamed to standard names)
    open-safe-input-file open-safe-output-file
    call-with-safe-input-file call-with-safe-output-file

    ;; Resource management
    with-resource with-resource1
    register-resource-cleanup!
    call-with-resource

    ;; Error conditions (full hierarchy)
    &jerboa jerboa-condition? jerboa-condition-subsystem
    db-error? network-error? timeout-error? parse-error? resource-error?
    db-connection-error? db-query-error? db-constraint-violation?
    connection-refused? connection-timeout?
    resource-leak? resource-already-closed? resource-exhausted?

    ;; Timeout
    with-timeout *default-timeout*

    ;; Safe FASL
    safe-fasl-write safe-fasl-read
    safe-fasl-write-bytevector safe-fasl-read-bytevector
    register-safe-record-type! unregister-safe-record-type!
    *fasl-allow-procedures* *fasl-max-object-count* *fasl-max-byte-size*

    ;; Safe mode control
    *safe-mode*)

  (import
    (except (chezscheme)
            make-hash-table hash-table?
            sort sort!
            printf fprintf
            path-extension path-absolute?
            with-input-from-string with-output-to-string
            iota 1+ 1-)
    (jerboa core)
    ;; No (jerboa ffi) — raw FFI is intentionally excluded
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
    (std misc ports)
    ;; Safety modules
    (prefix (std safe) safe:)
    (std resource)
    (std error conditions)
    (std safe-timeout)
    (std safe-fasl))

  ;; =========================================================================
  ;; Re-export safe APIs under standard names
  ;; =========================================================================

  ;; SQLite
  (define sqlite-open       safe:safe-sqlite-open)
  (define sqlite-close      safe:safe-sqlite-close)
  (define sqlite-exec       safe:safe-sqlite-exec)
  (define sqlite-execute    safe:safe-sqlite-execute)
  (define sqlite-query      safe:safe-sqlite-query)
  (define sqlite-prepare    safe:safe-sqlite-prepare)
  (define sqlite-finalize   safe:safe-sqlite-finalize)
  (define sqlite-step       safe:safe-sqlite-step)
  (define sqlite-bind       safe:safe-sqlite-bind)

  ;; TCP
  (define tcp-connect       safe:safe-tcp-connect)
  (define tcp-listen        safe:safe-tcp-listen)
  (define tcp-accept        safe:safe-tcp-accept)
  (define tcp-close         safe:safe-tcp-close)
  (define tcp-read          safe:safe-tcp-read)
  (define tcp-write         safe:safe-tcp-write)
  (define tcp-write-string  safe:safe-tcp-write-string)

  ;; File I/O
  (define open-safe-input-file   safe:safe-open-input-file)
  (define open-safe-output-file  safe:safe-open-output-file)
  (define call-with-safe-input-file  safe:safe-call-with-input-file)
  (define call-with-safe-output-file safe:safe-call-with-output-file)

  ;; Mode control
  (define *safe-mode*       safe:*safe-mode*)

) ;; end library
