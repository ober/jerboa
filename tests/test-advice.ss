#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc advice))

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

;; Test 1: make-advisable preserves behavior
(test "make-advisable preserves original behavior"
  (lambda ()
    (let ([f (make-advisable +)])
      (assert-equal (f 2 3) 5 "2+3")
      (assert-equal (f 1 2 3) 6 "1+2+3"))))

;; Test 2: advised? on fresh advisable
(test "advised? is #f on fresh advisable"
  (lambda ()
    (let ([f (make-advisable +)])
      (assert-equal (advised? f) #f "no advice yet"))))

;; Test 3: advised? on non-advisable
(test "advised? is #f on non-advisable procedure"
  (lambda ()
    (assert-equal (advised? +) #f "plain procedure")))

;; Test 4: advise-before runs hook with arguments
(test "advise-before receives arguments"
  (lambda ()
    (let ([log '()]
          [f (make-advisable +)])
      (advise-before f (lambda args (set! log (cons args log))))
      (assert-equal (f 10 20) 30 "result unchanged")
      (assert-equal log '((10 20)) "before hook received args"))))

;; Test 5: advise-after receives result
(test "advise-after receives result"
  (lambda ()
    (let ([log '()]
          [f (make-advisable *)])
      (advise-after f (lambda (result) (set! log (cons result log))))
      (assert-equal (f 3 4) 12 "result correct")
      (assert-equal log '(12) "after hook received result"))))

;; Test 6: advised? is #t after adding advice
(test "advised? is #t after advise-before"
  (lambda ()
    (let ([f (make-advisable +)])
      (advise-before f (lambda args (void)))
      (assert-equal (advised? f) #t "has advice"))))

;; Test 7: unadvise removes all advice
(test "unadvise removes all advice"
  (lambda ()
    (let ([call-count 0]
          [f (make-advisable +)])
      (advise-before f (lambda args (set! call-count (+ call-count 1))))
      (f 1 2)
      (assert-equal call-count 1 "before hook ran")
      (unadvise f)
      (assert-equal (advised? f) #f "no longer advised")
      (f 3 4)
      (assert-equal call-count 1 "before hook no longer runs"))))

;; Test 8: multiple before hooks stack (run in order added)
(test "multiple before hooks run in order"
  (lambda ()
    (let ([log '()]
          [f (make-advisable +)])
      (advise-before f (lambda args (set! log (append log '(first)))))
      (advise-before f (lambda args (set! log (append log '(second)))))
      (f 1 2)
      (assert-equal log '(first second) "before hooks in order"))))

;; Test 9: multiple after hooks stack (run in order added)
(test "multiple after hooks run in order"
  (lambda ()
    (let ([log '()]
          [f (make-advisable +)])
      (advise-after f (lambda (r) (set! log (append log '(first)))))
      (advise-after f (lambda (r) (set! log (append log '(second)))))
      (f 1 2)
      (assert-equal log '(first second) "after hooks in order"))))

;; Test 10: advise-around wraps the function
(test "advise-around wraps the function"
  (lambda ()
    (let ([f (make-advisable +)])
      ;; Around that doubles the result
      (advise-around f (lambda (next . args)
                         (* 2 (apply next args))))
      (assert-equal (f 3 4) 14 "result doubled: 2*(3+4)=14"))))

;; Test 11: multiple around advice composes (last added is outermost)
(test "multiple around advice composes correctly"
  (lambda ()
    (let ([f (make-advisable +)])
      ;; First around: add 10 to result
      (advise-around f (lambda (next . args)
                         (+ 10 (apply next args))))
      ;; Second around (outermost): multiply result by 3
      (advise-around f (lambda (next . args)
                         (* 3 (apply next args))))
      ;; Execution: outermost calls next -> inner calls next -> original
      ;; original: 1+2=3, inner: 3+10=13, outer: 13*3=39
      (assert-equal (f 1 2) 39 "composed around advice"))))

;; Test 12: before + after + around all together
(test "before, after, and around advice compose"
  (lambda ()
    (let ([log '()]
          [f (make-advisable +)])
      (advise-before f (lambda args (set! log (append log '(before)))))
      (advise-after f (lambda (r) (set! log (append log (list (list 'after r))))))
      (advise-around f (lambda (next . args)
                         (set! log (append log '(around-enter)))
                         (let ([r (apply next args)])
                           (set! log (append log '(around-exit)))
                           (+ r 100))))
      (let ([result (f 5 6)])
        ;; before runs first, then around (which calls original), then after
        ;; around modifies result: 5+6=11, +100=111
        ;; after sees final result: 111
        (assert-equal result 111 "result is 111")
        (assert-equal log '(before around-enter around-exit (after 111))
                      "hooks run in correct order")))))

;; Test 13: define-advisable syntax
(test "define-advisable creates advisable function"
  (lambda ()
    (define-advisable (double x) (* x 2))
    (assert-equal (double 5) 10 "basic call")
    (assert-equal (advised? double) #f "no advice yet")
    (advise-before double (lambda (x) (void)))
    (assert-equal (advised? double) #t "now advised")
    (assert-equal (double 7) 14 "still works with advice")
    (unadvise double)
    (assert-equal (double 3) 6 "works after unadvise")))

;; Test 14: around advice can short-circuit
(test "around advice can short-circuit without calling next"
  (lambda ()
    (let ([f (make-advisable +)])
      (advise-around f (lambda (next . args)
                         42))  ;; never calls next
      (assert-equal (f 1 2) 42 "short-circuited to 42"))))

;; Test 15: around advice can modify arguments
(test "around advice can modify arguments"
  (lambda ()
    (let ([f (make-advisable +)])
      (advise-around f (lambda (next . args)
                         ;; Double all arguments before passing
                         (apply next (map (lambda (x) (* 2 x)) args))))
      (assert-equal (f 3 4) 14 "(3*2)+(4*2)=14"))))

;; Test 16: unadvise then re-advise
(test "unadvise then re-advise works"
  (lambda ()
    (let ([count 0]
          [f (make-advisable +)])
      (advise-before f (lambda args (set! count (+ count 1))))
      (f 1 2)
      (assert-equal count 1 "first advice")
      (unadvise f)
      (f 1 2)
      (assert-equal count 1 "unadvised")
      (advise-after f (lambda (r) (set! count (+ count 10))))
      (f 1 2)
      (assert-equal count 11 "re-advised with after"))))

;; Test 17: advise-around as middleware pattern (logging)
(test "advise-around as logging middleware"
  (lambda ()
    (let ([log '()]
          [f (make-advisable (lambda (x) (* x x)))])
      (advise-around f
        (lambda (next . args)
          (set! log (append log (list (cons 'call args))))
          (let ([r (apply next args)])
            (set! log (append log (list (list 'return r))))
            r)))
      (assert-equal (f 5) 25 "result correct")
      (assert-equal log '((call 5) (return 25)) "log correct"))))

;; Test 18: error in advised function propagates
(test "errors propagate through advice"
  (lambda ()
    (let ([before-ran #f]
          [f (make-advisable (lambda (x) (error 'test "boom")))])
      (advise-before f (lambda (x) (set! before-ran #t)))
      (assert-equal
       (guard (e [#t (condition-message e)])
         (f 1))
       "boom"
       "error propagated")
      (assert-equal before-ran #t "before hook still ran"))))

;; Test 19: zero-argument function
(test "zero-argument advisable function"
  (lambda ()
    (let ([count 0])
      (define-advisable (get-value) 42)
      (advise-before get-value (lambda () (set! count (+ count 1))))
      (assert-equal (get-value) 42 "returns 42")
      (assert-equal count 1 "before ran"))))

;; Test 20: advise-before errors on non-advisable
(test "advise-before errors on non-advisable"
  (lambda ()
    (assert-equal
     (guard (e [#t 'got-error])
       (advise-before + (lambda args (void))))
     'got-error
     "error on non-advisable")))

(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
