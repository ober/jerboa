#!chezscheme
;;; :std/srfi/132 -- Sort Libraries (SRFI-132)
;;; Provides list and vector sorting with comparator argument first.

(library (std srfi srfi-132)
  (export
    list-sort list-stable-sort list-sort!
    vector-sort vector-stable-sort vector-sort!
    list-merge list-merge!
    vector-merge vector-merge!
    list-sorted? vector-sorted?)

  (import (except (chezscheme) list-sort vector-sort vector-sort!))

  ;; ---- List sorting (merge sort, stable) ----

  (define (list-sorted? less? lst)
    (or (null? lst)
        (null? (cdr lst))
        (let loop ([prev (car lst)] [rest (cdr lst)])
          (or (null? rest)
              (let ([cur (car rest)])
                (and (not (less? cur prev))
                     (loop cur (cdr rest))))))))

  (define (list-merge less? lst1 lst2)
    (let loop ([a lst1] [b lst2] [acc '()])
      (cond
        [(null? a) (append (reverse acc) b)]
        [(null? b) (append (reverse acc) a)]
        [(less? (car b) (car a))
         (loop a (cdr b) (cons (car b) acc))]
        [else
         (loop (cdr a) b (cons (car a) acc))])))

  (define (list-merge! less? lst1 lst2)
    ;; Destructive merge: reuse cons cells
    (cond
      [(null? lst1) lst2]
      [(null? lst2) lst1]
      [else
       (let ([result (if (less? (car lst2) (car lst1)) lst2 lst1)]
             [other  (if (less? (car lst2) (car lst1)) lst1 lst2)])
         (let loop ([tail result]
                    [a (cdr result)]
                    [b other])
           (cond
             [(null? a) (set-cdr! tail b)]
             [(null? b) (set-cdr! tail a)]
             [(less? (car b) (car a))
              (set-cdr! tail b)
              (loop b a (cdr b))]
             [else
              (set-cdr! tail a)
              (loop a (cdr a) b)]))
         result)]))

  (define (list-sort less? lst)
    (list-merge-sort less? lst))

  (define (list-stable-sort less? lst)
    (list-merge-sort less? lst))

  (define (list-sort! less? lst)
    (list-merge-sort! less? lst))

  ;; Merge sort for lists (stable, O(n log n))
  (define (list-merge-sort less? lst)
    (let ([n (length lst)])
      (if (<= n 1)
        lst
        (let-values ([(left right) (split-at-n lst (quotient n 2))])
          (list-merge less?
            (list-merge-sort less? left)
            (list-merge-sort less? right))))))

  ;; Destructive merge sort
  (define (list-merge-sort! less? lst)
    (let ([n (length lst)])
      (if (<= n 1)
        lst
        (let-values ([(left right) (split-at-n lst (quotient n 2))])
          (list-merge! less?
            (list-merge-sort! less? left)
            (list-merge-sort! less? right))))))

  (define (split-at-n lst n)
    (let loop ([i 0] [rest lst] [acc '()])
      (if (= i n)
        (values (reverse acc) rest)
        (loop (+ i 1) (cdr rest) (cons (car rest) acc)))))

  ;; ---- Vector sorting ----

  (define (vector-sorted? less? vec . args)
    (let ([start (if (pair? args) (car args) 0)]
          [end (if (and (pair? args) (pair? (cdr args)))
                   (cadr args)
                   (vector-length vec))])
      (or (<= (- end start) 1)
          (let loop ([i (+ start 1)])
            (or (= i end)
                (and (not (less? (vector-ref vec i)
                                 (vector-ref vec (- i 1))))
                     (loop (+ i 1))))))))

  ;; vector-sort: returns a new sorted vector
  (define (vector-sort less? vec . args)
    (let* ([start (if (pair? args) (car args) 0)]
           [end (if (and (pair? args) (pair? (cdr args)))
                    (cadr args)
                    (vector-length vec))]
           [len (- end start)]
           [result (make-vector len)])
      (do ([i 0 (+ i 1)])
          ((= i len))
        (vector-set! result i (vector-ref vec (+ start i))))
      (vector-sort-internal! less? result 0 len)
      result))

  (define (vector-stable-sort less? vec . args)
    (let* ([start (if (pair? args) (car args) 0)]
           [end (if (and (pair? args) (pair? (cdr args)))
                    (cadr args)
                    (vector-length vec))]
           [len (- end start)]
           [result (make-vector len)])
      (do ([i 0 (+ i 1)])
          ((= i len))
        (vector-set! result i (vector-ref vec (+ start i))))
      (vector-merge-sort! less? result (make-vector len) 0 len)
      result))

  ;; vector-sort!: sort in place
  (define (vector-sort! less? vec . args)
    (let ([start (if (pair? args) (car args) 0)]
          [end (if (and (pair? args) (pair? (cdr args)))
                   (cadr args)
                   (vector-length vec))])
      (vector-sort-internal! less? vec start end)))

  ;; Quicksort for vectors
  (define (vector-sort-internal! less? vec lo hi)
    (when (< (+ lo 1) hi)
      (let ([pivot (vector-ref vec lo)]
            [i lo]
            [j hi])
        ;; Partition
        (let ([mid (let loop ([l (+ lo 1)] [r (- hi 1)])
                     (let loop-l ([l l])
                       (if (and (< l hi) (less? (vector-ref vec l) pivot))
                         (loop-l (+ l 1))
                         (let loop-r ([r r])
                           (if (and (> r lo) (less? pivot (vector-ref vec r)))
                             (loop-r (- r 1))
                             (if (< l r)
                               (begin
                                 (let ([tmp (vector-ref vec l)])
                                   (vector-set! vec l (vector-ref vec r))
                                   (vector-set! vec r tmp))
                                 (loop (+ l 1) (- r 1)))
                               r))))))])
          ;; Put pivot in place
          (let ([tmp (vector-ref vec lo)])
            (vector-set! vec lo (vector-ref vec mid))
            (vector-set! vec mid tmp))
          (vector-sort-internal! less? vec lo mid)
          (vector-sort-internal! less? vec (+ mid 1) hi)))))

  ;; Merge sort for vectors (stable)
  (define (vector-merge-sort! less? vec aux lo hi)
    (when (> (- hi lo) 1)
      (let ([mid (quotient (+ lo hi) 2)])
        (vector-merge-sort! less? vec aux lo mid)
        (vector-merge-sort! less? vec aux mid hi)
        ;; Merge
        (do ([i lo (+ i 1)])
            ((= i hi))
          (vector-set! aux i (vector-ref vec i)))
        (let loop ([i lo] [j lo] [k mid])
          (when (< i hi)
            (cond
              [(>= j mid)
               (vector-set! vec i (vector-ref aux k))
               (loop (+ i 1) j (+ k 1))]
              [(>= k hi)
               (vector-set! vec i (vector-ref aux j))
               (loop (+ i 1) (+ j 1) k)]
              [(less? (vector-ref aux k) (vector-ref aux j))
               (vector-set! vec i (vector-ref aux k))
               (loop (+ i 1) j (+ k 1))]
              [else
               (vector-set! vec i (vector-ref aux j))
               (loop (+ i 1) (+ j 1) k)]))))))

  ;; vector-merge: merge two sorted vectors into a new vector
  (define (vector-merge less? vec1 vec2)
    (let* ([n1 (vector-length vec1)]
           [n2 (vector-length vec2)]
           [result (make-vector (+ n1 n2))])
      (let loop ([i 0] [j 0] [k 0])
        (cond
          [(and (= j n1) (= k n2)) result]
          [(= j n1)
           (vector-set! result i (vector-ref vec2 k))
           (loop (+ i 1) j (+ k 1))]
          [(= k n2)
           (vector-set! result i (vector-ref vec1 j))
           (loop (+ i 1) (+ j 1) k)]
          [(less? (vector-ref vec2 k) (vector-ref vec1 j))
           (vector-set! result i (vector-ref vec2 k))
           (loop (+ i 1) j (+ k 1))]
          [else
           (vector-set! result i (vector-ref vec1 j))
           (loop (+ i 1) (+ j 1) k)]))))

  ;; vector-merge!: merge into a pre-allocated vector
  (define (vector-merge! less? result vec1 vec2)
    (let ([n1 (vector-length vec1)]
          [n2 (vector-length vec2)])
      (let loop ([i 0] [j 0] [k 0])
        (cond
          [(and (= j n1) (= k n2)) result]
          [(= j n1)
           (vector-set! result i (vector-ref vec2 k))
           (loop (+ i 1) j (+ k 1))]
          [(= k n2)
           (vector-set! result i (vector-ref vec1 j))
           (loop (+ i 1) (+ j 1) k)]
          [(less? (vector-ref vec2 k) (vector-ref vec1 j))
           (vector-set! result i (vector-ref vec2 k))
           (loop (+ i 1) j (+ k 1))]
          [else
           (vector-set! result i (vector-ref vec1 j))
           (loop (+ i 1) (+ j 1) k)]))))

) ;; end library
