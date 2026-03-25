#!chezscheme
(import (except (chezscheme) make-date make-time partition
                make-hash-table hash-table?
                sort sort!
                printf fprintf
                path-extension path-absolute?
                with-input-from-string with-output-to-string
                iota 1+ 1-)
        (std sugar)
        (std result)
        (std datetime)
        (std test framework))

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

;; ========== Result-aware threading (->? and ->>?) ==========

(display "--- Result-aware threading ---") (newline)

;; ->? threads ok values, short-circuits on err
(chk (ok? (->? (ok 5) (+ 1) (* 2))) => #t)
(chk (unwrap (->? (ok 5) (+ 1) (* 2))) => 12)
(chk (err? (->? (err "bad") (+ 1))) => #t)
(chk (unwrap-err (->? (err "bad") (+ 1))) => "bad")

;; ->>? threads as last arg
(chk (unwrap (->>? (ok 10) (- 3))) => -7)  ;; (- 3 10) = -7
(chk (err? (->>? (err "fail") (- 3))) => #t)

;; Multi-step
(chk (unwrap (->? (ok 1) (+ 10) (* 2) (- 1))) => 21)  ;; ((1+10)*2)-1 = 21

;; ========== with-resource ==========

(display "--- with-resource ---") (newline)

;; Basic lifecycle: resource opened, body executed, cleanup runs
(let ([cleaned-up #f])
  (let ([result (with-resource (r 42 (lambda (x) (set! cleaned-up #t)))
                  (+ r 1))])
    (chk result => 43)
    (chk cleaned-up => #t)))

;; Cleanup runs even on error
(let ([cleaned-up #f])
  (guard (exn [#t (void)])
    (with-resource (r 42 (lambda (x) (set! cleaned-up #t)))
      (error 'test "boom")))
  (chk cleaned-up => #t))

;; ========== str (string builder) ==========

(display "--- str ---") (newline)

(chk (str) => "")
(chk (str "hello") => "hello")
(chk (str "hello " "world") => "hello world")
(chk (str "val=" 42) => "val=42")
(chk (str "pi=" 3.14) => "pi=3.14")
(chk (str "sym=" 'foo) => "sym=foo")
(chk (str #t " and " #f) => "#t and #f")
(chk (str "a" 1 "b" 2 "c") => "a1b2c")

;; ========== alist constructor ==========

(display "--- alist ---") (newline)

(chk (alist) => '())
(chk (alist (name "Alice")) => '((name . "Alice")))
(chk (alist (name "Alice") (age 30))
  => '((name . "Alice") (age . 30)))
(let ([a (alist (x 1) (y 2) (z 3))])
  (chk (cdr (assq 'x a)) => 1)
  (chk (cdr (assq 'z a)) => 3))

;; ========== defn (guarded definitions) ==========

(display "--- defn ---") (newline)

(defn (add [x number?] [y number?])
  (+ x y))

(chk (add 3 4) => 7)

;; Guard failure
(let ([failed #f])
  (guard (exn [#t (set! failed #t)])
    (add "not a number" 4))
  (chk failed => #t))

(defn (greet [name string?])
  (str "Hello, " name "!"))

(chk (greet "World") => "Hello, World!")

;; ========== check= (test framework shortcuts) ==========

(display "--- check= shortcuts ---") (newline)

;; These use the test framework internally, so we run them in a suite
(define-test-suite token-saver-checks
  (check= (+ 1 2) 3)
  (check-true (> 5 3))
  (check-false (> 3 5))
  (check-pred number? 42)
  (check-error (error 'test "boom")))

(let ([result (run-suite token-saver-checks)])
  (chk (suite-passed result) => 5)
  (chk (suite-failed result) => 0))

;; ========== Summary ==========

(newline)
(display "token-savers: ")
(display pass) (display " passed, ")
(display fail) (display " failed") (newline)
(when (> fail 0) (exit 1))
