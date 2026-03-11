#!chezscheme
;;; Tests for (std match-syntax) — Syntax-Level Pattern Matching

(import (chezscheme) (std match-syntax))

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
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define-syntax test-pred
  (syntax-rules ()
    [(_ name expr pred)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (pred got)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: predicate failed on ~s~%" name got)))))]))

(printf "--- (std match-syntax) tests ---~%")

;; ======== AST Predicates ========

(printf "~%-- AST Predicates --~%")

(test "stx-identifier? for symbol"
  (stx-identifier? 'foo)
  #t)

(test "stx-identifier? false for list"
  (stx-identifier? '(a b))
  #f)

(test "stx-literal? number"
  (stx-literal? 42)
  #t)

(test "stx-literal? string"
  (stx-literal? "hello")
  #t)

(test "stx-literal? boolean"
  (stx-literal? #t)
  #t)

(test "stx-literal? char"
  (stx-literal? #\a)
  #t)

(test "stx-literal? false for symbol"
  (stx-literal? 'x)
  #f)

(test "stx-list? proper list"
  (stx-list? '(1 2 3))
  #t)

(test "stx-list? false for null"
  (stx-list? '())
  #f)

(test "stx-null? on empty"
  (stx-null? '())
  #t)

(test "stx-null? false on pair"
  (stx-null? '(a))
  #f)

(test "stx-application? detects application"
  (stx-application? '(f 1 2))
  #t)

(test "stx-application? false for lambda"
  (stx-application? '(lambda (x) x))
  #f)

(test "stx-application? false for if"
  (stx-application? '(if #t 1 2))
  #f)

(test "stx-lambda?"
  (stx-lambda? '(lambda (x y) (+ x y)))
  #t)

(test "stx-if?"
  (stx-if? '(if test then else))
  #t)

(test "stx-let?"
  (stx-let? '(let ([x 1]) x))
  #t)

(test "stx-define?"
  (stx-define? '(define x 42))
  #t)

(test "stx-begin?"
  (stx-begin? '(begin 1 2 3))
  #t)

(test "stx-quote?"
  (stx-quote? '(quote foo))
  #t)

;; ======== Destructuring Accessors ========

(printf "~%-- Destructuring --~%")

(test "stx-app-fn"
  (stx-app-fn '(foo 1 2 3))
  'foo)

(test "stx-app-args"
  (stx-app-args '(foo 1 2 3))
  '(1 2 3))

(test "stx-lambda-formals"
  (stx-lambda-formals '(lambda (x y) (+ x y)))
  '(x y))

(test "stx-lambda-body"
  (stx-lambda-body '(lambda (x y) (+ x y)))
  '((+ x y)))

(test "stx-if-test"
  (stx-if-test '(if condition then else))
  'condition)

(test "stx-if-then"
  (stx-if-then '(if condition then else))
  'then)

(test "stx-if-else with else branch"
  (stx-if-else '(if condition then else-part))
  'else-part)

(test "stx-if-else without else branch"
  (stx-if-else '(if condition then))
  #f)

(test "stx-let-bindings"
  (stx-let-bindings '(let ([x 1] [y 2]) body))
  '((x 1) (y 2)))

(test "stx-let-body"
  (stx-let-body '(let ([x 1]) (+ x 1)))
  '((+ x 1)))

(test "stx-define-name: simple"
  (stx-define-name '(define x 42))
  'x)

(test "stx-define-name: function form"
  (stx-define-name '(define (f x y) (+ x y)))
  'f)

(test "stx-define-value: simple"
  (stx-define-value '(define x 42))
  42)

(test "stx-define-value: function form"
  (stx-define-value '(define (f x) (* x 2)))
  '(lambda (x) (* x 2)))

(test "stx-begin-exprs"
  (stx-begin-exprs '(begin 1 2 3))
  '(1 2 3))

(test "stx-identifier-symbol"
  (stx-identifier-symbol 'foo)
  'foo)

;; ======== Pattern Matching ========

(printf "~%-- Pattern Matching --~%")

;; Use the procedural match-pattern directly
(define (match pat stx)
  (match-pattern pat stx))

;; Wildcard
(test "wildcard matches anything"
  (match '_ 42)
  '())

(test "wildcard matches list"
  (match '_ '(1 2 3))
  '())

;; Variable binding
(test "variable binds value"
  (match 'x 42)
  '((x . 42)))

;; Quoted literal
(test "quote matches exact value"
  (match '(quote 42) 42)
  '())

(test "quote fails on wrong value"
  (match '(quote 42) 43)
  #f)

;; Predicate pattern
(test "? pattern matches"
  (match '(? number?) 42)
  '())

(test "? pattern fails"
  (match '(? number?) "hello")
  #f)

(test "? pattern with binding"
  (match '(? number? n) 42)
  '((n . 42)))

;; List pattern
(test "list pattern matches"
  (match '(list a b c) '(1 2 3))
  '((a . 1) (b . 2) (c . 3)))

(test "list pattern fails on wrong length"
  (match '(list a b) '(1 2 3))
  #f)

(test "list pattern with wildcard"
  (match '(list _ b _) '(1 2 3))
  '((b . 2)))

;; Pair pattern
(test "pair pattern matches"
  (match '(pair h t) '(1 2 3))
  '((h . 1) (t . (2 3))))

(test "pair pattern fails on non-pair"
  (match '(pair h t) '())
  #f)

;; syntax-match macro
(printf "~%-- syntax-match macro --~%")

(test "syntax-match: variable pattern"
  (syntax-match 42
    (x (* x 2)))
  84)

(test "syntax-match: list pattern"
  (syntax-match '(1 2 3)
    ((list a b c) (+ a b c)))
  6)

(test "syntax-match: no match returns #f"
  (syntax-match 99
    ((list a b) (+ a b)))
  #f)

(test "syntax-match: multiple clauses"
  (syntax-match '(if #t 1 2)
    ((list (quote if) tst thn alt) (list 'if-expr tst thn alt))
    (_ 'other))
  '(if-expr #t 1 2))

;; ======== Code Walking ========

(printf "~%-- Code Walking --~%")

(test "walk-syntax: identity"
  (walk-syntax (lambda (x) #f) '(+ 1 2))
  '(+ 1 2))

(test "walk-syntax: replace numbers"
  (walk-syntax (lambda (x) (if (number? x) 0 #f)) '(+ 1 2))
  '(+ 0 0))

(test "walk-syntax: deep replacement"
  (walk-syntax (lambda (x) (if (eq? x 'old) 'new #f))
               '(foo old (bar old baz)))
  '(foo new (bar new baz)))

(test "fold-syntax: sum all numbers"
  (fold-syntax (lambda (acc x) (if (number? x) (+ acc x) acc))
               0
               '(+ 1 (* 2 3)))
  6)

(test-pred "free-identifiers: simple"
  (free-identifiers '(+ x y) '())
  (lambda (fv) (and (member 'x fv) (member 'y fv) #t)))

(test-pred "free-identifiers: bound var not free"
  (free-identifiers '(let ([x 1]) (+ x y)) '())
  (lambda (fv) (and (member 'y fv) (not (member 'x fv)) #t)))

(test-pred "free-identifiers: lambda shadows"
  (free-identifiers '(lambda (x) (+ x y)) '())
  (lambda (fv) (and (member 'y fv) (not (member 'x fv)) #t)))

;; ======== Building Syntax ========

(printf "~%-- Building Syntax --~%")

(test "build-let with bindings"
  (build-let '((x 1) (y 2)) '(+ x y))
  '(let ((x 1) (y 2)) (+ x y)))

(test "build-let empty bindings"
  (build-let '() '(+ x y))
  '(+ x y))

(test "build-lambda"
  (build-lambda '(x y) '(+ x y))
  '(lambda (x y) (+ x y)))

(test "build-if with else"
  (build-if 'test 'then 'else)
  '(if test then else))

(test "build-if without else"
  (build-if 'test 'then)
  '(if test then))

(test "build-begin single"
  (build-begin '(expr))
  'expr)

(test "build-begin multiple"
  (build-begin '(a b c))
  '(begin a b c))

(test "build-app"
  (build-app 'f '(1 2 3))
  '(f 1 2 3))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
