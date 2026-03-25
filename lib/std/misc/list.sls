#!chezscheme
;;; :std/misc/list -- List utilities

(library (std misc list)
  (export flatten unique snoc
          take drop
          every any
          filter-map
          group-by
          zip
          ;; Clojure-inspired sequence utilities
          frequencies
          partition partition-all partition-by
          interleave interpose
          mapcat
          distinct
          keep
          some
          iterate-n
          reductions
          take-last drop-last
          split-at split-with)
  (import (except (chezscheme) partition))

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

  ;; --- Clojure-inspired sequence utilities ---

  ;; frequencies: count occurrences of each element
  ;; (frequencies '(a b a c b a)) => ((a . 3) (b . 2) (c . 1))
  (define (frequencies lst)
    (let ([ht (make-hashtable equal-hash equal?)])
      (for-each
        (lambda (x)
          (hashtable-update! ht x (lambda (n) (+ n 1)) 0))
        lst)
      (let-values ([(keys vals) (hashtable-entries ht)])
        (let loop ([i 0] [acc '()])
          (if (= i (vector-length keys)) acc
            (loop (+ i 1)
                  (cons (cons (vector-ref keys i) (vector-ref vals i))
                        acc)))))))

  ;; partition: split into fixed-size chunks
  ;; (partition 2 '(1 2 3 4 5)) => ((1 2) (3 4))  ; drops incomplete
  (define (partition n lst)
    (let loop ([rest lst] [acc '()])
      (let ([chunk (take rest n)])
        (if (< (length chunk) n)
          (reverse acc)
          (loop (drop rest n) (cons chunk acc))))))

  ;; partition-all: like partition but keeps incomplete final chunk
  ;; (partition-all 2 '(1 2 3 4 5)) => ((1 2) (3 4) (5))
  (define (partition-all n lst)
    (let loop ([rest lst] [acc '()])
      (if (null? rest)
        (reverse acc)
        (loop (drop rest n) (cons (take rest n) acc)))))

  ;; partition-by: split when f's return value changes
  ;; (partition-by odd? '(1 3 2 4 5)) => ((1 3) (2 4) (5))
  (define (partition-by f lst)
    (if (null? lst) '()
      (let loop ([rest (cdr lst)]
                 [prev-key (f (car lst))]
                 [current (list (car lst))]
                 [acc '()])
        (cond
          [(null? rest)
           (reverse (cons (reverse current) acc))]
          [else
           (let ([key (f (car rest))])
             (if (equal? key prev-key)
               (loop (cdr rest) key (cons (car rest) current) acc)
               (loop (cdr rest) key (list (car rest))
                     (cons (reverse current) acc))))]))))

  ;; interleave: interleave elements from multiple lists
  ;; (interleave '(1 2 3) '(a b c)) => (1 a 2 b 3 c)
  (define (interleave . lists)
    (let loop ([lsts lists] [acc '()])
      (if (any null? lsts) (reverse acc)
        (loop (map cdr lsts)
              (append (reverse (map car lsts)) acc)))))

  ;; interpose: insert separator between elements
  ;; (interpose ", " '("a" "b" "c")) => ("a" ", " "b" ", " "c")
  (define (interpose sep lst)
    (if (or (null? lst) (null? (cdr lst))) lst
      (cons (car lst)
            (let loop ([rest (cdr lst)])
              (if (null? rest) '()
                (cons sep (cons (car rest) (loop (cdr rest)))))))))

  ;; mapcat: map then concatenate (flatMap)
  ;; (mapcat (lambda (x) (list x x)) '(1 2 3)) => (1 1 2 2 3 3)
  (define (mapcat f lst)
    (apply append (map f lst)))

  ;; distinct: remove duplicates preserving order (like unique but Clojure name)
  (define (distinct lst)
    (unique lst))

  ;; keep: like filter-map — apply f, keep non-#f results
  ;; (keep (lambda (x) (and (> x 2) (* x 10))) '(1 2 3 4)) => (30 40)
  (define (keep f lst)
    (filter-map f lst))

  ;; some: return first truthy result of applying pred
  ;; (some even? '(1 3 4 5)) => #t
  (define (some pred lst)
    (and (pair? lst)
         (or (pred (car lst))
             (some pred (cdr lst)))))

  ;; iterate-n: take n values of repeated function application
  ;; (iterate-n 5 add1 0) => (0 1 2 3 4)
  (define (iterate-n n f init)
    (let loop ([i 0] [v init] [acc '()])
      (if (>= i n) (reverse acc)
        (loop (+ i 1) (f v) (cons v acc)))))

  ;; reductions: intermediate reduction values (like Clojure's reductions)
  ;; (reductions + 0 '(1 2 3 4)) => (0 1 3 6 10)
  (define (reductions f init lst)
    (let loop ([rest lst] [acc init] [result (list init)])
      (if (null? rest) (reverse result)
        (let ([next (f acc (car rest))])
          (loop (cdr rest) next (cons next result))))))

  ;; take-last: return last n elements
  ;; (take-last 2 '(1 2 3 4 5)) => (4 5)
  (define (take-last n lst)
    (let ([len (length lst)])
      (drop lst (max 0 (- len n)))))

  ;; drop-last: drop last n elements
  ;; (drop-last 2 '(1 2 3 4 5)) => (1 2 3)
  (define (drop-last n lst)
    (take lst (max 0 (- (length lst) n))))

  ;; split-at: split list at index n
  ;; (split-at 2 '(1 2 3 4 5)) => ((1 2) (3 4 5))
  (define (split-at n lst)
    (list (take lst n) (drop lst n)))

  ;; split-with: split where predicate first fails
  ;; (split-with even? '(2 4 5 6)) => ((2 4) (5 6))
  (define (split-with pred lst)
    (let loop ([rest lst] [acc '()])
      (cond
        [(null? rest) (list (reverse acc) '())]
        [(pred (car rest))
         (loop (cdr rest) (cons (car rest) acc))]
        [else (list (reverse acc) rest)])))

  ) ;; end library
