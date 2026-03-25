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
          split-at split-with
          ;; Gerbil v0.19 compatibility
          append-map append1
          flatten1
          push! pop!
          for-each!
          take-while take-until
          drop-while drop-until
          butlast
          slice
          split
          length=? length<? length<=? length>? length>=?
          length=n? length<n? length<=n? length>n? length>=n?
          group-consecutive group-n-consecutive group-same
          rassoc
          every-consecutive?
          map/car
          first-and-only
          when/list
          call-with-list-builder with-list-builder
          duplicates
          delete-duplicates/hash)
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

  ;; ---- Gerbil v0.19 compatibility ----

  ;; append-map: map then append (same as mapcat, Gerbil name)
  (define (append-map proc lst)
    (apply append (map proc lst)))

  ;; append1: append one element at end (same as snoc, Gerbil name)
  (define (append1 lst x) (append lst (list x)))

  ;; flatten1: remove one layer of nesting
  ;; (flatten1 '(1 (2 3) ((4)))) => (1 2 3 (4))
  (define (flatten1 lst)
    (let loop ((rest lst) (acc '()))
      (cond
        ((null? rest) (reverse acc))
        ((pair? (car rest))
         (loop (cdr rest) (fold-left (lambda (a x) (cons x a)) acc (car rest))))
        (else
         (loop (cdr rest) (cons (car rest) acc))))))

  ;; push!/pop! macros — CL-style mutation
  (define-syntax push!
    (lambda (stx)
      (syntax-case stx ()
        ((_ elem lst)
         #'(set! lst (cons elem lst))))))

  (define-syntax pop!
    (lambda (stx)
      (syntax-case stx ()
        ((_ lst)
         #'(let ((l lst))
             (and (pair? l)
                  (let ((v (car l)))
                    (set! lst (cdr l))
                    v)))))))

  ;; for-each! — like for-each but works on improper lists
  (define (for-each! lst proc)
    (let loop ((rest lst))
      (when (pair? rest)
        (proc (car rest))
        (loop (cdr rest)))))

  ;; take-while / take-until
  (define (take-while pred lst)
    (let loop ((rest lst) (acc '()))
      (cond
        ((null? rest) (reverse acc))
        ((pred (car rest))
         (loop (cdr rest) (cons (car rest) acc)))
        (else (reverse acc)))))

  (define (take-until pred lst)
    (take-while (lambda (x) (not (pred x))) lst))

  ;; drop-while / drop-until
  (define (drop-while pred lst)
    (let loop ((rest lst))
      (cond
        ((null? rest) '())
        ((pred (car rest)) (loop (cdr rest)))
        (else rest))))

  (define (drop-until pred lst)
    (drop-while (lambda (x) (not (pred x))) lst))

  ;; butlast: all but the last element
  ;; (butlast '(1 2 3)) => (1 2)
  (define (butlast lst)
    (if (or (null? lst) (null? (cdr lst))) '()
      (cons (car lst) (butlast (cdr lst)))))

  ;; slice: sublist from start with optional limit
  ;; (slice '(1 2 3 4) 2)   => (3 4)
  ;; (slice '(1 2 3 4) 2 1) => (3)
  (define slice
    (case-lambda
      ((lst start) (drop lst start))
      ((lst start limit) (take (drop lst start) limit))))

  ;; split: split list by value or predicate, with optional limit
  ;; (split '(1 2 0 3 4 0 5 6) 0)   => ((1 2) (3 4) (5 6))
  ;; (split '(1 2 0 3 4 0 5 6) 0 1) => ((1 2) (3 4 0 5 6))
  (define split
    (case-lambda
      ((lst stop) (split lst stop #f))
      ((lst stop limit)
       (let ((test (if (procedure? stop) stop (lambda (x) (equal? x stop)))))
         (let loop ((rest lst) (current '()) (n (or limit -1)))
           (cond
             ((null? rest)
              (if (null? current) '()
                (list (reverse current))))
             ((zero? n)
              (list (append (reverse current) rest)))
             ((test (car rest))
              (cons (reverse current)
                    (loop (cdr rest) '() (- n 1))))
             (else
              (loop (cdr rest) (cons (car rest) current) n))))))))

  ;; Efficient length comparisons (no full traversal needed)
  (define (length=? x y)
    (let loop ((x x) (y y))
      (let ((nx (not (pair? x)))
            (ny (not (pair? y))))
        (cond
          (nx ny)
          (ny #f)
          (else (loop (cdr x) (cdr y)))))))

  (define (length<? x y)
    (let loop ((x x) (y y))
      (let ((nx (not (pair? x)))
            (ny (not (pair? y))))
        (cond
          (nx (not ny))
          (ny #f)
          (else (loop (cdr x) (cdr y)))))))

  (define (length<=? x y) (not (length<? y x)))
  (define (length>? x y) (length<? y x))
  (define (length>=? x y) (not (length<? x y)))

  (define (length=n? x n)
    (and (fixnum? n) (fx>= n 0)
         (let loop ((x x) (n n))
           (cond
             ((not (pair? x)) (fxzero? n))
             ((fxzero? n) #f)
             (else (loop (cdr x) (fx- n 1)))))))

  (define (length<=n? x n)
    (and (fixnum? n) (fx>= n 0)
         (let loop ((x x) (n n))
           (cond
             ((not (pair? x)) #t)
             ((fxzero? n) #f)
             (else (loop (cdr x) (fx- n 1)))))))

  (define (length<n? x n)
    (and (fixnum? n) (fxpositive? n)
         (length<=n? x (fx- n 1))))

  (define (length>n? x n) (not (length<=n? x n)))
  (define (length>=n? x n) (not (length<n? x n)))

  ;; group-consecutive: group runs of equal elements
  ;; (group-consecutive '(1 1 2 2 3 1 1)) => ((1 1) (2 2) (3) (1 1))
  (define group-consecutive
    (case-lambda
      ((lst) (group-consecutive lst equal?))
      ((lst test)
       (if (null? lst) '()
         (let loop ((rest (cdr lst))
                    (latest (car lst))
                    (inner (list (car lst)))
                    (outer '()))
           (cond
             ((null? rest)
              (reverse (cons (reverse inner) outer)))
             ((test latest (car rest))
              (loop (cdr rest) (car rest) (cons (car rest) inner) outer))
             (else
              (loop (cdr rest) (car rest) (list (car rest))
                    (cons (reverse inner) outer)))))))))

  ;; group-n-consecutive: group into chunks of n
  ;; (group-n-consecutive 2 '(1 2 3 4 5)) => ((1 2) (3 4) (5))
  (define (group-n-consecutive n lst)
    (cond
      ((null? lst) '())
      ((length<=n? lst n) (list lst))
      (else
       (let-values (((hd tl) (let loop ((l lst) (i n) (acc '()))
                               (if (or (fxzero? i) (null? l))
                                 (values (reverse acc) l)
                                 (loop (cdr l) (fx- i 1) (cons (car l) acc))))))
         (cons hd (group-n-consecutive n tl))))))

  ;; group-same: group by key function into sublists
  ;; (group-same '(1 2 3 4) key: odd?) => ((1 3) (2 4))
  (define group-same
    (case-lambda
      ((lst) (group-same lst values))
      ((lst key)
       (let ((ht (make-hashtable equal-hash equal?))
             (order '()))
         (for-each
           (lambda (x)
             (let* ((k (key x))
                    (prev (hashtable-ref ht k #f)))
               (if prev
                 (hashtable-set! ht k (cons x prev))
                 (begin
                   (hashtable-set! ht k (list x))
                   (set! order (cons k order))))))
           lst)
         (map (lambda (k) (reverse (hashtable-ref ht k '())))
              (reverse order))))))

  ;; rassoc: reverse assoc — find pair by cdr
  ;; (rassoc 2 '((a . 1) (b . 2))) => (b . 2)
  (define rassoc
    (case-lambda
      ((x alist) (rassoc x alist eqv?))
      ((x alist cmp)
       (let loop ((lst alist))
         (cond
           ((null? lst) #f)
           ((and (pair? (car lst)) (cmp x (cdar lst)))
            (car lst))
           (else (loop (cdr lst))))))))

  ;; every-consecutive?: pairwise predicate check
  ;; (every-consecutive? < '(1 2 3 4)) => #t
  (define (every-consecutive? pred lst)
    (or (null? lst)
        (let loop ((x (car lst)) (rest (cdr lst)))
          (cond
            ((null? rest) #t)
            ((pred x (car rest))
             (loop (car rest) (cdr rest)))
            (else #f)))))

  ;; map/car: apply f to car of a pair
  ;; (map/car add1 '(1 . 2)) => (2 . 2)
  (define (map/car f p)
    (cons (f (car p)) (cdr p)))

  ;; first-and-only: assert exactly one element
  (define (first-and-only lst)
    (unless (and (pair? lst) (null? (cdr lst)))
      (error 'first-and-only "expected single-element list" lst))
    (car lst))

  ;; when/list: like when but returns '() instead of void when false
  (define-syntax when/list
    (lambda (stx)
      (syntax-case stx ()
        ((_ test body ...)
         #'(if test (begin body ...) '())))))

  ;; with-list-builder / call-with-list-builder
  ;; Efficient tail-cons list building
  (define-syntax with-list-builder
    (lambda (stx)
      (syntax-case stx ()
        ((_ (c) body ...)
         #'(let* ((head (list #f))
                  (tail head))
             (define (c val)
               (let ((new-tail (list val)))
                 (set-cdr! tail new-tail)
                 (set! tail new-tail)))
             body ...
             (cdr head))))))

  (define (call-with-list-builder proc)
    (with-list-builder (c) (proc c)))

  ;; duplicates: elements appearing more than once with counts
  ;; (duplicates '(a b a c b a)) => ((a . 3) (b . 2))
  (define duplicates
    (case-lambda
      ((lst) (duplicates lst equal?))
      ((lst test)
       (if (null? lst) '()
         (let ((ht (make-hashtable
                     (if (eq? test eq?) symbol-hash equal-hash)
                     test)))
           (for-each (lambda (x)
                       (hashtable-update! ht x (lambda (n) (+ n 1)) 0))
                     lst)
           (let-values (((keys vals) (hashtable-entries ht)))
             (let loop ((i 0) (acc '()))
               (if (= i (vector-length keys)) acc
                 (loop (+ i 1)
                       (if (> (vector-ref vals i) 1)
                         (cons (cons (vector-ref keys i) (vector-ref vals i)) acc)
                         acc))))))))))

  ;; delete-duplicates/hash: O(n) deduplication using hash table
  (define delete-duplicates/hash
    (case-lambda
      ((lst) (delete-duplicates/hash lst equal?))
      ((lst test)
       (let ((ht (make-hashtable
                   (if (eq? test eq?) symbol-hash equal-hash)
                   test)))
         (with-list-builder (c)
           (for-each (lambda (x)
                       (unless (hashtable-contains? ht x)
                         (hashtable-set! ht x #t)
                         (c x)))
                     lst))))))

  ) ;; end library
