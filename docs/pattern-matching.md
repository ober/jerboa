# Pattern Matching 2.0 — `(std match2)`

The `(std match2)` library extends Chez Scheme with a powerful pattern matching system. It builds on the ideas behind `(std match)` and adds three major capabilities: **sealed hierarchies** (closed sets of variants that enable exhaustiveness checking), **active patterns** (user-defined extractors that run arbitrary code during matching), and **view patterns** (computed projections bound as match variables). Together these make it practical to write exhaustive, structurally typed dispatch code in Chez Scheme.

## Table of Contents

1. [Quick Start](#quick-start)
2. [Core API](#core-api)
3. [Pattern Syntax Reference](#pattern-syntax-reference)
4. [Sealed Hierarchies](#sealed-hierarchies)
5. [Active Patterns](#active-patterns)
6. [Guards](#guards)
7. [Complete Examples](#complete-examples)
8. [Exhaustiveness Checking with `match/strict`](#exhaustiveness-checking-with-matchstrict)
9. [Comparison with Standard Match](#comparison-with-standard-match)

---

## Quick Start

```scheme
(import (chezscheme) (std match2))

;; Basic structural matching
(match '(1 2 3)
  [(list a b c) (+ a b c)])   ; => 6

;; Predicate patterns
(match 42
  [(? string?) 'string]
  [(? number?) 'number])      ; => 'number

;; Struct patterns (after registering the type)
(define-record-type (point make-point point?)
  (fields (immutable x point-x) (immutable y point-y)))

(define-match-type point point? point-x point-y)

(match (make-point 3 4)
  [(point x y) (sqrt (+ (* x x) (* y y)))])  ; => 5.0
```

---

## Core API

### `match`

```scheme
(match expr clause ...)
```

Evaluates `expr` and tests each `clause` in order until one matches. A clause has the form `(pattern body ...)` or `(pattern (where guard) body ...)`. The value of the first matching clause's body is returned. If no clause matches, an error is raised.

```scheme
(match value
  [pattern1 result1]
  [pattern2 result2]
  [_ default])
```

### `define-sealed-hierarchy`

```scheme
(define-sealed-hierarchy hier-name
  (variant-name pred-fn accessor ...)
  ...)
```

Declares a closed set of variant types under a single hierarchy name. Each variant is registered for structural matching and the group is registered as a sealed hierarchy for `match/strict` coverage checking.

- `hier-name` — symbol naming the hierarchy (used with `match/strict`)
- `variant-name` — symbol used as the pattern head (e.g., `(variant-name field ...)`)
- `pred-fn` — predicate procedure for this variant
- `accessor ...` — field accessor procedures in order

```scheme
(define-sealed-hierarchy expr
  (lit-expr lit-expr? lit-value)
  (add-expr add-expr? add-left add-right)
  (var-expr var-expr? var-name))
```

### `sealed-hierarchy?`

```scheme
(sealed-hierarchy? name) => boolean
```

Returns `#t` if `name` (a symbol) has been registered as a sealed hierarchy.

```scheme
(sealed-hierarchy? 'expr)    ; => #t
(sealed-hierarchy? 'unknown) ; => #f
```

### `sealed-hierarchy-members`

```scheme
(sealed-hierarchy-members name) => list
```

Returns the member list of a sealed hierarchy. Each element is a list `(variant-name pred-fn accessor ...)`. Returns `'()` if the hierarchy is not registered.

```scheme
(sealed-hierarchy-members 'expr)
; => ((lit-expr #<procedure lit-expr?> #<procedure lit-value>)
;     (add-expr #<procedure add-expr?> ...)
;     ...)
```

### `register-struct-type!`

```scheme
(register-struct-type! name pred accessor ...)
```

Registers a struct type for structural matching by name. After registration, `(name field1 field2 ...)` can be used as a pattern in `match`. This is the runtime procedure that `define-match-type` and `define-sealed-hierarchy` call internally.

```scheme
(define-record-type (point make-point point?)
  (fields (immutable x point-x) (immutable y point-y)))

(register-struct-type! 'point point? point-x point-y)
```

### `define-match-type`

```scheme
(define-match-type type-name pred-fn accessor ...)
```

Convenience macro that calls `register-struct-type!`. Use this to make any record type usable as a pattern head.

```scheme
(define-match-type point point? point-x point-y)

;; Now usable in patterns:
(match (make-point 1 2)
  [(point x y) (list x y)])  ; => '(1 2)
```

### `match/strict`

```scheme
(match/strict sealed-type expr clause ...)
(match/strict expr clause ...)
```

Like `match`, but signals intent that all variants of a sealed hierarchy are handled. The `sealed-type` argument names the hierarchy being matched; it is available for documentation and tooling purposes. If no clause matches at runtime, an error is raised (same as `match`).

Note: Full static exhaustiveness checking is not possible at Chez macro-expansion time under R6RS phasing. `match/strict` is primarily a documentation and convention signal — it pairs naturally with `define-sealed-hierarchy` to communicate "this match is supposed to cover all cases."

```scheme
(match/strict shape s
  [(circle r)   (* pi r r)]
  [(rect   w h) (* w h)])
```

### `define-active-pattern`

```scheme
(define-active-pattern (name input) body ...)
```

Defines a named extractor function for use in `match` patterns. The body receives the value being matched as `input` and should return:

- `#f` — pattern does not match
- `#t` — pattern matches, no extracted values
- A list `(v ...)` — pattern matches, values are bound to sub-patterns
- A vector `#(v ...)` — same as list form

Active patterns integrate seamlessly into `match` syntax: `(name sub-pat ...)` is valid wherever any other structural pattern is valid.

```scheme
(define-active-pattern (even? n)
  (and (integer? n) (even? n)))

(define-active-pattern (split-at-comma s)
  (if (string? s)
    (let ([i (string-contains s ",")])
      (if i
        (list (substring s 0 i)
              (substring s (+ i 1) (string-length s)))
        #f))
    #f))
```

### `active-pattern?`

```scheme
(active-pattern? name) => boolean
```

Returns `#t` if `name` (a symbol) has been registered via `define-active-pattern`.

### `active-pattern-proc`

```scheme
(active-pattern-proc name) => procedure | #f
```

Returns the extractor procedure for an active pattern, or `#f` if not registered. Useful for introspection or testing active patterns directly.

```scheme
((active-pattern-proc 'split-at-comma) "a,b")  ; => ("a" "b")
((active-pattern-proc 'split-at-comma) "nope")  ; => #f
```

---

## Pattern Syntax Reference

### Wildcard

```scheme
_
```

Matches any value without binding.

```scheme
(match x [_ 'anything])
```

### Variables

```scheme
name
```

Any identifier (other than `_` and reserved pattern keywords) binds the matched value.

```scheme
(match 42 [n (* n 2)])  ; => 84
```

### Literals

| Pattern | Matches |
|---------|---------|
| `42` | Number equal to 42 |
| `"hello"` | String equal to `"hello"` |
| `#t` / `#f` | Boolean |
| `'foo` | Symbol `foo` |
| `'(1 2)` | Any datum equal under `equal?` |

```scheme
(match x
  [0    "zero"]
  [1    "one"]
  ["hi" "greeting"]
  ['ok  "ok symbol"])
```

### Predicate: `(? pred)`

```scheme
(? predicate)
```

Matches if `(predicate value)` is truthy. Does not bind the value.

```scheme
(match x
  [(? number?) 'numeric]
  [(? string?) 'textual])
```

### Predicate with Binding: `(? pred -> var)`

```scheme
(? predicate -> variable)
```

Applies `predicate` to the value. If the result is truthy, binds it to `variable` and succeeds. This is useful when the predicate returns a transformed value (e.g., `string->number`).

```scheme
(match "42"
  [(? string->number -> n) (* n 10)]  ; => 420
  [_ 'not-a-number])
```

### View Pattern: `(=> proc var)`

```scheme
(=> procedure variable)
```

Applies `procedure` to the value unconditionally and binds the result to `variable`. Always succeeds. Use this for projections or computed views of the input.

```scheme
(match "hello"
  [(=> string-length len) len])  ; => 5

(match 10
  [(=> (lambda (x) (* x x)) sq) sq])  ; => 100
```

### Conjunction: `(and pat ...)`

```scheme
(and pattern ...)
```

Matches if all sub-patterns match. Bindings from all sub-patterns are in scope in the body. `(and)` with no sub-patterns always succeeds.

```scheme
(match x
  [(and (? number?) (? positive?)) 'positive-number]
  [(and (? number?) n)             (list 'nonpositive n)])
```

### Disjunction: `(or pat ...)`

```scheme
(or pattern ...)
```

Matches if any sub-pattern matches. Because different branches may bind different variables, bindings from `or` sub-patterns are not visible in the body — use `or` only for pure dispatch without variable capture. `(or)` with no sub-patterns never matches.

```scheme
(match x
  [(or 1 2 3) 'small]
  [_          'large])
```

### Negation: `(not pat)`

```scheme
(not pattern)
```

Matches if the sub-pattern does not match. No bindings are captured.

```scheme
(match x
  [(not (? string?)) 'not-a-string]
  [_                 'string])
```

### Pair: `(cons p1 p2)`

```scheme
(cons car-pattern cdr-pattern)
```

Matches a pair. Binds the car to `car-pattern` and the cdr to `cdr-pattern`.

```scheme
(match '(1 2 3)
  [(cons h t) (list 'head h 'tail t)])  ; => '(head 1 tail (2 3))
```

### Exact List: `(list pat ...)`

```scheme
(list pattern ...)
```

Matches a proper list of exactly the given length. Each sub-pattern matches the corresponding element.

```scheme
(match '(x y z)
  [(list a b c) (list c b a)])  ; => '(z y x)

(match '()
  [(list) 'empty])
```

### Improper / Prefix List: `(list* pat ... rest)`

```scheme
(list* pattern ... rest-pattern)
```

Matches a list with at least n elements (where n is the number of leading patterns). The leading patterns match elements 0 through n-1; `rest-pattern` matches the tail starting at element n.

```scheme
(match '(1 2 3 4 5)
  [(list* a b rest) (list a b rest)])  ; => '(1 2 (3 4 5))
```

### Vector: `(vector pat ...)`

```scheme
(vector pattern ...)
```

Matches a vector of exactly the given length.

```scheme
(match (vector 10 20 30)
  [(vector a b c) (+ a b c)])  ; => 60
```

### Box: `(box pat)`

```scheme
(box pattern)
```

Matches a Chez Scheme `box` and applies the sub-pattern to the unboxed value.

```scheme
(match (box 99)
  [(box n) n])  ; => 99
```

### Struct / Named Pattern: `(TypeName pat ...)`

```scheme
(TypeName field-pattern ...)
```

Matches a struct value whose type was registered via `register-struct-type!`, `define-match-type`, or `define-sealed-hierarchy`. The sub-patterns are matched against the field values in registration order.

Works identically for both struct types and active patterns — the runtime dispatcher tries active patterns first, then struct types.

```scheme
(match (make-point 3 4)
  [(point x y) (+ x y)])  ; => 7
```

### Pattern Guards: `(where expr)`

A guard condition can appear as the first form after the pattern in a clause:

```scheme
(pattern (where guard-expression) body ...)
```

The guard is evaluated with all pattern bindings in scope. If it returns `#f`, the clause is skipped and matching continues with the next clause.

```scheme
(match '(3 4)
  [(list a b) (where (= a b)) 'equal]
  [(list a b)                 'different])  ; => 'different

(match 42
  [n (where (> n 100)) 'big]
  [n                   (list 'small n)])    ; => '(small 42)
```

---

## Sealed Hierarchies

A sealed hierarchy declares that a set of variants is closed — there are no other variants. This is the Jerboa equivalent of a sum type or tagged union.

```scheme
;; 1. Define the record types
(define-record-type (circle make-circle circle?)
  (fields (immutable radius circle-radius)))

(define-record-type (rect make-rect rect?)
  (fields (immutable w rect-w) (immutable h rect-h)))

(define-record-type (triangle make-triangle triangle?)
  (fields (immutable base triangle-base) (immutable height triangle-height)))

;; 2. Declare the sealed hierarchy
(define-sealed-hierarchy shape
  (circle   circle?   circle-radius)
  (rect     rect?     rect-w rect-h)
  (triangle triangle? triangle-base triangle-height))

;; 3. Match against variants
(define (area s)
  (match/strict shape s
    [(circle   r)   (* 3.14159 r r)]
    [(rect     w h) (* w h)]
    [(triangle b h) (/ (* b h) 2.0)]))

(area (make-circle 5))         ; => 78.53975
(area (make-rect 3 4))         ; => 12
(area (make-triangle 6 4))     ; => 12.0
```

`define-sealed-hierarchy` automatically calls `register-struct-type!` for each variant, so the variants are immediately usable in ordinary `match` as well.

Introspection:

```scheme
(sealed-hierarchy? 'shape)        ; => #t
(length (sealed-hierarchy-members 'shape))  ; => 3
```

---

## Active Patterns

Active patterns let you define custom extractors — matching logic and value transformation in one place. They integrate into `match` syntax as named pattern heads.

### Boolean Active Patterns

Return `#t` or `#f` for predicate-only tests:

```scheme
(define-active-pattern (even-int? n)
  (and (integer? n) (even? n)))

(match 4
  [(even-int?) 'even]
  [_           'odd])   ; => 'even
```

### Extracting Active Patterns

Return a list to provide values to sub-patterns:

```scheme
(define-active-pattern (double n)
  (list (* n 2)))

(match 5
  [(double d) d])   ; => 10
```

### Multi-Value Extraction

```scheme
(define-active-pattern (parse-kv s)
  ;; Splits "key=value" into two strings, or fails
  (and (string? s)
       (let loop ([i 0])
         (cond
           [(= i (string-length s)) #f]
           [(char=? (string-ref s i) #\=)
            (list (substring s 0 i)
                  (substring s (+ i 1) (string-length s)))]
           [else (loop (+ i 1))]))))

(match "name=Alice"
  [(parse-kv k v) (list 'key k 'val v)]
  [_              'no-equals])
; => '(key "name" val "Alice")

(match "no-equals"
  [(parse-kv k v) (list k v)]
  [_              'no-equals])
; => 'no-equals
```

### Nesting Active Patterns

Active patterns can be nested with other patterns:

```scheme
(define-active-pattern (abs-val n)
  (list (if (negative? n) (- n) n)))

(match -42
  [(abs-val (? (lambda (x) (> x 10)))) 'large-magnitude]
  [(abs-val a)                          (list 'magnitude a)])
; => 'large-magnitude
```

---

## Complete Examples

### AST Processing with Sealed Hierarchy

```scheme
(import (chezscheme) (std match2))

;; Define an expression AST
(define-record-type (num-node  make-num  num?)
  (fields (immutable value num-value)))
(define-record-type (add-node  make-add  add?)
  (fields (immutable left add-left) (immutable right add-right)))
(define-record-type (mul-node  make-mul  mul?)
  (fields (immutable left mul-left) (immutable right mul-right)))
(define-record-type (var-node  make-var  var?)
  (fields (immutable name var-name)))

(define-sealed-hierarchy expr
  (num-node num?  num-value)
  (add-node add?  add-left add-right)
  (mul-node mul?  mul-left mul-right)
  (var-node var?  var-name))

;; Evaluator
(define (eval-expr node env)
  (match/strict expr node
    [(num-node v)   v]
    [(add-node l r) (+ (eval-expr l env) (eval-expr r env))]
    [(mul-node l r) (* (eval-expr l env) (eval-expr r env))]
    [(var-node n)   (cdr (assq n env))]))

(define my-env '((x . 3) (y . 4)))

(eval-expr
  (make-add (make-mul (make-var 'x) (make-var 'x))
            (make-mul (make-var 'y) (make-var 'y)))
  my-env)
; => 25  (3*3 + 4*4)

;; Pretty printer
(define (pp-expr node)
  (match/strict expr node
    [(num-node v)   (number->string v)]
    [(var-node n)   (symbol->string n)]
    [(add-node l r) (string-append "(" (pp-expr l) " + " (pp-expr r) ")")]
    [(mul-node l r) (string-append "(" (pp-expr l) " * " (pp-expr r) ")")]))

(pp-expr (make-add (make-var 'x) (make-num 1)))
; => "(x + 1)"
```

### JSON Value Matching

```scheme
(import (chezscheme) (std match2))

;; JSON values are represented as: number, string, boolean, 'null,
;; (vector ...) for arrays, and alists for objects.

(define (json-type v)
  (match v
    [(? number?)  'number]
    [(? string?)  'string]
    [#t           'true]
    [#f           'false]
    ['null        'null]
    [(? vector?)  'array]
    [(? pair?)    'object]
    [_            'unknown]))

(define (json-get obj key)
  (match obj
    [(? pair?) (let ([entry (assoc key obj)])
                 (if entry (cdr entry) 'null))]
    [_         'null]))

(define (json-summarize v)
  (match v
    [(? number?)              (format "~a" v)]
    [(? string?)              (format "\"~a\"" v)]
    [#t                       "true"]
    [#f                       "false"]
    ['null                    "null"]
    [(? vector?)
     (format "[~a items]" (vector-length v))]
    [(list* (cons _ _) rest)
     (format "{~a keys}" (+ 1 (length rest)))]
    [_                        "?"]))

(json-type 42)            ; => 'number
(json-type "hello")       ; => 'string
(json-type #t)            ; => 'true
(json-type '((x . 1)))   ; => 'object
(json-summarize '((name . "Alice") (age . 30)))  ; => "{2 keys}"
```

### Active Pattern for Parsing

```scheme
(import (chezscheme) (std match2))

;; Active pattern: parse an ISO date string "YYYY-MM-DD"
(define-active-pattern (iso-date s)
  (and (string? s)
       (= (string-length s) 10)
       (char=? (string-ref s 4) #\-)
       (char=? (string-ref s 7) #\-)
       (let ([y (string->number (substring s 0 4))]
             [m (string->number (substring s 5 7))]
             [d (string->number (substring s 8 10))])
         (and y m d (list y m d)))))

(define (classify-date s)
  (match s
    [(iso-date y m d)
     (cond
       [(= m 1)  (format "~a is in January" y)]
       [(= m 12) (format "~a is in December" y)]
       [else     (format "~a-~a-~a" y m d)])]
    [_ "not a date"]))

(classify-date "2024-01-15")  ; => "2024 is in January"
(classify-date "2024-12-25")  ; => "2024 is in December"
(classify-date "not-a-date")  ; => "not a date"
```

### Exhaustive Match Catching Missing Cases

```scheme
(import (chezscheme) (std match2))

(define-record-type (ok-val  make-ok  ok?)  (fields (immutable val ok-val)))
(define-record-type (err-val make-err err?) (fields (immutable msg err-msg)))

(define-sealed-hierarchy result
  (ok-val  ok?  ok-val)
  (err-val err? err-msg))

;; Using match/strict signals that this should cover all variants.
;; If you accidentally omit a branch and the missing case is hit at runtime,
;; match raises an error:
(define (unwrap r)
  (match/strict result r
    [(ok-val v) v]))

;; This works fine when called with ok-val, but raises an error on err-val:
;; (unwrap (make-err "oops"))
;; => Error: match: no matching clause ...

;; A complete version:
(define (result->string r)
  (match/strict result r
    [(ok-val  v) (format "ok: ~a" v)]
    [(err-val m) (format "error: ~a" m)]))

(result->string (make-ok 42))        ; => "ok: 42"
(result->string (make-err "failed")) ; => "error: failed"
```

---

## Exhaustiveness Checking with `match/strict`

`match/strict` is a documentation and defensive-programming convention. Its syntax is:

```scheme
(match/strict hierarchy-name expr clause ...)
;; or, omitting the hierarchy name:
(match/strict expr clause ...)
```

Both forms compile identically to `match`. The difference is semantic intent: using `match/strict` with a `define-sealed-hierarchy` name signals that you expect all variants to be covered. If a variant is hit at runtime without a matching clause, `match` (and therefore `match/strict`) raises an error rather than silently returning an unspecified value.

This is distinct from compile-time exhaustiveness checking (which would require dependent types or a more complex macro system). Think of `match/strict` as the equivalent of a programmer assertion: "I believe this match is complete; if it is not, fail loudly."

Workflow:

1. Define your type hierarchy with `define-sealed-hierarchy`.
2. Use `match/strict hier-name` for all dispatch over that hierarchy.
3. When you add a new variant to the hierarchy, grep for `match/strict hier-name` to find all sites that need updating — and if any are missed, a runtime error with the unmatched value will identify the gap.

---

## Comparison with Standard Match

| Feature | `(std match)` | `(std match2)` |
|---------|---------------|----------------|
| Wildcards and variables | Yes | Yes |
| Literals (number, string, boolean, symbol) | Yes | Yes |
| `(list ...)`, `(cons ...)`, `(vector ...)` | Yes | Yes |
| `(? pred)` predicate | Yes | Yes |
| `(? pred -> var)` predicate with binding | No | Yes |
| `(=> proc var)` view pattern | No | Yes |
| `(and ...)`, `(or ...)`, `(not ...)` | No | Yes |
| `(box pat)` box patterns | No | Yes |
| `(where guard)` inline guards | No | Yes |
| Named struct patterns | No | Yes, via `define-match-type` |
| Sealed hierarchies | No | Yes, via `define-sealed-hierarchy` |
| Active (user-defined extractor) patterns | No | Yes, via `define-active-pattern` |
| Strict/exhaustive mode | No | Yes, via `match/strict` |

The pattern dispatch in `match2` is runtime-based: `(TypeName ...)` patterns check a global hashtable to determine whether `TypeName` is an active pattern or a struct type. This means struct types and active patterns must be registered before any code that uses them runs (registration happens at module load time when using `define-match-type` or `define-active-pattern`).
