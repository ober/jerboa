#!chezscheme
;;; :std/srfi/1 -- SRFI-1 List Library (subset)
;;; Only exports names NOT already in (chezscheme), to avoid conflicts.
;;; Chezscheme already provides: cons* list-copy last-pair find remove remove!
;;;   partition partition! fold-right filter for-each map null?

(library (std srfi srfi-1)
  (export
    ;; iota: SRFI-1 version takes (count [start [step]]), Chez takes (n)
    iota
    ;; Predicates not in chezscheme
    null-list? proper-list? circular-list? dotted-list? not-pair? list=
    ;; Selectors
    first second third fourth fifth sixth seventh eighth ninth tenth
    car+cdr
    ;; Searching
    find-tail any every list-index
    ;; Filtering
    filter! filter-map
    ;; Fold/map
    fold reduce reduce-right
    pair-fold pair-fold-right pair-reduce
    map! flat-map
    append-map append-map!
    ;; Deletion
    delete delete! delete-duplicates delete-duplicates!
    ;; Association lists
    alist-copy alist-delete alist-delete!
    ;; Misc
    count zip unzip1 unzip2 unzip3 unzip4 unzip5
    append-reverse append-reverse!
    take drop take-while drop-while
    take! drop-right drop-right! split-at split-at!
    concatenate concatenate!
    lset-union lset-intersection lset-difference
    lset-xor lset-diff+intersection
    lset-union! lset-intersection! lset-difference!
    lset-xor! lset-diff+intersection!)

  ;; Exclude iota from chezscheme (different sig); keep everything else
  (import (except (chezscheme) iota))

  ;; iota: SRFI-1 version — (iota count [start [step]])
  (define (iota count . rest)
    (let ((start (if (pair? rest) (car rest) 0))
          (step  (if (and (pair? rest) (pair? (cdr rest))) (cadr rest) 1)))
      (let loop ((i (- count 1)) (acc '()))
        (if (< i 0)
          acc
          (loop (- i 1) (cons (+ start (* i step)) acc))))))

  (define (null-list? x) (null? x))
  (define (not-pair? x) (not (pair? x)))

  (define (proper-list? x)
    (cond ((null? x) #t)
          ((pair? x) (proper-list? (cdr x)))
          (else #f)))

  (define (circular-list? x)
    (let loop ((slow x) (fast x))
      (cond ((not (pair? fast)) #f)
            ((not (pair? (cdr fast))) #f)
            ((eq? slow (cdr fast)) #t)
            (else (loop (cdr slow) (cddr fast))))))

  (define (dotted-list? x)
    (and (pair? x) (not (proper-list? x)) (not (circular-list? x))))

  (define (list= eq? . lists)
    (or (null? lists)
        (let lp ((l1 (car lists)) (rest (cdr lists)))
          (or (null? rest)
              (let ((l2 (car rest)))
                (let loop ((a l1) (b l2))
                  (cond ((and (null? a) (null? b)) (lp l2 (cdr rest)))
                        ((or (null? a) (null? b)) #f)
                        ((eq? (car a) (car b)) (loop (cdr a) (cdr b)))
                        (else #f))))))))

  (define (first  x) (car x))
  (define (second x) (cadr x))
  (define (third  x) (caddr x))
  (define (fourth x) (cadddr x))
  (define (fifth  x) (car (cddddr x)))
  (define (sixth  x) (cadr (cddddr x)))
  (define (seventh x) (caddr (cddddr x)))
  (define (eighth  x) (cadddr (cddddr x)))
  (define (ninth   x) (car (cddddr (cddddr x))))
  (define (tenth   x) (cadr (cddddr (cddddr x))))

  (define (car+cdr pair) (values (car pair) (cdr pair)))

  (define (find-tail pred lst)
    (cond ((null? lst) #f)
          ((pred (car lst)) lst)
          (else (find-tail pred (cdr lst)))))

  (define (any pred . lists)
    (if (null? lists)
      #f
      (let lp ((ls lists))
        (if (null? (car ls)) #f
          (let ((vs (map car ls)))
            (or (apply pred vs)
                (lp (map cdr ls))))))))

  (define (every pred . lists)
    (if (null? lists)
      #t
      (let lp ((ls lists))
        (if (null? (car ls)) #t
          (let ((vs (map car ls)))
            (and (apply pred vs)
                 (lp (map cdr ls))))))))

  (define (list-index pred . lists)
    (let lp ((ls lists) (i 0))
      (if (null? (car ls)) #f
        (if (apply pred (map car ls)) i
          (lp (map cdr ls) (+ i 1))))))

  (define (count pred lst)
    (let lp ((lst lst) (n 0))
      (if (null? lst) n
        (lp (cdr lst) (if (pred (car lst)) (+ n 1) n)))))

  (define (filter! pred lst) (filter pred lst))

  (define (filter-map f lst)
    (let lp ((lst lst) (acc '()))
      (if (null? lst) (reverse acc)
        (let ((v (f (car lst))))
          (lp (cdr lst) (if v (cons v acc) acc))))))

  (define (fold kons knil lst)
    (if (null? lst) knil
      (fold kons (kons (car lst) knil) (cdr lst))))

  (define (reduce f ridentity lst)
    (if (null? lst) ridentity
      (fold f (car lst) (cdr lst))))

  (define (reduce-right f ridentity lst)
    (if (null? lst) ridentity
      (fold-right f (car (last-pair lst)) lst)))

  (define (pair-fold f knil lst)
    (if (null? lst) knil
      (let ((tail (cdr lst)))
        (pair-fold f (f lst knil) tail))))

  (define (pair-fold-right f knil lst)
    (if (null? lst) knil
      (f lst (pair-fold-right f knil (cdr lst)))))

  (define (pair-reduce f ridentity lst)
    (if (null? lst) ridentity
      (pair-fold f lst (cdr lst))))

  (define (map! f lst) (map f lst))
  (define (flat-map f lst) (apply append (map f lst)))
  (define (append-map f lst) (apply append (map f lst)))
  (define (append-map! f lst) (append-map f lst))

  (define (delete x lst . rest)
    (let ((eq (if (pair? rest) (car rest) equal?)))
      (filter (lambda (e) (not (eq x e))) lst)))

  (define (delete! x lst . rest) (apply delete x lst rest))

  (define (delete-duplicates lst . rest)
    (let ((eq (if (pair? rest) (car rest) equal?)))
      (let lp ((lst lst) (seen '()))
        (cond ((null? lst) (reverse seen))
              ((any (lambda (s) (eq s (car lst))) seen)
               (lp (cdr lst) seen))
              (else (lp (cdr lst) (cons (car lst) seen)))))))

  (define (delete-duplicates! lst . rest) (apply delete-duplicates lst rest))

  (define (alist-copy alist) (map (lambda (p) (cons (car p) (cdr p))) alist))

  (define (alist-delete key alist . rest)
    (let ((eq (if (pair? rest) (car rest) equal?)))
      (filter (lambda (p) (not (eq key (car p)))) alist)))

  (define (alist-delete! key alist . rest) (apply alist-delete key alist rest))

  (define (zip . lists) (apply map list lists))
  (define (unzip1 lst) (map car lst))
  (define (unzip2 lst) (values (map car lst) (map cadr lst)))
  (define (unzip3 lst) (values (map car lst) (map cadr lst) (map caddr lst)))
  (define (unzip4 lst) (values (map car lst) (map cadr lst) (map caddr lst) (map cadddr lst)))
  (define (unzip5 lst)
    (values (map car lst) (map cadr lst) (map caddr lst)
            (map cadddr lst) (map (lambda (x) (car (cddddr x))) lst)))

  (define (append-reverse rev-head tail) (fold cons tail rev-head))
  (define (append-reverse! rev-head tail) (append-reverse rev-head tail))

  (define (take lst k)
    (let lp ((lst lst) (k k) (acc '()))
      (if (or (= k 0) (null? lst)) (reverse acc)
        (lp (cdr lst) (- k 1) (cons (car lst) acc)))))

  (define (drop lst k)
    (if (or (= k 0) (null? lst)) lst
      (drop (cdr lst) (- k 1))))

  (define (take-while pred lst)
    (let lp ((lst lst) (acc '()))
      (if (or (null? lst) (not (pred (car lst)))) (reverse acc)
        (lp (cdr lst) (cons (car lst) acc)))))

  (define (drop-while pred lst)
    (cond ((null? lst) '())
          ((pred (car lst)) (drop-while pred (cdr lst)))
          (else lst)))

  (define (take! lst k) (take lst k))

  (define (drop-right lst k)
    (let ((len (length lst)))
      (take lst (max 0 (- len k)))))

  (define (drop-right! lst k) (drop-right lst k))

  (define (split-at lst k) (values (take lst k) (drop lst k)))
  (define (split-at! lst k) (split-at lst k))

  (define (concatenate lists) (apply append lists))
  (define (concatenate! lists) (concatenate lists))

  (define (lset-union eq? . lists)
    (fold (lambda (lst result)
            (fold (lambda (e r)
                    (if (any (lambda (x) (eq? e x)) r) r (cons e r)))
                  result lst))
          '() lists))

  (define (lset-intersection eq? lst . rest)
    (if (null? rest) lst
      (filter (lambda (e)
                (every (lambda (s) (any (lambda (x) (eq? e x)) s)) rest))
              lst)))

  (define (lset-difference eq? lst . rest)
    (if (null? rest) lst
      (filter (lambda (e)
                (every (lambda (s) (not (any (lambda (x) (eq? e x)) s))) rest))
              lst)))

  (define (lset-xor eq? . lists)
    (fold (lambda (lst result)
            (let ((only-in-lst (lset-difference eq? lst result))
                  (only-in-result (lset-difference eq? result lst)))
              (append only-in-lst only-in-result)))
          '() lists))

  (define (lset-diff+intersection eq? lst . rest)
    (values (apply lset-difference eq? lst rest)
            (apply lset-intersection eq? lst rest)))

  (define (lset-union! eq? . lists) (apply lset-union eq? lists))
  (define (lset-intersection! eq? lst . rest) (apply lset-intersection eq? lst rest))
  (define (lset-difference! eq? lst . rest) (apply lset-difference eq? lst rest))
  (define (lset-xor! eq? . lists) (apply lset-xor eq? lists))
  (define (lset-diff+intersection! eq? lst . rest) (apply lset-diff+intersection eq? lst rest))

) ;; end library
