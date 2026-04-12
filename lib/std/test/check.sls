#!chezscheme
;;; (std test check) — Property-Based Testing with Shrinking
;;;
;;; Inspired by Clojure's test.check / Haskell's QuickCheck.
;;; Generators produce random values; shrinking finds minimal
;;; failing cases.
;;;
;;; Usage:
;;;   (check-property 100
;;;     (for-all ([x (gen:integer)]
;;;               [y (gen:integer)])
;;;       (= (+ x y) (+ y x))))

(library (std test check)
  (export
    ;; Core
    gen:sample gen:generate
    for-all check-property

    ;; Generators
    gen:integer gen:nat gen:boolean gen:char gen:string
    gen:symbol gen:real
    gen:choose gen:elements gen:one-of
    gen:list gen:vector gen:pair
    gen:tuple gen:hash-table
    gen:such-that gen:fmap gen:bind gen:return
    gen:frequency gen:no-shrink gen:sized

    ;; Shrinking
    shrink-integer shrink-list shrink-string)

  (import (except (chezscheme) for-all))

  ;; =========================================================================
  ;; Rose tree: value + lazy list of shrunk variants
  ;; =========================================================================

  ;; A rose tree is (value . shrinks-thunk) where shrinks-thunk is a
  ;; procedure returning a list of rose trees.
  (define (rose val shrinks-thunk)
    (cons val shrinks-thunk))

  (define (rose-val r) (car r))
  (define (rose-shrinks r) ((cdr r)))

  (define (rose-pure val) (rose val (lambda () '())))

  (define (rose-fmap f r)
    (rose (f (rose-val r))
          (lambda () (map (lambda (s) (rose-fmap f s)) (rose-shrinks r)))))

  (define (rose-bind r f)
    (let ([inner (f (rose-val r))])
      (rose (rose-val inner)
            (lambda ()
              (append
                (map (lambda (s) (rose-bind s f)) (rose-shrinks r))
                (rose-shrinks inner))))))

  ;; =========================================================================
  ;; Generator: a function from (rng size) -> rose-tree
  ;; =========================================================================
  ;; rng is not used directly (we use Chez's built-in random).
  ;; size is an integer controlling the magnitude of generated values.

  (define (make-gen f) (vector 'gen f))
  (define (gen? x) (and (vector? x) (= (vector-length x) 2) (eq? (vector-ref x 0) 'gen)))
  (define (gen-func g) (vector-ref g 1))

  (define (gen:generate g size)
    (rose-val ((gen-func g) size)))

  (define (gen:sample g . opts)
    (let ([n (if (pair? opts) (car opts) 10)])
      (let loop ([i 0] [acc '()])
        (if (= i n) (reverse acc)
          (loop (+ i 1)
                (cons (gen:generate g (+ i 1)) acc))))))

  ;; =========================================================================
  ;; Generator combinators
  ;; =========================================================================

  (define (gen:return val)
    (make-gen (lambda (size) (rose-pure val))))

  (define (gen:fmap f g)
    (make-gen (lambda (size)
      (rose-fmap f ((gen-func g) size)))))

  (define (gen:bind g f)
    (make-gen (lambda (size)
      (rose-bind ((gen-func g) size)
                 (lambda (val) ((gen-func (f val)) size))))))

  (define (gen:sized f)
    ;; f takes size and returns a generator
    (make-gen (lambda (size)
      ((gen-func (f size)) size))))

  (define (gen:no-shrink g)
    (make-gen (lambda (size)
      (rose-pure (rose-val ((gen-func g) size))))))

  (define (gen:such-that pred g . opts)
    (let ([max-tries (if (pair? opts) (car opts) 100)])
      (make-gen (lambda (size)
        (let loop ([tries 0])
          (if (>= tries max-tries)
            (error 'gen:such-that "couldn't satisfy predicate" max-tries)
            (let ([r ((gen-func g) size)])
              (if (pred (rose-val r))
                r
                (loop (+ tries 1))))))))))

  ;; =========================================================================
  ;; Shrinking helpers
  ;; =========================================================================

  (define (shrink-integer n)
    ;; Shrink toward 0
    (if (= n 0) '()
      (let ([half (quotient n 2)])
        (let loop ([s (abs half)] [acc (list 0)])
          (if (>= s (abs n)) (reverse acc)
            (loop (* s 2)
                  (if (negative? n)
                    (cons (- s) acc)
                    (cons s acc))))))))

  (define (shrink-list lst)
    ;; Shrink by removing elements and shrinking individual elements
    (if (null? lst) '()
      (append
        ;; Remove each element in turn
        (let loop ([i 0] [acc '()])
          (if (>= i (length lst)) (reverse acc)
            (loop (+ i 1)
                  (cons (append (list-head lst i)
                                (list-tail lst (+ i 1)))
                        acc))))
        ;; Halve the list
        (if (> (length lst) 1)
          (list (list-head lst (quotient (length lst) 2)))
          '()))))

  (define (shrink-string s)
    (map list->string
         (shrink-list (string->list s))))

  ;; =========================================================================
  ;; Primitive generators
  ;; =========================================================================

  (define (gen:choose lo hi)
    (make-gen (lambda (size)
      (let ([val (+ lo (random (+ 1 (- hi lo))))])
        (rose val (lambda () (map rose-pure (shrink-integer val))))))))

  (define (gen:integer)
    (gen:sized (lambda (size)
      (gen:choose (- size) size))))

  (define (gen:nat)
    (gen:sized (lambda (size)
      (gen:choose 0 size))))

  (define (gen:boolean)
    (make-gen (lambda (size)
      (let ([val (= (random 2) 0)])
        (rose val (lambda () (if val (list (rose-pure #f)) '())))))))

  (define (gen:elements lst)
    (make-gen (lambda (size)
      (let ([val (list-ref lst (random (length lst)))])
        (rose-pure val)))))

  (define (gen:one-of gens)
    (make-gen (lambda (size)
      (let ([g (list-ref gens (random (length gens)))])
        ((gen-func g) size)))))

  (define (gen:frequency pairs)
    ;; pairs is ((weight . gen) ...)
    (let* ([total (apply + (map car pairs))]
           [pick (random total)])
      (make-gen (lambda (size)
        (let ([r (random total)])
          (let loop ([pairs pairs] [acc 0])
            (let ([w (caar pairs)] [g (cdar pairs)])
              (if (< r (+ acc w))
                ((gen-func g) size)
                (loop (cdr pairs) (+ acc w))))))))))

  (define (gen:char)
    (gen:fmap integer->char (gen:choose 32 126)))

  (define (gen:string)
    (gen:sized (lambda (size)
      (let ([len (random (+ size 1))])
        (make-gen (lambda (sz)
          (let* ([chars (let loop ([i 0] [acc '()])
                          (if (= i len) acc
                            (loop (+ i 1)
                                  (cons (integer->char (+ 32 (random 95)))
                                        acc))))]
                 [str (list->string chars)])
            (rose str (lambda () (map rose-pure (shrink-string str)))))))))))

  (define (gen:symbol)
    (gen:fmap string->symbol
      (gen:such-that (lambda (s) (> (string-length s) 0))
        (gen:fmap (lambda (s)
                    (list->string
                      (filter (lambda (c) (or (char-alphabetic? c)
                                              (char=? c #\-)
                                              (char=? c #\_)))
                              (string->list s))))
                  (gen:string)))))

  (define (gen:real)
    (gen:sized (lambda (size)
      (gen:fmap (lambda (n) (+ n (* (random 1000) 0.001)))
                (gen:choose (- size) size)))))

  (define (gen:list elem-gen)
    (gen:sized (lambda (size)
      (let ([len (random (+ size 1))])
        (make-gen (lambda (sz)
          (let* ([elems (let loop ([i 0] [acc '()])
                          (if (= i len) (reverse acc)
                            (loop (+ i 1)
                                  (cons (gen:generate elem-gen sz) acc))))])
            (rose elems (lambda () (map rose-pure (shrink-list elems)))))))))))

  (define (gen:vector elem-gen)
    (gen:fmap list->vector (gen:list elem-gen)))

  (define (gen:pair gen-a gen-b)
    (make-gen (lambda (size)
      (let ([a ((gen-func gen-a) size)]
            [b ((gen-func gen-b) size)])
        (rose (cons (rose-val a) (rose-val b))
              (lambda ()
                (append
                  (map (lambda (sa) (rose (cons (rose-val sa) (rose-val b))
                                         (lambda () '())))
                       (rose-shrinks a))
                  (map (lambda (sb) (rose (cons (rose-val a) (rose-val sb))
                                         (lambda () '())))
                       (rose-shrinks b)))))))))

  (define (gen:tuple . gens)
    (make-gen (lambda (size)
      (let ([roses (map (lambda (g) ((gen-func g) size)) gens)])
        (rose (map rose-val roses) (lambda () '()))))))

  (define (gen:hash-table key-gen val-gen)
    (gen:fmap (lambda (pairs)
                (let ([ht (make-hashtable equal-hash equal?)])
                  (for-each (lambda (p) (hashtable-set! ht (car p) (cdr p)))
                            pairs)
                  ht))
              (gen:list (gen:pair key-gen val-gen))))

  ;; =========================================================================
  ;; for-all — property macro
  ;; =========================================================================

  (define-syntax for-all
    (syntax-rules ()
      [(_ ([var gen] ...) body ...)
       (list (list gen ...) (lambda (var ...) body ...))]))

  ;; =========================================================================
  ;; check-property — run property tests
  ;; =========================================================================

  (define (check-property num-tests prop)
    (let ([gens (car prop)]
          [test-fn (cadr prop)])
      (let loop ([i 0] [size 1])
        (if (>= i num-tests)
          ;; All passed
          (list 'ok num-tests)
          (let* ([next-size (+ 1 (quotient (* i 30) num-tests))]
                 [roses (map (lambda (g) ((gen-func g) next-size)) gens)]
                 [vals (map rose-val roses)]
                 [passed? (guard (exn [#t #f])
                            (apply test-fn vals))])
            (if passed?
              (loop (+ i 1) next-size)
              ;; Failed — try to shrink
              (let ([shrunk (shrink-failure gens test-fn roses 0)])
                (list 'fail i vals (car shrunk) (cadr shrunk)))))))))

  (define (shrink-failure gens test-fn roses depth)
    (if (> depth 100)
      (list (map rose-val roses) depth)
      (let try-shrinks ([remaining-shrinks
                          (if (null? roses) '()
                            ;; Try shrinking each generator's rose tree
                            (let loop ([i 0] [acc '()])
                              (if (>= i (length roses))
                                (reverse acc)
                                (loop (+ i 1)
                                  (append acc
                                    (map (lambda (shrunk-rose)
                                           ;; Replace the i-th rose with shrunk
                                           (let replace ([j 0] [rs roses])
                                             (if (null? rs) '()
                                               (cons (if (= j i) shrunk-rose (car rs))
                                                     (replace (+ j 1) (cdr rs))))))
                                         (rose-shrinks (list-ref roses i))))))))])
        (if (null? remaining-shrinks)
          (list (map rose-val roses) depth)
          (let* ([candidate (car remaining-shrinks)]
                 [vals (map rose-val candidate)]
                 [still-fails? (guard (exn [#t #t])
                                 (not (apply test-fn vals)))])
            (if still-fails?
              (shrink-failure gens test-fn candidate (+ depth 1))
              (try-shrinks (cdr remaining-shrinks))))))))

) ;; end library
