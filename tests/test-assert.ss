#!chezscheme
;;; tests/test-assert.ss -- Tests for the assert! macro in (std test)

(import (chezscheme) (std test))

(define pass 0)
(define fail 0)

;; Helper: check if string s contains substring sub
(define (string-contains s sub)
  (let ([slen (string-length s)]
        [sublen (string-length sub)])
    (let loop ([i 0])
      (cond
        [(> (+ i sublen) slen) #f]
        [(string=? (substring s i (+ i sublen)) sub) i]
        [else (loop (+ i 1))]))))

(define-syntax verify
  (syntax-rules ()
    [(_ name expr expected)
     (let ([got expr])
       (if (equal? got expected)
         (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
         (begin (set! fail (+ fail 1))
                (printf "FAIL ~a: got ~s expected ~s~%" name got expected))))]))

(printf "--- assert! macro tests ---~%~%")

;; 1. Passing assertions should not produce failure output
(printf "~%-- Passing assertions --~%")

(test-begin!)

(assert! (= 1 1))
(verify "pass-equal" (test-result) 'OK)

(test-begin!)
(assert! (< 3 5))
(verify "pass-less-than" (test-result) 'OK)

(test-begin!)
(assert! (string=? "hello" "hello"))
(verify "pass-string-equal" (test-result) 'OK)

;; 2. Simple true expression (non-compound)
(test-begin!)
(assert! #t)
(verify "pass-simple-true" (test-result) 'OK)

;; 3. Passing assertion with sub-expressions
(test-begin!)
(let ([x 5] [y 3])
  (assert! (= (+ x y) 8)))
(verify "pass-subexpr" (test-result) 'OK)

;; 4. Failing assertions should record failure
(printf "~%-- Failing assertions (expect FAIL output) --~%")

(test-begin!)
(assert! (= 1 2))
(verify "fail-recorded" (test-result) 'FAILURE)

;; 5. Failing assertion with sub-expressions shows values
;; We capture stderr to verify the output
(test-begin!)
(let ([output (with-output-to-string
                (lambda ()
                  (parameterize ([current-error-port (current-output-port)])
                    (let ([x 5] [y 3])
                      (assert! (= (+ x 1) (* y 3)))))))])
  ;; Should mention the failing expression
  (verify "fail-shows-expr"
    (and (string-contains output "FAIL")
         (string-contains output "(+ x 1)")
         (string-contains output "(* y 3)")
         #t)
    #t)
  ;; Should show the sub-expression values
  (verify "fail-shows-value-6"
    (and (string-contains output "6") #t)
    #t)
  (verify "fail-shows-value-9"
    (and (string-contains output "9") #t)
    #t))

;; 6. Failing simple (non-compound) assertion
(test-begin!)
(assert! #f)
(verify "fail-simple-false" (test-result) 'FAILURE)

;; 7. Multiple assertions - mix of pass and fail
(test-begin!)
(assert! (= 2 2))
(assert! (= 3 4))
(verify "mixed-result" (test-result) 'FAILURE)

;; 8. Assertion with more than 2 arguments to operator
(test-begin!)
(assert! (< 1 2 3))
(verify "pass-three-args" (test-result) 'OK)

(test-begin!)
(assert! (< 1 3 2))
(verify "fail-three-args" (test-result) 'FAILURE)

;; 9. Works inside test-case
(test-begin!)
(let ([suite (test-suite "assert-suite"
               (test-case "passing assert"
                 (assert! (= 1 1)))
               (test-case "failing assert"
                 (assert! (= 1 2))))])
  (let ([ok (run-test-suite! suite)])
    (verify "suite-with-assert" ok #f)))  ;; should fail overall

;; --- Summary ---
(printf "~%--- assert! tests: ~a passed, ~a failed ---~%" pass fail)
(when (> fail 0) (exit 1))
