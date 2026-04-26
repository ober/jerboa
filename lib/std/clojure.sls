#!chezscheme
;;; (std clojure) — Clojure compatibility module
;;;
;;; Gives Clojure developers a single import that covers the most
;;; commonly used Clojure core names, mapped onto Jerboa's existing
;;; functionality. Most entries are thin aliases; a few are small
;;; polymorphic wrappers (get/assoc/dissoc/contains?/count/merge/...)
;;; that dispatch across imap, concurrent-hash, hash-table, and list.
;;;
;;; Usage:
;;;   (import (jerboa prelude)
;;;           (std clojure))
;;;
;;;   (def m (hash-map "a" 1 "b" 2))        ;; like Clojure's {:a 1 :b 2}
;;;   (get m "a")                            ;; => 1
;;;   (assoc m "c" 3)                        ;; new map with c=3
;;;   (dissoc m "a")                         ;; without a
;;;   (contains? m "a")                      ;; => #t
;;;   (count m)                              ;; => 2
;;;   (keys m) (vals m)                      ;; map entries
;;;   (merge m (hash-map "d" 4))             ;; combine
;;;
;;;   (def a (atom 0))                       ;; already in prelude
;;;   (swap! a inc)                          ;; inc is in here → 1
;;;
;;;   (reduce + 0 (range 5))                 ;; => 10
;;;   (filter even? (range 10))              ;; => (0 2 4 6 8)
;;;   (map inc [1 2 3])                      ;; vectors become lists
;;;
;;; Name conflicts:
;;;   `hash-map` is shadowed — Jerboa has (hash-map f ht) (Racket-style
;;;     mapping). In (std clojure), hash-map is a CONSTRUCTOR like
;;;     Clojure's {:k v}. If you need the Racket mapping, use hash-map/f
;;;     or import (std misc hash-more) directly.
;;;   `assoc` is shadowed — Chez's assoc does alist lookup; Clojure's
;;;     assoc updates. Import both only with rename if you need both.

(library (std clojure)
  (export
    ;; ---- Polymorphic collection ops (new in this module) ----
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

    ;; ---- Transients (Clojure-style polymorphic dispatch) ----
    transient persistent! transient?
    assoc! dissoc! conj!

    ;; ---- Sets ----
    hash-set set set?
    disj
    union intersection difference subset? superset?
    ;; ---- Set relational ops (clojure.set) ----
    set-select set-project set-rename set-index set-join
    map-invert

    ;; ---- Constructors (aliases) ----
    hash-map vec list* vector*
    make-hash-set
    ;; The prelude's mutable hash-table can still be constructed
    ;; with make-hash-table.

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

    ;; ---- Delay / Future / Promise (Clojure-style) ----
    clj-delay delay? clj-force
    clj-future future? future-cancel future-cancelled? future-done?
    clj-promise promise? deliver
    deref

    ;; ---- Anonymous protocol implementation ----
    reify

    ;; ---- Clojure 1.11+ conveniences ----
    parse-long parse-double parse-boolean parse-uuid
    random-uuid
    update-vals update-keys
    map-indexed keep-indexed
    if-some when-some
    condp letfn case-let
    NaN? abs iteration not-empty

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

    ;; ---- Lazy sequences (re-exports from (std seq)) ----
    lazy-cons lazy-first lazy-rest lazy-nil lazy-nil? lazy-seq? lazy-force
    lazy-map lazy-filter lazy-take lazy-drop lazy-take-while lazy-drop-while
    lazy-zip lazy-append lazy-flatten lazy-range lazy-iterate lazy-repeat
    lazy-cycle lazy->list list->lazy lazy-for-each lazy-fold lazy-count
    lazy-any? lazy-all? lazy-nth lazy-concat lazy-interleave lazy-mapcat
    lazy-interpose lazy-realize lazy-realized? lazy-partition lazy-chunk
    ;; Clojure-named wrappers
    cycle repeat doall dorun realized?)

  (import (except (chezscheme)
                  make-hash-table hash-table?
                  assoc iota 1+ 1-
                  atom?
                  merge merge!
                  list*
                  meta)
          (except (jerboa runtime) cons* hash-map hash-set)
          (std pmap)
          (std immutable)
          (rename (std pvec)
                  (transient  pvec-transient)
                  (transient? pvec-transient?)
                  (persistent! pvec-persistent!)
                  (transient-set!    pvec-t-set!)
                  (transient-ref     pvec-t-ref)
                  (transient-append! pvec-t-append!))
          (rename (std pset)
                  (persistent-set!    pset-persistent!))
          (std concur hash)
          (except (std misc atom) deref)
          (std misc meta)
          (std misc nested)
          (only (std misc func) fnil every-pred some-fn)
          (rename (only (std misc memoize) memoize) (memoize clj-memoize))
          (only (std misc list) iterate-n)
          (std pqueue)
          (std sorted-set)
          (only (std protocol) reify)
          (except (std seq) into sequence transduce
                  ;; Exclude transducer + parallel collection exports
                  ;; that clash or aren't needed here
                  map-xf filter-xf take-xf drop-xf take-while-xf
                  drop-while-xf flat-map-xf dedupe-xf compose-xf
                  par-map par-filter par-reduce par-for-each))

  ;; =========================================================================
  ;; Record-as-map helpers (§4.10)
  ;;
  ;; Clojure's defrecord instances are *also* persistent maps — you can
  ;; (get p :x), (keys p), etc. We extend Jerboa's polymorphic ops to
  ;; the same on plain records (defstruct / define-record-type) by
  ;; walking the rtd with `record-type-field-names` + `record-accessor`.
  ;;
  ;; The write side (assoc/dissoc on records) falls back to returning
  ;; a persistent-map containing all the record's fields plus the new
  ;; binding, matching Clojure's "escape to regular map" behaviour when
  ;; you assoc an unknown key. For known keys we also return a pmap
  ;; rather than trying to reconstruct the record — Chez doesn't
  ;; provide a uniform way to rebuild sealed records given only an
  ;; instance, so this keeps the implementation simple and uniform
  ;; at the cost of losing type information after assoc.
  ;; =========================================================================

  ;; Normalize a user-provided record key to a symbol. Accepts
  ;; symbol, string, or keyword. Returns #f for anything else.
  (define (%record-key->symbol k)
    (cond
      [(symbol? k) k]
      [(string? k) (string->symbol k)]
      [(keyword? k) (string->symbol (keyword->string k))]
      [else #f]))

  ;; Collect (field-name . accessor) pairs for a record instance,
  ;; walking the parent chain so inherited fields are included in
  ;; declaration order (parent first, child fields appended).
  ;; Returns a fresh list each call; cache in a caller if hot.
  (define (%record-fields-all rec)
    (let ([rtd (record-rtd rec)])
      ;; `walk` receives the tail-so-far and prepends this rtd's fields
      ;; (in reverse index order) to it. By walking the chain leaf-to-
      ;; root and feeding each result as the tail, we end up with
      ;; root-to-leaf declaration order overall.
      (define (walk-rtd r tail)
        (let* ([names (record-type-field-names r)]
               [n (vector-length names)])
          (let lp ([i (- n 1)] [out tail])
            (if (< i 0)
                out
                (lp (- i 1)
                      (cons (cons (vector-ref names i)
                                  (record-accessor r i))
                            out))))))
      (let walk ([r rtd] [tail '()])
        (cond
          [(not r) tail]
          [else
           (walk (record-type-parent r)
                 (walk-rtd r tail))]))))

  ;; Find a record's field-value by name (walking parent chain).
  ;; Returns default if not found.
  (define (%record-ref rec key default)
    (let ([name (%record-key->symbol key)])
      (cond
        [(not name) default]
        [else
         (let walk ([r (record-rtd rec)])
           (cond
             [(not r) default]
             [else
              (let* ([names (record-type-field-names r)]
                     [n (vector-length names)])
                (let lp ([i 0])
                  (cond
                    [(= i n) (walk (record-type-parent r))]
                    [(eq? (vector-ref names i) name)
                     ((record-accessor r i) rec)]
                    [else (lp (+ i 1))])))]))])))

  ;; Check whether a record has a field with the given name.
  (define (%record-has-field? rec key)
    (let ([name (%record-key->symbol key)])
      (and name
           (let walk ([r (record-rtd rec)])
             (cond
               [(not r) #f]
               [else
                (let* ([names (record-type-field-names r)]
                       [n (vector-length names)])
                  (let lp ([i 0])
                    (cond
                      [(= i n) (walk (record-type-parent r))]
                      [(eq? (vector-ref names i) name) #t]
                      [else (lp (+ i 1))])))])))))

  ;; Ordered list of a record's field name symbols (parent first).
  (define (%record-keys rec)
    (map car (%record-fields-all rec)))

  ;; Ordered list of a record's field values (parent first).
  (define (%record-vals rec)
    (map (lambda (pair) ((cdr pair) rec))
         (%record-fields-all rec)))

  ;; Escape a record to a persistent-map with its field bindings.
  ;; Called by assoc/dissoc when they need to produce an updated
  ;; collection but reconstructing the record is impractical.
  ;; Field name symbols become the map keys; values become the
  ;; map values. Inherited fields are included.
  (define (%record->pmap rec)
    (let lp ([fields (%record-fields-all rec)] [m pmap-empty])
      (if (null? fields)
          m
          (let ([pair (car fields)])
            (lp (cdr fields)
                  (persistent-map-set m (car pair) ((cdr pair) rec)))))))

  ;; =========================================================================
  ;; Numerics
  ;; =========================================================================
  (define (inc n) (+ n 1))
  (define (dec n) (- n 1))

  ;; =========================================================================
  ;; Predicates
  ;; =========================================================================

  ;; Clojure's nil? — in Jerboa, nil ~= #f
  (define (nil? x) (eq? x #f))

  ;; Clojure's some? — anything that is not nil (#f)
  (define (some? x) (not (eq? x #f)))

  (define (true? x) (eq? x #t))
  (define (false? x) (eq? x #f))

  (define (empty? coll)
    (cond
      [(null? coll) #t]
      [(pair? coll) #f]
      [(persistent-map? coll) (zero? (persistent-map-size coll))]
      [(persistent-set? coll) (zero? (persistent-set-size coll))]
      [(sorted-set? coll) (zero? (sorted-set-size coll))]
      [(concurrent-hash? coll) (zero? (concurrent-hash-size coll))]
      [(hash-table? coll) (zero? (hash-length coll))]
      [(vector? coll) (zero? (vector-length coll))]
      [(string? coll) (zero? (string-length coll))]
      ;; Plain record — empty iff no fields (including inherited).
      [(record? coll) (null? (%record-fields-all coll))]
      [else (error 'empty? "unsupported collection type" coll)]))

  ;; =========================================================================
  ;; Count
  ;; =========================================================================

  (define (count coll)
    (cond
      [(null? coll) 0]
      [(pair? coll) (length coll)]
      [(persistent-map? coll) (persistent-map-size coll)]
      [(persistent-set? coll) (persistent-set-size coll)]
      [(sorted-set? coll) (sorted-set-size coll)]
      [(concurrent-hash? coll) (concurrent-hash-size coll)]
      [(hash-table? coll) (hash-length coll)]
      [(vector? coll) (vector-length coll)]
      [(string? coll) (string-length coll)]
      ;; Plain record — number of fields including inherited ones.
      [(record? coll) (length (%record-fields-all coll))]
      [else (error 'count "unsupported collection type" coll)]))

  ;; =========================================================================
  ;; Polymorphic single-level get
  ;; =========================================================================

  (define get
    (case-lambda
      [(coll key) (get coll key #f)]
      [(coll key default)
       (cond
         ;; Sets: membership check — return `key` if present
         [(persistent-set? coll)
          (if (persistent-set-contains? coll key) key default)]
         [(sorted-set? coll)
          (if (sorted-set-contains? coll key) key default)]
         ;; Record — check nested-get first (handles containers), then
         ;; fall through to record-field lookup. `record?` is checked
         ;; AFTER the type-specific branches in nested-get so it only
         ;; catches user-defined records.
         [(and (record? coll)
               (not (persistent-map? coll))
               (not (persistent-set? coll))
               (not (sorted-set? coll))
               (not (concurrent-hash? coll)))
          (%record-ref coll key default)]
         [else (nested-get coll key default)])]))

  (define (contains? coll key)
    (cond
      [(persistent-map? coll) (persistent-map-has? coll key)]
      [(persistent-set? coll) (persistent-set-contains? coll key)]
      [(sorted-set? coll) (sorted-set-contains? coll key)]
      [(concurrent-hash? coll) (concurrent-hash-key? coll key)]
      [(hash-table? coll) (hash-key? coll key)]
      [(vector? coll)
       (and (integer? key) (exact? key) (>= key 0)
            (< key (vector-length coll)))]
      [(pair? coll) (and (assq key coll) #t)]
      ;; Plain user record — check if field exists.
      [(record? coll) (%record-has-field? coll key)]
      [else #f]))

  ;; =========================================================================
  ;; Polymorphic assoc / dissoc / update
  ;;
  ;; For immutable containers (imap/pmap): returns new container.
  ;; For mutable (chash/hash): mutates and returns same container.
  ;; This matches Clojure's expectation that the return value is
  ;; the "current" state of the data structure, so you can thread it.
  ;; =========================================================================

  (define (assoc coll key val . more)
    (cond
      [(persistent-map? coll)
       (let lp ([m (persistent-map-set coll key val)] [rest more])
         (cond
           [(null? rest) m]
           [(null? (cdr rest))
            (error 'assoc "odd number of key/value arguments" more)]
           [else
            (lp (persistent-map-set m (car rest) (cadr rest))
                  (cddr rest))]))]
      [(concurrent-hash? coll)
       (concurrent-hash-put! coll key val)
       (let lp ([rest more])
         (cond
           [(null? rest) coll]
           [(null? (cdr rest))
            (error 'assoc "odd number of key/value arguments" more)]
           [else
            (concurrent-hash-put! coll (car rest) (cadr rest))
            (lp (cddr rest))]))]
      [(hash-table? coll)
       (hash-put! coll key val)
       (let lp ([rest more])
         (cond
           [(null? rest) coll]
           [(null? (cdr rest))
            (error 'assoc "odd number of key/value arguments" more)]
           [else
            (hash-put! coll (car rest) (cadr rest))
            (lp (cddr rest))]))]
      ;; Plain user record — escape to a persistent map containing
      ;; all the record's fields plus the new bindings. This loses
      ;; the record type information but matches Clojure's documented
      ;; behaviour when you assoc a key a record doesn't support.
      ;; Known-key assoc could theoretically rebuild the record, but
      ;; Chez doesn't expose a uniform constructor-from-rtd, so we
      ;; use the pmap escape uniformly. Use per-record struct updates
      ;; (e.g. defstruct's setters) if you need to preserve type.
      [(record? coll)
       (apply assoc (%record->pmap coll) key val more)]
      [else (error 'assoc "unsupported collection type" coll)]))

  (define (dissoc coll . ks)
    (cond
      [(persistent-map? coll)
       (let lp ([m coll] [rest ks])
         (if (null? rest)
             m
             (lp (persistent-map-delete m (car rest)) (cdr rest))))]
      [(concurrent-hash? coll)
       (for-each (lambda (k) (concurrent-hash-remove! coll k)) ks)
       coll]
      [(hash-table? coll)
       (for-each (lambda (k) (hash-remove! coll k)) ks)
       coll]
      ;; Plain user record — escape to pmap and dissoc from there.
      ;; You can't actually remove a field from a record (it's part
      ;; of the type), so we return a pmap with the field omitted.
      [(record? coll)
       (apply dissoc (%record->pmap coll) ks)]
      [else (error 'dissoc "unsupported collection type" coll)]))

  (define update
    ;; (update m k f args...) → (f (get m k) args...)
    (case-lambda
      [(coll key f)
       (update* coll key f '())]
      [(coll key f . args)
       (update* coll key f args)]))

  (define (update* coll key f args)
    (let ([old (get coll key #f)])
      (assoc coll key (apply f old args))))

  (define (select-keys coll ks)
    ;; Return a new map containing only the given keys
    (cond
      [(persistent-map? coll)
       (let lp ([m pmap-empty] [rest ks])
         (if (null? rest)
             m
             (let ([k (car rest)])
               (if (persistent-map-has? coll k)
                   (lp (persistent-map-set m k (persistent-map-ref coll k))
                         (cdr rest))
                   (lp m (cdr rest))))))]
      [else
       ;; Fall back to generic via assoc
       (let lp ([acc (cond [(concurrent-hash? coll) (make-concurrent-hash)]
                             [else (make-hash-table)])]
                  [rest ks])
         (if (null? rest)
             acc
             (let ([k (car rest)])
               (when (contains? coll k)
                 (assoc acc k (get coll k)))
               (lp acc (cdr rest)))))]))

  ;; =========================================================================
  ;; Keys and vals (polymorphic)
  ;; =========================================================================

  (define (keys coll)
    (cond
      [(persistent-map? coll) (persistent-map-keys coll)]
      [(concurrent-hash? coll) (concurrent-hash-keys coll)]
      [(hash-table? coll) (hash-keys coll)]
      ;; Plain record — return field name symbols (parent chain first).
      [(record? coll) (%record-keys coll)]
      [else (error 'keys "unsupported collection type" coll)]))

  (define (vals coll)
    (cond
      [(persistent-map? coll) (persistent-map-values coll)]
      [(concurrent-hash? coll) (concurrent-hash-values coll)]
      [(hash-table? coll) (hash-values coll)]
      ;; Plain record — return field values (same order as keys).
      [(record? coll) (%record-vals coll)]
      [else (error 'vals "unsupported collection type" coll)]))

  ;; =========================================================================
  ;; merge — polymorphic. For imap: persistent-map-merge. For mutable: mutate.
  ;; =========================================================================

  (define (merge . maps)
    (cond
      [(null? maps) #f]                ;; Clojure returns nil for no args
      [(null? (cdr maps)) (car maps)]
      [(persistent-map? (car maps))
       (let lp ([acc (car maps)] [rest (cdr maps)])
         (if (null? rest)
             acc
             (lp (persistent-map-merge acc (car rest)) (cdr rest))))]
      [(concurrent-hash? (car maps))
       (let ([base (car maps)])
         (for-each (lambda (m) (concurrent-hash-merge! base m)) (cdr maps))
         base)]
      [(hash-table? (car maps))
       (let ([base (car maps)])
         (for-each
           (lambda (m)
             (cond
               [(hash-table? m)
                (hash-for-each (lambda (k v) (hash-put! base k v)) m)]
               [(persistent-map? m)
                (persistent-map-for-each
                  (lambda (k v) (hash-put! base k v)) m)]
               [(concurrent-hash? m)
                (concurrent-hash-for-each
                  (lambda (k v) (hash-put! base k v)) m)]))
           (cdr maps))
         base)]
      [else (error 'merge "unsupported collection type" (car maps))]))

  ;; =========================================================================
  ;; Sequence operations (subset needed for core.async cheat sheet)
  ;; =========================================================================

  (define (first coll)
    (cond
      [(null? coll) #f]
      [(pair? coll) (car coll)]
      [(sorted-set? coll) (sorted-set-min coll)]
      [(vector? coll)
       (if (zero? (vector-length coll)) #f (vector-ref coll 0))]
      [(string? coll)
       (if (zero? (string-length coll)) #f (string-ref coll 0))]
      [(ivec? coll)
       (if (zero? (ivec-length coll))
           #f
           (ivec-ref coll 0))]
      [else (error 'first "unsupported collection type" coll)]))

  (define (rest coll)
    (cond
      [(null? coll) '()]
      [(pair? coll) (cdr coll)]
      [(vector? coll)
       (let ([n (vector-length coll)])
         (if (zero? n)
             '()
             (let lp ([i (- n 1)] [acc '()])
               (if (= i 0) acc (lp (- i 1) (cons (vector-ref coll i) acc))))))]
      [else (error 'rest "unsupported collection type" coll)]))

  (define (next coll)
    ;; Like rest, but returns #f (nil) instead of empty sequence
    (let ([r (rest coll)])
      (cond
        [(null? r) #f]
        [(and (vector? r) (zero? (vector-length r))) #f]
        [else r])))

  (define (last coll)
    (cond
      [(null? coll) #f]
      [(pair? coll)
       (let lp ([c coll])
         (if (null? (cdr c)) (car c) (lp (cdr c))))]
      [(sorted-set? coll) (sorted-set-max coll)]
      [(vector? coll)
       (let ([n (vector-length coll)])
         (if (zero? n) #f (vector-ref coll (- n 1))))]
      [else (error 'last "unsupported collection type" coll)]))

  ;; Clojure's conj:
  ;;   - list:   prepend
  ;;   - vector: append (both mutable Chez vectors and persistent vectors)
  ;;   - map:    must be a [k v] pair; assoc
  ;;   - set:    add element
  ;;   - queue:  enqueue at the back
  (define (conj coll . xs)
    (cond
      [(null? coll)
       ;; Empty coll is assumed to be a list — prepend
       (if (null? xs) '() (apply conj (list (car xs)) (cdr xs)))]
      [(pair? coll)
       (let lp ([c coll] [rest xs])
         (if (null? rest) c (lp (cons (car rest) c) (cdr rest))))]
      [(vector? coll)
       ;; Build a new vector
       (list->vector (append (vector->list coll) xs))]
      [(persistent-vector? coll)
       (let lp ([v coll] [rest xs])
         (if (null? rest) v
             (lp (persistent-vector-append v (car rest)) (cdr rest))))]
      [(pqueue? coll)
       ;; NOTE: pqueue? is srfi-134's ideque predicate, which is a
       ;; superset of "queue" — any ideque passed in is treated as a
       ;; queue. This branch must precede the persistent-map? check
       ;; because ideques are records distinct from pmap, but we want
       ;; the polymorphism to be unambiguous.
       (let lp ([q coll] [rest xs])
         (if (null? rest) q
             (lp (pqueue-conj q (car rest)) (cdr rest))))]
      [(persistent-map? coll)
       ;; Expect (k . v) pairs or (list k v)
       (let lp ([m coll] [rest xs])
         (if (null? rest)
             m
             (let ([entry (car rest)])
               (cond
                 [(pair? entry)
                  (lp (persistent-map-set m (car entry)
                           (if (pair? (cdr entry)) (cadr entry) (cdr entry)))
                        (cdr rest))]
                 [else
                  (error 'conj "cannot conj non-pair onto map" entry)]))))]
      [(persistent-set? coll)
       (let lp ([s coll] [rest xs])
         (if (null? rest) s
             (lp (persistent-set-add s (car rest)) (cdr rest))))]
      [(sorted-set? coll)
       (let lp ([s coll] [rest xs])
         (if (null? rest) s
             (lp (sorted-set-add s (car rest)) (cdr rest))))]
      [else (error 'conj "unsupported collection type" coll)]))

  ;; =========================================================================
  ;; peek / pop — Clojure's stack/queue surface
  ;;
  ;; Clojure defines these on "stack-like" collections with type-
  ;; specific ends:
  ;;   - list:              peek = first, pop = rest
  ;;   - persistent-vector: peek = last,  pop = drop-last   (stack end)
  ;;   - persistent-queue:  peek = front, pop = drop-front  (FIFO end)
  ;; Calling either on an empty coll returns nil (#f) for peek and
  ;; raises for pop, mirroring clojure.lang.IPersistentStack.
  ;; =========================================================================

  (define (peek coll)
    (cond
      [(or (eq? coll #f) (null? coll)) #f]
      [(pair? coll) (car coll)]
      [(pqueue? coll) (pqueue-peek coll)]
      [(persistent-vector? coll)
       (let ([n (persistent-vector-length coll)])
         (if (zero? n) #f (persistent-vector-ref coll (- n 1))))]
      [(vector? coll)
       (let ([n (vector-length coll)])
         (if (zero? n) #f (vector-ref coll (- n 1))))]
      [else (error 'peek "unsupported collection type" coll)]))

  (define (pop coll)
    (cond
      [(null? coll) (error 'pop "cannot pop from an empty list")]
      [(pair? coll) (cdr coll)]
      [(pqueue? coll) (pqueue-pop coll)]
      [(persistent-vector? coll)
       (let ([n (persistent-vector-length coll)])
         (cond
           [(zero? n) (error 'pop "cannot pop from an empty vector")]
           [else (persistent-vector-slice coll 0 (- n 1))]))]
      [else (error 'pop "unsupported collection type" coll)]))

  ;; cons* — Chez's built-in cons* has identical semantics to Clojure's list*:
  ;; (cons* 1 2 3 '(4 5)) → (1 2 3 4 5). Re-used below as list*.

  ;; =========================================================================
  ;; reduce — fold-left on various collections
  ;; =========================================================================

  (define reduce
    (case-lambda
      [(f coll)
       (cond
         [(null? coll) (f)]
         [(null? (cdr coll)) (car coll)]
         [(pair? coll) (reduce f (car coll) (cdr coll))]
         [else (error 'reduce "2-arg reduce requires a list" coll)])]
      [(f init coll)
       (cond
         [(null? coll) init]
         [(pair? coll)
          (let lp ([acc init] [c coll])
            (if (null? c) acc (lp (f acc (car c)) (cdr c))))]
         [(vector? coll)
          (let ([n (vector-length coll)])
            (let lp ([acc init] [i 0])
              (if (= i n) acc (lp (f acc (vector-ref coll i)) (+ i 1)))))]
         [(persistent-map? coll)
          (persistent-map-fold (lambda (acc k v) (f acc (cons k v))) init coll)]
         [else (error 'reduce "unsupported collection type" coll)])]))

  (define (range . args)
    ;; (range)             → infinite lazy range from 0
    ;; (range end)         → 0..end-1 (eager list)
    ;; (range start end)   → start..end-1 (eager list)
    ;; (range start end step) (eager list)
    (case (length args)
      [(0) (lazy-range 0 +inf.0 1)]
      [(1)
       (let ([end (car args)])
         (let lp ([i 0] [acc '()])
           (if (>= i end) (reverse acc) (lp (+ i 1) (cons i acc)))))]
      [(2)
       (let ([start (car args)] [end (cadr args)])
         (let lp ([i start] [acc '()])
           (if (>= i end) (reverse acc) (lp (+ i 1) (cons i acc)))))]
      [(3)
       (let ([start (car args)] [end (cadr args)] [step (caddr args)])
         (if (positive? step)
             (let lp ([i start] [acc '()])
               (if (>= i end) (reverse acc) (lp (+ i step) (cons i acc))))
             (let lp ([i start] [acc '()])
               (if (<= i end) (reverse acc) (lp (+ i step) (cons i acc))))))]
      [else (error 'range "too many arguments" args)]))

  ;; =========================================================================
  ;; into — (into to-coll from-coll) pumps everything from from into to
  ;; =========================================================================

  (define (into to-coll from-coll)
    (cond
      [(null? to-coll)
       ;; to = '() → build a list via conj (prepend) then reverse
       (reverse (reduce (lambda (acc x) (cons x acc)) '() from-coll))]
      [(pair? to-coll)
       (reverse (reduce (lambda (acc x) (cons x acc)) to-coll from-coll))]
      [(vector? to-coll)
       (cond
         [(pair? from-coll)
          (list->vector (append (vector->list to-coll) from-coll))]
         [(vector? from-coll)
          (list->vector (append (vector->list to-coll)
                                (vector->list from-coll)))]
         [else (error 'into "unsupported from-coll" from-coll)])]
      [(persistent-map? to-coll)
       (reduce (lambda (acc kv)
                 (persistent-map-set acc (car kv) (cdr kv)))
               to-coll
               (cond
                 [(pair? from-coll) from-coll]
                 [(persistent-map? from-coll) (persistent-map->list from-coll)]
                 [else (error 'into "cannot into map from this" from-coll)]))]
      [else (error 'into "unsupported to-coll" to-coll)]))

  ;; =========================================================================
  ;; seq — polymorphic sequence view of a collection.
  ;;
  ;; Clojure's (seq coll) returns nil for empty collections and a
  ;; sequence of elements otherwise. We model Clojure's nil as #f.
  ;;   - Maps yield (key . val) pairs (matching Clojure's MapEntry).
  ;;   - Sets yield the elements in HAMT order.
  ;;   - Vectors and strings yield elements left-to-right.
  ;;   - Lists return themselves.
  ;; =========================================================================

  (define (seq coll)
    (cond
      [(eq? coll #f) #f]
      [(null? coll) #f]
      [(pair? coll) coll]
      [(persistent-map? coll)
       (if (zero? (persistent-map-size coll)) #f (persistent-map->list coll))]
      [(persistent-set? coll)
       (if (zero? (persistent-set-size coll)) #f (persistent-set->list coll))]
      [(sorted-set? coll)
       (if (zero? (sorted-set-size coll)) #f (sorted-set->list coll))]
      [(concurrent-hash? coll)
       (if (zero? (concurrent-hash-size coll))
           #f
           ;; Return (k . v) pairs, matching map semantics.
           (let ([ks (concurrent-hash-keys coll)])
             (map (lambda (k) (cons k (concurrent-hash-get coll k))) ks)))]
      [(hash-table? coll)
       (if (zero? (hash-length coll)) #f (hash->list coll))]
      [(vector? coll)
       (if (zero? (vector-length coll)) #f (vector->list coll))]
      [(string? coll)
       (if (zero? (string-length coll)) #f (string->list coll))]
      [else (error 'seq "unsupported collection type" coll)]))

  ;; =========================================================================
  ;; Equality and hash — polymorphic wrappers.
  ;;
  ;; Clojure's (= a b) is structural; Chez's equal? already does the
  ;; right thing for lists, vectors, strings, and numbers, but records
  ;; (including %pmap / %pset) compare with eq? by default. We dispatch
  ;; on the collection type so the specialized =/hash implementations
  ;; are used transparently.
  ;; =========================================================================

  (define =?
    (case-lambda
      [(a) #t]
      [(a b)
       ;; Metadata does not participate in equality — strip wrappers first.
       (let ([a (strip-meta a)] [b (strip-meta b)])
         (cond
           [(and (persistent-map? a) (persistent-map? b)) (persistent-map=? a b)]
           [(and (persistent-set? a) (persistent-set? b)) (persistent-set=? a b)]
           [else (equal? a b)]))]
      [(a b . more)
       (and (=? a b)
            (let lp ([x b] [rest more])
              (cond
                [(null? rest) #t]
                [else (and (=? x (car rest)) (lp (car rest) (cdr rest)))])))]))

  (define (hash x)
    ;; Polymorphic structural hash, consistent with =?.
    (cond
      [(persistent-map? x) (persistent-map-hash x)]
      [(persistent-set? x) (persistent-set-hash x)]
      [else (equal-hash x)]))

  ;; =========================================================================
  ;; Printing
  ;; =========================================================================

  (define println
    (case-lambda
      [() (newline)]
      [args (for-each (lambda (x) (display x) (display " ")) args) (newline)]))

  (define pr
    (case-lambda
      [() (void)]
      [args (for-each (lambda (x) (write x) (display " ")) args)]))

  (define prn
    (case-lambda
      [() (newline)]
      [args (for-each (lambda (x) (write x) (display " ")) args) (newline)]))

  (define (pr-str . args)
    (call-with-string-output-port
      (lambda (p) (for-each (lambda (x) (write x p) (display " " p)) args))))

  (define (prn-str . args)
    (call-with-string-output-port
      (lambda (p)
        (for-each (lambda (x) (write x p) (display " " p)) args)
        (newline p))))

  ;; =========================================================================
  ;; Transients — polymorphic dispatch across imap (pmap) and ivec (pvec)
  ;;
  ;; Clojure idiom:
  ;;   (let ([t (transient m)])
  ;;     (assoc! t "a" 1)
  ;;     (assoc! t "b" 2)
  ;;     (persistent! t))
  ;;
  ;;   (let ([t (transient v)])
  ;;     (conj! t 1)
  ;;     (conj! t 2)
  ;;     (persistent! t))
  ;; =========================================================================

  (define (transient coll)
    (cond
      [(persistent-map? coll) (transient-map coll)]
      [(persistent-vector? coll) (pvec-transient coll)]
      [(persistent-set? coll) (transient-set coll)]
      [else (error 'transient
                   "expected a persistent map, vector, or set" coll)]))

  (define (transient? x)
    (or (transient-map? x) (pvec-transient? x) (transient-set? x)))

  (define (persistent! t)
    (cond
      [(transient-map? t) (persistent-map! t)]
      [(pvec-transient? t) (pvec-persistent! t)]
      [(transient-set? t) (pset-persistent! t)]
      [else (error 'persistent! "expected a transient" t)]))

  (define assoc!
    ;; Mutating assoc on a transient map.
    ;; (assoc! t k v)
    ;; (assoc! t k1 v1 k2 v2 ...)
    (case-lambda
      [(t key val)
       (cond
         [(transient-map? t) (tmap-set! t key val)]
         [else (error 'assoc! "expected a transient map" t)])]
      [(t key val . more)
       (assoc! t key val)
       (let lp ([rest more])
         (cond
           [(null? rest) t]
           [(null? (cdr rest))
            (error 'assoc! "odd number of key/value arguments")]
           [else
            (assoc! t (car rest) (cadr rest))
            (lp (cddr rest))]))]))

  (define (dissoc! t . ks)
    (cond
      [(transient-map? t)
       (for-each (lambda (k) (tmap-delete! t k)) ks)
       t]
      [else (error 'dissoc! "expected a transient map" t)]))

  (define (conj! t . xs)
    (cond
      [(pvec-transient? t)
       (for-each (lambda (x) (pvec-t-append! t x)) xs)
       t]
      [(transient-map? t)
       ;; Like conj on maps, xs must be [k v] pairs
       (for-each
         (lambda (entry)
           (cond
             [(pair? entry)
              (tmap-set! t (car entry)
                (if (pair? (cdr entry)) (cadr entry) (cdr entry)))]
             [else (error 'conj! "cannot conj non-pair onto transient map" entry)]))
         xs)
       t]
      [(transient-set? t)
       (for-each (lambda (x) (tset-add! t x)) xs)
       t]
      [else (error 'conj! "expected a transient" t)]))

  ;; =========================================================================
  ;; Constructor aliases
  ;; =========================================================================

  ;; hash-map — Clojure constructor (shadows Jerboa's Racket-style mapper)
  (define (hash-map . kvs)
    (apply imap kvs))

  ;; vec — build a persistent vector from a list or vector
  (define vec
    (case-lambda
      [() ivec-empty]
      [(coll)
       (cond
         [(null? coll) ivec-empty]
         [(pair? coll) (apply ivec coll)]
         [(vector? coll) (vector->ivec coll)]
         [else (error 'vec "unsupported collection" coll)])]))

  ;; list* — (list* 1 2 '(3 4)) → (1 2 3 4)
  (define list* cons*)

  ;; vector* — builds a mutable vector (Chez's (vector ...) works too)
  (define (vector* . args) (apply vector args))

  ;; =========================================================================
  ;; Sets — Clojure-style persistent set API on top of (std pset)
  ;; =========================================================================

  ;; hash-set — Clojure's #{:a :b :c} constructor
  (define (hash-set . items)
    (apply persistent-set items))

  ;; set — alias for hash-set (Clojure has both; `set` also coerces
  ;; a collection into a set, which we handle by expanding the arg)
  (define set
    (case-lambda
      [() pset-empty]
      [(coll)
       (cond
         [(null? coll) pset-empty]
         [(persistent-set? coll) coll]
         [(pair? coll) (apply persistent-set coll)]
         [(vector? coll) (apply persistent-set (vector->list coll))]
         [(persistent-vector? coll)
          (apply persistent-set (persistent-vector->list coll))]
         [else (error 'set "unsupported collection" coll)])]))

  (define set? persistent-set?)

  ;; make-hash-set — parameterless constructor
  (define (make-hash-set) pset-empty)

  ;; disj — Clojure's "remove from set"
  (define (disj s . items)
    (cond
      [(persistent-set? s)
       (let lp ([cur s] [rest items])
         (if (null? rest) cur
             (lp (persistent-set-remove cur (car rest)) (cdr rest))))]
      [(sorted-set? s)
       (let lp ([cur s] [rest items])
         (if (null? rest) cur
             (lp (sorted-set-remove cur (car rest)) (cdr rest))))]
      [else (error 'disj "expected a set" s)]))

  ;; Clojure's clojure.set/ operations
  ;;
  ;; Both `persistent-set` (HAMT) and `sorted-set` (red-black tree) are
  ;; valid set-types. When the first operand is a sorted-set we dispatch
  ;; to a sorted-set-preserving implementation that folds elements from
  ;; the other operands — otherwise we use the HAMT-optimized primitives
  ;; from (std pset).

  (define (union . sets)
    (cond
      [(null? sets) pset-empty]
      [(null? (cdr sets)) (car sets)]
      [(sorted-set? (car sets))
       (let lp ([acc (car sets)] [rest (cdr sets)])
         (if (null? rest) acc
             (lp (sorted-set-fold (car rest)
                     (lambda (x a) (sorted-set-add a x))
                     acc)
                   (cdr rest))))]
      [else
       (let lp ([acc (car sets)] [rest (cdr sets)])
         (if (null? rest) acc
             (lp (persistent-set-union acc (car rest)) (cdr rest))))]))

  (define (intersection . sets)
    (cond
      [(null? sets) pset-empty]
      [(null? (cdr sets)) (car sets)]
      [(sorted-set? (car sets))
       (let lp ([acc (car sets)] [rest (cdr sets)])
         (if (null? rest) acc
             (let ([other (car rest)])
               (lp (sorted-set-fold acc
                       (lambda (x a)
                         (if (contains? other x) a (sorted-set-remove a x)))
                       acc)
                     (cdr rest)))))]
      [else
       (let lp ([acc (car sets)] [rest (cdr sets)])
         (if (null? rest) acc
             (lp (persistent-set-intersection acc (car rest)) (cdr rest))))]))

  (define (difference . sets)
    (cond
      [(null? sets) pset-empty]
      [(null? (cdr sets)) (car sets)]
      [(sorted-set? (car sets))
       (let lp ([acc (car sets)] [rest (cdr sets)])
         (if (null? rest) acc
             (lp (sorted-set-fold (car rest)
                     (lambda (x a) (sorted-set-remove a x))
                     acc)
                   (cdr rest))))]
      [else
       (let lp ([acc (car sets)] [rest (cdr sets)])
         (if (null? rest) acc
             (lp (persistent-set-difference acc (car rest)) (cdr rest))))]))

  (define (subset? s1 s2)
    (cond
      [(sorted-set? s1)
       (sorted-set-fold s1
         (lambda (x acc) (and acc (contains? s2 x)))
         #t)]
      [else (persistent-set-subset? s1 s2)]))

  (define (superset? s1 s2) (subset? s2 s1))

  ;; =========================================================================
  ;; Set relational operations (clojure.set)
  ;;
  ;; These operate on "relations" — sets of maps (persistent sets of
  ;; persistent maps). Like Clojure, they provide a tiny relational
  ;; algebra over in-memory data.
  ;; =========================================================================

  ;; set-select — return subset where (pred map) is true
  ;; Like clojure.set/select: (select even? #{1 2 3 4}) => #{2 4}
  (define (set-select pred rel)
    (let ([result pset-empty])
      (for-each (lambda (item)
                  (when (pred item)
                    (set! result (persistent-set-add result item))))
                (persistent-set->list rel))
      result))

  ;; set-project — project a relation onto a subset of keys
  ;; Like clojure.set/project: return set of maps with only given keys
  (define (set-project rel ks)
    (let ([result pset-empty])
      (for-each (lambda (m)
                  (let ([projected (select-keys m ks)])
                    (set! result (persistent-set-add result projected))))
                (persistent-set->list rel))
      result))

  ;; set-rename — rename keys in all maps of a relation
  ;; kmap: alist or pmap of old-key → new-key
  (define (set-rename rel kmap)
    (let ([pairs (cond
                   [(persistent-map? kmap) (persistent-map->list kmap)]
                   [(list? kmap) kmap]
                   [else (error 'set-rename "kmap must be a map or alist" kmap)])]
          [result pset-empty])
      (for-each (lambda (m)
                  (let ([new-m (fold-left
                                 (lambda (acc pair)
                                   (let ([old-k (car pair)] [new-k (cdr pair)])
                                     (if (contains? acc old-k)
                                       (assoc (dissoc acc old-k) new-k (get acc old-k))
                                       acc)))
                                 m pairs)])
                    (set! result (persistent-set-add result new-m))))
                (persistent-set->list rel))
      result))

  ;; set-index — index a relation by a set of keys
  ;; Returns a Chez hashtable (using =?/hash for key equality)
  ;; mapping key-map → set of matching rows.
  ;; Note: uses a mutable hashtable because persistent maps can't be
  ;; used as keys in other persistent maps (equal? doesn't work on them).
  (define (set-index rel ks)
    (let ([ht (make-hashtable hash =?)])
      (for-each
        (lambda (m)
          (let ([key-map (select-keys m ks)])
            (let ([existing (hashtable-ref ht key-map #f)])
              (hashtable-set! ht key-map
                (if existing
                  (persistent-set-add existing m)
                  (persistent-set-add pset-empty m))))))
        (persistent-set->list rel))
      ht))

  ;; set-join — natural join of two relations
  ;; Joins on shared keys. Like clojure.set/join.
  (define set-join
    (case-lambda
      [(rel1 rel2)
       ;; Natural join: find shared keys from first elements
       (if (or (zero? (persistent-set-size rel1))
               (zero? (persistent-set-size rel2)))
         pset-empty
         (let* ([m1 (car (persistent-set->list rel1))]
                [m2 (car (persistent-set->list rel2))]
                [k1 (keys m1)]
                [k2 (keys m2)]
                [shared (filter (lambda (k) (contains? m2 k)) k1)]
                [idx (set-index rel2 shared)]
                [result pset-empty])
           (for-each
             (lambda (row1)
               (let* ([key-map (select-keys row1 shared)]
                      [matches (hashtable-ref idx key-map #f)])
                 (when matches
                   (for-each
                     (lambda (row2)
                       (set! result
                         (persistent-set-add result (merge row1 row2))))
                     (persistent-set->list matches)))))
             (persistent-set->list rel1))
           result))]
      [(rel1 rel2 km)
       ;; Join with key mapping: km maps keys in rel1 to keys in rel2
       (let* ([pairs (cond
                       [(persistent-map? km) (persistent-map->list km)]
                       [(list? km) km]
                       [else (error 'set-join "km must be a map or alist" km)])]
              [renamed (set-rename rel2
                         (map (lambda (p) (cons (cdr p) (car p))) pairs))])
         (set-join rel1 renamed))]))

  ;; map-invert — swap keys and values in a map
  (define (map-invert m)
    (let ([entries (cond
                     [(persistent-map? m) (persistent-map->list m)]
                     [(and (pair? m) (pair? (car m))) m]
                     [else (error 'map-invert "not a map" m)])])
      (fold-left (lambda (acc pair)
                   (assoc acc (cdr pair) (car pair)))
                 pmap-empty
                 entries)))

  ;; =========================================================================
  ;; Map-convenience stragglers — Clojure's `merge-with`, `zipmap`,
  ;; `reduce-kv`, and `min-key`/`max-key`.
  ;; =========================================================================

  ;; merge-with — like merge, but resolves key collisions by applying
  ;; `f` to the existing and new values. Preserves the type of the
  ;; leftmost map argument.
  ;;   (merge-with + {:a 1 :b 2} {:b 3 :c 4}) => {:a 1 :b 5 :c 4}
  (define (merge-with f . maps)
    (cond
      [(null? maps) #f]                         ;; Clojure returns nil
      [(null? (cdr maps)) (car maps)]
      [else
       (let ([first-map (car maps)])
         (reduce
           (lambda (acc m)
             (reduce
               (lambda (acc2 kv)
                 (let ([k (car kv)] [v (cdr kv)])
                   (if (contains? acc2 k)
                       (assoc acc2 k (f (get acc2 k) v))
                       (assoc acc2 k v))))
               acc
               (seq m)))
           first-map
           (cdr maps)))]))

  ;; zipmap — build a persistent-map from a list of keys and values.
  ;;   (zipmap '(a b c) '(1 2 3)) => {a 1 b 2 c 3}
  ;; Extra items in either list are ignored, matching Clojure.
  (define (zipmap ks vs)
    (let lp ([ks ks] [vs vs] [acc pmap-empty])
      (cond
        [(or (null? ks) (null? vs)) acc]
        [else (lp (cdr ks) (cdr vs)
                    (persistent-map-set acc (car ks) (car vs)))])))

  ;; reduce-kv — like reduce, but takes a 3-argument function (acc k v)
  ;; and walks a map's entries.
  ;;   (reduce-kv (lambda (acc k v) (+ acc v)) 0 {:a 1 :b 2}) => 3
  (define (reduce-kv f init coll)
    (cond
      [(persistent-map? coll)
       (persistent-map-fold
         (lambda (acc k v) (f acc k v))
         init coll)]
      [(concurrent-hash? coll)
       (let ([acc init])
         (concurrent-hash-for-each
           (lambda (k v) (set! acc (f acc k v)))
           coll)
         acc)]
      [(hash-table? coll)
       (let ([acc init])
         (hash-for-each
           (lambda (k v) (set! acc (f acc k v)))
           coll)
         acc)]
      [(and (record? coll)
            (not (persistent-map? coll))
            (not (persistent-set? coll))
            (not (sorted-set? coll))
            (not (concurrent-hash? coll)))
       (let lp ([fields (%record-fields-all coll)] [acc init])
         (if (null? fields)
             acc
             (let ([pair (car fields)])
               (lp (cdr fields)
                     (f acc (car pair) ((cdr pair) coll))))))]
      [else (error 'reduce-kv "unsupported collection type" coll)]))

  ;; min-key — return the x in coll that minimizes (k x).
  ;;   (min-key count '("aa" "b" "ccc")) => "b"
  (define (min-key k x . more)
    (if (null? more)
        x
        (let lp ([best x] [best-key (k x)] [rest more])
          (if (null? rest)
              best
              (let* ([y (car rest)] [yk (k y)])
                (if (< yk best-key)
                    (lp y yk (cdr rest))
                    (lp best best-key (cdr rest))))))))

  ;; max-key — return the x in coll that maximizes (k x).
  (define (max-key k x . more)
    (if (null? more)
        x
        (let lp ([best x] [best-key (k x)] [rest more])
          (if (null? rest)
              best
              (let* ([y (car rest)] [yk (k y)])
                (if (> yk best-key)
                    (lp y yk (cdr rest))
                    (lp best best-key (cdr rest))))))))

  ;; =========================================================================
  ;; Functional combinators — memoize / iterate / repeatedly
  ;;
  ;; Clojure's `iterate` and `repeatedly` return lazy seqs; Jerboa has
  ;; no lazy seqs in the prelude (Tier 2 item). For now we expose
  ;; bounded, strict forms that require a count.
  ;; =========================================================================

  ;; memoize — cache f's results by argument list (unbounded).
  (define memoize clj-memoize)

  ;; iterate — two forms:
  ;;   (iterate f x)   → infinite lazy seq: x, (f x), (f (f x)), ...
  ;;   (iterate n f x) → eager list of n elements (backwards compat)
  (define iterate
    (case-lambda
      [(f x)   (lazy-iterate f x)]
      [(n f x) (iterate-n n f x)]))

  ;; repeatedly — two forms:
  ;;   (repeatedly f)   → infinite lazy seq of calls to (f)
  ;;   (repeatedly n f) → eager list of n calls to (f)
  (define repeatedly
    (case-lambda
      [(f)
       (let make-lazy ()
         (lazy-cons (f) (make-lazy)))]
      [(n f)
       (let lp ([i 0] [acc '()])
         (if (>= i n)
             (reverse acc)
             (lp (+ i 1) (cons (f) acc))))]))

  ;; =========================================================================
  ;; doto — thread an object through side-effecting calls.
  ;;
  ;; (doto obj (f a b) (g c)) => (let ([x obj]) (f x a b) (g x c) x)
  ;;
  ;; Classic use: build up a mutable container.
  ;;   (doto (make-hash-table)
  ;;     (hash-put! 'a 1)
  ;;     (hash-put! 'b 2))
  ;; =========================================================================
  (define-syntax doto
    (syntax-rules ()
      [(_ x) x]
      [(_ x (f arg ...) rest ...)
       (let ([tmp x])
         (f tmp arg ...)
         (doto tmp rest ...))]))

  ;; =========================================================================
  ;; Destructuring — Clojure-style `dlet` and `dfn`.
  ;;
  ;; Destructuring `let` that supports sequential and map patterns:
  ;;
  ;;   (dlet ([x 42]                              ;; plain binding
  ;;          [(a b c) '(1 2 3)]                   ;; list destructure
  ;;          [(h & t) '(10 20 30)]                ;; head + rest
  ;;          [(keys: x y) m]                      ;; map :keys (keyword lookup)
  ;;          [(keys: x y as: all) m]              ;; map + bind whole
  ;;          [(keys: x y or: ([y 100])) m])       ;; map + defaults
  ;;     body ...)
  ;;
  ;; `dfn` defines a function whose parameters are destructured:
  ;;   (dfn (name (keys: x y) z) body ...)
  ;;   → (define (name _tmp z) (dlet ([(keys: x y) _tmp]) body ...))
  ;;
  ;; NOTES:
  ;;   - keys: lookups use Jerboa keywords (x: → #:x) via `get`.
  ;;   - List patterns walk via car/cdr — no length checking.
  ;;   - & binds the remainder of the list.
  ;; =========================================================================

  (define-syntax dlet
    (lambda (stx)
      ;; Is datum a Jerboa keyword (name:)?
      ;; The Jerboa reader stores keywords as symbols with a trailing
      ;; colon: keys: → symbol "keys:", x: → symbol "x:".
      (define (kw-datum? d)
        (and (symbol? d)
             (let ([s (symbol->string d)])
               (and (>= (string-length s) 2)
                    (char=? (string-ref s (- (string-length s) 1)) #\:)))))

      ;; Does keyword datum match a specific name?
      (define (kw=? d name)
        (and (kw-datum? d)
             (string=? (symbol->string d)
                       (string-append name ":"))))

      ;; symbol → keyword symbol: x → x:
      (define (sym->kw s)
        (string->symbol (string-append (symbol->string s) ":")))

      ;; Parse the spec list after keys: keyword.
      ;; Returns (values names as-name or-alist)
      ;;   names   = list of symbols
      ;;   as-name = #f or symbol
      ;;   or-alist = ((name . default) ...)
      (define (parse-keys-spec specs)
        (let lp ([rest specs] [names '()] [as-name #f] [defaults '()])
          (cond
            [(null? rest)
             (values (reverse names) as-name defaults)]
            ;; as: sym
            [(and (kw=? (car rest) "as") (pair? (cdr rest)))
             (lp (cddr rest) names (cadr rest) defaults)]
            ;; or: ((name default) ...)
            [(and (kw=? (car rest) "or") (pair? (cdr rest))
                  (list? (cadr rest)))
             (lp (cddr rest) names as-name
                   (append defaults
                           (map (lambda (pair) (cons (car pair) (cadr pair)))
                                (cadr rest))))]
            ;; plain symbol
            [(and (symbol? (car rest)) (not (kw-datum? (car rest))))
             (lp (cdr rest) (cons (car rest) names) as-name defaults)]
            [else
             (error 'dlet "invalid keys: spec" specs)])))

      ;; Build car/cdr accessor chain for index i.
      ;; 0 → (car tmp), 1 → (cadr tmp), 2 → (caddr tmp), etc.
      (define (list-ref-expr tmp i)
        (let lp ([i i] [expr tmp])
          (cond
            [(zero? i) `(car ,expr)]
            [else (lp (- i 1) `(cdr ,expr))])))

      ;; Build cdr chain to get the tail after index i.
      ;; (list-tail-expr tmp 2) → (cddr tmp)
      (define (list-tail-expr tmp i)
        (let lp ([i i] [expr tmp])
          (cond
            [(zero? i) expr]
            [else (lp (- i 1) `(cdr ,expr))])))

      ;; Analyze a list pattern for & (rest capture).
      ;; Returns (values before-syms rest-sym)
      ;; where rest-sym is #f if no & found.
      (define (parse-list-pattern elems)
        (let lp ([rest elems] [before '()])
          (cond
            [(null? rest)
             (values (reverse before) #f)]
            [(and (symbol? (car rest)) (string=? (symbol->string (car rest)) "&")
                  (pair? (cdr rest))
                  (null? (cddr rest)))
             (values (reverse before) (cadr rest))]
            [else
             (lp (cdr rest) (cons (car rest) before))])))

      (syntax-case stx ()
        ;; Base: no bindings left
        [(k () body ...)
         #'(begin body ...)]

        ;; Symbol pattern — plain binding
        [(k ([pat expr] . rest) body ...)
         (identifier? #'pat)
         #'(let ([pat expr])
             (dlet rest body ...))]

        ;; Compound pattern — inspect at datum level.
        ;; Use #'expr as the lexical context for generated bindings
        ;; so that they resolve in the user's scope.
        [(k ([pat expr] . rest) body ...)
         (let* ([p (syntax->datum #'pat)]
                ;; Use the second element of pat (a user identifier)
                ;; as the lexical context so generated names resolve
                ;; in the user's scope. Fall back to the first body form.
                [pat-elts (syntax->list #'pat)]
                [ctx (if (and pat-elts (> (length pat-elts) 1))
                         (cadr pat-elts)  ;; first name in pattern
                         #'k)])
           (cond
             ;; --- Map destructure: (keys: x y ...) ---
             [(and (pair? p) (kw=? (car p) "keys"))
              (let-values ([(names as-name defaults)
                            (parse-keys-spec (cdr p))])
                (let* ([tmp (gensym "map")]
                       [binds
                         (append
                           (if as-name (list (list as-name tmp)) '())
                           (map (lambda (name)
                                  (let ([kw (sym->kw name)]
                                        [dflt (assq name defaults)])
                                    (if dflt
                                        `(,name (if (contains? ,tmp ',kw)
                                                    (get ,tmp ',kw)
                                                    ,(cdr dflt)))
                                        `(,name (get ,tmp ',kw)))))
                                names))])
                  (with-syntax ([tmp-id (datum->syntax ctx tmp)]
                                [(bind ...) (datum->syntax ctx binds)]
                                [e #'expr]
                                [r #'rest]
                                [(bd ...) #'(body ...)])
                    #'(let ([tmp-id e])
                        (let* (bind ...)
                          (dlet r bd ...))))))]

             ;; --- List destructure: (a b c) or (a b & rest) ---
             [(pair? p)
              (let-values ([(before rest-sym) (parse-list-pattern p)])
                (let* ([tmp (gensym "seq")]
                       [binds
                         (append
                           (let lp ([i 0] [syms before] [acc '()])
                             (if (null? syms)
                                 (reverse acc)
                                 (lp (+ i 1)
                                       (cdr syms)
                                       (cons (list (car syms)
                                                   (list-ref-expr tmp i))
                                             acc))))
                           (if rest-sym
                               (list (list rest-sym
                                           (list-tail-expr tmp
                                                           (length before))))
                               '()))])
                  (with-syntax ([tmp-id (datum->syntax ctx tmp)]
                                [(bind ...) (datum->syntax ctx binds)]
                                [e #'expr]
                                [r #'rest]
                                [(bd ...) #'(body ...)])
                    #'(let ([tmp-id e])
                        (let* (bind ...)
                          (dlet r bd ...))))))]

             [else (syntax-error #'pat "dlet: unsupported pattern")]))])))

  ;; dfn — define a function with destructured parameters.
  ;;
  ;; Parameters that are compound patterns are destructured. Plain
  ;; symbol parameters pass through.
  ;;
  ;; (dfn (name (keys: x y) z) body ...)
  ;; → (define (name __tmp1 z)
  ;;     (dlet ([(keys: x y) __tmp1]) body ...))
  (define-syntax dfn
    (lambda (stx)
      ;; Returns #t for identifiers (plain symbols), #f for compound
      ;; patterns that need destructuring.
      (define (simple-param? d)
        (and (symbol? d)
             (not (pair? d))))

      (syntax-case stx ()
        [(k (name params ...) body ...)
         (identifier? #'name)
         (let* ([ctx #'name]   ;; use the function name as lexical context
                [param-data (map syntax->datum (syntax->list #'(params ...)))]
                [formals
                  (map (lambda (p)
                         (if (simple-param? p) p (gensym "arg")))
                       param-data)]
                [bindings
                  (let lp ([ps param-data] [fs formals] [acc '()])
                    (cond
                      [(null? ps) (reverse acc)]
                      [(simple-param? (car ps))
                       (lp (cdr ps) (cdr fs) acc)]
                      [else
                       (lp (cdr ps) (cdr fs)
                             (cons (list (car ps) (car fs)) acc))]))])
           (with-syntax ([(formal ...) (datum->syntax ctx formals)]
                         [binds (datum->syntax ctx bindings)]
                         [(bd ...) #'(body ...)])
             #'(define (name formal ...)
                 (dlet binds bd ...))))])))

  ;; =========================================================================
  ;; Dynamic vars — Clojure-style `def-dynamic` + `binding`.
  ;;
  ;; Wraps Chez's `make-parameter` / `parameterize`.
  ;; Includes a registry so that `go` / `clj-thread` / `clj-future` can
  ;; snapshot current binding values and re-establish them in child
  ;; threads/fibers — matching Clojure's binding conveyance.
  ;; =========================================================================

  ;; Global registry of all dynamic-var parameters.
  (define *dynamic-var-registry* '())
  (define *dynamic-var-mutex* (make-mutex))

  (define (register-dynamic-var! param)
    (with-mutex *dynamic-var-mutex*
      (set! *dynamic-var-registry*
        (cons param *dynamic-var-registry*))))

  ;; Capture current values of all registered dynamic vars.
  ;; Returns an alist of (param . value).
  (define (capture-dynamic-bindings)
    (with-mutex *dynamic-var-mutex*
      (map (lambda (p) (cons p (p))) *dynamic-var-registry*)))

  ;; Wrap a thunk so it runs with the captured dynamic bindings.
  (define (bound-fn thunk)
    (let ([bindings (capture-dynamic-bindings)])
      (lambda ()
        (apply-dynamic-bindings bindings thunk))))

  ;; Apply captured bindings around a thunk.
  (define (apply-dynamic-bindings bindings thunk)
    (if (null? bindings)
        (thunk)
        (let ([pair (car bindings)])
          (parameterize ([(car pair) (cdr pair)])
            (apply-dynamic-bindings (cdr bindings) thunk)))))

  (define-syntax def-dynamic
    (syntax-rules ()
      [(_ name default)
       (begin
         (define name (make-parameter default))
         (register-dynamic-var! name))]
      [(_ name default guard)
       (begin
         (define name (make-parameter default guard))
         (register-dynamic-var! name))]))

  (define-syntax binding
    (syntax-rules ()
      [(_ ([var val] ...) body ...)
       (parameterize ([var val] ...) body ...)]))

  ;; =========================================================================
  ;; Structured exceptions — Clojure's `ex-info` / `ex-data` surface.
  ;;
  ;; Wraps Jerboa/Chez's condition system so handlers can match on
  ;; a data map rather than a class hierarchy.
  ;;
  ;;   (try
  ;;     (throw (ex-info "nsf" (hash-map :from a :to b :reason 'nsf)))
  ;;     (catch (e)
  ;;       (when (ex-info? e)
  ;;         (let ([data (ex-data e)])
  ;;           (when (eq? (get data :reason) 'nsf)
  ;;             (handle-nsf))))))
  ;;
  ;; `ex-info` creates a composite condition containing a data
  ;; condition, a message condition, and optionally a nested cause.
  ;; `ex-data`, `ex-message`, `ex-cause` extract the parts and return
  ;; #f if the condition isn't an ex-info.
  ;; =========================================================================

  (define-condition-type &ex-info &condition
    make-ex-info-condition ex-info-condition?
    (data ex-info-condition-data)
    (cause ex-info-condition-cause))

  (define ex-info
    (case-lambda
      [(msg data) (ex-info msg data #f)]
      [(msg data cause)
       (condition
         (make-ex-info-condition data cause)
         (make-message-condition msg))]))

  (define (ex-info? c)
    (and (condition? c) (ex-info-condition? c)))

  (define (ex-data c)
    (and (condition? c)
         (ex-info-condition? c)
         (ex-info-condition-data c)))

  (define (ex-message c)
    (cond
      [(and (condition? c) (message-condition? c))
       (condition-message c)]
      [else #f]))

  (define (ex-cause c)
    (and (condition? c)
         (ex-info-condition? c)
         (ex-info-condition-cause c)))

  ;; =========================================================================
  ;; Lazy sequence convenience wrappers (Clojure-named)
  ;; =========================================================================

  ;; cycle — infinite lazy repetition of a list's elements
  (define cycle lazy-cycle)

  ;; repeat — infinite lazy sequence of a single value
  (define repeat lazy-repeat)

  ;; doall — force all elements, return the realized lazy seq as a list
  (define (doall seq)
    (if (lazy-seq? seq)
      (lazy->list seq)
      seq))

  ;; dorun — force all elements for side effects, return void
  (define (dorun seq)
    (when (lazy-seq? seq)
      (lazy-for-each (lambda (_) (void)) seq)))

  ;; realized? — polymorphic: lazy seqs, delays, futures, promises
  (define (realized? x)
    (cond
      [(lazy-seq? x) (lazy-realized? x)]
      [(delay? x) (delay-realized? x)]
      [(future? x) (future-done? x)]
      [(promise? x) (promise-realized? x)]
      [else (error 'realized? "not a realizable type" x)]))

  ;; =========================================================================
  ;; Delay / Future / Promise — Clojure-style concurrency primitives
  ;; =========================================================================

  ;; ---- Delay: lazy memoized computation ----
  ;; (clj-delay body ...) → delay object, computed at most once on deref

  (define-record-type clj-delay-record
    (nongenerative std-clojure-delay)
    (fields thunk
            (mutable value)
            (mutable realized?))
    (sealed #t)
    (protocol (lambda (new) (lambda (thunk) (new thunk (void) #f)))))

  (define-syntax clj-delay
    (syntax-rules ()
      [(_ body ...)
       (make-clj-delay-record (lambda () body ...))]))

  (define (delay? x) (clj-delay-record? x))

  (define (delay-realized? d) (clj-delay-record-realized? d))

  (define (force-delay d)
    (unless (clj-delay-record-realized? d)
      (let ([v ((clj-delay-record-thunk d))])
        (unless (clj-delay-record-realized? d)
          (clj-delay-record-value-set! d v)
          (clj-delay-record-realized?-set! d #t))))
    (clj-delay-record-value d))

  (define clj-force force-delay)

  ;; ---- Future: computation in a separate thread ----
  ;; (clj-future body ...) → future object, runs body in a new thread

  (define-record-type clj-future-record
    (nongenerative std-clojure-future)
    (fields (mutable value)
            (mutable done?)
            (mutable exception)
            (mutable cancelled?)
            mutex
            condvar
            (mutable thread))
    (sealed #t))

  (define-syntax clj-future
    (syntax-rules ()
      [(_ body ...)
       (let* ([mtx (make-mutex)]
              [cv (make-condition)]
              [f (make-clj-future-record (void) #f #f #f mtx cv #f)]
              [%bindings (capture-dynamic-bindings)])
         (let ([t (fork-thread
                    (lambda ()
                      (apply-dynamic-bindings %bindings
                        (lambda ()
                          (guard (exn
                                   [#t
                                    (with-mutex mtx
                                      (clj-future-record-exception-set! f exn)
                                      (clj-future-record-done?-set! f #t)
                                      (condition-broadcast cv))])
                            (let ([v (begin body ...)])
                              (with-mutex mtx
                                (clj-future-record-value-set! f v)
                                (clj-future-record-done?-set! f #t)
                                (condition-broadcast cv))))))))])
           (clj-future-record-thread-set! f t)
           f))]))

  (define (future? x) (clj-future-record? x))

  (define (future-done? f)
    (clj-future-record-done? f))

  (define (future-cancel f)
    (with-mutex (clj-future-record-mutex f)
      (unless (clj-future-record-done? f)
        (clj-future-record-cancelled?-set! f #t)
        (clj-future-record-done?-set! f #t)
        (condition-broadcast (clj-future-record-condvar f))))
    #t)

  (define (future-cancelled? f)
    (clj-future-record-cancelled? f))

  (define (deref-future f)
    (with-mutex (clj-future-record-mutex f)
      (let lp ()
        (cond
          [(clj-future-record-cancelled? f)
           (error 'deref "future was cancelled")]
          [(clj-future-record-done? f)
           (let ([exn (clj-future-record-exception f)])
             (if exn (raise exn) (clj-future-record-value f)))]
          [else
           (condition-wait (clj-future-record-condvar f)
                           (clj-future-record-mutex f))
           (lp)]))))

  ;; ---- Promise: write-once value, delivered from another thread ----
  ;; (clj-promise) → promise object
  ;; (deliver p val) → delivers val to the promise

  (define-record-type clj-promise-record
    (nongenerative std-clojure-promise)
    (fields (mutable value)
            (mutable realized?)
            mutex
            condvar)
    (sealed #t)
    (protocol (lambda (new)
                (lambda ()
                  (new (void) #f (make-mutex) (make-condition))))))

  (define (clj-promise) (make-clj-promise-record))

  (define (promise? x) (clj-promise-record? x))

  (define (promise-realized? p) (clj-promise-record-realized? p))

  (define (deliver p val)
    (with-mutex (clj-promise-record-mutex p)
      (unless (clj-promise-record-realized? p)
        (clj-promise-record-value-set! p val)
        (clj-promise-record-realized?-set! p #t)
        (condition-broadcast (clj-promise-record-condvar p))))
    p)

  (define (deref-promise p)
    (with-mutex (clj-promise-record-mutex p)
      (let lp ()
        (if (clj-promise-record-realized? p)
          (clj-promise-record-value p)
          (begin
            (condition-wait (clj-promise-record-condvar p)
                            (clj-promise-record-mutex p))
            (lp))))))

  ;; ---- Polymorphic deref ----
  ;; Works on atoms, delays, futures, and promises

  (define (deref x)
    (cond
      [(atom? x) (atom-deref x)]
      [(delay? x) (force-delay x)]
      [(future? x) (deref-future x)]
      [(promise? x) (deref-promise x)]
      [(volatile? x) (vderef x)]
      [else (error 'deref "not a deref-able type" x)]))

  ;; =========================================================================
  ;; require — Clojure-style import sugar.
  ;;
  ;; (require '(std sort) :as s)         → (import (prefix (std sort) s:))
  ;; (require '(std sort) :refer (sort)) → (import (only (std sort) sort))
  ;; (require '(std sort))               → (import (std sort))
  ;;
  ;; NOTE: like import, this must be used at the top level of a program
  ;; or library body. It cannot be used inside let/define/etc.
  ;; =========================================================================
  (define-syntax require
    (lambda (stx)
      (syntax-case stx (quote)
        ;; (require '(mod path) :as alias)
        [(_ (quote mod-path) kw alias)
         (and (eq? (syntax->datum #'kw) ':as)
              (identifier? #'alias))
         (let ([prefix-sym (string->symbol
                             (string-append
                               (symbol->string (syntax->datum #'alias))
                               ":"))])
           (with-syntax ([pfx (datum->syntax #'alias prefix-sym)])
             #'(import (prefix mod-path pfx))))]
        ;; (require '(mod path) :refer (name1 name2 ...))
        [(_ (quote mod-path) kw (name ...))
         (eq? (syntax->datum #'kw) ':refer)
         #'(import (only mod-path name ...))]
        ;; (require '(mod path))  — bare import
        [(_ (quote mod-path))
         #'(import mod-path)])))

  ;; =========================================================================
  ;; loop / recur — Clojure-style explicit tail recursion.
  ;;
  ;; (loop ([x 0] [acc '()])
  ;;   (if (= x 5)
  ;;     acc
  ;;     (recur (+ x 1) (cons x acc))))
  ;;
  ;; Expands to a named let. recur becomes a tail call to the loop
  ;; label. Chez already optimizes all tail calls, so this is purely
  ;; a familiarity/readability aid for Clojure developers.
  ;; =========================================================================
  (define-syntax recur
    (lambda (stx)
      (syntax-violation 'recur "recur used outside of loop" stx)))

  (define-syntax loop
    (lambda (stx)
      (syntax-case stx ()
        [(k ([var init] ...) body ...)
         ;; Use datum->syntax with #'k (the call-site's `loop` keyword)
         ;; to inject %loop and recur into the caller's scope.
         (with-syntax ([%lp    (datum->syntax #'k '%loop)]
                       [recur* (datum->syntax #'k 'recur)])
           #'(let %lp ([var init] ...)
               (letrec-syntax ([recur*
                                (syntax-rules ()
                                  [(_ arg (... ...))
                                   (%lp arg (... ...))])])
                 body ...)))])))

  ;; =========================================================================
  ;; Clojure 1.11+ conveniences
  ;; =========================================================================

  ;; ---- parse-long / parse-double / parse-boolean / parse-uuid ----
  ;;
  ;; All return `#f` (Clojure's `nil`) when the input is not a valid
  ;; representation, matching Clojure's `clojure.core/parse-*`.

  (define (parse-long s)
    (and (string? s)
         (let ([n (string->number s 10)])
           (and (integer? n) (exact? n) n))))

  (define (parse-double s)
    (and (string? s)
         (let ([n (string->number s)])
           (and (number? n) (real? n) (inexact? n) n))))

  (define (parse-boolean s)
    (cond
      [(equal? s "true") #t]
      [(equal? s "false") #f]
      [else #f]))   ;; Clojure returns nil for non-matches; we use #f.

  ;; UUID v4 helpers — pure Scheme so no FFI dependency at parse time.
  (define (parse-uuid s)
    (and (string? s)
         (= (string-length s) 36)
         (char=? (string-ref s 8) #\-)
         (char=? (string-ref s 13) #\-)
         (char=? (string-ref s 18) #\-)
         (char=? (string-ref s 23) #\-)
         (let ([hex
                (string-append
                  (substring s 0 8)
                  (substring s 9 13)
                  (substring s 14 18)
                  (substring s 19 23)
                  (substring s 24 36))])
           (and (= (string-length hex) 32)
                (let loop ([i 0])
                  (cond
                    [(= i 32) s]
                    [else
                     (let ([c (string-ref hex i)])
                       (and (or (char<=? #\0 c #\9)
                                (char<=? #\a c #\f)
                                (char<=? #\A c #\F))
                            (loop (+ i 1))))]))))))

  ;; (random-uuid) returns a fresh v4 UUID as a 36-char string.
  ;; Uses Chez's `random` so it does not require crypto-grade entropy
  ;; — sufficient for local IDs, not for security tokens.  For a CSPRNG
  ;; UUID, use `(std crypto rand)`.
  (define (random-uuid)
    (define (hex-pad n width)
      (let* ([s (number->string n 16)]
             [pad (- width (string-length s))])
        (if (positive? pad)
            (string-append (make-string pad #\0) s)
            s)))
    (define (rand-hex n) (hex-pad (random (expt 16 n)) n))
    (let* ([a (rand-hex 8)]
           [b (rand-hex 4)]
           ;; v4: block 3 starts with "4"
           [c (string-append "4" (rand-hex 3))]
           ;; variant: block 4 starts with one of 8 9 a b
           [d (string-append
                (string (string-ref "89ab" (random 4)))
                (rand-hex 3))]
           [e (rand-hex 12)])
      (string-append a "-" b "-" c "-" d "-" e)))

  ;; ---- update-vals / update-keys --------------------------------
  ;;
  ;; Apply a function to every value (resp. key) of a map.  Operate
  ;; polymorphically across persistent-maps and hash-tables — the
  ;; output container kind matches the input.

  (define (update-vals m f)
    (cond
      [(persistent-map? m)
       (let loop ([pairs (persistent-map->list m)]
                  [acc (persistent-map)])
         (cond
           [(null? pairs) acc]
           [else
            (let ([kv (car pairs)])
              (loop (cdr pairs)
                    (persistent-map-set acc (car kv) (f (cdr kv)))))]))]
      [(hash-table? m)
       (let ([new (make-hash-table)])
         (for-each
           (lambda (k) (hash-put! new k (f (hash-ref m k))))
           (hash-keys m))
         new)]
      [else (error 'update-vals "not a map" m)]))

  (define (update-keys m f)
    (cond
      [(persistent-map? m)
       (let loop ([pairs (persistent-map->list m)]
                  [acc (persistent-map)])
         (cond
           [(null? pairs) acc]
           [else
            (let ([kv (car pairs)])
              (loop (cdr pairs)
                    (persistent-map-set acc (f (car kv)) (cdr kv))))]))]
      [(hash-table? m)
       (let ([new (make-hash-table)])
         (for-each
           (lambda (k) (hash-put! new (f k) (hash-ref m k)))
           (hash-keys m))
         new)]
      [else (error 'update-keys "not a map" m)]))

  ;; ---- map-indexed / keep-indexed -------------------------------
  ;;
  ;; (map-indexed (lambda (i x) ...) coll)  → list
  ;; (keep-indexed F coll) — drop entries where F returns #f.

  (define (%coerce-to-seq coll)
    (cond
      [(list? coll) coll]
      [(vector? coll) (vector->list coll)]
      [(persistent-vector? coll) (persistent-vector->list coll)]
      [(string? coll) (string->list coll)]
      [else (error 'map-indexed "unsupported collection" coll)]))

  (define (map-indexed f coll)
    (let loop ([i 0] [xs (%coerce-to-seq coll)] [acc '()])
      (cond
        [(null? xs) (reverse acc)]
        [else (loop (+ i 1) (cdr xs) (cons (f i (car xs)) acc))])))

  (define (keep-indexed f coll)
    (let loop ([i 0] [xs (%coerce-to-seq coll)] [acc '()])
      (cond
        [(null? xs) (reverse acc)]
        [else
         (let ([v (f i (car xs))])
           (loop (+ i 1) (cdr xs)
                 (if v (cons v acc) acc)))])))

  ;; ---- if-some / when-some -------------------------------------
  ;;
  ;; Same shape as if-let / when-let, but the binding is non-#f only
  ;; — useful when `#f` itself is a meaningful value in the falsy slot.

  (define-syntax if-some
    (syntax-rules ()
      [(_ (var expr) then) (if-some (var expr) then (if #f #f))]
      [(_ (var expr) then else)
       (let ([var expr])
         (if (eq? var #f) else then))]))

  (define-syntax when-some
    (syntax-rules ()
      [(_ (var expr) body ...)
       (let ([var expr])
         (if (eq? var #f) (if #f #f) (begin body ...)))]))

  ;; ---- condp ---------------------------------------------------
  ;;
  ;; (condp PRED EXPR
  ;;    test1 result1
  ;;    test2 :>> handler2
  ;;    default)
  ;;
  ;; Each test is fed to (PRED test EXPR).  If truthy, the matching
  ;; result is returned (or the truthy value is fed into handler2 when
  ;; the `:>>` form is used).  The trailing single expression is the
  ;; default; an absent default raises.

  ;; The Clojure-native `:>>` literal is unreachable in default
  ;; Jerboa reader mode (`:>>` reads as a Gerbil-style module path),
  ;; so we additionally accept `=>` — already familiar from `cond`'s
  ;; bind-arrow.  Both literals are equivalent.
  (define-syntax condp
    (syntax-rules (:>> =>)
      [(_ pred expr default)
       default]
      [(_ pred expr test :>> handler more ...)
       (let ([%v ((lambda (p e t) (p t e)) pred expr test)])
         (if %v
             (handler %v)
             (condp pred expr more ...)))]
      [(_ pred expr test => handler more ...)
       (let ([%v ((lambda (p e t) (p t e)) pred expr test)])
         (if %v
             (handler %v)
             (condp pred expr more ...)))]
      [(_ pred expr test result more ...)
       (if ((lambda (p e t) (p t e)) pred expr test)
           result
           (condp pred expr more ...))]
      [(_ pred expr)
       (error 'condp "no matching clause")]))

  ;; ---- letfn ---------------------------------------------------
  ;;
  ;; Mutual recursion sugar: (letfn [(f [x] ...) (g [x] ...)] body ...)

  (define-syntax letfn
    (syntax-rules ()
      [(_ ((name (arg ...) body ...) ...) expr ...)
       (letrec ((name (lambda (arg ...) body ...)) ...)
         expr ...)]))

  ;; ---- case-let ------------------------------------------------
  ;;
  ;; (case-let [v expr] (k1 r1) ... (else d))
  ;; Equivalent to (let ([v expr]) (case v ...))

  (define-syntax case-let
    (syntax-rules ()
      [(_ (var expr) clause ...)
       (let ([var expr]) (case var clause ...))]))

  ;; ---- NaN? / abs / not-empty / iteration ----------------------

  (define (NaN? x)
    (and (number? x) (or (and (real? x) (nan? x))
                         (and (complex? x)
                              (or (nan? (real-part x))
                                  (nan? (imag-part x)))))))

  ;; Chez has `abs` already; re-export under the same name so users
  ;; pulling (std clojure) get it without a separate (chezscheme) import.
  ;; (chezscheme) re-imports already in this library make this a no-op
  ;; if `abs` was not excluded — it was not, so the binding is just
  ;; re-exported.
  ;; (No explicit definition needed.)

  (define (not-empty x)
    (cond
      [(null? x) #f]
      [(string? x) (and (not (zero? (string-length x))) x)]
      [(vector? x) (and (not (zero? (vector-length x))) x)]
      [(persistent-map? x)
       (and (not (zero? (persistent-map-size x))) x)]
      [(persistent-vector? x)
       (and (not (zero? (persistent-vector-length x))) x)]
      [(persistent-set? x)
       (and (not (zero? (persistent-set-size x))) x)]
      [(hash-table? x)
       (and (not (zero? (length (hash-keys x)))) x)]
      [(pair? x) x]
      [else x]))

  ;; ---- iteration -----------------------------------------------
  ;;
  ;; (iteration step :somef pred :vf project :kf next-key :initk k0)
  ;;
  ;; Returns a lazy sequence of items by repeatedly calling
  ;;   (step k)
  ;; whose result is fed through :somef? to detect end, :vf to project
  ;; the page into a value, and :kf to compute the next key.  Mirrors
  ;; clojure.core/iteration (Clojure 1.11) for paginated APIs.
  ;;
  ;; Returns a plain list of projected items because Jerboa's
  ;; (std clojure) lazy-seq surface is already a separate package; we
  ;; eagerly materialise.  Replace with (lazy-seq ...) wrapper if a
  ;; truly lazy iteration is needed.

  (define iteration
    (case-lambda
      [(step) (iteration step (lambda (x) #t) (lambda (x) x) (lambda (x) #f) #f)]
      [(step somef vf kf initk)
       (let loop ([k initk] [acc '()])
         (let ([page (step k)])
           (cond
             [(somef page)
              (let ([item (vf page)]
                    [next (kf page)])
                (cond
                  [next (loop next (cons item acc))]
                  [else (reverse (cons item acc))]))]
             [else (reverse acc)])))]))

) ;; end library
