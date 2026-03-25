#!chezscheme
(import (std prelude))

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

;; Verify key features from each module are available

;; Core
(chk (match 42 [x (+ x 1)]) => 43)

;; Runtime
(let ([ht (make-hash-table)])
  (hash-put! ht 'a 1)
  (chk (hash-ref ht 'a) => 1))

;; Sugar - threading
(chk (-> 5 (+ 1) (* 2)) => 12)
(chk (->> 10 (- 3)) => -7)

;; Sugar - str
(chk (str "x=" 42) => "x=42")

;; Sugar - alist
(chk (alist (a 1) (b 2)) => '((a . 1) (b . 2)))

;; Sugar - with-resource
(let ([done #f])
  (with-resource (r 1 (lambda (x) (set! done #t)))
    (+ r 1))
  (chk done => #t))

;; Result
(chk (unwrap (ok 42)) => 42)
(chk (err? (err "bad")) => #t)
(chk (unwrap (->? (ok 5) (+ 10))) => 15)

;; DateTime
(let ([d (make-datetime 2024 3 25)])
  (chk (datetime-year d) => 2024))
(chk (leap-year? 2024) => #t)
(let ([d (make-date 2024 12 31)])
  (chk (datetime-month d) => 12))

;; List utilities
(chk (flatten '((1 2) (3 (4)))) => '(1 2 3 4))
(chk (frequencies '(a b a c b a)) => (frequencies '(a b a c b a)))  ;; just check it runs
(chk (take '(1 2 3 4 5) 3) => '(1 2 3))

;; Func
(chk ((compose add1 add1) 5) => 7)
(chk ((partial + 10) 5) => 15)

;; PP
(chk (ppd-to-string 42) => "42")

;; Format
(chk (format "~a" 42) => "42")

;; defn
(defn (double [x number?]) (* x 2))
(chk (double 5) => 10)

;; Summary
(newline)
(display "prelude: ")
(display pass) (display " passed, ")
(display fail) (display " failed") (newline)
(when (> fail 0) (exit 1))
