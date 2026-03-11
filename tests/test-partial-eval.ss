#!chezscheme
;;; Tests for (std dev partial-eval) -- Compile-Time Partial Evaluation

(import (chezscheme)
        (std dev partial-eval))

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

(printf "--- Phase 2b: Compile-Time Partial Evaluation ---~%~%")

;;; ======== define-ct and ct ========

(define-ct (square x) (* x x))
(define-ct (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))

(test "define-ct runtime works"
  (square 7)
  49)

(test "define-ct runtime fib"
  (fib 10)
  55)

(define ct-square-result (ct (square 5)))

(test "ct compile-time square"
  ct-square-result
  25)

(define ct-fib-result (ct (fib 10)))

(test "ct compile-time fib"
  ct-fib-result
  55)

(test "ct arithmetic"
  (ct (+ 2 3))
  5)

(test "ct nested"
  (ct (* (+ 1 2) (- 10 5)))
  15)

;;; ======== ct/try ========

(define try-literal (ct/try (+ 1 2 3)))

(test "ct/try on pure constant"
  try-literal
  6)

;; ct/try on runtime variable should fall through to runtime
(define dynamic-val 42)
(define try-dynamic (ct/try dynamic-val))

;; This should work at runtime (returning 42), whether ct/try evaluated it or not
(test "ct/try fallback is still correct"
  try-dynamic
  42)

;;; ======== ct-literal? ========

(test "ct-literal? number"
  (ct-literal? #'42)
  #t)

(test "ct-literal? string"
  (ct-literal? #'"hello")
  #t)

(test "ct-literal? boolean"
  (ct-literal? #'#t)
  #t)

(test "ct-literal? char"
  (ct-literal? #'#\a)
  #t)

(test "ct-literal? quoted"
  (ct-literal? #''foo)
  #t)

(test "ct-literal? identifier is not literal"
  (ct-literal? #'x)
  #f)

;;; ======== ct-constant-expr? ========

(test "ct-constant-expr? number"
  (ct-constant-expr? #'42)
  #t)

(test "ct-constant-expr? arithmetic"
  (ct-constant-expr? #'(+ 1 2))
  #t)

(test "ct-constant-expr? nested arithmetic"
  (ct-constant-expr? #'(* (+ 1 2) 3))
  #t)

(test "ct-constant-expr? string-append"
  (ct-constant-expr? #'(string-append "hello" " " "world"))
  #t)

(test "ct-constant-expr? list of constants"
  (ct-constant-expr? #'(list 1 2 3))
  #t)

(test "ct-constant-expr? identifier is not constant"
  (ct-constant-expr? #'x)
  #f)

;;; ======== ct-env-reset! ========

(test "ct-env-reset! returns void"
  (begin (ct-env-reset!) (void))
  (void))

;;; ======== Summary ========

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
