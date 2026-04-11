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
    ;; Merge / set operations
    persistent-map-merge persistent-map-diff)

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

  ;; Leaf: a single key-value pair
  (define-record-type hamt-leaf
    (fields key val))

  ;; Interior node: sparse array indexed by 5-bit hash chunks
  ;; bitmap: 32-bit integer where bit k means slot k is occupied
  ;; array:  compact vector of occupied children (length = popcount(bitmap))
  (define-record-type hamt-node
    (fields bitmap array))

  ;; Collision bucket: multiple keys with the exact same hash
  (define-record-type hamt-coll
    (fields hash pairs))  ; pairs = list of (key . val)

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
    (let loop ([kv kv-args] [m pmap-empty])
      (if (null? kv)
        m
        (loop (cddr kv) (persistent-map-set m (car kv) (cadr kv))))))

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
      (make-hamt-coll hash1
        (list (cons (hamt-leaf-key leaf1) (hamt-leaf-val leaf1))
              (cons (hamt-leaf-key leaf2) (hamt-leaf-val leaf2))))
      ;; Hashes differ — create interior node
      (let ([bit1 (hamt-bitpos hash1 shift)]
            [bit2 (hamt-bitpos hash2 shift)])
        (if (= bit1 bit2)
          ;; Still collide at this level — recurse one level down
          (make-hamt-node bit1
            (vector (hamt-merge-leaves leaf1 hash1 leaf2 hash2
                                       (+ shift BITS) equal-proc)))
          ;; Different slots — place each in its slot
          (if (< bit1 bit2)
            (make-hamt-node (bitwise-ior bit1 bit2) (vector leaf1 leaf2))
            (make-hamt-node (bitwise-ior bit1 bit2) (vector leaf2 leaf1)))))))

  ;;; ========== Insert ==========
  ;; Returns (values new-node delta-size)
  (define (hamt-set node key val key-hash shift equal-proc)
    (cond
      ;; Empty slot: create leaf
      [(not node)
       (values (make-hamt-leaf key val) 1)]

      ;; Existing leaf
      [(hamt-leaf? node)
       (if (equal-proc (hamt-leaf-key node) key)
         ;; Same key: update value (no size change)
         (values (make-hamt-leaf key val) 0)
         ;; Different key: expand into interior node
         (let ([existing-hash (equal-hash (hamt-leaf-key node))])
           (values
             (hamt-merge-leaves node existing-hash
                                (make-hamt-leaf key val) key-hash
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
               (values (make-hamt-node bitmap new-arr) delta)))
           ;; Slot empty: insert leaf here
           (let* ([len     (vector-length arr)]
                  [new-arr (make-vector (+ len 1))])
             (vec-copy! arr 0 new-arr 0 idx)
             (vector-set!  new-arr idx (make-hamt-leaf key val))
             (vec-copy! arr idx new-arr (+ idx 1) (- len idx))
             (values (make-hamt-node (bitwise-ior bitmap bit) new-arr) 1))))]

      ;; Collision bucket
      [(hamt-coll? node)
       (let ([coll-hash (hamt-coll-hash node)])
         (if (= coll-hash key-hash)
           ;; Same hash: update or extend the collision bucket
           (let* ([pairs    (hamt-coll-pairs node)]
                  [existing (assoc-with equal-proc key pairs)])
             (if existing
               (values
                 (make-hamt-coll key-hash
                   (map (lambda (p)
                          (if (equal-proc (car p) key) (cons key val) p))
                        pairs))
                 0)
               (values
                 (make-hamt-coll key-hash (cons (cons key val) pairs))
                 1)))
           ;; Different hash: create inner node discriminating at this level.
           ;; Both hashes differ somewhere; find it by checking current level.
           (let ([coll-bit (hamt-bitpos coll-hash shift)]
                 [new-bit  (hamt-bitpos key-hash  shift)])
             (if (= coll-bit new-bit)
               ;; Same slot here: go one level deeper
               (let-values ([(sub-node added)
                             (hamt-set node key val key-hash (+ shift BITS) equal-proc)])
                 (values (make-hamt-node coll-bit (vector sub-node)) added))
               ;; Different slots: create inner node with both
               (if (< coll-bit new-bit)
                 (values (make-hamt-node (bitwise-ior coll-bit new-bit)
                           (vector node (make-hamt-leaf key val))) 1)
                 (values (make-hamt-node (bitwise-ior new-bit coll-bit)
                           (vector (make-hamt-leaf key val) node)) 1))))))]))

  (define (hamt-coll->leaf pairs)
    ;; Dummy — not actually used
    (make-hamt-leaf (caar pairs) (cdar pairs)))

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
                       (values (make-hamt-node new-bitmap new-arr) #t)))
                   ;; Child updated
                   (let ([new-arr (vector-copy arr)])
                     (vector-set! new-arr idx new-child)
                     (values (make-hamt-node bitmap new-arr) #t))))))))]

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
                (values (make-hamt-leaf (caar new-pairs) (cdar new-pairs)) #t)]
               [else
                (values (make-hamt-coll key-hash new-pairs) #t)]))))]))

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
    (let ([result pmap-empty])
      (persistent-map-for-each
        (lambda (k v) (set! result (persistent-map-set result k (proc k v))))
        m)
      result))

  (define (persistent-map-fold proc init m)
    ;; proc: (acc key val) -> new-acc
    (let ([acc init])
      (persistent-map-for-each
        (lambda (k v) (set! acc (proc acc k v)))
        m)
      acc))

  (define (persistent-map-filter pred m)
    ;; pred: (key val) -> boolean
    (let ([result pmap-empty])
      (persistent-map-for-each
        (lambda (k v)
          (when (pred k v)
            (set! result (persistent-map-set result k v))))
        m)
      result))

  ;;; ========== Merge ==========
  (define (persistent-map-merge m1 m2 . merge-proc-opt)
    ;; Start with m1, fold m2's entries in.
    ;; merge-proc: (key val-from-m1 val-from-m2) -> new-val
    (let ([merge-proc (if (pair? merge-proc-opt)
                        (car merge-proc-opt)
                        (lambda (k v1 v2) v2))])
      (persistent-map-fold
        (lambda (acc k v)
          (if (persistent-map-has? acc k)
            (persistent-map-set acc k
              (merge-proc k (persistent-map-ref acc k) v))
            (persistent-map-set acc k v)))
        m1 m2)))

  ;;; ========== Diff ==========
  (define (persistent-map-diff m1 m2)
    ;; Keys in m1 that are not in m2
    (persistent-map-filter
      (lambda (k v) (not (persistent-map-has? m2 k)))
      m1))

) ;; end library
