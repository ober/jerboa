# Jerboa for Clojure Developers

Jerboa is a Chez Scheme dialect that provides a Clojure-compatible surface for developers who want fast startup, native compilation, and no JVM dependency. A single `(import (jerboa clojure))` gives you persistent data structures, atoms, lazy sequences, destructuring, `loop`/`recur`, `core.async`-style channels, and most of the Clojure core API — mapped onto Scheme's proper tail calls and hygienic macro system.

## Installation

```bash
git clone https://github.com/jafourni/jerboa.git
cd jerboa
make build
```

You need [Chez Scheme](https://cisco.github.io/ChezScheme/) installed (`scheme` on your PATH).

## Hello World

Create `hello.ss`:

```scheme
(import (jerboa clojure))

(println "Hello, world!")
```

Run it:

```bash
scheme --libdirs lib --script hello.ss
```

## REPL

```bash
scheme --libdirs lib
```

Then at the `>` prompt:

```scheme
> (import (jerboa clojure))
> (def m (hash-map "name" "Alice" "age" 30))
> (get m "name")
"Alice"
> (-> m (assoc "role" "dev") (dissoc "age") keys)
("name" "role")
```

## The Import Story

There is no `ns` form. A single import gives you everything:

```scheme
(import (jerboa clojure))
```

This brings in the full Jerboa prelude plus all Clojure-compatibility modules: persistent maps, sets, vectors, atoms, lazy sequences, destructuring, dynamic vars, `loop`/`recur`, `ex-info`, transients, `core.logic`, `clojure.spec`, Transit, and `clojure.string` (prefixed as `str/`).

For additional modules, use the `require` macro (Clojure-style):

```scheme
(require '(std csp clj) :as async)      ;; core.async  -> async:chan, async:go, ...
(require '(std multi) :refer (defmulti defmethod))
(require '(std protocol) :refer (defprotocol extend-type))
(require '(std db sqlite) :as db)
```

## Side-by-Side: 20 Common Patterns

### 1. Defining Functions

```clojure
;; Clojure
(defn greet [name]
  (str "Hello, " name "!"))
```

```scheme
;; Jerboa
(def (greet name)
  (str "Hello, " name "!"))
```

`def` with a list head defines a function. Optional args use `(def (f x (y 10)) ...)`. Multi-arity uses `def*`.

### 2. Let Bindings

```clojure
;; Clojure
(let [x 1
      y (+ x 1)]
  (+ x y))
```

```scheme
;; Jerboa
(let ([x 1]
      [y (+ x 1)])
  (+ x y))
```

Brackets and parens are interchangeable. Each binding is a pair `[name expr]`.

### 3. if / when / cond

```clojure
;; Clojure
(cond
  (> x 0) "positive"
  (< x 0) "negative"
  :else    "zero")
```

```scheme
;; Jerboa
(cond
  [(> x 0) "positive"]
  [(< x 0) "negative"]
  [else    "zero"])
```

`if`, `when`, and `unless` work the same as Clojure. In `cond`, use `else` instead of `:else`.

### 4. Threading Macros

```clojure
;; Clojure
(-> m (assoc :role "dev") (dissoc :age))
(->> (range 10) (filter even?) (map inc))
```

```scheme
;; Jerboa
(-> m (assoc role: "dev") (dissoc age:))
(->> (range 10) (filter even?) (map inc))
```

All threading macros are present: `->`, `->>`, `as->`, `some->`, `some->>`, `cond->`, `cond->>`.

### 5. Maps

```clojure
;; Clojure
(def m {:name "Alice" :age 30})
(get m :name)           ;=> "Alice"
(assoc m :role "dev")   ;=> {:name "Alice" :age 30 :role "dev"}
(dissoc m :age)         ;=> {:name "Alice"}
(merge m {:city "NYC"})
(update m :age inc)
(get-in nested [:a :b])
(contains? m :name)     ;=> true
(keys m)  (vals m)  (count m)
(select-keys m [:name])
```

```scheme
;; Jerboa
(def m (hash-map name: "Alice" age: 30))
(get m name:)             ;=> "Alice"
(assoc m role: "dev")     ;=> new map with role
(dissoc m age:)           ;=> new map without age
(merge m (hash-map city: "NYC"))
(update m age: inc)
(get-in m (list name: age:))
(contains? m name:)       ;=> #t
(keys m)  (vals m)  (count m)
(select-keys m (list name:))
```

`hash-map` returns a persistent (immutable) map backed by a HAMT. All ops are polymorphic across persistent maps, concurrent hash maps, and mutable hash tables.

### 6. Vectors

```clojure
;; Clojure
(def v [1 2 3])
(conj v 4)       ;=> [1 2 3 4]
(nth v 0)        ;=> 1
(count v)        ;=> 3
(first v)        ;=> 1
(rest v)         ;=> (2 3)
```

```scheme
;; Jerboa
(def v (vec '(1 2 3)))     ;; or (vec 1 2 3)
(conj v 4)                 ;=> persistent vector [1 2 3 4]
(get v 0)                  ;=> 1
(count v)                  ;=> 3
(first v)                  ;=> 1
(rest v)                   ;=> (2 3)
```

`vec` builds a persistent vector. `[1 2 3]` in Jerboa is just `(1 2 3)` — a list, not a vector.

### 7. Sets

```clojure
;; Clojure
(def s #{1 2 3})
(conj s 4)              ;=> #{1 2 3 4}
(disj s 2)              ;=> #{1 3}
(contains? s 2)         ;=> true
(clojure.set/union s #{4 5})
(clojure.set/intersection s #{2 3 4})
```

```scheme
;; Jerboa
(def s (hash-set 1 2 3))
(conj s 4)              ;=> persistent set with 1 2 3 4
(disj s 2)              ;=> persistent set with 1 3
(contains? s 2)         ;=> #t
(union s (hash-set 4 5))
(intersection s (hash-set 2 3 4))
```

`union`, `intersection`, `difference`, `subset?`, and `superset?` are all available. The full `clojure.set` relational algebra (`set-select`, `set-project`, `set-rename`, `set-index`, `set-join`, `map-invert`) is included.

### 8. Atoms

```clojure
;; Clojure
(def counter (atom 0))
(swap! counter inc)
(reset! counter 42)
@counter                ;=> 42
(add-watch counter :log (fn [k r old new] (println old "->" new)))
```

```scheme
;; Jerboa
(def counter (atom 0))
(swap! counter inc)
(reset! counter 42)
(deref counter)          ;=> 42
(add-watch! counter log: (lambda (k r old new) (println old "->" new)))
```

`compare-and-set!` is also available. No `@` reader macro — use `deref`.

### 9. loop / recur

```clojure
;; Clojure
(loop [i 0 acc []]
  (if (= i 5)
    acc
    (recur (inc i) (conj acc i))))
```

```scheme
;; Jerboa
(loop ([i 0] [acc '()])
  (if (= i 5)
    (reverse acc)
    (recur (+ i 1) (cons i acc))))
```

`loop`/`recur` exist for familiarity. But Chez has proper tail calls, so a plain named `let` loop is idiomatic and equally efficient:

```scheme
(let lp ([i 0] [acc '()])
  (if (= i 5) (reverse acc) (lp (+ i 1) (cons i acc))))
```

### 10. Destructuring

```clojure
;; Clojure
(let [{:keys [name age]} person]
  (println name age))
```

```scheme
;; Jerboa
(dlet ([(keys: name age) person])
  (println name age))
```

`dlet` supports list destructuring, `&` rest, map `keys:` lookup, `as:` binding, and `or:` defaults:

```scheme
(dlet ([(a b & rest) '(1 2 3 4 5)]
       [(keys: x y or: ([y 99])) some-map])
  (println a b rest x y))
```

`dfn` defines a function with destructured parameters.

### 11. Pattern Matching

```clojure
;; Clojure (core.match)
(match [x]
  [1] "one"
  [(:or 2 3)] "two or three"
  :else "other")
```

```scheme
;; Jerboa (built-in)
(match x
  (1 "one")
  ((or 2 3) "two or three")
  (_ "other"))
```

`match` is in the prelude. Supports literals, list/cons destructuring, predicates `(? number?)`, guards `(n (where (> n 0)))`, view patterns `(=> string->number n)`, and `and`/`or` combinators.

### 12. Lazy Sequences

```clojure
;; Clojure
(take 5 (iterate inc 0))      ;=> (0 1 2 3 4)
(take 3 (cycle [1 2 3]))      ;=> (1 2 3)
(take 3 (repeat 42))          ;=> (42 42 42)
(->> (range) (filter even?) (take 5))
```

```scheme
;; Jerboa
(lazy->list (lazy-take 5 (iterate inc 0)))   ;=> (0 1 2 3 4)
(lazy->list (lazy-take 3 (cycle '(1 2 3))))  ;=> (1 2 3)
(lazy->list (lazy-take 3 (repeat 42)))        ;=> (42 42 42)
(doall (lazy-take 5 (lazy-filter even? (lazy-range 0 +inf.0 1))))
```

`iterate` and `repeat` return infinite lazy sequences. `cycle`, `lazy-map`, `lazy-filter`, `lazy-take`, `lazy-drop`, `lazy-concat`, `lazy-interleave`, `lazy-mapcat`, `lazy-partition` — the full suite is available. Use `doall` to force a lazy seq into a list, or `lazy->list`.

### 13. Transducers

Transducers are available via `(std transducer)`:

```scheme
(require '(std transducer) :refer (sequence transduce map-xf filter-xf take-xf compose-xf))

(sequence (compose-xf (filter-xf even?) (map-xf inc) (take-xf 3))
          (range 10))
;=> (1 3 5)
```

Channels accept transducers directly — see core.async below.

### 14. core.async

```clojure
;; Clojure
(require '[clojure.core.async :as async :refer [go chan <! >! alts! timeout]])
(let [c (chan 10)]
  (go (>! c 42))
  (go (println (<! c))))
```

```scheme
;; Jerboa
(require '(std csp clj) :as async)

(let ([c (async:chan 10)])
  (async:go (async:>! c 42))
  (async:go (println (async:<! c))))
```

Or import names directly:

```scheme
(require '(std csp clj) :refer (go chan <! >! alt! timeout close!))

(let ([c (chan 10)])
  (go (>! c 42))
  (go (println (<! c))))
```

Full `core.async` surface: `go`, `go-loop`, `chan`, `<!`, `>!`, `<!!`, `>!!`, `close!`, `alt!`, `alts!`, `timeout`, `pipe`, `mult`, `tap`, `pub`, `sub`, `merge`, `split`, `pipeline`, `sliding-buffer`, `dropping-buffer`, `promise-chan`, `to-chan`, `onto-chan`. When running inside a fiber runtime, `go` spawns lightweight fibers (~4KB) instead of OS threads.

### 15. Dynamic Vars

```clojure
;; Clojure
(def ^:dynamic *indent* 0)
(binding [*indent* 2]
  (println *indent*))
```

```scheme
;; Jerboa
(def-dynamic *indent* 0)
(binding ([*indent* 2])
  (println (*indent*)))
```

`def-dynamic` creates a Chez parameter. Access the value by calling it: `(*indent*)`. Dynamic bindings propagate to `clj-future` and `bound-fn` automatically.

### 16. Protocols

```clojure
;; Clojure
(defprotocol Shape
  (area [this])
  (perimeter [this]))

(defrecord Circle [r])
(extend-type Circle Shape
  (area [c] (* Math/PI (.r c) (.r c)))
  (perimeter [c] (* 2 Math/PI (.r c))))
```

```scheme
;; Jerboa
(require '(std protocol) :refer (defprotocol extend-type))

(defprotocol Shape
  (area     (self))
  (perimeter (self)))

(defstruct circle (r))
(extend-type circle::t Shape
  (area     (c) (* 3.14159 (circle-r c) (circle-r c)))
  (perimeter (c) (* 2 3.14159 (circle-r c))))

(area (make-circle 3))  ;=> 28.27...
```

Protocols dispatch on Chez record types (use `name::t`) or symbols for builtins (`'string`, `'pair`, `'number`, etc.).

### 17. Multimethods

```clojure
;; Clojure
(defmulti area :shape)
(defmethod area :circle [{:keys [r]}] (* Math/PI r r))
(defmethod area :default [s] (throw (ex-info "Unknown" {:shape s})))
```

```scheme
;; Jerboa
(require '(std multi) :refer (defmulti defmethod))

(defmulti area (lambda (shape) (get shape shape:)))
(defmethod area 'circle (s) (* 3.14159 (get s r:) (get s r:)))
(defmethod area 'default (s) (raise (ex-info "Unknown" (hash-map shape: s))))
```

Dispatch values are compared with `equal?` — any value works: symbols, strings, numbers, lists.

### 18. Error Handling

```clojure
;; Clojure
(try
  (throw (ex-info "bad input" {:code 400}))
  (catch Exception e
    (println (ex-message e))
    (println (ex-data e))))
```

```scheme
;; Jerboa
(try
  (raise (ex-info "bad input" (hash-map code: 400)))
  (catch (e)
    (println (ex-message e))
    (println (ex-data e))))
```

`ex-info`, `ex-data`, `ex-message`, and `ex-cause` work as expected. The `try`/`catch`/`finally` form catches any raised condition.

### 19. Futures / Promises / Delays

```clojure
;; Clojure
(def d (delay (expensive-computation)))
(def f (future (long-running-task)))
(def p (promise))
(deliver p 42)
@d  @f  @p
```

```scheme
;; Jerboa
(def d (clj-delay (expensive-computation)))
(def f (clj-future (long-running-task)))
(def p (clj-promise))
(deliver p 42)
(deref d)  (deref f)  (deref p)
```

`deref` is polymorphic: works on atoms, delays, futures, promises, and volatiles. `realized?` checks if a lazy seq, delay, future, or promise has been computed.

### 20. Testing

```clojure
;; Clojure
(deftest math-test
  (is (= 4 (+ 2 2)))
  (is (thrown? Exception (/ 1 0))))
```

```scheme
;; Jerboa
(import (std test))

(def math-tests
  (test-suite "math"
    (test-case "addition"
      (check (+ 2 2) => 4))
    (test-case "division by zero"
      (check-exception (/ 1 0)))))

(run-tests! math-tests)
```

Uses `check` with `=>` for equality, `check-predicate` for predicates, and `check-exception` for expected errors.

## What's Different and Why

### Brackets are just parens
`[1 2 3]` is the same as `(1 2 3)` — a list, not a vector. Use `(vec '(1 2 3))` or `(vec 1 2 3)` for persistent vectors.

### Keywords end with a colon
Jerboa: `name:`, `age:`. Clojure: `:name`, `:age`. The trailing colon is consistent with Gerbil Scheme.

### No Java interop
There is no `.method` syntax and no `import` for Java classes. Jerboa compiles to native code via Chez Scheme. For system interop, use FFI to C or Rust.

### `#t` / `#f` instead of `true` / `false`
Scheme booleans. `true?` and `false?` predicates exist. Everything except `#f` is truthy (including `0`, `""`, and `'()`).

### `nil` is `#f`
Clojure's `nil` maps to `#f`. `nil?` checks for `#f`. `seq` returns `#f` for empty collections, not `nil`.

### Proper tail calls replace `recur`
Every function in Jerboa has proper tail calls. You don't need `recur` to avoid stack overflow — any self-call in tail position is optimized. `loop`/`recur` exist for readability and familiarity.

### No literal syntax for data structures
No `{}`, `#{}`, or `[]` literals. Use `hash-map`, `hash-set`, `vec`, `list`.

### `assoc` means different things
Chez Scheme's built-in `assoc` does alist lookup. The `(jerboa clojure)` import shadows it with Clojure's `assoc` (map update). If you need alist lookup, use `aget` or `agetv`.

## What to Reach For Instead of Java Interop

| Java / Clojure Library | Jerboa Module | Import |
|---|---|---|
| HTTP client | `(std net request)` | `(require '(std net request) :as http)` |
| HTTP server | `(std net httpd)` | `(require '(std net httpd) :as httpd)` |
| JSON | Built-in | `read-json`, `write-json`, `string->json-object` |
| SQLite | `(std db sqlite)` | `(require '(std db sqlite) :as db)` |
| PostgreSQL | `(std db postgres)` | `(require '(std db postgres) :as pg)` |
| Crypto / hashing | `(std crypto digest)` | `(require '(std crypto digest) :as crypto)` |
| Regex | Built-in | `re`, `re-match?`, `re-find-all`, `re-replace` |
| File I/O (slurp/spit) | `(std clojure io)` | `(require '(std clojure io) :refer (slurp spit))` |
| clojure.string | Built-in (prefixed) | `str/trim`, `str/split`, `str/join`, etc. |
| Logging | `(std logger)` | `(require '(std logger) :as log)` |
| core.async | `(std csp clj)` | `(require '(std csp clj) :refer (go chan <! >!))` |
| core.logic | Built-in | `run*`, `fresh`, `conde`, `==` |
| clojure.spec | Built-in | `s-def`, `s-valid?`, `s-conform`, `s-explain` |
| Transit | Built-in | `transit-write`, `transit-read` |
| Datafy/Nav | Built-in | `datafy`, `nav` |
| test.check (property) | `(std proptest)` | `(require '(std proptest) :as pt)` |

## Project Structure

```
my-project/
  lib/              ;; your modules go here
    my/
      app.sls       ;; (library (my app) ...)
      util.sls
  main.ss           ;; entry point: (import (jerboa clojure)) ...
  tests/
    test-app.ss     ;; (import (std test)) ...
  Makefile
```

A minimal `Makefile`:

```makefile
SCHEME = scheme
LIBDIRS = lib:path/to/jerboa/lib

run:
	$(SCHEME) --libdirs $(LIBDIRS) --script main.ss

test:
	$(SCHEME) --libdirs $(LIBDIRS) --script tests/test-app.ss
```

## Known Gotchas

**Forgetting the import.** There is no `ns` form. Every `.ss` file needs `(import (jerboa clojure))` at the top. Without it, nothing works.

**Using `:keyword` instead of `keyword:`.** Jerboa keywords trail: `name:` not `:name`. The reader converts `name:` to a keyword object.

**Expecting `[1 2 3]` to be a vector.** Brackets are just parentheses. `[1 2 3]` evaluates `1` as a procedure applied to `2` and `3`. Use `(vec '(1 2 3))`.

**`nil` is `#f`.** There is no separate nil value. Empty list `'()` is *not* nil/falsy. `(if '() "truthy" "falsy")` returns `"truthy"`. Test emptiness with `(empty? coll)` or `(seq coll)`.

**`assoc` shadows Chez's `assoc`.** If you import `(jerboa clojure)`, `assoc` means "update a map key" (Clojure semantics), not "lookup in an alist" (Chez semantics). For alist lookup, use `aget`.

**`deref` instead of `@`.** There is no `@` reader macro. Use `(deref atom-or-future)` or call `(*my-dynamic-var*)` for dynamic vars.

**`clj-delay` / `clj-future` / `clj-promise` instead of `delay` / `future` / `promise`.** The `clj-` prefix avoids conflict with Chez Scheme builtins. The `deref` and `realized?` functions are not prefixed.

**Keywords as function arguments.** The `require` macro uses `:as` and `:refer` with a leading colon (matching Clojure syntax). But in data, keywords trail: `name:`, not `:name`. This is the one place where Jerboa deliberately uses Clojure-style leading-colon keywords.

**No implicit `str` on `println` args.** `(println 1 "hello" 'sym)` works — it calls `display` on each arg. But if you need string interpolation, use `(str "count: " n)` explicitly.
