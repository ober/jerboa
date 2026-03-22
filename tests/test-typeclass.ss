#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc typeclass))

(define (string-contains haystack needle)
  (let ([hlen (string-length haystack)]
        [nlen (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nlen) hlen) #f]
        [(string=? (substring haystack i (+ i nlen)) needle) i]
        [else (loop (+ i 1))]))))

(define test-count 0)
(define pass-count 0)

(define (test name thunk)
  (set! test-count (+ test-count 1))
  (guard (e [#t (display "FAIL: ") (display name) (newline)
              (display "  Error: ") (display (condition-message e)) (newline)])
    (thunk)
    (set! pass-count (+ pass-count 1))
    (display "PASS: ") (display name) (newline)))

(define (assert-equal actual expected msg)
  (unless (equal? actual expected)
    (error 'assert-equal
           (string-append msg ": expected " (format "~s" expected)
                          " got " (format "~s" actual)))))

(define (assert-true val msg)
  (unless val
    (error 'assert-true (string-append msg ": expected #t"))))

(define (assert-false val msg)
  (when val
    (error 'assert-false (string-append msg ": expected #f"))))

;; =============================================================
;; Eq typeclass tests
;; =============================================================

(test "Eq number: equal values"
  (lambda ()
    (assert-true (tc-apply 'Eq 'eq? 'number 1 1) "1 == 1")))

(test "Eq number: unequal values"
  (lambda ()
    (assert-false (tc-apply 'Eq 'eq? 'number 1 2) "1 != 2")))

(test "Eq string: equal"
  (lambda ()
    (assert-true (tc-apply 'Eq 'eq? 'string "hello" "hello") "hello == hello")))

(test "Eq string: unequal"
  (lambda ()
    (assert-false (tc-apply 'Eq 'eq? 'string "hello" "world") "hello != world")))

(test "Eq symbol: equal"
  (lambda ()
    (assert-true (tc-apply 'Eq 'eq? 'symbol 'foo 'foo) "foo == foo")))

(test "Eq symbol: unequal"
  (lambda ()
    (assert-false (tc-apply 'Eq 'eq? 'symbol 'foo 'bar) "foo != bar")))

;; =============================================================
;; Ord typeclass tests
;; =============================================================

(test "Ord number: compare less"
  (lambda ()
    (assert-equal (tc-apply 'Ord 'compare 'number 1 2) -1 "1 < 2")))

(test "Ord number: compare equal"
  (lambda ()
    (assert-equal (tc-apply 'Ord 'compare 'number 5 5) 0 "5 == 5")))

(test "Ord number: compare greater"
  (lambda ()
    (assert-equal (tc-apply 'Ord 'compare 'number 3 1) 1 "3 > 1")))

(test "Ord number: lt?"
  (lambda ()
    (assert-true (tc-apply 'Ord 'lt? 'number 1 2) "1 < 2")
    (assert-false (tc-apply 'Ord 'lt? 'number 2 1) "not 2 < 1")))

(test "Ord number: gt?"
  (lambda ()
    (assert-true (tc-apply 'Ord 'gt? 'number 5 3) "5 > 3")
    (assert-false (tc-apply 'Ord 'gt? 'number 3 5) "not 3 > 5")))

(test "Ord number: le?"
  (lambda ()
    (assert-true (tc-apply 'Ord 'le? 'number 1 2) "1 <= 2")
    (assert-true (tc-apply 'Ord 'le? 'number 2 2) "2 <= 2")
    (assert-false (tc-apply 'Ord 'le? 'number 3 2) "not 3 <= 2")))

(test "Ord number: ge?"
  (lambda ()
    (assert-true (tc-apply 'Ord 'ge? 'number 5 3) "5 >= 3")
    (assert-true (tc-apply 'Ord 'ge? 'number 3 3) "3 >= 3")
    (assert-false (tc-apply 'Ord 'ge? 'number 2 3) "not 2 >= 3")))

(test "Ord string: compare"
  (lambda ()
    (assert-equal (tc-apply 'Ord 'compare 'string "apple" "banana") -1 "apple < banana")
    (assert-equal (tc-apply 'Ord 'compare 'string "banana" "apple") 1 "banana > apple")
    (assert-equal (tc-apply 'Ord 'compare 'string "same" "same") 0 "same == same")))

(test "Ord string: lt? gt?"
  (lambda ()
    (assert-true (tc-apply 'Ord 'lt? 'string "a" "b") "a < b")
    (assert-true (tc-apply 'Ord 'gt? 'string "z" "a") "z > a")))

;; =============================================================
;; Ord inherits Eq (superclass test)
;; =============================================================

(test "Ord number inherits Eq: eq? method available"
  (lambda ()
    (assert-true (tc-apply 'Ord 'eq? 'number 42 42) "Ord has eq? from Eq")
    (assert-false (tc-apply 'Ord 'eq? 'number 42 43) "Ord eq? false")))

(test "Ord string inherits Eq: eq? method available"
  (lambda ()
    (assert-true (tc-apply 'Ord 'eq? 'string "x" "x") "Ord has eq? from Eq")))

;; =============================================================
;; Show typeclass tests
;; =============================================================

(test "Show number"
  (lambda ()
    (assert-equal (tc-apply 'Show '->string 'number 42) "42" "show 42")))

(test "Show string"
  (lambda ()
    (assert-equal (tc-apply 'Show '->string 'string "hello") "hello" "show hello")))

(test "Show symbol"
  (lambda ()
    (assert-equal (tc-apply 'Show '->string 'symbol 'foo) "foo" "show foo")))

;; =============================================================
;; typeclass-dispatch / tc-ref
;; =============================================================

(test "typeclass-dispatch returns a procedure"
  (lambda ()
    (let ([proc (typeclass-dispatch 'Eq 'number 'eq?)])
      (assert-true (procedure? proc) "is procedure")
      (assert-true (proc 1 1) "1 == 1 via dispatch"))))

(test "tc-ref is alias for typeclass-dispatch"
  (lambda ()
    (let ([proc (tc-ref 'Show 'number '->string)])
      (assert-equal (proc 99) "99" "tc-ref works"))))

;; =============================================================
;; typeclass-instance? / typeclass-instance-of?
;; =============================================================

(test "typeclass-instance? positive"
  (lambda ()
    (assert-true (typeclass-instance? 'Eq 'number) "Eq number exists")
    (assert-true (typeclass-instance? 'Ord 'string) "Ord string exists")
    (assert-true (typeclass-instance? 'Show 'symbol) "Show symbol exists")))

(test "typeclass-instance? negative"
  (lambda ()
    (assert-false (typeclass-instance? 'Eq 'list) "Eq list doesn't exist")
    (assert-false (typeclass-instance? 'Ord 'symbol) "Ord symbol doesn't exist")))

(test "typeclass-instance-of? is alias"
  (lambda ()
    (assert-true (typeclass-instance-of? 'Show 'number) "alias works")))

;; =============================================================
;; Error cases
;; =============================================================

(test "dispatch missing instance raises error"
  (lambda ()
    (guard (e [#t (assert-true (string-contains (condition-message e) "no instance")
                               "error mentions 'no instance'")])
      (typeclass-dispatch 'Eq 'list 'eq?)
      (error 'test "should have raised"))))

(test "dispatch missing method raises error"
  (lambda ()
    (guard (e [#t (assert-true (string-contains (condition-message e) "no method")
                               "error mentions 'no method'")])
      (typeclass-dispatch 'Eq 'number 'nonexistent)
      (error 'test "should have raised"))))

;; =============================================================
;; User-defined typeclass and instance
;; =============================================================

(define-typeclass (Hashable a)
  (hash-code a -> integer))

(define-instance (Hashable number)
  (hash-code (lambda (n) (modulo (abs (exact (truncate n))) 1000000007))))

(define-instance (Hashable string)
  (hash-code (lambda (s) (string-hash s))))

(test "user-defined typeclass: Hashable number"
  (lambda ()
    (let ([h (tc-apply 'Hashable 'hash-code 'number 42)])
      (assert-true (integer? h) "hash is integer")
      (assert-equal h 42 "hash of 42 is 42"))))

(test "user-defined typeclass: Hashable string"
  (lambda ()
    (let ([h (tc-apply 'Hashable 'hash-code 'string "test")])
      (assert-true (integer? h) "hash is integer")
      (assert-equal h (tc-apply 'Hashable 'hash-code 'string "test") "deterministic"))))

;; =============================================================
;; User-defined typeclass with superclass
;; =============================================================

(define-typeclass (Printable a) extends (Show a)
  (print! a -> void))

(define-instance (Printable number)
  (print! (lambda (n) (display (number->string n)))))

(test "user-defined typeclass with superclass: inherits Show"
  (lambda ()
    ;; Printable number should have ->string from Show
    (assert-equal (tc-apply 'Printable '->string 'number 7) "7"
                  "inherited ->string")))

(test "user-defined typeclass with superclass: own method"
  (lambda ()
    ;; print! should work
    (let ([proc (tc-ref 'Printable 'number 'print!)])
      (assert-true (procedure? proc) "print! is procedure"))))

;; =============================================================
;; lookup-instance returns the dictionary
;; =============================================================

(test "lookup-instance returns hashtable"
  (lambda ()
    (let ([dict (lookup-instance 'Eq 'number)])
      (assert-true (hashtable? dict) "is hashtable")
      (assert-true (procedure? (hashtable-ref dict 'eq? #f)) "eq? is procedure"))))

(test "lookup-instance returns #f for missing"
  (lambda ()
    (assert-false (lookup-instance 'Eq 'list) "no Eq for list")))

;; =============================================================
;; Summary
;; =============================================================

(newline)
(display (format "~a/~a tests passed.~n" pass-count test-count))
(unless (= pass-count test-count)
  (exit 1))
