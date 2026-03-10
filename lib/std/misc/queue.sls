#!chezscheme
;;; :std/misc/queue -- Mutable FIFO queue

(library (std misc queue)
  (export
    make-queue
    queue?
    queue-empty?
    queue-length
    enqueue!
    dequeue!
    queue-peek
    queue->list)

  (import (chezscheme))

  (define-record-type queue
    (fields (mutable head) (mutable tail) (mutable size))
    (protocol
      (lambda (new)
        (lambda () (new '() '() 0)))))

  (define (queue-empty? q)
    (= (queue-size q) 0))

  (define (queue-length q)
    (queue-size q))

  (define (enqueue! q val)
    (let ((cell (list val)))
      (if (null? (queue-tail q))
        (begin
          (queue-head-set! q cell)
          (queue-tail-set! q cell))
        (begin
          (set-cdr! (queue-tail q) cell)
          (queue-tail-set! q cell)))
      (queue-size-set! q (+ (queue-size q) 1))))

  (define (dequeue! q)
    (when (queue-empty? q)
      (error 'dequeue! "queue is empty"))
    (let ((val (car (queue-head q))))
      (queue-head-set! q (cdr (queue-head q)))
      (when (null? (queue-head q))
        (queue-tail-set! q '()))
      (queue-size-set! q (- (queue-size q) 1))
      val))

  (define (queue-peek q)
    (when (queue-empty? q)
      (error 'queue-peek "queue is empty"))
    (car (queue-head q)))

  (define (queue->list q)
    (list-copy (queue-head q)))

  ) ;; end library
