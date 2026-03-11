#!chezscheme
;;; std/ds/sorted-map.sls -- Persistent sorted map using red-black trees

(library (std ds sorted-map)
  (export
    sorted-map-empty sorted-map? sorted-map-size
    sorted-map-insert sorted-map-lookup sorted-map-delete
    sorted-map-min sorted-map-max
    sorted-map-fold sorted-map->alist alist->sorted-map
    sorted-map-keys sorted-map-values
    sorted-map-range
    make-sorted-map)

  (import (chezscheme))

  ;; ---- Red-Black Tree Representation ----
  ;; Node: #(color key value left right)
  ;; color: 'R (red) or 'B (black)
  ;; Empty: #f

  (define *empty* #f)

  (define (node-color  n) (vector-ref n 0))
  (define (node-key    n) (vector-ref n 1))
  (define (node-value  n) (vector-ref n 2))
  (define (node-left   n) (vector-ref n 3))
  (define (node-right  n) (vector-ref n 4))

  (define (make-node color key value left right)
    (vector color key value left right))

  (define (red?   n) (and n (eq? (node-color n) 'R)))
  (define (black? n) (or (not n) (eq? (node-color n) 'B)))

  ;; ---- Sorted map record ----
  ;; Wraps the tree root + comparator + size

  (define-record-type sorted-map-rec
    (fields root cmp size)
    (protocol
      (lambda (new)
        (lambda (root cmp size)
          (new root cmp size)))))

  (define (sorted-map? x) (sorted-map-rec? x))

  ;; ---- sorted-map-empty ----

  (define (sorted-map-empty)
    (make-sorted-map-rec *empty* default-cmp 0))

  (define (make-sorted-map cmp)
    (make-sorted-map-rec *empty* cmp 0))

  ;; ---- Default comparator ----

  (define (default-cmp a b)
    (cond
      [(and (number? a) (number? b))
       (cond [(< a b) -1] [(> a b) 1] [else 0])]
      [(and (string? a) (string? b))
       (cond [(string<? a b) -1] [(string>? a b) 1] [else 0])]
      [(and (symbol? a) (symbol? b))
       (let ([sa (symbol->string a)] [sb (symbol->string b)])
         (cond [(string<? sa sb) -1] [(string>? sa sb) 1] [else 0]))]
      [else
       (let ([sa (format "~s" a)] [sb (format "~s" b)])
         (cond [(string<? sa sb) -1] [(string>? sa sb) 1] [else 0]))]))

  ;; ---- Balance ----
  ;; Standard Okasaki balance cases for left-leaning RB trees

  (define (balance color key value left right)
    (cond
      ;; Case 1: left-left
      [(and (eq? color 'B)
            (red? left)
            (red? (node-left left)))
       (make-node 'R
                  (node-key left)
                  (node-value left)
                  (make-node 'B
                             (node-key (node-left left))
                             (node-value (node-left left))
                             (node-left (node-left left))
                             (node-right (node-left left)))
                  (make-node 'B key value (node-right left) right))]
      ;; Case 2: left-right
      [(and (eq? color 'B)
            (red? left)
            (red? (node-right left)))
       (make-node 'R
                  (node-key (node-right left))
                  (node-value (node-right left))
                  (make-node 'B
                             (node-key left)
                             (node-value left)
                             (node-left left)
                             (node-left (node-right left)))
                  (make-node 'B key value
                             (node-right (node-right left))
                             right))]
      ;; Case 3: right-left
      [(and (eq? color 'B)
            (red? right)
            (red? (node-left right)))
       (make-node 'R
                  (node-key (node-left right))
                  (node-value (node-left right))
                  (make-node 'B key value left
                             (node-left (node-left right)))
                  (make-node 'B
                             (node-key right)
                             (node-value right)
                             (node-right (node-left right))
                             (node-right right)))]
      ;; Case 4: right-right
      [(and (eq? color 'B)
            (red? right)
            (red? (node-right right)))
       (make-node 'R
                  (node-key right)
                  (node-value right)
                  (make-node 'B key value left (node-left right))
                  (make-node 'B
                             (node-key (node-right right))
                             (node-value (node-right right))
                             (node-left (node-right right))
                             (node-right (node-right right))))]
      ;; Default
      [else
       (make-node color key value left right)]))

  ;; ---- sorted-map-insert ----

  (define (sorted-map-insert sm key value)
    (let* ([cmp  (sorted-map-rec-cmp sm)]
           [root (sorted-map-rec-root sm)]
           [found? #f]
           [new-root (ins root key value cmp found?)])
      ;; Make root black
      (let ([black-root (make-node 'B
                                   (node-key new-root)
                                   (node-value new-root)
                                   (node-left new-root)
                                   (node-right new-root))])
        ;; We need to know if key was already present to track size
        ;; Use a simpler approach: check membership first
        (let ([exists? (sorted-map-lookup sm key)])
          (make-sorted-map-rec
            black-root
            cmp
            (if exists?
                (sorted-map-rec-size sm)
                (+ (sorted-map-rec-size sm) 1)))))))

  (define (ins node key value cmp found)
    (if (not node)
        (make-node 'R key value *empty* *empty*)
        (let ([c (cmp key (node-key node))])
          (cond
            [(< c 0)
             (balance (node-color node)
                      (node-key node)
                      (node-value node)
                      (ins (node-left node) key value cmp found)
                      (node-right node))]
            [(> c 0)
             (balance (node-color node)
                      (node-key node)
                      (node-value node)
                      (node-left node)
                      (ins (node-right node) key value cmp found))]
            [else
             ;; Key exists: update value
             (make-node (node-color node) key value
                        (node-left node) (node-right node))]))))

  ;; ---- sorted-map-lookup ----

  (define (sorted-map-lookup sm key)
    (let ([cmp (sorted-map-rec-cmp sm)])
      (let search ([node (sorted-map-rec-root sm)])
        (if (not node)
            #f
            (let ([c (cmp key (node-key node))])
              (cond
                [(< c 0) (search (node-left node))]
                [(> c 0) (search (node-right node))]
                [else    (node-value node)]))))))

  ;; ---- sorted-map-size ----

  (define (sorted-map-size sm)
    (sorted-map-rec-size sm))

  ;; ---- sorted-map-min / sorted-map-max ----

  (define (sorted-map-min sm)
    (let loop ([node (sorted-map-rec-root sm)] [prev #f])
      (if (not node)
          prev
          (loop (node-left node) (cons (node-key node) (node-value node))))))

  (define (sorted-map-max sm)
    (let loop ([node (sorted-map-rec-root sm)] [prev #f])
      (if (not node)
          prev
          (loop (node-right node) (cons (node-key node) (node-value node))))))

  ;; ---- sorted-map-fold ----
  ;; In-order traversal: (proc key value acc) -> acc

  (define (sorted-map-fold sm proc init)
    (let traverse ([node (sorted-map-rec-root sm)] [acc init])
      (if (not node)
          acc
          (let* ([left-acc  (traverse (node-left node) acc)]
                 [mid-acc   (proc (node-key node) (node-value node) left-acc)])
            (traverse (node-right node) mid-acc)))))

  ;; ---- sorted-map->alist ----

  (define (sorted-map->alist sm)
    (reverse (sorted-map-fold sm
               (lambda (k v acc) (cons (cons k v) acc))
               '())))

  ;; ---- alist->sorted-map ----

  (define (alist->sorted-map alist . cmp-arg)
    (let ([sm (if (null? cmp-arg)
                  (sorted-map-empty)
                  (make-sorted-map (car cmp-arg)))])
      (fold-left
        (lambda (m kv) (sorted-map-insert m (car kv) (cdr kv)))
        sm
        alist)))

  ;; ---- sorted-map-keys / sorted-map-values ----

  (define (sorted-map-keys sm)
    (reverse (sorted-map-fold sm (lambda (k v acc) (cons k acc)) '())))

  (define (sorted-map-values sm)
    (reverse (sorted-map-fold sm (lambda (k v acc) (cons v acc)) '())))

  ;; ---- sorted-map-delete ----
  ;; Deletion from RB tree (using standard algorithm)

  (define (sorted-map-delete sm key)
    (let* ([cmp  (sorted-map-rec-cmp sm)]
           [root (sorted-map-rec-root sm)])
      (if (not (sorted-map-lookup sm key))
          sm  ; Key not found, return unchanged
          (let ([new-root (rb-delete root key cmp)])
            (let ([black-root (if new-root
                                  (make-node 'B
                                             (node-key new-root)
                                             (node-value new-root)
                                             (node-left new-root)
                                             (node-right new-root))
                                  *empty*)])
              (make-sorted-map-rec
                black-root
                cmp
                (- (sorted-map-rec-size sm) 1)))))))

  ;; Simple delete using rebuild approach
  (define (rb-delete node key cmp)
    (if (not node)
        *empty*
        (let ([c (cmp key (node-key node))])
          (cond
            [(< c 0)
             (let ([new-left (rb-delete (node-left node) key cmp)])
               (balance (node-color node)
                        (node-key node)
                        (node-value node)
                        new-left
                        (node-right node)))]
            [(> c 0)
             (let ([new-right (rb-delete (node-right node) key cmp)])
               (balance (node-color node)
                        (node-key node)
                        (node-value node)
                        (node-left node)
                        new-right))]
            [else
             ;; Found the node to delete
             (let ([left  (node-left node)]
                   [right (node-right node)])
               (cond
                 [(not left)  right]
                 [(not right) left]
                 [else
                  ;; Replace with in-order successor (leftmost of right subtree)
                  (let-values ([(succ-key succ-val new-right) (extract-min right)])
                    (balance (node-color node)
                             succ-key succ-val
                             left
                             new-right))]))]))))

  (define (extract-min node)
    (if (not (node-left node))
        (values (node-key node) (node-value node) (node-right node))
        (let-values ([(k v new-left) (extract-min (node-left node))])
          (values k v
                  (balance (node-color node)
                           (node-key node)
                           (node-value node)
                           new-left
                           (node-right node))))))

  ;; ---- sorted-map-range ----
  ;; Returns new sorted-map with only keys in [lo, hi]

  (define (sorted-map-range sm lo hi)
    (let ([cmp (sorted-map-rec-cmp sm)])
      (sorted-map-fold sm
        (lambda (k v acc)
          (if (and (>= (cmp k lo) 0)
                   (<= (cmp k hi) 0))
              (sorted-map-insert acc k v)
              acc))
        (make-sorted-map cmp))))

  ) ;; end library
