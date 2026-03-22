#!chezscheme
;;; :std/srfi/101 -- Purely Functional Random-Access Lists (SRFI-101)
;;; Skew binary random-access list: a list of complete binary trees.
;;; O(1) cons/car/cdr, O(log n) ref/set.

(library (std srfi srfi-101)
  (export
    ra:cons ra:car ra:cdr ra:pair? ra:null? ra:list ra:list?
    ra:list-ref ra:list-set ra:list-ref/update
    ra:length ra:append ra:map ra:for-each ra:fold
    ra:list->ra-list ra-list->list)

  (import (chezscheme))

  ;; A tree node: either a leaf or a branch with value + left + right subtrees.
  ;; Each tree has weight = 2^k - 1 (a complete binary tree).
  (define-record-type leaf
    (fields val)
    (sealed #t))

  (define-record-type node
    (fields val left right)
    (sealed #t))

  ;; A random-access list is a list of (weight . tree) pairs
  ;; stored in order of increasing weight (skew binary representation).
  ;; The ra-list itself is just a regular Scheme list of entries.
  (define-record-type entry
    (fields (immutable weight)
            (immutable tree))
    (sealed #t))

  (define ra-null '())

  (define (ra:null? x) (null? x))

  (define (ra:pair? x)
    (and (pair? x) (entry? (car x))))

  (define (ra:list? x)
    (or (null? x)
        (and (pair? x) (entry? (car x)) (ra:list? (cdr x)))))

  ;; cons: if first two trees have same weight, merge them
  (define (ra:cons x ls)
    (if (and (pair? ls)
             (pair? (cdr ls))
             (= (entry-weight (car ls))
                (entry-weight (cadr ls))))
        (cons (make-entry (+ 1 (entry-weight (car ls))
                             (entry-weight (cadr ls)))
                          (make-node x
                                     (entry-tree (car ls))
                                     (entry-tree (cadr ls))))
              (cddr ls))
        (cons (make-entry 1 (make-leaf x)) ls)))

  (define (ra:car ls)
    (when (null? ls)
      (error 'ra:car "empty list"))
    (let ([t (entry-tree (car ls))])
      (if (leaf? t)
          (leaf-val t)
          (node-val t))))

  (define (ra:cdr ls)
    (when (null? ls)
      (error 'ra:cdr "empty list"))
    (let ([e (car ls)]
          [rest (cdr ls)])
      (let ([t (entry-tree e)]
            [w (entry-weight e)])
        (if (leaf? t)
            rest
            (let ([hw (quotient w 2)])
              (cons (make-entry hw (node-left t))
                    (cons (make-entry hw (node-right t))
                          rest)))))))

  (define (ra:list . args)
    (fold-right ra:cons ra-null args))

  ;; tree-ref: index into a complete binary tree of given weight
  (define (tree-ref w t i)
    (cond
      [(leaf? t)
       (if (zero? i) (leaf-val t)
           (error 'ra:list-ref "index out of range" i))]
      [(zero? i) (node-val t)]
      [else
       (let ([hw (quotient w 2)])
         (if (<= i hw)
             (tree-ref hw (node-left t) (- i 1))
             (tree-ref hw (node-right t) (- i 1 hw))))]))

  ;; tree-set: functional update in a complete binary tree
  (define (tree-set w t i v)
    (cond
      [(leaf? t)
       (if (zero? i) (make-leaf v)
           (error 'ra:list-set "index out of range" i))]
      [(zero? i) (make-node v (node-left t) (node-right t))]
      [else
       (let ([hw (quotient w 2)])
         (if (<= i hw)
             (make-node (node-val t)
                        (tree-set hw (node-left t) (- i 1) v)
                        (node-right t))
             (make-node (node-val t)
                        (node-left t)
                        (tree-set hw (node-right t) (- i 1 hw) v))))]))

  ;; tree-ref/update: returns both old value and updated tree
  (define (tree-ref/update w t i f)
    (cond
      [(leaf? t)
       (if (zero? i)
           (let ([old (leaf-val t)])
             (values old (make-leaf (f old))))
           (error 'ra:list-ref/update "index out of range" i))]
      [(zero? i)
       (let ([old (node-val t)])
         (values old (make-node (f old) (node-left t) (node-right t))))]
      [else
       (let ([hw (quotient w 2)])
         (if (<= i hw)
             (let-values ([(old new-left) (tree-ref/update hw (node-left t) (- i 1) f)])
               (values old (make-node (node-val t) new-left (node-right t))))
             (let-values ([(old new-right) (tree-ref/update hw (node-right t) (- i 1 hw) f)])
               (values old (make-node (node-val t) (node-left t) new-right)))))]))

  (define (ra:list-ref ls i)
    (when (< i 0) (error 'ra:list-ref "negative index" i))
    (let loop ([ls ls] [i i])
      (when (null? ls) (error 'ra:list-ref "index out of range" i))
      (let ([w (entry-weight (car ls))])
        (if (< i w)
            (tree-ref w (entry-tree (car ls)) i)
            (loop (cdr ls) (- i w))))))

  (define (ra:list-set ls i v)
    (when (< i 0) (error 'ra:list-set "negative index" i))
    (let loop ([ls ls] [i i])
      (when (null? ls) (error 'ra:list-set "index out of range" i))
      (let ([e (car ls)]
            [rest (cdr ls)])
        (let ([w (entry-weight e)])
          (if (< i w)
              (cons (make-entry w (tree-set w (entry-tree e) i v)) rest)
              (cons e (loop rest (- i w))))))))

  (define (ra:list-ref/update ls i f)
    (when (< i 0) (error 'ra:list-ref/update "negative index" i))
    (let loop ([ls ls] [i i])
      (when (null? ls) (error 'ra:list-ref/update "index out of range" i))
      (let ([e (car ls)]
            [rest (cdr ls)])
        (let ([w (entry-weight e)])
          (if (< i w)
              (let-values ([(old new-tree) (tree-ref/update w (entry-tree e) i f)])
                (values old (cons (make-entry w new-tree) rest)))
              (let-values ([(old new-rest) (loop rest (- i w))])
                (values old (cons e new-rest))))))))

  (define (ra:length ls)
    (let loop ([ls ls] [n 0])
      (if (null? ls) n
          (loop (cdr ls) (+ n (entry-weight (car ls)))))))

  (define (ra:append . lsts)
    (if (null? lsts) ra-null
        (let loop ([lsts lsts])
          (if (null? (cdr lsts))
              (car lsts)
              (let ([a (ra-list->list (car lsts))]
                    [rest (loop (cdr lsts))])
                (fold-right ra:cons rest a))))))

  (define (ra:map f ls)
    (if (ra:null? ls) ra-null
        (ra:cons (f (ra:car ls))
                 (ra:map f (ra:cdr ls)))))

  (define (ra:for-each f ls)
    (unless (ra:null? ls)
      (f (ra:car ls))
      (ra:for-each f (ra:cdr ls))))

  (define (ra:fold f seed ls)
    (if (ra:null? ls) seed
        (ra:fold f (f (ra:car ls) seed) (ra:cdr ls))))

  (define (ra:list->ra-list ls)
    (fold-right ra:cons ra-null ls))

  (define (ra-list->list ls)
    (if (ra:null? ls) '()
        (cons (ra:car ls) (ra-list->list (ra:cdr ls)))))
)
