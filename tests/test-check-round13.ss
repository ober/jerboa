;; Round 13 — test.check Clojure-flavor API surface
(import (jerboa prelude))
(import (std test check))

(def test-count 0)
(def pass-count 0)

(defrule (test name body ...)
  (begin
    (set! test-count (+ test-count 1))
    (guard (exn [#t
      (displayln (str "FAIL: " name))
      (displayln (str "  Error: " (if (message-condition? exn)
                                    (condition-message exn) exn)))])
      body ...
      (set! pass-count (+ pass-count 1))
      (displayln (str "PASS: " name)))))

(defrule (assert-true val msg)
  (unless val (error 'assert msg)))

(defrule (assert-equal got expected msg)
  (unless (equal? got expected)
    (error 'assert msg (list 'got: got 'expected: expected))))

;; ---- combinator aliases ----

(test "gen/return is constant"
  (let ([s (gen/sample (gen/return 42) 5)])
    (assert-equal s '(42 42 42 42 42) "all 42")))

(test "gen/fmap transforms"
  (let ([s (gen/sample (gen/fmap (lambda (n) (* n 10)) gen/nat) 10)])
    (assert-true (every (lambda (n) (= 0 (modulo n 10))) s) "all mult of 10")))

(test "gen/bind sequences"
  (let* ([g (gen/bind gen/nat
              (lambda (n) (gen/return (+ n 100))))]
         [s (gen/sample g 5)])
    (assert-true (every (lambda (n) (>= n 100)) s) "all >= 100")))

(test "gen/choose range"
  (let ([s (gen/sample (gen/choose 1 5) 30)])
    (assert-true (every (lambda (n) (and (>= n 1) (<= n 5))) s) "in 1..5")))

(test "gen/elements picks"
  (let ([s (gen/sample (gen/elements '(red green blue)) 30)])
    (assert-true (every (lambda (x) (memq x '(red green blue))) s) "from set")))

(test "gen/one-of picks generator"
  (let ([s (gen/sample (gen/one-of (list (gen/return 'a)
                                         (gen/return 'b))) 30)])
    (assert-true (every (lambda (x) (memq x '(a b))) s) "all a or b")))

(test "gen/such-that filters"
  (let ([s (gen/sample (gen/such-that even? gen/int) 20)])
    (assert-true (every even? s) "all even")))

(test "gen/frequency weighted choice"
  (let ([s (gen/sample
             (gen/frequency (list (cons 9 (gen/return 'common))
                                  (cons 1 (gen/return 'rare))))
             100)])
    (assert-true (any (lambda (x) (eq? x 'common)) s) "has common")
    (assert-true (every (lambda (x) (memq x '(common rare))) s) "all valid")))

(test "gen/tuple shape"
  (let ([s (gen/sample (gen/tuple gen/nat gen/boolean) 5)])
    (assert-true (every (lambda (t) (= 2 (length t))) s) "all length 2")
    (assert-true (every (lambda (t) (integer? (car t))) s) "first is int")
    (assert-true (every (lambda (t) (boolean? (cadr t))) s) "second is bool")))

;; ---- numeric built-ins ----

(test "gen/boolean is bool"
  (let ([s (gen/sample gen/boolean 30)])
    (assert-true (every boolean? s) "all booleans")))

(test "gen/byte in 0..255"
  (let ([s (gen/sample gen/byte 30)])
    (assert-true (every (lambda (n) (and (>= n 0) (<= n 255))) s) "in byte range")))

(test "gen/int signed"
  (let ([s (gen/sample gen/int 30)])
    (assert-true (every integer? s) "all ints")))

(test "gen/nat non-negative"
  (let ([s (gen/sample gen/nat 30)])
    (assert-true (every (lambda (n) (>= n 0)) s) "all >= 0")))

(test "gen/pos-int positive"
  (let ([s (gen/sample gen/pos-int 30)])
    (assert-true (every positive? s) "all positive")))

(test "gen/neg-int negative"
  (let ([s (gen/sample gen/neg-int 30)])
    (assert-true (every negative? s) "all negative")))

(test "gen/large-integer scales"
  (let ([s (gen/sample gen/large-integer 30)])
    (assert-true (every integer? s) "all ints")))

;; ---- char + string ----

(test "gen/char produces chars"
  (let ([s (gen/sample gen/char 10)])
    (assert-true (every char? s) "all chars")))

(test "gen/char-alphanumeric is alnum"
  (let ([s (gen/sample gen/char-alphanumeric 30)])
    (assert-true (every char? s) "all chars")
    (assert-true (every (lambda (c)
                          (or (char-alphabetic? c)
                              (char-numeric? c)))
                        s)
                 "all alphanumeric")))

(test "gen/string-alphanumeric all alnum"
  (let ([s (gen/sample gen/string-alphanumeric 10)])
    (assert-true (every string? s) "all strings")
    (assert-true (every (lambda (str)
                          (every (lambda (c)
                                   (or (char-alphabetic? c)
                                       (char-numeric? c)))
                                 (string->list str)))
                        s)
                 "all alphanumeric")))

(test "gen/string-ascii printable"
  (let ([s (gen/sample gen/string-ascii 10)])
    (assert-true (every string? s) "all strings")))

(test "gen/keyword starts with colon"
  (let ([s (gen/sample gen/keyword 10)])
    (assert-true (every symbol? s) "all symbols")
    (assert-true (every (lambda (k)
                          (char=? #\: (string-ref (symbol->string k) 0)))
                        s)
                 "all start :")))

(test "gen/uuid shape"
  (let ([s (gen/sample gen/uuid 10)])
    (assert-true (every string? s) "all strings")
    (assert-true (every (lambda (u) (= 36 (string-length u))) s) "all 36 chars")
    (assert-true (every (lambda (u)
                          (and (char=? (string-ref u 8) #\-)
                               (char=? (string-ref u 13) #\-)
                               (char=? (string-ref u 14) #\4)
                               (char=? (string-ref u 18) #\-)
                               (char=? (string-ref u 23) #\-)))
                        s)
                 "uuid v4 dashes + version")))

;; ---- collections ----

(test "gen/list-of"
  (let ([s (gen/sample (gen/list-of gen/nat) 10)])
    (assert-true (every list? s) "all lists")))

(test "gen/vector-of"
  (let ([s (gen/sample (gen/vector-of gen/boolean) 10)])
    (assert-true (every vector? s) "all vectors")))

(test "gen/hash-set-of has unique elements"
  (let ([s (gen/sample (gen/hash-set-of (gen/choose 0 5)) 10)])
    (assert-true (every hashtable? s) "all hashtables")))

(test "gen/hash-map-of"
  (let ([s (gen/sample (gen/hash-map-of gen/nat gen/boolean) 5)])
    (assert-true (every hashtable? s) "all hashtables")))

;; ---- prop/for-all + quick-check ----

(test "quick-check passing returns ok map"
  (let* ([prop (prop/for-all ([x gen/int] [y gen/int])
                 (= (+ x y) (+ y x)))]
         [r (quick-check 50 prop)])
    (assert-equal (hash-ref r 'result) #t "result #t")
    (assert-equal (hash-ref r 'pass?) #t "pass? #t")
    (assert-equal (hash-ref r 'num-tests) 50 "50 trials")))

(test "quick-check failing returns shrunk map"
  (let* ([prop (prop/for-all ([x (gen/choose 0 200)])
                 (< x 10))]
         [r (quick-check 100 prop)])
    (assert-equal (hash-ref r 'result) #f "result #f")
    (assert-equal (hash-ref r 'pass?) #f "pass? #f")
    (assert-true (pair? (hash-ref r 'fail)) "fail is list")
    (assert-true (pair? (hash-ref r 'shrunk)) "shrunk present")))

;; ---- defspec ----

(defspec spec-add-commutative 30
  (prop/for-all ([x gen/int] [y gen/int])
    (= (+ x y) (+ y x))))

(test "defspec runs and returns ok"
  (let ([r (spec-add-commutative)])
    (assert-equal (hash-ref r 'result) #t "ok")))

;; ---- shrinking convergence ----

(test "shrinking on broken sort property"
  (let* ([prop (prop/for-all ([xs (gen/list-of gen/int)])
                 (equal? xs (list-sort < xs)))]
         [r (quick-check 100 prop)])
    (assert-equal (hash-ref r 'result) #f "should fail")
    (let ([shrunk (hash-ref r 'shrunk)])
      (let ([smallest (cdr (assq 'smallest shrunk))])
        ;; smallest is the list of generator values: (xs)
        (assert-true (pair? smallest) "smallest is list of inputs")))))

;; =========================================================================
;; Summary
;; =========================================================================
(newline)
(displayln (str "========================================="))
(displayln (str "Round 13 results: " pass-count "/" test-count " passed"))
(displayln (str "========================================="))
(when (< pass-count test-count)
  (exit 1))
