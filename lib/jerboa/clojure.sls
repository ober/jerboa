#!chezscheme
;;; (jerboa clojure) — Single-import Clojure experience
;;;
;;; (import (jerboa clojure)) gives you the ENTIRE Jerboa API plus
;;; every Clojure-compatibility module:
;;;
;;;   - The full (jerboa prelude) — macros, runtime, iterators, etc.
;;;   - (std clojure) — polymorphic collections, persistent data, atoms,
;;;     lazy seqs, loop/recur, destructuring, dynamic vars, etc.
;;;   - (std datafy) — datafy/nav protocols
;;;   - (std logic) — miniKanren (core.logic)
;;;   - (std spec) — composable validation (clojure.spec)
;;;   - (std transit) — Transit wire format
;;;   - (std clojure seq) — unified seq-* operations
;;;   - (std clojure string) — clojure.string (prefixed str/)
;;;   - (std clojure reducers) — parallel reducers
;;;
;;; Conflict resolution: when the prelude and (std clojure) export the
;;; same name, the (std clojure) version wins (it re-exports from the
;;; same underlying modules, so semantics are identical).

(library (jerboa clojure)
  (export
    ;; ================================================================
    ;; (jerboa prelude) — everything EXCEPT names also in (std clojure)
    ;; ================================================================

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

    ;; ---- std/misc/func (only names NOT in (std clojure)) ----
    compose compose1 identity constantly flip
    curry curryn negate conjoin disjoin
    memo-proc juxt
    partial complement comp

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

    ;; ---- std/misc/shared ----
    make-shared shared? shared-ref shared-set!
    shared-update! shared-cas! shared-swap!

    ;; ---- AI compatibility aliases ----
    hash-has-key? hash-table-set!
    directory-exists?
    eql?
    random-integer
    read-line
    force-output
    string-map
    regex-match regex-search regex-replace regex-replace-all

    ;; ---- Clojure reader mode ----
    ;; reader-cloj-mode: parameter — (reader-cloj-mode #t) activates Clojure syntax
    ;; fn-literal: macro — expands #(...) anonymous function literals
    ;; activate-cloj-reader!: procedure — convenience wrapper to enable cloj mode
    reader-cloj-mode
    fn-literal
    activate-cloj-reader!

    ;; ================================================================
    ;; (std clojure) — Clojure compatibility layer (wins on conflicts)
    ;; ================================================================

    ;; ---- Polymorphic collection ops ----
    get assoc dissoc contains? count keys vals
    merge merge-with update select-keys
    zipmap reduce-kv min-key max-key
    first rest next last
    conj cons* empty?
    peek pop
    reduce into range
    seq =? hash
    inc dec
    nil? some? true? false?

    ;; ---- Functional combinators (re-exports + Clojure additions) ----
    memoize iterate repeatedly fnil
    every-pred some-fn

    ;; ---- Sugar macros ----
    doto
    loop recur
    require

    ;; ---- Destructuring (Clojure-style) ----
    dlet dfn

    ;; ---- Dynamic vars (Clojure-style binding) ----
    def-dynamic binding
    bound-fn capture-dynamic-bindings apply-dynamic-bindings

    ;; ---- Structured exceptions (ex-info / ex-data) ----
    ex-info ex-info? ex-data ex-message ex-cause

    ;; ---- Transients ----
    transient persistent! transient?
    assoc! dissoc! conj!

    ;; ---- Sets ----
    hash-set set set?
    disj
    union intersection difference subset? superset?
    ;; Set relational ops
    set-select set-project set-rename set-index set-join
    map-invert

    ;; ---- Constructors ----
    hash-map vec list* vector*
    make-hash-set

    ;; ---- Printing ----
    println prn pr pr-str prn-str

    ;; ---- Re-exports from (std immutable) ----
    imap imap? imap-set imap-ref imap-has?
    imap=? imap-hash
    in-imap in-imap-pairs in-imap-keys in-imap-values
    ivec ivec-set ivec-ref ivec-length
    ;; ---- Re-exports from (std pmap) ----
    persistent-map?
    ;; ---- Re-exports from (std pset) ----
    persistent-set persistent-set?
    persistent-set-contains? persistent-set->list
    persistent-set-hash in-pset

    ;; ---- Re-exports from (std misc atom) ----
    atom atom? reset! swap! compare-and-set!
    add-watch! remove-watch!
    volatile! volatile? vreset! vswap! vderef

    ;; ---- Delay / Future / Promise ----
    clj-delay delay? clj-force
    clj-future future? future-cancel future-cancelled? future-done?
    clj-promise promise? deliver
    deref

    ;; ---- Re-exports from (std misc meta) ----
    with-meta meta vary-meta meta-wrapped? strip-meta

    ;; ---- Re-exports from (std misc nested) ----
    get-in assoc-in update-in

    ;; ---- Re-exports from (std pqueue) ----
    persistent-queue pqueue-empty pqueue?
    pqueue-conj pqueue-peek pqueue-pop
    pqueue-count pqueue->list
    pqueue-empty? list->pqueue

    ;; ---- Re-exports from (std sorted-set) ----
    sorted-set sorted-set-by sorted-set?
    sorted-set-empty
    sorted-set-add sorted-set-remove
    sorted-set-contains? sorted-set-size
    sorted-set-min sorted-set-max
    sorted-set-range sorted-set->list
    sorted-set-fold

    ;; ---- Lazy sequences ----
    lazy-cons lazy-first lazy-rest lazy-nil lazy-nil? lazy-seq? lazy-force
    lazy-map lazy-filter lazy-take lazy-drop lazy-take-while lazy-drop-while
    lazy-zip lazy-append lazy-flatten lazy-range lazy-iterate lazy-repeat
    lazy-cycle lazy->list list->lazy lazy-for-each lazy-fold lazy-count
    lazy-any? lazy-all? lazy-nth lazy-concat lazy-interleave lazy-mapcat
    lazy-interpose lazy-realize lazy-realized? lazy-partition lazy-chunk
    ;; Clojure-named wrappers
    cycle repeat doall dorun realized?

    ;; ---- Prelude extras not in (std clojure) ----
    ;; assoc-in! and update-in! are mutable variants from prelude's
    ;; (std misc nested) re-export that (std clojure) does not provide.
    assoc-in! update-in!
    nested-get nested-empty-like

    ;; ================================================================
    ;; (std datafy) — datafy/nav protocols
    ;; ================================================================
    Datafiable Navigable
    datafy nav

    ;; ================================================================
    ;; (std logic) — miniKanren core.logic
    ;; ================================================================
    == run run* fresh conde conda condu
    succeed fail
    conso caro cdro nullo pairo
    appendo membero
    absento
    lvar lvar? reify

    ;; ================================================================
    ;; (std spec) — composable validation
    ;; ================================================================
    s-def s-get-spec
    s-pred s-and s-or s-keys s-keys-opt
    s-cat s-coll-of s-map-of
    s-nilable s-tuple s-enum
    s-int-in s-double-in
    s-valid? s-conform s-explain s-explain-str s-assert
    s-fdef s-check-fn
    s-exercise

    ;; ================================================================
    ;; (std transit) — Transit wire format
    ;; ================================================================
    transit-write transit-read
    transit->string string->transit
    transit-encode transit-decode
    transit-keyword transit-keyword?
    transit-symbol transit-symbol?
    transit-uuid transit-uuid?
    transit-instant transit-instant?
    transit-uri transit-uri?

    ;; ================================================================
    ;; (std clojure seq) — unified seq-* operations
    ;; ================================================================
    seqable? seq->list
    seq-map seq-filter seq-remove
    seq-take seq-drop seq-take-while seq-drop-while
    seq-reduce seq-some seq-every?
    seq-sort seq-sort-by
    seq-distinct seq-flatten
    seq-partition seq-partition-by seq-partition-all
    seq-group-by seq-frequencies
    seq-interpose seq-interleave
    seq-mapcat seq-keep
    seq-map-indexed
    seq-concat
    seq-into
    seq-count seq-empty?
    seq-nth seq-first seq-rest
    seq-second seq-last
    seq-butlast
    seq-reverse
    seq-zip seq-zipmap

    ;; ================================================================
    ;; (std clojure string) — clojure.string (prefixed str/)
    ;; ================================================================
    str/blank?
    str/capitalize
    str/ends-with?
    str/escape
    str/includes?
    str/clj-index-of
    str/join
    str/lower-case
    str/upper-case
    str/replace
    str/replace-first
    str/re-quote-replacement
    str/reverse
    str/split
    str/split-lines
    str/starts-with?
    str/trim
    str/trim-newline
    str/triml
    str/trimr

    ;; ================================================================
    ;; (std clojure reducers) — parallel reducers
    ;; ================================================================
    r-fold r-map r-filter r-remove
    r-take r-drop r-take-while
    r-mapcat r-flatten
    r-foldcat
    r-reduce)

  (import
    ;; The full prelude, EXCEPT names that (std clojure) also exports.
    ;; (std clojure) re-exports from the same underlying modules, so
    ;; semantics are identical — we just avoid R6RS duplicate-import errors.
    (except (jerboa prelude)
      ;; hash-map, hash-set — re-exported by (std clojure) as Clojure constructors
      hash-map hash-set
      ;; atom / volatile / watches — re-exported by (std clojure)
      atom atom? reset! swap! compare-and-set!
      add-watch! remove-watch!
      volatile! volatile? vreset! vswap! vderef
      deref
      ;; meta — re-exported by (std clojure)
      with-meta meta vary-meta meta-wrapped? strip-meta
      ;; nested access — re-exported by (std clojure)
      get-in assoc-in update-in
      ;; func combinators — re-exported by (std clojure)
      fnil every-pred some-fn)

    ;; Clojure reader mode + fn-literal macro (in its own bootstrap file)
    (jerboa cloj)

    ;; Clojure compatibility — wins on all conflicts
    (std clojure)

    ;; Additional Clojure-ecosystem modules
    (std datafy)
    (std logic)
    (std spec)
    (std transit)
    (std clojure seq)
    (prefix (std clojure string) str/)
    (std clojure reducers))

  ;;;; Activate Clojure reader mode for programmatic use
  ;; (e.g. REPL sessions, load-file calls).
  ;; Files that use Clojure syntax should also start with  #!cloj  so the
  ;; reader is in cloj mode before parsing the  (import (jerboa clojure))  form.
  (activate-cloj-reader!)

  )
