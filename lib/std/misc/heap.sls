#!chezscheme
;;; (std misc heap) -- Priority Queue / Binary Heap
;;;
;;; Min-heap by default. Use custom comparator for max-heap.
;;;
;;; Usage:
;;;   (import (std misc heap))
;;;   (define h (make-heap <))     ;; min-heap
;;;   (heap-insert! h 5)
;;;   (heap-insert! h 2)
;;;   (heap-insert! h 8)
;;;   (heap-peek h)               ; => 2
;;;   (heap-extract! h)           ; => 2
;;;   (heap-peek h)               ; => 5
;;;
;;;   ;; Max-heap
;;;   (define mh (make-heap >))
;;;
;;;   ;; Heapify
;;;   (define h2 (list->heap < '(5 3 1 4 2)))
;;;   (heap->sorted-list h2)      ; => (1 2 3 4 5)

(library (std misc heap)
  (export
    make-heap
    heap?
    heap-size
    heap-empty?
    heap-insert!
    heap-peek
    heap-extract!
    heap-clear!
    list->heap
    heap->list
    heap->sorted-list)

  (import (chezscheme))

  (define-record-type heap-rec
    (fields (immutable cmp)        ;; comparator: (lambda (a b) -> bool) = "a has higher priority"
            (mutable data)          ;; vector
            (mutable count)         ;; current element count
            (mutable capacity))     ;; vector length
    (protocol (lambda (new)
      (lambda (cmp)
        (new cmp (make-vector 16 #f) 0 16)))))

  (define (make-heap cmp) (make-heap-rec cmp))
  (define (heap? x) (heap-rec? x))
  (define (heap-size h) (heap-rec-count h))
  (define (heap-empty? h) (= (heap-rec-count h) 0))

  ;; ========== Insert ==========
  (define (heap-insert! h val)
    ;; Grow if needed
    (when (= (heap-rec-count h) (heap-rec-capacity h))
      (grow! h))
    (let ([i (heap-rec-count h)])
      (vector-set! (heap-rec-data h) i val)
      (heap-rec-count-set! h (+ i 1))
      (bubble-up! h i)))

  ;; ========== Peek ==========
  (define (heap-peek h)
    (when (heap-empty? h)
      (error 'heap-peek "heap is empty"))
    (vector-ref (heap-rec-data h) 0))

  ;; ========== Extract ==========
  (define (heap-extract! h)
    (when (heap-empty? h)
      (error 'heap-extract! "heap is empty"))
    (let* ([data (heap-rec-data h)]
           [top (vector-ref data 0)]
           [last-idx (- (heap-rec-count h) 1)])
      (vector-set! data 0 (vector-ref data last-idx))
      (vector-set! data last-idx #f)
      (heap-rec-count-set! h last-idx)
      (when (> last-idx 0)
        (bubble-down! h 0))
      top))

  ;; ========== Clear ==========
  (define (heap-clear! h)
    (heap-rec-data-set! h (make-vector 16 #f))
    (heap-rec-count-set! h 0)
    (heap-rec-capacity-set! h 16))

  ;; ========== Conversions ==========
  (define (list->heap cmp lst)
    (let ([h (make-heap cmp)])
      (for-each (lambda (x) (heap-insert! h x)) lst)
      h))

  (define (heap->list h)
    ;; Return elements in internal order (not sorted)
    (let ([data (heap-rec-data h)]
          [n (heap-rec-count h)])
      (let loop ([i 0] [acc '()])
        (if (= i n) (reverse acc)
          (loop (+ i 1) (cons (vector-ref data i) acc))))))

  (define (heap->sorted-list h)
    ;; Extract all in priority order (destructive!)
    (let loop ([acc '()])
      (if (heap-empty? h)
        (reverse acc)
        (loop (cons (heap-extract! h) acc)))))

  ;; ========== Internal ==========
  (define (heap-parent i) (quotient (- i 1) 2))
  (define (left i) (+ (* 2 i) 1))
  (define (right i) (+ (* 2 i) 2))

  (define (bubble-up! h i)
    (let ([data (heap-rec-data h)]
          [cmp (heap-rec-cmp h)])
      (let loop ([i i])
        (when (> i 0)
          (let ([p (heap-parent i)])
            (when (cmp (vector-ref data i) (vector-ref data p))
              (swap! data i p)
              (loop p)))))))

  (define (bubble-down! h i)
    (let ([data (heap-rec-data h)]
          [cmp (heap-rec-cmp h)]
          [n (heap-rec-count h)])
      (let loop ([i i])
        (let ([l (left i)]
              [r (right i)]
              [best i])
          (when (and (< l n) (cmp (vector-ref data l) (vector-ref data best)))
            (set! best l))
          (when (and (< r n) (cmp (vector-ref data r) (vector-ref data best)))
            (set! best r))
          (unless (= best i)
            (swap! data i best)
            (loop best))))))

  (define (swap! vec i j)
    (let ([tmp (vector-ref vec i)])
      (vector-set! vec i (vector-ref vec j))
      (vector-set! vec j tmp)))

  (define (grow! h)
    (let* ([old (heap-rec-data h)]
           [old-cap (heap-rec-capacity h)]
           [new-cap (* old-cap 2)]
           [new-vec (make-vector new-cap #f)])
      (let loop ([i 0])
        (when (< i old-cap)
          (vector-set! new-vec i (vector-ref old i))
          (loop (+ i 1))))
      (heap-rec-data-set! h new-vec)
      (heap-rec-capacity-set! h new-cap)))

) ;; end library
