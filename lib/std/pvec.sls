#!chezscheme
;;; (std pvec) -- Persistent Vectors
;;;
;;; Immutable 32-way branching trie with tail optimization.
;;; O(log_32 n) ≈ O(1) for ref, set, append.
;;; Structural sharing: modifications return new vectors sharing unchanged nodes.
;;;
;;; Based on Clojure's PersistentVector design by Rich Hickey.

(library (std pvec)
  (export
    ;; Construction
    persistent-vector pvec-empty list->persistent-vector
    ;; Type predicate
    persistent-vector?
    ;; Access
    persistent-vector-length persistent-vector-ref
    ;; Functional update
    persistent-vector-set persistent-vector-append
    ;; Derived operations
    persistent-vector->list persistent-vector-for-each
    persistent-vector-map persistent-vector-fold persistent-vector-filter
    persistent-vector-concat persistent-vector-slice persistent-vector-prepend
    ;; Transients: batch mutation without per-step copying
    transient transient? transient-ref transient-set! transient-append! persistent!
    ;; Structural equality / hashing
    persistent-vector=? persistent-vector-hash)

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

  ;;; ========== Constants ==========
  (define BITS      5)          ; bits per level
  (define BRANCHING 32)         ; 2^BITS: branching factor
  (define MASK      31)         ; BRANCHING - 1: low-bits mask

  ;;; ========== Internal: trie node ==========
  ;; Each node is a vector of up to BRANCHING elements.
  ;; Inner nodes contain child nodes; leaf nodes contain values.
  (define-record-type pvec-node
    (fields (mutable array))
    (protocol (lambda (new) (lambda (arr) (new arr)))))

  ;;; ========== Public: persistent vector ==========
  ;; count  — total element count
  ;; shift  — tree height in bits (BITS per level; starts at BITS, grows by BITS)
  ;; root   — trie root (pvec-node)
  ;; tail   — vector of the last up-to-32 elements (not in trie)
  (define-record-type %pvec
    (fields count shift root tail))

  (define (persistent-vector? x) (%pvec? x))
  (define (persistent-vector-length v) (%pvec-count v))

  ;; Shared empty-node and empty vector
  (define empty-node (make-pvec-node (make-vector BRANCHING #f)))
  (define pvec-empty (make-%pvec 0 BITS empty-node '#()))

  ;;; ========== Tail-offset ==========
  ;; Elements [0, tail-off) are in the trie.
  ;; Elements [tail-off, count) are in the tail.
  ;; tail-off is always a multiple of BRANCHING.
  (define (pvec-tail-off v)
    (let ([count (%pvec-count v)])
      (if (< count BRANCHING)
        0
        ;; ((count - 1) >> BITS) << BITS
        (bitwise-arithmetic-shift
          (bitwise-arithmetic-shift (- count 1) (- BITS))
          BITS))))

  ;;; ========== Locate the array containing index i ==========
  (define (pvec-array-for v i)
    (let ([count (%pvec-count v)])
      (when (or (< i 0) (>= i count))
        (error 'persistent-vector-ref "index out of bounds" i count))
      (if (>= i (pvec-tail-off v))
        ;; Element is in the tail
        (%pvec-tail v)
        ;; Navigate trie top-down
        (let loop ([node (%pvec-root v)] [level (%pvec-shift v)])
          (if (> level 0)
            (loop
              (vector-ref (pvec-node-array node)
                          (bitwise-and (bitwise-arithmetic-shift i (- level)) MASK))
              (- level BITS))
            ;; level = 0: reached leaf node; return its array
            (pvec-node-array node))))))

  ;;; ========== Ref ==========
  (define (persistent-vector-ref v i)
    (vector-ref (pvec-array-for v i) (bitwise-and i MASK)))

  ;;; ========== Path-copy set (trie portion) ==========
  ;; Returns a new node with the value at position i updated.
  (define (pvec-assoc-node node level i val)
    (let ([arr (vector-copy (pvec-node-array node))])
      (if (= level 0)
        ;; Leaf: update element
        (begin
          (vector-set! arr (bitwise-and i MASK) val)
          (make-pvec-node arr))
        ;; Inner: recurse into the correct child
        (let ([subidx (bitwise-and (bitwise-arithmetic-shift i (- level)) MASK)])
          (vector-set! arr subidx
            (pvec-assoc-node (vector-ref arr subidx) (- level BITS) i val))
          (make-pvec-node arr)))))

  ;;; ========== Set ==========
  (define (persistent-vector-set v i val)
    (let ([count (%pvec-count v)]
          [shift (%pvec-shift v)])
      (when (or (< i 0) (>= i count))
        (error 'persistent-vector-set "index out of bounds" i count))
      (if (>= i (pvec-tail-off v))
        ;; In tail: copy and update
        (let ([new-tail (vector-copy (%pvec-tail v))])
          (vector-set! new-tail (- i (pvec-tail-off v)) val)
          (make-%pvec count shift (%pvec-root v) new-tail))
        ;; In trie: path copy
        (make-%pvec count shift
          (pvec-assoc-node (%pvec-root v) shift i val)
          (%pvec-tail v)))))

  ;;; ========== Push tail into trie (when tail is full) ==========
  ;; count: count before appending new element (tail is full at this point)
  (define (pvec-push-tail count level parent tail-node)
    (let* ([arr (vector-copy (pvec-node-array parent))]
           [subidx (bitwise-and
                     (bitwise-arithmetic-shift (- count 1) (- level))
                     MASK)])
      (if (= level BITS)
        ;; At leaf of inner tree: place tail-node here
        (begin
          (vector-set! arr subidx tail-node)
          (make-pvec-node arr))
        ;; Inner level: recurse or create new path
        (let ([child (vector-ref arr subidx)])
          (if child
            (begin
              (vector-set! arr subidx
                (pvec-push-tail count (- level BITS) child tail-node))
              (make-pvec-node arr))
            (begin
              (vector-set! arr subidx
                (pvec-new-path (- level BITS) tail-node))
              (make-pvec-node arr)))))))

  ;; Create a new right-spine path of inner nodes leading to tail-node at level 0
  (define (pvec-new-path level node)
    (if (= level 0)
      node
      (let ([arr (make-vector BRANCHING #f)])
        (vector-set! arr 0 (pvec-new-path (- level BITS) node))
        (make-pvec-node arr))))

  ;;; ========== Append ==========
  (define (persistent-vector-append v val)
    (let* ([count (%pvec-count v)]
           [shift (%pvec-shift v)]
           [tail  (%pvec-tail v)]
           [tail-len (vector-length tail)])
      (if (< tail-len BRANCHING)
        ;; Tail has room: extend it
        (let ([new-tail (make-vector (+ tail-len 1))])
          (vec-copy! tail 0 new-tail 0 tail-len)
          (vector-set! new-tail tail-len val)
          (make-%pvec (+ count 1) shift (%pvec-root v) new-tail))
        ;; Tail is full: push tail into trie, start new tail
        (let* ([tail-node (make-pvec-node tail)]
               [new-tail  (vector val)]
               ;; Root overflow: (count >> BITS) > (1 << shift)
               [overflow? (> (bitwise-arithmetic-shift count (- BITS))
                             (bitwise-arithmetic-shift 1 shift))])
          (if overflow?
            ;; Grow tree height by one level
            (let ([new-root-arr (make-vector BRANCHING #f)])
              (vector-set! new-root-arr 0 (%pvec-root v))
              (vector-set! new-root-arr 1 (pvec-new-path shift tail-node))
              (make-%pvec (+ count 1) (+ shift BITS)
                (make-pvec-node new-root-arr)
                new-tail))
            ;; Room in existing trie
            (make-%pvec (+ count 1) shift
              (pvec-push-tail count shift (%pvec-root v) tail-node)
              new-tail))))))

  ;;; ========== Construction ==========
  (define (persistent-vector . args)
    (let loop ([v pvec-empty] [lst args])
      (if (null? lst)
        v
        (loop (persistent-vector-append v (car lst)) (cdr lst)))))

  (define (list->persistent-vector lst)
    (let loop ([v pvec-empty] [lst lst])
      (if (null? lst)
        v
        (loop (persistent-vector-append v (car lst)) (cdr lst)))))

  ;;; ========== Iteration ==========
  (define (persistent-vector->list v)
    (let ([count (%pvec-count v)])
      (let loop ([i (- count 1)] [acc '()])
        (if (< i 0)
          acc
          (loop (- i 1) (cons (persistent-vector-ref v i) acc))))))

  (define (persistent-vector-for-each proc v)
    (let ([count (%pvec-count v)])
      (do ([i 0 (+ i 1)])
          ((= i count))
        (proc (persistent-vector-ref v i)))))

  (define (persistent-vector-map proc v)
    (let ([count (%pvec-count v)])
      (let loop ([i 0] [result pvec-empty])
        (if (= i count)
          result
          (loop (+ i 1)
            (persistent-vector-append result
              (proc (persistent-vector-ref v i))))))))

  (define (persistent-vector-fold proc init v)
    (let ([count (%pvec-count v)])
      (let loop ([i 0] [acc init])
        (if (= i count)
          acc
          (loop (+ i 1) (proc acc (persistent-vector-ref v i)))))))

  (define (persistent-vector-filter pred v)
    (persistent-vector-fold
      (lambda (acc x) (if (pred x) (persistent-vector-append acc x) acc))
      pvec-empty v))

  (define (persistent-vector-concat v1 v2)
    (persistent-vector-fold
      (lambda (acc x) (persistent-vector-append acc x))
      v1 v2))

  (define (persistent-vector-slice v start end)
    (let* ([count (%pvec-count v)]
           [s (max 0 start)]
           [e (min count end)])
      (let loop ([i s] [result pvec-empty])
        (if (>= i e)
          result
          (loop (+ i 1)
            (persistent-vector-append result (persistent-vector-ref v i)))))))

  (define (persistent-vector-prepend v val)
    ;; O(n) — prepend by appending val to empty then concat with v
    (let ([result (persistent-vector val)])
      (persistent-vector-concat result v)))

  ;;; ========== Transients ==========
  ;; Transients allow O(1) mutations for batch operations.
  ;; Create with (transient v), mutate with transient-set! / transient-append!,
  ;; convert back with (persistent! t).
  ;;
  ;; Simple implementation: backed by a growable mutable vector.
  ;; Can be upgraded to a true transient trie for better performance.

  (define-record-type %transient
    (fields (mutable items) (mutable count) (mutable done?))
    (protocol (lambda (new)
      (lambda (items count) (new items count #f)))))

  (define (transient? x) (%transient? x))

  (define (transient v)
    (let* ([count (%pvec-count v)]
           [cap   (max count 16)]
           [items (make-vector cap)])
      (do ([i 0 (+ i 1)])
          ((= i count))
        (vector-set! items i (persistent-vector-ref v i)))
      (make-%transient items count)))

  (define (transient-check! t who)
    (unless (%transient? t)
      (error who "not a transient" t))
    (when (%transient-done? t)
      (error who "transient already converted to persistent — cannot reuse" t)))

  (define (transient-ref t i)
    (transient-check! t 'transient-ref)
    (when (or (< i 0) (>= i (%transient-count t)))
      (error 'transient-ref "index out of bounds" i))
    (vector-ref (%transient-items t) i))

  (define (transient-set! t i val)
    (transient-check! t 'transient-set!)
    (when (or (< i 0) (>= i (%transient-count t)))
      (error 'transient-set! "index out of bounds" i))
    (vector-set! (%transient-items t) i val))

  (define (transient-append! t val)
    (transient-check! t 'transient-append!)
    (let* ([count (%transient-count t)]
           [items (%transient-items t)]
           [cap   (vector-length items)])
      (when (= count cap)
        (let ([new-items (make-vector (max 16 (* 2 cap)))])
          (vec-copy! items 0 new-items 0 count)
          (%transient-items-set! t new-items)
          (set! items new-items)))
      (vector-set! items count val)
      (%transient-count-set! t (+ count 1))))

  (define (persistent! t)
    (transient-check! t 'persistent!)
    (%transient-done?-set! t #t)
    (let* ([count (%transient-count t)]
           [items (%transient-items t)])
      (let loop ([i 0] [v pvec-empty])
        (if (= i count)
          v
          (loop (+ i 1) (persistent-vector-append v (vector-ref items i)))))))

  ;;; ========== Structural equality ==========
  ;; Element order matters: two pvecs are equal iff they have the same
  ;; length and corresponding elements are pvec-val=?.
  (define (pvec-val=? a b)
    (cond
      [(and (%pvec? a) (%pvec? b)) (persistent-vector=? a b)]
      [(and (pair? a) (pair? b))
       (and (pvec-val=? (car a) (car b))
            (pvec-val=? (cdr a) (cdr b)))]
      [(and (vector? a) (vector? b))
       (let ([la (vector-length a)])
         (and (= la (vector-length b))
              (let loop ([i 0])
                (cond
                  [(= i la) #t]
                  [(pvec-val=? (vector-ref a i) (vector-ref b i))
                   (loop (+ i 1))]
                  [else #f]))))]
      [else (equal? a b)]))

  (define (persistent-vector=? v1 v2)
    (cond
      [(eq? v1 v2) #t]
      [(not (%pvec? v1)) #f]
      [(not (%pvec? v2)) #f]
      [(not (= (%pvec-count v1) (%pvec-count v2))) #f]
      [else
       (let ([n (%pvec-count v1)])
         (let loop ([i 0])
           (cond
             [(= i n) #t]
             [(pvec-val=? (persistent-vector-ref v1 i)
                          (persistent-vector-ref v2 i))
              (loop (+ i 1))]
             [else #f])))]))

  ;;; ========== Structural hash ==========
  ;; Order-dependent: each element's hash is position-mixed so that
  ;; reversing the vector changes the hash.
  (define (pvec-val-hash x)
    (cond
      [(%pvec? x) (persistent-vector-hash x)]
      [(pair? x)
       (bitwise-xor (pvec-val-hash (car x))
                    (bitwise-arithmetic-shift (pvec-val-hash (cdr x)) 1))]
      [(vector? x)
       (let ([len (vector-length x)])
         (let loop ([i 0] [h len])
           (if (= i len)
               h
               (loop (+ i 1)
                     (bitwise-xor h
                       (bitwise-arithmetic-shift
                         (pvec-val-hash (vector-ref x i)) 3))))))]
      [else (equal-hash x)]))

  (define (persistent-vector-hash v)
    (let ([n (%pvec-count v)])
      (let loop ([i 0] [h n])
        (if (= i n)
            h
            (loop (+ i 1)
                  (bitwise-xor
                    (bitwise-arithmetic-shift h 5)
                    (pvec-val-hash (persistent-vector-ref v i))))))))

  ;;; ========== Chez equal? / equal-hash integration ==========
  (record-type-equal-procedure (record-type-descriptor %pvec)
    (lambda (a b rec-equal?) (persistent-vector=? a b)))
  (record-type-hash-procedure (record-type-descriptor %pvec)
    (lambda (v rec-hash) (persistent-vector-hash v)))

  ;;; ========== Printer ==========
  ;; Surface form: [e1 e2 e3]. Square brackets distinguish from plain
  ;; Chez vectors (#(...)). Not round-trippable without a reader macro.
  (record-writer (record-type-descriptor %pvec)
    (lambda (v port wr)
      (write-char #\[ port)
      (let ([n (%pvec-count v)])
        (let loop ([i 0])
          (when (< i n)
            (unless (= i 0) (write-char #\space port))
            (wr (persistent-vector-ref v i) port)
            (loop (+ i 1)))))
      (write-char #\] port)))

) ;; end library
