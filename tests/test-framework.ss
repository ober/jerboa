#!chezscheme
;;; tests/test-framework.ss -- Tests for (std test framework)

(import (chezscheme) (std test framework))

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

(printf "--- Phase 2e: Test Framework ---~%~%")

;; ---- 1. Basic test-equal passes ----
(define suite-results-list '())

(define-test-suite basic-suite
  (test-equal "1+1=2"    (+ 1 1) 2)
  (test-equal "string"   "hello" "hello")
  (test-true  "truthy"   (> 5 3))
  (test-false "false"    (= 1 2))
  (test-not-equal "neq" 1 2))

(let ([r (run-suite basic-suite)])
  (test "suite-passed"  (suite-passed r) 5)
  (test "suite-failed"  (suite-failed r) 0)
  (test "suite-name"    (suite-name r)   "basic-suite"))

;; ---- 2. Failing test records failure ----
(define-test-suite failing-suite
  (test-equal "will-fail" (+ 1 1) 99))

(let ([r (run-suite failing-suite)])
  (test "failing-suite-failed" (suite-failed r) 1)
  (test "failing-suite-passed" (suite-passed r) 0))

;; ---- 3. test-error catches exceptions ----
(define-test-suite error-suite
  (test-error "divide-by-zero" (/ 1 0)))

(let ([r (run-suite error-suite)])
  (test "error-suite-passed" (suite-passed r) 1))

;; ---- 4. Property testing ----
(define-test-suite property-suite
  (check-property "addition-commutative"
    (prop-for-all ([a arbitrary-integer] [b arbitrary-integer])
      (= (+ a b) (+ b a))))
  (check-property "list-length-nonneg"
    (prop-for-all ([lst (lambda () (arbitrary-list arbitrary-integer))])
      (>= (length lst) 0))))

(let ([r (run-suite property-suite)])
  (test "property-passed" (suite-passed r) 2))

;; ---- 5. arbitrary generators produce right types ----
(test "arb-integer-type"  (integer? (arbitrary-integer))  #t)
(test "arb-string-type"   (string?  (arbitrary-string))   #t)
(test "arb-boolean-type"  (boolean? (arbitrary-boolean))  #t)
(test "arb-list-type"     (list?    (arbitrary-list arbitrary-integer)) #t)

;; ---- 6. run-all-suites returns list ----
(define-test-suite another-suite
  (test-equal "x" 42 42))

(let ([all (*test-suites*)])
  (test "registered-suites-count-ge-4" (>= (length all) 4) #t))

;; ---- 7. with-test-output redirects output ----
(define-test-suite redirect-suite
  (test-equal "r1" 1 1))
(define captured
  (with-test-output (open-output-string)
    (run-suite redirect-suite)
    'done))
(test "with-test-output" captured 'done)

;; ---- 8. failing property reports counterexample ----
;; (This test checks that a false property is detected)
(define-test-suite detect-false-suite
  (check-property "always-false"
    (prop-for-all ([a arbitrary-integer])
      (> a 1000))))

(let ([r (run-suite detect-false-suite)])
  (test "false-property-detected" (suite-failed r) 1))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
