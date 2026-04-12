#!chezscheme
;;; (std zipper) — Functional Tree Zippers (Huet / clojure.zip)
;;;
;;; A zipper is a cursor into a tree that supports O(1) navigation
;;; (up, down, left, right) and editing (replace, insert, remove).
;;; The tree structure is parameterized: you supply branch?, children,
;;; and make-node functions to create a zipper for any tree type.
;;;
;;; Built-in: list-zipper for nested-list trees, vector-zipper for
;;; vector-based trees.

(library (std zipper)
  (export
    ;; Core
    zipper zipper?
    zip-node zip-root
    zip-up zip-down zip-left zip-right
    zip-leftmost zip-rightmost

    ;; Predicates
    zip-branch? zip-end? zip-top?

    ;; Editing
    zip-replace zip-edit zip-remove
    zip-insert-left zip-insert-right
    zip-insert-child zip-append-child

    ;; Children
    zip-children zip-lefts zip-rights
    zip-path

    ;; Navigation
    zip-next zip-prev

    ;; Built-in tree types
    list-zipper
    vector-zipper)

  (import (chezscheme))

  ;; A zipper location is a vector:
  ;; #(node path branch? children make-node)
  ;;
  ;; path is either #f (root) or:
  ;; #(left-siblings right-siblings parent-path parent-node
  ;;   branch? children make-node)

  (define (make-loc node path branch? children make-node)
    (vector node path branch? children make-node))

  (define (loc-node loc)      (vector-ref loc 0))
  (define (loc-path loc)      (vector-ref loc 1))
  (define (loc-branch? loc)   (vector-ref loc 2))
  (define (loc-children loc)  (vector-ref loc 3))
  (define (loc-make-node loc) (vector-ref loc 4))

  (define (make-path lefts rights parent-path parent-node
                     branch? children make-node)
    (vector lefts rights parent-path parent-node
            branch? children make-node))

  (define (path-lefts p)       (vector-ref p 0))
  (define (path-rights p)      (vector-ref p 1))
  (define (path-parent-path p) (vector-ref p 2))
  (define (path-parent-node p) (vector-ref p 3))
  (define (path-branch? p)     (vector-ref p 4))
  (define (path-children p)    (vector-ref p 5))
  (define (path-make-node p)   (vector-ref p 6))

  ;; =========================================================================
  ;; Construction
  ;; =========================================================================

  ;; Create a zipper for a tree. branch?, children, and make-node
  ;; parameterize the tree structure:
  ;;   branch?   : node -> boolean (can this node have children?)
  ;;   children  : node -> list    (get children of a branch node)
  ;;   make-node : node children -> node (create new node with given children)
  (define (zipper branch? children make-node root)
    (make-loc root #f branch? children make-node))

  (define (zipper? x)
    (and (vector? x) (= (vector-length x) 5)))

  ;; =========================================================================
  ;; Access
  ;; =========================================================================

  (define (zip-node loc) (loc-node loc))

  (define (zip-branch? loc)
    ((loc-branch? loc) (loc-node loc)))

  (define (zip-children loc)
    (if (zip-branch? loc)
      ((loc-children loc) (loc-node loc))
      (error 'zip-children "called on leaf node" (loc-node loc))))

  (define (zip-top? loc) (not (loc-path loc)))

  (define (zip-end? loc)
    ;; Sentinel: an end marker is a loc with eq? path 'end
    (and (vector? loc) (eq? (loc-path loc) 'end)))

  (define (zip-lefts loc)
    (let ([p (loc-path loc)])
      (if p (reverse (path-lefts p)) '())))

  (define (zip-rights loc)
    (let ([p (loc-path loc)])
      (if p (path-rights p) '())))

  (define (zip-path loc)
    ;; Return list of nodes from root to current (excluding current)
    (let loop ([p (loc-path loc)] [acc '()])
      (if (not p)
        acc
        (loop (path-parent-path p) (cons (path-parent-node p) acc)))))

  ;; =========================================================================
  ;; Navigation
  ;; =========================================================================

  (define (zip-down loc)
    (when (zip-end? loc) (error 'zip-down "at end"))
    (if (not (zip-branch? loc))
      #f  ;; can't go down on a leaf
      (let ([cs ((loc-children loc) (loc-node loc))])
        (if (null? cs)
          #f  ;; branch with no children
          (make-loc (car cs)
                    (make-path '() (cdr cs) (loc-path loc)
                               (loc-node loc)
                               (loc-branch? loc)
                               (loc-children loc)
                               (loc-make-node loc))
                    (loc-branch? loc)
                    (loc-children loc)
                    (loc-make-node loc))))))

  (define (zip-up loc)
    (let ([p (loc-path loc)])
      (if (not p)
        #f  ;; already at root
        (let ([new-children (append (reverse (path-lefts p))
                                    (cons (loc-node loc)
                                          (path-rights p)))])
          (make-loc ((loc-make-node loc) (path-parent-node p) new-children)
                    (path-parent-path p)
                    (path-branch? p)
                    (path-children p)
                    (path-make-node p))))))

  (define (zip-left loc)
    (let ([p (loc-path loc)])
      (if (or (not p) (null? (path-lefts p)))
        #f
        (make-loc (car (path-lefts p))
                  (make-path (cdr (path-lefts p))
                             (cons (loc-node loc) (path-rights p))
                             (path-parent-path p)
                             (path-parent-node p)
                             (path-branch? p)
                             (path-children p)
                             (path-make-node p))
                  (loc-branch? loc)
                  (loc-children loc)
                  (loc-make-node loc)))))

  (define (zip-right loc)
    (let ([p (loc-path loc)])
      (if (or (not p) (null? (path-rights p)))
        #f
        (make-loc (car (path-rights p))
                  (make-path (cons (loc-node loc) (path-lefts p))
                             (cdr (path-rights p))
                             (path-parent-path p)
                             (path-parent-node p)
                             (path-branch? p)
                             (path-children p)
                             (path-make-node p))
                  (loc-branch? loc)
                  (loc-children loc)
                  (loc-make-node loc)))))

  (define (zip-leftmost loc)
    (let ([p (loc-path loc)])
      (if (or (not p) (null? (path-lefts p)))
        loc
        (let ([lefts (reverse (path-lefts p))])
          (make-loc (car lefts)
                    (make-path '()
                               (append (cdr lefts)
                                       (cons (loc-node loc)
                                             (path-rights p)))
                               (path-parent-path p)
                               (path-parent-node p)
                               (path-branch? p)
                               (path-children p)
                               (path-make-node p))
                    (loc-branch? loc)
                    (loc-children loc)
                    (loc-make-node loc))))))

  (define (zip-rightmost loc)
    (let ([p (loc-path loc)])
      (if (or (not p) (null? (path-rights p)))
        loc
        (let ([rights (reverse (path-rights p))])
          (make-loc (car rights)
                    (make-path (append (cdr rights)
                                       (cons (loc-node loc)
                                             (path-lefts p)))
                               '()
                               (path-parent-path p)
                               (path-parent-node p)
                               (path-branch? p)
                               (path-children p)
                               (path-make-node p))
                    (loc-branch? loc)
                    (loc-children loc)
                    (loc-make-node loc))))))

  ;; =========================================================================
  ;; Editing
  ;; =========================================================================

  (define (zip-replace loc node)
    (make-loc node (loc-path loc)
              (loc-branch? loc) (loc-children loc) (loc-make-node loc)))

  (define (zip-edit loc f . args)
    (zip-replace loc (apply f (loc-node loc) args)))

  (define (zip-insert-left loc item)
    (let ([p (loc-path loc)])
      (unless p (error 'zip-insert-left "at root"))
      (make-loc (loc-node loc)
                (make-path (cons item (path-lefts p))
                           (path-rights p)
                           (path-parent-path p)
                           (path-parent-node p)
                           (path-branch? p)
                           (path-children p)
                           (path-make-node p))
                (loc-branch? loc)
                (loc-children loc)
                (loc-make-node loc))))

  (define (zip-insert-right loc item)
    (let ([p (loc-path loc)])
      (unless p (error 'zip-insert-right "at root"))
      (make-loc (loc-node loc)
                (make-path (path-lefts p)
                           (cons item (path-rights p))
                           (path-parent-path p)
                           (path-parent-node p)
                           (path-branch? p)
                           (path-children p)
                           (path-make-node p))
                (loc-branch? loc)
                (loc-children loc)
                (loc-make-node loc))))

  (define (zip-insert-child loc item)
    ;; Insert item as the leftmost child of the current node
    (if (not (zip-branch? loc))
      (error 'zip-insert-child "not a branch node")
      (zip-replace loc
        ((loc-make-node loc) (loc-node loc)
         (cons item ((loc-children loc) (loc-node loc)))))))

  (define (zip-append-child loc item)
    ;; Append item as the rightmost child of the current node
    (if (not (zip-branch? loc))
      (error 'zip-append-child "not a branch node")
      (zip-replace loc
        ((loc-make-node loc) (loc-node loc)
         (append ((loc-children loc) (loc-node loc)) (list item))))))

  (define (zip-remove loc)
    (let ([p (loc-path loc)])
      (unless p (error 'zip-remove "at root"))
      (cond
        ;; If there are left siblings, move to the rightmost left sibling
        [(pair? (path-lefts p))
         (let loop ([l (make-loc (car (path-lefts p))
                                 (make-path (cdr (path-lefts p))
                                            (path-rights p)
                                            (path-parent-path p)
                                            (path-parent-node p)
                                            (path-branch? p)
                                            (path-children p)
                                            (path-make-node p))
                                 (loc-branch? loc)
                                 (loc-children loc)
                                 (loc-make-node loc))])
           ;; Go to the deepest rightmost descendant (for zip-next consistency)
           l)]
        ;; No left siblings — rebuild parent without this node
        [else
         (let ([new-children (path-rights p)])
           (make-loc ((loc-make-node loc) (path-parent-node p) new-children)
                     (path-parent-path p)
                     (path-branch? p)
                     (path-children p)
                     (path-make-node p)))])))

  ;; =========================================================================
  ;; Depth-first traversal: next / prev
  ;; =========================================================================

  (define (zip-next loc)
    (if (zip-end? loc) loc
      (or
        ;; Try going down first
        (and (zip-branch? loc) (zip-down loc))
        ;; Try going right
        (zip-right loc)
        ;; Go up until we can go right
        (let loop ([p loc])
          (let ([up (zip-up p)])
            (if (not up)
              ;; Back at root with nowhere to go — we're done
              (make-loc (loc-node p) 'end
                        (loc-branch? p) (loc-children p) (loc-make-node p))
              (or (zip-right up)
                  (loop up))))))))

  (define (zip-prev loc)
    ;; Move to previous node in depth-first order
    (let ([l (zip-left loc)])
      (if l
        ;; Go to the rightmost-deepest descendant of left sibling
        (let loop ([n l])
          (if (and (zip-branch? n) (zip-down n))
            (let ([d (zip-down n)])
              (let go-right ([r d])
                (let ([next (zip-right r)])
                  (if next (go-right next) (loop r)))))
            n))
        ;; No left sibling — go up
        (zip-up loc))))

  ;; =========================================================================
  ;; Root reconstruction
  ;; =========================================================================

  (define (zip-root loc)
    (if (zip-end? loc)
      (loc-node loc)
      (let ([up (zip-up loc)])
        (if up (zip-root up) (loc-node loc)))))

  ;; =========================================================================
  ;; Built-in tree types
  ;; =========================================================================

  ;; List zipper: branches are lists, leaves are non-list atoms
  (define (list-zipper root)
    (zipper
      pair?                      ;; branch?
      (lambda (n) n)             ;; children (a list IS its children)
      (lambda (node children) children)  ;; make-node
      root))

  ;; Vector zipper: branches are vectors
  (define (vector-zipper root)
    (zipper
      vector?
      vector->list
      (lambda (node children) (list->vector children))
      root))

) ;; end library
