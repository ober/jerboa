#!chezscheme
;;; jerboa/prelude -- One-import-to-rule-them-all
;;;
;;; (import (jerboa prelude)) gives you the full Jerboa API:
;;; - Core macros: def, defstruct, defmethod, match, try/catch, etc.
;;; - Runtime: hash tables, method dispatch, keywords
;;; - Standard library: sort, format, JSON, paths, strings, lists, etc.
;;; - Advanced: result types, datetime, iterators, CSV, pretty-printer
;;; - Ergonomic typing: using, :, maybe
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
    unwind-protect with-id with-lock with-catch
    cut cute <> <...>
    awhen aif when-let if-let
    -> ->> as-> some-> some->> cond-> cond->>
    ->? ->>?
    with-resource str alist defn defrecord
    let-alist define-enum capture dotimes define-values

    ;; ---- std/text/json ----
    read-json write-json json-object->string string->json-object

    ;; ---- std/os/path ----
    path-expand path-normalize path-directory path-strip-directory
    path-extension path-strip-extension
    path-join path-absolute?

    ;; ---- std/regex ----
    re re?
    re-match? re-search
    re-find-all re-groups
    re-replace re-replace-all
    re-split re-fold
    re-match-full re-match-group re-match-groups
    re-match-start re-match-end re-match-named

    ;; ---- std/rx ----
    rx define-rx

    ;; ---- std/misc/string ----
    string-split string-join string-trim
    string-prefix? string-suffix?
    string-contains string-index
    string-empty?
    string-match? string-find string-find-all

    ;; ---- std/misc/list ----
    flatten unique snoc
    take drop
    every any
    filter-map
    group-by
    zip
    frequencies
    partition partition-all partition-by
    interleave interpose
    mapcat
    distinct
    keep
    some
    iterate-n
    reductions
    take-last drop-last
    split-at split-with
    ;; Gerbil v0.19 compat
    append-map append1 flatten1
    push! pop!
    for-each!
    take-while take-until drop-while drop-until
    butlast slice split
    length=? length<? length<=? length>? length>=?
    length=n? length<n? length<=n? length>n? length>=n?
    group-consecutive group-n-consecutive group-same
    rassoc every-consecutive?
    map/car first-and-only when/list
    with-list-builder call-with-list-builder
    duplicates delete-duplicates/hash

    ;; ---- std/misc/alist ----
    agetq agetv aget
    asetq! asetv! aset!
    pgetq pgetv pget
    alist->hash-table
    ;; Gerbil v0.19 compat
    alist? acons
    asetq asetv aset
    aremq aremv arem
    aremq! aremv! arem!
    psetq psetv pset
    psetq! psetv! pset!
    premq premv prem
    premq! premv! prem!
    plist->alist* alist->plist*

    ;; ---- std/misc/ports ----
    read-all-as-string read-all-as-lines
    read-file-string read-file-lines
    write-file-string
    with-input-from-string with-output-to-string

    ;; ---- std/misc/func ----
    compose compose1 identity constantly flip
    curry curryn negate conjoin disjoin
    memo-proc juxt
    partial complement comp
    fnil every-pred some-fn

    ;; ---- std/iter ----
    for for/collect for/fold for/or for/and
    in-list in-vector in-range in-string
    in-hash-keys in-hash-values in-hash-pairs
    in-naturals in-indexed
    in-port in-lines in-chars in-bytes in-producer

    ;; ---- std/result ----
    ok err
    ok? err? result?
    unwrap unwrap-err unwrap-or unwrap-or-else
    map-ok map-err
    and-then or-else
    flatten-result
    result->values
    try-result try-result*
    result->option
    results-partition
    map-results
    filter-ok filter-err
    sequence-results
    ok->list err->list

    ;; ---- std/datetime ----
    make-datetime datetime?
    make-date make-time
    datetime-now datetime-utc-now
    datetime-year datetime-month datetime-day
    datetime-hour datetime-minute datetime-second
    datetime-nanosecond datetime-offset
    parse-datetime parse-date parse-time
    datetime->string date->string time->string
    datetime->iso8601
    datetime->epoch epoch->datetime
    datetime->julian julian->datetime
    datetime-add datetime-subtract
    datetime-diff
    duration duration? duration-seconds duration-nanoseconds
    make-duration
    datetime<? datetime>? datetime=? datetime<=? datetime>=?
    datetime-min datetime-max datetime-clamp
    day-of-week day-of-year days-in-month leap-year?
    datetime->alist
    datetime-truncate
    datetime-floor-hour datetime-floor-day datetime-floor-month

    ;; ---- std/debug/pp ----
    pp pp-to-string pprint
    ppd ppd-to-string

    ;; ---- std/csv ----
    read-csv read-csv-file csv-port->rows
    write-csv write-csv-file rows->csv-string
    csv->alists alists->csv

    ;; ---- FFI ----
    c-lambda define-c-lambda
    begin-ffi c-declare

    ;; ---- std/ergo ----
    using : maybe list-of?

    ;; ---- AI compatibility aliases ----
    ;; Common names LLMs hallucinate from Racket/Gerbil/Gambit/CL training data.
    ;; These are thin aliases so AI-generated code works on the first try.
    hash-has-key? hash-table-set!        ;; Racket
    directory-exists?                     ;; Gambit
    eql?                                 ;; Common Lisp
    random-integer                       ;; Gambit
    read-line                            ;; Gambit
    force-output                         ;; Gambit
    string-map                           ;; Racket/R7RS
    ;; Regex aliases (common generic names from Python, Ruby, JS training data)
    regex-match regex-search regex-replace regex-replace-all)

  (import
    (except (chezscheme)
            make-hash-table hash-table?
            sort sort!
            printf fprintf
            path-extension path-absolute?
            with-input-from-string with-output-to-string
            iota 1+ 1-
            partition
            make-date make-time)
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
    (except (std sugar) try catch finally)
    (std text json)
    (std os path)
    (std regex)
    (std rx)
    (std misc string)
    (std misc list)
    (std misc alist)
    (std misc ports)
    (std misc func)
    (std iter)
    (std result)
    (std datetime)
    (std debug pp)
    (std csv)
    (std ergo))

  ;; ---- AI compatibility aliases ----
  (define hash-has-key? hash-key?)
  (define hash-table-set! hash-put!)
  (define directory-exists? file-directory?)
  (define eql? eqv?)
  (define random-integer random)
  (define (read-line . args)
    (if (null? args)
        (get-line (current-input-port))
        (get-line (car args))))
  (define (force-output . args)
    (flush-output-port
      (if (null? args) (current-output-port) (car args))))
  (define (string-map f s)
    (list->string (map f (string->list s))))

  ;; ---- Regex AI compatibility aliases ----
  ;; LLMs trained on Python/Ruby/JavaScript commonly use these generic names.
  (define (regex-match pat str)       (re-search pat str))
  (define (regex-search pat str)      (re-search pat str))
  (define (regex-replace pat str rep) (re-replace pat str rep))
  (define (regex-replace-all pat str rep) (re-replace-all pat str rep))

  ) ;; end library
