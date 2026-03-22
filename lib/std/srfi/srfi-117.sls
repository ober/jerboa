#!chezscheme
;;; :std/srfi/117 -- Mutable Queues (SRFI-117)
;;; List-based mutable queues with O(1) add-front, add-back, remove-front.
;;; Uses front/back pointer pair over a mutable list.

(library (std srfi srfi-117)
  (export
    make-list-queue list-queue list-queue? list-queue-empty?
    list-queue-front list-queue-back
    list-queue-add-front! list-queue-add-back!
    list-queue-remove-front! list-queue-remove-back!
    list-queue-list list-queue-length
    list-queue-append! list-queue-for-each list-queue-map)

  (import (chezscheme))

  ;; Queue: mutable front and back pointers into a singly-linked list
  (define-record-type lq
    (fields (mutable front)
            (mutable back))
    (sealed #t))

  (define (list-queue? x) (lq? x))

  (define (make-list-queue lst)
    (if (null? lst)
        (make-lq '() '())
        (let loop ([p lst])
          (if (null? (cdr p))
              (make-lq lst p)
              (loop (cdr p))))))

  (define (list-queue . elems)
    (make-list-queue (list-copy elems)))

  (define (list-queue-empty? q)
    (null? (lq-front q)))

  (define (list-queue-front q)
    (when (list-queue-empty? q)
      (error 'list-queue-front "empty queue"))
    (car (lq-front q)))

  (define (list-queue-back q)
    (when (list-queue-empty? q)
      (error 'list-queue-back "empty queue"))
    (car (lq-back q)))

  (define (list-queue-add-front! q elem)
    (let ([new (cons elem (lq-front q))])
      (lq-front-set! q new)
      (when (null? (lq-back q))
        (lq-back-set! q new))))

  (define (list-queue-add-back! q elem)
    (let ([new (cons elem '())])
      (if (null? (lq-front q))
          (begin
            (lq-front-set! q new)
            (lq-back-set! q new))
          (begin
            (set-cdr! (lq-back q) new)
            (lq-back-set! q new)))))

  (define (list-queue-remove-front! q)
    (when (list-queue-empty? q)
      (error 'list-queue-remove-front! "empty queue"))
    (let ([val (car (lq-front q))])
      (lq-front-set! q (cdr (lq-front q)))
      (when (null? (lq-front q))
        (lq-back-set! q '()))
      val))

  (define (list-queue-remove-back! q)
    (when (list-queue-empty? q)
      (error 'list-queue-remove-back! "empty queue"))
    (let ([val (car (lq-back q))])
      (if (eq? (lq-front q) (lq-back q))
          ;; single element
          (begin
            (lq-front-set! q '())
            (lq-back-set! q '()))
          ;; walk to find second-to-last
          (let loop ([p (lq-front q)])
            (if (eq? (cdr p) (lq-back q))
                (begin
                  (set-cdr! p '())
                  (lq-back-set! q p))
                (loop (cdr p)))))
      val))

  (define (list-queue-list q)
    (lq-front q))

  (define (list-queue-length q)
    (length (lq-front q)))

  (define (list-queue-append! q . queues)
    (for-each
      (lambda (other)
        (for-each (lambda (x) (list-queue-add-back! q x))
                  (lq-front other)))
      queues))

  (define (list-queue-for-each f q)
    (for-each f (lq-front q)))

  (define (list-queue-map f q)
    (make-list-queue (map f (lq-front q))))
)
