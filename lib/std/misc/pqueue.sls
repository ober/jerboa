#!chezscheme
;;; (std misc pqueue) — Binary heap priority queue
;;;
;;; Min-heap by default. Supply a custom comparator for max-heap or other orderings.
;;;
;;; (define pq (make-pqueue <))
;;; (pqueue-push! pq 5) (pqueue-push! pq 1) (pqueue-push! pq 3)
;;; (pqueue-pop! pq) => 1
;;; (pqueue-peek pq) => 3

(library (std misc pqueue)
  (export make-pqueue pqueue? pqueue-empty? pqueue-length
          pqueue-push! pqueue-pop! pqueue-peek
          pqueue->list pqueue-for-each pqueue-clear!)

  (import (chezscheme))

  ;; Mutable vector-backed binary heap
  (define-record-type pqueue
    (fields (mutable data)     ;; vector
            (mutable size)     ;; current element count
            cmp)               ;; comparator: (< a b) means a has higher priority
    (protocol
     (lambda (new)
       (case-lambda
         [() (new (make-vector 16) 0 <)]
         [(cmp) (new (make-vector 16) 0 cmp)]))))

  (define (pqueue-empty? pq)
    (= (pqueue-size pq) 0))

  (define (pqueue-length pq)
    (pqueue-size pq))

  (define (ensure-capacity! pq)
    (let ([data (pqueue-data pq)]
          [sz (pqueue-size pq)])
      (when (= sz (vector-length data))
        (let ([new-data (make-vector (* 2 sz))])
          (do ([i 0 (+ i 1)])
              ((= i sz))
            (vector-set! new-data i (vector-ref data i)))
          (pqueue-data-set! pq new-data)))))

  (define (swap! vec i j)
    (let ([tmp (vector-ref vec i)])
      (vector-set! vec i (vector-ref vec j))
      (vector-set! vec j tmp)))

  (define (sift-up! pq idx)
    (let ([data (pqueue-data pq)]
          [cmp (pqueue-cmp pq)])
      (let loop ([i idx])
        (when (> i 0)
          (let ([parent (quotient (- i 1) 2)])
            (when (cmp (vector-ref data i) (vector-ref data parent))
              (swap! data i parent)
              (loop parent)))))))

  (define (sift-down! pq idx)
    (let ([data (pqueue-data pq)]
          [sz (pqueue-size pq)]
          [cmp (pqueue-cmp pq)])
      (let loop ([i idx])
        (let ([left (+ (* 2 i) 1)]
              [right (+ (* 2 i) 2)]
              [smallest i])
          (when (and (< left sz)
                     (cmp (vector-ref data left) (vector-ref data smallest)))
            (set! smallest left))
          (when (and (< right sz)
                     (cmp (vector-ref data right) (vector-ref data smallest)))
            (set! smallest right))
          (unless (= smallest i)
            (swap! data i smallest)
            (loop smallest))))))

  (define (pqueue-push! pq val)
    (ensure-capacity! pq)
    (let ([idx (pqueue-size pq)])
      (vector-set! (pqueue-data pq) idx val)
      (pqueue-size-set! pq (+ idx 1))
      (sift-up! pq idx)))

  (define (pqueue-peek pq)
    (when (pqueue-empty? pq)
      (error 'pqueue-peek "empty priority queue"))
    (vector-ref (pqueue-data pq) 0))

  (define (pqueue-pop! pq)
    (when (pqueue-empty? pq)
      (error 'pqueue-pop! "empty priority queue"))
    (let* ([data (pqueue-data pq)]
           [val (vector-ref data 0)]
           [new-sz (- (pqueue-size pq) 1)])
      (vector-set! data 0 (vector-ref data new-sz))
      (vector-set! data new-sz #f)  ;; help GC
      (pqueue-size-set! pq new-sz)
      (unless (= new-sz 0)
        (sift-down! pq 0))
      val))

  (define (pqueue->list pq)
    (let ([copy (make-pqueue (pqueue-cmp pq))])
      ;; Copy elements
      (do ([i 0 (+ i 1)])
          ((= i (pqueue-size pq)))
        (pqueue-push! copy (vector-ref (pqueue-data pq) i)))
      ;; Drain in order
      (let loop ([acc '()])
        (if (pqueue-empty? copy)
            (reverse acc)
            (loop (cons (pqueue-pop! copy) acc))))))

  (define (pqueue-for-each proc pq)
    (for-each proc (pqueue->list pq)))

  (define (pqueue-clear! pq)
    (pqueue-data-set! pq (make-vector 16))
    (pqueue-size-set! pq 0))

) ;; end library
