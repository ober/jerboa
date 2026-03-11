#!chezscheme
;;; Tests for (std dev cont-mark-opt) -- Linear Handler Optimization

(import (chezscheme)
        (std effect)
        (std dev cont-mark-opt))

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

(printf "--- Phase 2b: Linear Handler Optimization ---~%~%")

;;; ======== count-resumes ========

(test "count-resumes none"
  (count-resumes '(+ 1 2))
  0)

(test "count-resumes one"
  (count-resumes '(resume k 42))
  1)

(test "count-resumes nested"
  (count-resumes '(begin (resume k 1) (resume k 2)))
  2)

(test "count-resumes in if"
  (count-resumes '(if c (resume k v) (resume k 0)))
  2)

(test "count-resumes in body"
  (count-resumes '(set! x 1))
  0)

;;; ======== resume-in-tail-position? ========

(test "tail-position single resume"
  (resume-in-tail-position? '((resume k v)))
  #t)

(test "tail-position non-resume last"
  (resume-in-tail-position? '((+ 1 2)))
  #f)

(test "tail-position resume not last"
  (resume-in-tail-position? '((resume k v) (display "hi")))
  #f)

(test "tail-position empty"
  (resume-in-tail-position? '())
  #f)

;;; ======== handler-clause-linear? ========

(test "handler-clause linear: one resume in tail"
  (handler-clause-linear? '(get (k) (resume k 42)))
  #t)

(test "handler-clause linear: two resumes not linear"
  (handler-clause-linear? '(choice (k) (resume k 1) (resume k 2)))
  #f)

(test "handler-clause linear: resume not in tail"
  (handler-clause-linear? '(put (v k) (resume k (void)) (display "done")))
  #f)

(test "handler-clause linear: no resume is not linear"
  (handler-clause-linear? '(log (msg k) (display msg)))
  #f)

;;; ======== linear-handler-info record ========

(test "make-linear-handler-info constructor"
  (let ([info (make-linear-handler-info 'State '((get (k)) (put (v k))))])
    (linear-handler-info? info))
  #t)

(test "linear-handler-info-name"
  (let ([info (make-linear-handler-info 'MyEffect '())])
    (linear-handler-info-name info))
  'MyEffect)

(test "linear-handler-info-ops"
  (let ([info (make-linear-handler-info 'E '(op1 op2))])
    (linear-handler-info-ops info))
  '(op1 op2))

;;; ======== optimization statistics ========

(test "initial optimization count"
  (integer? (linear-handler-optimization-count))
  #t)

(test "reset-linear-stats!"
  (begin
    (reset-linear-stats!)
    (linear-handler-optimization-count))
  0)

;;; ======== with-linear-handler (dispatches to with-handler) ========

(defeffect TestFX
  (test-op x))

(test "with-linear-handler works like with-handler"
  (with-linear-handler
    ([TestFX
      (test-op (k x) (resume k (* x 2)))])
    (TestFX test-op 21))
  42)

(defeffect CounterFX
  (inc)
  (get-val))

(test "with-linear-handler multiple ops"
  (let ([n 0])
    (with-linear-handler
      ([CounterFX
        (inc (k) (set! n (+ n 1)) (resume k (void)))
        (get-val (k) (resume k n))])
      (begin
        (CounterFX inc)
        (CounterFX inc)
        (CounterFX inc)
        (CounterFX get-val))))
  3)

;;; ======== Summary ========

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
