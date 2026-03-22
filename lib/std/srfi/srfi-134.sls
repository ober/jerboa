#!chezscheme
;;; :std/srfi/134 -- Immutable Deques (SRFI-134)
;;; Banker's deque: two lists (front, rear) with balance invariant.
;;; All operations O(1) amortized.

(library (std srfi srfi-134)
  (export
    ideque ideque? ideque-empty? ideque-length
    ideque-front ideque-back
    ideque-add-front ideque-add-back
    ideque-remove-front ideque-remove-back
    ideque->list list->ideque
    ideque-map ideque-filter ideque-fold ideque-fold-right
    ideque-append ideque-for-each ideque-any ideque-every)

  (import (chezscheme))

  ;; Deque record: front list, front length, rear list (reversed), rear length
  (define-record-type ideque-rec
    (fields (immutable front)
            (immutable flen)
            (immutable rear)
            (immutable rlen))
    (sealed #t))

  (define (ideque? x) (ideque-rec? x))

  ;; Balance constant: neither side more than c*other + 1
  ;; Using c=3 for amortized O(1)
  (define balance-c 3)

  ;; Rebalance if needed
  (define (make-deque f flen r rlen)
    (cond
      [(> flen (+ (* balance-c rlen) 1))
       ;; Front too long: move half to rear
       (let* ([n (quotient (+ flen rlen) 2)]
              [new-f (take-list f n)]
              [new-r (append r (reverse (drop-list f n)))])
         (make-ideque-rec new-f n new-r (- (+ flen rlen) n)))]
      [(> rlen (+ (* balance-c flen) 1))
       ;; Rear too long: move half to front
       (let* ([n (quotient (+ flen rlen) 2)]
              [new-r (take-list r (- (+ flen rlen) n))]
              [new-f (append f (reverse (drop-list r (- (+ flen rlen) n))))])
         (make-ideque-rec new-f n new-r (- (+ flen rlen) n)))]
      [else
       (make-ideque-rec f flen r rlen)]))

  (define (take-list lst n)
    (let loop ([lst lst] [n n] [acc '()])
      (if (or (<= n 0) (null? lst))
        (reverse acc)
        (loop (cdr lst) (- n 1) (cons (car lst) acc)))))

  (define (drop-list lst n)
    (let loop ([lst lst] [n n])
      (if (or (<= n 0) (null? lst))
        lst
        (loop (cdr lst) (- n 1)))))

  ;; Empty deque
  (define empty-ideque (make-ideque-rec '() 0 '() 0))

  ;; Constructor: (ideque element ...)
  (define (ideque . elements)
    (list->ideque elements))

  (define (ideque-empty? dq)
    (and (= (ideque-rec-flen dq) 0)
         (= (ideque-rec-rlen dq) 0)))

  (define (ideque-length dq)
    (+ (ideque-rec-flen dq) (ideque-rec-rlen dq)))

  (define (ideque-front dq)
    (cond
      [(not (null? (ideque-rec-front dq)))
       (car (ideque-rec-front dq))]
      [(not (null? (ideque-rec-rear dq)))
       ;; Single element in rear
       (car (ideque-rec-rear dq))]
      [else (error 'ideque-front "empty deque")]))

  (define (ideque-back dq)
    (cond
      [(not (null? (ideque-rec-rear dq)))
       (car (ideque-rec-rear dq))]
      [(not (null? (ideque-rec-front dq)))
       ;; Single element in front
       (car (ideque-rec-front dq))]
      [else (error 'ideque-back "empty deque")]))

  (define (ideque-add-front dq elem)
    (make-deque (cons elem (ideque-rec-front dq))
                (+ (ideque-rec-flen dq) 1)
                (ideque-rec-rear dq)
                (ideque-rec-rlen dq)))

  (define (ideque-add-back dq elem)
    (make-deque (ideque-rec-front dq)
                (ideque-rec-flen dq)
                (cons elem (ideque-rec-rear dq))
                (+ (ideque-rec-rlen dq) 1)))

  (define (ideque-remove-front dq)
    (cond
      [(not (null? (ideque-rec-front dq)))
       (make-deque (cdr (ideque-rec-front dq))
                   (- (ideque-rec-flen dq) 1)
                   (ideque-rec-rear dq)
                   (ideque-rec-rlen dq))]
      [(not (null? (ideque-rec-rear dq)))
       ;; Front empty, rear has element(s) -- remove the only one
       ;; (after rebalance, front would be populated, but if rlen=1,
       ;; removing the single element gives empty)
       empty-ideque]
      [else (error 'ideque-remove-front "empty deque")]))

  (define (ideque-remove-back dq)
    (cond
      [(not (null? (ideque-rec-rear dq)))
       (make-deque (ideque-rec-front dq)
                   (ideque-rec-flen dq)
                   (cdr (ideque-rec-rear dq))
                   (- (ideque-rec-rlen dq) 1))]
      [(not (null? (ideque-rec-front dq)))
       empty-ideque]
      [else (error 'ideque-remove-back "empty deque")]))

  (define (ideque->list dq)
    (append (ideque-rec-front dq)
            (reverse (ideque-rec-rear dq))))

  (define (list->ideque lst)
    (let* ([n (length lst)]
           [half (quotient n 2)]
           [front (take-list lst half)]
           [rear (reverse (drop-list lst half))])
      (make-ideque-rec front half rear (- n half))))

  (define (ideque-map proc dq)
    (list->ideque (map proc (ideque->list dq))))

  (define (ideque-filter pred dq)
    (list->ideque (filter pred (ideque->list dq))))

  (define (ideque-fold proc seed dq)
    (fold-left proc seed (ideque->list dq)))

  (define (ideque-fold-right proc seed dq)
    (fold-right proc seed (ideque->list dq)))

  (define (ideque-append dq1 dq2)
    (list->ideque (append (ideque->list dq1) (ideque->list dq2))))

  (define (ideque-for-each proc dq)
    (for-each proc (ideque->list dq)))

  (define (ideque-any pred dq)
    (exists pred (ideque->list dq)))

  (define (ideque-every pred dq)
    (for-all pred (ideque->list dq)))

) ;; end library
