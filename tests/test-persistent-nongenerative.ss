#!chezscheme
;;; Regression test pinning nongenerative UIDs on persistent collection
;;; record types.  Phase 29 of Round 4.
;;;
;;; Purpose: ensure the RTDs keep stable UIDs so cp0 can fold predicates
;;; across compilation units and future cptypes extensions can track
;;; pmap/pvec/pset types via stable identity.  If someone removes the
;;; nongenerative clause (or renames the UID) this test fails loudly.

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

(printf "--- Round 4 Phase 29: nongenerative UID pins ---~%~%")

(test "pmap RTD has expected UID"
  (record-type-uid (record-rtd (make-persistent-map)))
  'jerboa-pmap-v1)

(test "pvec RTD has expected UID"
  (record-type-uid (record-rtd (persistent-vector)))
  'jerboa-pvec-v1)

(test "pset RTD has expected UID"
  (record-type-uid (record-rtd (make-persistent-set)))
  'jerboa-pset-v1)

(test "tmap RTD has expected UID"
  (record-type-uid (record-rtd (transient-map pmap-empty)))
  'jerboa-tmap-v1)

(test "tset RTD has expected UID"
  (record-type-uid (record-rtd (transient-set pset-empty)))
  'jerboa-tset-v1)

;; RTD identity across separate constructor calls (same library, same run)
(test "pmap RTDs are eq? across instances"
  (eq? (record-rtd (make-persistent-map))
       (record-rtd (make-persistent-map 'a 1)))
  #t)

(test "pvec RTDs are eq? across instances"
  (eq? (record-rtd (persistent-vector))
       (record-rtd (persistent-vector 1 2 3)))
  #t)

(test "pset RTDs are eq? across instances"
  (eq? (record-rtd (make-persistent-set))
       (record-rtd (make-persistent-set 1)))
  #t)

(printf "~%--- Results: ~a/~a passed, ~a failed ---~%"
  pass (+ pass fail) fail)

(exit (if (= fail 0) 0 1))
