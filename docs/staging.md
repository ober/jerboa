# Metaprogramming and Staging — `(std staging)`

The `(std staging)` library provides tools for compile-time computation and code generation in Chez Scheme. It is organized around three themes:

- **Compile-time computation** (`at-compile-time`, `define/ct`): evaluate expressions at macro-expansion time and embed the results as constants
- **Code generation DSL** (`format-id`, `derive-serializer`, `derive-printer`, `quasigen`, `with-gensyms`, `define-staging-type`, `struct-fields`): build and emit Scheme code programmatically from macros
- **Syntax-rules extensions** (`defrule/guard`, `defrule/rec`, `syntax-walk`): enhanced macro-definition forms for guarded rules and recursive tree rewriting

## Table of Contents

1. [Quick Start](#quick-start)
2. [Core API](#core-api)
   - [at-compile-time](#at-compile-time)
   - [define/ct](#definect)
   - [format-id](#format-id)
   - [define-staging-type and struct-fields](#define-staging-type-and-struct-fields)
   - [derive-serializer](#derive-serializer)
   - [derive-printer](#derive-printer)
   - [quasigen](#quasigen)
   - [with-gensyms](#with-gensyms)
   - [defrule/guard](#defruleguard)
   - [defrule/rec](#defrulerec)
   - [syntax-walk](#syntax-walk)
3. [Complete Examples](#complete-examples)
4. [When to Use Staging vs Runtime Computation](#when-to-use-staging-vs-runtime-computation)

---

## Quick Start

```scheme
(import (chezscheme) (std staging))

;; Compute a constant at expand time
(define/ct pi (acos -1.0))
;; expands to: (define pi '3.141592653589793)

;; Generate identifiers in macros
(define-syntax make-accessor
  (lambda (stx)
    (syntax-case stx ()
      [(_ type field)
       (let ([getter (format-id #'type "~a-~a" #'type #'field)])
         #`(define (#,getter obj) (slot-ref obj 'field)))])))

;; Hygienic temporaries
(define-syntax safe-div
  (lambda (stx)
    (syntax-case stx ()
      [(_ a b)
       (with-gensyms (tmp)
         #`(let ([#,tmp b])
             (if (zero? #,tmp) #f (/ a #,tmp))))])))
```

---

## Core API

### `at-compile-time`

```scheme
(at-compile-time expr)
```

Evaluates `expr` at macro-expansion time (using `eval` in the `(chezscheme)` environment) and splices the result in as a quoted datum. The expression is evaluated once, when the surrounding form is compiled. At runtime, the surrounding definition holds a constant.

The result can be any Scheme value: number, string, list, boolean, symbol, vector, etc.

```scheme
;; Transcendental constants computed once at compile time
(define pi      (at-compile-time (acos -1.0)))
(define two-pi  (at-compile-time (* 2.0 (acos -1.0))))
(define log2    (at-compile-time (log 2.0)))

;; String manipulation at compile time
(define app-banner
  (at-compile-time (string-append "MyApp v" "1.0.0")))

;; Build a table at compile time
(define squares
  (at-compile-time
    (let loop ([i 0] [acc '()])
      (if (= i 10)
        (list->vector (reverse acc))
        (loop (+ i 1) (cons (* i i) acc))))))
;; => '#(0 1 4 9 16 25 36 49 64 81)
```

Constraints:
- `expr` is evaluated in a fresh `(chezscheme)` environment — it cannot reference runtime bindings from the enclosing module.
- Only pure Scheme values survive the eval→datum round-trip. Procedures, ports, and other opaque objects cannot be embedded.

### `define/ct`

```scheme
(define/ct name expr)
```

Defines `name` as a constant whose value is computed at expand time. Equivalent to:

```scheme
(define name (at-compile-time expr))
```

Use `define/ct` when you want a named compile-time constant at the top level.

```scheme
(define/ct max-connections 1024)
(define/ct default-timeout 30)
(define/ct port-range      (list 80 443 8080))
(define/ct factorial-10
  (let loop ([i 1] [acc 1])
    (if (> i 10) acc (loop (+ i 1) (* acc i)))))

factorial-10  ; => 3628800 (the constant, not a computation)
```

### `format-id`

```scheme
(format-id context-id fmt arg ...) => identifier
```

Creates a new syntax identifier by formatting a name string. This is the Jerboa equivalent of Racket's `format-id`. It is a runtime procedure intended to be called inside macro transformers.

- `context-id` — a syntax identifier used for lexical context and source location of the new identifier
- `fmt` — a format string (Chez `format` style, `~a` for values)
- `arg ...` — arguments: syntax identifiers have their symbol name extracted automatically; strings and other values are formatted with `~a`

```scheme
;; Inside a macro transformer:
(define-syntax define-pair
  (lambda (stx)
    (syntax-case stx ()
      [(_ name a-val b-val)
       (let ([fst (format-id #'name "~a-fst" #'name)]
             [snd (format-id #'name "~a-snd" #'name)])
         #`(begin
             (define (#,fst) a-val)
             (define (#,snd) b-val)))])))

(define-pair origin 0 0)
(origin-fst)  ; => 0
(origin-snd)  ; => 0

;; With string prefix
(define-syntax make-checker
  (lambda (stx)
    (syntax-case stx ()
      [(_ name pred)
       (let ([checker (format-id #'name "is-~a?" #'name)])
         #`(define (#,checker x) (pred x)))])))

(make-checker even even?)
(is-even? 4)   ; => #t
(is-even? 3)   ; => #f
```

`format-id` uses `datum->syntax` with the provided context identifier, so the generated identifier participates correctly in hygiene and source tracking.

### `define-staging-type` and `struct-fields`

```scheme
(define-staging-type type-name pred-fn (field ...) (acc ...))
```

Registers a struct type in the staging registry for runtime introspection. This is separate from the `(std match2)` registry — `define-staging-type` is specifically for use with `struct-fields`, `derive-serializer`, and `derive-printer`.

- `type-name` — symbol naming the type
- `pred-fn` — predicate procedure
- `(field ...)` — field name symbols
- `(acc ...)` — accessor procedures in the same order as the fields

```scheme
(define-record-type (point make-point point?)
  (fields (immutable x point-x) (immutable y point-y)))

(define-staging-type point point? (x y) (point-x point-y))
```

```scheme
(struct-fields name) => list-of-symbols
```

Returns the field name list for a type registered with `define-staging-type`, or `'()` if the type is unknown.

```scheme
(struct-fields 'point)      ; => '(x y)
(struct-fields 'unknown)    ; => '()
```

`struct-fields` is a runtime procedure. To use field information at compile time (inside a macro), call it inside the macro transformer body (which runs at expand time). Note that the type must have been registered before the macro expansion runs; for types defined in the same file, use `eval` or place the `define-staging-type` in an earlier phase.

### `derive-serializer`

```scheme
(derive-serializer struct-name (field ...) (acc ...))
```

Macro that generates a serializer procedure named `serialize-<struct-name>`. The generated procedure writes each field as a `(field-name . value)` cons pair to a port.

Fields and accessors are specified explicitly (rather than looked up from `define-staging-type`) to avoid R6RS phase issues.

**Generated signature:**
```scheme
(serialize-<struct-name> obj port) => void
```

```scheme
(define-record-type (person make-person person?)
  (fields (immutable name person-name)
          (immutable age  person-age)))

(derive-serializer person (name age) (person-name person-age))

;; Usage:
(let ([out (open-output-string)])
  (serialize-person (make-person "Alice" 30) out)
  (get-output-string out))
; => "(name . Alice)(age . 30)"
```

Each field is written using `write`, which means strings are written with quotes, symbols with their notation, etc. The output is a sequence of `write`-format cons pairs with no separator between them.

### `derive-printer`

```scheme
(derive-printer struct-name (field ...) (acc ...))
```

Macro that generates a pretty-printer procedure named `print-<struct-name>`. The generated procedure returns a string in `#<type-name field=value ...>` format.

**Generated signature:**
```scheme
(print-<struct-name> obj) => string
```

```scheme
(define-record-type (color make-color color?)
  (fields (immutable r color-r)
          (immutable g color-g)
          (immutable b color-b)))

(derive-printer color (r g b) (color-r color-g color-b))

(print-color (make-color 255 0 128))
; => "#<color r=255 g=0 b=128>"
```

Field values are formatted with `~a` (display format), not `write`. Use `derive-serializer` when you need round-trippable output.

### `quasigen`

```scheme
(quasigen ctx-id body ...)
```

Creates a code-generating lambda that takes a single context identifier argument `ctx-id` and returns the syntax produced by `body ...`. This is a lightweight way to package a parameterized code generator.

```scheme
(quasigen ctx-id body ...)
;; expands to:
(lambda (ctx-id) body ...)
```

Typical use: define a generator at the module level, then invoke it inside macro transformers.

```scheme
;; Define a reusable generator
(define gen-validator
  (quasigen ctx
    (let ([pred-id (format-id ctx "valid-~a?" ctx)])
      #`(define (#,pred-id x) (and (number? x) (positive? x))))))

;; Use in a macro
(define-syntax make-validator
  (lambda (stx)
    (syntax-case stx ()
      [(_ name)
       (gen-validator #'name)])))

(make-validator amount)
(valid-amount? 10)   ; => #t
(valid-amount? -1)   ; => #f
(valid-amount? "x")  ; => #f
```

### `with-gensyms`

```scheme
(with-gensyms (id ...) body ...)
```

Binds each `id` to a fresh unique syntax temporary (via `generate-temporaries`), then evaluates `body ...` with those bindings in scope. Use inside macro transformers to create hygienic temporaries that cannot capture surrounding bindings.

```scheme
(define-syntax swap!
  (lambda (stx)
    (syntax-case stx ()
      [(_ a b)
       (with-gensyms (tmp)
         #`(let ([#,tmp a])
             (set! a b)
             (set! b #,tmp)))])))

(let ([x 1] [y 2])
  (swap! x y)
  (list x y))
; => '(2 1)
```

Multiple gensyms at once:

```scheme
(define-syntax memoize-1
  (lambda (stx)
    (syntax-case stx ()
      [(_ f)
       (with-gensyms (cache key val)
         #`(let ([#,cache (make-equal-hashtable)])
             (lambda (#,key)
               (or (hashtable-ref #,cache #,key #f)
                   (let ([#,val (f #,key)])
                     (hashtable-set! #,cache #,key #,val)
                     #,val)))))])))
```

### `defrule/guard`

```scheme
(defrule/guard (name pat ...) (where guard-expr) template)
(defrule/guard (name pat ...) template)
```

Defines a macro with an optional compile-time guard. The two-argument form (no guard) is equivalent to `define-syntax` with `syntax-rules`. The three-argument form (with `(where guard-expr)`) adds a fender: the macro only applies if `guard-expr` evaluates to a truthy value at expand time.

The guard runs via `eval` in the `(chezscheme)` environment at expand time. It cannot reference runtime values, but it CAN reference pattern variables as their syntax object representations.

```scheme
;; Without guard — simple abbreviation macro
(defrule/guard (my-when test body ...)
  (if test (begin body ...) (void)))

;; With guard — only applies when the test expression looks like a number literal
(defrule/guard (double-if-number x)
  (where (number? (syntax->datum #'x)))
  (* 2 x))

(double-if-number 21)   ; => 42
;; (double-if-number "hi") => syntax error: guard failed
```

Note: the `(where ...)` guard must be the second element (immediately after the pattern), before the template.

### `defrule/rec`

```scheme
(defrule/rec name transformer-proc)
```

Defines a macro named `name` that applies `transformer-proc` recursively to a syntax tree. The transformer is called on each node depth-first:

- If it returns a syntax object, that object replaces the node (no further descent into the replacement).
- If it returns `#f`, the node is descended into (for list/pair nodes) or left as-is (for atoms).

Usage: `(name expr)` returns the recursively transformed expression.

```scheme
;; Replace all occurrences of 'old-name with 'new-name in a tree
(define rename-x->y
  (lambda (stx)
    (if (and (identifier? stx)
             (eq? (syntax->datum stx) 'x))
      #'y
      #f)))

(defrule/rec rename-x rename-x->y)

(rename-x (let ([x 1]) (+ x x)))
;; => (let ([y 1]) (+ y y))  [conceptually — actual hygiene applies]
```

### `syntax-walk`

```scheme
(syntax-walk stx proc) => stx
```

Runtime procedure that walks a syntax tree depth-first, applying `proc` to each node. `proc` takes a syntax object and returns either a replacement syntax object or `#f`. When `#f` is returned, the walker descends into the node's children (if it is a list). Atoms that return `#f` from `proc` are returned unchanged.

`defrule/rec` is built on `syntax-walk`. Call `syntax-walk` directly when you need to walk a tree inside a macro transformer without the overhead of a named macro.

```scheme
;; Walk and collect all identifiers
(define (collect-ids stx)
  (let ([ids '()])
    (syntax-walk stx
      (lambda (node)
        (when (identifier? node)
          (set! ids (cons (syntax->datum node) ids)))
        #f))
    (reverse ids)))
```

Note: `syntax-walk` reconstructs list nodes using `datum->syntax` with the first element as the context identifier, so the resulting tree retains hygiene anchored to the original list heads.

---

## Complete Examples

### Compile-Time Math Constants

```scheme
(import (chezscheme) (std staging))

;; Transcendental and derived constants computed once
(define/ct pi       (acos -1.0))
(define/ct tau      (* 2.0 (acos -1.0)))
(define/ct e        (exp 1.0))
(define/ct sqrt2    (sqrt 2.0))
(define/ct ln2      (log 2.0))
(define/ct deg->rad (/ (acos -1.0) 180.0))

;; A lookup vector computed at compile time
(define/ct sin-table
  (let ([n 360])
    (let loop ([i 0] [acc '()])
      (if (= i n)
        (list->vector (reverse acc))
        (loop (+ i 1)
              (cons (sin (* i (/ (acos -1.0) 180.0))) acc))))))

;; Fast sine lookup (integer degrees only)
(define (sin-deg d)
  (vector-ref sin-table (modulo d 360)))
```

### Code Generation for Repeated Patterns

```scheme
(import (chezscheme) (std staging))

;; Generate a family of clamping functions: clamp-byte, clamp-short, etc.
(define gen-clamp
  (quasigen ctx
    (let ([fn-id  (format-id ctx "clamp-~a" ctx)]
          [min-id (format-id ctx "~a-min" ctx)]
          [max-id (format-id ctx "~a-max" ctx)])
      #`(begin
          (define (#,fn-id lo hi v)
            (cond [(< v lo) lo]
                  [(> v hi) hi]
                  [else v]))
          (define (#,min-id v) (#,fn-id 0 255 v))
          (define (#,max-id v) (#,fn-id -32768 32767 v))))))

(define-syntax define-clamp-family
  (lambda (stx)
    (syntax-case stx ()
      [(_ name) (gen-clamp #'name)])))

;; Each invocation generates 3 functions:
(define-syntax clamp-types
  (lambda (stx)
    (syntax-case stx ()
      [(_ name ...)
       #`(begin #,@(map gen-clamp (syntax->list #'(name ...))))])))

;; Manual expansion of the pattern:
(define (clamp-byte lo hi v)
  (cond [(< v lo) lo] [(> v hi) hi] [else v]))
```

### Auto-Deriving Serializer for a Struct

```scheme
(import (chezscheme) (std staging))

;; Define a record
(define-record-type (user make-user user?)
  (fields
    (immutable id       user-id)
    (immutable username user-username)
    (immutable email    user-email)
    (immutable age      user-age)))

;; Register for introspection
(define-staging-type user user?
  (id username email age)
  (user-id user-username user-email user-age))

;; Derive both serializer and printer
(derive-serializer user
  (id username email age)
  (user-id user-username user-email user-age))

(derive-printer user
  (id username email age)
  (user-id user-username user-email user-age))

;; Try them out
(define alice (make-user 1 "alice" "alice@example.com" 30))

(print-user alice)
; => "#<user id=1 username=alice email=alice@example.com age=30>"

(let ([port (open-output-string)])
  (serialize-user alice port)
  (get-output-string port))
; => "(id . 1)(username . alice)(email . alice@example.com)(age . 30)"

;; Field names available at runtime
(struct-fields 'user)
; => '(id username email age)
```

### Hygienic Macro with Gensyms

```scheme
(import (chezscheme) (std staging))

;; A memoizing let that evaluates each init-expr only once,
;; even if the result is used multiple times in body.
(define-syntax memolet
  (lambda (stx)
    (syntax-case stx ()
      [(_ ([var expr] ...) body ...)
       ;; Generate a fresh cache variable for each binding
       (with-gensyms (cache)
         ;; For a single cache-per-var example:
         #`(let ([var expr] ...)
             body ...))])))

;; A thread-safe "run once" initialization macro
(define-syntax run-once
  (lambda (stx)
    (syntax-case stx ()
      [(_ body ...)
       (with-gensyms (done? result)
         #`(let ([#,done?  #f]
                 [#,result #f])
             (lambda ()
               (if #,done?
                 #,result
                 (begin
                   (set! #,result (begin body ...))
                   (set! #,done? #t)
                   #,result)))))])))

(define init-db!
  (run-once
    (display "connecting...")
    'connected))

(init-db!)  ; prints "connecting...", returns 'connected
(init-db!)  ; returns 'connected (no recomputation)
```

---

## When to Use Staging vs Runtime Computation

**Use staging when:**

- The value is truly constant and known at compile time (mathematical constants, version strings, small static tables).
- You are generating code in a macro transformer and need to construct identifiers from naming conventions (`format-id`).
- You want to auto-derive boilerplate (serializers, printers) from field lists without writing repetitive code.
- You need hygienic temporaries in a macro and want to avoid naming conflicts (`with-gensyms`).
- You are writing a macro that must inspect or rewrite syntax trees (`syntax-walk`, `defrule/rec`).

**Use runtime computation when:**

- The value depends on user input, environment variables, file contents, or any external state.
- The computation is expensive but not constant (e.g., database queries, network calls).
- The value may differ between program runs.
- You need to update the value without recompiling (configuration, feature flags).

**Heuristic:** If the answer would be the same in every binary produced from the same source file, staging is appropriate. If it could differ between runs on the same binary, use runtime computation.

A common pattern is to combine both: use `define/ct` for the constant parts of a computation (e.g., a precomputed table), and reference those constants at runtime in functions that handle the dynamic parts.
