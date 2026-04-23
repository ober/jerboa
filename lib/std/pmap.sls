#!chezscheme
;;; (std pmap) -- Persistent Hash Maps (HAMT)
;;;
;;; Immutable hash maps with structural sharing.
;;; Hash Array Mapped Trie (HAMT) with 32-way branching.
;;; O(log_32 n) ≈ O(1) for ref, set, delete.
;;;
;;; Node types:
;;;   #f              — empty slot
;;;   hamt-leaf       — single (key, value) pair
;;;   hamt-node       — interior node with bitmap and compact array
;;;   hamt-coll       — collision bucket (multiple keys with same hash)

(library (std pmap)
  (export
    ;; Construction
    persistent-map make-persistent-map pmap-empty
    ;; Type predicate
    persistent-map?
    ;; Access
    persistent-map-ref persistent-map-has? persistent-map-size
    ;; Functional update
    persistent-map-set persistent-map-delete
    ;; Derived operations
    persistent-map->list persistent-map-keys persistent-map-values
    persistent-map-for-each persistent-map-map persistent-map-fold
    persistent-map-filter
    ;; Structural equality / hashing
    persistent-map=? persistent-map-hash
    ;; Iterators (return lists compatible with std/iter's for/for/collect)
    in-pmap in-pmap-pairs in-pmap-keys in-pmap-values
    ;; Merge / set operations
    persistent-map-merge persistent-map-diff
    ;; Transients — mutable, faster for bulk construction
    transient-map transient-map?
    tmap-ref tmap-has? tmap-size
    tmap-set! tmap-delete! persistent-map!)

  (import (chezscheme))

  ;;; ========== Vector copy helper ==========
  ;; Chez Scheme's vector-copy! has non-standard argument order:
  ;;   (vector-copy! from from-start to to-start count)
  ;; We use a simple loop to avoid confusion.
  (define (vec-copy! from from-start to to-start count)
    (do ([i 0 (+ i 1)])
        ((= i count))
      (vector-set! to (+ to-start i)
                      (vector-ref from (+ from-start i)))))

  ;;; ========== Alist lookup with custom equality ==========
  ;; Chez's built-in assoc only accepts 2 arguments (key and alist).
  ;; SRFI-1's 3-arg (assoc key alist =?) is not available here, so we
  ;; hand-roll a find that consults the user-supplied equality procedure.
  (define (assoc-with equal-proc key alist)
    (cond
      [(null? alist) #f]
      [(equal-proc (caar alist) key) (car alist)]
      [else (assoc-with equal-proc key (cdr alist))]))

  ;;; ========== HAMT constants ==========
  (define BITS      5)
  (define BRANCHING 32)
  (define MASK      31)

  ;;; ========== Node records ==========
  ;;
  ;; Every node carries a mutable `edit` slot used for transient
  ;; ownership tagging (Clojure-style edit-owner protocol):
  ;;
  ;;   edit = #f          → persistent / immutable node
  ;;   edit = <box id>    → owned by the transient whose edit is the same box
  ;;
  ;; When a transient operation encounters a node whose `edit` is `eq?`
  ;; to the transient's own edit box, it mutates the node in place.
  ;; Otherwise it copies the node with the transient's edit, exactly
  ;; like Clojure's HAMT.

  ;; Leaf: a single key-value pair
  (define-record-type hamt-leaf
    (fields (mutable edit) key (mutable val)))

  ;; Interior node: sparse array indexed by 5-bit hash chunks
  ;; bitmap: 32-bit integer where bit k means slot k is occupied
  ;; array:  compact vector of occupied children (length = popcount(bitmap))
  (define-record-type hamt-node
    (fields (mutable edit) (mutable bitmap) (mutable array)))

  ;; Collision bucket: multiple keys with the exact same hash
  (define-record-type hamt-coll
    (fields (mutable edit) hash (mutable pairs)))  ; pairs = list of (key . val)

  ;;; ========== The map record ==========
  (define-record-type %pmap
    (fields root size equal-proc hash-proc))

  (define (persistent-map? x) (%pmap? x))
  (define (persistent-map-size m) (%pmap-size m))

  ;;; ========== Bit utilities ==========

  ;; Count set bits (Brian Kernighan's method)
  (define (popcount x)
    (let loop ([x x] [n 0])
      (if (= x 0) n
        (loop (bitwise-and x (- x 1)) (+ n 1)))))

  ;; The bit position for hash at a given shift level
  (define (hamt-bitpos hash shift)
    (bitwise-arithmetic-shift 1 (bitwise-and (bitwise-arithmetic-shift hash (- shift)) MASK)))

  ;; Index into the compact array for a given bit position
  (define (hamt-index bitmap bit)
    (popcount (bitwise-and bitmap (- bit 1))))

  ;;; ========== Empty map ==========
  (define pmap-empty
    (make-%pmap #f 0 equal? equal-hash))

  ;;; ========== Construction ==========
  (define (make-persistent-map . kv-args)
    ;; kv-args = key1 val1 key2 val2 ...
    ;; Uses a transient so we only allocate one %pmap record at the
    ;; end. See transient section below.
    (let ([t (transient-map pmap-empty)])
      (let loop ([kv kv-args])
        (cond
          [(null? kv) (persistent-map! t)]
          [(null? (cdr kv))
           (error 'make-persistent-map
                  "odd number of arguments — expected key/value pairs")]
          [else
           (tmap-set! t (car kv) (cadr kv))
           (loop (cddr kv))]))))

  (define (persistent-map . kv-args)
    (apply make-persistent-map kv-args))

  ;;; ========== Lookup ==========
  (define (hamt-ref node key key-hash shift equal-proc)
    (cond
      [(not node) #f]

      [(hamt-leaf? node)
       (and (equal-proc (hamt-leaf-key node) key)
            (cons (hamt-leaf-key node) (hamt-leaf-val node)))]

      [(hamt-node? node)
       (let ([bit (hamt-bitpos key-hash shift)])
         (if (not (= 0 (bitwise-and (hamt-node-bitmap node) bit)))
           (hamt-ref
             (vector-ref (hamt-node-array node)
                         (hamt-index (hamt-node-bitmap node) bit))
             key key-hash (+ shift BITS) equal-proc)
           #f))]

      [(hamt-coll? node)
       (and (= (hamt-coll-hash node) key-hash)
            (assoc-with equal-proc key (hamt-coll-pairs node)))]))

  (define (persistent-map-ref m key . default-thunk)
    (let ([result (hamt-ref (%pmap-root m) key
                             ((%pmap-hash-proc m) key)
                             0 (%pmap-equal-proc m))])
      (cond
        [result (cdr result)]
        [(pair? default-thunk) ((car default-thunk))]
        [else (error 'persistent-map-ref "key not found" key)])))

  (define (persistent-map-has? m key)
    (and (hamt-ref (%pmap-root m) key
                   ((%pmap-hash-proc m) key)
                   0 (%pmap-equal-proc m))
         #t))

  ;;; ========== Merge two leaf nodes at a collision point ==========
  (define (hamt-merge-leaves leaf1 hash1 leaf2 hash2 shift equal-proc)
    (if (= hash1 hash2)
      ;; True hash collision — bucket them
      (make-hamt-coll #f hash1
        (list (cons (hamt-leaf-key leaf1) (hamt-leaf-val leaf1))
              (cons (hamt-leaf-key leaf2) (hamt-leaf-val leaf2))))
      ;; Hashes differ — create interior node
      (let ([bit1 (hamt-bitpos hash1 shift)]
            [bit2 (hamt-bitpos hash2 shift)])
        (if (= bit1 bit2)
          ;; Still collide at this level — recurse one level down
          (make-hamt-node #f bit1
            (vector (hamt-merge-leaves leaf1 hash1 leaf2 hash2
                                       (+ shift BITS) equal-proc)))
          ;; Different slots — place each in its slot
          (if (< bit1 bit2)
            (make-hamt-node #f (bitwise-ior bit1 bit2) (vector leaf1 leaf2))
            (make-hamt-node #f (bitwise-ior bit1 bit2) (vector leaf2 leaf1)))))))

  ;;; ========== Insert ==========
  ;; Returns (values new-node delta-size)
  (define (hamt-set node key val key-hash shift equal-proc)
    (cond
      ;; Empty slot: create leaf
      [(not node)
       (values (make-hamt-leaf #f key val) 1)]

      ;; Existing leaf
      [(hamt-leaf? node)
       (if (equal-proc (hamt-leaf-key node) key)
         ;; Same key: update value (no size change)
         (values (make-hamt-leaf #f key val) 0)
         ;; Different key: expand into interior node
         (let ([existing-hash (equal-hash (hamt-leaf-key node))])
           (values
             (hamt-merge-leaves node existing-hash
                                (make-hamt-leaf #f key val) key-hash
                                shift equal-proc)
             1)))]

      ;; Interior node
      [(hamt-node? node)
       (let* ([bit    (hamt-bitpos key-hash shift)]
              [bitmap (hamt-node-bitmap node)]
              [arr    (hamt-node-array node)]
              [idx    (hamt-index bitmap bit)])
         (if (not (= 0 (bitwise-and bitmap bit)))
           ;; Slot occupied: recurse
           (let-values ([(new-child delta)
                         (hamt-set (vector-ref arr idx) key val
                                   key-hash (+ shift BITS) equal-proc)])
             (let ([new-arr (vector-copy arr)])
               (vector-set! new-arr idx new-child)
               (values (make-hamt-node #f bitmap new-arr) delta)))
           ;; Slot empty: insert leaf here
           (let* ([len     (vector-length arr)]
                  [new-arr (make-vector (+ len 1))])
             (vec-copy! arr 0 new-arr 0 idx)
             (vector-set!  new-arr idx (make-hamt-leaf #f key val))
             (vec-copy! arr idx new-arr (+ idx 1) (- len idx))
             (values (make-hamt-node #f (bitwise-ior bitmap bit) new-arr) 1))))]

      ;; Collision bucket
      [(hamt-coll? node)
       (let ([coll-hash (hamt-coll-hash node)])
         (if (= coll-hash key-hash)
           ;; Same hash: update or extend the collision bucket
           (let* ([pairs    (hamt-coll-pairs node)]
                  [existing (assoc-with equal-proc key pairs)])
             (if existing
               (values
                 (make-hamt-coll #f key-hash
                   (map (lambda (p)
                          (if (equal-proc (car p) key) (cons key val) p))
                        pairs))
                 0)
               (values
                 (make-hamt-coll #f key-hash (cons (cons key val) pairs))
                 1)))
           ;; Different hash: create inner node discriminating at this level.
           ;; Both hashes differ somewhere; find it by checking current level.
           (let ([coll-bit (hamt-bitpos coll-hash shift)]
                 [new-bit  (hamt-bitpos key-hash  shift)])
             (if (= coll-bit new-bit)
               ;; Same slot here: go one level deeper
               (let-values ([(sub-node added)
                             (hamt-set node key val key-hash (+ shift BITS) equal-proc)])
                 (values (make-hamt-node #f coll-bit (vector sub-node)) added))
               ;; Different slots: create inner node with both
               (if (< coll-bit new-bit)
                 (values (make-hamt-node #f (bitwise-ior coll-bit new-bit)
                           (vector node (make-hamt-leaf #f key val))) 1)
                 (values (make-hamt-node #f (bitwise-ior new-bit coll-bit)
                           (vector (make-hamt-leaf #f key val) node)) 1))))))]))

  (define (hamt-coll->leaf pairs)
    ;; Dummy — not actually used
    (make-hamt-leaf #f (caar pairs) (cdar pairs)))

  (define (persistent-map-set m key val)
    (let* ([h        ((%pmap-hash-proc m) key)]
           [root     (%pmap-root m)]
           [eq-proc  (%pmap-equal-proc m)]
           [h-proc   (%pmap-hash-proc m)])
      (let-values ([(new-root delta)
                    (hamt-set root key val h 0 eq-proc)])
        (make-%pmap new-root (+ (%pmap-size m) delta) eq-proc h-proc))))

  ;;; ========== Delete ==========
  ;; Returns (values new-node removed?)
  (define (hamt-delete node key key-hash shift equal-proc)
    (cond
      [(not node)
       (values #f #f)]

      [(hamt-leaf? node)
       (if (equal-proc (hamt-leaf-key node) key)
         (values #f #t)
         (values node #f))]

      [(hamt-node? node)
       (let* ([bit    (hamt-bitpos key-hash shift)]
              [bitmap (hamt-node-bitmap node)]
              [arr    (hamt-node-array node)])
         (if (= 0 (bitwise-and bitmap bit))
           (values node #f)
           (let* ([idx   (hamt-index bitmap bit)]
                  [child (vector-ref arr idx)])
             (let-values ([(new-child removed?)
                           (hamt-delete child key key-hash (+ shift BITS) equal-proc)])
               (if (not removed?)
                 (values node #f)
                 (if (not new-child)
                   ;; Child removed entirely
                   (if (= (vector-length arr) 1)
                     ;; Node itself becomes empty
                     (values #f #t)
                     ;; Compress the array
                     (let* ([arr-len  (vector-length arr)]
                            [new-arr  (make-vector (- arr-len 1))]
                            [new-bitmap (bitwise-xor bitmap bit)])
                       (vec-copy! arr 0 new-arr 0 idx)
                       (vec-copy! arr (+ idx 1) new-arr idx (- arr-len idx 1))
                       (values (make-hamt-node #f new-bitmap new-arr) #t)))
                   ;; Child updated
                   (let ([new-arr (vector-copy arr)])
                     (vector-set! new-arr idx new-child)
                     (values (make-hamt-node #f bitmap new-arr) #t))))))))]

      [(hamt-coll? node)
       (if (not (= (hamt-coll-hash node) key-hash))
         (values node #f)
         (let* ([pairs     (hamt-coll-pairs node)]
                [new-pairs (filter (lambda (p) (not (equal-proc (car p) key))) pairs)])
           (if (= (length new-pairs) (length pairs))
             (values node #f)
             (cond
               [(null? new-pairs)
                (values #f #t)]
               [(= (length new-pairs) 1)
                (values (make-hamt-leaf #f (caar new-pairs) (cdar new-pairs)) #t)]
               [else
                (values (make-hamt-coll #f key-hash new-pairs) #t)]))))]))

  (define (persistent-map-delete m key)
    (let* ([h       ((%pmap-hash-proc m) key)]
           [root    (%pmap-root m)]
           [eq-proc (%pmap-equal-proc m)]
           [h-proc  (%pmap-hash-proc m)])
      (let-values ([(new-root removed?)
                    (hamt-delete root key h 0 eq-proc)])
        (if removed?
          (make-%pmap new-root (- (%pmap-size m) 1) eq-proc h-proc)
          m))))

  ;;; ========== Iteration ==========
  (define (hamt-for-each proc node)
    (cond
      [(not node) (void)]
      [(hamt-leaf? node) (proc (hamt-leaf-key node) (hamt-leaf-val node))]
      [(hamt-node? node)
       (vector-for-each (lambda (child) (hamt-for-each proc child))
                        (hamt-node-array node))]
      [(hamt-coll? node)
       (for-each (lambda (pair) (proc (car pair) (cdr pair)))
                 (hamt-coll-pairs node))]))

  (define (persistent-map-for-each proc m)
    (hamt-for-each proc (%pmap-root m)))

  (define (persistent-map->list m)
    (let ([result '()])
      (persistent-map-for-each
        (lambda (k v) (set! result (cons (cons k v) result)))
        m)
      result))

  (define (persistent-map-keys m)
    (map car (persistent-map->list m)))

  (define (persistent-map-values m)
    (map cdr (persistent-map->list m)))

  (define (persistent-map-map proc m)
    ;; proc: (key val) -> new-val
    ;; Uses a transient to amortize the per-entry update cost.
    (let ([t (transient-map pmap-empty)])
      (persistent-map-for-each
        (lambda (k v) (tmap-set! t k (proc k v)))
        m)
      (persistent-map! t)))

  (define (persistent-map-fold proc init m)
    ;; proc: (acc key val) -> new-acc
    (let ([acc init])
      (persistent-map-for-each
        (lambda (k v) (set! acc (proc acc k v)))
        m)
      acc))

  (define (persistent-map-filter pred m)
    ;; pred: (key val) -> boolean
    (let ([t (transient-map pmap-empty)])
      (persistent-map-for-each
        (lambda (k v)
          (when (pred k v)
            (tmap-set! t k v)))
        m)
      (persistent-map! t)))

  ;;; ========== Merge ==========
  (define (persistent-map-merge m1 m2 . merge-proc-opt)
    ;; Start with m1, fold m2's entries in.
    ;; merge-proc: (key val-from-m1 val-from-m2) -> new-val
    ;; Uses a transient over m1 for the running result.
    (let ([merge-proc (if (pair? merge-proc-opt)
                        (car merge-proc-opt)
                        (lambda (k v1 v2) v2))]
          [t (transient-map m1)])
      (persistent-map-for-each
        (lambda (k v)
          (if (tmap-has? t k)
            (tmap-set! t k (merge-proc k (tmap-ref t k) v))
            (tmap-set! t k v)))
        m2)
      (persistent-map! t)))

  ;;; ========== Diff ==========
  (define (persistent-map-diff m1 m2)
    ;; Keys in m1 that are not in m2
    (persistent-map-filter
      (lambda (k v) (not (persistent-map-has? m2 k)))
      m1))

  ;;; ========== Structural equality ==========
  ;;
  ;; Two persistent maps are equal iff they have the same size AND
  ;; every (key, value) pair in m1 is also present in m2 (with a
  ;; value that equal?'s). Size check is O(1); the membership walk
  ;; is O(n * log_32 n) ≈ O(n). Short-circuits on first mismatch via
  ;; an internal escape continuation.
  ;;
  ;; Does NOT require key order to match — HAMT iteration order is
  ;; a function of hash layout, not insertion order, so ordering is
  ;; not part of the value-equality contract.
  ;;
  ;; Values are compared with a recursive helper `pmap-val=?` so that
  ;; nested persistent maps compare structurally rather than by eq?
  ;; (Chez's equal? does not understand user-defined record types).

  (define (pmap-val=? a b)
    (cond
      [(and (%pmap? a) (%pmap? b)) (persistent-map=? a b)]
      [(and (pair? a) (pair? b))
       (and (pmap-val=? (car a) (car b))
            (pmap-val=? (cdr a) (cdr b)))]
      [(and (vector? a) (vector? b))
       (let ([la (vector-length a)])
         (and (= la (vector-length b))
              (let loop ([i 0])
                (cond
                  [(= i la) #t]
                  [(pmap-val=? (vector-ref a i) (vector-ref b i))
                   (loop (+ i 1))]
                  [else #f]))))]
      [else (equal? a b)]))

  (define (persistent-map=? m1 m2)
    (cond
      [(eq? m1 m2) #t]
      [(not (%pmap? m1)) #f]
      [(not (%pmap? m2)) #f]
      [(not (= (%pmap-size m1) (%pmap-size m2))) #f]
      [else
       (call/cc
         (lambda (return)
           (persistent-map-for-each
             (lambda (k v)
               (let ([result (hamt-ref (%pmap-root m2) k
                                       ((%pmap-hash-proc m2) k)
                                       0 (%pmap-equal-proc m2))])
                 (unless (and result (pmap-val=? (cdr result) v))
                   (return #f))))
             m1)
           #t))]))

  ;;; ========== Structural hash ==========
  ;;
  ;; Order-independent hash: combine per-entry hashes with XOR so
  ;; rearranging entries yields the same map-hash. Each entry is
  ;; hashed as (pmap-val-hash k) xor (pmap-val-hash v) which mixes
  ;; key and value. Uses a recursive helper that understands nested
  ;; %pmap values, so the invariant
  ;;   (=> (persistent-map=? m1 m2) (= (persistent-map-hash m1)
  ;;                                   (persistent-map-hash m2)))
  ;; holds even for maps whose values are themselves %pmap records
  ;; (which Chez's equal-hash compares by identity).

  (define (pmap-val-hash x)
    (cond
      [(%pmap? x) (persistent-map-hash x)]
      [(pair? x)
       ;; Cheap mixing — sensitive to position so (a . b) and (b . a)
       ;; don't collide, but still deterministic for equal values.
       (bitwise-xor (pmap-val-hash (car x))
                    (bitwise-arithmetic-shift (pmap-val-hash (cdr x)) 1))]
      [(vector? x)
       (let ([len (vector-length x)])
         (let loop ([i 0] [h len])
           (if (= i len)
               h
               (loop (+ i 1)
                     (bitwise-xor h
                       (bitwise-arithmetic-shift
                         (pmap-val-hash (vector-ref x i)) 3))))))]
      [else (equal-hash x)]))

  (define (persistent-map-hash m)
    (let ([h 0])
      (persistent-map-for-each
        (lambda (k v)
          ;; Combine k and v with a non-linear mix so swapping
          ;; two entries' halves can't alias in the global XOR.
          (set! h (bitwise-xor h
                    (bitwise-xor (pmap-val-hash k)
                      (bitwise-arithmetic-shift (pmap-val-hash v) 1)))))
        m)
      ;; Mix size in so empty vs. full-of-zeros don't collide.
      (bitwise-xor h (equal-hash (%pmap-size m)))))

  ;;; ========== Iterators ==========
  ;;
  ;; (std iter)'s for/for-collect/for/fold walk plain lists, so each
  ;; iterator here materializes the map into a list. This matches the
  ;; existing in-hash-keys / in-hash-values / in-hash-pairs pattern.

  (define (in-pmap-keys m)
    (persistent-map-keys m))

  (define (in-pmap-values m)
    (persistent-map-values m))

  (define (in-pmap-pairs m)
    (persistent-map->list m))

  ;; `in-pmap` — default iterator yields (key . val) pairs, matching
  ;; Clojure's (for [[k v] m] ...) idiom once users destructure.
  (define in-pmap in-pmap-pairs)

  ;;; ========== Transients ==========
  ;;
  ;; A transient-map is a mutable wrapper around a HAMT root that
  ;; lets Clojure users express bulk construction idiomatically:
  ;;
  ;;   (def t (transient-map pmap-empty))
  ;;   (for ([i (in-range 1000)]) (tmap-set! t i (* i i)))
  ;;   (def m (persistent-map! t))     ;; invalidates t
  ;;
  ;; Edit-owner protocol (matches Clojure's transient semantics):
  ;;
  ;; Every HAMT node carries a mutable `edit` slot. Persistent nodes
  ;; have edit = #f. When a transient is created, it gets a fresh
  ;; "edit token" — a mutable box containing #t. All nodes created
  ;; or copied by that transient share the same edit box.
  ;;
  ;; On mutation (tmap-set!, tmap-delete!), the edit-aware HAMT
  ;; operations check `(eq? (node-edit node) edit)`:
  ;;   - Match: mutate the node in place (no allocation).
  ;;   - Mismatch: copy the node with the transient's edit, then mutate.
  ;;
  ;; `persistent-map!` sets the edit box's contents to #f, which:
  ;;   1. Prevents further transient mutations (the `tmap-check` guard
  ;;      reads the box and rejects #f).
  ;;   2. Ensures any nodes still referencing this edit are never
  ;;      mutated again — their edit box now contains #f, which won't
  ;;      `eq?`-match any future transient's edit box.
  ;;
  ;; This is the standard Clojure approach adapted for Chez Scheme:
  ;; Clojure uses AtomicReference<Thread>; we use (box #t) / (box #f)
  ;; with `eq?` identity comparison on the box itself.

  (define-record-type %tmap
    (fields
      (mutable root)
      (mutable size)
      equal-proc
      hash-proc
      edit))  ; a mutable box: (box #t) when live, set to #f on persist

  (define (transient-map? x) (%tmap? x))

  (define (tmap-live? t)
    (unbox (%tmap-edit t)))

  (define (transient-map m)
    ;; Create a transient from a persistent map. A fresh edit box
    ;; is allocated — it becomes the ownership token for all nodes
    ;; created or adopted by this transient's mutations.
    (unless (persistent-map? m)
      (error 'transient-map "expected a persistent-map" m))
    (make-%tmap (%pmap-root m) (%pmap-size m)
                (%pmap-equal-proc m) (%pmap-hash-proc m)
                (box #t)))

  (define (tmap-check who t)
    (unless (%tmap? t)
      (error who "expected a transient-map" t))
    (unless (tmap-live? t)
      (error who "transient used after persistent!" t)))

  (define (tmap-ref t key . default-thunk)
    (tmap-check 'tmap-ref t)
    (let ([result (hamt-ref (%tmap-root t) key
                             ((%tmap-hash-proc t) key)
                             0 (%tmap-equal-proc t))])
      (cond
        [result (cdr result)]
        [(pair? default-thunk) ((car default-thunk))]
        [else (error 'tmap-ref "key not found" key)])))

  (define (tmap-has? t key)
    (tmap-check 'tmap-has? t)
    (and (hamt-ref (%tmap-root t) key
                   ((%tmap-hash-proc t) key)
                   0 (%tmap-equal-proc t))
         #t))

  (define (tmap-size t)
    (tmap-check 'tmap-size t)
    (%tmap-size t))

  ;;; ---------- Edit-aware HAMT insert (transient path) ----------
  ;;
  ;; hamt-set/edit is the transient counterpart of hamt-set. When a
  ;; node's edit is `eq?` to the transient's edit, it mutates in
  ;; place. Otherwise it copies the node (stamped with the transient's
  ;; edit) and then mutates the copy.

  ;; Ensure we have an owned (mutable) leaf for this edit.
  (define (ensure-leaf-edit leaf edit)
    (if (eq? (hamt-leaf-edit leaf) edit)
      leaf
      (make-hamt-leaf edit (hamt-leaf-key leaf) (hamt-leaf-val leaf))))

  ;; Ensure we have an owned (mutable) interior node for this edit.
  (define (ensure-node-edit node edit)
    (if (eq? (hamt-node-edit node) edit)
      node
      (make-hamt-node edit (hamt-node-bitmap node)
                      (vector-copy (hamt-node-array node)))))

  ;; Ensure we have an owned (mutable) collision node for this edit.
  (define (ensure-coll-edit coll edit)
    (if (eq? (hamt-coll-edit coll) edit)
      coll
      (make-hamt-coll edit (hamt-coll-hash coll) (hamt-coll-pairs coll))))

  ;; Edit-aware variant of hamt-merge-leaves.
  (define (hamt-merge-leaves/edit leaf1 hash1 leaf2 hash2 shift equal-proc edit)
    (if (= hash1 hash2)
      ;; True hash collision — bucket them
      (make-hamt-coll edit hash1
        (list (cons (hamt-leaf-key leaf1) (hamt-leaf-val leaf1))
              (cons (hamt-leaf-key leaf2) (hamt-leaf-val leaf2))))
      ;; Hashes differ — create interior node
      (let ([bit1 (hamt-bitpos hash1 shift)]
            [bit2 (hamt-bitpos hash2 shift)])
        (if (= bit1 bit2)
          ;; Still collide at this level — recurse one level down
          (make-hamt-node edit bit1
            (vector (hamt-merge-leaves/edit leaf1 hash1 leaf2 hash2
                                            (+ shift BITS) equal-proc edit)))
          ;; Different slots — place each in its slot
          (if (< bit1 bit2)
            (make-hamt-node edit (bitwise-ior bit1 bit2) (vector leaf1 leaf2))
            (make-hamt-node edit (bitwise-ior bit1 bit2) (vector leaf2 leaf1)))))))

  ;; Returns (values new-node delta-size)
  (define (hamt-set/edit node key val key-hash shift equal-proc edit)
    (cond
      ;; Empty slot: create owned leaf
      [(not node)
       (values (make-hamt-leaf edit key val) 1)]

      ;; Existing leaf
      [(hamt-leaf? node)
       (if (equal-proc (hamt-leaf-key node) key)
         ;; Same key: update value in place if owned
         (let ([n (ensure-leaf-edit node edit)])
           (hamt-leaf-val-set! n val)
           (values n 0))
         ;; Different key: expand into interior node
         (let ([existing-hash (equal-hash (hamt-leaf-key node))])
           (values
             (hamt-merge-leaves/edit node existing-hash
                                     (make-hamt-leaf edit key val) key-hash
                                     shift equal-proc edit)
             1)))]

      ;; Interior node
      [(hamt-node? node)
       (let* ([bit    (hamt-bitpos key-hash shift)]
              [bitmap (hamt-node-bitmap node)]
              [arr    (hamt-node-array node)]
              [idx    (hamt-index bitmap bit)])
         (if (not (= 0 (bitwise-and bitmap bit)))
           ;; Slot occupied: recurse, then update array in place if owned
           (let-values ([(new-child delta)
                         (hamt-set/edit (vector-ref arr idx) key val
                                        key-hash (+ shift BITS) equal-proc edit)])
             (let ([n (ensure-node-edit node edit)])
               (vector-set! (hamt-node-array n) idx new-child)
               (values n delta)))
           ;; Slot empty: expand array, insert leaf
           (let* ([len     (vector-length arr)]
                  [new-arr (make-vector (+ len 1))])
             (vec-copy! arr 0 new-arr 0 idx)
             (vector-set! new-arr idx (make-hamt-leaf edit key val))
             (vec-copy! arr idx new-arr (+ idx 1) (- len idx))
             (if (eq? (hamt-node-edit node) edit)
               ;; Owned: mutate bitmap and array in place
               (begin
                 (hamt-node-bitmap-set! node (bitwise-ior bitmap bit))
                 (hamt-node-array-set! node new-arr)
                 (values node 1))
               ;; Not owned: create new node
               (values (make-hamt-node edit (bitwise-ior bitmap bit) new-arr) 1)))))]

      ;; Collision bucket
      [(hamt-coll? node)
       (let ([coll-hash (hamt-coll-hash node)])
         (if (= coll-hash key-hash)
           ;; Same hash: update or extend the collision bucket
           (let* ([pairs    (hamt-coll-pairs node)]
                  [existing (assoc-with equal-proc key pairs)])
             (let ([n (ensure-coll-edit node edit)])
               (if existing
                 (begin
                   (hamt-coll-pairs-set! n
                     (map (lambda (p)
                            (if (equal-proc (car p) key) (cons key val) p))
                          pairs))
                   (values n 0))
                 (begin
                   (hamt-coll-pairs-set! n (cons (cons key val) pairs))
                   (values n 1)))))
           ;; Different hash: create inner node discriminating at this level.
           (let ([coll-bit (hamt-bitpos coll-hash shift)]
                 [new-bit  (hamt-bitpos key-hash  shift)])
             (if (= coll-bit new-bit)
               ;; Same slot here: go one level deeper
               (let-values ([(sub-node added)
                             (hamt-set/edit node key val key-hash
                                            (+ shift BITS) equal-proc edit)])
                 (values (make-hamt-node edit coll-bit (vector sub-node)) added))
               ;; Different slots: create inner node with both
               (if (< coll-bit new-bit)
                 (values (make-hamt-node edit (bitwise-ior coll-bit new-bit)
                           (vector node (make-hamt-leaf edit key val))) 1)
                 (values (make-hamt-node edit (bitwise-ior new-bit coll-bit)
                           (vector (make-hamt-leaf edit key val) node)) 1))))))]))

  ;;; ---------- Edit-aware HAMT delete (transient path) ----------
  ;;
  ;; hamt-delete/edit is the transient counterpart of hamt-delete.
  ;; Returns (values new-node removed?).

  (define (hamt-delete/edit node key key-hash shift equal-proc edit)
    (cond
      [(not node)
       (values #f #f)]

      [(hamt-leaf? node)
       (if (equal-proc (hamt-leaf-key node) key)
         (values #f #t)
         (values node #f))]

      [(hamt-node? node)
       (let* ([bit    (hamt-bitpos key-hash shift)]
              [bitmap (hamt-node-bitmap node)]
              [arr    (hamt-node-array node)])
         (if (= 0 (bitwise-and bitmap bit))
           (values node #f)
           (let* ([idx   (hamt-index bitmap bit)]
                  [child (vector-ref arr idx)])
             (let-values ([(new-child removed?)
                           (hamt-delete/edit child key key-hash
                                             (+ shift BITS) equal-proc edit)])
               (if (not removed?)
                 (values node #f)
                 (if (not new-child)
                   ;; Child removed entirely
                   (if (= (vector-length arr) 1)
                     ;; Node itself becomes empty
                     (values #f #t)
                     ;; Compress the array (always creates a new smaller vector)
                     (let* ([arr-len    (vector-length arr)]
                            [new-arr    (make-vector (- arr-len 1))]
                            [new-bitmap (bitwise-xor bitmap bit)])
                       (vec-copy! arr 0 new-arr 0 idx)
                       (vec-copy! arr (+ idx 1) new-arr idx (- arr-len idx 1))
                       (if (eq? (hamt-node-edit node) edit)
                         ;; Owned: mutate in place
                         (begin
                           (hamt-node-bitmap-set! node new-bitmap)
                           (hamt-node-array-set! node new-arr)
                           (values node #t))
                         (values (make-hamt-node edit new-bitmap new-arr) #t))))
                   ;; Child updated (not removed, just replaced)
                   (let ([n (ensure-node-edit node edit)])
                     (vector-set! (hamt-node-array n) idx new-child)
                     (values n #t))))))))]

      [(hamt-coll? node)
       (if (not (= (hamt-coll-hash node) key-hash))
         (values node #f)
         (let* ([pairs     (hamt-coll-pairs node)]
                [new-pairs (filter (lambda (p) (not (equal-proc (car p) key))) pairs)])
           (if (= (length new-pairs) (length pairs))
             (values node #f)
             (cond
               [(null? new-pairs)
                (values #f #t)]
               [(= (length new-pairs) 1)
                (values (make-hamt-leaf edit (caar new-pairs) (cdar new-pairs)) #t)]
               [else
                (let ([n (ensure-coll-edit node edit)])
                  (hamt-coll-pairs-set! n new-pairs)
                  (values n #t))]))))]))

  (define (tmap-set! t key val)
    (tmap-check 'tmap-set! t)
    (let-values ([(new-root delta)
                  (hamt-set/edit (%tmap-root t) key val
                                 ((%tmap-hash-proc t) key)
                                 0 (%tmap-equal-proc t)
                                 (%tmap-edit t))])
      (%tmap-root-set! t new-root)
      (%tmap-size-set! t (+ (%tmap-size t) delta))
      t))

  (define (tmap-delete! t key)
    (tmap-check 'tmap-delete! t)
    (let-values ([(new-root removed?)
                  (hamt-delete/edit (%tmap-root t) key
                                    ((%tmap-hash-proc t) key)
                                    0 (%tmap-equal-proc t)
                                    (%tmap-edit t))])
      (when removed?
        (%tmap-root-set! t new-root)
        (%tmap-size-set! t (- (%tmap-size t) 1)))
      t))

  (define (persistent-map! t)
    ;; Finalize a transient back into a persistent map. Setting the
    ;; edit box to #f invalidates the transient: any further tmap-*
    ;; call raises an error (tmap-live? reads the box), and nodes
    ;; stamped with this edit will never match a future transient's
    ;; edit box, so they become effectively immutable.
    (tmap-check 'persistent-map! t)
    (set-box! (%tmap-edit t) #f)
    (make-%pmap (%tmap-root t) (%tmap-size t)
                (%tmap-equal-proc t) (%tmap-hash-proc t)))

  ;;; ========== Bulk construction via transients ==========
  ;;
  ;; make-persistent-map originally walked its arguments with
  ;; persistent-map-set, allocating a new %pmap record per key. The
  ;; transient version re-uses a single %tmap wrapper end-to-end and
  ;; produces the final %pmap only once, in persistent-map!.

  ;;; ========== Chez equal? / equal-hash integration ==========
  ;; Plumbs persistent-map=? / persistent-map-hash into Chez's generic
  ;; equality protocol so that (equal? pm1 pm2) holds when the two
  ;; maps have the same entries regardless of insertion order, and a
  ;; pmap can be used as a key in an equal-hashtable.
  (record-type-equal-procedure (record-type-descriptor %pmap)
    (lambda (a b rec-equal?) (persistent-map=? a b)))
  (record-type-hash-procedure (record-type-descriptor %pmap)
    (lambda (m rec-hash) (persistent-map-hash m)))

  ;;; ========== Printer ==========
  ;; Surface form: {k1 v1 k2 v2}. No commas, matching Clojure minus
  ;; keyword colons. Not round-trippable without a reader macro, but
  ;; readable for REPL / debugging / logs.
  (record-writer (record-type-descriptor %pmap)
    (lambda (pm port wr)
      (write-char #\{ port)
      (let ([first? #t])
        (persistent-map-for-each
          (lambda (k v)
            (if first? (set! first? #f) (write-char #\space port))
            (wr k port) (write-char #\space port) (wr v port))
          pm))
      (write-char #\} port)))

) ;; end library
