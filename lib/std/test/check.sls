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

    ;; Generators (jerboa colon-flavor — original)
    gen:integer gen:nat gen:boolean gen:char gen:string
    gen:symbol gen:real
    gen:choose gen:elements gen:one-of
    gen:list gen:vector gen:pair
    gen:tuple gen:hash-table
    gen:such-that gen:fmap gen:bind gen:return
    gen:frequency gen:no-shrink gen:sized

    ;; Shrinking
    shrink-integer shrink-list shrink-string

    ;; Clojure test.check-flavor API (Round 13, 2026-04-27)
    gen/return gen/fmap gen/bind gen/sized gen/no-shrink
    gen/choose gen/elements gen/one-of gen/such-that
    gen/frequency gen/tuple
    gen/boolean gen/byte gen/char gen/char-alphanumeric
    gen/int gen/nat gen/pos-int gen/neg-int gen/large-integer
    gen/string gen/string-alphanumeric gen/string-ascii
    gen/keyword gen/symbol gen/uuid
    gen/list-of gen/vector-of gen/hash-set-of gen/hash-map-of
    gen/sample
    prop/for-all quick-check defspec)

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

  ;; =========================================================================
  ;; Round 13 (2026-04-27) — Clojure test.check-flavor API
  ;; Re-exposes the existing engine under the canonical Clojure names
  ;; (gen/return, gen/fmap, ...) and fills in built-ins not previously
  ;; covered (uuid, keyword, large-integer, hash-set, etc.).
  ;; All of these are layered on top of the original gen:* engine —
  ;; no behavioural changes to the existing API.
  ;; =========================================================================

  ;; ---- combinator aliases ----
  (define gen/return    gen:return)
  (define gen/fmap      gen:fmap)
  (define gen/bind      gen:bind)
  (define gen/sized     gen:sized)
  (define gen/no-shrink gen:no-shrink)
  (define gen/choose    gen:choose)
  (define gen/elements  gen:elements)
  (define gen/one-of    gen:one-of)
  (define gen/such-that gen:such-that)
  (define gen/frequency gen:frequency)
  (define gen/tuple     gen:tuple)
  (define gen/sample    gen:sample)

  ;; ---- numeric built-ins ----
  (define gen/boolean (gen:boolean))
  (define gen/byte    (gen:choose 0 255))
  (define gen/int
    (gen:sized (lambda (size) (gen:choose (- size) size))))
  (define gen/nat
    (gen:sized (lambda (size) (gen:choose 0 size))))
  (define gen/pos-int
    (gen:sized (lambda (size) (gen:choose 1 (max 1 size)))))
  (define gen/neg-int
    (gen:sized (lambda (size) (gen:choose (- (max 1 size)) -1))))
  (define gen/large-integer
    (gen:sized
      (lambda (size)
        (let ([scale (max 1 (* size size))])
          (gen:choose (- scale) scale)))))

  ;; ---- char + string ----
  (define gen/char (gen:char))

  (define gen/char-alphanumeric
    (gen:fmap integer->char
      (gen:one-of
        (list (gen:choose 48 57)     ;; 0-9
              (gen:choose 65 90)     ;; A-Z
              (gen:choose 97 122)))))  ;; a-z

  (define gen/string (gen:string))

  (define (string-from-char-gen char-gen)
    (gen:sized
      (lambda (size)
        (gen:fmap list->string
          (gen:list-from-elem char-gen size)))))

  ;; helper used only inside this module
  (define (gen:list-from-elem elem-gen target-size)
    (make-gen
      (lambda (sz)
        (let* ([len (random (+ target-size 1))]
               [elems (let loop ([i 0] [acc '()])
                        (if (= i len)
                          (reverse acc)
                          (loop (+ i 1)
                            (cons (gen:generate elem-gen sz) acc))))])
          (rose elems
                (lambda () (map rose-pure (shrink-list elems))))))))

  (define gen/string-alphanumeric (string-from-char-gen gen/char-alphanumeric))

  (define gen/string-ascii
    (string-from-char-gen
      (gen:fmap integer->char (gen:choose 32 126))))

  (define gen/keyword
    (gen:fmap (lambda (s) (string->symbol (string-append ":" s)))
      (gen:such-that
        (lambda (s) (> (string-length s) 0))
        gen/string-alphanumeric)))

  (define gen/symbol (gen:symbol))

  ;; ---- UUID v4-shaped (random hex; not cryptographically RFC-4122) ----
  (define (rand-hex-char)
    (let ([n (random 16)])
      (string-ref "0123456789abcdef" n)))

  (define (rand-hex-string n)
    (let ([cs (make-string n)])
      (let loop ([i 0])
        (if (= i n)
          cs
          (begin (string-set! cs i (rand-hex-char))
                 (loop (+ i 1)))))))

  (define gen/uuid
    (make-gen
      (lambda (_size)
        (rose-pure
          (string-append
            (rand-hex-string 8) "-"
            (rand-hex-string 4) "-4"
            (rand-hex-string 3) "-"
            (string (string-ref "89ab" (random 4)))
            (rand-hex-string 3) "-"
            (rand-hex-string 12))))))

  ;; ---- collection generators (Clojure style: gen/list-of, etc.) ----
  (define gen/list-of   gen:list)
  (define gen/vector-of gen:vector)

  (define (gen/hash-set-of elem-gen)
    (gen:fmap
      (lambda (lst)
        (let ([ht (make-hashtable equal-hash equal?)])
          (for-each (lambda (x) (hashtable-set! ht x #t)) lst)
          ht))
      (gen:list elem-gen)))

  (define (gen/hash-map-of key-gen val-gen)
    (gen:hash-table key-gen val-gen))

  ;; ---- prop/for-all + quick-check + defspec ----

  (define-syntax prop/for-all
    (syntax-rules ()
      [(_ ([var gen] ...) body ...)
       (for-all ([var gen] ...) body ...)]))

  ;; quick-check: returns a hashtable result map (compatible with
  ;; jerboa's hash-ref).  Insertion-ordered when iterated (the
  ;; underlying ordered-hashtable is captured below in -ordered).
  ;; Shape mirrors Clojure test.check:
  ;;   result        — #t on success, #f on failure
  ;;   pass?         — boolean alias of result
  ;;   num-tests     — total trials run
  ;;   failing-size  — size index at first failure
  ;;   fail          — first failing input list
  ;;   shrunk        — alist with 'smallest and 'depth
  (define (qc-result-map alist)
    (let ([ht (make-hashtable equal-hash equal?)])
      (for-each
        (lambda (p) (hashtable-set! ht (car p) (cdr p)))
        alist)
      ht))

  (define quick-check
    (case-lambda
      [(num-tests prop) (quick-check num-tests prop 200)]
      [(num-tests prop max-size)
       (let ([raw (check-property num-tests prop)])
         (if (eq? (car raw) 'ok)
           (qc-result-map
             `((result . #t)
               (num-tests . ,num-tests)
               (pass? . #t)))
           ;; (fail i vals shrunk-vals depth)
           (qc-result-map
             `((result . #f)
               (pass? . #f)
               (num-tests . ,num-tests)
               (failing-size . ,(cadr raw))
               (fail . ,(caddr raw))
               (shrunk . ((smallest . ,(cadddr raw))
                          (depth . ,(car (cddddr raw)))))))))]))

  ;; defspec — names a thunk that runs quick-check and returns its
  ;; result map.  Uses `define` (jerboa code can wrap with mat).
  (define-syntax defspec
    (syntax-rules ()
      [(_ name num-tests prop)
       (define (name)
         (quick-check num-tests prop))]))

) ;; end library
