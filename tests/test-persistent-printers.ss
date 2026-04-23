#!chezscheme
;;; Tests for record-writer integration on persistent collections.
;;; Phase 26 of Round 4.
;;;
;;; Contract:
;;;   pmap prints as {k1 v1 k2 v2}  (no commas, matches Clojure sans :)
;;;   pvec prints as [e1 e2 e3]     (square brackets distinguish from #(...))
;;;   pset prints as #{e1 e2 e3}    (matches Clojure set literal)
;;;
;;; Element order for pmap/pset follows internal iteration order, which
;;; is a function of hash layout — not insertion order. Tests avoid
;;; depending on order for multi-element collections.

(import (chezscheme) (std pmap) (std pvec) (std pset))

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

(define (->str proc obj)
  (with-output-to-string (lambda () (proc obj))))

(printf "--- Round 4 Phase 26: printers ---~%~%")

;;; ========== pmap ==========

(test "pmap empty" (->str display (make-persistent-map)) "{}")

(test "pmap single"
  (->str display (make-persistent-map 'a 1))
  "{a 1}")

(test "pmap size 2"
  ;; Must parse back to the exact map, regardless of hash order.
  (let ([s (->str display (make-persistent-map 'a 1 'b 2))])
    (or (equal? s "{a 1 b 2}") (equal? s "{b 2 a 1}")))
  #t)

(test "pmap write strings quotes"
  (->str write (make-persistent-map "k" "v"))
  "{\"k\" \"v\"}")

;;; ========== pvec ==========

(test "pvec empty" (->str display (persistent-vector)) "[]")
(test "pvec single" (->str display (persistent-vector 42)) "[42]")
(test "pvec ordered" (->str display (persistent-vector 1 2 3)) "[1 2 3]")
(test "pvec write strings"
  (->str write (persistent-vector "a" "b"))
  "[\"a\" \"b\"]")

(test "pvec large retains order"
  (->str display (list->persistent-vector (iota 10)))
  "[0 1 2 3 4 5 6 7 8 9]")

;;; ========== pset ==========

(test "pset empty" (->str display (make-persistent-set)) "#{}")
(test "pset single" (->str display (make-persistent-set 'a)) "#{a}")

;;; ========== nesting ==========

(test "pvec of pmap"
  (->str display (persistent-vector (make-persistent-map 'x 1)))
  "[{x 1}]")

(test "pmap with pvec value"
  (->str display (make-persistent-map 'lst (persistent-vector 1 2 3)))
  "{lst [1 2 3]}")

(test "pmap with pset value"
  (->str display (make-persistent-map 'tags (make-persistent-set 'a)))
  "{tags #{a}}")

(printf "~%--- Results: ~a/~a passed, ~a failed ---~%"
  pass (+ pass fail) fail)

(exit (if (= fail 0) 0 1))
