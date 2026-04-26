#!chezscheme
;;; (std clojure zip) — clojure.zip compatibility
;;;
;;; A zipper is a functional pointer into a tree.  It carries the
;;; "current" subtree along with enough context (path back to the
;;; root, and unvisited siblings on either side) to reconstruct the
;;; whole tree on demand.  All movement and edits are pure: every
;;; operation returns a new zipper.
;;;
;;; A zipper is built by handing `zipper` three procedures plus the
;;; root tree:
;;;
;;;   branch?  (lambda (node) ...)   ;; can node have children?
;;;   children (lambda (node) ...)   ;; → list of child nodes
;;;   make     (lambda (node kids) ...) ;; reassemble node from kids
;;;
;;; For convenience, three pre-baked zippers are provided:
;;;
;;;   (seq-zip    root)   ;; lists; branch? = list?
;;;   (vector-zip root)   ;; vectors; branch? = vector?
;;;   (xml-zip    root)   ;; SXML-style nodes (tag . children-list)
;;;
;;; Movement:    up down left right
;;; Inspection:  node branch? children
;;; Editing:     replace edit insert-left insert-right
;;;              insert-child append-child remove
;;; Termination: root  end?  next  prev

(library (std clojure zip)
  (export
    zipper seq-zip vector-zip xml-zip
    zip? node branch? children make-node
    up down left right
    leftmost rightmost
    lefts rights path
    replace edit insert-left insert-right
    insert-child append-child remove
    root end? next prev)

  (import (except (chezscheme) remove))

  ;; ---- record ---------------------------------------------------
  ;;
  ;; A zipper holds the current node and a "loc" — the contextual
  ;; information needed to walk back to the root.  The branch?,
  ;; children, and make-node procedures travel with the zipper so
  ;; that all operations stay polymorphic across container kinds.

  (define-record-type zip
    (fields (immutable node)
            (immutable loc)        ;; #f at root, else (parent-zip ls rs)
            (immutable branch?-p)
            (immutable children-p)
            (immutable make-p)
            (immutable end?-flag))
    (sealed #t))

  (define (node z) (zip-node z))

  (define (branch? z)
    ((zip-branch?-p z) (zip-node z)))

  (define (children z)
    (cond
      [(branch? z) ((zip-children-p z) (zip-node z))]
      [else (error 'children "called on a leaf node" z)]))

  (define (make-node z n kids)
    ((zip-make-p z) n kids))

  ;; ---- constructors --------------------------------------------

  (define (zipper branch?-p children-p make-p root)
    (make-zip root #f branch?-p children-p make-p #f))

  (define (seq-zip root)
    (zipper list? values
            (lambda (_node kids) kids)
            root))

  (define (vector-zip root)
    (zipper vector? vector->list
            (lambda (_node kids) (list->vector kids))
            root))

  ;; SXML-style: a branch is a pair whose car is a tag (symbol or
  ;; string) and whose cdr is the list of children.  Leaves are
  ;; everything else.
  (define (xml-zip root)
    (zipper (lambda (n)
              (and (pair? n)
                   (or (symbol? (car n)) (string? (car n)))))
            cdr
            (lambda (n kids) (cons (car n) kids))
            root))

  ;; ---- a "loc" carries: parent-zip + lefts (reversed) + rights ----

  (define-record-type loc
    (fields (immutable parent)     ;; zip pointing at the parent node
            (immutable ls)         ;; siblings to the left, REVERSED
            (immutable rs))        ;; siblings to the right
    (sealed #t))

  ;; ---- movement -------------------------------------------------

  (define (down z)
    (cond
      [(not (branch? z)) #f]
      [else
       (let ([kids (children z)])
         (cond
           [(null? kids) #f]
           [else
            (make-zip (car kids)
                      (make-loc z '() (cdr kids))
                      (zip-branch?-p z)
                      (zip-children-p z)
                      (zip-make-p z)
                      #f)]))]))

  (define (up z)
    (let ([l (zip-loc z)])
      (cond
        [(not l) #f]
        [else
         (let* ([p     (loc-parent l)]
                [kids  (append (reverse (loc-ls l))
                               (cons (zip-node z) (loc-rs l)))]
                [new-p (make-node p (zip-node p) kids)])
           (make-zip new-p
                     (zip-loc p)
                     (zip-branch?-p z)
                     (zip-children-p z)
                     (zip-make-p z)
                     #f))])))

  (define (left z)
    (let ([l (zip-loc z)])
      (cond
        [(or (not l) (null? (loc-ls l))) #f]
        [else
         (make-zip (car (loc-ls l))
                   (make-loc (loc-parent l)
                             (cdr (loc-ls l))
                             (cons (zip-node z) (loc-rs l)))
                   (zip-branch?-p z)
                   (zip-children-p z)
                   (zip-make-p z)
                   #f)])))

  (define (right z)
    (let ([l (zip-loc z)])
      (cond
        [(or (not l) (null? (loc-rs l))) #f]
        [else
         (make-zip (car (loc-rs l))
                   (make-loc (loc-parent l)
                             (cons (zip-node z) (loc-ls l))
                             (cdr (loc-rs l)))
                   (zip-branch?-p z)
                   (zip-children-p z)
                   (zip-make-p z)
                   #f)])))

  (define (leftmost z)
    (let lp ([z z])
      (let ([l (left z)])
        (if l (lp l) z))))

  (define (rightmost z)
    (let lp ([z z])
      (let ([r (right z)])
        (if r (lp r) z))))

  (define (lefts z)
    (cond
      [(zip-loc z) => (lambda (l) (reverse (loc-ls l)))]
      [else '()]))

  (define (rights z)
    (cond
      [(zip-loc z) => (lambda (l) (loc-rs l))]
      [else '()]))

  ;; Walk to the root of a zipper, return the list of nodes from
  ;; root → current.
  (define (path z)
    (let lp ([z z] [acc (list (zip-node z))])
      (let ([u (up z)])
        (if u (lp u (cons (zip-node u) acc)) acc))))

  ;; ---- editing --------------------------------------------------

  (define (replace z new-node)
    (make-zip new-node
              (zip-loc z)
              (zip-branch?-p z)
              (zip-children-p z)
              (zip-make-p z)
              #f))

  (define (edit z f . args)
    (replace z (apply f (zip-node z) args)))

  (define (insert-left z x)
    (let ([l (zip-loc z)])
      (cond
        [(not l) (error 'insert-left "at root")]
        [else
         (make-zip (zip-node z)
                   (make-loc (loc-parent l)
                             (cons x (loc-ls l))
                             (loc-rs l))
                   (zip-branch?-p z)
                   (zip-children-p z)
                   (zip-make-p z)
                   #f)])))

  (define (insert-right z x)
    (let ([l (zip-loc z)])
      (cond
        [(not l) (error 'insert-right "at root")]
        [else
         (make-zip (zip-node z)
                   (make-loc (loc-parent l)
                             (loc-ls l)
                             (cons x (loc-rs l)))
                   (zip-branch?-p z)
                   (zip-children-p z)
                   (zip-make-p z)
                   #f)])))

  (define (insert-child z x)
    (cond
      [(not (branch? z))
       (error 'insert-child "leaf has no children" z)]
      [else
       (let* ([kids (children z)]
              [new  (make-node z (zip-node z) (cons x kids))])
         (replace z new))]))

  (define (append-child z x)
    (cond
      [(not (branch? z))
       (error 'append-child "leaf has no children" z)]
      [else
       (let* ([kids (children z)]
              [new  (make-node z (zip-node z) (append kids (list x)))])
         (replace z new))]))

  ;; Remove the current node, returning the zipper at the location
  ;; of the previous sibling (or parent if there is no left sibling).
  (define (remove z)
    (let ([l (zip-loc z)])
      (cond
        [(not l) (error 'remove "at root")]
        [(not (null? (loc-ls l)))
         (make-zip (car (loc-ls l))
                   (make-loc (loc-parent l)
                             (cdr (loc-ls l))
                             (loc-rs l))
                   (zip-branch?-p z)
                   (zip-children-p z)
                   (zip-make-p z)
                   #f)]
        [else
         ;; No left sibling: rebuild parent with the right siblings
         ;; only and return that as the new current.
         (let* ([p     (loc-parent l)]
                [new-p (make-node p (zip-node p) (loc-rs l))])
           (make-zip new-p
                     (zip-loc p)
                     (zip-branch?-p z)
                     (zip-children-p z)
                     (zip-make-p z)
                     #f))])))

  ;; ---- termination ---------------------------------------------

  (define (root z)
    (let lp ([z z])
      (let ([u (up z)])
        (if u (lp u) (zip-node z)))))

  (define (end? z) (zip-end?-flag z))

  ;; Depth-first, in-order: down, then right, then up+right, ... .
  (define (next z)
    (cond
      [(end? z) z]
      [(branch? z)
       (let ([d (down z)])
         (or d (next-after z)))]
      [else (next-after z)]))

  (define (next-after z)
    (let lp ([z z])
      (cond
        [(right z) => (lambda (r) r)]
        [else
         (let ([u (up z)])
           (cond
             [(not u)
              ;; Done — flag terminal zipper with end?-flag = #t.
              (make-zip (zip-node z) #f
                        (zip-branch?-p z)
                        (zip-children-p z)
                        (zip-make-p z)
                        #t)]
             [else (lp u)]))])))

  ;; Reverse traversal: cousin of `next`.
  (define (prev z)
    (cond
      [(left z)
       => (lambda (l)
            ;; Descend rightmost branches until a leaf is reached.
            (let lp ([z l])
              (cond
                [(branch? z)
                 (let ([d (down z)])
                   (cond
                     [d (lp (rightmost d))]
                     [else z]))]
                [else z])))]
      [else (up z)]))

) ;; end library
