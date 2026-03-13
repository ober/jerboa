#!chezscheme
;;; (std data pmap) — Persistent hash map with O(1) snapshots
;;;
;;; Track 27: Hash-Array Mapped Trie (HAMT) for copy-on-write
;;; environment snapshots. Supports O(1) snapshot via structural sharing.

(library (std data pmap)
  (export
    pmap-empty
    pmap?
    pmap-ref
    pmap-set
    pmap-delete
    pmap-contains?
    pmap-size
    pmap-fold
    pmap-for-each
    pmap-keys
    pmap-values
    pmap->alist
    alist->pmap
    pmap-snapshot
    pmap-merge
    ;; Mutable cell wrapper for shell environments
    make-pmap-cell
    pmap-cell?
    pmap-cell-ref
    pmap-cell-set!
    pmap-cell-update!
    pmap-cell-snapshot)

  (import (chezscheme))

  ;; ========== HAMT Implementation ==========
  ;; A Hash Array Mapped Trie using 32-way branching.
  ;; Each node is either:
  ;;   - #f (empty)
  ;;   - #(leaf key value hash)
  ;;   - #(node bitmap children)  where children is a vector
  ;;   - #(collision hash entries) where entries is ((k . v) ...)

  (define BITS 5)
  (define WIDTH (expt 2 BITS))    ;; 32
  (define MASK  (- WIDTH 1))      ;; 31

  (define (hash-key key)
    (cond
      [(string? key) (string-hash key)]
      [(symbol? key) (symbol-hash key)]
      [(fixnum? key) (if (fx< key 0) (fxnot key) key)]
      [else (equal-hash key)]))

  ;; --- Node constructors ---
  (define (make-leaf key value hash)
    (vector 'leaf key value hash))

  (define (make-inode bitmap children)
    (vector 'node bitmap children))

  (define (make-collision hash entries)
    (vector 'collision hash entries))

  (define (node-type n) (vector-ref n 0))

  ;; --- Bitmap operations ---
  (define (bit-pos hash shift)
    (bitwise-and (bitwise-arithmetic-shift-right hash shift) MASK))

  (define (bit-val pos)
    (bitwise-arithmetic-shift-left 1 pos))

  (define (has-bit? bitmap pos)
    (not (zero? (bitwise-and bitmap (bit-val pos)))))

  (define (bit-index bitmap pos)
    ;; Count bits set below pos (popcount of masked bitmap)
    (popcount (bitwise-and bitmap (- (bit-val pos) 1))))

  (define (popcount n)
    (let lp ([n n] [count 0])
      (if (zero? n) count
        (lp (bitwise-and n (- n 1)) (+ count 1)))))

  ;; --- HAMT operations ---

  (define pmap-empty #f)

  (define (pmap? x)
    (or (not x)
        (and (vector? x)
             (> (vector-length x) 0)
             (memq (vector-ref x 0) '(leaf node collision)))))

  (define (pmap-ref trie key default)
    (let ([hash (hash-key key)])
      (lookup trie key hash 0 default)))

  (define (lookup node key hash shift default)
    (cond
      [(not node) default]
      [(eq? (node-type node) 'leaf)
       (if (equal? (vector-ref node 1) key)
         (vector-ref node 2)
         default)]
      [(eq? (node-type node) 'collision)
       (let ([entries (vector-ref node 2)])
         (let lp ([es entries])
           (cond
             [(null? es) default]
             [(equal? (caar es) key) (cdar es)]
             [else (lp (cdr es))])))]
      [(eq? (node-type node) 'node)
       (let* ([bitmap (vector-ref node 1)]
              [pos (bit-pos hash shift)])
         (if (has-bit? bitmap pos)
           (let ([idx (bit-index bitmap pos)]
                 [children (vector-ref node 2)])
             (lookup (vector-ref children idx) key hash (+ shift BITS) default))
           default))]
      [else default]))

  (define (pmap-set trie key value)
    (let ([hash (hash-key key)])
      (insert trie key value hash 0)))

  (define (insert node key value hash shift)
    (cond
      [(not node)
       (make-leaf key value hash)]
      [(eq? (node-type node) 'leaf)
       (let ([existing-hash (vector-ref node 3)]
             [existing-key (vector-ref node 1)])
         (cond
           [(equal? existing-key key)
            ;; Update existing
            (make-leaf key value hash)]
           [(= existing-hash hash)
            ;; Hash collision
            (make-collision hash
              (list (cons key value) (cons existing-key (vector-ref node 2))))]
           [else
            ;; Different hashes, create internal node
            (let ([new-node (make-inode 0 (make-vector 0))])
              (let* ([n1 (insert new-node existing-key (vector-ref node 2)
                                 existing-hash shift)]
                     [n2 (insert n1 key value hash shift)])
                n2))]))]
      [(eq? (node-type node) 'collision)
       (if (= hash (vector-ref node 1))
         ;; Same hash bucket
         (let ([entries (vector-ref node 2)])
           (make-collision hash
             (cons (cons key value)
                   (filter-key entries key))))
         ;; Different hash, need to restructure
         (let ([n (make-inode 0 (make-vector 0))])
           (let* ([n1 (fold-left (lambda (acc e)
                                   (insert acc (car e) (cdr e) (vector-ref node 1) shift))
                                 n (vector-ref node 2))]
                  [n2 (insert n1 key value hash shift)])
             n2)))]
      [(eq? (node-type node) 'node)
       (let* ([bitmap (vector-ref node 1)]
              [children (vector-ref node 2)]
              [pos (bit-pos hash shift)]
              [bit (bit-val pos)])
         (if (has-bit? bitmap pos)
           ;; Descend
           (let* ([idx (bit-index bitmap pos)]
                  [child (vector-ref children idx)]
                  [new-child (insert child key value hash (+ shift BITS))])
             (make-inode bitmap (vector-replace children idx new-child)))
           ;; Insert new
           (let* ([idx (bit-index bitmap pos)]
                  [new-child (make-leaf key value hash)]
                  [new-children (vector-insert children idx new-child)])
             (make-inode (bitwise-ior bitmap bit) new-children))))]
      [else (make-leaf key value hash)]))

  (define (filter-key entries key)
    (let lp ([es entries] [result '()])
      (if (null? es) (reverse result)
        (if (equal? (caar es) key)
          (lp (cdr es) result)
          (lp (cdr es) (cons (car es) result))))))

  (define (vector-replace vec idx val)
    (let ([new (vector-copy vec)])
      (vector-set! new idx val)
      new))

  (define (vector-insert vec idx val)
    (let* ([n (vector-length vec)]
           [new (make-vector (+ n 1))])
      ;; Copy before idx
      (do ([i 0 (+ i 1)])
          ((= i idx))
        (vector-set! new i (vector-ref vec i)))
      ;; Insert
      (vector-set! new idx val)
      ;; Copy after idx
      (do ([i idx (+ i 1)])
          ((= i n))
        (vector-set! new (+ i 1) (vector-ref vec i)))
      new))

  (define (pmap-delete trie key)
    (let ([hash (hash-key key)])
      (delete-node trie key hash 0)))

  (define (delete-node node key hash shift)
    (cond
      [(not node) #f]
      [(eq? (node-type node) 'leaf)
       (if (equal? (vector-ref node 1) key) #f node)]
      [(eq? (node-type node) 'collision)
       (let ([entries (filter-key (vector-ref node 2) key)])
         (cond
           [(null? entries) #f]
           [(null? (cdr entries))
            (make-leaf (caar entries) (cdar entries) hash)]
           [else
            (make-collision hash entries)]))]
      [(eq? (node-type node) 'node)
       (let* ([bitmap (vector-ref node 1)]
              [children (vector-ref node 2)]
              [pos (bit-pos hash shift)])
         (if (has-bit? bitmap pos)
           (let* ([idx (bit-index bitmap pos)]
                  [child (vector-ref children idx)]
                  [new-child (delete-node child key hash (+ shift BITS))])
             (if new-child
               (make-inode bitmap (vector-replace children idx new-child))
               ;; Child was deleted
               (let ([new-bitmap (bitwise-and bitmap (bitwise-not (bit-val pos)))])
                 (if (zero? new-bitmap) #f
                   (make-inode new-bitmap (vector-remove children idx))))))
           node))]
      [else node]))

  (define (vector-remove vec idx)
    (let* ([n (vector-length vec)]
           [new (make-vector (- n 1))])
      (do ([i 0 (+ i 1)]) ((= i idx))
        (vector-set! new i (vector-ref vec i)))
      (do ([i (+ idx 1) (+ i 1)]) ((= i n))
        (vector-set! new (- i 1) (vector-ref vec i)))
      new))

  (define (pmap-contains? trie key)
    (let ([sentinel (cons 'not 'found)])
      (not (eq? (pmap-ref trie key sentinel) sentinel))))

  (define (pmap-size trie)
    (cond
      [(not trie) 0]
      [(eq? (node-type trie) 'leaf) 1]
      [(eq? (node-type trie) 'collision)
       (length (vector-ref trie 2))]
      [(eq? (node-type trie) 'node)
       (let ([children (vector-ref trie 2)])
         (let lp ([i 0] [total 0])
           (if (= i (vector-length children)) total
             (lp (+ i 1) (+ total (pmap-size (vector-ref children i)))))))]
      [else 0]))

  (define (pmap-fold proc init trie)
    (cond
      [(not trie) init]
      [(eq? (node-type trie) 'leaf)
       (proc (vector-ref trie 1) (vector-ref trie 2) init)]
      [(eq? (node-type trie) 'collision)
       (fold-left (lambda (acc e) (proc (car e) (cdr e) acc))
                  init (vector-ref trie 2))]
      [(eq? (node-type trie) 'node)
       (let ([children (vector-ref trie 2)])
         (let lp ([i 0] [acc init])
           (if (= i (vector-length children)) acc
             (lp (+ i 1) (pmap-fold proc acc (vector-ref children i))))))]
      [else init]))

  (define (pmap-for-each proc trie)
    (pmap-fold (lambda (k v _) (proc k v)) (void) trie))

  (define (pmap-keys trie)
    (pmap-fold (lambda (k v acc) (cons k acc)) '() trie))

  (define (pmap-values trie)
    (pmap-fold (lambda (k v acc) (cons v acc)) '() trie))

  (define (pmap->alist trie)
    (pmap-fold (lambda (k v acc) (cons (cons k v) acc)) '() trie))

  (define (alist->pmap alist)
    (fold-left (lambda (m pair) (pmap-set m (car pair) (cdr pair)))
               pmap-empty alist))

  ;; Snapshot is trivially O(1) — the trie is already persistent!
  (define (pmap-snapshot trie) trie)

  (define (pmap-merge base overlay)
    ;; Merge overlay into base; overlay keys take precedence
    (pmap-fold (lambda (k v acc) (pmap-set acc k v)) base overlay))

  ;; ========== Mutable Cell Wrapper ==========
  ;; For shell environments: wraps pmap in a mutable box

  (define-record-type pmap-cell
    (fields (mutable map))
    (protocol
      (lambda (new)
        (case-lambda
          [()  (new pmap-empty)]
          [(m) (new m)]))))

  (define (pmap-cell-ref cell key . default)
    (pmap-ref (pmap-cell-map cell) key
              (if (pair? default) (car default) #f)))

  (define (pmap-cell-set! cell key value)
    (pmap-cell-map-set! cell (pmap-set (pmap-cell-map cell) key value)))

  (define (pmap-cell-update! cell key proc . default)
    (let ([old (pmap-ref (pmap-cell-map cell) key
                         (if (pair? default) (car default) #f))])
      (pmap-cell-set! cell key (proc old))))

  (define (pmap-cell-snapshot cell)
    ;; O(1) — returns the current immutable pmap
    (pmap-cell-map cell))

  ) ;; end library
