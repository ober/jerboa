#!chezscheme
;;; Tests for (std peg) — PEG grammar system

(import (chezscheme)
        (std peg))

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

(define-syntax test-t (syntax-rules () [(_ n e) (test n (if e #t #f) #t)]))
(define-syntax test-f (syntax-rules () [(_ n e) (test n (if e #t #f) #f)]))
(define-syntax test-err
  (syntax-rules ()
    [(_ name expr)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: expected peg-error, got exception: ~a~%" name exn)])
       (let ([got expr])
         (if (peg-error? got)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: expected peg-error, got ~s~%" name got)))))]))

(printf "--- (std peg) grammar system ---~%~%")

;;; ========== Basic single-rule grammars ==========

(printf "  -- literal matching --~%")

(define-grammar lit-test
  (hello "hello"))

(test "literal: hello" (lit-test:hello "hello") "hello")
(test-err "literal: no match" (lit-test:hello "world"))
(test-err "literal: partial" (lit-test:hello "helloworld"))

;;; ========== Sequences ==========

(printf "~%  -- sequences --~%")

(define-grammar seq-test
  (ab "a" "b")
  (abc "a" "b" "c"))

(test "seq: ab" (seq-test:ab "ab") "ab")
(test "seq: abc" (seq-test:abc "abc") "abc")
(test-err "seq: missing char" (seq-test:ab "a"))

;;; ========== Ordered choice ==========

(printf "~%  -- ordered choice (or) --~%")

(define-grammar choice-test
  (bool (or "true" "false"))
  (sign (or "+" "-" "")))

(test "or: true"  (choice-test:bool "true")  "true")
(test "or: false" (choice-test:bool "false") "false")
(test-err "or: neither"  (choice-test:bool "maybe"))
(test "or: plus"  (choice-test:sign "+") "+")
(test "or: minus" (choice-test:sign "-") "-")
(test "or: empty" (choice-test:sign "")  "")

;;; ========== Repetition ==========

(printf "~%  -- repetition (* + ? = **) --~%")

(define-grammar rep-test
  (digits  (+ (/ #\0 #\9)))
  (letters (* (/ #\a #\z)))
  (opt-x   (? "x") "y")
  (exactly3 (= 3 (/ #\a #\z)))
  (two-to-four (** 2 4 (/ #\0 #\9))))

(test "plus: 123"   (rep-test:digits "123") "123")
(test "plus: single" (rep-test:digits "9") "9")
(test-err "plus: empty" (rep-test:digits ""))
(test "star: abc"  (rep-test:letters "abc") "abc")
(test "star: empty" (rep-test:letters "") "")
(test "opt+y: xy"  (rep-test:opt-x "xy") "xy")
(test "opt+y: y"   (rep-test:opt-x "y")  "y")
(test-err "opt+y: x only" (rep-test:opt-x "x"))
(test "exactly 3"  (rep-test:exactly3 "abc") "abc")
(test-err "exactly 3: 2 chars" (rep-test:exactly3 "ab"))
(test "** 2-4: 2 digits" (rep-test:two-to-four "12") "12")
(test "** 2-4: 3 digits" (rep-test:two-to-four "123") "123")
(test "** 2-4: 4 digits" (rep-test:two-to-four "1234") "1234")
(test-err "** 2-4: 1 digit" (rep-test:two-to-four "1"))

;;; ========== Not predicate ==========

(printf "~%  -- predicates (! and &) --~%")

(define-grammar pred-test
  ;; Match any char that isn't a digit
  (non-digit (! (/ #\0 #\9)) any)
  ;; Match only if next char is a digit, but don't consume
  (before-digit (& (/ #\0 #\9)) any))

(test "not pred: letter" (pred-test:non-digit "a") "a")
(test-err "not pred: digit" (pred-test:non-digit "5"))
(test "and pred: digit"  (pred-test:before-digit "5") "5")
(test-err "and pred: letter" (pred-test:before-digit "a"))

;;; ========== Named captures ==========

(printf "~%  -- named captures (=>) --~%")

(define-grammar capture-test
  (pair (=> key (+ (/ #\a #\z))) "=" (=> value (+ (/ #\0 #\9)))))

(let ([result (capture-test:pair "foo=123")])
  (test-t "capture result is alist" (list? result))
  (test "capture: key"   (cdr (assq 'key result))   "foo")
  (test "capture: value" (cdr (assq 'value result)) "123"))

(define-grammar date-parser
  (date (=> year  (= 4 (/ #\0 #\9))) "-"
        (=> month (= 2 (/ #\0 #\9))) "-"
        (=> day   (= 2 (/ #\0 #\9)))))

(let ([result (date-parser:date "2026-04-09")])
  (test "date: year"  (cdr (assq 'year  result)) "2026")
  (test "date: month" (cdr (assq 'month result)) "04")
  (test "date: day"   (cdr (assq 'day   result)) "09"))

;;; ========== Drop ==========

(printf "~%  -- (drop ...) --~%")

(define-grammar drop-test
  ;; Quoted string: drop the quotes, keep the content
  (qstr (drop "\"") (* (~ "\"")) (drop "\"")))

(test "drop quotes"      (drop-test:qstr "\"hello\"")       "hello")
(test "drop empty str"   (drop-test:qstr "\"\"")            "")
(test "drop with spaces" (drop-test:qstr "\"hello world\"") "hello world")
(test-err "drop unclosed" (drop-test:qstr "\"oops"))

;;; ========== Complement (~ ...) ==========

(printf "~%  -- complement (~~ ...) --~%")

(define-grammar comp-test
  (not-comma   (+ (~ ",")))
  (not-newline (+ (~ "\n"))))

(test "not-comma: abc"     (comp-test:not-comma "abc")   "abc")
(test "not-newline: hello" (comp-test:not-newline "hello") "hello")
(test-err "not-comma: starts with comma" (comp-test:not-comma ",abc"))

;;; ========== sep-by ==========

(printf "~%  -- sep-by --~%")

(define-grammar sepby-test
  (csv-row (sep-by (+ (~ (or "," "\n"))) ",")))

(test "sep-by: a,b,c" (sepby-test:csv-row "a,b,c") '("a" "b" "c"))
(test "sep-by: single" (sepby-test:csv-row "a")    '("a"))
(test "sep-by: empty"  (sepby-test:csv-row "")     '())

;;; ========== Mutual recursion ==========

(printf "~%  -- mutual recursion --~%")

;; Nested parentheses: () (()) ((())) etc.
(define-grammar parens
  (expr (or nested empty))
  (nested "(" expr ")")
  (empty ""))

(test "parens: empty"    (parens:expr "")      "")
(test "parens: ()"       (parens:expr "()")    "()")
(test "parens: (())"     (parens:expr "(())")  "(())")
(test "parens: ((()))"   (parens:expr "((()))") "((()))")

;;; ========== Error reporting ==========

(printf "~%  -- error reporting --~%")

(define-grammar err-test
  (digits (+ (/ #\0 #\9))))

(let ([result (err-test:digits "abc")])
  (test-t "error is peg-error?" (peg-error? result))
  (test-t "error has position" (number? (peg-error-position result)))
  (test-t "error has input"    (string? (peg-error-input result)))
  (test-t "error has message"  (string? (peg-error-message result))))

;;; ========== Full CSV integration test ==========

(printf "~%  -- CSV integration test --~%")

(define-grammar csv
  (file        (+ row))
  (row         (sep-by field ",") (drop "\n"))
  (field       (or quoted-field plain-field))
  (quoted-field (drop "\"") (* (~ "\"")) (drop "\""))
  (plain-field  (* (~ (or "," "\n")))))

(test "csv: one row"
  (csv:file "Alice,30\n")
  '(("Alice" "30")))

(test "csv: multiple rows"
  (csv:file "name,age\nAlice,30\nBob,25\n")
  '(("name" "age") ("Alice" "30") ("Bob" "25")))

(test "csv: quoted field"
  (csv:file "\"hello, world\",42\n")
  '(("hello, world" "42")))

(test "csv: empty field"
  (csv:file "a,,c\n")
  '(("a" "" "c")))

;;; ========== Summary ==========
(newline)
(printf "Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
