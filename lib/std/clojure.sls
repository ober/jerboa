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
    reduce into range
    inc dec
    nil? some? true? false?

    ;; ---- Transients (Clojure-style polymorphic dispatch) ----
    transient persistent! transient?
    assoc! dissoc! conj!

    ;; ---- Constructors (aliases) ----
    hash-map vec list* vector*
    hash-set make-hash-set
    ;; The prelude's mutable hash-table can still be constructed
    ;; with make-hash-table.

    ;; ---- Printing ----
    println prn pr pr-str prn-str

    ;; ---- Re-exports from (std immutable) ----
    imap imap-set imap-ref imap-has?
    ivec ivec-set ivec-ref ivec-length

    ;; ---- Re-exports from (std misc atom) ----
    atom atom? deref reset! swap! compare-and-set!

    ;; ---- Re-exports from (std misc nested) ----
    get-in assoc-in update-in)

  (import (except (chezscheme)
                  make-hash-table hash-table?
                  assoc iota 1+ 1-
                  atom?
                  merge merge!
                  list*)
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
          (std concur hash)
          (std misc atom)
          (std misc nested))

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
      [(concurrent-hash? coll) (zero? (concurrent-hash-size coll))]
      [(hash-table? coll) (zero? (hash-length coll))]
      [(vector? coll) (zero? (vector-length coll))]
      [(string? coll) (zero? (string-length coll))]
      [else (error 'empty? "unsupported collection type" coll)]))

  ;; =========================================================================
  ;; Count
  ;; =========================================================================

  (define (count coll)
    (cond
      [(null? coll) 0]
      [(pair? coll) (length coll)]
      [(persistent-map? coll) (persistent-map-size coll)]
      [(concurrent-hash? coll) (concurrent-hash-size coll)]
      [(hash-table? coll) (hash-length coll)]
      [(vector? coll) (vector-length coll)]
      [(string? coll) (string-length coll)]
      [else (error 'count "unsupported collection type" coll)]))

  ;; =========================================================================
  ;; Polymorphic single-level get
  ;; =========================================================================

  (define get
    (case-lambda
      [(coll key) (nested-get coll key #f)]
      [(coll key default) (nested-get coll key default)]))

  (define (contains? coll key)
    (cond
      [(persistent-map? coll) (persistent-map-has? coll key)]
      [(concurrent-hash? coll) (concurrent-hash-key? coll key)]
      [(hash-table? coll) (hash-key? coll key)]
      [(vector? coll)
       (and (integer? key) (exact? key) (>= key 0)
            (< key (vector-length coll)))]
      [(pair? coll) (and (assq key coll) #t)]
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
      [else (error 'keys "unsupported collection type" coll)]))

  (define (vals coll)
    (cond
      [(persistent-map? coll) (persistent-map-values coll)]
      [(concurrent-hash? coll) (concurrent-hash-values coll)]
      [(hash-table? coll) (hash-values coll)]
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
      [(vector? coll)
       (let ([n (vector-length coll)])
         (if (zero? n) #f (vector-ref coll (- n 1))))]
      [else (error 'last "unsupported collection type" coll)]))

  ;; Clojure's conj:
  ;;   - list:   prepend
  ;;   - vector: append
  ;;   - map:    must be a [k v] pair; assoc
  ;;   - set:    add element
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
      [else (error 'conj "unsupported collection type" coll)]))

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
      [else (error 'transient
                   "expected a persistent map or vector" coll)]))

  (define (transient? x)
    (or (transient-map? x) (pvec-transient? x)))

  (define (persistent! t)
    (cond
      [(transient-map? t) (persistent-map! t)]
      [(pvec-transient? t) (pvec-persistent! t)]
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

  ;; hash-set / make-hash-set placeholders — will be replaced by (std pset)
  ;; once that module lands. For now they use a hash-table with dummy values.
  (define (make-hash-set) (make-hash-table))
  (define (hash-set . items)
    (let ([h (make-hash-table)])
      (for-each (lambda (x) (hash-put! h x #t)) items)
      h))

) ;; end library
