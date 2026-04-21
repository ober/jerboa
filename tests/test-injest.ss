#!chezscheme
;;; Tests for (std injest) — smart threading macros with auto-fusion.

(import (except (chezscheme) =>) (std injest) (std transducer))

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
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(printf "--- (std injest) tests ---~%")

;;;; =>  : identity / single step

(test "=> identity"
  (=> '(1 2 3))
  '(1 2 3))

(test "=> single recognised step (map)"
  (=> '(1 2 3) (map (lambda (x) (* x 2))))
  '(2 4 6))

(test "=> single recognised step (filter)"
  (=> '(1 2 3 4 5) (filter even?))
  '(2 4))

(test "=> single unrecognised step"
  (=> '(1 2 3) reverse)
  '(3 2 1))

(test "=> non-recognised with args"
  (=> '(1 2 3 4) (append '(0)))
  '(0 1 2 3 4))

;;;; =>  : fused runs

(test "=> fused map+filter"
  (=> '(1 2 3 4 5)
      (map (lambda (x) (* x x)))
      (filter even?))
  '(4 16))

(test "=> fused map+filter+take"
  (=> '(1 2 3 4 5 6 7 8 9 10)
      (map (lambda (x) (+ x 1)))
      (filter odd?)
      (take 3))
  '(3 5 7))

(test "=> filter+remove"
  (=> '(1 2 3 4 5 6)
      (filter (lambda (x) (> x 1)))
      (remove (lambda (x) (= x 4))))
  '(2 3 5 6))

(test "=> take-while+drop-while"
  (=> '(1 2 3 10 20 3 4 5)
      (take-while (lambda (x) (< x 15)))
      (drop-while (lambda (x) (< x 5))))
  '(10))

(test "=> mapcat flattens"
  (=> '(1 2 3)
      (mapcat (lambda (x) (list x x)))
      (take 4))
  '(1 1 2 2))

;;;; =>  : fused run followed by non-recognised step

(test "=> fused run then reverse"
  (=> '(1 2 3 4 5)
      (map (lambda (x) (* x 10)))
      (filter (lambda (x) (> x 20)))
      reverse)
  '(50 40 30))

(test "=> non-recognised then fused run"
  (=> '((3 4) (1 2) (5 6))
      reverse
      (mapcat (lambda (p) p))
      (filter odd?))
  '(5 1 3))

(test "=> two fused runs split by plain step"
  (=> '(1 2 3 4 5)
      (map (lambda (x) (* x x)))   ;; run 1: fused
      (filter (lambda (x) (> x 1)))
      reverse                       ;; plain
      (map (lambda (x) (+ x 100)))  ;; run 2: single native
      )
  '(125 116 109 104))

;;;; =>  : vector / string inputs (transducer supports them)

(test "=> over vector, fused"
  (=> (vector 1 2 3 4 5)
      (map (lambda (x) (* x 3)))
      (filter (lambda (x) (> x 6))))
  '(9 12 15))

;;;; =>  : argless recognised forms

(test "=> deduplicate consecutive"
  (=> '(1 1 2 2 2 3 1 1)
      (dedupe)
      (map (lambda (x) (* x 10))))
  '(10 20 30 10))

;;;; x>>  : basic pipelines

(test "x>> single step"
  (x>> '(1 2 3) (map (lambda (x) (+ x 1))))
  '(2 3 4))

(test "x>> fused 3-step"
  (x>> '(1 2 3 4 5 6 7 8)
       (filter even?)
       (map (lambda (x) (* x x)))
       (take 2))
  '(4 16))

(test "x>> mapcat+take"
  (x>> '(1 2 3 4)
       (mapcat (lambda (x) (list x (- x))))
       (take 5))
  '(1 -1 2 -2 3))

(test "x>> filter-map"
  (x>> '(1 2 3 4 5)
       (filter-map (lambda (x) (and (even? x) (* x 10)))))
  '(20 40))

;;;; Edge case: empty collection

(test "=> empty list fused"
  (=> '()
      (map (lambda (x) x))
      (filter odd?))
  '())

;;;; Edge case: single elt, run of 3

(test "=> single elt 3-stage"
  (=> '(42)
      (map (lambda (x) (+ x 1)))
      (filter (lambda (_) #t))
      (take 10))
  '(43))

;;;; Ensure semantics match plain ->>

(test "=> matches ->> semantics (plain steps only)"
  (let ([plain (reverse (cdr '(0 1 2 3 4 5)))])
    (equal? plain (=> '(0 1 2 3 4 5) cdr reverse)))
  #t)

;;;; Ensure short-circuit via (take) in fused run

(define counter 0)

(test "=> (take) short-circuits fused pipeline"
  (begin
    (set! counter 0)
    (let ([r (=> '(1 2 3 4 5 6 7 8 9 10)
                 (map (lambda (x) (set! counter (+ counter 1)) x))
                 (take 3))])
      (list r counter)))
  '((1 2 3) 3))

(printf "~%~a passed, ~a failed~%" pass fail)
(exit (if (zero? fail) 0 1))
