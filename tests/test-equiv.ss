#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc equiv))

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

;;; ==========================================
;;; Non-cyclic tests (should behave like equal?)
;;; ==========================================

(test "equiv? on equal numbers"
  (lambda ()
    (assert-equal (equiv? 42 42) #t "same fixnum")
    (assert-equal (equiv? 3.14 3.14) #t "same flonum")
    (assert-equal (equiv? 1 2) #f "different numbers")))

(test "equiv? on strings"
  (lambda ()
    (assert-equal (equiv? "hello" (string-copy "hello")) #t "equal strings")
    (assert-equal (equiv? "hello" "world") #f "different strings")))

(test "equiv? on symbols"
  (lambda ()
    (assert-equal (equiv? 'foo 'foo) #t "same symbol")
    (assert-equal (equiv? 'foo 'bar) #f "different symbols")))

(test "equiv? on flat lists"
  (lambda ()
    (assert-equal (equiv? '(1 2 3) '(1 2 3)) #t "equal lists")
    (assert-equal (equiv? '(1 2 3) '(1 2 4)) #f "different lists")
    (assert-equal (equiv? '() '()) #t "empty lists")))

(test "equiv? on nested lists"
  (lambda ()
    (assert-equal (equiv? '(1 (2 (3))) '(1 (2 (3)))) #t "nested equal")
    (assert-equal (equiv? '(1 (2 (3))) '(1 (2 (4)))) #f "nested different")))

(test "equiv? on vectors"
  (lambda ()
    (assert-equal (equiv? (vector 1 2 3) (vector 1 2 3)) #t "equal vectors")
    (assert-equal (equiv? (vector 1 2 3) (vector 1 2 4)) #f "different vectors")
    (assert-equal (equiv? (vector) (vector)) #t "empty vectors")))

(test "equiv? on bytevectors"
  (lambda ()
    (assert-equal (equiv? (bytevector 1 2 3) (bytevector 1 2 3)) #t "equal bv")
    (assert-equal (equiv? (bytevector 1 2 3) (bytevector 1 2 4)) #f "different bv")))

(test "equiv? on mixed types"
  (lambda ()
    (assert-equal (equiv? '(1 2) (vector 1 2)) #f "list vs vector")
    (assert-equal (equiv? 42 "42") #f "number vs string")
    (assert-equal (equiv? '() #f) #f "null vs false")))

(test "equiv? on booleans and chars"
  (lambda ()
    (assert-equal (equiv? #t #t) #t "true")
    (assert-equal (equiv? #f #f) #t "false")
    (assert-equal (equiv? #\a #\a) #t "same char")
    (assert-equal (equiv? #\a #\b) #f "different char")))

;;; ==========================================
;;; Cyclic pair tests
;;; ==========================================

(test "self-referential pair: (equiv? x x)"
  (lambda ()
    (let ([x (cons 1 2)])
      (set-cdr! x x)
      (assert-equal (equiv? x x) #t "self-ref eq"))))

(test "two different cyclic lists with same structure"
  (lambda ()
    ;; x = (1 1 1 1 ...) cyclic
    ;; y = (1 1 1 1 ...) cyclic
    (let ([x (cons 1 '())]
          [y (cons 1 '())])
      (set-cdr! x x)
      (set-cdr! y y)
      (assert-equal (equiv? x y) #t "same-structure cyclic lists"))))

(test "different cyclic lists are not equiv"
  (lambda ()
    (let ([x (cons 1 '())]
          [y (cons 2 '())])
      (set-cdr! x x)
      (set-cdr! y y)
      (assert-equal (equiv? x y) #f "different element in cycle"))))

(test "cyclic list vs non-cyclic"
  (lambda ()
    ;; x = (1 . x)  cyclic
    ;; y = (1 . 1)  not cyclic
    (let ([x (cons 1 '())])
      (set-cdr! x x)
      (assert-equal (equiv? x '(1)) #f "cyclic vs finite"))))

(test "two-element cyclic lists"
  (lambda ()
    ;; x = (1 2 1 2 1 2 ...)
    ;; y = (1 2 1 2 1 2 ...)
    (let ([x1 (cons 1 '())]
          [x2 (cons 2 '())]
          [y1 (cons 1 '())]
          [y2 (cons 2 '())])
      (set-cdr! x1 x2)
      (set-cdr! x2 x1)
      (set-cdr! y1 y2)
      (set-cdr! y2 y1)
      (assert-equal (equiv? x1 y1) #t "two-element cyclic same structure"))))

(test "mutual cyclic pair reference"
  (lambda ()
    ;; a = (a . a) -- both car and cdr point to self
    (let ([a (cons '() '())])
      (set-car! a a)
      (set-cdr! a a)
      (assert-equal (equiv? a a) #t "self-referencing car and cdr"))))

(test "two mutually self-referencing pairs equiv"
  (lambda ()
    (let ([a (cons '() '())]
          [b (cons '() '())])
      (set-car! a a)
      (set-cdr! a a)
      (set-car! b b)
      (set-cdr! b b)
      (assert-equal (equiv? a b) #t "both car+cdr self-ref"))))

;;; ==========================================
;;; Cyclic vector tests
;;; ==========================================

(test "self-referential vector"
  (lambda ()
    (let ([v (vector 1 2 #f)])
      (vector-set! v 2 v)
      (assert-equal (equiv? v v) #t "self-ref vector eq"))))

(test "two cyclic vectors with same structure"
  (lambda ()
    (let ([v1 (vector 1 2 #f)]
          [v2 (vector 1 2 #f)])
      (vector-set! v1 2 v1)
      (vector-set! v2 2 v2)
      (assert-equal (equiv? v1 v2) #t "same-structure cyclic vectors"))))

(test "cyclic vectors with different elements"
  (lambda ()
    (let ([v1 (vector 1 2 #f)]
          [v2 (vector 1 3 #f)])
      (vector-set! v1 2 v1)
      (vector-set! v2 2 v2)
      (assert-equal (equiv? v1 v2) #f "different elements in cyclic vectors"))))

;;; ==========================================
;;; Mixed cyclic/non-cyclic tests
;;; ==========================================

(test "list containing cyclic vector"
  (lambda ()
    (let ([v1 (vector 1 #f)]
          [v2 (vector 1 #f)])
      (vector-set! v1 1 v1)
      (vector-set! v2 1 v2)
      (assert-equal (equiv? (list 'a v1 'b) (list 'a v2 'b)) #t
                    "list with cyclic vector inside"))))

(test "vector containing cyclic list"
  (lambda ()
    (let ([x (cons 1 '())]
          [y (cons 1 '())])
      (set-cdr! x x)
      (set-cdr! y y)
      (assert-equal (equiv? (vector 'a x) (vector 'a y)) #t
                    "vector with cyclic list inside"))))

(test "deeply nested non-cyclic structure"
  (lambda ()
    (let ([a (list 1 (vector 2 (list 3 4)) "five")]
          [b (list 1 (vector 2 (list 3 4)) "five")])
      (assert-equal (equiv? a b) #t "deep non-cyclic"))))

(test "box with cyclic content"
  (lambda ()
    (let ([b1 (box '())]
          [b2 (box '())])
      (let ([x (cons 1 '())]
            [y (cons 1 '())])
        (set-cdr! x x)
        (set-cdr! y y)
        (set-box! b1 x)
        (set-box! b2 y)
        (assert-equal (equiv? b1 b2) #t "boxes with cyclic lists")))))

;;; ==========================================
;;; equiv-hash tests
;;; ==========================================

(test "equiv-hash on non-cyclic data"
  (lambda ()
    ;; Same structure should produce same hash
    (assert-equal (equiv-hash '(1 2 3)) (equiv-hash '(1 2 3)) "list hash eq")
    (assert-equal (equiv-hash "hello") (equiv-hash "hello") "string hash eq")
    (assert-equal (equiv-hash 42) (equiv-hash 42) "number hash eq")))

(test "equiv-hash terminates on cyclic pair"
  (lambda ()
    (let ([x (cons 1 '())])
      (set-cdr! x x)
      ;; Just verify it terminates and returns a fixnum
      (assert-equal (fixnum? (equiv-hash x)) #t "cyclic hash is fixnum"))))

(test "equiv-hash terminates on cyclic vector"
  (lambda ()
    (let ([v (vector 1 #f)])
      (vector-set! v 1 v)
      (assert-equal (fixnum? (equiv-hash v)) #t "cyclic vector hash is fixnum"))))

(test "equiv-hash same for equiv structures"
  (lambda ()
    (let ([x (cons 1 '())]
          [y (cons 1 '())])
      (set-cdr! x x)
      (set-cdr! y y)
      (assert-equal (equiv-hash x) (equiv-hash y) "cyclic list hash equal"))))

;;; ==========================================
;;; Summary
;;; ==========================================

(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
