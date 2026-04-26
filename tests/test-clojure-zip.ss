#!chezscheme
;;; Tests for (std clojure zip) — functional zipper.

(import (jerboa prelude)
        (rename (std clojure zip)
                (remove zip-remove)))

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

(printf "--- std/clojure zip ---~%~%")

;;; Build a tree zipper: '(1 (2 3) (4 (5 6)))
(define z0 (seq-zip '(1 (2 3) (4 (5 6)))))

(test "node at root"
  (node z0)
  '(1 (2 3) (4 (5 6))))

(test "branch? at root"
  (branch? z0)
  #t)

(test "down → first child"
  (node (down z0))
  1)

(test "right after down"
  (node (right (down z0)))
  '(2 3))

(test "right twice"
  (node (right (right (down z0))))
  '(4 (5 6)))

;;; Walk into the inner subtree.
(test "down-down node"
  (node (down (right (down z0))))
  2)

(test "up restores parent"
  (node (up (down z0)))
  '(1 (2 3) (4 (5 6))))

;;; Edits.
(test "replace at first child"
  (root (replace (down z0) 99))
  '(99 (2 3) (4 (5 6))))

(test "edit doubles first child"
  (root (edit (down z0) (lambda (x) (* x 2))))
  '(2 (2 3) (4 (5 6))))

(test "insert-right after first child"
  (root (insert-right (down z0) 'NEW))
  '(1 NEW (2 3) (4 (5 6))))

(test "insert-left before first child"
  (root (insert-left (down z0) 'NEW))
  '(NEW 1 (2 3) (4 (5 6))))

(test "remove first child"
  (root (zip-remove (down z0)))
  '((2 3) (4 (5 6))))

;;; Vector zipper.
(define vz (vector-zip (vector 1 (vector 2 3) 4)))

(test "vector down node"
  (node (down vz))
  1)

(test "vector edit second child"
  (root (edit (right (down vz))
              (lambda (v) (vector 9 9))))
  (vector 1 (vector 9 9) 4))

;;; Traversal: (next ...) walks depth-first.
(let ([z (seq-zip '(1 (2 (3))))])
  (test "next-1" (node (next z)) 1)
  (test "next-2" (node (next (next z))) '(2 (3)))
  (test "next-3" (node (next (next (next z)))) 2))

;;; rightmost / leftmost.
(let ([first (down z0)])
  (test "rightmost from first"
    (node (rightmost first))
    '(4 (5 6)))
  (test "leftmost from rightmost"
    (node (leftmost (rightmost first)))
    1))

;;; lefts / rights.
(let ([second (right (down z0))])
  (test "lefts at second" (lefts  second) '(1))
  (test "rights at second" (rights second) '((4 (5 6)))))

(printf "~%passed: ~a / failed: ~a~%" pass fail)
(unless (zero? fail) (exit 1))
