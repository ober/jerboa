#!chezscheme
;;; Tests for (std rewrite) -- Term rewriting system

(import (chezscheme)
        (std rewrite))

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

(printf "--- Phase 3d: Term Rewriting ---~%~%")

;;; ---- Terms ----

(test "make-term basic"
  (make-term 'add 1 2)
  '(add 1 2))

(test "make-term nested"
  (make-term 'mul (make-term 'add 1 2) 3)
  '(mul (add 1 2) 3))

(test "term? true"
  (term? '(add 1 2))
  #t)

(test "term? atom is not term"
  (term? 42)
  #f)

(test "term? non-symbol head"
  (term? '(1 2 3))
  #f)

(test "term-head"
  (term-head '(add 1 2))
  'add)

(test "term-args"
  (term-args '(add 1 2))
  '(1 2))

;;; ---- Pattern variables ----

(test "pattern-var? yes"
  (pattern-vars '?x)
  '(?x))

(test "pattern-vars in term"
  (let ([vars (pattern-vars '(add ?x ?y))])
    (and (member '?x vars) (member '?y vars) (= (length vars) 2)))
  #t)

(test "pattern-vars no vars"
  (pattern-vars '(add 1 2))
  '())

(test "pattern-vars nested"
  (let ([vars (pattern-vars '(add ?x (mul ?y 0)))])
    (and (member '?x vars) (member '?y vars) (= (length vars) 2)))
  #t)

;;; ---- Pattern matching ----

(test "pattern-match simple"
  (pattern-match '(add ?x 0) '(add 42 0))
  '((?x . 42)))

(test "pattern-match no match"
  (pattern-match '(add ?x 0) '(mul 2 3))
  #f)

(test "pattern-match two vars"
  (pattern-match '(add ?x ?y) '(add 3 4))
  '((?y . 4) (?x . 3)))

(test "pattern-match atom"
  (pattern-match 42 42)
  '())

(test "pattern-match atom mismatch"
  (pattern-match 42 99)
  #f)

(test "pattern-match nested"
  (pattern-match '(mul ?x (add ?y 0)) '(mul 3 (add 5 0)))
  '((?y . 5) (?x . 3)))

;;; ---- Substitution ----

(test "substitute basic"
  (substitute '(add ?x ?y) '((?x . 3) (?y . 4)))
  '(add 3 4))

(test "substitute atom"
  (substitute '?x '((?x . 42)))
  42)

(test "substitute no binding"
  (substitute '?z '((?x . 1)))
  '?z)

(test "substitute nested"
  (substitute '(mul ?a (add ?b ?c)) '((?a . 2) (?b . 3) (?c . 4)))
  '(mul 2 (add 3 4)))

;;; ---- Rules ----

(test "make-rule"
  (rule? (make-rule "addze" '(add ?x 0) '?x))
  #t)

(test "rule-name"
  (rule-name (make-rule "addze" '(add ?x 0) '?x))
  "addze")

(test "rule-lhs"
  (rule-lhs (make-rule "r" '(add ?x 0) '?x))
  '(add ?x 0))

(test "rule-rhs"
  (rule-rhs (make-rule "r" '(add ?x 0) '?x))
  '?x)

;;; ---- Ruleset ----

(test "make-ruleset"
  (ruleset? (make-ruleset))
  #t)

;;; ---- rewrite-once ----

(let* ([rs (make-ruleset)]
       [r1 (make-rule "add-zero" '(add ?x 0) '?x)]
       [r2 (make-rule "mul-one" '(mul ?x 1) '?x)])
  (ruleset-add! rs r1)
  (ruleset-add! rs r2)

  (test "rewrite-once match"
    (rewrite-once rs '(add 42 0))
    42)

  (test "rewrite-once mul-one"
    (rewrite-once rs '(mul 7 1))
    7)

  (test "rewrite-once no match"
    (rewrite-once rs '(sub 5 3))
    #f))

;;; ---- rewrite (innermost-first) ----

(let* ([rs (make-ruleset)]
       [r1 (make-rule "add-zero" '(add ?x 0) '?x)]
       [r2 (make-rule "mul-zero" '(mul ?x 0) '0)])
  (ruleset-add! rs r1)
  (ruleset-add! rs r2)

  (test "rewrite nested"
    (rewrite rs '(add (add 5 0) 0))
    5)

  (test "rewrite mul-zero"
    (rewrite rs '(mul (add 3 0) 0))
    '0))

;;; ---- rewrite-fixed-point ----

(let* ([rs (make-ruleset)])
  (ruleset-add! rs (make-rule "double" '(double ?x) '(add ?x ?x)))
  (ruleset-add! rs (make-rule "add-zero" '(add ?x 0) '?x))

  (test "rewrite-fixed-point"
    (rewrite-fixed-point rs '(double 5))
    '(add 5 5)))

;;; ---- normalize ----

(let* ([rs (make-ruleset)])
  (ruleset-add! rs (make-rule "add-zero" '(add ?x 0) '?x))
  (ruleset-add! rs (make-rule "mul-one" '(mul ?x 1) '?x))

  (test "normalize"
    (normalize rs '(mul (add 7 0) 1))
    7))

(printf "~%Rewrite tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
