#!chezscheme
;;; (std prelude) — One import for everything
;;;
;;; (import (std prelude)) gives you the full jerboa API plus
;;; all new libraries (result, datetime, threading, etc.)
;;; with all Chez Scheme conflicts pre-resolved.

(library (std prelude)
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
    -> ->> as-> some-> some->> cond-> cond->>
    ->? ->>?
    awhen aif when-let if-let
    cut cute <> <...>
    dotimes
    with-resource
    str
    alist
    defn
    defrecord
    let-alist
    define-enum
    capture

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

    ;; ---- Timing helpers ----
    sleep-ms)

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
    ;; Private access to Chez's make-time (shadowed above) so we can
    ;; build a time-duration record for the sleep-ms wrapper.
    (rename (only (chezscheme) make-time)
            (make-time %chez-make-time))
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
    (std misc string)
    (std misc list)
    (std misc alist)
    (std misc ports)
    (std misc func)
    (std iter)
    (std result)
    (std datetime)
    (std debug pp)
    (std csv))

  ;; ---- Timing helpers ----
  ;; (sleep-ms ms) sleeps for MS milliseconds. Wraps Chez's
  ;; `(sleep (make-time 'time-duration ns sec))` so users never have
  ;; to reach for `make-time` (which the prelude shadows with a
  ;; date-style constructor). MS must be a non-negative integer.
  (define (sleep-ms ms)
    (unless (and (integer? ms) (>= ms 0))
      (error 'sleep-ms "ms must be a non-negative integer" ms))
    (let ([sec (quotient ms 1000)]
          [ns  (* (remainder ms 1000) 1000000)])
      (sleep (%chez-make-time 'time-duration ns sec))))

  ) ;; end library
