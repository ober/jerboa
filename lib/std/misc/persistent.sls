#!chezscheme
;;; (std misc persistent) -- Hash Array Mapped Trie (HAMT)
;;;
;;; Persistent (immutable) hash map with structural sharing.
;;; Uses 32-way branching (5 bits per level) with bitmap-indexed nodes.
;;; All operations return new HAMTs; the original is never mutated.
;;;
;;; Usage:
;;;   (import (std misc persistent))
;;;   (define h0 hamt-empty)
;;;   (define h1 (hamt-set h0 "name" "Alice"))
;;;   (define h2 (hamt-set h1 "age" 30))
;;;   (hamt-ref h2 "name" #f)           ; => "Alice"
;;;   (hamt-contains? h2 "age")         ; => #t
;;;   (hamt-size h2)                    ; => 2
;;;   (hamt->alist h2)                  ; => (("name" . "Alice") ("age" . 30))
;;;   (define h3 (hamt-delete h2 "age"))
;;;   (hamt-size h3)                    ; => 1

(library (std misc persistent)
  (export
    hamt-empty
    hamt?
    hamt-ref
    hamt-set
    hamt-delete
    hamt-contains?
    hamt-size
    hamt-fold
    hamt-keys
    hamt-values
    hamt-map
    hamt->alist
    alist->hamt)

  (import (chezscheme))

  ;; ========== Constants ==========
  ;; 5 bits per level, 32-way branching
  (define BITS 5)
  (define WIDTH 32)  ; (expt 2 BITS)
  (define MASK 31)   ; (- WIDTH 1)

  ;; ========== Node types ==========
  ;; Three node types:
  ;; - empty: #f
  ;; - leaf: stores a single key-value pair
  ;; - bitmap-indexed: sparse array of children indexed by bitmap
  ;; - collision: multiple entries sharing the same hash

  (define-record-type leaf
    (fields hash key value))

  (define-record-type bitmap-node
    (fields bitmap children))  ; bitmap: fixnum, children: vector

  (define-record-type collision-node
    (fields hash entries))  ; entries: list of (key . value) pairs

  ;; ========== HAMT wrapper ==========
  (define-record-type hamt-rec
    (fields root count))

  (define (hamt? x) (hamt-rec? x))

  (define hamt-empty (make-hamt-rec #f 0))

  ;; ========== Bit manipulation helpers ==========

  ;; Extract the 5-bit fragment at the given level (shift)
  (define (hash-fragment shift hash)
    (fxlogand MASK (fxsrl hash shift)))

  ;; Count the number of set bits below position in bitmap (popcount of masked bits)
  ;; This gives us the index into the children vector.
  (define (bitmap-index bitmap frag)
    (bitwise-bit-count (fxlogand bitmap (- (fxsll 1 frag) 1))))

  ;; Check if a bit is set in bitmap
  (define (bitmap-has? bitmap frag)
    (fxlogbit? frag bitmap))

  ;; ========== Internal node operations ==========

  ;; Create a new bitmap-node with one child
  (define (make-single-child-node frag child)
    (make-bitmap-node (fxsll 1 frag) (vector child)))

  ;; Insert/replace a child in a bitmap-node
  (define (bitmap-node-set bm-node frag child)
    (let* ([bitmap (bitmap-node-bitmap bm-node)]
           [children (bitmap-node-children bm-node)]
           [idx (bitmap-index bitmap frag)])
      (if (bitmap-has? bitmap frag)
        ;; Replace existing child at idx
        (let ([new-children (vector-copy children)])
          (vector-set! new-children idx child)
          (make-bitmap-node bitmap new-children))
        ;; Insert new child at idx
        (let* ([len (vector-length children)]
               [new-children (make-vector (+ len 1))])
          ;; Copy elements before idx
          (do ([i 0 (+ i 1)])
              ((= i idx))
            (vector-set! new-children i (vector-ref children i)))
          ;; Insert new child
          (vector-set! new-children idx child)
          ;; Copy elements after idx
          (do ([i idx (+ i 1)])
              ((= i len))
            (vector-set! new-children (+ i 1) (vector-ref children i)))
          (make-bitmap-node (fxlogior bitmap (fxsll 1 frag)) new-children)))))

  ;; Remove a child from a bitmap-node
  (define (bitmap-node-remove bm-node frag)
    (let* ([bitmap (bitmap-node-bitmap bm-node)]
           [children (bitmap-node-children bm-node)]
           [idx (bitmap-index bitmap frag)]
           [len (vector-length children)]
           [new-bitmap (fxlogand bitmap (fxlognot (fxsll 1 frag)))])
      (cond
        [(= len 1)
         ;; Removing the last child => empty
         #f]
        [(= len 2)
         ;; Removing one of two children: if the remaining child is a leaf
         ;; or collision, promote it up; otherwise keep as bitmap-node
         (let ([remaining (vector-ref children (if (= idx 0) 1 0))])
           (if (or (leaf? remaining) (collision-node? remaining))
             remaining
             ;; remaining is a bitmap-node; can't promote, keep structure
             (let ([new-children (make-vector 1)])
               (vector-set! new-children 0 remaining)
               (make-bitmap-node new-bitmap new-children))))]
        [else
         ;; Remove element at idx
         (let ([new-children (make-vector (- len 1))])
           (do ([i 0 (+ i 1)])
               ((= i idx))
             (vector-set! new-children i (vector-ref children i)))
           (do ([i (+ idx 1) (+ i 1)])
               ((= i len))
             (vector-set! new-children (- i 1) (vector-ref children i)))
           (make-bitmap-node new-bitmap new-children))])))

  ;; ========== Collision node helpers ==========

  ;; Find key in collision entries
  (define (collision-find-entry entries key)
    (cond
      [(null? entries) #f]
      [(equal? (caar entries) key) (car entries)]
      [else (collision-find-entry (cdr entries) key)]))

  ;; Update/insert in collision entries
  (define (collision-set-entry entries key value)
    (cond
      [(null? entries)
       (list (cons key value))]
      [(equal? (caar entries) key)
       (cons (cons key value) (cdr entries))]
      [else
       (cons (car entries) (collision-set-entry (cdr entries) key value))]))

  ;; Remove from collision entries
  (define (collision-remove-entry entries key)
    (cond
      [(null? entries) '()]
      [(equal? (caar entries) key) (cdr entries)]
      [else (cons (car entries) (collision-remove-entry (cdr entries) key))]))

  ;; ========== Core: node-set ==========
  ;; Insert/update a key-value pair in the trie rooted at `node`.
  ;; Returns (values new-node added?) where added? is #t if size increased.
  (define (node-set node hash key value shift)
    (cond
      ;; Empty slot: create a leaf
      [(not node)
       (values (make-leaf hash key value) #t)]

      ;; Leaf node
      [(leaf? node)
       (let ([existing-hash (leaf-hash node)])
         (cond
           ;; Same hash and same key: replace value
           [(and (= hash existing-hash) (equal? key (leaf-key node)))
            (if (equal? value (leaf-value node))
              (values node #f)  ; no change
              (values (make-leaf hash key value) #f))]
           ;; Same hash, different key: create collision node
           [(= hash existing-hash)
            (values (make-collision-node hash
                      (list (cons key value)
                            (cons (leaf-key node) (leaf-value node))))
                    #t)]
           ;; Different hash: need to push both down
           [else
            (let* ([frag1 (hash-fragment shift existing-hash)]
                   [frag2 (hash-fragment shift hash)])
              (if (= frag1 frag2)
                ;; Same fragment at this level: recurse deeper
                (let-values ([(child _) (node-set node hash key value (+ shift BITS))])
                  ;; Push the new subtree into a bitmap-node at this level
                  ;; Actually, we need to create a bitmap-node with one child
                  ;; that contains both entries. Let me restructure:
                  ;; Create a sub-node with just the existing leaf, then insert the new key.
                  (let-values ([(sub added?) (node-set (make-single-child-node frag1 node)
                                                       hash key value shift)])
                    (values sub added?)))
                ;; Different fragments: create bitmap-node with both children
                (let* ([bm1 (fxsll 1 frag1)]
                       [bm2 (fxsll 1 frag2)]
                       [bitmap (fxlogior bm1 bm2)])
                  (if (< frag1 frag2)
                    (values (make-bitmap-node bitmap (vector node (make-leaf hash key value))) #t)
                    (values (make-bitmap-node bitmap (vector (make-leaf hash key value) node)) #t)))))]))]

      ;; Bitmap-indexed node
      [(bitmap-node? node)
       (let* ([frag (hash-fragment shift hash)]
              [bitmap (bitmap-node-bitmap node)]
              [idx (bitmap-index bitmap frag)])
         (if (bitmap-has? bitmap frag)
           ;; Child exists at this position: recurse into it
           (let ([child (vector-ref (bitmap-node-children node) idx)])
             (let-values ([(new-child added?) (node-set child hash key value (+ shift BITS))])
               (if (eq? new-child child)
                 (values node #f)
                 (values (bitmap-node-set node frag new-child) added?))))
           ;; No child at this position: add a new leaf
           (values (bitmap-node-set node frag (make-leaf hash key value)) #t)))]

      ;; Collision node
      [(collision-node? node)
       (let ([node-hash (collision-node-hash node)]
             [entries (collision-node-entries node)])
         (if (= hash node-hash)
           ;; Same hash bucket: add/update in collision list
           (let ([existing (collision-find-entry entries key)])
             (if existing
               (if (equal? (cdr existing) value)
                 (values node #f)
                 (values (make-collision-node hash (collision-set-entry entries key value)) #f))
               (values (make-collision-node hash (collision-set-entry entries key value)) #t)))
           ;; Different hash: need to nest this collision under a bitmap-node
           (let* ([frag1 (hash-fragment shift node-hash)]
                  [frag2 (hash-fragment shift hash)])
             (if (= frag1 frag2)
               ;; Same fragment: recurse deeper
               (let-values ([(sub added?)
                             (node-set (make-single-child-node frag1 node)
                                       hash key value shift)])
                 (values sub added?))
               ;; Different fragments: two children
               (let* ([new-leaf (make-leaf hash key value)]
                      [bm1 (fxsll 1 frag1)]
                      [bm2 (fxsll 1 frag2)]
                      [bitmap (fxlogior bm1 bm2)])
                 (if (< frag1 frag2)
                   (values (make-bitmap-node bitmap (vector node new-leaf)) #t)
                   (values (make-bitmap-node bitmap (vector new-leaf node)) #t)))))))]

      [else (error 'node-set "invalid node type" node)]))

  ;; ========== Core: node-ref ==========
  (define (node-ref node hash key shift default)
    (cond
      [(not node) default]

      [(leaf? node)
       (if (and (= hash (leaf-hash node)) (equal? key (leaf-key node)))
         (leaf-value node)
         default)]

      [(bitmap-node? node)
       (let* ([frag (hash-fragment shift hash)]
              [bitmap (bitmap-node-bitmap node)])
         (if (bitmap-has? bitmap frag)
           (let ([idx (bitmap-index bitmap frag)])
             (node-ref (vector-ref (bitmap-node-children node) idx)
                       hash key (+ shift BITS) default))
           default))]

      [(collision-node? node)
       (if (= hash (collision-node-hash node))
         (let ([entry (collision-find-entry (collision-node-entries node) key)])
           (if entry (cdr entry) default))
         default)]

      [else (error 'node-ref "invalid node type" node)]))

  ;; ========== Core: node-delete ==========
  ;; Returns (values new-node removed?) where removed? is #t if size decreased.
  (define (node-delete node hash key shift)
    (cond
      [(not node)
       (values #f #f)]

      [(leaf? node)
       (if (and (= hash (leaf-hash node)) (equal? key (leaf-key node)))
         (values #f #t)
         (values node #f))]

      [(bitmap-node? node)
       (let* ([frag (hash-fragment shift hash)]
              [bitmap (bitmap-node-bitmap node)])
         (if (bitmap-has? bitmap frag)
           (let* ([idx (bitmap-index bitmap frag)]
                  [child (vector-ref (bitmap-node-children node) idx)])
             (let-values ([(new-child removed?) (node-delete child hash key (+ shift BITS))])
               (if (not removed?)
                 (values node #f)
                 (if (not new-child)
                   ;; Child was deleted entirely
                   (values (bitmap-node-remove node frag) #t)
                   ;; Child was modified
                   (values (bitmap-node-set node frag new-child) #t)))))
           (values node #f)))]

      [(collision-node? node)
       (if (= hash (collision-node-hash node))
         (let* ([entries (collision-node-entries node)]
                [new-entries (collision-remove-entry entries key)])
           (if (= (length new-entries) (length entries))
             (values node #f)  ; key not found
             (if (= (length new-entries) 1)
               ;; Only one entry left: convert to leaf
               (let ([e (car new-entries)])
                 (values (make-leaf hash (car e) (cdr e)) #t))
               (values (make-collision-node hash new-entries) #t))))
         (values node #f))]

      [else (error 'node-delete "invalid node type" node)]))

  ;; ========== Core: node-fold ==========
  (define (node-fold proc seed node)
    (cond
      [(not node) seed]

      [(leaf? node)
       (proc (leaf-key node) (leaf-value node) seed)]

      [(bitmap-node? node)
       (let ([children (bitmap-node-children node)]
             [len (vector-length (bitmap-node-children node))])
         (let loop ([i 0] [acc seed])
           (if (= i len)
             acc
             (loop (+ i 1) (node-fold proc acc (vector-ref children i))))))]

      [(collision-node? node)
       (let loop ([entries (collision-node-entries node)] [acc seed])
         (if (null? entries)
           acc
           (loop (cdr entries) (proc (caar entries) (cdar entries) acc))))]

      [else (error 'node-fold "invalid node type" node)]))

  ;; ========== Core: node-map ==========
  ;; Apply f to each value, returning a new node tree
  (define (node-map f node)
    (cond
      [(not node) #f]

      [(leaf? node)
       (make-leaf (leaf-hash node) (leaf-key node) (f (leaf-value node)))]

      [(bitmap-node? node)
       (let* ([children (bitmap-node-children node)]
              [len (vector-length children)]
              [new-children (make-vector len)])
         (do ([i 0 (+ i 1)])
             ((= i len))
           (vector-set! new-children i (node-map f (vector-ref children i))))
         (make-bitmap-node (bitmap-node-bitmap node) new-children))]

      [(collision-node? node)
       (make-collision-node
         (collision-node-hash node)
         (map (lambda (e) (cons (car e) (f (cdr e))))
              (collision-node-entries node)))]

      [else (error 'node-map "invalid node type" node)]))

  ;; ========== Public API ==========

  (define (hamt-set h key value)
    (let ([hash (equal-hash key)])
      (let-values ([(new-root added?) (node-set (hamt-rec-root h) hash key value 0)])
        (make-hamt-rec new-root
                       (if added? (+ (hamt-rec-count h) 1) (hamt-rec-count h))))))

  (define (hamt-ref h key default)
    (node-ref (hamt-rec-root h) (equal-hash key) key 0 default))

  (define (hamt-delete h key)
    (let ([hash (equal-hash key)])
      (let-values ([(new-root removed?) (node-delete (hamt-rec-root h) hash key 0)])
        (if removed?
          (make-hamt-rec new-root (- (hamt-rec-count h) 1))
          h))))

  (define (hamt-contains? h key)
    (let ([sentinel (list 'not-found)])
      (not (eq? (hamt-ref h key sentinel) sentinel))))

  (define (hamt-size h)
    (hamt-rec-count h))

  (define (hamt-fold proc seed h)
    (node-fold proc seed (hamt-rec-root h)))

  (define (hamt-keys h)
    (hamt-fold (lambda (k v acc) (cons k acc)) '() h))

  (define (hamt-values h)
    (hamt-fold (lambda (k v acc) (cons v acc)) '() h))

  (define (hamt-map f h)
    (make-hamt-rec (node-map f (hamt-rec-root h)) (hamt-rec-count h)))

  (define (hamt->alist h)
    (hamt-fold (lambda (k v acc) (cons (cons k v) acc)) '() h))

  (define (alist->hamt alist)
    (let loop ([pairs alist] [h hamt-empty])
      (if (null? pairs)
        h
        (loop (cdr pairs)
              (hamt-set h (caar pairs) (cdar pairs))))))

) ;; end library
