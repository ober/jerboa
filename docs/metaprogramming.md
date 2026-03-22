# Metaprogramming and Advanced Abstraction Modules

This document covers six modules in the `(std misc ...)` namespace that provide
advanced metaprogramming, type abstraction, and interception facilities.

## Table of Contents

- [1. Typeclasses -- `(std misc typeclass)`](#1-typeclasses----std-misc-typeclass)
- [2. CK Macros -- `(std misc ck-macros)`](#2-ck-macros----std-misc-ck-macros)
- [3. Format String Compilation -- `(std misc fmt)`](#3-format-string-compilation----std-misc-fmt)
- [4. Chaperones and Impersonators -- `(std misc chaperone)`](#4-chaperones-and-impersonators----std-misc-chaperone)
- [5. Advice System -- `(std misc advice)`](#5-advice-system----std-misc-advice)
- [6. Binary Type Framework -- `(std misc binary-type)`](#6-binary-type-framework----std-misc-binary-type)

---

## 1. Typeclasses -- `(std misc typeclass)`

**Source:** `lib/std/misc/typeclass.sls`

```scheme
(import (std misc typeclass))
```

### Overview

Haskell-style typeclasses via dictionary-passing. Define typeclasses with
named methods, create instances for specific types, and dispatch method calls
through a global registry. Supports single inheritance via `extends`.

Three typeclasses (`Eq`, `Ord`, `Show`) and instances for `number`, `string`,
and `symbol` are provided out of the box.

### API Reference

| Identifier | Kind | Description |
|---|---|---|
| `define-typeclass` | macro | Define a new typeclass with method signatures |
| `define-instance` | macro | Define an instance binding methods to implementations |
| `typeclass-dispatch` | procedure | `(typeclass-dispatch class-name type-name method-name)` -- returns the method procedure |
| `tc-ref` | procedure | Alias for `typeclass-dispatch` |
| `tc-apply` | procedure | `(tc-apply class-name method-name type-name arg ...)` -- dispatch and apply in one call |
| `typeclass-instance?` | procedure | `(typeclass-instance? class-name type-name)` -- returns `#t` if an instance exists |
| `typeclass-instance-of?` | procedure | Alias for `typeclass-instance?` |
| `lookup-instance` | procedure | `(lookup-instance class-name type-name)` -- returns the method dictionary hashtable, or `#f` |
| `lookup-typeclass` | procedure | `(lookup-typeclass name)` -- returns the typeclass metadata record, or `#f` |
| `register-typeclass!` | procedure | `(register-typeclass! name method-names supers)` -- low-level registration |
| `register-instance!` | procedure | `(register-instance! class-name type-name dict)` -- low-level instance registration |
| `build-instance-dict` | procedure | `(build-instance-dict class-name type-name method-pairs)` -- build a method dictionary, inheriting from superclasses |

### Built-in Typeclasses

| Typeclass | Methods | Extends |
|---|---|---|
| `Eq` | `eq?` | -- |
| `Ord` | `compare`, `lt?`, `gt?`, `le?`, `ge?` | `Eq` |
| `Show` | `->string` | -- |

Built-in instances exist for types `number`, `string`, and `symbol`.

### Usage Examples

**Defining a typeclass:**

```scheme
(define-typeclass (Eq a)
  (eq? a a -> boolean))

;; With superclass inheritance:
(define-typeclass (Ord a) extends (Eq a)
  (compare a a -> integer)
  (lt? a a -> boolean))
```

**Defining an instance:**

```scheme
(define-instance (Eq number)
  (eq? =))

(define-instance (Show number)
  (->string number->string))
```

**Dispatching methods:**

```scheme
;; Using tc-apply (class, method, type, then args):
(tc-apply 'Eq 'eq? 'number 1 2)       ;=> #f
(tc-apply 'Eq 'eq? 'number 5 5)       ;=> #t
(tc-apply 'Show '->string 'number 42) ;=> "42"
(tc-apply 'Ord 'lt? 'number 1 5)      ;=> #t

;; Getting a method procedure directly:
(define num-eq? (typeclass-dispatch 'Eq 'number 'eq?))
(num-eq? 3 3)  ;=> #t

;; Checking instance existence:
(typeclass-instance? 'Eq 'number)  ;=> #t
(typeclass-instance? 'Eq 'list)    ;=> #f
```

**Defining a custom typeclass and instance:**

```scheme
(define-typeclass (Serializable a)
  (serialize a -> bytevector)
  (deserialize bytevector -> a))

(define-instance (Serializable number)
  (serialize (lambda (n) (string->utf8 (number->string n))))
  (deserialize (lambda (bv) (string->number (utf8->string bv)))))

(tc-apply 'Serializable 'serialize 'number 42)
;=> #vu8(52 50)
```

---

## 2. CK Macros -- `(std misc ck-macros)`

**Source:** `lib/std/misc/ck-macros.sls`

```scheme
(import (std misc ck-macros))
```

### Overview

An implementation of Oleg Kiselyov's CK abstract machine for composable
higher-order macros. All computation happens at macro-expansion time using only
`syntax-rules` -- no `syntax-case` required. CK macros pass results to a
continuation stack, enabling composition of macro-time list operations.

All CK macro arguments must be either **quoted values** (`'datum`) or
**CK expressions** (`(c-op args ...)`). The `ck` machine evaluates nested
CK expressions automatically.

### API Reference

| Identifier | Kind | Description |
|---|---|---|
| `ck` | macro | The CK machine entry point. `(ck () expr)` evaluates `expr` and returns the result. |
| `c-quote` | macro | `(c-quote v)` -- quote a value (identity in CK) |
| `c-cons` | macro | `(c-cons a b)` -- cons two values at expansion time |
| `c-car` | macro | `(c-car pair)` -- car of a quoted pair |
| `c-cdr` | macro | `(c-cdr pair)` -- cdr of a quoted pair |
| `c-null?` | macro | `(c-null? v)` -- returns `'#t` for `'()`, `'#f` otherwise |
| `c-if` | macro | `(c-if test then else)` -- conditional; `'#f` selects else, anything else selects then |
| `c-map` | macro | `(c-map (f ...) list)` -- map a CK function over a list |
| `c-filter` | macro | `(c-filter (pred ...) list)` -- filter a list by a CK predicate |
| `c-foldr` | macro | `(c-foldr (f ...) init list)` -- right fold over a list |
| `c-append` | macro | `(c-append list1 list2)` -- append two lists |
| `c-reverse` | macro | `(c-reverse list)` -- reverse a list (O(n) accumulator) |
| `c-length` | macro | `(c-length list)` -- returns length as Peano-encoded list: `'()` = 0, `'(s)` = 1, `'(s s)` = 2 |

### Usage Examples

**Basic list operations (all at expansion time):**

```scheme
(ck () (c-cons '1 '(2 3)))
;=> (1 2 3)

(ck () (c-car '(a b c)))
;=> a

(ck () (c-cdr '(a b c)))
;=> (b c)

(ck () (c-reverse '(a b c)))
;=> (c b a)

(ck () (c-append '(1 2) '(3 4)))
;=> (1 2 3 4)
```

**Conditional:**

```scheme
(ck () (c-if '#t 'yes 'no))
;=> yes

(ck () (c-if '#f 'yes 'no))
;=> no
```

**Mapping with a partially applied CK function:**

```scheme
;; (c-cons 'x) is a partial application -- maps each element h to (x . h)
(ck () (c-map (c-cons 'x) '(1 2 3)))
;=> ((x . 1) (x . 2) (x . 3))
```

**Composing CK expressions:**

```scheme
;; Nested CK calls are evaluated automatically:
(ck () (c-reverse (c-append '(a b) '(c d))))
;=> (d c b a)

(ck () (c-car (c-reverse '(a b c))))
;=> c
```

**Getting the length as a Peano number:**

```scheme
(ck () (c-length '(a b c)))
;=> (s s s)

;; Convert to runtime number:
(length (ck () (c-length '(a b c d e))))
;=> 5
```

**Right fold:**

```scheme
(ck () (c-foldr (c-cons) '() '(a b c)))
;=> (a b c)
```

---

## 3. Format String Compilation -- `(std misc fmt)`

**Source:** `lib/std/misc/fmt.sls`

```scheme
(import (std misc fmt))
```

### Overview

A format string system with two modes: **compile-time** format string parsing
via the `compile-format` macro (zero runtime parsing overhead) and **runtime**
formatting via `fmt` and `fmt/port`. Also provides string padding helpers.

### Format Directives

| Directive | Description |
|---|---|
| `~a` | Display (like `display`) |
| `~s` | Write (like `write`, with quotes for strings) |
| `~d` | Decimal number |
| `~b` | Binary number |
| `~o` | Octal number |
| `~x` | Hexadecimal number (lowercase) |
| `~%` | Newline |
| `~~` | Literal tilde |
| `~Nw` | Display with right-padded width of N characters (e.g., `~10w`) |

### API Reference

| Identifier | Kind | Description |
|---|---|---|
| `compile-format` | macro | `(compile-format "fmt-str")` -- compiles a format string into a lambda at macro-expansion time. The string must be a literal. |
| `fmt` | procedure | `(fmt fmt-str arg ...)` -- format to a string at runtime |
| `fmt/port` | procedure | `(fmt/port port fmt-str arg ...)` -- format to a port at runtime |
| `pad-left` | procedure | `(pad-left str width [char])` -- left-pad `str` to `width` with `char` (default: space) |
| `pad-right` | procedure | `(pad-right str width [char])` -- right-pad `str` to `width` with `char` (default: space) |

### Usage Examples

**Compile-time format strings (zero runtime parsing):**

```scheme
(define fmt-point (compile-format "Point(~a, ~a)"))
(fmt-point 3 4)
;=> "Point(3, 4)"

(define fmt-hex (compile-format "0x~x"))
(fmt-hex 255)
;=> "0xff"

(define fmt-bin (compile-format "~a in binary: ~b"))
(fmt-bin 42 42)
;=> "42 in binary: 101010"
```

**Runtime formatting:**

```scheme
(fmt "~a + ~a = ~a" 1 2 3)
;=> "1 + 2 = 3"

(fmt "hex: ~x, oct: ~o, bin: ~b" 255 255 255)
;=> "hex: ff, oct: 377, bin: 11111111"

(fmt "Name: ~10w Age: ~a" "Alice" 30)
;=> "Name: Alice      Age: 30"

(fmt "~s is a string" "hello")
;=> "\"hello\" is a string"

(fmt "100~~ complete~%done")
;=> "100~ complete\ndone"
```

**Formatting to a port:**

```scheme
(fmt/port (current-output-port) "hello ~a~%" "world")
;; prints: hello world
;;         (followed by newline)
```

**String padding:**

```scheme
(pad-left "42" 6)        ;=> "    42"
(pad-left "42" 6 #\0)    ;=> "000042"
(pad-right "hi" 10)      ;=> "hi        "
(pad-right "hi" 10 #\.)  ;=> "hi........"
(pad-left "toolong" 3)   ;=> "toolong"  (no truncation)
```

---

## 4. Chaperones and Impersonators -- `(std misc chaperone)`

**Source:** `lib/std/misc/chaperone.sls`

```scheme
(import (std misc chaperone))
```

### Overview

Transparent proxies that intercept operations on values, inspired by Racket's
chaperone/impersonator system. **Chaperones** enforce contracts via interceptors
(the interceptor should return an equivalent value). **Impersonators** can
freely transform arguments and results. Supports procedure, vector, and
hashtable wrapping. Chaperones can be layered (chaperone of a chaperone).

### API Reference

| Identifier | Kind | Description |
|---|---|---|
| `chaperone-procedure` | procedure | `(chaperone-procedure proc args-interceptor [result-interceptor])` -- wrap a procedure with argument and/or result interception |
| `impersonate-procedure` | procedure | `(impersonate-procedure proc args-interceptor [result-interceptor])` -- like `chaperone-procedure` but allows arbitrary transformation |
| `chaperone-vector` | procedure | `(chaperone-vector vec ref-interceptor [set-interceptor])` -- wrap a vector |
| `chaperone-vector-ref` | procedure | `(chaperone-vector-ref cv idx)` -- read from a chaperoned vector |
| `chaperone-vector-set!` | procedure | `(chaperone-vector-set! cv idx val)` -- write to a chaperoned vector |
| `chaperone-hashtable` | procedure | `(chaperone-hashtable ht ref-interceptor [set-interceptor [delete-interceptor]])` -- wrap a hashtable |
| `chaperone-hashtable-ref` | procedure | `(chaperone-hashtable-ref ch key default)` -- read from a chaperoned hashtable |
| `chaperone-hashtable-set!` | procedure | `(chaperone-hashtable-set! ch key val)` -- write to a chaperoned hashtable |
| `chaperone-hashtable-delete!` | procedure | `(chaperone-hashtable-delete! ch key)` -- delete from a chaperoned hashtable |
| `chaperone?` | procedure | `(chaperone? v)` -- returns `#t` if `v` is a chaperone or impersonator |
| `chaperone-of?` | procedure | `(chaperone-of? v1 v2)` -- returns `#t` if `v1` wraps `v2` (directly or transitively) |
| `chaperone-unwrap` | procedure | `(chaperone-unwrap v)` -- strip all chaperone layers, returning the innermost value |

### Usage Examples

**Procedure chaperone (logging):**

```scheme
(define (add x y) (+ x y))

;; Log every call's arguments:
(define logged-add
  (chaperone-procedure add
    (lambda args
      (display "called with: ") (display args) (newline)
      args)    ; args-interceptor must return the argument list
    #f))       ; no result interception

(logged-add 3 4)
;; prints: called with: (3 4)
;=> 7
```

**Procedure chaperone (argument and result interception):**

```scheme
;; Ensure arguments are positive, double the result:
(define guarded-add
  (chaperone-procedure add
    (lambda args
      (for-each (lambda (a)
                  (unless (positive? a)
                    (error 'guarded-add "expected positive" a)))
                args)
      args)
    (lambda results
      (map (lambda (r) (* r 2)) results))))

(guarded-add 3 4)  ;=> 14
```

**Impersonator (freely transform):**

```scheme
;; An impersonator that adds 1 to every argument:
(define inc-add
  (impersonate-procedure add
    (lambda args (map (lambda (a) (+ a 1)) args))
    #f))

(inc-add 3 4)  ;=> 9  (computes (+ 4 5))
```

**Vector chaperone (access control):**

```scheme
(define v (vector 10 20 30))
(define cv
  (chaperone-vector v
    ;; ref-interceptor: receives (vec idx val), returns transformed val
    (lambda (vec idx val)
      (display (format "reading index ~a\n" idx))
      val)
    ;; set-interceptor: receives (vec idx val), returns value to store
    (lambda (vec idx val)
      (unless (number? val)
        (error 'cv "only numbers allowed"))
      val)))

(chaperone-vector-ref cv 0)   ;=> 10 (prints "reading index 0")
(chaperone-vector-set! cv 1 99)
```

**Hashtable chaperone:**

```scheme
(define ht (make-hashtable string-hash string=?))
(hashtable-set! ht "name" "Alice")

(define cht
  (chaperone-hashtable ht
    ;; ref-interceptor: (ht key val) -> val
    (lambda (ht key val) (string-upcase val))
    ;; set-interceptor: (ht key val) -> val
    (lambda (ht key val) (string-downcase val))
    ;; delete-interceptor: (ht key) -> key
    #f))

(chaperone-hashtable-ref cht "name" #f)    ;=> "ALICE"
(chaperone-hashtable-set! cht "city" "NYC")
(hashtable-ref ht "city" #f)               ;=> "nyc"
```

**Predicates and unwrapping:**

```scheme
(chaperone? logged-add)          ;=> #t
(chaperone? add)                 ;=> #f
(chaperone-of? logged-add add)   ;=> #t
(chaperone-unwrap logged-add)    ;=> the original add procedure
```

---

## 5. Advice System -- `(std misc advice)`

**Source:** `lib/std/misc/advice.sls`

```scheme
(import (std misc advice))
```

### Overview

An Emacs-style advice system for wrapping procedures with entry/exit hooks
without modifying the original definition. Supports three kinds of advice:

- **Before** advice: runs before the call, receives the same arguments.
- **After** advice: runs after the call, receives the result.
- **Around** advice: wraps the entire call, receives `(next . args)` and must call `next`.

Multiple advice of each kind can be stacked. Around advice composes as
middleware: the last-added around wrapper is outermost.

### API Reference

| Identifier | Kind | Description |
|---|---|---|
| `make-advisable` | procedure | `(make-advisable proc)` -- wrap a procedure so it can receive advice; returns a new callable |
| `advise-before` | procedure | `(advise-before advisable hook)` -- add a before-hook; `hook` receives the same args as the function |
| `advise-after` | procedure | `(advise-after advisable hook)` -- add an after-hook; `hook` receives the result value |
| `advise-around` | procedure | `(advise-around advisable hook)` -- add an around wrapper; `hook` is `(lambda (next . args) ...)` |
| `unadvise` | procedure | `(unadvise advisable)` -- remove all advice, restore original behavior |
| `advised?` | procedure | `(advised? advisable)` -- returns `#t` if any advice is currently installed |
| `define-advisable` | macro | `(define-advisable (name args ...) body ...)` -- define an advisable function directly |

### Usage Examples

**Basic before/after advice:**

```scheme
(define my-add (make-advisable +))

(advise-before my-add
  (lambda args
    (display "calling add with: ")
    (display args)
    (newline)))

(advise-after my-add
  (lambda (result)
    (display "result: ")
    (display result)
    (newline)))

(my-add 3 4)
;; prints: calling add with: (3 4)
;; prints: result: 7
;=> 7
```

**Around advice (timing, memoization, retry):**

```scheme
(define my-mul (make-advisable *))

;; Timing wrapper:
(advise-around my-mul
  (lambda (next . args)
    (let ([start (current-time)])
      (let ([result (apply next args)])
        (display (format "took ~a ns\n"
                   (- (time-nanosecond (current-time))
                      (time-nanosecond start))))
        result))))

(my-mul 6 7)  ;=> 42
```

**Using `define-advisable`:**

```scheme
(define-advisable (greet name)
  (string-append "Hello, " name "!"))

(greet "Alice")  ;=> "Hello, Alice!"

(advise-before greet
  (lambda (name)
    (display (format "greeting ~a\n" name))))

(greet "Bob")
;; prints: greeting Bob
;=> "Hello, Bob!"
```

**Removing advice:**

```scheme
(advised? my-add)  ;=> #t
(unadvise my-add)
(advised? my-add)  ;=> #f
(my-add 3 4)       ;=> 7  (no more logging)
```

**Stacking multiple around advice:**

```scheme
(define my-fn (make-advisable (lambda (x) (* x 2))))

;; First around: adds 1 to input
(advise-around my-fn
  (lambda (next x) (next (+ x 1))))

;; Second around (outermost): multiplies result by 10
(advise-around my-fn
  (lambda (next x)
    (* 10 (next x))))

(my-fn 3)
;; Execution: outer receives 3, calls next(3)
;;   inner receives 3, calls next(3+1=4)
;;     original: (* 4 2) = 8
;;   inner returns 8
;; outer returns (* 10 8) = 80
;=> 80
```

---

## 6. Binary Type Framework -- `(std misc binary-type)`

**Source:** `lib/std/misc/binary-type.sls`

```scheme
(import (std misc binary-type))
```

### Overview

A syntax-driven framework for defining binary data types with automatic
reader/writer generation. Supports primitive types, composite records, and
fixed-length arrays. All types are registered in a global registry and can be
nested. Values are read from and written to binary ports.

### Built-in Primitive Types

| Type Name | Size | Description |
|---|---|---|
| `uint8` | 1 byte | Unsigned 8-bit integer |
| `uint16-be` | 2 bytes | Unsigned 16-bit, big-endian |
| `uint16-le` | 2 bytes | Unsigned 16-bit, little-endian |
| `uint32-be` | 4 bytes | Unsigned 32-bit, big-endian |
| `uint32-le` | 4 bytes | Unsigned 32-bit, little-endian |
| `int8` | 1 byte | Signed 8-bit integer |
| `int16-be` | 2 bytes | Signed 16-bit, big-endian |
| `int16-le` | 2 bytes | Signed 16-bit, little-endian |
| `int32-be` | 4 bytes | Signed 32-bit, big-endian |
| `int32-le` | 4 bytes | Signed 32-bit, little-endian |
| `float32-be` | 4 bytes | IEEE 754 single, big-endian |
| `float64-be` | 8 bytes | IEEE 754 double, big-endian |

### API Reference

| Identifier | Kind | Description |
|---|---|---|
| `define-binary-type` | macro | Define a new primitive binary type with reader and writer lambdas |
| `define-binary-record` | macro | Define a composite record type from named fields with binary types |
| `define-binary-array` | macro | Define a fixed-length array type over an element type |
| `binary-read` | procedure | `(binary-read type-name port)` -- read a value of the named type from a binary port |
| `binary-write` | procedure | `(binary-write type-name port val)` -- write a value of the named type to a binary port |
| `register-binary-type!` | procedure | `(register-binary-type! name reader writer)` -- low-level type registration |

### Usage Examples

**Reading and writing primitive types:**

```scheme
(import (std misc binary-type))

;; Write to a bytevector port, then read back:
(let ([bv (make-bytevector 4)])
  (let ([out (open-bytevector-output-port)])
    (binary-write 'uint16-be out 1000)
    (binary-write 'uint16-be out 2000)
    (let-values ([(result _) (get-output-bytevector+port out)])
      (let ([in (open-bytevector-input-port result)])
        (values (binary-read 'uint16-be in)    ;=> 1000
                (binary-read 'uint16-be in)))))) ;=> 2000
```

**Defining a custom primitive type:**

```scheme
(define-binary-type uint8
  (reader (lambda (port) (get-u8 port)))
  (writer (lambda (port val) (put-u8 port val))))
```

**Defining a binary record:**

```scheme
(define-binary-record point
  (x uint16-be)
  (y uint16-be))

;; This generates:
;;   make-point   -- constructor: (make-point x y)
;;   point-x      -- accessor
;;   point-y      -- accessor
;;   read-point   -- (read-point port) -> point
;;   write-point  -- (write-point port point)
;;   Registers 'point in the binary type registry.

(define p (make-point 100 200))
(point-x p)  ;=> 100
(point-y p)  ;=> 200

;; Round-trip through a port:
(let-values ([(port get-bv) (open-bytevector-output-port)])
  (write-point port p)
  (let ([in (open-bytevector-input-port (get-bv))])
    (let ([p2 (read-point in)])
      (values (point-x p2) (point-y p2)))))
;=> 100, 200
```

**Defining a binary array:**

```scheme
(define-binary-array triple-byte uint8 3)

;; This generates:
;;   read-triple-byte   -- (read-triple-byte port) -> vector
;;   write-triple-byte  -- (write-triple-byte port vec)
;;   Registers 'triple-byte in the binary type registry.

(let-values ([(port get-bv) (open-bytevector-output-port)])
  (write-triple-byte port (vector 10 20 30))
  (let ([in (open-bytevector-input-port (get-bv))])
    (read-triple-byte in)))
;=> #(10 20 30)
```

**Nesting records and arrays:**

```scheme
;; A color type:
(define-binary-record color
  (r uint8)
  (g uint8)
  (b uint8))

;; A rectangle using nested point and color:
(define-binary-record rect
  (top-left point)
  (bottom-right point)
  (fill color))

(define r (make-rect (make-point 0 0)
                     (make-point 640 480)
                     (make-color 255 0 128)))

(let-values ([(port get-bv) (open-bytevector-output-port)])
  (write-rect port r)
  (let ([in (open-bytevector-input-port (get-bv))])
    (let ([r2 (read-rect in)])
      (point-x (rect-top-left r2)))))
;=> 0
```

**Using `binary-read`/`binary-write` for generic dispatch:**

```scheme
;; Works with any registered type name:
(let-values ([(port get-bv) (open-bytevector-output-port)])
  (binary-write 'point port (make-point 42 99))
  (let ([in (open-bytevector-input-port (get-bv))])
    (let ([p (binary-read 'point in)])
      (point-y p))))
;=> 99
```

**Defining a simple network packet:**

```scheme
(define-binary-record packet-header
  (version uint8)
  (type    uint8)
  (length  uint16-be))

(define-binary-array payload uint8 256)

(define-binary-record packet
  (header packet-header)
  (data   payload))
```
