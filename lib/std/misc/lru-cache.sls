#!chezscheme
;;; (std misc lru-cache) -- LRU Cache with O(1) Operations
;;;
;;; Standalone LRU cache using hash table + doubly-linked list.
;;; O(1) get, put, and eviction.
;;;
;;; Usage:
;;;   (import (std misc lru-cache))
;;;   (define cache (make-lru-cache 100))
;;;   (lru-cache-put! cache "key1" "value1")
;;;   (lru-cache-get cache "key1")        ; => "value1"
;;;   (lru-cache-get cache "missing" #f)  ; => #f
;;;
;;;   (lru-cache-stats cache)  ; => ((size . N) (capacity . M) (hits . H) (misses . M))

(library (std misc lru-cache)
  (export
    make-lru-cache
    lru-cache?
    lru-cache-get
    lru-cache-put!
    lru-cache-delete!
    lru-cache-contains?
    lru-cache-size
    lru-cache-capacity
    lru-cache-clear!
    lru-cache-keys
    lru-cache-values
    lru-cache-stats
    lru-cache-for-each)

  (import (chezscheme))

  ;; ========== Doubly-linked list node ==========
  (define-record-type node-rec
    (fields (immutable key)
            (mutable value)
            (mutable prev)
            (mutable next))
    (protocol (lambda (new)
      (lambda (key value)
        (new key value #f #f)))))

  ;; ========== LRU Cache ==========
  (define-record-type lru-cache-rec
    (fields (immutable capacity)
            (immutable table)       ;; hashtable: key -> node
            (mutable head)          ;; most recently used
            (mutable tail)          ;; least recently used
            (mutable size)
            (mutable hits)
            (mutable misses))
    (protocol (lambda (new)
      (lambda (cap)
        (new cap (make-hashtable equal-hash equal?) #f #f 0 0 0)))))

  (define (make-lru-cache cap)
    (unless (> cap 0) (error 'make-lru-cache "capacity must be positive" cap))
    (make-lru-cache-rec cap))

  (define (lru-cache? x) (lru-cache-rec? x))
  (define (lru-cache-size c) (lru-cache-rec-size c))
  (define (lru-cache-capacity c) (lru-cache-rec-capacity c))

  ;; ========== Get ==========
  (define lru-cache-get
    (case-lambda
      [(c key) (lru-cache-get c key (void))]
      [(c key default)
       (let ([node (hashtable-ref (lru-cache-rec-table c) key #f)])
         (if node
           (begin
             (lru-cache-rec-hits-set! c (+ (lru-cache-rec-hits c) 1))
             (move-to-head! c node)
             (node-rec-value node))
           (begin
             (lru-cache-rec-misses-set! c (+ (lru-cache-rec-misses c) 1))
             default)))]))

  ;; ========== Put ==========
  (define (lru-cache-put! c key value)
    (let ([existing (hashtable-ref (lru-cache-rec-table c) key #f)])
      (if existing
        ;; Update existing
        (begin
          (node-rec-value-set! existing value)
          (move-to-head! c existing))
        ;; Insert new
        (begin
          (when (= (lru-cache-rec-size c) (lru-cache-rec-capacity c))
            (evict-tail! c))
          (let ([node (make-node-rec key value)])
            (hashtable-set! (lru-cache-rec-table c) key node)
            (lru-cache-rec-size-set! c (+ (lru-cache-rec-size c) 1))
            (add-to-head! c node))))))

  ;; ========== Delete ==========
  (define (lru-cache-delete! c key)
    (let ([node (hashtable-ref (lru-cache-rec-table c) key #f)])
      (when node
        (remove-node! c node)
        (hashtable-delete! (lru-cache-rec-table c) key)
        (lru-cache-rec-size-set! c (- (lru-cache-rec-size c) 1)))))

  ;; ========== Contains ==========
  (define (lru-cache-contains? c key)
    (hashtable-contains? (lru-cache-rec-table c) key))

  ;; ========== Clear ==========
  (define (lru-cache-clear! c)
    (hashtable-clear! (lru-cache-rec-table c))
    (lru-cache-rec-head-set! c #f)
    (lru-cache-rec-tail-set! c #f)
    (lru-cache-rec-size-set! c 0))

  ;; ========== Keys/Values ==========
  (define (lru-cache-keys c)
    ;; MRU to LRU order
    (let loop ([node (lru-cache-rec-head c)] [acc '()])
      (if (not node) (reverse acc)
        (loop (node-rec-next node) (cons (node-rec-key node) acc)))))

  (define (lru-cache-values c)
    (let loop ([node (lru-cache-rec-head c)] [acc '()])
      (if (not node) (reverse acc)
        (loop (node-rec-next node) (cons (node-rec-value node) acc)))))

  ;; ========== Stats ==========
  (define (lru-cache-stats c)
    `((size . ,(lru-cache-rec-size c))
      (capacity . ,(lru-cache-rec-capacity c))
      (hits . ,(lru-cache-rec-hits c))
      (misses . ,(lru-cache-rec-misses c))
      (hit-rate . ,(let ([total (+ (lru-cache-rec-hits c) (lru-cache-rec-misses c))])
                     (if (= total 0) 0.0
                       (inexact (/ (lru-cache-rec-hits c) total)))))))

  ;; ========== Iteration ==========
  (define (lru-cache-for-each proc c)
    ;; Calls (proc key value) for each entry, MRU to LRU
    (let loop ([node (lru-cache-rec-head c)])
      (when node
        (proc (node-rec-key node) (node-rec-value node))
        (loop (node-rec-next node)))))

  ;; ========== Internal Linked List Operations ==========
  (define (add-to-head! c node)
    (node-rec-prev-set! node #f)
    (node-rec-next-set! node (lru-cache-rec-head c))
    (when (lru-cache-rec-head c)
      (node-rec-prev-set! (lru-cache-rec-head c) node))
    (lru-cache-rec-head-set! c node)
    (unless (lru-cache-rec-tail c)
      (lru-cache-rec-tail-set! c node)))

  (define (remove-node! c node)
    (let ([prev (node-rec-prev node)]
          [next (node-rec-next node)])
      (if prev
        (node-rec-next-set! prev next)
        (lru-cache-rec-head-set! c next))
      (if next
        (node-rec-prev-set! next prev)
        (lru-cache-rec-tail-set! c prev))))

  (define (move-to-head! c node)
    (unless (eq? node (lru-cache-rec-head c))
      (remove-node! c node)
      (add-to-head! c node)))

  (define (evict-tail! c)
    (let ([tail (lru-cache-rec-tail c)])
      (when tail
        (hashtable-delete! (lru-cache-rec-table c) (node-rec-key tail))
        (remove-node! c tail)
        (lru-cache-rec-size-set! c (- (lru-cache-rec-size c) 1)))))

) ;; end library
