#!chezscheme
;;; Tests for (std typed linear) — Linear types

(import (chezscheme) (std typed linear))

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

(printf "--- Phase 2c: Linear Types ---~%~%")

;; ========== make-linear / linear? ==========

(test "make-linear returns linear"
  (linear? (make-linear 42))
  #t)

(test "linear? non-linear"
  (linear? 42)
  #f)

(test "linear? string"
  (linear? "hello")
  #f)

(test "linear? vector"
  (linear? (vector 1 2 3))
  #f)

(test "linear? #f"
  (linear? #f)
  #f)

;; ========== linear-consumed? ==========

(test "fresh linear not consumed"
  (linear-consumed? (make-linear 10))
  #f)

(test "consumed after linear-use"
  (let ([lv (make-linear 99)])
    (linear-use lv (lambda (v) v))
    (linear-consumed? lv))
  #t)

;; ========== linear-value ==========

(test "linear-value reads payload"
  (linear-value (make-linear 'hello))
  'hello)

(test "linear-value on consumed errors"
  (guard (exn [#t (condition-message exn)])
    (let ([lv (make-linear 5)])
      (linear-use lv (lambda (v) v))
      (linear-value lv)))
  "linear value already consumed")

(test "linear-value non-linear errors"
  (guard (exn [#t (condition-message exn)])
    (linear-value 42))
  "not a linear value")

;; ========== linear-use ==========

(test "linear-use returns proc result"
  (linear-use (make-linear 21) (lambda (v) (* v 2)))
  42)

(test "linear-use with string"
  (linear-use (make-linear "world") (lambda (s) (string-append "hello " s)))
  "hello world")

(test "linear-use double consumption errors"
  (guard (exn [#t (condition-message exn)])
    (let ([lv (make-linear 5)])
      (linear-use lv (lambda (v) v))
      (linear-use lv (lambda (v) v))))
  "linear value already consumed")

(test "linear-use non-linear errors"
  (guard (exn [#t (condition-message exn)])
    (linear-use 42 (lambda (v) v)))
  "not a linear value")

;; ========== define-linear ==========

(define-linear counter 0)

(test "define-linear creates linear"
  (linear? counter)
  #t)

(test "define-linear not initially consumed"
  (linear-consumed? counter)
  #f)

(test "define-linear use"
  (linear-use counter (lambda (v) (+ v 1)))
  1)

(test "define-linear consumed after use"
  (linear-consumed? counter)
  #t)

;; ========== linear-split ==========

(test "linear-split produces n copies"
  (let ([lv (make-linear 'data)])
    (length (linear-split lv 3)))
  3)

(test "linear-split all parts are linear"
  (let* ([lv    (make-linear 10)]
         [parts (linear-split lv 2)])
    (for-all linear? parts))
  #t)

(test "linear-split original consumed"
  (let ([lv (make-linear 'orig)])
    (linear-split lv 2)
    (linear-consumed? lv))
  #t)

(test "linear-split parts carry payload"
  (let* ([lv    (make-linear 77)]
         [parts (linear-split lv 3)]
         [vals  (map (lambda (p) (linear-use p (lambda (v) v))) parts)])
    vals)
  '(77 77 77))

(test "linear-split n=1"
  (let* ([lv   (make-linear 'solo)]
         [parts (linear-split lv 1)])
    (linear-use (car parts) (lambda (v) v)))
  'solo)

(test "linear-split on consumed errors"
  (guard (exn [#t (condition-message exn)])
    (let ([lv (make-linear 5)])
      (linear-use lv (lambda (v) v))
      (linear-split lv 2)))
  "linear value already consumed")

(test "linear-split non-positive n errors"
  (guard (exn [#t (condition-message exn)])
    (linear-split (make-linear 1) 0))
  "n must be a positive integer")

;; ========== with-linear ==========

(test "with-linear basic"
  (with-linear ([a 10])
    (linear-use a (lambda (v) (* v 3))))
  30)

(test "with-linear multiple bindings"
  (with-linear ([a 3] [b 4])
    (+ (linear-use a (lambda (v) v))
       (linear-use b (lambda (v) v))))
  7)

(test "with-linear leak detection"
  (guard (exn [#t (condition-message exn)])
    (with-linear ([x 5])
      'unused))
  "linear value was not consumed")

(test "with-linear first consumed second leaked"
  (guard (exn [#t (condition-message exn)])
    (with-linear ([a 1] [b 2])
      (linear-use a (lambda (v) v))
      'done))
  "linear value was not consumed")

(test "with-linear nested"
  (with-linear ([outer 100])
    (linear-use outer
      (lambda (ov)
        (with-linear ([inner ov])
          (linear-use inner (lambda (iv) (+ iv 1)))))))
  101)

;; ========== with varying types ==========

(test "linear wraps list"
  (linear-use (make-linear '(1 2 3)) length)
  3)

(test "linear wraps procedure"
  (let ([f (make-linear (lambda (x) (* x x)))])
    (linear-use f (lambda (proc) (proc 7))))
  49)

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
