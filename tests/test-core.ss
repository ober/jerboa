#!chezscheme
;;; test-core.ss -- Tests for Jerboa core macros and runtime

(import (except (chezscheme) make-hash-table hash-table? iota 1+ 1-)
        (jerboa core) (jerboa runtime))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr]
           [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: ")
           (write 'expr)
           (display " => ")
           (write result)
           (display " expected ")
           (write exp)
           (newline))))]))

;;; ---- DEF tests ----

;; Simple binding
(def x 42)
(check x => 42)

;; Simple function
(def (add a b) (+ a b))
(check (add 3 4) => 7)

;; Function with optional args
(def (greet name (greeting "hello"))
  (string-append greeting " " name))
(check (greet "world") => "hello world")
(check (greet "world" "hi") => "hi world")

;; Multiple optionals
(def (make-point (x 0) (y 0) (z 0))
  (list x y z))
(check (make-point) => '(0 0 0))
(check (make-point 1) => '(1 0 0))
(check (make-point 1 2) => '(1 2 0))
(check (make-point 1 2 3) => '(1 2 3))

;; Rest args
(def (variadic first . rest)
  (cons first rest))
(check (variadic 1 2 3) => '(1 2 3))

;;; ---- DEF* (case-lambda) ----

(def* multi-arity
  [(x) (list 'one x)]
  [(x y) (list 'two x y)]
  [(x y z) (list 'three x y z)])
(check (multi-arity 1) => '(one 1))
(check (multi-arity 1 2) => '(two 1 2))
(check (multi-arity 1 2 3) => '(three 1 2 3))

;;; ---- DEFRULE / DEFRULES ----

(defrule (swap! a b)
  (let ([tmp a])
    (set! a b)
    (set! b tmp)))

(let ([x 1] [y 2])
  (swap! x y)
  (check x => 2)
  (check y => 1))

(defrules my-or ()
  [(_) #f]
  [(_ e) e]
  [(_ e1 e2 ...)
   (let ([t e1])
     (if t t (my-or e2 ...)))])

(check (my-or) => #f)
(check (my-or 42) => 42)
(check (my-or #f 99) => 99)
(check (my-or #f #f "yes") => "yes")

;;; ---- DEFSTRUCT ----

(defstruct point (x y))

(let ([p (make-point 3 4)])
  (check (point? p) => #t)
  (check (point-x p) => 3)
  (check (point-y p) => 4)
  (point-x-set! p 10)
  (check (point-x p) => 10))

;; Test record-type descriptor
(check (record-type-descriptor? point::t) => #t)

;;; ---- DEFMETHOD ----

(defmethod (describe (self point))
  (string-append "point(" (number->string (point-x self))
                 "," (number->string (point-y self)) ")"))

(let ([p (make-point 3 4)])
  (check (~ p 'describe) => "point(3,4)"))

;;; ---- MATCH ----

;; Literal matching
(check (match 42
         (42 "yes")
         (else "no"))
       => "yes")

;; Variable binding
(check (match '(1 2 3)
         ((a . rest) (list a rest)))
       => '(1 (2 3)))

;; List pattern
(check (match '(1 2 3)
         ((list a b c) (+ a b c)))
       => 6)

;; Nested
(check (match '(1 (2 3))
         ((list a (list b c)) (list c b a)))
       => '(3 2 1))

;; Wildcard
(check (match '(1 2)
         ((list _ b) b))
       => 2)

;; Predicate
(check (match "hello"
         ((? string? s) (string-append s "!"))
         (else "not a string"))
       => "hello!")

;; Quoted
(check (match 'foo
         ('foo "got foo")
         (else "nope"))
       => "got foo")

;; else
(check (match 99
         ("x" 1)
         (else 2))
       => 2)

;; Boolean/number literals
(check (match #t
         (#t "true")
         (#f "false"))
       => "true")

;; Cons pattern
(check (match '(a . b)
         ((cons x y) (list y x)))
       => '(b a))

;;; ---- TRY/CATCH/FINALLY ----

;; Catch all
(check (try
         (error 'test "boom")
         (catch (e) "caught"))
       => "caught")

;; Catch with error-message
(check (try
         (error 'test "boom")
         (catch (e) (error-message e)))
       => "boom")

;; Finally
(let ([cleaned #f])
  (try
    42
    (finally (set! cleaned #t)))
  (check cleaned => #t))

;; Catch + finally
(let ([cleaned #f])
  (check (try
           (error 'test "boom")
           (catch (e) "caught")
           (finally (set! cleaned #t)))
         => "caught")
  (check cleaned => #t))

;;; ---- WHILE/UNTIL ----

(let ([i 0] [sum 0])
  (while (< i 5)
    (set! sum (+ sum i))
    (set! i (+ i 1)))
  (check sum => 10))

(let ([i 0])
  (until (= i 3)
    (set! i (+ i 1)))
  (check i => 3))

;;; ---- HASH tables ----

(let ([ht (make-hash-table)])
  (hash-put! ht 'a 1)
  (hash-put! ht 'b 2)
  (check (hash-ref ht 'a) => 1)
  (check (hash-get ht 'c) => #f)
  (check (hash-key? ht 'a) => #t)
  (check (hash-key? ht 'z) => #f)
  (check (hash-length ht) => 2)
  (hash-remove! ht 'a)
  (check (hash-length ht) => 1))

;; hash-ref with default
(let ([ht (make-hash-table)])
  (check (hash-ref ht 'missing "default") => "default")
  (check (hash-ref ht 'missing (lambda () "computed")) => "computed"))

;; hash-update!
(let ([ht (make-hash-table)])
  (hash-put! ht 'count 0)
  (hash-update! ht 'count 1+)
  (hash-update! ht 'count 1+)
  (check (hash-ref ht 'count) => 2))

;; hash-copy, hash-merge
(let ([h1 (make-hash-table)]
      [h2 (make-hash-table)])
  (hash-put! h1 'a 1)
  (hash-put! h2 'b 2)
  (let ([merged (hash-merge h1 h2)])
    (check (hash-ref merged 'a) => 1)
    (check (hash-ref merged 'b) => 2)))

;; list->hash-table
(let ([ht (list->hash-table '((a . 1) (b . 2)))])
  (check (hash-ref ht 'a) => 1)
  (check (hash-ref ht 'b) => 2))

;; hash-literal
(let ([ht (hash-literal (a 1) (b 2))])
  (check (hash-ref ht 'a) => 1)
  (check (hash-ref ht 'b) => 2))

;;; ---- LET-HASH ----

(let ([ht (make-hash-table)])
  (hash-put! ht 'name "Alice")
  (hash-put! ht 'age 30)
  (check (let-hash ht .name) => "Alice")
  (check (let-hash ht .age) => 30)
  (check (let-hash ht .?missing) => #f))

;;; ---- KEYWORDS ----

(check (keyword? (string->keyword "foo")) => #t)
(check (keyword? 'foo) => #f)
(check (keyword->string (string->keyword "test")) => "test")

;;; ---- DISPLAYLN ----

(let ([out (open-output-string)])
  (parameterize ([current-output-port out])
    (displayln "hello" " " "world"))
  (check (get-output-string out) => "hello world\n"))

;;; ---- UTILITIES ----

(check (1+ 5) => 6)
(check (1- 5) => 4)
(check (iota 5) => '(0 1 2 3 4))
(check (iota 3 1) => '(1 2 3))
(check (last-pair '(a b c)) => '(c))

;;; ---- Summary ----
(newline)
(display "Core tests: ")
(display pass-count)
(display " passed, ")
(display fail-count)
(display " failed")
(newline)
(when (> fail-count 0) (exit 1))
