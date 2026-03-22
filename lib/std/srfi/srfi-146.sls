#!chezscheme
;;; :std/srfi/146 -- Immutable Mappings (SRFI-146)
;;; HAMT (Hash Array Mapped Trie) implementation with structural sharing.
;;; 32-way branching, 5 bits per level, bitmap-indexed nodes.

(library (std srfi srfi-146)
  (export
    mapping mapping? mapping-empty? mapping-contains?
    mapping-ref mapping-ref/default
    mapping-set mapping-delete mapping-delete-all
    mapping-update mapping-size
    mapping-keys mapping-values mapping-entries
    mapping-fold mapping-map mapping-for-each
    mapping-filter mapping-remove
    mapping-union mapping-intersection mapping-difference
    mapping->alist alist->mapping
    mapping-comparator mapping-default-comparator)

  (import (chezscheme))

  ;; ---------- Comparator access helpers ----------
  ;; Support both SRFI-128 comparator records and bare vectors.

  (define (comp-equality c)
    (cond
      [(procedure? c) c]
      [(vector? c) (vector-ref c 1)]
      [(and (record? c)
            (guard (exn [else #f])
              (let ([e ((record-accessor (record-rtd c) 1) c)])
                e)))
       => values]
      [else equal?]))

  (define (comp-hash c)
    (cond
      [(vector? c) (vector-ref c 3)]
      [(and (record? c)
            (guard (exn [else #f])
              (let ([h ((record-accessor (record-rtd c) 3) c)])
                h)))
       => values]
      [else equal-hash]))

  ;; ---------- HAMT node types ----------
  ;; Nodes: empty, leaf, or branch.
  ;; We use tagged vectors for performance:
  ;;   empty:  the symbol 'empty
  ;;   leaf:   #(leaf hash key value)
  ;;   branch: #(branch bitmap children)
  ;; children is a vector of populated child nodes only (compact).

  (define hamt-empty 'empty)

  (define (hamt-empty? n) (eq? n hamt-empty))

  (define (make-leaf hash key value)
    (vector 'leaf hash key value))

  (define (leaf? n)
    (and (vector? n) (fx> (vector-length n) 0) (eq? (vector-ref n 0) 'leaf)))

  (define (leaf-hash n) (vector-ref n 1))
  (define (leaf-key n)  (vector-ref n 2))
  (define (leaf-val n)  (vector-ref n 3))

  (define (make-branch bitmap children)
    (vector 'branch bitmap children))

  (define (branch? n)
    (and (vector? n) (fx> (vector-length n) 0) (eq? (vector-ref n 0) 'branch)))

  (define (branch-bitmap n)   (vector-ref n 1))
  (define (branch-children n) (vector-ref n 2))

  ;; Collision node: multiple entries with the same hash.
  ;; #(collision hash entries) where entries is a list of (key . value).
  (define (make-collision hash entries)
    (vector 'collision hash entries))

  (define (collision? n)
    (and (vector? n) (fx> (vector-length n) 0) (eq? (vector-ref n 0) 'collision)))

  (define (collision-hash n)    (vector-ref n 1))
  (define (collision-entries n) (vector-ref n 2))

  ;; ---------- Bit manipulation ----------

  (define bits-per-level 5)
  (define branch-factor 32)   ;; (expt 2 5)
  (define mask #x1F)          ;; (- branch-factor 1)

  (define (hash-fragment shift hash)
    (fxand (fxsrl hash shift) mask))

  (define (bit-pos frag)
    (fxsll 1 frag))

  (define (bitmap-has? bitmap bit)
    (not (fxzero? (fxand bitmap bit))))

  (define (bitmap-index bitmap bit)
    (fxpopcount (fxand bitmap (fx- bit 1))))

  ;; ---------- Vector helpers ----------

  (define (vector-insert v idx val)
    (let* ([len (vector-length v)]
           [new (make-vector (fx+ len 1))])
      (do ([i 0 (fx+ i 1)])
        ((fx= i idx))
        (vector-set! new i (vector-ref v i)))
      (vector-set! new idx val)
      (do ([i idx (fx+ i 1)])
        ((fx= i len))
        (vector-set! new (fx+ i 1) (vector-ref v i)))
      new))

  (define (vector-remove v idx)
    (let* ([len (vector-length v)]
           [new (make-vector (fx- len 1))])
      (do ([i 0 (fx+ i 1)])
        ((fx= i idx))
        (vector-set! new i (vector-ref v i)))
      (do ([i (fx+ idx 1) (fx+ i 1)])
        ((fx= i len))
        (vector-set! new (fx- i 1) (vector-ref v i)))
      new))

  (define (vector-replace v idx val)
    (let* ([len (vector-length v)]
           [new (make-vector len)])
      (do ([i 0 (fx+ i 1)])
        ((fx= i len))
        (vector-set! new i (if (fx= i idx) val (vector-ref v i))))
      new))

  ;; ---------- HAMT operations ----------

  (define (hamt-ref node hash key eq-fn shift)
    (cond
      [(hamt-empty? node) (values #f #f)]
      [(leaf? node)
       (if (and (fx= hash (leaf-hash node))
                (eq-fn key (leaf-key node)))
         (values (leaf-val node) #t)
         (values #f #f))]
      [(collision? node)
       (if (fx= hash (collision-hash node))
         (let loop ([entries (collision-entries node)])
           (cond
             [(null? entries) (values #f #f)]
             [(eq-fn key (caar entries))
              (values (cdar entries) #t)]
             [else (loop (cdr entries))]))
         (values #f #f))]
      [(branch? node)
       (let* ([frag (hash-fragment shift hash)]
              [bit  (bit-pos frag)]
              [bm   (branch-bitmap node)])
         (if (bitmap-has? bm bit)
           (let ([idx (bitmap-index bm bit)])
             (hamt-ref (vector-ref (branch-children node) idx)
                       hash key eq-fn (fx+ shift bits-per-level)))
           (values #f #f)))]
      [else (values #f #f)]))

  (define (hamt-set node hash key value eq-fn shift)
    (cond
      [(hamt-empty? node)
       (make-leaf hash key value)]
      [(leaf? node)
       (let ([lh (leaf-hash node)])
         (cond
           [(and (fx= hash lh) (eq-fn key (leaf-key node)))
            ;; Replace existing value
            (make-leaf hash key value)]
           [(fx= hash lh)
            ;; Hash collision: create collision node
            (make-collision hash
              (list (cons key value)
                    (cons (leaf-key node) (leaf-val node))))]
           [else
            ;; Different hashes: push both down into a branch
            (let ([new-branch (make-branch 0 (make-vector 0))])
              (let* ([b1 (hamt-set new-branch lh (leaf-key node)
                                   (leaf-val node) eq-fn shift)]
                     [b2 (hamt-set b1 hash key value eq-fn shift)])
                b2))]))]
      [(collision? node)
       (if (fx= hash (collision-hash node))
         ;; Same hash bucket: update or add
         (let loop ([entries (collision-entries node)]
                    [acc '()])
           (cond
             [(null? entries)
              ;; Key not found, add it
              (make-collision hash
                (cons (cons key value) (collision-entries node)))]
             [(eq-fn key (caar entries))
              ;; Replace existing
              (make-collision hash
                (append (reverse acc)
                        (cons (cons key value) (cdr entries))))]
             [else
              (loop (cdr entries) (cons (car entries) acc))]))
         ;; Different hash: push collision node into a branch
         (let* ([b (make-branch 0 (make-vector 0))]
                ;; Re-insert collision node at its hash
                [frag1 (hash-fragment shift (collision-hash node))]
                [bit1  (bit-pos frag1)]
                [b1    (make-branch bit1 (vector node))]
                ;; Now insert the new key
                [b2    (hamt-set b1 hash key value eq-fn shift)])
           b2))]
      [(branch? node)
       (let* ([frag (hash-fragment shift hash)]
              [bit  (bit-pos frag)]
              [bm   (branch-bitmap node)]
              [children (branch-children node)]
              [idx  (bitmap-index bm bit)])
         (if (bitmap-has? bm bit)
           ;; Child exists, recurse
           (let* ([child (vector-ref children idx)]
                  [new-child (hamt-set child hash key value eq-fn
                                       (fx+ shift bits-per-level))])
             (make-branch bm (vector-replace children idx new-child)))
           ;; No child, insert a leaf
           (make-branch (fxior bm bit)
                        (vector-insert children idx
                                       (make-leaf hash key value)))))]
      [else (make-leaf hash key value)]))

  (define (hamt-delete node hash key eq-fn shift)
    (cond
      [(hamt-empty? node) hamt-empty]
      [(leaf? node)
       (if (and (fx= hash (leaf-hash node))
                (eq-fn key (leaf-key node)))
         hamt-empty
         node)]
      [(collision? node)
       (if (fx= hash (collision-hash node))
         (let ([new-entries
                (filter (lambda (e) (not (eq-fn key (car e))))
                        (collision-entries node))])
           (cond
             [(null? new-entries) hamt-empty]
             [(null? (cdr new-entries))
              (make-leaf hash (caar new-entries) (cdar new-entries))]
             [else (make-collision hash new-entries)]))
         node)]
      [(branch? node)
       (let* ([frag (hash-fragment shift hash)]
              [bit  (bit-pos frag)]
              [bm   (branch-bitmap node)]
              [children (branch-children node)])
         (if (bitmap-has? bm bit)
           (let* ([idx (bitmap-index bm bit)]
                  [child (vector-ref children idx)]
                  [new-child (hamt-delete child hash key eq-fn
                                          (fx+ shift bits-per-level))])
             (cond
               [(hamt-empty? new-child)
                ;; Remove this slot
                (let ([new-bm (fxand bm (fxnot bit))])
                  (if (fxzero? new-bm)
                    hamt-empty
                    (let ([new-children (vector-remove children idx)])
                      (if (and (fx= (vector-length new-children) 1)
                               (or (leaf? (vector-ref new-children 0))
                                   (collision? (vector-ref new-children 0))))
                        ;; Collapse single-child branch
                        (vector-ref new-children 0)
                        (make-branch new-bm new-children)))))]
               [else
                (make-branch bm (vector-replace children idx new-child))]))
           ;; Key not in this branch
           node))]
      [else node]))

  (define (hamt-fold proc init node)
    (cond
      [(hamt-empty? node) init]
      [(leaf? node)
       (proc (leaf-key node) (leaf-val node) init)]
      [(collision? node)
       (fold-left (lambda (acc e) (proc (car e) (cdr e) acc))
                  init (collision-entries node))]
      [(branch? node)
       (let ([children (branch-children node)])
         (let loop ([i 0] [acc init])
           (if (fx= i (vector-length children))
             acc
             (loop (fx+ i 1)
                   (hamt-fold proc acc (vector-ref children i))))))]
      [else init]))

  (define (hamt-size node)
    (hamt-fold (lambda (k v acc) (fx+ acc 1)) 0 node))

  ;; ---------- Mapping record ----------

  (define-record-type mapping-rec
    (fields (immutable comp)     ;; comparator
            (immutable root)     ;; HAMT root node
            (immutable count))   ;; cached size
    (sealed #t))

  (define (mapping? x) (mapping-rec? x))

  (define (mapping-empty? m)
    (fxzero? (mapping-rec-count m)))

  (define (mapping-comparator m)
    (mapping-rec-comp m))

  ;; ---------- Default comparator ----------

  (define mapping-default-comparator
    (vector
      (lambda (x) #t)   ;; type-test
      equal?             ;; equality
      #f                 ;; ordering (not needed for hash maps)
      equal-hash))       ;; hash

  ;; ---------- Constructor ----------

  (define (mapping comp . args)
    (let loop ([args args]
               [root hamt-empty]
               [count 0])
      (if (null? args)
        (make-mapping-rec comp root count)
        (if (null? (cdr args))
          (error 'mapping "odd number of key/value arguments")
          (let* ([key (car args)]
                 [val (cadr args)]
                 [hash-fn (comp-hash comp)]
                 [eq-fn   (comp-equality comp)]
                 [h       (hash-fn key)])
            (call-with-values
              (lambda () (hamt-ref root h key eq-fn 0))
              (lambda (old-val found?)
                (let ([new-root (hamt-set root h key val eq-fn 0)])
                  (loop (cddr args) new-root
                        (if found? count (fx+ count 1)))))))))))

  ;; ---------- Lookup ----------

  (define mapping-ref
    (case-lambda
      [(m key)
       (let* ([comp (mapping-rec-comp m)]
              [h    ((comp-hash comp) key)])
         (call-with-values
           (lambda () (hamt-ref (mapping-rec-root m) h key
                                (comp-equality comp) 0))
           (lambda (val found?)
             (if found? val
               (error 'mapping-ref "key not found" key)))))]
      [(m key default)
       (let* ([comp (mapping-rec-comp m)]
              [h    ((comp-hash comp) key)])
         (call-with-values
           (lambda () (hamt-ref (mapping-rec-root m) h key
                                (comp-equality comp) 0))
           (lambda (val found?)
             (if found? val default))))]))

  (define (mapping-ref/default m key default)
    (mapping-ref m key default))

  (define (mapping-contains? m key)
    (let* ([comp (mapping-rec-comp m)]
           [h    ((comp-hash comp) key)])
      (call-with-values
        (lambda () (hamt-ref (mapping-rec-root m) h key
                             (comp-equality comp) 0))
        (lambda (val found?) found?))))

  ;; ---------- Functional update ----------

  (define (mapping-set m . args)
    (let ([comp (mapping-rec-comp m)]
          [hash-fn (comp-hash (mapping-rec-comp m))]
          [eq-fn   (comp-equality (mapping-rec-comp m))])
      (let loop ([args args]
                 [root (mapping-rec-root m)]
                 [count (mapping-rec-count m)])
        (if (null? args)
          (make-mapping-rec comp root count)
          (if (null? (cdr args))
            (error 'mapping-set "odd number of key/value arguments")
            (let* ([key (car args)]
                   [val (cadr args)]
                   [h   (hash-fn key)])
              (call-with-values
                (lambda () (hamt-ref root h key eq-fn 0))
                (lambda (old-val found?)
                  (let ([new-root (hamt-set root h key val eq-fn 0)])
                    (loop (cddr args) new-root
                          (if found? count (fx+ count 1))))))))))))

  (define (mapping-delete m . keys)
    (let ([comp (mapping-rec-comp m)]
          [hash-fn (comp-hash (mapping-rec-comp m))]
          [eq-fn   (comp-equality (mapping-rec-comp m))])
      (let loop ([keys keys]
                 [root (mapping-rec-root m)]
                 [count (mapping-rec-count m)])
        (if (null? keys)
          (make-mapping-rec comp root count)
          (let* ([key (car keys)]
                 [h   (hash-fn key)])
            (call-with-values
              (lambda () (hamt-ref root h key eq-fn 0))
              (lambda (old-val found?)
                (if found?
                  (loop (cdr keys)
                        (hamt-delete root h key eq-fn 0)
                        (fx- count 1))
                  (loop (cdr keys) root count)))))))))

  (define (mapping-delete-all m keys)
    (apply mapping-delete m keys))

  (define (mapping-update m key proc default)
    (let* ([comp    (mapping-rec-comp m)]
           [hash-fn (comp-hash comp)]
           [eq-fn   (comp-equality comp)]
           [h       (hash-fn key)])
      (call-with-values
        (lambda () (hamt-ref (mapping-rec-root m) h key eq-fn 0))
        (lambda (old-val found?)
          (let* ([val (proc (if found? old-val default))]
                 [new-root (hamt-set (mapping-rec-root m) h key val eq-fn 0)])
            (make-mapping-rec comp new-root
                              (if found?
                                (mapping-rec-count m)
                                (fx+ (mapping-rec-count m) 1))))))))

  ;; ---------- Size ----------

  (define (mapping-size m)
    (mapping-rec-count m))

  ;; ---------- Iteration ----------

  (define (mapping-fold proc init m)
    (hamt-fold proc init (mapping-rec-root m)))

  (define (mapping-for-each proc m)
    (hamt-fold (lambda (k v acc) (proc k v)) (void) (mapping-rec-root m)))

  (define (mapping-keys m)
    (mapping-fold (lambda (k v acc) (cons k acc)) '() m))

  (define (mapping-values m)
    (mapping-fold (lambda (k v acc) (cons v acc)) '() m))

  (define (mapping-entries m)
    (let ([pairs (mapping-fold (lambda (k v acc) (cons (cons k v) acc))
                               '() m)])
      (values (map car pairs) (map cdr pairs))))

  (define (mapping->alist m)
    (mapping-fold (lambda (k v acc) (cons (cons k v) acc)) '() m))

  (define (alist->mapping comp alist)
    (let ([hash-fn (comp-hash comp)]
          [eq-fn   (comp-equality comp)])
      (let loop ([entries alist]
                 [root hamt-empty]
                 [count 0])
        (if (null? entries)
          (make-mapping-rec comp root count)
          (let* ([key (caar entries)]
                 [val (cdar entries)]
                 [h   (hash-fn key)])
            (call-with-values
              (lambda () (hamt-ref root h key eq-fn 0))
              (lambda (old-val found?)
                (loop (cdr entries)
                      (hamt-set root h key val eq-fn 0)
                      (if found? count (fx+ count 1))))))))))

  ;; ---------- Transformations ----------

  (define (mapping-map proc m)
    (let ([comp (mapping-rec-comp m)]
          [hash-fn (comp-hash (mapping-rec-comp m))]
          [eq-fn   (comp-equality (mapping-rec-comp m))])
      (mapping-fold
        (lambda (k v acc)
          (let* ([new-val (proc k v)]
                 [h (hash-fn k)]
                 [root (mapping-rec-root acc)]
                 [new-root (hamt-set root h k new-val eq-fn 0)])
            (make-mapping-rec comp new-root (mapping-rec-count acc))))
        (make-mapping-rec comp hamt-empty 0)
        m)))

  (define (mapping-filter pred m)
    (let ([comp (mapping-rec-comp m)]
          [hash-fn (comp-hash (mapping-rec-comp m))]
          [eq-fn   (comp-equality (mapping-rec-comp m))])
      (mapping-fold
        (lambda (k v acc)
          (if (pred k v)
            (let* ([h (hash-fn k)]
                   [root (mapping-rec-root acc)]
                   [cnt  (mapping-rec-count acc)]
                   [new-root (hamt-set root h k v eq-fn 0)])
              (make-mapping-rec comp new-root (fx+ cnt 1)))
            acc))
        (make-mapping-rec comp hamt-empty 0)
        m)))

  (define (mapping-remove pred m)
    (mapping-filter (lambda (k v) (not (pred k v))) m))

  ;; ---------- Set operations ----------

  (define (mapping-union m1 m2)
    ;; Left-biased: m1 values take precedence
    (let ([comp (mapping-rec-comp m1)]
          [hash-fn (comp-hash (mapping-rec-comp m1))]
          [eq-fn   (comp-equality (mapping-rec-comp m1))])
      (mapping-fold
        (lambda (k v acc)
          (if (mapping-contains? acc k)
            acc  ;; left bias: keep m1's value
            (let* ([h (hash-fn k)]
                   [root (mapping-rec-root acc)]
                   [cnt  (mapping-rec-count acc)]
                   [new-root (hamt-set root h k v eq-fn 0)])
              (make-mapping-rec comp new-root (fx+ cnt 1)))))
        m1
        m2)))

  (define (mapping-intersection m1 m2)
    ;; Keep entries from m1 whose keys are also in m2
    (mapping-filter (lambda (k v) (mapping-contains? m2 k)) m1))

  (define (mapping-difference m1 m2)
    ;; Keep entries from m1 whose keys are NOT in m2
    (mapping-filter (lambda (k v) (not (mapping-contains? m2 k))) m1))

) ;; end library
