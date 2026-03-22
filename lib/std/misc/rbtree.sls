#!chezscheme
;;; (std misc rbtree) -- Red-Black Balanced Binary Search Tree
;;;
;;; Functional (persistent) left-leaning red-black tree.
;;; All mutation-sounding operations return new trees; the original
;;; is unchanged.
;;;
;;; Usage:
;;;   (import (std misc rbtree))
;;;   (define t (make-rbtree <))
;;;   (define t1 (rbtree-insert t 3 "three"))
;;;   (define t2 (rbtree-insert t1 1 "one"))
;;;   (define t3 (rbtree-insert t2 2 "two"))
;;;   (rbtree-lookup t3 2)          ; => "two"
;;;   (rbtree-contains? t3 4)       ; => #f
;;;   (rbtree-min t3)               ; => (1 . "one")
;;;   (rbtree->list t3)             ; => ((1 . "one") (2 . "two") (3 . "three"))
;;;   (rbtree-size t3)              ; => 3
;;;   (rbtree-fold (lambda (k v a) (+ a v)) 0 numeric-tree)

(library (std misc rbtree)
  (export
    make-rbtree
    rbtree?
    rbtree-insert
    rbtree-lookup
    rbtree-delete
    rbtree-contains?
    rbtree-min
    rbtree-max
    rbtree-fold
    rbtree->list
    rbtree-size
    rbtree-empty?)

  (import (chezscheme))

  ;; ========== Node Representation ==========
  ;; We use plain vectors for nodes to keep it simple and fast.
  ;; node = #(color left key value right)
  ;; color: 'red or 'black
  ;; leaf = #f

  (define (node color left key value right)
    (vector color left key value right))

  (define (node? n) (vector? n))
  (define (node-color n) (vector-ref n 0))
  (define (node-left n) (vector-ref n 1))
  (define (node-key n) (vector-ref n 2))
  (define (node-value n) (vector-ref n 3))
  (define (node-right n) (vector-ref n 4))

  (define (red? n) (and n (eq? (node-color n) 'red)))
  (define (black? n) (or (not n) (eq? (node-color n) 'black)))

  (define (paint-red n)
    (if n (node 'red (node-left n) (node-key n) (node-value n) (node-right n)) n))
  (define (paint-black n)
    (if n (node 'black (node-left n) (node-key n) (node-value n) (node-right n)) n))

  ;; ========== Tree Record ==========
  (define-record-type rbtree-rec
    (fields (immutable less?)     ;; comparator
            (immutable root)      ;; root node or #f
            (immutable count))    ;; number of elements
    (protocol (lambda (new)
      (lambda (less? root count)
        (new less? root count)))))

  (define (rbtree? x) (rbtree-rec? x))

  (define (make-rbtree less?)
    (make-rbtree-rec less? #f 0))

  (define (rbtree-empty? t)
    (not (rbtree-rec-root t)))

  (define (rbtree-size t)
    (rbtree-rec-count t))

  ;; ========== LLRB Rotations ==========

  (define (rotate-left h)
    ;; h.right becomes new root
    (let ([x (node-right h)])
      (node (node-color h)
            (node (node-color x) (node-left h) (node-key h) (node-value h) (node-left x))
            (node-key x) (node-value x)
            (node-right x))))

  (define (rotate-right h)
    ;; h.left becomes new root
    (let ([x (node-left h)])
      (node (node-color h)
            (node-left x)
            (node-key x) (node-value x)
            (node (node-color x) (node-right x) (node-key h) (node-value h) (node-right h)))))

  (define (flip-colors h)
    ;; Flip colors of h and both children
    (let ([new-color (if (red? h) 'black 'red)]
          [child-color (if (red? h) 'red 'black)])
      (node new-color
            (if (node-left h)
              (node child-color
                    (node-left (node-left h))
                    (node-key (node-left h))
                    (node-value (node-left h))
                    (node-right (node-left h)))
              #f)
            (node-key h) (node-value h)
            (if (node-right h)
              (node child-color
                    (node-left (node-right h))
                    (node-key (node-right h))
                    (node-value (node-right h))
                    (node-right (node-right h)))
              #f))))

  ;; ========== LLRB Fixup ==========
  (define (fixup h)
    (let* ([h (if (and (red? (node-right h)) (black? (node-left h)))
                (rotate-left h)
                h)]
           [h (if (and (red? (node-left h))
                       (node-left h)
                       (red? (node-left (node-left h))))
                (rotate-right h)
                h)]
           [h (if (and (red? (node-left h)) (red? (node-right h)))
                (flip-colors h)
                h)])
      h))

  ;; ========== Insert ==========

  (define (node-insert h key value less?)
    (if (not h)
      ;; New node is always red
      (node 'red #f key value #f)
      (let ([h (if (and (red? (node-left h)) (red? (node-right h)))
                 (flip-colors h)
                 h)])
        (cond
          [(less? key (node-key h))
           (fixup (node (node-color h)
                        (node-insert (node-left h) key value less?)
                        (node-key h) (node-value h)
                        (node-right h)))]
          [(less? (node-key h) key)
           (fixup (node (node-color h)
                        (node-left h)
                        (node-key h) (node-value h)
                        (node-insert (node-right h) key value less?)))]
          [else
           ;; Key already exists, replace value
           (node (node-color h) (node-left h) key value (node-right h))]))))

  (define (rbtree-insert t key value)
    (let* ([less? (rbtree-rec-less? t)]
           [old-root (rbtree-rec-root t)]
           [existed? (node-contains? old-root key less?)]
           [new-root (paint-black (node-insert old-root key value less?))]
           [new-count (if existed?
                       (rbtree-rec-count t)
                       (+ (rbtree-rec-count t) 1))])
      (make-rbtree-rec less? new-root new-count)))

  ;; ========== Lookup ==========

  (define (node-lookup h key less?)
    (if (not h)
      (values #f #f)
      (cond
        [(less? key (node-key h))
         (node-lookup (node-left h) key less?)]
        [(less? (node-key h) key)
         (node-lookup (node-right h) key less?)]
        [else
         (values (node-value h) #t)])))

  (define rbtree-lookup
    (case-lambda
      [(t key)
       (rbtree-lookup t key #f)]
      [(t key default)
       (let-values ([(val found?) (node-lookup (rbtree-rec-root t) key (rbtree-rec-less? t))])
         (if found? val default))]))

  (define (node-contains? h key less?)
    (if (not h)
      #f
      (cond
        [(less? key (node-key h))
         (node-contains? (node-left h) key less?)]
        [(less? (node-key h) key)
         (node-contains? (node-right h) key less?)]
        [else #t])))

  (define (rbtree-contains? t key)
    (node-contains? (rbtree-rec-root t) key (rbtree-rec-less? t)))

  ;; ========== Min / Max ==========

  (define (node-min h)
    (if (node-left h)
      (node-min (node-left h))
      h))

  (define (node-max h)
    (if (node-right h)
      (node-max (node-right h))
      h))

  (define (rbtree-min t)
    (when (rbtree-empty? t)
      (error 'rbtree-min "tree is empty"))
    (let ([n (node-min (rbtree-rec-root t))])
      (cons (node-key n) (node-value n))))

  (define (rbtree-max t)
    (when (rbtree-empty? t)
      (error 'rbtree-max "tree is empty"))
    (let ([n (node-max (rbtree-rec-root t))])
      (cons (node-key n) (node-value n))))

  ;; ========== Delete ==========
  ;; LLRB delete following Sedgewick's algorithm

  (define (move-red-left h)
    (let ([h (flip-colors h)])
      (if (and (node-right h) (red? (node-left (node-right h))))
        (let ([h (node (node-color h)
                       (node-left h)
                       (node-key h) (node-value h)
                       (rotate-right (node-right h)))])
          (rotate-left h))
        h)))

  (define (move-red-right h)
    (let ([h (flip-colors h)])
      (if (and (node-left h) (red? (node-left (node-left h))))
        (rotate-right h)
        h)))

  (define (delete-min h)
    (if (not (node-left h))
      #f  ;; leaf
      (let* ([h (if (and (black? (node-left h))
                         (node-left h)
                         (black? (node-left (node-left h))))
                  (move-red-left h)
                  h)]
             [new-left (delete-min (node-left h))])
        (fixup (node (node-color h) new-left
                     (node-key h) (node-value h)
                     (node-right h))))))

  (define (node-delete h key less?)
    (if (not h)
      #f
      (if (less? key (node-key h))
        ;; Go left
        (if (and (node-left h)
                 (black? (node-left h))
                 (node-left h)
                 (black? (node-left (node-left h))))
          (let ([h (move-red-left h)])
            (fixup (node (node-color h)
                         (node-delete (node-left h) key less?)
                         (node-key h) (node-value h)
                         (node-right h))))
          (fixup (node (node-color h)
                       (node-delete (node-left h) key less?)
                       (node-key h) (node-value h)
                       (node-right h))))
        ;; Key >= current
        (let* ([h (if (red? (node-left h))
                    (rotate-right h)
                    h)])
          (if (and (not (less? key (node-key h)))
                   (not (less? (node-key h) key))
                   (not (node-right h)))
            ;; Found at leaf, remove
            #f
            (let* ([h (if (and (node-right h)
                               (black? (node-right h))
                               (black? (node-left (node-right h))))
                       (move-red-right h)
                       h)])
              (if (and (not (less? key (node-key h)))
                       (not (less? (node-key h) key)))
                ;; Found, replace with successor
                (let ([succ (node-min (node-right h))])
                  (fixup (node (node-color h)
                               (node-left h)
                               (node-key succ) (node-value succ)
                               (delete-min (node-right h)))))
                ;; Go right
                (fixup (node (node-color h)
                             (node-left h)
                             (node-key h) (node-value h)
                             (node-delete (node-right h) key less?))))))))))

  (define (rbtree-delete t key)
    (let* ([less? (rbtree-rec-less? t)]
           [existed? (node-contains? (rbtree-rec-root t) key less?)])
      (if (not existed?)
        t  ;; key not present, return unchanged
        (let* ([new-root (node-delete (rbtree-rec-root t) key less?)]
               [new-root (if new-root (paint-black new-root) #f)])
          (make-rbtree-rec less? new-root (- (rbtree-rec-count t) 1))))))

  ;; ========== Fold and Conversion ==========

  (define (node-fold proc acc h)
    (if (not h)
      acc
      (let* ([acc (node-fold proc acc (node-left h))]
             [acc (proc (node-key h) (node-value h) acc)]
             [acc (node-fold proc acc (node-right h))])
        acc)))

  (define (rbtree-fold proc init t)
    (node-fold proc init (rbtree-rec-root t)))

  (define (rbtree->list t)
    ;; Returns sorted alist via in-order traversal
    (reverse
      (rbtree-fold (lambda (k v acc) (cons (cons k v) acc)) '() t)))

) ;; end library
