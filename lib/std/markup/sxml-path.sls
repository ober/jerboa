#!chezscheme
;;; :std/markup/sxml-path -- XPath-like queries on SXML trees
;;;
;;; Provides sxpath (composable path queries) and convenience selectors.
;;; Path elements: tag symbols, * (wildcard), // (descendants), @ (attributes).

(library (std markup sxml-path)
  (export
    sxpath
    sxml:select
    sxml:select-first
    node-typeof?
    node-join
    node-closure
    sxml:filter)

  (import (chezscheme)
          (std markup sxml))

  ;; A "nodeset" is a list of nodes.
  ;; A "converter" is a procedure: node -> nodeset.

  ;; node-typeof? returns a converter that selects child elements
  ;; matching a given tag symbol, or all element children for '*.
  (define (node-typeof? tag)
    (cond
      ((eq? tag '*)
       ;; Select all element children
       (lambda (node)
         (if (sxml:element? node)
           (filter sxml:element? (sxml:children node))
           '())))
      ((eq? tag '@)
       ;; Select attributes as (name value) pairs
       (lambda (node)
         (if (sxml:element? node)
           (sxml:attributes node)
           '())))
      (else
       ;; Select child elements with the given tag
       (lambda (node)
         (if (sxml:element? node)
           (filter (lambda (child)
                     (and (sxml:element? child)
                          (eq? (sxml:element-name child) tag)))
                   (sxml:children node))
           '())))))

  ;; node-join composes multiple converters in sequence.
  ;; Each converter is applied to every node in the current nodeset,
  ;; and results are concatenated.
  (define (node-join . converters)
    (lambda (node)
      (let loop ((convs converters) (nodeset (list node)))
        (if (null? convs)
          nodeset
          (loop (cdr convs)
                (apply append
                       (map (car convs) nodeset)))))))

  ;; node-closure: repeatedly apply converter to node and all descendants.
  ;; Returns all matching nodes at any depth (like XPath //).
  (define (node-closure converter)
    (lambda (node)
      (let collect ((n node))
        (let ((direct (converter n)))
          (if (sxml:element? n)
            (append direct
                    (apply append
                           (map collect (sxml:children n))))
            direct)))))

  ;; sxml:filter keeps only nodes satisfying a predicate.
  (define (sxml:filter pred nodes)
    (filter pred nodes))

  ;; Recursively find all descendant elements (including node itself).
  (define (all-descendants node)
    (if (sxml:element? node)
      (cons node
            (apply append
                   (map all-descendants (sxml:children node))))
      '()))

  ;; sxml:select -- find all elements with a given tag at any depth.
  (define (sxml:select tree tag)
    (filter (lambda (n)
              (and (sxml:element? n)
                   (eq? (sxml:element-name n) tag)))
            (all-descendants tree)))

  ;; sxml:select-first -- find the first element with a given tag.
  (define (sxml:select-first tree tag)
    (let search ((node tree))
      (cond
        ((and (sxml:element? node)
              (eq? (sxml:element-name node) tag))
         node)
        ((sxml:element? node)
         (let loop ((children (sxml:children node)))
           (cond
             ((null? children) #f)
             ((let ((result (search (car children))))
                (and result result)))
             (else (loop (cdr children))))))
        (else #f))))

  ;; sxpath: compile a path (list of step descriptors) into a converter.
  ;;
  ;; Supported path steps:
  ;;   symbol     -- select children with that tag name
  ;;   '*         -- select all element children (wildcard)
  ;;   '//        -- select all descendants (axis)
  ;;   '@         -- select attributes
  ;;   (symbol)   -- same as bare symbol (nested list notation)
  ;;
  ;; Example: (sxpath '(html body div)) selects div children of body
  ;; children of html children.
  ;;
  ;; Returns: procedure node -> nodeset
  (define (sxpath path)
    (let ((converters
           (map (lambda (step)
                  (cond
                    ;; // means "all descendants then apply next step"
                    ((eq? step '//)
                     (lambda (node)
                       (all-descendants node)))
                    ;; Symbol: select matching children
                    ((symbol? step)
                     (node-typeof? step))
                    ;; List containing a symbol: same as bare symbol
                    ((and (pair? step) (symbol? (car step)) (null? (cdr step)))
                     (node-typeof? (car step)))
                    (else
                     (error 'sxpath "unsupported path step" step))))
                path)))
      (lambda (node)
        (let loop ((convs converters) (nodeset (list node)))
          (if (null? convs)
            nodeset
            (loop (cdr convs)
                  (apply append
                         (map (car convs) nodeset))))))))

  ) ;; end library
