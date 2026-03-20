#!chezscheme
;;; Tests for newer batch 3: parser, SRFI-43, SRFI-128, SRFI-141, translator

(import (chezscheme)
        (std parser)
        (std srfi srfi-43)
        (std srfi srfi-128)
        (std srfi srfi-141)
        (jerboa translator))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr]
           [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (printf "FAIL: ~s => ~s (expected ~s)~n" 'expr result exp))))]))

(define-syntax check-true
  (syntax-rules ()
    [(_ expr)
     (let ([result expr])
       (if result
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (printf "FAIL: ~s => ~s (expected truthy)~n" 'expr result))))]))

(define-syntax check-false
  (syntax-rules ()
    [(_ expr)
     (let ([result expr])
       (if (not result)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (printf "FAIL: ~s => ~s (expected falsy)~n" 'expr result))))]))

(printf "--- Testing newer batch 3 ---~n")

;; ========== Parser Combinators ==========
(printf "  Parser combinators...~n")

;; Literal parsing
(let ([r (parse-string (parse-literal "hello") "hello world")])
  (check-true (parse-result? r))
  (check (parse-result-value r) => "hello"))

;; Failure
(let ([r (parse-string* (parse-literal "xyz") "hello")])
  (check-true (parse-failure? r)))

;; Char parser
(let ([digit (parse-char char-numeric?)])
  (let ([r (parse-string digit "5abc")])
    (check-true (parse-result? r))
    (check (parse-result-value r) => #\5)))

;; Many
(let ([digits (parse-many (parse-char char-numeric?))])
  (let ([r (parse-string digits "123abc")])
    (check-true (parse-result? r))
    (check (parse-result-value r) => '(#\1 #\2 #\3))))

;; Many1
(let ([digits (parse-many1 (parse-char char-numeric?))])
  (let ([r (parse-string* digits "abc")])
    (check-true (parse-failure? r))))

;; Alt
(let ([p (parse-alt (parse-literal "foo") (parse-literal "bar"))])
  (check (parse-result-value (parse-string p "foo")) => "foo")
  (check (parse-result-value (parse-string p "bar")) => "bar")
  (check-true (parse-failure? (parse-string* p "baz"))))

;; Map
(let ([num (parse-map (parse-many1 (parse-char char-numeric?))
                      (lambda (chars) (string->number (list->string chars))))])
  (check (parse-result-value (parse-string num "42")) => 42))

;; Seq
(let ([p (parse-seq (parse-literal "a") (parse-literal "b"))])
  (let ([r (parse-string p "ab")])
    (check-true (parse-result? r))
    (check (parse-result-value r) => '("a" "b"))))

;; Optional
(let ([p (parse-optional (parse-literal "x") "default")])
  (check (parse-result-value (parse-string p "xyz")) => "x")
  (check (parse-result-value (parse-string p "abc")) => "default"))

;; Sep-by
(let ([p (parse-sep-by (parse-char char-numeric?)
                       (parse-literal ","))])
  (let ([r (parse-string p "1,2,3")])
    (check-true (parse-result? r))
    (check (parse-result-value r) => '(#\1 #\2 #\3))))

;; ========== SRFI-43 Vectors ==========
(printf "  SRFI-43...~n")
(check-true (vector-empty? (vector)))
(check-false (vector-empty? (vector 1)))

(check (vector-index odd? (vector 2 4 5 6)) => 2)
(check (vector-index odd? (vector 2 4 6)) => #f)
(check (vector-index-right odd? (vector 1 2 3 4)) => 2)

(check (vector-count even? (vector 1 2 3 4 5 6)) => 3)
(check-true (vector-any odd? (vector 2 3 4)))
(check-false (vector-any odd? (vector 2 4 6)))
(check-true (vector-every even? (vector 2 4 6)))
(check-false (vector-every even? (vector 2 3 6)))

(let ([v (vector 1 2 3)])
  (vector-reverse! v)
  (check v => (vector 3 2 1)))

(let ([v (vector 10 20 30)])
  (vector-swap! v 0 2)
  (check v => (vector 30 20 10)))

(check (vector-fold (lambda (i acc x) (+ acc x)) 0 (vector 1 2 3 4)) => 10)

(let ([v (vector-append (vector 1 2) (vector 3 4 5))])
  (check (vector-length v) => 5)
  (check (vector-ref v 0) => 1)
  (check (vector-ref v 4) => 5))

;; ========== SRFI-128 Comparators ==========
(printf "  SRFI-128...~n")
(let ([c (make-default-comparator)])
  (check-true (comparator? c))
  (check-true (=? c 1 1))
  (check-false (=? c 1 2))
  (check-true (<? c 1 2))
  (check-false (<? c 2 1))
  (check-true (>? c 2 1))
  (check-true (<=? c 1 1))
  (check-true (<=? c 1 2))
  (check-true (>=? c 2 2))
  (check-true (comparator-ordered? c))
  (check-true (comparator-hashable? c)))

(check-true (=? number-comparator 42 42))
(check-true (<? number-comparator 1 2))
(check-true (=? string-comparator "hello" "hello"))
(check-true (<? string-comparator "abc" "xyz"))
(check-true (=? char-comparator #\a #\a))
(check-true (<? char-comparator #\a #\b))

;; ========== SRFI-141 Integer Division ==========
(printf "  SRFI-141...~n")
(check (floor-quotient 7 3) => 2)
(check (floor-remainder 7 3) => 1)
(check (floor-quotient -7 3) => -3)
(check (floor-remainder -7 3) => 2)

(check (truncate-quotient 7 3) => 2)
(check (truncate-remainder 7 3) => 1)
(check (truncate-quotient -7 3) => -2)
(check (truncate-remainder -7 3) => -1)

(check (ceiling-quotient 7 3) => 3)
(check (ceiling-remainder 7 3) => -2)

(check (euclidean-remainder 7 3) => 1)
(check (euclidean-remainder -7 3) => 2)

;; ========== Translator ==========
(printf "  Translator...~n")

;; Import translation
(check (translate-imports '(import :std/sugar :std/iter :gerbil/gambit))
       => '(import (std sugar) (std iter) (jerboa core)))

(check (translate-imports '(import :std/text/json :std/misc/string))
       => '(import (std text json) (std misc string)))

;; Keyword translation
(check (translate-keywords "#:name") => "'name:")
(check (translate-keywords "foo #:bar baz") => "foo 'bar: baz")

;; Hash-bang translation
(check (translate-hash-bang "#!void") => "(void)")
(check (translate-hash-bang "#!eof") => "(eof-object)")

;; ========== Summary ==========
(printf "~n--- Results: ~a passed, ~a failed ---~n" pass-count fail-count)
(when (> fail-count 0) (exit 1))
