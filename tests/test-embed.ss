#!chezscheme
;;; Tests for (jerboa embed) -- Embeddable Runtime / Sandbox

(import (chezscheme)
        (jerboa embed))

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

(printf "--- Phase 3c: Embeddable Sandbox ---~%~%")

;;; ======== Sandbox Creation ========

(test "make-sandbox"
  (let ([sb (make-sandbox)])
    (sandbox? sb))
  #t)

(test "sandbox? false"
  (sandbox? 42)
  #f)

(test "sandbox-environment is an environment"
  (let ([sb (make-sandbox)])
    (environment? (sandbox-environment sb)))
  #t)

;;; ======== Sandbox Config ========

(test "make-sandbox-config"
  (let ([cfg (make-sandbox-config 5000 #f #t)])
    (sandbox-config? cfg))
  #t)

(test "sandbox-config? false"
  (sandbox-config? "nope")
  #f)

;;; ======== sandbox-eval ========

(test "sandbox-eval number"
  (let ([sb (make-sandbox)])
    (sandbox-eval sb '(+ 1 2)))
  3)

(test "sandbox-eval string"
  (let ([sb (make-sandbox)])
    (sandbox-eval sb '"hello"))
  "hello")

(test "sandbox-eval list"
  (let ([sb (make-sandbox)])
    (sandbox-eval sb '(list 1 2 3)))
  '(1 2 3))

(test "sandbox-eval error returns sandbox-error"
  (let* ([sb  (make-sandbox)]
         [res (sandbox-eval sb '(error "test error" 42))])
    (sandbox-error? res))
  #t)

(test "sandbox-error-message"
  (let* ([sb  (make-sandbox)]
         [res (sandbox-eval sb '(error "my message" 1 2))])
    (sandbox-error-message res))
  "my message")

(test "sandbox-error-irritants"
  (let* ([sb  (make-sandbox)]
         [res (sandbox-eval sb '(error "msg" 10 20))])
    (sandbox-error-irritants res))
  '(10 20))

;;; ======== sandbox-eval-string ========

(test "sandbox-eval-string basic"
  (let ([sb (make-sandbox)])
    (sandbox-eval-string sb "(+ 3 4)"))
  7)

(test "sandbox-eval-string multiple forms returns last"
  (let ([sb (make-sandbox)])
    (sandbox-eval-string sb "(define x 10) (* x 2)"))
  20)

(test "sandbox-eval-string error"
  (let* ([sb  (make-sandbox)]
         [res (sandbox-eval-string sb "(car '())")])
    (sandbox-error? res))
  #t)

;;; ======== sandbox-define! and sandbox-ref ========

(test "sandbox-define! and sandbox-ref"
  (let ([sb (make-sandbox)])
    (sandbox-define! sb 'myvar 99)
    (sandbox-ref sb 'myvar))
  99)

(test "sandbox-define! updates existing"
  (let ([sb (make-sandbox)])
    (sandbox-define! sb 'counter 0)
    (sandbox-define! sb 'counter 42)
    (sandbox-ref sb 'counter))
  42)

;;; ======== sandbox-call ========

(test "sandbox-call"
  (let ([sb (make-sandbox)])
    (sandbox-eval sb '(define (add a b) (+ a b)))
    (sandbox-call sb 'add 3 7))
  10)

(test "sandbox-call error returns sandbox-error"
  (let* ([sb  (make-sandbox)]
         [res (sandbox-call sb 'car)])  ;; wrong arity
    (sandbox-error? res))
  #t)

;;; ======== sandbox-reset! ========

(test "sandbox-reset! clears user definitions"
  (let ([sb (make-sandbox)])
    (sandbox-eval-string sb "(define my-secret 42)")
    (sandbox-reset! sb)
    ;; After reset, my-secret should be unbound
    (let ([res (sandbox-eval sb 'my-secret)])
      (sandbox-error? res)))
  #t)

;;; ======== sandbox-import! ========

(test "sandbox-import! chezscheme"
  (let* ([sb  (make-sandbox)]
         [res (sandbox-import! sb '(chezscheme))])
  ;; Should not return a sandbox-error
  (not (sandbox-error? res)))
  #t)

;;; ======== with-sandbox ========

(test "with-sandbox creates sandbox"
  (with-sandbox sb
    (sandbox? sb))
  #t)

(test "with-sandbox eval"
  (with-sandbox sb
    (sandbox-eval sb '(* 6 7)))
  42)

;;; Summary

(printf "~%Embeddable Sandbox: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
