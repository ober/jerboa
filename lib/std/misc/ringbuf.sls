#!chezscheme
;;; (std misc ringbuf) -- Ring Buffer / Circular Buffer
;;;
;;; Fixed-size circular buffer with O(1) push/pop operations.
;;; When full, new elements overwrite the oldest.
;;;
;;; Usage:
;;;   (import (std misc ringbuf))
;;;   (define rb (make-ringbuf 5))
;;;   (ringbuf-push! rb 1)
;;;   (ringbuf-push! rb 2)
;;;   (ringbuf-push! rb 3)
;;;   (ringbuf->list rb)          ; => (1 2 3)
;;;   (ringbuf-peek rb)           ; => 1 (oldest)
;;;   (ringbuf-pop! rb)           ; => 1
;;;   ;; When full, overwrites oldest
;;;   (ringbuf-full? rb)

(library (std misc ringbuf)
  (export
    make-ringbuf
    ringbuf?
    ringbuf-capacity
    ringbuf-size
    ringbuf-empty?
    ringbuf-full?
    ringbuf-push!
    ringbuf-pop!
    ringbuf-peek
    ringbuf-peek-newest
    ringbuf-clear!
    ringbuf->list
    ringbuf-for-each
    ringbuf-ref)

  (import (chezscheme))

  (define-record-type ringbuf-rec
    (fields (immutable capacity)
            (immutable buf)        ;; vector
            (mutable head)          ;; read position
            (mutable tail)          ;; write position
            (mutable count))        ;; current count
    (protocol (lambda (new)
      (lambda (cap)
        (new cap (make-vector cap #f) 0 0 0)))))

  (define (make-ringbuf cap)
    (unless (> cap 0) (error 'make-ringbuf "capacity must be positive" cap))
    (make-ringbuf-rec cap))

  (define (ringbuf? x) (ringbuf-rec? x))
  (define (ringbuf-capacity rb) (ringbuf-rec-capacity rb))
  (define (ringbuf-size rb) (ringbuf-rec-count rb))
  (define (ringbuf-empty? rb) (= (ringbuf-rec-count rb) 0))
  (define (ringbuf-full? rb) (= (ringbuf-rec-count rb) (ringbuf-rec-capacity rb)))

  (define (ringbuf-push! rb val)
    ;; Push value. If full, overwrites oldest (advances head).
    (let ([buf (ringbuf-rec-buf rb)]
          [tail (ringbuf-rec-tail rb)]
          [cap (ringbuf-rec-capacity rb)])
      (vector-set! buf tail val)
      (ringbuf-rec-tail-set! rb (modulo (+ tail 1) cap))
      (if (ringbuf-full? rb)
        ;; Overwrite: advance head
        (ringbuf-rec-head-set! rb (modulo (+ (ringbuf-rec-head rb) 1) cap))
        ;; Not full: increment count
        (ringbuf-rec-count-set! rb (+ (ringbuf-rec-count rb) 1)))))

  (define (ringbuf-pop! rb)
    ;; Pop oldest value
    (when (ringbuf-empty? rb)
      (error 'ringbuf-pop! "ring buffer is empty"))
    (let* ([buf (ringbuf-rec-buf rb)]
           [head (ringbuf-rec-head rb)]
           [val (vector-ref buf head)])
      (vector-set! buf head #f)  ;; help GC
      (ringbuf-rec-head-set! rb (modulo (+ head 1) (ringbuf-rec-capacity rb)))
      (ringbuf-rec-count-set! rb (- (ringbuf-rec-count rb) 1))
      val))

  (define (ringbuf-peek rb)
    ;; Look at oldest without removing
    (when (ringbuf-empty? rb)
      (error 'ringbuf-peek "ring buffer is empty"))
    (vector-ref (ringbuf-rec-buf rb) (ringbuf-rec-head rb)))

  (define (ringbuf-peek-newest rb)
    ;; Look at newest element
    (when (ringbuf-empty? rb)
      (error 'ringbuf-peek-newest "ring buffer is empty"))
    (let ([idx (modulo (- (ringbuf-rec-tail rb) 1) (ringbuf-rec-capacity rb))])
      (vector-ref (ringbuf-rec-buf rb) idx)))

  (define (ringbuf-ref rb i)
    ;; Access i-th element (0 = oldest)
    (when (or (< i 0) (>= i (ringbuf-rec-count rb)))
      (error 'ringbuf-ref "index out of range" i))
    (let ([idx (modulo (+ (ringbuf-rec-head rb) i) (ringbuf-rec-capacity rb))])
      (vector-ref (ringbuf-rec-buf rb) idx)))

  (define (ringbuf-clear! rb)
    (let ([buf (ringbuf-rec-buf rb)]
          [cap (ringbuf-rec-capacity rb)])
      (let loop ([i 0])
        (when (< i cap)
          (vector-set! buf i #f)
          (loop (+ i 1))))
      (ringbuf-rec-head-set! rb 0)
      (ringbuf-rec-tail-set! rb 0)
      (ringbuf-rec-count-set! rb 0)))

  (define (ringbuf->list rb)
    ;; Return elements in order (oldest to newest)
    (let loop ([i 0] [acc '()])
      (if (= i (ringbuf-rec-count rb))
        (reverse acc)
        (loop (+ i 1) (cons (ringbuf-ref rb i) acc)))))

  (define (ringbuf-for-each proc rb)
    (let ([count (ringbuf-rec-count rb)]
          [head (ringbuf-rec-head rb)]
          [cap (ringbuf-rec-capacity rb)]
          [buf (ringbuf-rec-buf rb)])
      (let loop ([i 0])
        (when (< i count)
          (proc (vector-ref buf (modulo (+ head i) cap)))
          (loop (+ i 1))))))

) ;; end library
