#!chezscheme
;;; (std mmap-btree) — Persistent, file-backed B+ tree
;;;
;;; Provides key-value storage that survives process restart.
;;; Implemented as a file-backed B+ tree: tree is loaded into memory
;;; on open, and written back to file on commit/close.
;;;
;;; Keys and values must be readable/writable with Chez's read/write.
;;; Default order (branching factor) is 4 (max 2*order keys per node).
;;;
;;; NOTE: Chez Scheme vector-copy! signature is:
;;;   (vector-copy! src src-start dest dest-start count)

(library (std mmap-btree)
  (export
    ;; Open/create
    open-btree
    btree?
    close-btree
    btree-order
    btree-size
    btree-path
    ;; Operations
    btree-get
    btree-put!
    btree-delete!
    btree-has?
    ;; Iteration
    btree-fold
    btree-keys
    btree-values
    btree-range
    btree->alist
    alist->btree
    ;; Transactions
    with-btree-transaction
    btree-commit!
    btree-rollback!)

  (import (chezscheme))

  ;; ========== B+ Tree Node Representation ==========
  ;;
  ;; Nodes are vectors: #(leaf? keys data)
  ;;   leaf? : boolean
  ;;   keys  : sorted vector of keys
  ;;   data  : if leaf?  -> vector of values (parallel to keys)
  ;;           if !leaf? -> vector of children (length = (+ (vector-length keys) 1))

  (define (make-leaf-node keys vals)
    (vector #t keys vals))

  (define (make-internal-node keys children)
    (vector #f keys children))

  (define (node-leaf?    n) (vector-ref n 0))
  (define (node-keys     n) (vector-ref n 1))
  (define (node-data     n) (vector-ref n 2))

  ;; ========== Key comparison ==========
  ;; Total order via write-to-string: works for any read/write-able key.

  (define (key->string k)
    (let ([sp (open-output-string)])
      (write k sp)
      (get-output-string sp)))

  (define (key<? a b)
    (string<? (key->string a) (key->string b)))

  (define (key=? a b)
    (equal? a b))

  ;; bisect-left: returns leftmost i such that keys[i] >= key.
  ;; Used for leaf insertion/search.
  (define (bisect-left keys key)
    (let loop ([lo 0] [hi (vector-length keys)])
      (if (>= lo hi)
        lo
        (let ([mid (quotient (+ lo hi) 2)])
          (if (key<? (vector-ref keys mid) key)
            (loop (+ mid 1) hi)
            (loop lo mid))))))

  ;; bisect-right: returns rightmost i such that keys[i] <= key.
  ;; Used for internal node routing: child index = number of separators <= key.
  (define (bisect-right keys key)
    (let loop ([lo 0] [hi (vector-length keys)])
      (if (>= lo hi)
        lo
        (let ([mid (quotient (+ lo hi) 2)])
          (if (key<? key (vector-ref keys mid))
            (loop lo mid)
            (loop (+ mid 1) hi))))))

  ;; ========== Helper: vector insert at position ==========
  ;; Insert val at position pos in vec (0-based), returning new vector.
  ;; Chez vector-copy! is: (src src-start dest dest-start count)
  (define (vector-insert vec pos val)
    (let* ([n   (vector-length vec)]
           [res (make-vector (+ n 1))])
      ;; Copy vec[0..pos) into res[0..]
      (vector-copy! vec 0 res 0 pos)
      ;; Set res[pos] = val
      (vector-set! res pos val)
      ;; Copy vec[pos..n) into res[pos+1..]
      (vector-copy! vec pos res (+ pos 1) (- n pos))
      res))

  ;; ========== Helper: vector remove at position ==========
  ;; Remove element at pos, returning new vector of length n-1.
  (define (vector-remove vec pos)
    (let* ([n   (vector-length vec)]
           [res (make-vector (- n 1))])
      (vector-copy! vec 0 res 0 pos)
      (vector-copy! vec (+ pos 1) res pos (- n pos 1))
      res))

  ;; ========== Helper: vector sub-range ==========
  ;; Returns a copy of vec[start..end).
  (define (vector-slice vec start end)
    (let* ([count (- end start)]
           [res   (make-vector count)])
      (vector-copy! vec start res 0 count)
      res))

  ;; ========== Tree search ==========

  (define (node-search node key)
    (let ([keys (node-keys node)]
          [data (node-data node)])
      (if (node-leaf? node)
        ;; Leaf: search for exact key
        (let ([idx (bisect-left keys key)])
          (if (and (< idx (vector-length keys))
                   (key=? (vector-ref keys idx) key))
            (vector-ref data idx)
            #f))
        ;; Internal: use bisect-right so key=separator routes RIGHT
        ;; child i contains keys strictly less than separator[i]
        (node-search (vector-ref data (bisect-right keys key)) key))))

  ;; ========== Leaf node insertion ==========
  ;; Returns (values result added?)
  ;; result is either a new leaf node, or #(split left sep right).

  (define (leaf-insert leaf key val order)
    (let* ([keys (node-keys leaf)]
           [vals (node-data leaf)]
           [n    (vector-length keys)]
           [idx  (bisect-left keys key)])
      (if (and (< idx n) (key=? (vector-ref keys idx) key))
        ;; Update existing
        (let ([new-vals (vector-copy vals)])
          (vector-set! new-vals idx val)
          (values (make-leaf-node keys new-vals) #f))
        ;; Insert new key at idx
        (let ([new-keys (vector-insert keys idx key)]
              [new-vals (vector-insert vals idx val)])
          (let ([new-n (vector-length new-keys)])
            (if (> new-n (* 2 order))
              ;; Split: left gets [0..order), right gets [order..new-n)
              (let* ([mid        order]
                     [left-keys  (vector-slice new-keys 0 mid)]
                     [left-vals  (vector-slice new-vals 0 mid)]
                     [right-keys (vector-slice new-keys mid new-n)]
                     [right-vals (vector-slice new-vals mid new-n)]
                     [sep        (vector-ref right-keys 0)])
                (values (vector 'split
                                (make-leaf-node left-keys left-vals)
                                sep
                                (make-leaf-node right-keys right-vals))
                        #t))
              (values (make-leaf-node new-keys new-vals) #t)))))))

  ;; ========== Internal node split ==========
  ;; Returns (values left sep right).

  (define (split-internal node order)
    (let* ([keys     (node-keys node)]
           [children (node-data node)]
           [n        (vector-length keys)]
           [mid      order]  ;; separator is keys[mid], promoted up
           [sep      (vector-ref keys mid)])
      (values (make-internal-node (vector-slice keys 0 mid)
                                  (vector-slice children 0 (+ mid 1)))
              sep
              (make-internal-node (vector-slice keys (+ mid 1) n)
                                  (vector-slice children (+ mid 1) (+ n 1))))))

  ;; ========== Internal node: promote a child split ==========
  ;; child-idx: the index of the child that split (into left/sep/right).
  ;; Returns a node or a split vector if this node also overflows.

  (define (internal-promote node child-idx left sep right order)
    (let* ([keys (node-keys node)]
           [data (node-data node)]
           [n    (vector-length keys)]
           [nc   (vector-length data)])
      ;; New keys: insert sep at position child-idx
      (let ([new-keys (vector-insert keys child-idx sep)]
            ;; New children: replace data[child-idx] with left, insert right at child-idx+1
            [new-ch (let ([r (make-vector (+ nc 1))])
                      ;; Copy data[0..child-idx) into r[0..]
                      (vector-copy! data 0 r 0 child-idx)
                      ;; Place left at child-idx
                      (vector-set! r child-idx left)
                      ;; Place right at child-idx+1
                      (vector-set! r (+ child-idx 1) right)
                      ;; Copy data[child-idx+1..nc) into r[child-idx+2..]
                      (vector-copy! data (+ child-idx 1) r (+ child-idx 2) (- nc (+ child-idx 1)))
                      r)])
        (if (> (vector-length new-keys) (* 2 order))
          (let-values ([(l s r) (split-internal (make-internal-node new-keys new-ch) order)])
            (vector 'split l s r))
          (make-internal-node new-keys new-ch)))))

  ;; ========== Tree insertion ==========

  (define (node-insert root key val order)
    (define (ins node)
      (if (node-leaf? node)
        (leaf-insert node key val order)
        (let* ([keys      (node-keys node)]
               [data      (node-data node)]
               ;; Use bisect-right: keys < separator go LEFT, keys >= separator go RIGHT
               [child-idx (bisect-right keys key)])
          (let-values ([(result added?) (ins (vector-ref data child-idx))])
            (if (and (vector? result)
                     (> (vector-length result) 0)
                     (eq? (vector-ref result 0) 'split))
              (let* ([left  (vector-ref result 1)]
                     [sep   (vector-ref result 2)]
                     [right (vector-ref result 3)]
                     [promoted (internal-promote node child-idx left sep right order)])
                (values promoted added?))
              ;; No split: replace updated child
              (let ([new-ch (vector-copy data)])
                (vector-set! new-ch child-idx result)
                (values (make-internal-node keys new-ch) added?)))))))
    (ins root))

  ;; ========== Tree deletion ==========
  ;; Simple deletion without rebalancing.

  (define (node-delete node key)
    (define (del nd)
      (let ([keys (node-keys nd)]
            [data (node-data nd)])
        (if (node-leaf? nd)
          (let ([idx (bisect-left keys key)])
            (if (and (< idx (vector-length keys)) (key=? (vector-ref keys idx) key))
              (values (make-leaf-node (vector-remove keys idx)
                                      (vector-remove data idx))
                      #t)
              (values nd #f)))
          (let ([child-idx (bisect-right keys key)])
            (let-values ([(new-child deleted?) (del (vector-ref data child-idx))])
              (if deleted?
                (let ([new-ch (vector-copy data)])
                  (vector-set! new-ch child-idx new-child)
                  (values (make-internal-node keys new-ch) #t))
                (values nd #f)))))))
    (del node))

  ;; ========== In-order traversal ==========

  (define (node-fold node proc acc)
    (if (node-leaf? node)
      (let ([keys (node-keys node)]
            [vals (node-data node)]
            [n    (vector-length (node-keys node))])
        (let loop ([i 0] [a acc])
          (if (= i n)
            a
            (loop (+ i 1)
                  (proc (vector-ref keys i) (vector-ref vals i) a)))))
      (let ([children (node-data node)]
            [nc (+ (vector-length (node-keys node)) 1)])
        (let loop ([i 0] [a acc])
          (if (= i nc)
            a
            (loop (+ i 1)
                  (node-fold (vector-ref children i) proc a)))))))

  ;; ========== Btree record ==========

  (define-record-type %btree
    (fields
      (immutable path)
      (immutable order)
      (mutable   root)
      (mutable   size)
      (mutable   closed?)
      (mutable   snapshot))  ;; (root . size) for rollback, or #f
    (protocol
      (lambda (new)
        (lambda (path order root size)
          (new path order root size #f #f)))))

  (define (btree? x) (%btree? x))
  (define (btree-order t) (%btree-order t))
  (define (btree-size t)  (%btree-size t))
  (define (btree-path t)  (%btree-path t))

  (define (assert-open! who t)
    (when (%btree-closed? t)
      (error who "btree is closed" t)))

  ;; ========== File I/O ==========

  (define *file-magic* "JERBOA-BTREE-V1")

  (define (btree-save! t)
    (let ([path (%btree-path t)])
      (call-with-output-file path
        (lambda (port)
          (write *file-magic* port)
          (newline port)
          (write (%btree-order t) port)
          (newline port)
          (write (%btree-size t) port)
          (newline port)
          (write (%btree-root t) port)
          (newline port))
        'truncate)))

  (define (btree-load path)
    ;; Returns (values root size), or an empty tree if file missing/corrupt.
    (if (file-exists? path)
      (call-with-input-file path
        (lambda (port)
          (let ([magic (read port)])
            (if (equal? magic *file-magic*)
              (let* ([_order (read port)]
                     [size   (read port)]
                     [root   (read port)])
                (values root size))
              (values (make-leaf-node '#() '#()) 0)))))
      (values (make-leaf-node '#() '#()) 0)))

  ;; ========== open-btree ==========
  ;; (open-btree path)           — default order 4
  ;; (open-btree path 'order n)  — custom branching factor n

  (define (open-btree path . opts)
    (let ([order (let loop ([o opts])
                   (cond
                     [(null? o) 4]
                     [(and (pair? o) (eq? (car o) 'order) (pair? (cdr o)))
                      (cadr o)]
                     [else (loop (cdr o))]))])
      (let-values ([(root size) (btree-load path)])
        (make-%btree path order root size))))

  ;; ========== close-btree ==========

  (define (close-btree t)
    (assert-open! 'close-btree t)
    (btree-save! t)
    (%btree-closed?-set! t #t))

  ;; ========== btree-get ==========

  (define (btree-get t key)
    (assert-open! 'btree-get t)
    (node-search (%btree-root t) key))

  ;; ========== btree-has? ==========

  (define (btree-has? t key)
    (assert-open! 'btree-has? t)
    (if (node-search (%btree-root t) key) #t #f))

  ;; ========== btree-put! ==========

  (define (btree-put! t key val)
    (assert-open! 'btree-put! t)
    (let-values ([(result added?) (node-insert (%btree-root t) key val (%btree-order t))])
      (if (and (vector? result) (> (vector-length result) 0)
               (eq? (vector-ref result 0) 'split))
        ;; Root was split: create new root with one key and two children
        (let ([new-root (make-internal-node
                          (vector (vector-ref result 2))
                          (vector (vector-ref result 1)
                                  (vector-ref result 3)))])
          (%btree-root-set! t new-root))
        (%btree-root-set! t result))
      (when added?
        (%btree-size-set! t (+ (%btree-size t) 1)))))

  ;; ========== btree-delete! ==========

  (define (btree-delete! t key)
    (assert-open! 'btree-delete! t)
    (let-values ([(new-root deleted?) (node-delete (%btree-root t) key)])
      (%btree-root-set! t new-root)
      (when deleted?
        (%btree-size-set! t (- (%btree-size t) 1)))))

  ;; ========== btree-fold ==========
  ;; (proc key val acc) -> new-acc, in sorted key order

  (define (btree-fold t proc init)
    (assert-open! 'btree-fold t)
    (node-fold (%btree-root t) proc init))

  ;; ========== btree-keys / btree-values ==========

  (define (btree-keys t)
    (assert-open! 'btree-keys t)
    (reverse (btree-fold t (lambda (k v acc) (cons k acc)) '())))

  (define (btree-values t)
    (assert-open! 'btree-values t)
    (reverse (btree-fold t (lambda (k v acc) (cons v acc)) '())))

  ;; ========== btree-range ==========
  ;; Returns alist of (key . val) for keys in [lo, hi] inclusive.

  (define (btree-range t lo hi)
    (assert-open! 'btree-range t)
    (reverse
      (btree-fold t
        (lambda (k v acc)
          (if (and (not (key<? k lo)) (not (key<? hi k)))
            (cons (cons k v) acc)
            acc))
        '())))

  ;; ========== btree->alist / alist->btree ==========

  (define (btree->alist t)
    (assert-open! 'btree->alist t)
    (reverse (btree-fold t (lambda (k v acc) (cons (cons k v) acc)) '())))

  (define (alist->btree path alist)
    (let ([t (open-btree path)])
      (for-each (lambda (pair) (btree-put! t (car pair) (cdr pair))) alist)
      t))

  ;; ========== Transactions ==========

  (define (btree-commit! t)
    (assert-open! 'btree-commit! t)
    (%btree-snapshot-set! t #f)
    (btree-save! t))

  (define (btree-rollback! t)
    (assert-open! 'btree-rollback! t)
    (let ([snap (%btree-snapshot t)])
      (when snap
        (%btree-root-set! t (car snap))
        (%btree-size-set! t (cdr snap))
        (%btree-snapshot-set! t #f))))

  (define-syntax with-btree-transaction
    (syntax-rules ()
      [(_ tree body ...)
       (let ([t tree])
         ;; Capture snapshot before transaction begins
         (%btree-snapshot-set! t (cons (%btree-root t) (%btree-size t)))
         (with-exception-handler
           (lambda (exn)
             (btree-rollback! t)
             (raise exn))
           (lambda ()
             (let ([result (begin body ...)])
               (btree-commit! t)
               result))))]))

) ;; end library
