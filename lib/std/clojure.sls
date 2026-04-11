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
    merge update select-keys
    first rest next last
    conj cons* empty?
    peek pop
    reduce into range
    seq =? hash
    inc dec
    nil? some? true? false?

    ;; ---- Transients (Clojure-style polymorphic dispatch) ----
    transient persistent! transient?
    assoc! dissoc! conj!

    ;; ---- Sets ----
    hash-set set set?
    disj
    union intersection difference subset? superset?

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
    atom atom? deref reset! swap! compare-and-set!
    add-watch! remove-watch!
    volatile! volatile? vreset! vswap! vderef

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
    sorted-set-fold)

  (import (except (chezscheme)
                  make-hash-table hash-table?
                  assoc iota 1+ 1-
                  atom?
                  merge merge!
                  list*
                  meta)
          (except (jerboa runtime) cons* hash-map)
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
          (std misc atom)
          (std misc meta)
          (std misc nested)
          (std pqueue)
          (std sorted-set))

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
          (let loop ([i (- n 1)] [out tail])
            (if (< i 0)
                out
                (loop (- i 1)
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
                (let loop ([i 0])
                  (cond
                    [(= i n) (walk (record-type-parent r))]
                    [(eq? (vector-ref names i) name)
                     ((record-accessor r i) rec)]
                    [else (loop (+ i 1))])))]))])))

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
                  (let loop ([i 0])
                    (cond
                      [(= i n) (walk (record-type-parent r))]
                      [(eq? (vector-ref names i) name) #t]
                      [else (loop (+ i 1))])))])))))

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
    (let loop ([fields (%record-fields-all rec)] [m pmap-empty])
      (if (null? fields)
          m
          (let ([pair (car fields)])
            (loop (cdr fields)
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
       (let loop ([m (persistent-map-set coll key val)] [rest more])
         (cond
           [(null? rest) m]
           [(null? (cdr rest))
            (error 'assoc "odd number of key/value arguments" more)]
           [else
            (loop (persistent-map-set m (car rest) (cadr rest))
                  (cddr rest))]))]
      [(concurrent-hash? coll)
       (concurrent-hash-put! coll key val)
       (let loop ([rest more])
         (cond
           [(null? rest) coll]
           [(null? (cdr rest))
            (error 'assoc "odd number of key/value arguments" more)]
           [else
            (concurrent-hash-put! coll (car rest) (cadr rest))
            (loop (cddr rest))]))]
      [(hash-table? coll)
       (hash-put! coll key val)
       (let loop ([rest more])
         (cond
           [(null? rest) coll]
           [(null? (cdr rest))
            (error 'assoc "odd number of key/value arguments" more)]
           [else
            (hash-put! coll (car rest) (cadr rest))
            (loop (cddr rest))]))]
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
       (let loop ([m coll] [rest ks])
         (if (null? rest)
             m
             (loop (persistent-map-delete m (car rest)) (cdr rest))))]
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
       (let loop ([m pmap-empty] [rest ks])
         (if (null? rest)
             m
             (let ([k (car rest)])
               (if (persistent-map-has? coll k)
                   (loop (persistent-map-set m k (persistent-map-ref coll k))
                         (cdr rest))
                   (loop m (cdr rest))))))]
      [else
       ;; Fall back to generic via assoc
       (let loop ([acc (cond [(concurrent-hash? coll) (make-concurrent-hash)]
                             [else (make-hash-table)])]
                  [rest ks])
         (if (null? rest)
             acc
             (let ([k (car rest)])
               (when (contains? coll k)
                 (assoc acc k (get coll k)))
               (loop acc (cdr rest)))))]))

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
       (let loop ([acc (car maps)] [rest (cdr maps)])
         (if (null? rest)
             acc
             (loop (persistent-map-merge acc (car rest)) (cdr rest))))]
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
             (let loop ([i (- n 1)] [acc '()])
               (if (= i 0) acc (loop (- i 1) (cons (vector-ref coll i) acc))))))]
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
       (let loop ([c coll])
         (if (null? (cdr c)) (car c) (loop (cdr c))))]
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
       (let loop ([c coll] [rest xs])
         (if (null? rest) c (loop (cons (car rest) c) (cdr rest))))]
      [(vector? coll)
       ;; Build a new vector
       (list->vector (append (vector->list coll) xs))]
      [(persistent-vector? coll)
       (let loop ([v coll] [rest xs])
         (if (null? rest) v
             (loop (persistent-vector-append v (car rest)) (cdr rest))))]
      [(pqueue? coll)
       ;; NOTE: pqueue? is srfi-134's ideque predicate, which is a
       ;; superset of "queue" — any ideque passed in is treated as a
       ;; queue. This branch must precede the persistent-map? check
       ;; because ideques are records distinct from pmap, but we want
       ;; the polymorphism to be unambiguous.
       (let loop ([q coll] [rest xs])
         (if (null? rest) q
             (loop (pqueue-conj q (car rest)) (cdr rest))))]
      [(persistent-map? coll)
       ;; Expect (k . v) pairs or (list k v)
       (let loop ([m coll] [rest xs])
         (if (null? rest)
             m
             (let ([entry (car rest)])
               (cond
                 [(pair? entry)
                  (loop (persistent-map-set m (car entry)
                           (if (pair? (cdr entry)) (cadr entry) (cdr entry)))
                        (cdr rest))]
                 [else
                  (error 'conj "cannot conj non-pair onto map" entry)]))))]
      [(persistent-set? coll)
       (let loop ([s coll] [rest xs])
         (if (null? rest) s
             (loop (persistent-set-add s (car rest)) (cdr rest))))]
      [(sorted-set? coll)
       (let loop ([s coll] [rest xs])
         (if (null? rest) s
             (loop (sorted-set-add s (car rest)) (cdr rest))))]
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
          (let loop ([acc init] [c coll])
            (if (null? c) acc (loop (f acc (car c)) (cdr c))))]
         [(vector? coll)
          (let ([n (vector-length coll)])
            (let loop ([acc init] [i 0])
              (if (= i n) acc (loop (f acc (vector-ref coll i)) (+ i 1)))))]
         [(persistent-map? coll)
          (persistent-map-fold (lambda (acc k v) (f acc (cons k v))) init coll)]
         [else (error 'reduce "unsupported collection type" coll)])]))

  (define (range . args)
    ;; (range)             → infinite (we return '() as a placeholder — Jerboa has no lazy)
    ;; (range end)         → 0..end-1
    ;; (range start end)   → start..end-1
    ;; (range start end step)
    (case (length args)
      [(0) (error 'range "infinite range not supported (no lazy sequences)")]
      [(1)
       (let ([end (car args)])
         (let loop ([i 0] [acc '()])
           (if (>= i end) (reverse acc) (loop (+ i 1) (cons i acc)))))]
      [(2)
       (let ([start (car args)] [end (cadr args)])
         (let loop ([i start] [acc '()])
           (if (>= i end) (reverse acc) (loop (+ i 1) (cons i acc)))))]
      [(3)
       (let ([start (car args)] [end (cadr args)] [step (caddr args)])
         (if (positive? step)
             (let loop ([i start] [acc '()])
               (if (>= i end) (reverse acc) (loop (+ i step) (cons i acc))))
             (let loop ([i start] [acc '()])
               (if (<= i end) (reverse acc) (loop (+ i step) (cons i acc))))))]
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
            (let loop ([x b] [rest more])
              (cond
                [(null? rest) #t]
                [else (and (=? x (car rest)) (loop (car rest) (cdr rest)))])))]))

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
       (let loop ([rest more])
         (cond
           [(null? rest) t]
           [(null? (cdr rest))
            (error 'assoc! "odd number of key/value arguments")]
           [else
            (assoc! t (car rest) (cadr rest))
            (loop (cddr rest))]))]))

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
       (let loop ([cur s] [rest items])
         (if (null? rest) cur
             (loop (persistent-set-remove cur (car rest)) (cdr rest))))]
      [(sorted-set? s)
       (let loop ([cur s] [rest items])
         (if (null? rest) cur
             (loop (sorted-set-remove cur (car rest)) (cdr rest))))]
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
       (let loop ([acc (car sets)] [rest (cdr sets)])
         (if (null? rest) acc
             (loop (sorted-set-fold (car rest)
                     (lambda (x a) (sorted-set-add a x))
                     acc)
                   (cdr rest))))]
      [else
       (let loop ([acc (car sets)] [rest (cdr sets)])
         (if (null? rest) acc
             (loop (persistent-set-union acc (car rest)) (cdr rest))))]))

  (define (intersection . sets)
    (cond
      [(null? sets) pset-empty]
      [(null? (cdr sets)) (car sets)]
      [(sorted-set? (car sets))
       (let loop ([acc (car sets)] [rest (cdr sets)])
         (if (null? rest) acc
             (let ([other (car rest)])
               (loop (sorted-set-fold acc
                       (lambda (x a)
                         (if (contains? other x) a (sorted-set-remove a x)))
                       acc)
                     (cdr rest)))))]
      [else
       (let loop ([acc (car sets)] [rest (cdr sets)])
         (if (null? rest) acc
             (loop (persistent-set-intersection acc (car rest)) (cdr rest))))]))

  (define (difference . sets)
    (cond
      [(null? sets) pset-empty]
      [(null? (cdr sets)) (car sets)]
      [(sorted-set? (car sets))
       (let loop ([acc (car sets)] [rest (cdr sets)])
         (if (null? rest) acc
             (loop (sorted-set-fold (car rest)
                     (lambda (x a) (sorted-set-remove a x))
                     acc)
                   (cdr rest))))]
      [else
       (let loop ([acc (car sets)] [rest (cdr sets)])
         (if (null? rest) acc
             (loop (persistent-set-difference acc (car rest)) (cdr rest))))]))

  (define (subset? s1 s2)
    (cond
      [(sorted-set? s1)
       (sorted-set-fold s1
         (lambda (x acc) (and acc (contains? s2 x)))
         #t)]
      [else (persistent-set-subset? s1 s2)]))

  (define (superset? s1 s2) (subset? s2 s1))

) ;; end library
