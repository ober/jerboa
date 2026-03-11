# Gradual Typing in Jerboa

`(std typed)` and `(std typed advanced)` provide optional type annotations
for Chez Scheme code. Annotations compile to runtime assertions in `debug`
mode and disappear entirely in `release` mode — zero overhead in production.

---

## Overview

Gradual typing lets you add type information incrementally. You can annotate
a single hot function, a whole module, or nothing at all. Untyped and typed
code interoperate freely: a typed function can call an untyped one and vice
versa.

The philosophy is practical:

- **Development**: catch type errors early with descriptive messages that
  name the function, the argument, the expected type, and the actual value.
- **Production**: flip `(*typed-mode* 'release)` and every annotation
  vanishes from the compiled code. No allocation, no branches, no overhead.
- **Incrementally adoptable**: annotate what matters, leave the rest alone.

---

## Importing the Library

```scheme
(import (std typed))
```

For advanced features (occurrence typing, row polymorphism, refinement
types, type-directed compilation):

```scheme
(import (std typed)
        (std typed advanced))
```

---

## Core API — `(std typed)`

### `*typed-mode*`

A Chez Scheme parameter that controls whether annotations are enforced.

```scheme
(*typed-mode*)           ; => 'debug   (default)
(*typed-mode* 'debug)    ; enable runtime checks
(*typed-mode* 'release)  ; strip all checks (zero overhead)
(*typed-mode* 'none)     ; alias for 'release
```

Accepts exactly `debug`, `release`, or `none`; any other value raises an
error. Set this once at program startup, typically from a command-line flag
or environment variable.

---

### `define/t` — typed define

```
(define/t (name [arg : type] ...) : ret-type body ...)
(define/t (name [arg : type] ...) body ...)
```

Defines a function with annotated arguments and an optional return type.
Arguments without a `: type` annotation are implicitly typed `any` (no
check). In `debug` mode the macro expands to argument checks before the body
and a return-type check after. In `release` mode it expands to a plain
`define`.

```scheme
(import (std typed))

;; Both arguments and return type annotated
(define/t (add-strings [a : string] [b : string]) : string
  (string-append a b))

;; Only arguments annotated (no return type check)
(define/t (safe-divide [n : number] [d : number])
  (if (zero? d)
    (error 'safe-divide "division by zero")
    (/ n d)))

;; Mixed: one typed, one untyped
(define/t (scale [xs : list] factor)
  (map (lambda (x) (* x factor)) xs))
```

Error message example (in `debug` mode):

```
Exception in add-strings: b: expected string, got 42
```

---

### `lambda/t` — typed lambda

```
(lambda/t ([arg : type] ...) : ret-type body ...)
(lambda/t ([arg : type] ...) body ...)
```

Same as `define/t` but produces an anonymous procedure.

```scheme
(define process
  (lambda/t ([items : list] [transform : procedure]) : list
    (map transform items)))

;; Works naturally as a higher-order argument
(sort items (lambda/t ([a : string] [b : string]) : boolean
              (string<? a b)))
```

---

### `assert-type` — inline type assertion

```
(assert-type expr type-name)
```

Evaluates `expr`, checks that its value satisfies the named type in `debug`
mode, and returns the value. Useful for asserting types at arbitrary points
in code without annotating a whole function.

```scheme
(define (read-config path)
  (let ([raw (call-with-input-file path read)])
    (assert-type raw list)     ; must be a list at the top level
    (process-config raw)))
```

---

### Built-in Type Names

The following type names are recognized out of the box:

| Name          | Predicate         |
|---------------|-------------------|
| `fixnum`      | `fixnum?`         |
| `flonum`      | `flonum?`         |
| `string`      | `string?`         |
| `pair`        | `pair?`           |
| `vector`      | `vector?`         |
| `bytevector`  | `bytevector?`     |
| `boolean`     | `boolean?`        |
| `char`        | `char?`           |
| `symbol`      | `symbol?`         |
| `list`        | `list?`           |
| `number`      | `number?`         |
| `integer`     | `integer?`        |
| `real`        | `real?`           |
| `any`         | _(no check)_      |

#### Compound type specs

In addition to flat names, `type-predicate` understands these constructors:

```scheme
(listof string)          ; list whose every element is a string
(vectorof fixnum)        ; vector whose every element is a fixnum
(hashof symbol any)      ; hashtable (key/value types not checked per-entry)
(-> string number)       ; any procedure (only arity/type not verified at runtime)
```

---

### `register-type-predicate!` — extend the type registry

```scheme
(register-type-predicate! 'port port?)
(register-type-predicate! 'positive-integer
  (lambda (x) (and (integer? x) (positive? x))))
```

After registration the name works everywhere: `define/t`, `lambda/t`,
`assert-type`, `check-type!`, etc.

---

### `type-predicate` — look up a predicate

```scheme
(type-predicate 'string)      ; => string?
(type-predicate '(listof fixnum))  ; => compound predicate procedure
(type-predicate 'unknown)     ; => #f
```

Returns `#f` for unrecognized type specs.

---

### `check-type!` and `check-return-type!` — procedural checks

```scheme
(check-type! who arg-name val type-name)
(check-return-type! who val type-name)
```

The primitive checkers used internally by `define/t` and `lambda/t`. You can
call them directly to build custom validation helpers. Both are no-ops when
`(*typed-mode*)` is not `debug`.

```scheme
(define (validate-config! cfg)
  (check-type! 'validate-config! 'cfg cfg 'list)
  (for-each (lambda (entry)
              (check-type! 'validate-config! 'entry entry 'pair))
            cfg))
```

---

### `with-fixnum-ops` — fixnum arithmetic specialization

```
(with-fixnum-ops body ...)
```

A syntax transformer that walks `body` at macro-expansion time and replaces
generic arithmetic operators with their fixnum-specific variants:

| Generic    | Fixnum    |
|------------|-----------|
| `+`        | `fx+`     |
| `-`        | `fx-`     |
| `*`        | `fx*`     |
| `/`        | _(none)_  |
| `<`        | `fx<`     |
| `>`        | `fx>`     |
| `<=`       | `fx<=`    |
| `>=`       | `fx>=`    |
| `=`        | `fx=`     |
| `quotient` | `fxquotient` |
| `remainder`| `fxremainder` |
| `modulo`   | `fxmodulo` |
| `abs`      | `fxabs`   |
| `zero?`    | `fxzero?` |
| `positive?`| `fxpositive?` |
| `negative?`| `fxnegative?` |
| `min`      | `fxmin`   |
| `max`      | `fxmax`   |
| `add1`     | `fx1+`    |
| `sub1`     | `fx1-`    |

```scheme
(define (sum-fixnums xs)
  (with-fixnum-ops
    (let loop ([lst xs] [acc 0])
      (if (null? lst)
        acc
        (loop (cdr lst) (+ acc (car lst)))))))
```

Special forms (`if`, `let`, `lambda`, `cond`, `when`, etc.) are traversed
but their heads are never rewritten. Only operator positions are affected.

---

### `with-flonum-ops` — flonum arithmetic specialization

```
(with-flonum-ops body ...)
```

Same idea as `with-fixnum-ops`, replacing generic operators with their
flonum variants (`fl+`, `fl-`, `fl*`, `fl/`, `flsqrt`, `flsin`, `flcos`,
etc.). Includes transcendentals: `sqrt`, `floor`, `ceiling`, `round`,
`truncate`, `sin`, `cos`, `tan`, `exp`, `log`.

```scheme
(define (euclidean-distance x1 y1 x2 y2)
  (with-flonum-ops
    (let ([dx (- x2 x1)]
          [dy (- y2 y1)])
      (sqrt (+ (* dx dx) (* dy dy))))))
```

---

### Effect type annotations — `define/te` and `lambda/te`

```
(define/te (name [arg : type] ...) : (Effect EffectName ReturnType) body ...)
(lambda/te ([arg : type] ...) : (Effect EffectName ReturnType) body ...)
```

Effect types document that a function performs a named side effect and
returns a value of `ReturnType`. At runtime only the argument types and
`ReturnType` are checked; `EffectName` is informational for tooling and
documentation.

```scheme
(define/te (write-record! [db : any] [rec : pair]) : (Effect IO boolean)
  (db-insert! db rec))

(define/te (fetch-user [id : fixnum]) : (Effect IO pair)
  (db-query user-table id))
```

Fallback: if no `(Effect ...)` wrapper is present, `define/te` behaves
exactly like `define/t`.

#### Effect type descriptors

```scheme
(make-effect-type effect-name result-type) ; => effect-type record
(effect-type? x)                           ; => #t/#f
(effect-type-effect et)                    ; => effect-name symbol
(effect-type-result et)                    ; => result type symbol
```

These records are available for tooling that wants to inspect annotations at
runtime, but are not used internally by the assertion machinery.

---

## Advanced API — `(std typed advanced)`

### Step 14: Occurrence Typing

Occurrence typing narrows the type of a variable inside a conditional branch
based on the test predicate. The narrowing is inserted as an `assert-type`
call at the start of the branch body, making the type-checker (and the
reader) aware that the variable is more specific within that branch.

Supported narrowings:

| Predicate      | Narrowed type  |
|----------------|----------------|
| `string?`      | `string`       |
| `fixnum?`      | `fixnum`       |
| `flonum?`      | `flonum`       |
| `number?`      | `number`       |
| `integer?`     | `integer`      |
| `real?`        | `real`         |
| `pair?`        | `pair`         |
| `list?`        | `list`         |
| `null?`        | `null`         |
| `vector?`      | `vector`       |
| `symbol?`      | `symbol`       |
| `char?`        | `char`         |
| `boolean?`     | `boolean`      |
| `procedure?`   | `procedure`    |
| `bytevector?`  | `bytevector`   |
| `hashtable?`   | `hashtable`    |

#### `if/t`

```scheme
(if/t test then else)
```

In the `then` branch, if `test` is `(pred? var)` and `pred?` maps to a
known type, `var` is rebound with an `assert-type` annotation.

```scheme
(define (stringify x)
  (if/t (string? x)
    (string-append "[" x "]")   ; x narrowed to string here
    (number->string x)))
```

#### `when/t`

```scheme
(when/t test body ...)
```

Like `if/t` but for one-armed conditionals.

```scheme
(define (maybe-upcase x)
  (when/t (string? x)
    (string-upcase x)))   ; x narrowed to string in body
```

#### `unless/t`

```scheme
(unless/t test body ...)
```

Negated form. The body runs when `test` is false. (Internally expands to
`when/t (not test) ...`.)

#### `cond/t`

```scheme
(cond/t ([test body ...] ...)
        [else body ...])
```

Multi-branch version. Each clause whose test is a predicate application
narrows the tested variable in its body.

```scheme
(define (describe x)
  (cond/t
    [(string? x)  (string-append "string: " x)]
    [(fixnum? x)  (string-append "fixnum: " (number->string x))]
    [(pair? x)    (string-append "pair of length " (number->string (length x)))]
    [else         "unknown"]))
```

---

### Step 15: Row Polymorphism

Row types express structural constraints: "this object must have at least
these fields accessible by these accessors, with these types." Any record
type that satisfies the row shape passes the check, regardless of its
nominal type.

#### `defrow`

```
(defrow Name (field-name : Type) ...)
```

Defines a named row type and generates:

- `Name?` — predicate that returns `#t` if the object satisfies the row
- `check-Name!` — assertion that raises an error on failure

Field accessibility is checked at runtime by calling the accessor (resolved
via `eval` in the interaction environment) on the object and catching any
exception.

```scheme
(defrow Printable
  (to-string : procedure))

(defrow Drawable
  (draw!   : procedure)
  (x       : number)
  (y       : number))
```

After this:

```scheme
(Printable? my-obj)   ; => #t or #f
(check-Printable! my-obj)  ; raises if not satisfied
```

#### `row-check`

```
(row-check obj-expr row-name)
(row-check obj-expr (field-name : Type) ...)
```

Inline row check without needing a named `defrow`. Returns `#t` or `#f`.

```scheme
;; Named row
(row-check widget Drawable)

;; Anonymous inline row
(row-check config
  (host : string)
  (port : fixnum))
```

#### `row?`

```scheme
(row? 'Printable)   ; => row-type record or #f
```

Looks up a named row type from the registry.

#### `row-type?`

Predicate for the `row-type` record type itself (distinguishes row-type
descriptors from other values).

---

### Step 16: Refinement Types

A refinement type combines a base type with an additional predicate. The
value must satisfy both.

#### `make-refinement-type`

```scheme
(make-refinement-type 'integer positive?)
; => refinement-type record: base=integer, pred=positive?
```

#### Accessors

```scheme
(refinement-type? x)          ; predicate
(refinement-type-base rt)     ; => base type symbol
(refinement-type-pred rt)     ; => predicate procedure or symbol
```

#### `check-refinement!`

```scheme
(check-refinement! who name val base pred-spec)
```

In `debug` mode: first checks that `val` satisfies `base`, then calls
`pred-spec` on `val`. Either check failure raises an error. `pred-spec` may
be a procedure or a symbol (resolved via `eval`).

#### `assert-refined`

```
(assert-refined expr base-type pred-expr)
```

Inline macro version. Evaluates `expr`, runs both checks, and returns the
value.

```scheme
(define (set-port! [p : fixnum])
  (assert-refined p integer positive?)   ; must be a positive integer
  ...)

;; Or with a lambda predicate
(define (bounded-index! [i : fixnum])
  (assert-refined i fixnum (lambda (n) (and (>= n 0) (< n max-index))))
  ...)
```

---

### Step 17: Type-Directed Compilation

`define/tc` and `lambda/tc` extend `define/t` and `lambda/t` with
automatic arithmetic specialization based on declared types.

**Specialization rules:**

- All arguments _and_ return type are `fixnum` → body wrapped in
  `(with-fixnum-ops ...)` automatically
- All arguments _and_ return type are `flonum` → body wrapped in
  `(with-flonum-ops ...)`
- Mixed or other types → no specialization (generic ops, return type
  checked normally)

```
(define/tc (name [arg : type] ...) : ret-type body ...)
(lambda/tc ([arg : type] ...) : ret-type body ...)
```

```scheme
;; All fixnum → automatic fx+ fx- fx* rewriting, zero overhead in release
(define/tc (dot-product-int [a : fixnum] [b : fixnum] [c : fixnum] [d : fixnum]) : fixnum
  (+ (* a c) (* b d)))

;; All flonum → automatic fl+ fl* etc.
(define/tc (hypot [x : flonum] [y : flonum]) : flonum
  (sqrt (+ (* x x) (* y y))))

;; Mixed → no rewriting, just type checks
(define/tc (format-value [n : number] [label : string]) : string
  (string-append label ": " (number->string n)))
```

`define/tc` also handles `(Refine base pred)` annotations in argument
position:

```scheme
(define/tc (sqrt-positive [x : (Refine flonum flpositive?)]) : flonum
  (flsqrt x))
```

In `debug` mode this checks both that `x` is a `flonum` and that
`(flpositive? x)` holds before executing the body.

---

### Union and Intersection type specs

```
(Union T1 T2 ...)
(Intersection T1 T2 ...)
```

These produce predicate procedures at runtime. They can be passed to
`register-type-predicate!` to give the combined type a name.

```scheme
(register-type-predicate! 'number-or-string
  (Union number string))

(register-type-predicate! 'positive-real
  (Intersection real (lambda (x) (positive? x))))

(define/t (display-value [x : number-or-string]) : string
  (if (number? x) (number->string x) x))
```

---

## Complete Example

```scheme
(import (chezscheme)
        (std typed)
        (std typed advanced))

;; ---- Custom type ----
(register-type-predicate! 'non-empty-string
  (lambda (s) (and (string? s) (> (string-length s) 0))))

;; ---- Basic typed define ----
(define/t (greet [name : non-empty-string]) : string
  (string-append "Hello, " name "!"))

;; ---- Type-directed fixnum arithmetic ----
(define/tc (factorial [n : fixnum]) : fixnum
  (if (fxzero? n) 1 (fx* n (factorial (fx1- n)))))

;; ---- Occurrence typing ----
(define (safe-length x)
  (cond/t
    [(list?   x) (length x)]
    [(string? x) (string-length x)]
    [(vector? x) (vector-length x)]
    [else (error 'safe-length "unsupported type" x)]))

;; ---- Row polymorphism ----
(defrow Named
  (name : string))

(define (print-name obj)
  (check-Named! obj)
  (display (name obj)))

;; ---- Refinement type ----
(define (safe-sqrt [x : (Refine flonum flpositive?)])
  (define/tc ([x : (Refine flonum flpositive?)]) : flonum
    (flsqrt x)))

;; ---- Effect annotation ----
(define/te (read-line! [port : any]) : (Effect IO string)
  (get-line port))

;; ---- Switch to release for production ----
;; (*typed-mode* 'release)  ; all checks become no-ops
```

---

## Performance Notes

| Scenario | Recommendation |
|---|---|
| Development / CI | Keep `(*typed-mode* 'debug)` (default). Annotations catch bugs early with descriptive messages. |
| Production binary | Set `(*typed-mode* 'release)` at startup or in your build entry point. |
| Hot inner loops with fixnum math | Use `define/tc` with full fixnum annotations; get `fx*` etc. for free. |
| Hot inner loops with flonum math | Use `define/tc` with full flonum annotations; get `fl*`, `flsqrt`, etc. |
| Annotating library boundaries only | Annotate public-facing functions; leave internal helpers untyped or use `assert-type` at key points. |
| `(listof T)` on large lists | The predicate walks every element. Prefer `list?` if the annotation is just documentation. |

`with-fixnum-ops` and `with-flonum-ops` are pure compile-time rewrites —
they have identical performance to writing `fx+` / `fl+` by hand.

The effect of `(*typed-mode* 'release)` is runtime, not compile-time. If
you need truly zero-overhead release builds, wrap `define/t` forms in a
`when` on a compile-time constant, or use `define/tc` which only emits
checks inside `(when (eq? (*typed-mode*) 'debug) ...)` guards that Chez can
optimize away.
