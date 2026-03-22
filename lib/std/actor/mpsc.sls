#!chezscheme
;;; (std actor mpsc) — Multi-Producer Single-Consumer queue (mailbox)
;;;
;;; Two-lock linked list: one lock for the tail (producers), one for the head
;;; (consumer). Producers never block the consumer. Signal the consumer by
;;; briefly acquiring head-mutex AFTER releasing tail-mutex — no nested locking.

(library (std actor mpsc)
  (export
    make-mpsc-queue
    mpsc-queue?
    mpsc-enqueue!       ;; producer: add to tail
    mpsc-dequeue!       ;; consumer: remove from head (blocks if empty)
    mpsc-try-dequeue!   ;; consumer: remove or return (values #f #f) immediately
    mpsc-empty?         ;; approximate — safe only from consumer thread
    mpsc-length         ;; approximate count — safe from consumer thread
    mpsc-close!         ;; signal no more messages; wakes blocked consumers
    mpsc-closed?)
  (import (chezscheme))

  ;; -------- Linked-list node --------

  (define-record-type mpsc-node
    (fields
      (mutable value)   ;; message payload, or 'sentinel for dummy head
      (mutable next))   ;; next node or #f
    (protocol
      (lambda (new)
        (lambda (val) (new val #f))))
    (sealed #t))

  ;; -------- Queue record --------

  (define-record-type mpsc-queue
    (fields
      (mutable head)          ;; dummy node; consumer reads head.next
      (mutable tail)          ;; last real node (or dummy when empty)
      (immutable head-mutex)  ;; consumer lock + condition variable
      (immutable tail-mutex)  ;; producer lock
      (immutable not-empty)   ;; condition: signaled on enqueue
      (mutable closed?))
    (protocol
      (lambda (new)
        (lambda ()
          (let ([dummy (make-mpsc-node 'sentinel)])
            (new dummy dummy
                 (make-mutex) (make-mutex)
                 (make-condition)
                 #f)))))
    (sealed #t))

  ;; -------- Producer --------

  ;; Enqueue a value.  Acquires tail-mutex only.
  ;; Signals consumer AFTER releasing tail-mutex to avoid nested locking.
  (define (mpsc-enqueue! q val)
    (when (mpsc-queue-closed? q)
      (error 'mpsc-enqueue! "queue is closed"))
    (let ([node (make-mpsc-node val)])
      (with-mutex (mpsc-queue-tail-mutex q)
        (when (mpsc-queue-closed? q)
          (error 'mpsc-enqueue! "queue is closed"))
        (mpsc-node-next-set! (mpsc-queue-tail q) node)
        (mpsc-queue-tail-set! q node)))
    ;; Signal consumer outside tail-lock
    (with-mutex (mpsc-queue-head-mutex q)
      (condition-signal (mpsc-queue-not-empty q))))

  ;; -------- Consumer --------

  ;; Dequeue, blocking if the queue is empty.
  (define (mpsc-dequeue! q)
    (with-mutex (mpsc-queue-head-mutex q)
      (let loop ()
        (let ([next (mpsc-node-next (mpsc-queue-head q))])
          (cond
            [next
             (let ([val (mpsc-node-value next)])
               ;; Advance dummy head; old head is discarded
               (mpsc-queue-head-set! q next)
               (mpsc-node-value-set! next 'sentinel) ;; help GC
               val)]
            [(mpsc-queue-closed? q)
             (error 'mpsc-dequeue! "queue closed and empty")]
            [else
             (condition-wait (mpsc-queue-not-empty q)
                             (mpsc-queue-head-mutex q))
             (loop)])))))

  ;; Try dequeue without blocking.
  ;; Returns (values val #t) on success, (values #f #f) if empty.
  (define (mpsc-try-dequeue! q)
    (with-mutex (mpsc-queue-head-mutex q)
      (let ([next (mpsc-node-next (mpsc-queue-head q))])
        (if next
          (let ([val (mpsc-node-value next)])
            (mpsc-queue-head-set! q next)
            (mpsc-node-value-set! next 'sentinel)
            (values val #t))
          (values #f #f)))))

  ;; Approximate empty check — safe only from the consumer thread.
  (define (mpsc-empty? q)
    (not (mpsc-node-next (mpsc-queue-head q))))

  ;; -------- Lifecycle --------

  (define (mpsc-close! q)
    (with-mutex (mpsc-queue-tail-mutex q)
      (mpsc-queue-closed?-set! q #t))
    ;; Wake all blocked consumers
    (with-mutex (mpsc-queue-head-mutex q)
      (condition-broadcast (mpsc-queue-not-empty q))))

  ;; Approximate length — walks the linked list from head.
  ;; Safe to call from the consumer thread.
  (define (mpsc-length q)
    (let loop ([node (mpsc-node-next (mpsc-queue-head q))] [n 0])
      (if node
        (loop (mpsc-node-next node) (+ n 1))
        n)))

  ;; Public predicate — wraps the record field accessor
  (define (mpsc-closed? q) (mpsc-queue-closed? q))

  ) ;; end library
