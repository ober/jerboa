#!chezscheme
;;; Round 11 small Clojure-parity additions:
;;;   Phase 56 — condp accepts `=>` as alias for `:>>`.
;;;   Phase 60 — map-indexed / keep-indexed work over vectors,
;;;              persistent-vectors, and strings (not just lists).

(import (jerboa prelude)
        (only (std clojure)
              condp map-indexed keep-indexed)
        (only (std pvec)
              persistent-vector persistent-vector->list))

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

(printf "--- Round 11 / clojure extras ---~%~%")

;;; ---- Phase 56: condp `=>` alias --------------------------------

(test "condp => binds match through handler"
  (condp (lambda (a b) (and (= a b) a)) 5
    3 => (lambda (x) (list 'three x))
    5 => (lambda (x) (list 'five x))
    9 => (lambda (x) (list 'nine x))
    'no-match)
  '(five 5))

(test "condp falls through to default"
  (condp (lambda (a b) (and (= a b) a)) 7
    3 => (lambda (x) (list 'three x))
    5 => (lambda (x) (list 'five x))
    'fallback)
  'fallback)

;;; ---- Phase 60: indexed maps over multiple containers -----------

(test "map-indexed on list"
  (map-indexed (lambda (i x) (cons i x)) '(a b c))
  '((0 . a) (1 . b) (2 . c)))

(test "map-indexed on vector"
  (map-indexed (lambda (i x) (cons i x)) (vector 'a 'b 'c))
  '((0 . a) (1 . b) (2 . c)))

(test "map-indexed on persistent-vector"
  (map-indexed (lambda (i x) (cons i x))
               (persistent-vector 'a 'b 'c))
  '((0 . a) (1 . b) (2 . c)))

(test "map-indexed on string"
  (map-indexed (lambda (i c) (list i c)) "abc")
  '((0 #\a) (1 #\b) (2 #\c)))

(test "keep-indexed on vector keeps even-index chars"
  (keep-indexed
    (lambda (i x) (if (even? i) x #f))
    (vector 'a 'b 'c 'd))
  '(a c))

(test "keep-indexed on persistent-vector"
  (keep-indexed
    (lambda (i x) (and (odd? i) (cons i x)))
    (persistent-vector 'a 'b 'c 'd))
  '((1 . b) (3 . d)))

(printf "~%passed: ~a / failed: ~a~%" pass fail)
(unless (zero? fail) (exit 1))
