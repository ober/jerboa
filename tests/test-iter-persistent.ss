#!chezscheme
;;; Tests for for/for-collect/for-fold over persistent collections.
;;; Phase 28 of Round 4.
;;;
;;; Iterators covered:
;;;   in-pvec               → yields elements in index order
;;;   in-pmap, in-pmap-pairs → yields (k . v) pairs (iteration order = hash)
;;;   in-pmap-keys          → yields keys
;;;   in-pmap-values        → yields values
;;;   in-pset               → yields elements (iteration order = hash)
;;;
;;; Fused paths skip the materialize-to-list step.  Correctness vs. the
;;; unfused path is the thing we test here.

(import (chezscheme) (std iter) (std pmap) (std pvec) (std pset))

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

(define-syntax test-setish
  ;; Same as test but with set-equivalence comparison (hash iteration
  ;; order for pmap/pset isn't insertion order).
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (let ([gs (list-sort < got)] [es (list-sort < expected)])
           (if (equal? gs es)
               (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
               (begin (set! fail (+ fail 1))
                      (printf "FAIL ~a: got ~s expected ~s~%" name got expected))))))]))

(printf "--- Round 4 Phase 28: for over persistent collections ---~%~%")

;;; ========== pvec ==========

(test "for in-pvec side-effect order"
  (let ([acc '()])
    (for ((x (in-pvec (persistent-vector 10 20 30))))
      (set! acc (cons x acc)))
    (reverse acc))
  '(10 20 30))

(test "for/collect in-pvec"
  (for/collect ((x (in-pvec (persistent-vector 1 2 3 4 5))))
    (* x x))
  '(1 4 9 16 25))

(test "for/fold in-pvec sum"
  (for/fold ((s 0)) ((x (in-pvec (persistent-vector 1 2 3 4 5))))
    (+ s x))
  15)

(test "for in-pvec empty"
  (let ([acc '()])
    (for ((x (in-pvec (persistent-vector))))
      (set! acc (cons x acc)))
    acc)
  '())

(test "for/collect in-pvec large"
  (for/collect ((x (in-pvec (list->persistent-vector (iota 50)))))
    x)
  (iota 50))

;;; ========== pmap (pairs) ==========

(test "for/collect in-pmap pairs → sum of k+v"
  (list-sort <
    (for/collect ((kv (in-pmap (make-persistent-map 'a 1 'b 2 'c 3))))
      (cdr kv)))
  '(1 2 3))

(test "for/fold in-pmap values sum"
  (for/fold ((s 0))
            ((kv (in-pmap (make-persistent-map 'a 1 'b 2 'c 3))))
    (+ s (cdr kv)))
  6)

(test "for in-pmap side-effect count"
  (let ([n 0])
    (for ((kv (in-pmap (make-persistent-map 'a 1 'b 2 'c 3 'd 4))))
      (set! n (+ n 1)))
    n)
  4)

(test "for in-pmap empty"
  (for/fold ((c 0)) ((kv (in-pmap (make-persistent-map))))
    (+ c 1))
  0)

;;; ========== pmap-keys / pmap-values ==========

(test-setish "for/collect in-pmap-keys"
  (for/collect ((k (in-pmap-keys (make-persistent-map 1 'a 2 'b 3 'c))))
    k)
  '(1 2 3))

(test-setish "for/collect in-pmap-values"
  (for/collect ((v (in-pmap-values (make-persistent-map 'a 10 'b 20 'c 30))))
    v)
  '(10 20 30))

(test "for/fold in-pmap-values sum"
  (for/fold ((s 0))
            ((v (in-pmap-values (make-persistent-map 'a 1 'b 2 'c 3 'd 4))))
    (+ s v))
  10)

;;; ========== pset ==========

(test-setish "for/collect in-pset"
  (for/collect ((x (in-pset (make-persistent-set 1 2 3 4))))
    x)
  '(1 2 3 4))

(test "for/fold in-pset sum"
  (for/fold ((s 0)) ((x (in-pset (make-persistent-set 1 2 3 4 5))))
    (+ s x))
  15)

(test "for in-pset count"
  (let ([n 0])
    (for ((x (in-pset (make-persistent-set 'a 'b 'c))))
      (set! n (+ n 1)))
    n)
  3)

(test "for/collect in-pset empty"
  (for/collect ((x (in-pset (make-persistent-set))))
    x)
  '())

;;; ========== Mixed: pmap within larger computation ==========

(test "for/fold in-pmap build alist"
  (list-sort (lambda (a b) (< (cdr a) (cdr b)))
    (for/fold ((al '()))
              ((kv (in-pmap (make-persistent-map 'x 1 'y 2 'z 3))))
      (cons kv al)))
  '((x . 1) (y . 2) (z . 3)))

;;; ========== Regression: non-persistent paths still fused ==========

(test "regression for/collect in-range"
  (for/collect ((i (in-range 5))) i)
  '(0 1 2 3 4))

(test "regression for/collect in-vector"
  (for/collect ((x (in-vector (vector 'a 'b 'c)))) x)
  '(a b c))

(test "regression for/fold in-list"
  (for/fold ((s 0)) ((x (in-list '(1 2 3 4)))) (+ s x))
  10)

(printf "~%--- Results: ~a/~a passed, ~a failed ---~%"
  pass (+ pass fail) fail)

(exit (if (= fail 0) 0 1))
