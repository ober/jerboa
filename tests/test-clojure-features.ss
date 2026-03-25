#!chezscheme
(import (except (chezscheme) partition)
        (std sugar)
        (std misc list)
        (std misc func))

(define pass 0)
(define fail 0)
(define-syntax chk
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([r expr] [e expected])
       (if (equal? r e)
         (set! pass (+ pass 1))
         (begin (set! fail (+ fail 1))
                (display "FAIL: ") (write 'expr)
                (display " => ") (write r)
                (display " expected ") (write e) (newline))))]))

;; ========== Threading macros ==========

;; ->  (thread-first)
(chk (-> 1 (+ 2) (* 3)) => 9)        ; (* (+ 1 2) 3)
(chk (-> "hello" string-length) => 5)
(chk (-> '(1 2 3) car) => 1)

;; ->> (thread-last)
(chk (->> '(1 2 3 4 5)
           (filter odd?)
           (map (lambda (x) (* x x)))) => '(1 9 25))
(chk (->> 5 (- 10)) => 5)  ; (- 10 5)

;; as-> (named threading)
(chk (as-> 0 x (+ x 1) (* x 2) (- x 1)) => 1)

;; some-> (nil-safe threading)
(chk (some-> 5 (+ 3) (* 2)) => 16)
(chk (some-> #f (+ 3)) => #f)

;; some->> (nil-safe thread-last)
(chk (some->> '(1 2 3) (map add1)) => '(2 3 4))
(chk (some->> #f (map add1)) => #f)

;; cond-> (conditional threading)
(chk (cond-> 10 #t (+ 5) #f (* 100)) => 15)
(chk (cond-> 10 #t (+ 5) #t (* 2)) => 30)

;; cond->> (conditional thread-last)
(chk (cond->> '(1 2 3 4 5) #t (filter odd?) #t (map add1)) => '(2 4 6))

;; ========== Sequence utilities ==========

;; frequencies
(let ([freqs (frequencies '(a b a c b a))])
  (chk (cdr (assq 'a freqs)) => 3)
  (chk (cdr (assq 'b freqs)) => 2)
  (chk (cdr (assq 'c freqs)) => 1))

;; partition
(chk (partition 2 '(1 2 3 4 5)) => '((1 2) (3 4)))
(chk (partition 3 '(1 2 3 4 5 6 7)) => '((1 2 3) (4 5 6)))

;; partition-all
(chk (partition-all 2 '(1 2 3 4 5)) => '((1 2) (3 4) (5)))

;; partition-by
(chk (partition-by odd? '(1 3 2 4 5)) => '((1 3) (2 4) (5)))

;; interleave
(chk (interleave '(1 2 3) '(a b c)) => '(1 a 2 b 3 c))
(chk (interleave '(1 2) '(a b c)) => '(1 a 2 b))

;; interpose
(chk (interpose 0 '(1 2 3)) => '(1 0 2 0 3))
(chk (interpose ", " '("a" "b" "c")) => '("a" ", " "b" ", " "c"))

;; mapcat
(chk (mapcat (lambda (x) (list x x)) '(1 2 3)) => '(1 1 2 2 3 3))

;; distinct
(chk (distinct '(1 2 1 3 2 4)) => '(1 2 3 4))

;; keep (filter-map)
(chk (keep (lambda (x) (and (> x 2) (* x 10))) '(1 2 3 4)) => '(30 40))

;; some
(chk (some even? '(1 3 4 5)) => #t)
(chk (some even? '(1 3 5 7)) => #f)

;; iterate-n
(chk (iterate-n 5 add1 0) => '(0 1 2 3 4))

;; reductions
(chk (reductions + 0 '(1 2 3 4)) => '(0 1 3 6 10))

;; take-last / drop-last
(chk (take-last 2 '(1 2 3 4 5)) => '(4 5))
(chk (drop-last 2 '(1 2 3 4 5)) => '(1 2 3))

;; split-at
(chk (split-at 2 '(1 2 3 4 5)) => '((1 2) (3 4 5)))

;; split-with
(chk (split-with even? '(2 4 5 6)) => '((2 4) (5 6)))

;; ========== Functional combinators ==========

;; partial
(chk ((partial + 10) 5) => 15)
(chk ((partial * 2 3) 4) => 24)

;; complement
(chk ((complement even?) 3) => #t)
(chk ((complement even?) 4) => #f)

;; comp
(chk ((comp add1 add1 add1) 0) => 3)

;; fnil
(let ([safe-+ (fnil + 0 0)])
  (chk (safe-+ #f 5) => 5)
  (chk (safe-+ 3 #f) => 3)
  (chk (safe-+ 3 5) => 8))

;; every-pred
(chk ((every-pred number? positive?) 5) => #t)
(chk ((every-pred number? positive?) -1) => #f)
(chk ((every-pred number? positive?) "hi") => #f)

;; some-fn
(chk ((some-fn symbol? string?) 'hello) => #t)
(chk ((some-fn symbol? string?) "hello") => #t)
(chk ((some-fn symbol? string?) 42) => #f)

(newline)
(display "clojure features: ")
(display pass) (display " passed, ")
(display fail) (display " failed") (newline)
(when (> fail 0) (exit 1))
