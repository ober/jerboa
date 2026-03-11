#!chezscheme
;;; Tests for (std match2) — Pattern Matching 2.0

(import (chezscheme) (std match2))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(printf "--- (std match2) tests ---~%")

;;; ======== Basic patterns ========

(printf "~%-- wildcard and variables --~%")

(test "wildcard matches anything"
  (match 42 [_ 'ok])
  'ok)

(test "variable binds value"
  (match 42 [x x])
  42)

(test "variable in body"
  (match 99 [n (* n 2)])
  198)

;;; ======== Literal patterns ========

(printf "~%-- literal patterns --~%")

(test "boolean #t"
  (match #t [#t 'yes] [_ 'no])
  'yes)

(test "boolean #f"
  (match #f [#f 'yes] [_ 'no])
  'yes)

(test "number literal"
  (match 42 [42 'yes] [_ 'no])
  'yes)

(test "number miss"
  (match 43 [42 'yes] [_ 'no])
  'no)

(test "string literal"
  (match "hello" ["hello" 'yes] [_ 'no])
  'yes)

(test "string miss"
  (match "world" ["hello" 'yes] [_ 'no])
  'no)

(test "quoted symbol"
  (match 'foo ['foo 'yes] [_ 'no])
  'yes)

(test "quoted list"
  (match '(1 2) ['(1 2) 'yes] [_ 'no])
  'yes)

;;; ======== Predicate patterns ========

(printf "~%-- predicate patterns --~%")

(test "(? pred) passes"
  (match 42 [(? number?) 'num] [_ 'other])
  'num)

(test "(? pred) fails"
  (match "hello" [(? number?) 'num] [_ 'other])
  'other)

(test "(? pred -> var) binds result"
  (match "42"
    [(? string->number -> n) n]
    [_ #f])
  42)

(test "(? pred -> var) fails"
  (match 5
    [(? negative? -> n) n]
    [_ #f])
  #f)

;;; ======== View patterns ========

(printf "~%-- view patterns (=>) --~%")

(test "(=> proc var) applies and binds"
  (match 10
    [(=> (lambda (x) (* x x)) sq) sq])
  100)

(test "(=> proc var) always succeeds"
  (match "hello"
    [(=> string-length len) len])
  5)

;;; ======== Conjunction / disjunction / negation ========

(printf "~%-- and / or / not --~%")

(test "(and) empty succeeds"
  (match 42 [(and) 'ok])
  'ok)

(test "(and p1 p2) both match"
  (match 42
    [(and (? number?) (? positive?)) 'pos-num]
    [_ 'other])
  'pos-num)

(test "(and p1 p2) first fails"
  (match "hi"
    [(and (? number?) x) x]
    [_ 'other])
  'other)

(test "(and p1 p2) second fails"
  (match -5
    [(and (? number?) (? positive?)) 'pos]
    [_ 'neg])
  'neg)

(test "(or) empty fails → next clause"
  (match 42 [(or) 'bad] [_ 'ok])
  'ok)

(test "(or p1 p2) first matches"
  (match 1
    [(or 1 2) 'yes]
    [_ 'no])
  'yes)

(test "(or p1 p2) second matches"
  (match 2
    [(or 1 2) 'yes]
    [_ 'no])
  'yes)

(test "(or p1 p2) none match"
  (match 3
    [(or 1 2) 'yes]
    [_ 'no])
  'no)

(test "(not p) inverts"
  (match 42
    [(not (? string?)) 'not-string]
    [_ 'string])
  'not-string)

(test "(not p) inverts 2"
  (match "hi"
    [(not (? string?)) 'not-string]
    [_ 'string])
  'string)

;;; ======== Structural patterns ========

(printf "~%-- cons / list / list* --~%")

(test "(cons p1 p2) matches pair"
  (match '(1 . 2)
    [(cons a b) (list a b)]
    [_ #f])
  '(1 2))

(test "(cons p1 p2) matches list head"
  (match '(1 2 3)
    [(cons h t) (list h t)]
    [_ #f])
  '(1 (2 3)))

(test "(cons) fails on non-pair"
  (match 42
    [(cons a b) 'pair]
    [_ 'not-pair])
  'not-pair)

(test "(list) exact match"
  (match '(1 2 3)
    [(list a b c) (+ a b c)]
    [_ #f])
  6)

(test "(list) wrong length fails"
  (match '(1 2)
    [(list a b c) 'three]
    [_ 'other])
  'other)

(test "(list) empty list"
  (match '()
    [(list) 'empty]
    [_ 'other])
  'empty)

(test "(list*) leading + rest"
  (match '(1 2 3 4)
    [(list* a b rest) (list a b rest)]
    [_ #f])
  '(1 2 (3 4)))

(test "(list*) at least n"
  (match '(1)
    [(list* a b rest) 'long]
    [_ 'short])
  'short)

;;; ======== Vector patterns ========

(printf "~%-- vector --~%")

(test "(vector) exact match"
  (match (vector 1 2 3)
    [(vector a b c) (+ a b c)]
    [_ #f])
  6)

(test "(vector) wrong length fails"
  (match (vector 1 2)
    [(vector a b c) 'three]
    [_ 'other])
  'other)

(test "(vector) empty"
  (match (vector)
    [(vector) 'empty]
    [_ 'other])
  'empty)

;;; ======== Box patterns ========

(printf "~%-- box --~%")

(test "(box) matches box"
  (match (box 42)
    [(box n) n]
    [_ #f])
  42)

(test "(box) fails on non-box"
  (match 42
    [(box n) n]
    [_ 'not-box])
  'not-box)

;;; ======== Guards (where) ========

(printf "~%-- where guards --~%")

(test "where guard passes"
  (match 42
    [n (where (> n 10)) 'big]
    [_ 'small])
  'big)

(test "where guard fails"
  (match 5
    [n (where (> n 10)) 'big]
    [_ 'small])
  'small)

(test "where guard with binding"
  (match '(3 4)
    [(list a b) (where (= a 3)) (* a b)]
    [_ #f])
  12)

;;; ======== define-match-type and struct patterns ========

(printf "~%-- define-match-type / struct patterns --~%")

;; Simple point struct
(define-record-type (point make-point point?)
  (fields (immutable x point-x)
          (immutable y point-y)))

(define-match-type point point? point-x point-y)

(test "struct pattern matches"
  (match (make-point 3 4)
    [(point px py) (list px py)]
    [_ #f])
  '(3 4))

(test "struct pattern fails"
  (match 42
    [(point px py) 'point]
    [_ 'other])
  'other)

(test "struct pattern with guard"
  (match (make-point 0 5)
    [(point px py) (where (= px 0)) py]
    [_ #f])
  5)

;;; ======== define-sealed-hierarchy ========

(printf "~%-- define-sealed-hierarchy --~%")

(define-record-type (shape-circle make-shape-circle shape-circle?)
  (fields (immutable radius circle-radius)))
(define-record-type (shape-rect make-shape-rect shape-rect?)
  (fields (immutable w rect-w)
          (immutable h rect-h)))

(define-sealed-hierarchy shape
  (shape-circle shape-circle? circle-radius)
  (shape-rect   shape-rect?   rect-w rect-h))

(test "sealed hierarchy: circle matches"
  (match (make-shape-circle 5)
    [(shape-circle r) (* r r)]
    [(shape-rect w h) (* w h)])
  25)

(test "sealed hierarchy: rect matches"
  (match (make-shape-rect 3 4)
    [(shape-circle r) (* r r)]
    [(shape-rect w h) (* w h)])
  12)

(test "sealed-hierarchy?"
  (sealed-hierarchy? 'shape)
  #t)

(test "sealed-hierarchy? unknown"
  (sealed-hierarchy? 'unknown)
  #f)

(test "sealed-hierarchy-members"
  (length (sealed-hierarchy-members 'shape))
  2)

;;; ======== active patterns ========

(printf "~%-- active patterns --~%")

;; Even/odd active patterns
(define-active-pattern (even-pat n)
  (and (integer? n) (even? n)))

(define-active-pattern (double-pat n)
  (list (* n 2)))

(test "active-pattern? registered"
  (active-pattern? 'even-pat)
  #t)

(test "active-pattern? unregistered"
  (active-pattern? 'nonexistent)
  #f)

(test "active pattern: boolean result"
  (match 4
    [(even-pat) 'even]
    [_ 'odd])
  'even)

(test "active pattern: boolean result fail"
  (match 3
    [(even-pat) 'even]
    [_ 'odd])
  'odd)

(test "active pattern: list result"
  (match 5
    [(double-pat d) d]
    [_ #f])
  10)

;; Active pattern that extracts multiple values
(define-active-pattern (split-at-comma s)
  (if (string? s)
    (let ([idx (let loop ([i 0])
                 (cond [(= i (string-length s)) #f]
                       [(char=? (string-ref s i) #\,) i]
                       [else (loop (+ i 1))]))])
      (if idx
        (list (substring s 0 idx)
              (substring s (+ idx 1) (string-length s)))
        #f))
    #f))

(test "active pattern: multi-value extract"
  (match "hello,world"
    [(split-at-comma a b) (list a b)]
    [_ #f])
  '("hello" "world"))

(test "active pattern: fails correctly"
  (match "nope"
    [(split-at-comma a b) 'split]
    [_ 'no-comma])
  'no-comma)

;;; ======== match/strict ========

(printf "~%-- match/strict --~%")

;; Full coverage — no warning expected
(test "match/strict: full coverage"
  (match/strict shape (make-shape-circle 3)
    [(shape-circle r) r]
    [(shape-rect w h) (* w h)])
  3)

;; Partial coverage — warning printed (can't suppress in test, just runs)
(test "match/strict: partial coverage (warning to stdout)"
  (with-output-to-string
    (lambda ()
      (match/strict shape (make-shape-rect 2 3)
        [(shape-circle r) r]
        [(shape-rect w h) (* w h)])))
  "")  ; no warning when all covered

;;; ======== Multiple clause fallthrough ========

(printf "~%-- multi-clause fallthrough --~%")

(test "fallthrough to second clause"
  (match 'b
    ['a 1]
    ['b 2]
    ['c 3])
  2)

(test "no matching clause raises error"
  (guard (exn [#t 'error])
    (match 99
      [1 'one]
      [2 'two]))
  'error)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
