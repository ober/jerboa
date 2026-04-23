# Jerboa Anti-Cookbook

_Patterns that look right but aren't. Each entry shows **wrong** code a
reasonable LLM/Schemer would write, then the **correct** Jerboa form and
why it matters. Focused on multi-form pitfalls; single-identifier
hallucinations live in [`divergence.md`](divergence.md)._

---

## 1. `(hash-ref key ht)` — arg order reversed

**Wrong** (Clojure/Racket order):
```scheme
(hash-ref "name" h)
```
**Correct** (Jerboa/Gerbil order: container first):
```scheme
(hash-ref h "name")
(hash-ref h "name" "default")   ; optional default
```
**Why:** Jerboa follows Chez/Gerbil "container first" convention. Clojure is
the odd one out.

---

## 2. `(sort lst <)` — arg order reversed

**Wrong** (SRFI-95 / Clojure / Gerbil order):
```scheme
(sort '(3 1 2) <)
```
**Correct** (Chez order: comparator first):
```scheme
(sort < '(3 1 2))
```
**Why:** `(std sort)` matches Chez, not SRFI-95. LLMs trained on Gerbil
reliably get this wrong — and the wrong form compiles silently then
crashes at runtime with a type error because `<` is being applied as
`(< '(3 1 2) <)`.

---

## 3. `((list-of? number?) '(1 2 3))` — factory, not predicate

**Wrong:**
```scheme
(list-of? number? '(1 2 3))     ; arity error
```
**Correct:**
```scheme
((list-of? number?) '(1 2 3))   ; → #t
```
**Why:** `list-of?` and `maybe` are predicate **factories**: they take one
argument and return a predicate. Same for `maybe`, `one-of?`.

---

## 4. `(string-contains "abc" "b")` returns an index, not a boolean

**Wrong:**
```scheme
(when (string-contains s "needle")
  ...)
```
**Correct** — `(string-contains s sub)` returns an index or `#f`, and
`0` is truthy in Scheme, so `(when (string-contains ...))` works:
```scheme
(when (string-contains s "needle")
  ...)
```
For an explicit predicate (and to avoid confusion with JS/Python where
`0` is falsy), import the predicate form:
```scheme
(import (std misc string-more))     ; NOT in the prelude
(string-contains? s "needle")       ; → #t/#f
```
**Why:** `string-contains` returns the match **index** (or `#f`). The
predicate form `string-contains?` lives in `(std misc string-more)`, not
the prelude. Prefer the explicit predicate when writing code others will
skim.

---

## 5. `(string-split "a,b" ",")` — delimiter must be a **char**

**Wrong:**
```scheme
(string-split "a,b,c" ",")      ; passes a string
```
**Correct:**
```scheme
(string-split "a,b,c" #\,)      ; passes a char
```
**Why:** Unlike Python / Racket / Clojure, Jerboa's `string-split` takes
a `char` delimiter, not a string. For multi-char delimiters, use
`(re-split "…" s)` from the prelude.

---

## 6. `(raise "message")` — won't produce a readable error

**Wrong:**
```scheme
(raise "something went wrong")       ; raises a string condition
```
**Correct:**
```scheme
(error 'my-func "something went wrong" irritant1 irritant2)
```
**Why:** `raise` with a bare string propagates a string as the condition
object; downstream `(condition-message c)` returns `#f`. `error`
constructs a proper `&message`/`&irritants` condition with who/what/why
structure.

---

## 7. `let` with multiple RHS forms referencing each other

**Wrong** (expects Clojure's `let` or Racket's `let*`):
```scheme
(let ((x 1)
      (y (+ x 1)))          ; x not in scope here!
  (* y 2))
```
**Correct**:
```scheme
(let* ((x 1)
       (y (+ x 1)))
  (* y 2))
```
**Why:** Scheme `let` binds all RHSs in parallel (no access to earlier
bindings). `let*` is sequential. `letrec` is mutually recursive. Pick
the right one.

---

## 8. `(for ((x lst)) ...)` without an iterator

**Wrong:**
```scheme
(for ((x '(1 2 3)))         ; raw list, not an iterator
  (displayln x))
```
**Correct:**
```scheme
(for ((x (in-list '(1 2 3))))
  (displayln x))
```
**Why:** `for` works with **iterator expressions**, not raw data. Use
`in-list`, `in-vector`, `in-string`, `in-range`, `in-hash-keys`,
`in-hash-values`, `in-hash-pairs`, `in-naturals`, `in-indexed`,
`in-port`, `in-lines`, `in-chars`, `in-bytes`.

---

## 9. `(match val [list a b])` — missing inner parens

**Wrong** (Clojure-ish, drops pattern constructor):
```scheme
(match val
  ([a b c] "three")          ; [a b c] is a bracket-list — this DOES match
  (else "other"))             ; but this form is fragile
```
**Correct**:
```scheme
(match val
  ((list a b c) (+ a b c))
  ((cons h t) h)
  (_ 'other))
```
**Why:** Use explicit pattern constructors (`list`, `cons`, `vector`,
`?`, `and`, `or`). Bare bracket-lists work under stock Chez reader but
are a syntax error under the Jerboa reader (which rewrites `[...]` →
`(list ...)`).

---

## 10. `(catch e ...)` — `try` needs a clause form

**Wrong** (Java/JavaScript-ish):
```scheme
(try
  (do-thing)
  (catch e (handle e)))      ; catch takes a BINDING LIST
```
**Correct**:
```scheme
(try
  (do-thing)
  (catch (e) (handle e))                 ; any exception, bound to e
  (catch (error? e) (handle-error e))    ; predicate filter
  (finally (cleanup)))
```
**Why:** `catch` takes either `(var)` or `(pred var)` as the binding
form. The classic mistake is writing `(catch e ...)` which parses as a
predicate of one argument — often silently.

---

## 11. `(make-rwlock 'my-lock)` — no name argument

**Wrong** (Gerbil):
```scheme
(make-rwlock 'cache-lock)    ; Gerbil accepts a name; Jerboa does not
```
**Correct**:
```scheme
(make-rwlock)                 ; zero args
```
**Why:** Jerboa's `make-rwlock` is a 0-argument procedure. For debug
identity, wrap with your own `(defstruct named-rwlock (lock name))`.

---

## 12. `(path-expand relpath base)` — only 1 arg

**Wrong** (Gerbil):
```scheme
(path-expand "foo.txt" "/home/user")
```
**Correct**:
```scheme
(path-expand "foo.txt")            ; absolute-ify against CWD
(path-join "/home/user" "foo.txt") ; the Jerboa way to combine
```
**Why:** `path-expand` is unary; use `path-join` for concatenation.

---

## 13. `(thread-sleep! 1.0)` — not a thing

**Wrong** (Gambit):
```scheme
(thread-sleep! 2.5)
```
**Correct**:
```scheme
(sleep (make-time 'time-duration 500000000 2))   ; 2.5 seconds
;; or
(import (std misc thread))
(thread-sleep! 2.5)                              ; Gambit-compat export
```
**Why:** Stock Jerboa prelude uses Chez's `sleep` which takes a `time`
object. The Gambit spelling works only when you explicitly import
`(std misc thread)`.

---

## 14. `(with-resource port open-port close-port)` — arg order

**Wrong** (looks like Lisp `with-slots`):
```scheme
(with-resource port (open-file "x.txt") (close-port port)
  body)
```
**Correct**:
```scheme
(with-resource (port (open-file "x.txt") close-port)
  (read-all port))
```
**Why:** The first form is a 3-element **binding list**: `(var init
cleanup-proc)`. `cleanup-proc` is a procedure taking the resource, not
an expression.

---

## 15. Hash-table iteration: iterator vs callback

**Wrong** (mixes APIs):
```scheme
(for ((k v) (in-hash ht))     ; in-hash is not a Jerboa iterator name
  ...)
```
**Correct**:
```scheme
;; Callback style:
(hash-for-each (lambda (k v) ...) ht)

;; Iterator style:
(for (((k v) (in-hash-pairs ht)))      ; note the double parens
  ...)
(for ((k (in-hash-keys ht))) ...)
(for ((v (in-hash-values ht))) ...)
```
**Why:** Racket's `(in-hash h)` does not exist in Jerboa. Use one of the
three explicit iterators, or go callback-style with `hash-for-each`.

---

## 16. `(displayln x y z)` — correct, but subtle

**Wrong assumption:** "`displayln` takes one arg and newline."
Actually correct code:
```scheme
(displayln "answer: " 42 "!")
```
Prints `answer: 42!` followed by newline. Jerboa's `displayln` is
variadic and concatenates display-formatted args — similar to `print`
in Racket. If you want `display` semantics + explicit newline, use:
```scheme
(display x) (newline)
```

---

## 17. `(ok 1 2)` / `(err)` — Result is unary

**Wrong**:
```scheme
(ok 1 2 3)                 ; arity error
(err)                      ; arity error
```
**Correct**:
```scheme
(ok (list 1 2 3))          ; pack multiple values
(err "reason")             ; always one payload
```
**Why:** `ok` / `err` wrap exactly one value. Multiple results must be
packed into a list, vector, or record.

---

## 18. Quasi-regex: `re-match?` vs `re-search`

**Wrong assumption:** "`re-match?` returns a match object."
```scheme
(let ((m (re-match? #/\d+/ "abc 42")))
  (match-group m 0))                     ; m is #t, not a match obj
```
**Correct**:
```scheme
(let ((m (re-search "\\d+" "abc 42")))   ; returns match-obj or #f
  (when m (re-match-group m 0)))          ; → "42"

(re-match? "\\d+" "42")                  ; → #t  (full-string match only)
(re-match? "\\d+" "abc 42")              ; → #f  (must match ENTIRE string)
```
**Why:** `re-match?` is a boolean **full-string** match. `re-search`
finds a substring match and returns a match object. `re-find-all`
returns all matches as strings.

---

## 19. `(format "~s" x)` — `~s` vs `~a`

**Same as Common Lisp, but worth calling out:**
```scheme
(format "~a" "hi")    ; → "hi"        (display)
(format "~s" "hi")    ; → "\"hi\""    (write — readable)
(format "~%")         ; → "\n"
(format "~a, ~a" 1 2) ; → "1, 2"
```
Do not use `{}` (Python), `%s` (C), or `${…}` (JS) — Jerboa's `format`
is CL/Racket style only.

---

## 20. `(defstruct point (x y))` defines a constructor named `make-point`

**Wrong assumption:** "the constructor is `point`."
```scheme
(defstruct point (x y))
(point 1 2)              ; undefined — `point` is the predicate maker
```
**Correct**:
```scheme
(defstruct point (x y))
(define p (make-point 1 2))
(point? p)               ; → #t
(point-x p)              ; → 1           accessor
(point-x-set! p 99)      ; → unspecified  mutator
```
**Why:** The macro generates names by convention: `make-NAME`, `NAME?`,
`NAME-FIELD`, `NAME-FIELD-set!`. Verify with `jerboa_class_info` if in
doubt. Do **not** assume Racket's `set-NAME-FIELD!` order.
