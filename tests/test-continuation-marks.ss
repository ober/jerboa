#!chezscheme
;;; Tests for (std control marks) — Continuation Marks

(import (except (chezscheme) current-continuation-marks continuation-marks->list)
        (std control marks))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn)
                           (condition-message exn)
                           exn))])
       (let ([got expr])
         (if (equal? got expected)
             (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
             (begin (set! fail (+ fail 1))
                    (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define-syntax test-true
  (syntax-rules ()
    [(_ name expr)
     (test name (if expr #t #f) #t)]))

(printf "--- (std control marks) tests ---~%~%")

;;; ======== current-continuation-marks outside any mark ========

(test "no mark returns #f"
  (current-continuation-marks 'missing-key)
  #f)

;;; ======== with-continuation-mark + current-continuation-marks ========

(test "single mark lookup"
  (with-continuation-mark 'k 42
    (current-continuation-marks 'k))
  42)

(test "mark lookup different key returns #f"
  (with-continuation-mark 'k 42
    (current-continuation-marks 'other))
  #f)

(test "nested marks different keys"
  (with-continuation-mark 'a 1
    (with-continuation-mark 'b 2
      (list (current-continuation-marks 'a)
            (current-continuation-marks 'b))))
  '(1 2))

(test "inner mark shadows outer same key — innermost wins"
  (with-continuation-mark 'k 'outer
    (with-continuation-mark 'k 'inner
      (current-continuation-marks 'k)))
  'inner)

(test "mark gone after with-continuation-mark returns"
  (begin
    (with-continuation-mark 'temp 99
      (void))
    (current-continuation-marks 'temp))
  #f)

(test "mark restored after exception in body"
  (begin
    (guard (exn [#t #f])
      (with-continuation-mark 'err 'set
        (error "oops")))
    (current-continuation-marks 'err))
  #f)

;;; ======== continuation-marks->list ========

(test "marks->list empty when no mark"
  (continuation-marks->list 'absent)
  '())

(test "marks->list single mark"
  (with-continuation-mark 'x 10
    (continuation-marks->list 'x))
  '(10))

(test "marks->list multiple different keys only returns matching"
  (with-continuation-mark 'a 1
    (with-continuation-mark 'b 2
      (continuation-marks->list 'a)))
  '(1))

;;; ======== call-with-current-continuation-marks ========

(test-true "call-with-current-continuation-marks passes marks object"
  (with-continuation-mark 'p 99
    (call-with-current-continuation-marks continuation-marks?)))

(test "call-with-current-continuation-marks sees current marks"
  (with-continuation-mark 'q 'hello
    (call-with-current-continuation-marks
      (lambda (cms)
        (continuation-marks-first cms 'q #f))))
  'hello)

;;; ======== key types ========
;;; Note: Chez Scheme's with-continuation-mark uses eq? for key comparison.
;;; Symbol and fixnum keys work reliably (symbols are interned, fixnums are eq?).
;;; String literals may or may not work depending on whether the compiler
;;; interns them.

(test "symbol key"
  (with-continuation-mark 'my-key "my-value"
    (current-continuation-marks 'my-key))
  "my-value")

(test "integer key"
  (with-continuation-mark 42 'fortytwo
    (current-continuation-marks 42))
  'fortytwo)

;;; ======== value types ========

(test "boolean value"
  (with-continuation-mark 'flag #t
    (current-continuation-marks 'flag))
  #t)

(test "list value"
  (with-continuation-mark 'data '(1 2 3)
    (current-continuation-marks 'data))
  '(1 2 3))

(test "number value"
  (with-continuation-mark 'n 3.14
    (current-continuation-marks 'n))
  3.14)

;;; ======== nested scoping ========

(test "outer mark visible after inner exits"
  (with-continuation-mark 'outer 'o
    (begin
      (with-continuation-mark 'inner 'i
        (void))
      (current-continuation-marks 'outer)))
  'o)

;;; Summary

(printf "~%~a tests: ~a passed, ~a failed~%" (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
