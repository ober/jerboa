# What's New in Jerboa — Latest Additions

This document covers the 33 new standard library modules added in the latest development push. Every module is a full R6RS library with comprehensive tests — **1,021 tests total**, all passing.

---

## Concurrency & Scheduling

### `(std misc fiber)` — Green Threads with M:N Scheduling
*19 tests*

Lightweight fibers multiplexed onto OS threads with fiber-aware channels and cooperative yielding.

```scheme
(import (std misc fiber))

(fiber-run
  (lambda ()
    (define ch (make-fiber-channel))
    (fiber-spawn (lambda () (fiber-channel-put ch 42)))
    (fiber-channel-get ch)))  ;; => 42
```

### `(std misc event)` — Unified Event System
*44 tests*

First-class synchronizable events with multiplexed selectors, channels, and timer events.

```scheme
(import (std misc event))

(sync (choice (timer-evt 1.0)
              (channel-recv-evt ch)))

(let-values ([(idx val) (select evt1 evt2 evt3)])
  (printf "event ~a: ~a~n" idx val))
```

### `(std misc custodian)` — Hierarchical Resource Groups
*16 tests*

Racket-style custodians for grouping resources with recursive shutdown.

```scheme
(import (std misc custodian))

(define cust (make-custodian))
(custodian-register! cust port custodian-close-port)
(custodian-shutdown! cust)  ;; closes all registered resources
```

### `(std misc delimited)` — Delimited Continuations
*8 tests*

`reset`/`shift` via Filinski encoding over `call/cc`. Also provides `call-with-prompt`/`abort-to-prompt`.

```scheme
(import (std misc delimited))

(reset (+ 1 (shift k (k 10))))  ;; => 11

(reset (list 1 (shift k (k 2) (k 3))))  ;; => (1 3)
```

### `(std misc pool)` — Resource Pool (Enhanced)
*17 tests*

Thread-safe object pool with timeout, idle eviction, health checks, and statistics.

```scheme
(import (std misc pool))

(define pool (make-pool create-conn destroy-conn 10))
(with-pooled-resource pool
  (lambda (conn)
    (query conn "SELECT 1")))
```

---

## Data Structures

### `(std misc persistent)` — HAMT Persistent Hash Maps
*98 tests*

Hash Array Mapped Trie with 32-way branching, bitmap-indexed nodes, and structural sharing.

```scheme
(import (std misc persistent))

(define m (hamt-empty))
(define m2 (hamt-set m 'x 42))
(hamt-ref m2 'x)         ;; => 42
(hamt-ref m 'x 'missing) ;; => missing (original unchanged)
```

### `(std misc lazy-seq)` — Lazy Sequences
*44 tests*

Clojure-style lazy sequences with memoized thunks, infinite generators, and standard combinators.

```scheme
(import (std misc lazy-seq))

(define nats (lazy-iterate add1 0))
(lazy-seq->list (lazy-take 5 nats))     ;; => (0 1 2 3 4)
(lazy-seq->list (lazy-filter odd? (lazy-take 10 nats)))  ;; => (1 3 5 7 9)
```

### `(std misc weak)` — Weak Collections
*33 tests*

Weak pairs, weak lists, and weak hash tables built on Chez's `weak-cons` and guardians.

```scheme
(import (std misc weak))

(define wht (make-weak-hashtable equal-hash equal?))
(weak-hashtable-set! wht key value)
;; entry disappears when key is GC'd
```

### `(std misc collection)` — Generic Collection Protocol
*42 tests*

Uniform iteration over lists, vectors, strings, bytevectors, and hashtables.

```scheme
(import (std misc collection))

(collection-map add1 #(1 2 3))        ;; => #(2 3 4)
(collection-fold + 0 '(1 2 3))        ;; => 6
(collection-filter char-alphabetic? "h3llo")  ;; => "hllo"
```

### `(std misc relation)` — Relational Data Protocol
*58 tests*

Select/project/extend/sort/group-by/join/aggregate over lists of association-list records.

```scheme
(import (std misc relation))

(define employees
  '(((name . "Alice") (dept . "eng") (salary . 90000))
    ((name . "Bob")   (dept . "eng") (salary . 85000))
    ((name . "Carol") (dept . "hr")  (salary . 70000))))

(relation-select (lambda (r) (> (cdr (assq 'salary r)) 80000)) employees)
(relation-project '(name dept) employees)
(relation-aggregate 'dept 'salary + employees)
```

---

## Serialization & Protocols

### `(std text msgpack)` — MessagePack (Enhanced)
*64 tests*

Full MessagePack spec coverage: fixints, str/bin/ext families, float32/64, map/array.

```scheme
(import (std text msgpack))

(define packed (msgpack-encode '(1 "hello" #t)))
(msgpack-decode packed)  ;; => (1 "hello" #t)
```

### `(std net 9p)` — 9P2000 Filesystem Protocol
*91 tests*

Complete 9P2000 message encode/decode for all 27 message types.

```scheme
(import (std net 9p))

(define msg (make-9p-tversion 8192 "9P2000"))
(define bv (9p-encode msg))
(9p-decode bv)  ;; => round-trips perfectly
```

### `(std misc binary-type)` — Binary Protocol Framework
*27 tests*

`define-binary-type` and `define-binary-record` macros for declarative binary format parsing.

```scheme
(import (std misc binary-type))

(define-binary-type u16-le
  (reader (lambda (port) ...))
  (writer (lambda (port val) ...)))

(define-binary-record point
  (x u16-le) (y u16-le))
```

---

## Testing & Debugging

### `(std test)` — Assert! Macro
*15 tests*

`assert!` with sub-expression introspection — on failure, shows the values of each sub-expression.

```scheme
(import (std test))

(assert! (= (+ 1 2) 4))
;; Assertion failed: (= (+ 1 2) 4)
;;   (+ 1 2) => 3
;;   4 => 4
```

### `(std test quickcheck)` — Property-Based Testing
*12 tests*

Generators, combinators, automatic shrinking, and `for-all` macro.

```scheme
(import (std test quickcheck))

(check-property
  (for-all ([xs (gen-list (gen-integer -100 100))])
    (= (length (reverse xs)) (length xs))))
```

### `(std misc profile)` — Profiling Framework
*11 tests*

`define-profiled` wraps functions with call counting and timing. Report per-function stats.

```scheme
(import (std misc profile))

(define-profiled my-fib
  (lambda (n) (if (< n 2) n (+ (my-fib (- n 1)) (my-fib (- n 2))))))

(my-fib 20)
(profile-report)
;; my-fib: 21891 calls, 45ms total, 0.002ms avg
```

### `(std misc equiv)` — Cycle-Aware Equality
*28 tests*

`equiv?` handles cyclic data structures without infinite loops.

```scheme
(import (std misc equiv))

(define a (list 1 2))
(set-cdr! (cdr a) a)  ;; circular list
(equiv? a a)  ;; => #t (doesn't loop forever)
```

### `(std misc diff)` — LCS-Based Diff
*34 tests*

Computes edit scripts (insert/delete/equal) between sequences.

```scheme
(import (std misc diff))

(diff '(a b c d) '(a c d e))
;; => ((equal a) (delete b) (equal c) (equal d) (insert e))
```

---

## Metaprogramming

### `(std misc typeclass)` — Haskell-Style Typeclasses
*34 tests*

Dictionary-passing typeclasses with superclass inheritance.

```scheme
(import (std misc typeclass))

(define-typeclass (Hashable a)
  (hash-code a -> integer))

(define-instance (Hashable number)
  (hash-code (lambda (n) (modulo (abs n) 1000000007))))

(tc-apply 'Hashable 'hash-code 'number 42)  ;; => 42
```

### `(std misc ck-macros)` — CK Abstract Machine
*40 tests*

Composable higher-order macros using the CK machine — pure `syntax-rules`, no `syntax-case`.

```scheme
(import (std misc ck-macros))

(ck () (c-reverse '(a b c)))          ;; => (c b a)
(ck () (c-map (c-cons 'x) '(1 2 3))) ;; => ((x . 1) (x . 2) (x . 3))
(ck () (c-filter (c-null?) '(() (a) () (b))))  ;; => (() ())
```

### `(std misc fmt)` — Format String Compilation
*39 tests*

`compile-format` parses format strings at compile time — zero runtime parsing overhead.

```scheme
(import (std misc fmt))

(define fmt-point (compile-format "Point(~a, ~a)"))
(fmt-point 3 4)  ;; => "Point(3, 4)"

(fmt "~a + ~a = ~a" 1 2 3)  ;; => "1 + 2 = 3"
(fmt "hex: ~x, bin: ~b" 255 10)  ;; => "hex: ff, bin: 1010"
```

### `(std misc chaperone)` — Chaperones & Impersonators
*22 tests*

Racket-style composable interceptors for procedures, vectors, and hashtables.

```scheme
(import (std misc chaperone))

(define safe-add
  (chaperone-procedure +
    (lambda args
      (for-each (lambda (a) (assert (number? a))) args)
      args)
    #f))
(safe-add 1 2)  ;; => 3
```

### `(std misc advice)` — Advice System
*21 tests*

Before/after/around hooks with middleware-style composition for function wrapping.

```scheme
(import (std misc advice))

(define-advisable my-func (lambda (x) (* x 2)))
(add-advice! 'my-func 'before (lambda (x) (printf "calling with ~a~n" x) x))
(my-func 5)  ;; prints "calling with 5", returns 10
```

---

## System & Infrastructure

### `(std misc config)` — Hierarchical Configuration
*25 tests*

S-expression config files with parent cascading and dot-path access.

```scheme
(import (std misc config))

(define cfg (config-read "app.conf"))
(config-ref cfg 'database.host "localhost")
(config-ref cfg 'database.port 5432)
```

### `(std misc cont-marks)` — Continuation Marks
*26 tests*

Thin alias layer over Chez 10.4's native continuation marks for stack-aware context propagation.

```scheme
(import (std misc cont-marks))

(with-continuation-mark 'key 'val
  (current-continuation-marks))
```

### `(std misc terminal)` — Terminal Control
*44 tests*

ANSI escape codes for cursor movement, screen clearing, colors, and text styling.

```scheme
(import (std misc terminal))

(term-bold "important")        ;; => "\e[1mimportant\e[0m"
(term-fg-color 'red "error")   ;; => "\e[31merror\e[0m"
(term-cursor-move 5 10)        ;; move cursor to row 5, col 10
```

### `(std misc highlight)` — Scheme Syntax Highlighting
*38 tests*

Tokenizer + ANSI colorizer for Scheme source code.

```scheme
(import (std misc highlight))

(display (highlight-scheme "(define (f x) (+ x 1))"))
;; outputs colorized Scheme code to terminal
```

### `(std misc guardian-pool)` — Guardian-Based FFI Cleanup
*13 tests*

Standardized pattern for GC-triggered cleanup of FFI resources using Chez guardians.

```scheme
(import (std misc guardian-pool))

(define pool (make-guardian-pool free-foreign-ptr))
(guardian-pool-register! pool ptr)
;; ptr is automatically freed when GC'd
```

### `(std misc amb)` — Non-Deterministic Choice
*9 tests*

McCarthy's `amb` operator with automatic backtracking.

```scheme
(import (std misc amb))

(amb-collect
  (let ([x (amb 1 2 3)]
        [y (amb 4 5 6)])
    (amb-assert (= (+ x y) 7))
    (list x y)))
;; => ((1 6) (2 5) (3 4))
```

### `(std misc memoize)` — Memoization
*6 tests*

Function memoization with LRU eviction and cache management.

```scheme
(import (std misc memoize))

(define fib
  (memoize
    (lambda (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))))

(fib 100)  ;; instant, cached
```

---

## Summary

| Category | Modules | Tests |
|----------|---------|-------|
| Concurrency & Scheduling | 5 | 104 |
| Data Structures | 5 | 275 |
| Serialization & Protocols | 3 | 182 |
| Testing & Debugging | 5 | 100 |
| Metaprogramming | 5 | 156 |
| System & Infrastructure | 8 | 204 |
| **Total** | **33 modules** | **1,021 tests** |

All modules are R6RS libraries importable as `(std misc ...)`, `(std test ...)`, `(std text ...)`, or `(std net ...)`.
