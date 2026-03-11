#!chezscheme
;;; Tests for Phase 11: Data Processing (Lazy Sequences, Transducers, Parallel)

(import (chezscheme)
        (std seq))

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

(printf "--- Phase 11: Data Processing ---~%")

;;; ======== Lazy Sequences ========

(printf "~%-- Lazy Sequences --~%")

(test "lazy-nil? true"
  (lazy-nil? (lazy-nil))
  #t)

(test "lazy-nil? false for cons"
  (lazy-nil? (lazy-cons 1 (lazy-nil)))
  #f)

(test "lazy-seq? nil"
  (lazy-seq? (lazy-nil))
  #t)

(test "lazy-first"
  (lazy-first (lazy-cons 42 (lazy-nil)))
  42)

(test "lazy-rest is nil"
  (lazy-nil? (lazy-rest (lazy-cons 1 (lazy-nil))))
  #t)

(test "lazy->list basic"
  (lazy->list (lazy-cons 1 (lazy-cons 2 (lazy-cons 3 (lazy-nil)))))
  '(1 2 3))

(test "list->lazy and back"
  (lazy->list (list->lazy '(a b c)))
  '(a b c))

;; lazy-range
(test "lazy-range 5"
  (lazy->list (lazy-range 5))
  '(0 1 2 3 4))

(test "lazy-range 2 7"
  (lazy->list (lazy-range 2 7))
  '(2 3 4 5 6))

(test "lazy-range 0 10 3"
  (lazy->list (lazy-range 0 10 3))
  '(0 3 6 9))

;; lazy-map
(test "lazy-map"
  (lazy->list (lazy-map (lambda (x) (* x x)) (lazy-range 4)))
  '(0 1 4 9))

;; lazy-filter
(test "lazy-filter even"
  (lazy->list (lazy-filter even? (lazy-range 8)))
  '(0 2 4 6))

;; lazy-take
(test "lazy-take"
  (lazy->list (lazy-take 3 (lazy-range 10)))
  '(0 1 2))

;; lazy-drop
(test "lazy-drop"
  (lazy->list (lazy-drop 3 (lazy-range 6)))
  '(3 4 5))

;; lazy-take-while
(test "lazy-take-while"
  (lazy->list (lazy-take-while (lambda (x) (< x 5)) (lazy-range 10)))
  '(0 1 2 3 4))

;; lazy-drop-while
(test "lazy-drop-while"
  (lazy->list (lazy-drop-while (lambda (x) (< x 5)) (lazy-range 8)))
  '(5 6 7))

;; lazy-zip
(test "lazy-zip"
  (lazy->list (lazy-zip (lazy-range 3) (list->lazy '(a b c))))
  '((0 a) (1 b) (2 c)))

;; lazy-append
(test "lazy-append"
  (lazy->list (lazy-append (lazy-range 3) (list->lazy '(a b c))))
  '(0 1 2 a b c))

;; lazy-iterate
(test "lazy-iterate"
  (lazy->list (lazy-take 5 (lazy-iterate (lambda (x) (* x 2)) 1)))
  '(1 2 4 8 16))

;; lazy-repeat
(test "lazy-repeat"
  (lazy->list (lazy-take 4 (lazy-repeat 'x)))
  '(x x x x))

;; lazy-cycle
(test "lazy-cycle"
  (lazy->list (lazy-take 7 (lazy-cycle '(a b c))))
  '(a b c a b c a))

;; lazy-fold
(test "lazy-fold sum"
  (lazy-fold + 0 (lazy-range 6))
  15)

;; lazy-count
(test "lazy-count"
  (lazy-count (lazy-range 10))
  10)

;; lazy-any? / lazy-all?
(test "lazy-any? true"
  (lazy-any? even? (lazy-range 5))
  #t)

(test "lazy-any? false"
  (lazy-any? negative? (lazy-range 5))
  #f)

(test "lazy-all? true"
  (lazy-all? (lambda (x) (>= x 0)) (lazy-range 5))
  #t)

(test "lazy-all? false"
  (lazy-all? even? (lazy-range 5))
  #f)

;; lazy-nth
(test "lazy-nth 3rd element"
  (lazy-nth 2 (lazy-range 10))
  2)

;;; ======== Transducers ========

(printf "~%-- Transducers --~%")

;; map-xf
(test "map-xf"
  (into '() (map-xf (lambda (x) (* x 2))) '(1 2 3))
  '(2 4 6))

;; filter-xf
(test "filter-xf even"
  (into '() (filter-xf even?) '(1 2 3 4 5 6))
  '(2 4 6))

;; take-xf
(test "take-xf"
  (into '() (take-xf 3) '(1 2 3 4 5))
  '(1 2 3))

;; drop-xf
(test "drop-xf"
  (into '() (drop-xf 2) '(1 2 3 4 5))
  '(3 4 5))

;; take-while-xf
(test "take-while-xf"
  (into '() (take-while-xf (lambda (x) (< x 4))) '(1 2 3 4 5))
  '(1 2 3))

;; drop-while-xf
(test "drop-while-xf"
  (into '() (drop-while-xf (lambda (x) (< x 3))) '(1 2 3 4 5))
  '(3 4 5))

;; flat-map-xf
(test "flat-map-xf"
  (into '() (flat-map-xf (lambda (x) (list x (* x 10)))) '(1 2 3))
  '(1 10 2 20 3 30))

;; dedupe-xf
(test "dedupe-xf"
  (into '() (dedupe-xf) '(1 1 2 2 3 1 1))
  '(1 2 3 1))

;; compose-xf
(test "compose-xf: filter then map"
  (into '() (compose-xf (filter-xf even?) (map-xf (lambda (x) (* x x)))) '(1 2 3 4 5 6))
  '(4 16 36))

;; transduce with +
(test "transduce sum of even squares"
  (transduce
    (compose-xf (filter-xf even?) (map-xf (lambda (x) (* x x))))
    +
    0
    '(1 2 3 4 5 6))
  56)  ;; 4 + 16 + 36

;; sequence
(test "sequence"
  (sequence (map-xf (lambda (x) (* x 3))) '(1 2 3 4))
  '(3 6 9 12))

;; transduce over lazy sequence
(test "transduce over lazy range"
  (transduce (take-xf 5) + 0 (lazy-range 100))
  10)  ;; 0+1+2+3+4

;;; ======== Parallel Collections ========

(printf "~%-- Parallel Collections --~%")

;; par-map
(test "par-map squares"
  (list-sort < (par-map (lambda (x) (* x x)) '(1 2 3 4 5)))
  '(1 4 9 16 25))

;; par-filter
(test "par-filter evens"
  (list-sort < (par-filter even? '(1 2 3 4 5 6 7 8)))
  '(2 4 6 8))

;; par-reduce
(test "par-reduce sum"
  (par-reduce + 0 '(1 2 3 4 5 6 7 8 9 10))
  55)

;; par-map with chunk-size
(test "par-map chunk-size 2"
  (list-sort < (par-map (lambda (x) (+ x 1)) '(0 1 2 3 4) 'chunk-size: 2))
  '(1 2 3 4 5))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
