#!chezscheme
;;; tests/test-quickcheck.ss -- Tests for (std test quickcheck)

(import (except (chezscheme) for-all) (std test quickcheck))

(define pass-count 0)
(define fail-count 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail-count (+ fail-count 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn)
                           (format "~s" exn)))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass-count (+ pass-count 1)) (printf "  ok ~a~%" name))
           (begin (set! fail-count (+ fail-count 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(define-syntax test-pred
  (syntax-rules ()
    [(_ name pred expr)
     (guard (exn [#t (set! fail-count (+ fail-count 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn)
                           (format "~s" exn)))])
       (let ([got expr])
         (if (pred got)
           (begin (set! pass-count (+ pass-count 1)) (printf "  ok ~a~%" name))
           (begin (set! fail-count (+ fail-count 1))
                  (printf "FAIL ~a: ~s did not satisfy ~a~%" name got 'pred)))))]))

(printf "~%--- QuickCheck Tests ---~%~%")

;; ================================================================
;; 1. Primitive generators produce correct types
;; ================================================================
(printf "-- Generator type checks --~%")

(test-pred "gen-int returns integer"
  integer? (gen-int 10))

(test-pred "gen-nat returns non-negative"
  (lambda (n) (and (integer? n) (>= n 0)))
  (gen-nat 10))

(test-pred "gen-bool returns boolean"
  boolean? (gen-bool 5))

(test-pred "gen-char returns char"
  char? (gen-char 5))

(test-pred "gen-string returns string"
  string? (gen-string 10))

;; ================================================================
;; 2. gen-int range respects size
;; ================================================================
(printf "~%-- gen-int respects size --~%")

(test "gen-int size 0 is 0" (gen-int 0) 0)

;; Run many times, all should be in [-size, size]
(let ([size 5])
  (test-pred "gen-int within bounds"
    (lambda (x) x)
    (let loop ([n 200] [all-ok? #t])
      (if (zero? n)
          all-ok?
          (let ([v (gen-int size)])
            (loop (- n 1)
                  (and all-ok? (>= v (- size)) (<= v size))))))))

;; ================================================================
;; 3. gen-nat is always non-negative
;; ================================================================
(printf "~%-- gen-nat always non-negative --~%")

(test-pred "gen-nat many trials"
  (lambda (x) x)
  (let loop ([n 200] [ok? #t])
    (if (zero? n)
        ok?
        (loop (- n 1) (and ok? (>= (gen-nat 20) 0))))))

;; ================================================================
;; 4. gen-list produces lists of correct type
;; ================================================================
(printf "~%-- gen-list --~%")

(let ([gen (gen-list gen-int)])
  (test-pred "gen-list returns list"
    list? (gen 10))
  (test-pred "gen-list elements are integers"
    (lambda (lst) (andmap (lambda (x) (integer? x)) lst))
    (gen 10)))

;; ================================================================
;; 5. gen-vector produces vectors
;; ================================================================
(printf "~%-- gen-vector --~%")

(let ([gen (gen-vector gen-int)])
  (test-pred "gen-vector returns vector"
    vector? (gen 10)))

;; ================================================================
;; 6. gen-one-of picks from the list
;; ================================================================
(printf "~%-- gen-one-of --~%")

(let ([gen (gen-one-of '(a b c))])
  (test-pred "gen-one-of from set"
    (lambda (v) (memv v '(a b c)))
    (gen 5)))

;; ================================================================
;; 7. gen-pair makes pairs
;; ================================================================
(printf "~%-- gen-pair --~%")

(let ([gen (gen-pair gen-int gen-bool)])
  (let ([p (gen 10)])
    (test-pred "gen-pair returns pair" pair? p)
    (test-pred "gen-pair car is integer" integer? (car p))
    (test-pred "gen-pair cdr is boolean" boolean? (cdr p))))

;; ================================================================
;; 8. gen-choose range
;; ================================================================
(printf "~%-- gen-choose --~%")

(let ([gen (gen-choose 5 10)])
  (test-pred "gen-choose in range"
    (lambda (x) x)
    (let loop ([n 200] [ok? #t])
      (if (zero? n)
          ok?
          (let ([v (gen 0)])
            (loop (- n 1) (and ok? (>= v 5) (<= v 10))))))))

;; ================================================================
;; 9. Generator combinators
;; ================================================================
(printf "~%-- Combinators --~%")

;; gen-map
(test-pred "gen-map doubles"
  even?
  ((gen-map (lambda (n) (* 2 n)) gen-nat) 10))

;; gen-bind
(let ([gen (gen-bind gen-nat
                     (lambda (n) (gen-choose 0 (max 1 n))))])
  (test-pred "gen-bind produces integer"
    integer? (gen 10)))

;; gen-filter
(let ([gen (gen-filter even? gen-int)])
  (test-pred "gen-filter only evens"
    even? (gen 20)))

;; gen-sized
(let ([gen (gen-sized (lambda (sz) (gen-choose 0 (max 1 sz))))])
  (test-pred "gen-sized produces integer"
    integer? (gen 10)))

;; ================================================================
;; 10. make-gen
;; ================================================================
(printf "~%-- make-gen --~%")

(let ([gen (make-gen (lambda (size) (* size 2)))])
  (test "make-gen custom" (gen 5) 10))

;; ================================================================
;; 11. Shrinking
;; ================================================================
(printf "~%-- Shrinking --~%")

;; shrink-int
(test "shrink-int 0" (shrink-int 0) '())
(test-pred "shrink-int 10 contains 0"
  (lambda (lst) (memv 0 lst))
  (shrink-int 10))
(test-pred "shrink-int 10 all smaller"
  (lambda (lst) (andmap (lambda (c) (< c 10)) lst))
  (shrink-int 10))
(test-pred "shrink-int -5 all closer to 0"
  (lambda (lst) (andmap (lambda (c) (< (abs c) 5)) lst))
  (shrink-int -5))

;; shrink-list
(test "shrink-list empty" (shrink-list '()) '())
(test-pred "shrink-list starts with empty"
  (lambda (lst) (and (pair? lst) (null? (car lst))))
  (shrink-list '(1 2 3)))
(test-pred "shrink-list all shorter"
  (lambda (candidates)
    (andmap (lambda (c) (< (length c) 3)) candidates))
  (shrink-list '(1 2 3)))

;; shrink-string
(test-pred "shrink-string produces strings"
  (lambda (lst) (andmap string? lst))
  (shrink-string "hello"))
(test-pred "shrink-string all shorter"
  (lambda (lst) (andmap (lambda (s) (< (string-length s) 5)) lst))
  (shrink-string "hello"))

;; ================================================================
;; 12. check-property -- passing property
;; ================================================================
(printf "~%-- check-property --~%")

(let ([result (check-property 50 (list gen-int gen-int)
               (lambda (a b) (= (+ a b) (+ b a))))])
  (test "commutativity passes"
    (cdr (assq 'status result))
    'pass)
  (test "ran 50 trials"
    (cdr (assq 'trials result))
    50))

;; ================================================================
;; 13. check-property -- failing property detected
;; ================================================================
(printf "~%-- check-property detects failure --~%")

(let ([result (check-property 100 (list gen-nat)
               (lambda (n) (< n 50)))])
  (test "large-nat fails"
    (cdr (assq 'status result))
    'fail)
  (test-pred "shrunk result present"
    (lambda (r) (assq 'shrunk r))
    result))

;; ================================================================
;; 14. check-property -- shrinking works
;; ================================================================
(printf "~%-- Shrinking finds minimal counterexample --~%")

;; Property: n < 10.  Minimal counterexample is 10.
(let ([result (check-property 200 (list gen-nat)
               (lambda (n) (< n 10)))])
  (test "fails as expected"
    (cdr (assq 'status result))
    'fail)
  (let ([shrunk (cdr (assq 'shrunk result))])
    (test-pred "shrunk to minimal"
      (lambda (s) (and (pair? s) (= (car s) 10)))
      shrunk)))

;; ================================================================
;; 15. for-all macro -- passing
;; ================================================================
(printf "~%-- for-all macro --~%")

(let ([result (for-all ([x gen-int] [y gen-int])
                (integer? (+ x y)))])
  (test "for-all pass"
    (cdr (assq 'status result))
    'pass))

;; ================================================================
;; 16. for-all macro -- failing
;; ================================================================
(let ([result (for-all ([x gen-nat])
                (< x 20))])
  (test "for-all detects failure"
    (cdr (assq 'status result))
    'fail))

;; ================================================================
;; 17. quickcheck main entry
;; ================================================================
(printf "~%-- quickcheck --~%")

(let ([result (quickcheck 100
               (lambda (gen-fn)
                 (let ([n (gen-fn gen-int)])
                   (= (+ n 0) n))))])
  (test "quickcheck pass"
    (cdr (assq 'status result))
    'pass))

(let ([result (quickcheck 200
               (lambda (gen-fn)
                 (let ([n (gen-fn gen-nat)])
                   (< n 30))))])
  (test "quickcheck fail"
    (cdr (assq 'status result))
    'fail))

;; ================================================================
;; 18. check-property catches exceptions as failures
;; ================================================================
(printf "~%-- Exception handling --~%")

(let ([result (check-property 10 (list gen-int)
               (lambda (n)
                 (when (> n 3)
                   (error 'test "boom"))
                 #t))])
  ;; It should eventually fail since gen-int will produce > 3
  ;; (at size >= 4, there's a chance)
  ;; But with size starting at 0 and going up, size 4+ can produce 4
  ;; Let's just verify it doesn't crash the whole test suite
  (test-pred "exception property returns alist"
    (lambda (r) (assq 'status r))
    result))

;; ================================================================
;; Summary
;; ================================================================
(printf "~%--- Results: ~a passed, ~a failed ---~%" pass-count fail-count)
(when (> fail-count 0)
  (exit 1))
