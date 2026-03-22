#!chezscheme
;;; :std/srfi/95 -- SRFI-95 Sorting and Merging
;;; Provides a unified sort interface that works on both lists and vectors.

(library (std srfi srfi-95)
  (export sort sort! merge merge! sorted?)

  (import (except (chezscheme) sort sort! merge merge!))

  ;; (sorted? sequence less?) -- check if sorted
  (define (sorted? seq less?)
    (cond
      [(list? seq)
       (or (null? seq) (null? (cdr seq))
           (let loop ([prev (car seq)] [rest (cdr seq)])
             (or (null? rest)
                 (and (not (less? (car rest) prev))
                      (loop (car rest) (cdr rest))))))]
      [(vector? seq)
       (let ([len (vector-length seq)])
         (or (< len 2)
             (let loop ([i 1])
               (or (= i len)
                   (and (not (less? (vector-ref seq i) (vector-ref seq (- i 1))))
                        (loop (+ i 1)))))))]
      [else (error 'sorted? "expected list or vector" seq)]))

  ;; (merge list1 list2 less?) -- merge two sorted lists
  (define (merge lst1 lst2 less?)
    (cond
      [(null? lst1) lst2]
      [(null? lst2) lst1]
      [(less? (car lst2) (car lst1))
       (cons (car lst2) (merge lst1 (cdr lst2) less?))]
      [else
       (cons (car lst1) (merge (cdr lst1) lst2 less?))]))

  ;; (merge! list1 list2 less?) -- destructive merge
  (define (merge! lst1 lst2 less?)
    (cond
      [(null? lst1) lst2]
      [(null? lst2) lst1]
      [(less? (car lst2) (car lst1))
       (set-cdr! lst2 (merge! lst1 (cdr lst2) less?))
       lst2]
      [else
       (set-cdr! lst1 (merge! (cdr lst1) lst2 less?))
       lst1]))

  ;; (sort sequence less?) -- non-destructive sort
  (define (sort seq less?)
    (cond
      [(list? seq) (list-sort less? seq)]
      [(vector? seq)
       (let ([v (vector-copy seq)])
         (vector-sort! less? v)
         v)]
      [else (error 'sort "expected list or vector" seq)]))

  ;; (sort! sequence less?) -- destructive sort (for vectors; lists use merge sort)
  (define (sort! seq less?)
    (cond
      [(list? seq) (list-sort less? seq)] ;; list-sort already returns a new list
      [(vector? seq)
       (vector-sort! less? seq)
       seq]
      [else (error 'sort! "expected list or vector" seq)]))

) ;; end library
