#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc chaperone))

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
    (error 'assert-true (string-append msg ": expected #t, got #f"))))

(define (assert-false val msg)
  (when val
    (error 'assert-false (string-append msg ": expected #f, got #t"))))

;; =========================================================
;; Procedure chaperone tests
;; =========================================================

;; Test 1: chaperone a procedure — validate args are positive
(test "chaperone-procedure: validate positive args"
  (lambda ()
    (let* ([add (lambda (a b) (+ a b))]
           [safe-add
            (chaperone-procedure add
              (lambda (a b)
                (unless (and (positive? a) (positive? b))
                  (error 'safe-add "arguments must be positive"))
                (list a b))
              #f)])
      (assert-equal (safe-add 3 4) 7 "positive args work")
      (let ([caught #f])
        (guard (e [#t (set! caught #t)])
          (safe-add -1 4))
        (assert-true caught "negative arg rejected")))))

;; Test 2: chaperone-procedure with result interceptor
(test "chaperone-procedure: result interceptor"
  (lambda ()
    (let* ([square (lambda (x) (* x x))]
           [logged-square
            (chaperone-procedure square
              #f
              (lambda (result)
                (assert-true (>= result 0) "result non-negative")
                (list result)))])
      (assert-equal (logged-square 5) 25 "5^2 = 25")
      (assert-equal (logged-square -3) 9 "(-3)^2 = 9"))))

;; Test 3: chaperone? predicate on procedure chaperone
(test "chaperone? on procedure chaperone"
  (lambda ()
    (let* ([f (lambda (x) x)]
           [cf (chaperone-procedure f #f #f)])
      (assert-true (chaperone? cf) "wrapped proc is chaperone")
      (assert-false (chaperone? f) "original proc is not chaperone")
      (assert-false (chaperone? 42) "number is not chaperone"))))

;; Test 4: chaperone-of? on procedure chaperone
(test "chaperone-of? on procedure chaperone"
  (lambda ()
    (let* ([f (lambda (x) x)]
           [cf (chaperone-procedure f #f #f)])
      (assert-true (chaperone-of? cf f) "cf is chaperone of f")
      (assert-false (chaperone-of? f cf) "f is not chaperone of cf"))))

;; Test 5: impersonate a procedure — double the result
(test "impersonate-procedure: double result"
  (lambda ()
    (let* ([add1 (lambda (x) (+ x 1))]
           [double-add1
            (impersonate-procedure add1
              #f
              (lambda (result)
                (list (* result 2))))])
      (assert-equal (double-add1 5) 12 "(5+1)*2 = 12")
      (assert-equal (double-add1 0) 2 "(0+1)*2 = 2"))))

;; Test 6: impersonate-procedure with args interceptor
(test "impersonate-procedure: transform args"
  (lambda ()
    (let* ([mul (lambda (a b) (* a b))]
           [shifted-mul
            (impersonate-procedure mul
              (lambda (a b) (list (+ a 1) (+ b 1)))
              #f)])
      (assert-equal (shifted-mul 2 3) 12 "(2+1)*(3+1) = 12"))))

;; =========================================================
;; Vector chaperone tests
;; =========================================================

;; Test 7: chaperone a vector — log accesses
(test "chaperone-vector: intercept ref"
  (lambda ()
    (let* ([v (vector 10 20 30)]
           [access-log '()]
           [cv (chaperone-vector v
                 (lambda (vec idx val)
                   (set! access-log (cons idx access-log))
                   val)
                 #f)])
      (assert-equal (chaperone-vector-ref cv 0) 10 "ref index 0")
      (assert-equal (chaperone-vector-ref cv 2) 30 "ref index 2")
      (assert-equal access-log '(2 0) "access log recorded"))))

;; Test 8: chaperone vector — intercept set!
(test "chaperone-vector: intercept set!"
  (lambda ()
    (let* ([v (vector 1 2 3)]
           [set-log '()]
           [cv (chaperone-vector v
                 #f
                 (lambda (vec idx val)
                   (set! set-log (cons (list idx val) set-log))
                   val))])
      (chaperone-vector-set! cv 1 99)
      (assert-equal (vector-ref v 1) 99 "underlying vector updated")
      (assert-equal set-log '((1 99)) "set log recorded"))))

;; Test 9: chaperone vector — set! interceptor can reject
(test "chaperone-vector: set! interceptor rejects"
  (lambda ()
    (let* ([v (vector 1 2 3)]
           [cv (chaperone-vector v
                 #f
                 (lambda (vec idx val)
                   (unless (number? val)
                     (error 'chaperone "only numbers allowed"))
                   val))])
      (chaperone-vector-set! cv 0 42)
      (assert-equal (vector-ref v 0) 42 "number accepted")
      (let ([caught #f])
        (guard (e [#t (set! caught #t)])
          (chaperone-vector-set! cv 0 "bad"))
        (assert-true caught "non-number rejected")))))

;; Test 10: chaperone? on vector chaperone
(test "chaperone? on vector chaperone"
  (lambda ()
    (let* ([v (vector 1 2)]
           [cv (chaperone-vector v #f #f)])
      (assert-true (chaperone? cv) "vector chaperone detected")
      (assert-false (chaperone? v) "plain vector not chaperone"))))

;; =========================================================
;; Hashtable chaperone tests
;; =========================================================

;; Test 11: chaperone hashtable ref
(test "chaperone-hashtable: intercept ref"
  (lambda ()
    (let* ([ht (make-hashtable equal-hash equal?)]
           [ref-log '()])
      (hashtable-set! ht 'a 1)
      (hashtable-set! ht 'b 2)
      (let ([cht (chaperone-hashtable ht
                   (lambda (h key val)
                     (set! ref-log (cons key ref-log))
                     val)
                   #f
                   #f)])
        (assert-equal (chaperone-hashtable-ref cht 'a 0) 1 "ref a")
        (assert-equal (chaperone-hashtable-ref cht 'b 0) 2 "ref b")
        (assert-equal (chaperone-hashtable-ref cht 'c 0) 0 "ref c default")
        (assert-equal ref-log '(c b a) "ref log")))))

;; Test 12: chaperone hashtable set!
(test "chaperone-hashtable: intercept set!"
  (lambda ()
    (let* ([ht (make-hashtable equal-hash equal?)]
           [cht (chaperone-hashtable ht
                  #f
                  (lambda (h key val)
                    (unless (and (number? val) (positive? val))
                      (error 'chaperone "only positive numbers"))
                    val)
                  #f)])
      (chaperone-hashtable-set! cht 'x 42)
      (assert-equal (hashtable-ref ht 'x 0) 42 "positive accepted")
      (let ([caught #f])
        (guard (e [#t (set! caught #t)])
          (chaperone-hashtable-set! cht 'x -1))
        (assert-true caught "negative rejected")))))

;; Test 13: chaperone hashtable delete!
(test "chaperone-hashtable: intercept delete!"
  (lambda ()
    (let* ([ht (make-hashtable equal-hash equal?)]
           [delete-log '()])
      (hashtable-set! ht 'a 1)
      (hashtable-set! ht 'b 2)
      (let ([cht (chaperone-hashtable ht
                   #f #f
                   (lambda (h key)
                     (set! delete-log (cons key delete-log))
                     key))])
        (chaperone-hashtable-delete! cht 'a)
        (assert-equal (hashtable-ref ht 'a 'gone) 'gone "a deleted")
        (assert-equal (hashtable-ref ht 'b 'gone) 2 "b still there")
        (assert-equal delete-log '(a) "delete log")))))

;; =========================================================
;; Composition tests
;; =========================================================

;; Test 14: chaperone of a chaperone (procedure)
(test "composing procedure chaperones"
  (lambda ()
    (let* ([f (lambda (x) (* x x))]
           ;; First layer: ensure arg is positive
           [c1 (chaperone-procedure f
                 (lambda (x)
                   (unless (positive? x)
                     (error 'c1 "must be positive"))
                   (list x))
                 #f)]
           ;; Second layer: ensure arg is < 100
           [c2 (chaperone-procedure c1
                 (lambda (x)
                   (unless (< x 100)
                     (error 'c2 "must be < 100"))
                   (list x))
                 #f)])
      (assert-equal (c2 5) 25 "valid arg passes both")
      ;; Negative: caught by inner chaperone
      (let ([caught #f])
        (guard (e [#t (set! caught #t)])
          (c2 -1))
        (assert-true caught "negative rejected"))
      ;; Too large: caught by outer chaperone
      (let ([caught #f])
        (guard (e [#t (set! caught #t)])
          (c2 200))
        (assert-true caught "too-large rejected")))))

;; Test 15: chaperone of a chaperone (vector)
(test "composing vector chaperones"
  (lambda ()
    (let* ([v (vector 10 20 30)]
           [log1 '()]
           [log2 '()]
           [cv1 (chaperone-vector v
                  (lambda (vec idx val)
                    (set! log1 (cons idx log1))
                    val)
                  #f)]
           [cv2 (chaperone-vector cv1
                  (lambda (vec idx val)
                    (set! log2 (cons idx log2))
                    val)
                  #f)])
      (assert-equal (chaperone-vector-ref cv2 1) 20 "ref through two layers")
      (assert-equal log1 '(1) "inner interceptor called")
      (assert-equal log2 '(1) "outer interceptor called"))))

;; Test 16: chaperone-of? with nested chaperones
(test "chaperone-of? with nesting"
  (lambda ()
    (let* ([v (vector 1 2 3)]
           [cv1 (chaperone-vector v #f #f)]
           [cv2 (chaperone-vector cv1 #f #f)])
      (assert-true (chaperone-of? cv1 v) "cv1 is chaperone of v")
      (assert-true (chaperone-of? cv2 cv1) "cv2 is chaperone of cv1")
      (assert-true (chaperone-of? cv2 v) "cv2 is chaperone of v (transitive)"))))

;; Test 17: chaperone-unwrap
(test "chaperone-unwrap returns base value"
  (lambda ()
    (let* ([v (vector 1 2 3)]
           [cv1 (chaperone-vector v #f #f)]
           [cv2 (chaperone-vector cv1 #f #f)])
      (assert-true (eq? (chaperone-unwrap cv2) v) "unwrap cv2 -> v")
      (assert-true (eq? (chaperone-unwrap cv1) v) "unwrap cv1 -> v")
      (assert-true (eq? (chaperone-unwrap v) v) "unwrap plain -> same"))))

;; Test 18: impersonate with both arg and result transforms
(test "impersonate-procedure: both args and result"
  (lambda ()
    (let* ([add (lambda (a b) (+ a b))]
           [weird-add
            (impersonate-procedure add
              (lambda (a b) (list (* a 10) (* b 10)))
              (lambda (result) (list (- result 1))))])
      ;; (3*10 + 4*10) - 1 = 69
      (assert-equal (weird-add 3 4) 69 "arg+result transform"))))

;; Test 19: chaperone-procedure with no interceptors (passthrough)
(test "chaperone-procedure: passthrough (no interceptors)"
  (lambda ()
    (let* ([f (lambda (x) (* x 3))]
           [cf (chaperone-procedure f #f #f)])
      (assert-equal (cf 7) 21 "passthrough works")
      (assert-true (chaperone? cf) "still recognized as chaperone"))))

;; Test 20: chaperone-vector-ref/set! on plain vector (no chaperone)
(test "chaperone-vector-ref/set! on plain vector"
  (lambda ()
    (let ([v (vector 1 2 3)])
      (assert-equal (chaperone-vector-ref v 0) 1 "ref on plain vector")
      (chaperone-vector-set! v 1 99)
      (assert-equal (vector-ref v 1) 99 "set! on plain vector"))))

;; Test 21: chaperone-hashtable ops on plain hashtable
(test "chaperone-hashtable ops on plain hashtable"
  (lambda ()
    (let ([ht (make-hashtable equal-hash equal?)])
      (chaperone-hashtable-set! ht 'x 42)
      (assert-equal (chaperone-hashtable-ref ht 'x 0) 42 "ref on plain ht")
      (chaperone-hashtable-delete! ht 'x)
      (assert-equal (chaperone-hashtable-ref ht 'x 'gone) 'gone "delete on plain ht"))))

;; =========================================================
;; Summary
;; =========================================================

(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
