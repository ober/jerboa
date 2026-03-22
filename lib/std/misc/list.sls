#!chezscheme
;;; :std/misc/list -- List utilities

(library (std misc list)
  (export flatten unique snoc
          take drop
          every any
          filter-map
          group-by
          zip)
  (import (chezscheme))

  (define (flatten lst)
    (cond
      [(null? lst) '()]
      [(pair? (car lst))
       (append (flatten (car lst)) (flatten (cdr lst)))]
      [else (cons (car lst) (flatten (cdr lst)))]))

  (define unique
    (case-lambda
      ((lst) (unique lst equal?))
      ((lst same?)
       (let loop ([rest lst] [acc '()])
         (if (null? rest) (reverse acc)
           (if (exists (lambda (x) (same? x (car rest))) acc)
             (loop (cdr rest) acc)
             (loop (cdr rest) (cons (car rest) acc))))))))

  (define (snoc lst item)
    (append lst (list item)))

  (define take
    (case-lambda
      ((lst n) (take lst n '()))
      ((lst n acc)
       (if (or (<= n 0) (null? lst))
         (reverse acc)
         (take (cdr lst) (- n 1) (cons (car lst) acc))))))

  (define (drop lst n)
    (if (or (<= n 0) (null? lst)) lst
      (drop (cdr lst) (- n 1))))

  (define (every pred lst)
    (or (null? lst)
        (and (pred (car lst))
             (every pred (cdr lst)))))

  (define (any pred lst)
    (and (pair? lst)
         (or (pred (car lst))
             (any pred (cdr lst)))))

  (define (filter-map proc lst)
    (let loop ([rest lst] [acc '()])
      (if (null? rest) (reverse acc)
        (let ([v (proc (car rest))])
          (loop (cdr rest) (if v (cons v acc) acc))))))

  (define (group-by key lst)
    (let ([ht (make-hashtable equal-hash equal?)])
      (for-each
        (lambda (item)
          (let ([k (key item)])
            (hashtable-update! ht k
              (lambda (old) (cons item old))
              '())))
        lst)
      (let-values ([(keys vals) (hashtable-entries ht)])
        (let loop ([i 0] [acc '()])
          (if (= i (vector-length keys)) acc
            (loop (+ i 1)
                  (cons (cons (vector-ref keys i)
                              (reverse (vector-ref vals i)))
                        acc)))))))

  (define (zip . lists)
    (apply map list lists))

  ) ;; end library
