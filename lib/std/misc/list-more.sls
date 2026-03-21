#!chezscheme
;;; (std misc list-more) — Extended list operations
;;;
;;; List operations from Gerbil that aren't in jerboa core or SRFI-1.

(library (std misc list-more)
  (export flatten group-by zip-with interleave
          chunk unique frequencies
          list-index list-split-at
          snoc butlast)

  (import (chezscheme))

  ;; Deep flatten nested lists
  (define (flatten lst)
    (cond
      [(null? lst) '()]
      [(pair? (car lst))
       (append (flatten (car lst)) (flatten (cdr lst)))]
      [else
       (cons (car lst) (flatten (cdr lst)))]))

  ;; Group elements by key function
  ;; (group-by car '((a 1) (b 2) (a 3))) => ((a (a 1) (a 3)) (b (b 2)))
  (define (group-by key-fn lst)
    (let ([ht (make-hashtable equal-hash equal?)])
      (for-each (lambda (x)
                  (let ([k (key-fn x)])
                    (hashtable-update! ht k
                      (lambda (old) (append old (list x)))
                      '())))
                lst)
      (let-values ([(keys vals) (hashtable-entries ht)])
        (let loop ([i 0] [acc '()])
          (if (= i (vector-length keys))
              (reverse acc)
              (loop (+ i 1)
                    (cons (cons (vector-ref keys i) (vector-ref vals i))
                          acc)))))))

  ;; Zip two lists with combining function
  (define (zip-with f lst1 lst2)
    (let loop ([l1 lst1] [l2 lst2] [acc '()])
      (if (or (null? l1) (null? l2))
          (reverse acc)
          (loop (cdr l1) (cdr l2)
                (cons (f (car l1) (car l2)) acc)))))

  ;; Interleave two lists
  (define (interleave lst1 lst2)
    (let loop ([l1 lst1] [l2 lst2] [acc '()])
      (cond
        [(and (null? l1) (null? l2)) (reverse acc)]
        [(null? l1) (append (reverse acc) l2)]
        [(null? l2) (append (reverse acc) l1)]
        [else (loop (cdr l1) (cdr l2)
                    (cons (car l2) (cons (car l1) acc)))])))

  ;; Split list into sublists of size N
  (define (chunk lst n)
    (when (<= n 0) (error 'chunk "chunk size must be positive" n))
    (let loop ([rest lst] [acc '()])
      (if (null? rest)
          (reverse acc)
          (let take ([r rest] [i 0] [chunk-acc '()])
            (if (or (= i n) (null? r))
                (loop r (cons (reverse chunk-acc) acc))
                (take (cdr r) (+ i 1) (cons (car r) chunk-acc)))))))

  ;; Remove duplicates (preserves first occurrence)
  (define unique
    (case-lambda
      [(lst) (unique lst equal?)]
      [(lst eq-fn)
       (let loop ([rest lst] [seen '()] [acc '()])
         (cond
           [(null? rest) (reverse acc)]
           [(memp (lambda (s) (eq-fn s (car rest))) seen)
            (loop (cdr rest) seen acc)]
           [else
            (loop (cdr rest)
                  (cons (car rest) seen)
                  (cons (car rest) acc))]))]))

  ;; Count occurrences as hash table
  (define (frequencies lst)
    (let ([ht (make-hashtable equal-hash equal?)])
      (for-each (lambda (x)
                  (hashtable-update! ht x add1 0))
                lst)
      ht))

  ;; Find index of first element satisfying pred (or #f)
  (define (list-index pred lst)
    (let loop ([rest lst] [i 0])
      (cond
        [(null? rest) #f]
        [(pred (car rest)) i]
        [else (loop (cdr rest) (+ i 1))])))

  ;; Split list at index, returning two lists
  (define (list-split-at lst n)
    (let loop ([rest lst] [i 0] [acc '()])
      (if (or (= i n) (null? rest))
          (values (reverse acc) rest)
          (loop (cdr rest) (+ i 1) (cons (car rest) acc)))))

  ;; Append to end (snoc = cons reversed)
  (define (snoc lst elem)
    (append lst (list elem)))

  ;; All but last element
  (define (butlast lst)
    (if (or (null? lst) (null? (cdr lst)))
        '()
        (let loop ([rest lst] [acc '()])
          (if (null? (cdr rest))
              (reverse acc)
              (loop (cdr rest) (cons (car rest) acc))))))

) ;; end library
