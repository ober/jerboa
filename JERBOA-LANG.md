# The Jerboa Programming Language

Jerboa is a Scheme dialect built on Chez Scheme. It is Gerbil-inspired but its own
language — with features that differ from and exceed Gerbil. All user-facing code is
written in `.ss` files. The `.sls` files are implementation internals.

## Quick Start

```scheme
;; hello.ss
(import (jerboa prelude))

(def (main)
  (def name "world")
  (displayln (str "Hello, " name "!")))

(main)
```

Run with:
```
scheme --libdirs lib --script hello.ss
```

One import gives you the entire language:
```scheme
(import (jerboa prelude))
```

---

## Table of Contents

1. [File Structure](#file-structure)
2. [Reader Syntax](#reader-syntax)
3. [Definitions](#definitions)
4. [Data Structures](#data-structures)
5. [Pattern Matching](#pattern-matching)
6. [Control Flow](#control-flow)
7. [Error Handling](#error-handling)
8. [Result Types](#result-types)
9. [Iterators](#iterators)
10. [Threading Macros](#threading-macros)
11. [Ergonomic Typing](#ergonomic-typing)
12. [Hash Tables](#hash-tables)
13. [Functions & Combinators](#functions--combinators)
14. [Standard Library](#standard-library)
15. [FFI](#ffi)
16. [Differences from Gerbil](#differences-from-gerbil)
17. [Differences from Chez Scheme](#differences-from-chez-scheme)

---

## File Structure

A Jerboa `.ss` file has this shape:

```scheme
(import (jerboa prelude))
;; Optional extra imports for modules not in the prelude:
;; (import (std net request))
;; (import (std db sqlite))

;; Definitions
(def (my-function x y)
  (+ x y))

;; Top-level code
(displayln (my-function 1 2))
```

Key points:
- **No `(library ...)` wrapper** — that's for `.sls` internals only
- **`(import (jerboa prelude))`** gives you everything: core macros, runtime,
  result types, datetime, iterators, CSV, pretty-printer, JSON, paths, strings,
  lists, alists, hash tables, functional combinators, ergo typing, FFI, and more
- For specialized modules not in the prelude, add extra imports

---

## Reader Syntax

Jerboa extends the Chez Scheme reader with Gerbil-inspired syntax.

### Square Brackets → List Literals

```scheme
[1 2 3]           ;; → (list 1 2 3)
[]                ;; → (list)
[a [b c]]         ;; → (list a (list b c))
```

### Curly Braces → Method Dispatch

```scheme
{draw canvas}           ;; → (~ canvas 'draw)
{move sprite 10 20}     ;; → (~ sprite 'move 10 20)
{name person}            ;; → (~ person 'name)
```

### Keywords (trailing colon)

```scheme
name:             ;; → keyword object #:name
color:            ;; → keyword object #:color
(keyword? name:)  ;; → #t
```

### Module Paths (Gerbil-style)

```scheme
:std/sort               ;; → (std sort)
:std/text/json          ;; → (std text json)
:std/misc/string        ;; → (std misc string)
```

Both forms work in `import`:
```scheme
(import :std/net/request)     ;; Gerbil style
(import (std net request))    ;; R6RS style — both are equivalent
```

### Heredoc Strings

```scheme
#<<END
This is a multi-line
string literal.
END
```

### Standard Scheme Syntax

All standard Chez Scheme reader features work:
- `'expr` — quote
- `` `expr `` — quasiquote, with `,expr` unquote and `,@expr` splicing
- `#(1 2 3)` — vector
- `#u8(1 2 3)` — bytevector
- `#\space`, `#\newline`, `#\x41` — characters
- `#xFF`, `#b1010`, `#o77` — number radix prefixes
- `#;expr` — datum comment (skip next form)
- `#| ... |#` — block comment (nestable)
- `#&value` — box
- `#!void`, `#!eof` — void and eof literals

---

## Definitions

### `def` — Define Variables and Functions

```scheme
;; Simple binding
(def x 42)
(def name "Alice")

;; Function
(def (add a b)
  (+ a b))

;; Optional parameters (default values)
(def (greet name (greeting "hello"))
  (str greeting ", " name "!"))

(greet "Bob")           ;; → "hello, Bob!"
(greet "Bob" "howdy")   ;; → "howdy, Bob!"

;; Rest arguments
(def (first-and-rest first . rest)
  (list first rest))

;; Type-checked parameters (via ergo)
(def (add (x : number?) (y : number?)) : number?
  (+ x y))
```

### `def*` — Multiple Arities

```scheme
(def* greet
  ((name) (greet name "hello"))
  ((name greeting) (str greeting ", " name "!")))
```

### `defrule` / `defrules` — Define Macros

```scheme
;; Single-pattern macro
(defrule (swap! a b)
  (let ((tmp a)) (set! a b) (set! b tmp)))

;; Multi-pattern macro
(defrules my-or ()
  ((_ a) a)
  ((_ a b ...) (let ((t a)) (if t t (my-or b ...)))))
```

---

## Data Structures

### `defstruct` — Record Types

```scheme
(defstruct point (x y))

;; Generated:
;;   make-point   — constructor
;;   point?       — predicate
;;   point-x      — accessor
;;   point-y      — accessor
;;   point-x-set! — mutator
;;   point-y-set! — mutator
;;   point::t     — record type descriptor

(def p (make-point 3 4))
(point-x p)              ;; → 3
(point-y-set! p 10)
(point-y p)              ;; → 10
```

### Inheritance

```scheme
(defstruct shape (color))
(defstruct (circle shape) (radius))

(def c (make-circle "red" 5))
(shape-color c)     ;; → "red"   (inherited field)
(circle-radius c)   ;; → 5
(shape? c)          ;; → #t
(circle? c)         ;; → #t
```

Only **single inheritance** is supported.

### `defclass` — Alias for `defstruct`

```scheme
(defclass point (x y))          ;; same as defstruct
(defclass (circle shape) (r))   ;; same as defstruct with parent
```

### `defrecord` — Struct with Pretty Printing

```scheme
(defrecord person (name age))

;; Same as defstruct plus:
;;   person->alist — convert to association list
;;   Custom printer: #<person name="Alice" age=30>
```

### `defmethod` — Method Dispatch

```scheme
(defstruct circle (radius))
(defstruct rect (width height))

(defmethod (area (self circle))
  (* 3.14159 (expt (circle-radius self) 2)))

(defmethod (area (self rect))
  (* (rect-width self) (rect-height self)))

;; Call with ~ or {} syntax
(def c (make-circle 5))
(~ c 'area)              ;; → 78.53975
{area c}                 ;; → 78.53975 (same thing)

;; Methods with extra args
(defmethod (move (self point) dx dy)
  (make-point (+ (point-x self) dx)
              (+ (point-y self) dy)))

{move p 10 20}           ;; → new point shifted by (10, 20)
```

Method dispatch walks the inheritance chain — a method defined on `shape`
works on `circle` too.

### `define-enum` — Enumeration Types

```scheme
(define-enum color (red green blue))

;; Generated:
;;   color-red   → 0
;;   color-green → 1
;;   color-blue  → 2
;;   color?      — predicate (checks 0..2)
;;   color->name — number to string
;;   name->color — string to number
```

---

## Pattern Matching

### `match`

```scheme
(match value
  ;; Literal patterns
  (0 "zero")
  (#t "true")
  ("hello" "greeting")

  ;; Variable binding
  (x (str "got: " x)))

;; List destructuring
(match (list 1 2 3)
  ((list a b c) (+ a b c)))     ;; → 6

;; Nested patterns
(match '(1 (2 3))
  ((list a (list b c)) (+ a b c)))  ;; → 6

;; Cons patterns
(match '(1 2 3)
  ((cons head tail) head))     ;; → 1

;; Predicate patterns
(match 42
  ((? string?) "a string")
  ((? number?) "a number"))    ;; → "a number"

;; Guards
(match x
  (n (where (> n 0)) "positive")
  (n (where (< n 0)) "negative")
  (_ "zero"))

;; Logical combinators
(match x
  ((and (? number?) (? positive?)) "positive number")
  ((or "yes" "y" "true") #t)
  ((not #f) "truthy"))

;; Wildcard
(match x
  (_ "anything"))

;; View patterns — apply function, match result
(match "123"
  ((=> string->number n) (+ n 1)))  ;; → 124

;; Struct patterns (requires define-match-type registration)
(define-match-type point point? point-x point-y)
(match (make-point 3 4)
  ((point x y) (+ x y)))       ;; → 7
```

### `match/strict` — Exhaustiveness-Checked Matching

```scheme
(define-sealed-hierarchy shape
  (circle circle? circle-radius)
  (rect rect? rect-width rect-height))

(match/strict shape my-shape
  ((circle r) (* 3.14 r r))
  ((rect w h) (* w h)))
;; Warns at runtime if a variant is missing
```

### `define-active-pattern` — Custom Extractors

```scheme
(define-active-pattern (even? n)
  (and (number? n) (zero? (mod n 2)) n))

(match 42
  ((even? n) (str n " is even")))
```

---

## Control Flow

### Conditionals

```scheme
;; Standard
(if test then else)
(cond (test1 expr1) (test2 expr2) (else default))
(when test body ...)
(unless test body ...)

;; Anaphoric — binds result to `it`
(awhen (find-user name)
  (send-email it))

(aif (lookup key)
  (use it)
  (handle-missing))

;; Conditional binding
(when-let (x (get-thing))
  (process x))

(if-let (user (find-user id))
  (greet user)
  (show-login))
```

### Loops

```scheme
;; Counted loop
(dotimes (i 10)
  (displayln i))        ;; prints 0..9

;; While/until
(while (< x 10)
  (set! x (+ x 1)))

(until (> x 10)
  (set! x (+ x 1)))

;; Iterators (see Iterators section)
(for ((x (in-range 10)))
  (displayln x))
```

### `assert!`

```scheme
(assert! (> x 0))                ;; raises error if false
(assert! (> x 0) "x must be positive")  ;; with message
```

---

## Error Handling

### `try` / `catch` / `finally`

```scheme
;; Basic try/catch
(try
  (risky-operation)
  (catch (e)
    (displayln "Error: " (error-message e))))

;; With predicate
(try
  (/ 1 0)
  (catch (error? e)
    (displayln "caught: " e)))

;; With finally (always runs)
(try
  (def port (open-input-file "data.txt"))
  (process port)
  (catch (e)
    (displayln "failed"))
  (finally
    (close-input-port port)))
```

### Resource Management

```scheme
;; Guaranteed cleanup
(unwind-protect
  (do-work)
  (cleanup))

;; Resource lifecycle
(with-resource (port (open-input-file "f.txt") close-input-port)
  (read-all-as-string port))

;; Mutex
(with-lock my-mutex
  (modify-shared-state))
```

---

## Result Types

Rust-inspired `Result<T,E>` for composable error handling without exceptions.

### Constructors & Predicates

```scheme
(ok 42)           ;; success value
(err "not found") ;; error value

(ok? (ok 42))     ;; → #t
(err? (err "x"))  ;; → #t
(result? (ok 1))  ;; → #t
```

### Extracting Values

```scheme
(unwrap (ok 42))                 ;; → 42
(unwrap (err "x"))               ;; raises error!

(unwrap-or (err "x") 0)         ;; → 0  (safe default)
(unwrap-or-else (err "x")
  (lambda () (compute-default))) ;; → lazy default

(unwrap-err (err "bad"))         ;; → "bad"
```

### Transforming Results

```scheme
;; Map over ok values
(map-ok (lambda (x) (* x 2)) (ok 5))     ;; → (ok 10)
(map-ok (lambda (x) (* x 2)) (err "x"))  ;; → (err "x")

;; Map over error values
(map-err string-upcase (err "bad"))       ;; → (err "BAD")

;; Monadic bind (chain operations)
(and-then (ok 5) (lambda (x)
  (if (> x 0) (ok (* x 2)) (err "negative"))))
;; → (ok 10)

;; Error recovery
(or-else (err "bad") (lambda (e) (ok 0)))  ;; → (ok 0)
```

### Exception ↔ Result Conversion

```scheme
;; Wrap exceptions as err
(try-result (/ 1 0))             ;; → (err <condition>)
(try-result* (/ 1 0))           ;; → (err "...message string...")
(try-result (+ 1 2))            ;; → (ok 3)
```

### Collection Operations

```scheme
;; All-or-nothing
(sequence-results (list (ok 1) (ok 2) (ok 3)))
;; → (ok (1 2 3))

(sequence-results (list (ok 1) (err "x") (ok 3)))
;; → (err "x")

;; Partition successes and failures
(results-partition (list (ok 1) (err "a") (ok 2)))
;; → ((1 2) . ("a"))

;; Filter
(filter-ok (list (ok 1) (err "a") (ok 2)))   ;; → (1 2)
(filter-err (list (ok 1) (err "a") (ok 2)))  ;; → ("a")
```

### Result-Aware Threading

```scheme
(->? (ok 10) (+ 5) (* 2))    ;; → (ok 30)
(->? (err "x") (+ 5) (* 2))  ;; → (err "x")  — short circuits
(->>? (ok 10) (- 3))          ;; → (ok -7)  — thread last
```

---

## Iterators

### `for` — Side Effects

```scheme
(for ((x (in-range 5)))
  (displayln x))
;; prints 0 1 2 3 4

;; Multiple iterators (zipped, stops at shortest)
(for ((name (in-list '("Alice" "Bob")))
      (age (in-list '(30 25))))
  (displayln name ": " age))
```

### `for/collect` — Build a List

```scheme
(for/collect ((x (in-range 5)))
  (* x x))
;; → (0 1 4 9 16)
```

### `for/fold` — Accumulate

```scheme
(for/fold ((sum 0)) ((x (in-range 10)))
  (+ sum x))
;; → 45
```

### `for/or` — First Truthy

```scheme
(for/or ((x (in-list '(1 -2 3 -4))))
  (and (negative? x) x))
;; → -2
```

### `for/and` — All Truthy

```scheme
(for/and ((x (in-list '(2 4 6))))
  (even? x))
;; → #t
```

### Iterator Constructors

| Constructor | Description | Example |
|-------------|-------------|---------|
| `(in-list lst)` | Iterate over list | `(in-list '(a b c))` |
| `(in-vector vec)` | Iterate over vector | `(in-vector #(1 2 3))` |
| `(in-string str)` | Iterate over chars | `(in-string "abc")` |
| `(in-range end)` | 0 to end-1 | `(in-range 5)` → 0..4 |
| `(in-range start end)` | start to end-1 | `(in-range 2 5)` → 2..4 |
| `(in-range start end step)` | with step | `(in-range 0 10 2)` → 0,2,4,6,8 |
| `(in-hash-keys ht)` | Hash table keys | |
| `(in-hash-values ht)` | Hash table values | |
| `(in-hash-pairs ht)` | Key-value pairs | `(key . val)` |
| `(in-naturals)` | 0, 1, 2, ... | Bounded to 100k |
| `(in-naturals start)` | start, start+1, ... | |
| `(in-indexed lst)` | `(idx . elem)` pairs | |
| `(in-port [port [reader]])` | Read datums | |
| `(in-lines [port])` | Read lines | |
| `(in-chars [port])` | Read characters | |
| `(in-bytes [port])` | Read bytes | |
| `(in-producer thunk [sentinel])` | Call thunk until done | |

---

## Threading Macros

### `->` Thread First

Insert value as **first** argument at each step:

```scheme
(-> 10
    (+ 5)        ;; (+ 10 5) → 15
    (* 2))       ;; (* 15 2) → 30
```

### `->>` Thread Last

Insert value as **last** argument:

```scheme
(->> '(1 2 3 4 5)
     (filter even?)      ;; (filter even? '(...)) → (2 4)
     (map (cut * <> 10)) ;; (map ... '(2 4)) → (20 40)
     (apply +))          ;; → 60
```

### `as->` Thread with Explicit Name

```scheme
(as-> 1 x
  (+ x 10)       ;; → 11
  (* x 2)        ;; → 22
  (- 100 x))     ;; → 78
```

### `some->` / `some->>` Short-Circuit on `#f`

```scheme
(some-> user
  (get-address)      ;; returns #f if no address
  (get-city))        ;; skipped if previous was #f
;; → city or #f
```

### `cond->` / `cond->>` Conditional Steps

```scheme
(cond-> base-query
  include-deleted? (add-filter "deleted = true")
  limit            (add-limit limit))
```

---

## Ergonomic Typing

### `:` Type Cast

```scheme
(: value predicate?)    ;; checked cast — raises if wrong type
(: x number?)           ;; asserts x is a number
```

### `using` — Typed Bindings with Dot Access

```scheme
(defstruct point (x y))

(using (p (make-point 3 4) : point?)
  (+ p.x p.y))           ;; p.x → (point-x p)
;; → 7

;; Multiple bindings
(using ((p (make-point 1 2) : point?)
        (c (make-circle 5) : circle?))
  (displayln p.x c.radius))

;; `as` skips the type check (trust mode)
(using (p some-expr as point?)
  p.x)
```

### Contract Predicates

```scheme
;; Predicate factory — returns a predicate
((list-of? number?) '(1 2 3))     ;; → #t
((list-of? string?) '(1 2 3))     ;; → #f

;; Maybe — accepts #f or matching value
((maybe string?) "hello")          ;; → #t
((maybe string?) #f)               ;; → #t
((maybe string?) 42)               ;; → #f
```

---

## Hash Tables

### Construction

```scheme
;; Empty
(def ht (make-hash-table))

;; From pairs (literal macro)
(def ht (hash-literal ("name" "Alice") ("age" 30)))

;; From list of pairs
(def ht (list->hash-table '(("a" . 1) ("b" . 2))))

;; From property list
(def ht (plist->hash-table '("name" "Alice" "age" 30)))
```

### Access

```scheme
(hash-ref ht "name")              ;; → "Alice" (error if missing)
(hash-ref ht "missing" "default") ;; → "default"
(hash-get ht "name")              ;; → "Alice" or #f
(hash-key? ht "name")             ;; → #t
```

### Mutation

```scheme
(hash-put! ht "email" "alice@example.com")
(hash-update! ht "age" add1)
(hash-remove! ht "email")
(hash-merge! target source)       ;; merge source into target
```

### Iteration

```scheme
(hash-for-each (lambda (k v) (displayln k ": " v)) ht)
(hash-map (lambda (k v) (cons k (add1 v))) ht)
(hash-fold (lambda (k v acc) (+ acc v)) 0 ht)

;; With iterators
(for ((k (in-hash-keys ht)))
  (displayln k))
(for (((k . v) (in-hash-pairs ht)))
  (displayln k " → " v))
```

### Conversion

```scheme
(hash->list ht)      ;; → ((key . val) ...)
(hash->plist ht)     ;; → (key val key val ...)
(hash-keys ht)       ;; → (key ...)
(hash-values ht)     ;; → (val ...)
(hash-length ht)     ;; → count
(hash-copy ht)       ;; → shallow copy
```

### Destructuring

```scheme
(let-hash ht (name age)
  (displayln name " is " age))
```

---

## Functions & Combinators

### Partial Application

```scheme
;; cut / cute (SRFI-26) — <> marks slots
((cut + 1 <>) 5)                ;; → 6
((cut map <> '(1 2 3)) add1)    ;; → (2 3 4)
((cut string-append <> "!" <>) "hi" "?")  ;; → "hi!?"

;; partial (Clojure-style)
((partial + 10) 5)              ;; → 15
```

### Composition

```scheme
((compose add1 add1) 5)         ;; → 7
((comp add1 (* 2)) 5)          ;; same (alias)
((complement even?) 3)          ;; → #t
((negate even?) 3)              ;; → #t
((constantly 42) 'anything)     ;; → 42
(identity 42)                   ;; → 42
((flip cons) '(2 3) 1)         ;; → (1 2 3)
```

### Higher-Order Utilities

```scheme
((conjoin positive? even?) 4)   ;; → #t (both true)
((disjoin zero? negative?) -1)  ;; → #t (either true)
((every-pred number? positive?) 5) ;; → #t
((some-fn string? number?) "hi")   ;; → #t

((curry + 1) 2)                 ;; → 3
((juxt min max) 3 1 4 1 5)     ;; → (1 5)
((fnil + 0 0) #f 5)            ;; → 5 (replaces #f with 0)

(def slow-fib (memo-proc fib))  ;; memoize a procedure
```

---

## Standard Library

Everything below is available from `(import (jerboa prelude))`.

### Strings — `(std misc string)`

```scheme
(string-split "a,b,c" #\,)       ;; → ("a" "b" "c")
(string-join '("a" "b" "c") ",") ;; → "a,b,c"
(string-trim "  hello  ")        ;; → "hello"
(string-prefix? "hel" "hello")   ;; → #t
(string-suffix? "llo" "hello")   ;; → #t
(string-contains "hello" "ell")  ;; → 1 (index)
(string-index "hello" #\l)       ;; → 2
(string-empty? "")               ;; → #t
(string-match? "^[0-9]+$" "123") ;; → #t
(string-find "[0-9]+" "abc123")  ;; → "123"
(string-find-all "[0-9]+" "a1b2");; → ("1" "2")
(str "age: " 25 "!")             ;; → "age: 25!" (auto-coerce)
```

### Lists — `(std misc list)`

```scheme
(flatten '(1 (2 (3))))           ;; → (1 2 3)
(unique '(1 2 2 3 3))            ;; → (1 2 3)
(take '(1 2 3 4 5) 3)            ;; → (1 2 3)
(drop '(1 2 3 4 5) 3)            ;; → (4 5)
(take-last '(1 2 3 4) 2)         ;; → (3 4)
(drop-last '(1 2 3 4) 2)         ;; → (1 2)
(every number? '(1 2 3))         ;; → #t
(any negative? '(1 -2 3))        ;; → #t
(filter-map (lambda (x) (and (> x 0) (* x 2))) '(-1 2 -3 4))
;; → (4 8)
(group-by even? '(1 2 3 4 5))
;; → ((#t 2 4) (#f 1 3 5))
(zip '(1 2 3) '(a b c))          ;; → ((1 a) (2 b) (3 c))
(frequencies '(a b a c b a))     ;; → ((a . 3) (b . 2) (c . 1))
(partition even? '(1 2 3 4 5))   ;; → ((2 4) (1 3 5))
(interleave '(1 2 3) '(a b c))   ;; → (1 a 2 b 3 c)
(interpose ", " '("a" "b" "c"))  ;; → ("a" ", " "b" ", " "c")
(mapcat (lambda (x) (list x x)) '(1 2 3))  ;; → (1 1 2 2 3 3)
(distinct '(1 2 1 3 2))          ;; → (1 2 3)
(keep (lambda (x) (and (> x 0) x)) '(-1 2 -3 4))  ;; → (2 4)
(split-at '(1 2 3 4 5) 3)        ;; → ((1 2 3) (4 5))
(reductions + 0 '(1 2 3))        ;; → (0 1 3 6)
(append-map (lambda (x) (list x x)) '(1 2))  ;; → (1 1 2 2)
(snoc '(1 2) 3)                   ;; → (1 2 3)
```

### Association Lists — `(std misc alist)`

```scheme
;; Construction
(alist (name "Alice") (age 30))   ;; → ((name . "Alice") (age . 30))

;; Access (q=eq?, v=eqv?, default=equal?)
(aget '((name . "Alice")) 'name)  ;; → "Alice"
(agetq '((x . 1)) 'x)            ;; → 1

;; Mutation
(aset! '((x . 1)) 'x 2)          ;; → ((x . 2))

;; Property lists
(pgetq '(x 1 y 2) 'y)            ;; → 2
```

### Sorting — `(std sort)`

```scheme
(sort '(3 1 2) <)                 ;; → (1 2 3)
(sort! vec <)                     ;; in-place on vectors
(stable-sort lst string<?)        ;; preserves order of equal elements
```

### Formatting — `(std format)`

```scheme
(format "~a is ~a" "Alice" 30)    ;; → "Alice is 30"
(printf "count: ~a\n" 42)         ;; print to stdout
(eprintf "error: ~a\n" msg)       ;; print to stderr
```

### JSON — `(std text json)`

```scheme
(def data (string->json-object "{\"name\":\"Alice\",\"age\":30}"))
(hash-ref data "name")            ;; → "Alice"

(json-object->string (hash-literal ("x" 1) ("y" 2)))
;; → "{\"x\":1,\"y\":2}"

;; Port-based
(read-json port)
(write-json obj port)
```

### Paths — `(std os path)`

```scheme
(path-join "/home" "user" "file.txt")  ;; → "/home/user/file.txt"
(path-directory "/home/user/f.txt")    ;; → "/home/user"
(path-extension "/home/user/f.txt")    ;; → "txt"
(path-strip-extension "file.txt")      ;; → "file"
(path-absolute? "/home")               ;; → #t
(path-expand "~/file")                 ;; → "/home/user/file"
```

### File I/O — `(std misc ports)`

```scheme
(read-file-string "data.txt")          ;; → entire file as string
(read-file-lines "data.txt")           ;; → list of lines
(write-file-string "out.txt" "hello")  ;; write string to file
(read-all-as-string port)              ;; read port to string
```

### CSV — `(std csv)`

```scheme
(csv->alists "name,age\nAlice,30\nBob,25")
;; → (((name . "Alice") (age . "30"))
;;    ((name . "Bob") (age . "25")))

(read-csv-file "data.csv")              ;; → list of row lists
(write-csv-file "out.csv" '(("a" "b") ("1" "2")))
(rows->csv-string '(("x" "y") ("1" "2")))
```

### DateTime — `(std datetime)`

```scheme
(def now (datetime-now))
(datetime-year now)                     ;; → 2026
(datetime->iso8601 now)                 ;; → "2026-03-27T22:13:43Z"

;; Construction
(make-datetime 2026 3 27 12 0 0)
(make-date 2026 3 27)
(make-time 12 30 0)

;; Parsing
(parse-datetime "2026-03-27T12:00:00Z")
(parse-date "2026-03-27")

;; Arithmetic
(datetime-add now (make-duration 3600 0))    ;; +1 hour
(datetime-diff dt1 dt2)                      ;; → duration

;; Comparison
(datetime<? dt1 dt2)
(datetime-min dt1 dt2)
(datetime-clamp dt lower upper)

;; Calendar
(day-of-week (make-date 2026 3 27))   ;; → 5 (Friday)
(leap-year? 2024)                      ;; → #t
(days-in-month 2026 2)                ;; → 28
```

### Pretty Printing — `(std debug pp)`

```scheme
(pp '(a b (c d (e f))))    ;; pretty-print to stdout
(pp-to-string expr)         ;; → formatted string
(ppd expr)                  ;; deep pretty-print (shows internals)
```

### Error Constructors — `(std error)`

```scheme
(Error "something went wrong" irritant1 irritant2)
(ContractViolation "expected positive" value)
```

---

## FFI

### Quick FFI

```scheme
(import (jerboa prelude))

(c-declare "#include <math.h>")
(def c-sqrt (c-lambda (double) double "sqrt"))
(c-sqrt 2.0)  ;; → 1.4142135623730951
```

### `begin-ffi` Block

```scheme
(begin-ffi (my-getpid)
  (c-declare "#include <unistd.h>")
  (define my-getpid (c-lambda () int "getpid")))
```

### Direct Chez FFI

For more control, use Chez's native FFI directly:

```scheme
(import (chezscheme))
(load-shared-object "libm.so.6")
(def c-sin (foreign-procedure "sin" (double) double))
```

---

## Additional Modules

These are **not** in the prelude — import them separately:

```scheme
;; Networking
(import (std net request))      ;; HTTP client
(import (std net httpd))        ;; HTTP server

;; Database
(import (std db sqlite))        ;; SQLite bindings

;; Concurrency
(import (std actor))            ;; Actor system
(import (std async))            ;; Async/await
(import (std concur))           ;; Concurrency primitives

;; Crypto
(import (std crypto digest))    ;; SHA, MD5, etc.
(import (std crypto cipher))    ;; AES, etc.

;; Security
(import (std security sandbox)) ;; Sandboxing
(import (std security taint))   ;; Taint tracking

;; Text processing
(import (std text xml))         ;; XML
(import (std text yaml))        ;; YAML
(import (std text regex))       ;; Regular expressions

;; OS
(import (std os env))           ;; Environment variables
(import (std os signal))        ;; Signal handling
(import (std os temp))          ;; Temp files
```

---

## Differences from Gerbil

| Feature | Gerbil | Jerboa |
|---------|--------|--------|
| Backend | Gambit | Chez Scheme |
| Multiple inheritance | Yes | No (single only) |
| `[...]` | Various uses | Always `(list ...)` |
| `{...}` | Method call | Method call (same) |
| `keyword:` | Keywords | Keywords (same) |
| Module system | Gerbil modules | R6RS libraries (`.sls`) |
| Compilation | `gxc` | Load from source / `compile-whole-program` |
| `export` | `(export ...)` | Part of `(library ...)` form |
| `##` primitives | Yes (Gambit) | No (use `(chezscheme)` imports) |
| Iterators | `for/collect` etc. | Same syntax |
| Result types | Not built-in | Built-in `ok`/`err` |
| DateTime | Not built-in | Built-in `datetime` |
| Ergo typing | Not built-in | Built-in `using`, `:` |
| Threading macros | `->`, `->>` | Same + `->?`, `->>?` (result-aware) |

---

## Differences from Chez Scheme

| Feature | Chez Scheme | Jerboa |
|---------|-------------|--------|
| File format | `.sls` with `(library ...)` | `.ss` with `(import ...)` |
| `define` | `define` | `def` (preferred) |
| Records | `define-record-type` | `defstruct` / `defclass` |
| Hash tables | `(make-hashtable ...)` | `(make-hash-table)` with richer API |
| Pattern matching | None built-in | `match` with guards, views, struct patterns |
| Error handling | `guard` | `try`/`catch`/`finally` |
| Macros | `define-syntax` | `defrule`/`defrules` (simpler), or `define-syntax` |
| Strings | Basic | `string-split`, `string-join`, `str`, regex |
| Lists | Basic | `take`, `drop`, `flatten`, `group-by`, `zip`, 50+ more |
| Iteration | `do`, named `let` | `for`/`for/collect`/`for/fold` |
| Method dispatch | None | `defmethod` + `~` / `{...}` |
| FFI | `foreign-procedure` | `c-lambda` (simpler) + `foreign-procedure` |
| JSON | None | Built-in `read-json`/`write-json` |
| Paths | None | Built-in path operations |
| CSV | None | Built-in CSV parsing |
| Result type | None | Built-in `ok`/`err` monad |
| DateTime | None | Built-in datetime library |

---

## The Jerboa Philosophy

1. **One import to start**: `(import (jerboa prelude))` gives you a complete language
2. **`.ss` files are the language**: You never need to write `.sls` files
3. **Gerbil-familiar, Chez-powered**: Syntax is Gerbil-like, performance is Chez
4. **Batteries included**: JSON, CSV, datetime, result types, iterators — all in the prelude
5. **Functional first**: Threading macros, combinators, result monads — but mutation when needed
6. **No boilerplate**: `def` over `define`, `defstruct` over `define-record-type`, `match` over nested `cond`
