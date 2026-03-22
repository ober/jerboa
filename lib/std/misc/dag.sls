#!chezscheme
;;; (std misc dag) -- Directed Acyclic Graph operations
;;;
;;; Mutable DAG backed by hashtables.  Nodes are any value usable as
;;; a hashtable key (symbols, numbers, strings).
;;;
;;; Usage:
;;;   (import (std misc dag))
;;;   (define g (make-dag))
;;;   (dag-add-node! g 'a)
;;;   (dag-add-node! g 'b)
;;;   (dag-add-node! g 'c)
;;;   (dag-add-edge! g 'a 'b)
;;;   (dag-add-edge! g 'b 'c)
;;;   (topological-sort g)            ;; => (a b c)
;;;   (dag-reachable g 'a)            ;; => (b c)
;;;   (dag-sources g)                 ;; => (a)
;;;   (dag-sinks g)                   ;; => (c)

(library (std misc dag)
  (export
    make-dag
    dag?
    dag-add-node!
    dag-add-edge!
    dag-nodes
    dag-edges
    dag-neighbors
    dag-predecessors
    topological-sort
    dag-reachable
    dag-sources
    dag-sinks
    dag-has-cycle?)

  (import (chezscheme))

  ;; Internal: adjacency list (forward) and reverse adjacency list (backward)
  (define-record-type dag-rec
    (fields (immutable fwd)     ;; hashtable: node -> list of successors
            (immutable bwd))    ;; hashtable: node -> list of predecessors
    (sealed #t))

  (define (make-dag)
    (make-dag-rec (make-hashtable equal-hash equal?) (make-hashtable equal-hash equal?)))

  (define (dag? x) (dag-rec? x))

  ;; ========== Mutation ==========

  (define (dag-add-node! g node)
    (let ([fwd (dag-rec-fwd g)]
          [bwd (dag-rec-bwd g)])
      (unless (hashtable-contains? fwd node)
        (hashtable-set! fwd node '()))
      (unless (hashtable-contains? bwd node)
        (hashtable-set! bwd node '()))))

  (define (dag-add-edge! g from to)
    ;; Ensure both nodes exist
    (dag-add-node! g from)
    (dag-add-node! g to)
    (let ([fwd (dag-rec-fwd g)]
          [bwd (dag-rec-bwd g)])
      ;; Add forward edge (avoid duplicates)
      (let ([succs (hashtable-ref fwd from '())])
        (unless (member to succs)
          (hashtable-set! fwd from (cons to succs))))
      ;; Add backward edge
      (let ([preds (hashtable-ref bwd to '())])
        (unless (member from preds)
          (hashtable-set! bwd to (cons from preds))))))

  ;; ========== Queries ==========

  (define (dag-nodes g)
    (vector->list (hashtable-keys (dag-rec-fwd g))))

  (define (dag-edges g)
    ;; Returns list of (from . to) pairs
    (let ([fwd (dag-rec-fwd g)]
          [result '()])
      (let-values ([(keys vals) (hashtable-entries fwd)])
        (let ([n (vector-length keys)])
          (let loop ([i 0] [acc '()])
            (if (>= i n)
              acc
              (let ([from (vector-ref keys i)]
                    [tos (vector-ref vals i)])
                (loop (+ i 1)
                      (append (map (lambda (to) (cons from to)) tos) acc)))))))))

  (define (dag-neighbors g node)
    ;; Successors of node
    (hashtable-ref (dag-rec-fwd g) node '()))

  (define (dag-predecessors g node)
    ;; Predecessors of node
    (hashtable-ref (dag-rec-bwd g) node '()))

  ;; ========== Topological sort (Kahn's algorithm) ==========

  (define (topological-sort g)
    ;; Returns a list of nodes in topological order,
    ;; or raises an error if cycle exists.
    (let* ([fwd (dag-rec-fwd g)]
           ;; Build mutable in-degree table
           [in-deg (make-hashtable equal-hash equal?)]
           [nodes (dag-nodes g)])
      ;; Initialize in-degrees
      (for-each
        (lambda (n) (hashtable-set! in-deg n 0))
        nodes)
      ;; Count in-degrees from forward edges
      (for-each
        (lambda (n)
          (for-each
            (lambda (succ)
              (hashtable-set! in-deg succ
                (+ 1 (hashtable-ref in-deg succ 0))))
            (hashtable-ref fwd n '())))
        nodes)
      ;; Collect initial sources (in-degree = 0)
      (let ([queue (filter (lambda (n) (zero? (hashtable-ref in-deg n 0))) nodes)])
        (let loop ([queue queue] [result '()])
          (if (null? queue)
            (if (= (length result) (length nodes))
              (reverse result)
              (error 'topological-sort "cycle detected in graph"))
            (let ([node (car queue)]
                  [rest (cdr queue)])
              (let ([new-queue
                     (fold-left
                       (lambda (q succ)
                         (let ([new-deg (- (hashtable-ref in-deg succ 0) 1)])
                           (hashtable-set! in-deg succ new-deg)
                           (if (zero? new-deg)
                             (append q (list succ))
                             q)))
                       rest
                       (hashtable-ref fwd node '()))])
                (loop new-queue (cons node result)))))))))

  ;; ========== Reachability (BFS) ==========

  (define (dag-reachable g start)
    ;; Returns list of all nodes reachable from start (not including start itself).
    (let ([fwd (dag-rec-fwd g)]
          [visited (make-hashtable equal-hash equal?)])
      (hashtable-set! visited start #t)
      (let loop ([queue (hashtable-ref fwd start '())] [result '()])
        (if (null? queue)
          (reverse result)
          (let ([node (car queue)]
                [rest (cdr queue)])
            (if (hashtable-ref visited node #f)
              (loop rest result)
              (begin
                (hashtable-set! visited node #t)
                (loop (append rest (hashtable-ref fwd node '()))
                      (cons node result)))))))))

  ;; ========== Sources and Sinks ==========

  (define (dag-sources g)
    ;; Nodes with no incoming edges
    (let ([bwd (dag-rec-bwd g)])
      (filter (lambda (n)
                (null? (hashtable-ref bwd n '())))
              (dag-nodes g))))

  (define (dag-sinks g)
    ;; Nodes with no outgoing edges
    (let ([fwd (dag-rec-fwd g)])
      (filter (lambda (n)
                (null? (hashtable-ref fwd n '())))
              (dag-nodes g))))

  ;; ========== Cycle detection ==========

  (define (dag-has-cycle? g)
    ;; Uses DFS with coloring: white=unvisited, gray=in-progress, black=done
    (let ([fwd (dag-rec-fwd g)]
          [color (make-hashtable equal-hash equal?)]
          [nodes (dag-nodes g)])
      ;; Initialize all white
      (for-each (lambda (n) (hashtable-set! color n 'white)) nodes)
      (call/cc
        (lambda (return)
          (define (visit node)
            (hashtable-set! color node 'gray)
            (for-each
              (lambda (succ)
                (case (hashtable-ref color succ 'white)
                  [(gray) (return #t)]
                  [(white) (visit succ)]
                  [else (void)]))  ;; black, skip
              (hashtable-ref fwd node '()))
            (hashtable-set! color node 'black))
          (for-each
            (lambda (n)
              (when (eq? (hashtable-ref color n 'white) 'white)
                (visit n)))
            nodes)
          #f))))

) ;; end library
