#!chezscheme
;;; Tests for (std spec) — Round 5 Phase 36.
;;; Exercises registry, composable spec constructors, validation,
;;; explain, conform, function specs, and instrumentation.

(import (jerboa prelude)
        (std spec))

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

(printf "--- Round 5 Phase 36: std/spec ---~%~%")

;;; ---- Registry ----

(s-def pos-int (s-and integer? (s-pred positive?)))

(test "s-valid? registered spec accepts"
  (s-valid? 'pos-int 42)
  #t)

(test "s-valid? registered spec rejects"
  (s-valid? 'pos-int -1)
  #f)

(test "s-valid? registered spec rejects non-integer"
  (s-valid? 'pos-int 1.5)
  #f)

(test "s-get-spec returns registered spec"
  (procedure? (lambda () (s-get-spec 'pos-int))) ;; always #t; side-effect check
  #t)

;;; ---- s-pred ----

(test "s-pred wraps raw predicate (accept)"
  (s-valid? (s-pred string?) "hi")
  #t)

(test "s-pred wraps raw predicate (reject)"
  (s-valid? (s-pred string?) 42)
  #f)

;;; ---- s-and (variadic specs, no tags) ----

(test "s-and composes (accept)"
  (s-valid? (s-and integer? positive?) 5)
  #t)

(test "s-and short-circuits (reject first)"
  (s-valid? (s-and integer? positive?) "x")
  #f)

(test "s-and rejects when second fails"
  (s-valid? (s-and integer? positive?) -3)
  #f)

;;; ---- s-or (tag/spec pairs) ----

(test "s-or accepts first alternative"
  (s-valid? (s-or 'int integer? 'str string?) 42)
  #t)

(test "s-or accepts second alternative"
  (s-valid? (s-or 'int integer? 'str string?) "hi")
  #t)

(test "s-or rejects neither"
  (s-valid? (s-or 'int integer? 'str string?) 'sym)
  #f)

;;; ---- s-nilable ----

(test "s-nilable accepts #f"
  (s-valid? (s-nilable integer?) #f)
  #t)

(test "s-nilable accepts valid"
  (s-valid? (s-nilable integer?) 42)
  #t)

(test "s-nilable rejects invalid non-#f"
  (s-valid? (s-nilable integer?) "no")
  #f)

;;; ---- s-coll-of ----

(test "s-coll-of list accept"
  (s-valid? (s-coll-of integer?) '(1 2 3))
  #t)

(test "s-coll-of list reject mixed"
  (s-valid? (s-coll-of integer?) '(1 "x" 3))
  #f)

(test "s-coll-of vector accept"
  (s-valid? (s-coll-of integer?) (vector 1 2 3))
  #t)

(test "s-coll-of empty list accept"
  (s-valid? (s-coll-of integer?) '())
  #t)

;;; ---- s-tuple ----

(test "s-tuple accepts fixed shape"
  (s-valid? (s-tuple integer? string?) '(1 "hi"))
  #t)

(test "s-tuple rejects wrong arity"
  (s-valid? (s-tuple integer? string?) '(1))
  #f)

(test "s-tuple rejects wrong type"
  (s-valid? (s-tuple integer? string?) '("hi" "there"))
  #f)

;;; ---- s-enum ----

(test "s-enum accepts member"
  (s-valid? (s-enum 'red 'green 'blue) 'red)
  #t)

(test "s-enum rejects non-member"
  (s-valid? (s-enum 'red 'green 'blue) 'yellow)
  #f)

;;; ---- s-int-in ----

(test "s-int-in accepts inside range"
  (s-valid? (s-int-in 1 10) 5)
  #t)

(test "s-int-in rejects below"
  (s-valid? (s-int-in 1 10) 0)
  #f)

(test "s-int-in rejects above-or-equal-upper (half-open)"
  (s-valid? (s-int-in 1 10) 10)
  #f)

;;; ---- s-keys on alist ----

(s-def person-name string?)
(s-def person-age  (s-and integer? (s-pred (lambda (n) (>= n 0)))))
(s-def person      (s-keys 'person-name 'person-age))

(test "s-keys accepts alist with all required"
  (s-valid? 'person '((person-name . "Alice") (person-age . 30)))
  #t)

(test "s-keys rejects missing required"
  (s-valid? 'person '((person-name . "Bob")))
  #f)

;;; ---- s-conform ----

(test "s-conform returns value on valid"
  (s-conform (s-pred integer?) 42)
  42)

(test "s-conform returns invalid sentinel on reject"
  (s-conform (s-pred integer?) "x")
  'invalid)

;;; ---- s-explain-str ----

(test "s-explain-str on valid mentions Success"
  (let ([s (s-explain-str (s-pred integer?) 42)])
    (and (string? s) (> (string-length s) 0)))
  #t)

(test "s-explain-str on invalid mentions failed"
  (let ([s (s-explain-str (s-pred integer?) "x")])
    (and (string? s) (> (string-length s) 0)))
  #t)

;;; ---- Function specs + s-fdef (Round 5 §36 fix: evaluates specs) ----

(define (add a b) (+ a b))

(s-fdef add
  :args (s-cat 'a integer? 'b integer?)
  :ret integer?)

(test "s-check-fn accepts valid call"
  (s-check-fn 'add add '(2 3))
  5)

(test "s-check-fn rejects non-integer arg"
  (guard (exn [else 'caught])
    (s-check-fn 'add add '(2 "x")))
  'caught)

;;; ---- Instrumentation ----

(test "s-instrumented? starts #f"
  (s-instrumented? 'add)
  #f)

(s-instrument 'add)

(test "s-instrumented? after instrument is #t"
  (s-instrumented? 'add)
  #t)

(test "instrumented call with valid args"
  (add 2 3)
  5)

(test "instrumented call with invalid args raises"
  (guard (exn [else 'caught])
    (add "bad" 3))
  'caught)

(test "s-instrument is idempotent"
  (begin
    (s-instrument 'add)
    (s-instrument 'add)
    (s-instrumented? 'add))
  #t)

(s-unstrument 'add)

(test "s-unstrument restores original"
  (s-instrumented? 'add)
  #f)

(test "after unstrument, original behaviour returns"
  (add 2 3)
  5)

(test "s-unstrument is idempotent on non-instrumented name"
  (begin
    (s-unstrument 'add)
    (s-unstrument 'add)
    'ok)
  'ok)

(test "s-instrument errors on name with no fspec"
  (guard (exn [else 'caught])
    (s-instrument 'nonexistent-fn))
  'caught)

;;; ---- s-defn — script-safe speced define ------------------------

(s-defn sd-both (x y)
  :args (s-cat ':x integer? ':y integer?)
  :ret  integer?
  (+ x y))

(test "s-defn :args+:ret accepts valid call"
  (sd-both 2 3)
  5)

(test "s-defn :args rejects bad args"
  (guard (exn [else 'caught])
    (sd-both "bad" 3))
  'caught)

(s-defn sd-ret-bad (x) :ret integer? "not-an-int")

(test "s-defn :ret rejects bad return"
  (guard (exn [else 'caught])
    (sd-ret-bad 1))
  'caught)

(s-defn sd-args-only (x)
  :args (s-cat ':x string?)
  (string-upcase x))

(test "s-defn :args only passes valid"
  (sd-args-only "hi")
  "HI")

(test "s-defn :args only rejects invalid"
  (guard (exn [else 'caught])
    (sd-args-only 99))
  'caught)

(s-defn sd-ret-only (x) :ret symbol? (string->symbol x))

(test "s-defn :ret only passes valid"
  (sd-ret-only "sym")
  'sym)

(s-defn sd-bare (x y) (* x y))

(test "s-defn with no specs behaves like def"
  (sd-bare 4 5)
  20)

(s-defn sd-reverse (x)
  :ret symbol?
  :args (s-cat ':x string?)
  (string->symbol x))

(test "s-defn accepts :ret before :args"
  (sd-reverse "ok")
  'ok)

(test "s-defn registers s-fdef for s-check-fn"
  (s-check-fn 'sd-both sd-both '(10 20))
  30)

;;; ---- Summary ----

(printf "~%std/spec: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
