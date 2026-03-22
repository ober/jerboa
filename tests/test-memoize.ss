#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc memoize))

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

;; Test 1: basic memoize
(test "memoize caches results"
  (lambda ()
    (let* ([call-count 0]
           [f (memoize (lambda (x) (set! call-count (+ call-count 1)) (* x x)))])
      (assert-equal (f 5) 25 "first call")
      (assert-equal (f 5) 25 "second call (cached)")
      (assert-equal call-count 1 "called only once"))))

;; Test 2: memoize with multiple args
(test "memoize with multiple arguments"
  (lambda ()
    (let* ([count 0]
           [f (memoize (lambda (x y) (set! count (+ count 1)) (+ x y)))])
      (assert-equal (f 3 4) 7 "3+4")
      (assert-equal (f 3 4) 7 "cached")
      (assert-equal (f 4 3) 7 "different args")
      (assert-equal count 2 "called twice for different args"))))

;; Test 3: define-memoized with Fibonacci
(test "define-memoized fibonacci"
  (lambda ()
    (define-memoized (fib n)
      (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
    (assert-equal (fib 0) 0 "fib(0)")
    (assert-equal (fib 1) 1 "fib(1)")
    (assert-equal (fib 10) 55 "fib(10)")
    (assert-equal (fib 30) 832040 "fib(30)")))

;; Test 4: LRU eviction
(test "memoize/lru evicts old entries"
  (lambda ()
    (let* ([count 0]
           [f (memoize/lru (lambda (x) (set! count (+ count 1)) (* x x)) 3)])
      (f 1) (f 2) (f 3)  ;; fill cache
      (assert-equal count 3 "3 calls")
      (f 1)  ;; cached
      (assert-equal count 3 "still 3")
      (f 4)  ;; evicts oldest (2)
      (assert-equal count 4 "4 calls")
      (f 2)  ;; was evicted, recomputed
      (assert-equal count 5 "5 calls (2 recomputed)"))))

;; Test 5: memoize with case-lambda max-size
(test "memoize with max-size parameter"
  (lambda ()
    (let* ([count 0]
           [f (memoize (lambda (x) (set! count (+ count 1)) x) 2)])
      (f 1) (f 2) (f 3)
      (f 1)  ;; may have been evicted
      (assert-equal (>= count 3) #t "at least 3 calls"))))

(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
