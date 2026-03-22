# Data Structures and Algorithms

Advanced data structures and algorithms in the jerboa standard library.

## Table of Contents

- [Persistent Hash Maps](#persistent-hash-maps) -- `(std misc persistent)`
- [Lazy Sequences](#lazy-sequences) -- `(std misc lazy-seq)`
- [Weak Collections](#weak-collections) -- `(std misc weak)`
- [Generic Collection Protocol](#generic-collection-protocol) -- `(std misc collection)`
- [Relational Data Operations](#relational-data-operations) -- `(std misc relation)`
- [LCS-Based Diff](#lcs-based-diff) -- `(std misc diff)`
- [Cycle-Aware Equality](#cycle-aware-equality) -- `(std misc equiv)`

---

## Persistent Hash Maps

**Module:** `(std misc persistent)`
**File:** `lib/std/misc/persistent.sls`

```scheme
(import (std misc persistent))
```

Immutable hash maps implemented as Hash Array Mapped Tries (HAMT) with 32-way branching and structural sharing. All operations return new HAMTs; the original is never mutated. Keys are compared with `equal?` and hashed with `equal-hash`.

### API Reference

| Procedure | Signature | Description |
|-----------|-----------|-------------|
| `hamt-empty` | value | The empty HAMT. |
| `hamt?` | `(hamt? x)` | Returns `#t` if `x` is a HAMT. |
| `hamt-set` | `(hamt-set h key value)` | Returns a new HAMT with `key` mapped to `value`. |
| `hamt-ref` | `(hamt-ref h key default)` | Returns the value for `key`, or `default` if not found. |
| `hamt-delete` | `(hamt-delete h key)` | Returns a new HAMT without `key`. Returns `h` unchanged if `key` is absent. |
| `hamt-contains?` | `(hamt-contains? h key)` | Returns `#t` if `key` is present in the HAMT. |
| `hamt-size` | `(hamt-size h)` | Returns the number of key-value pairs. |
| `hamt-fold` | `(hamt-fold proc seed h)` | Folds `proc` over all entries. `proc` receives `(key value accumulator)`. |
| `hamt-keys` | `(hamt-keys h)` | Returns a list of all keys. |
| `hamt-values` | `(hamt-values h)` | Returns a list of all values. |
| `hamt-map` | `(hamt-map f h)` | Returns a new HAMT with `f` applied to each value. Keys are unchanged. |
| `hamt->alist` | `(hamt->alist h)` | Returns the HAMT contents as an association list of `(key . value)` pairs. |
| `alist->hamt` | `(alist->hamt alist)` | Creates a HAMT from an association list. |

### Examples

```scheme
(import (std misc persistent))

;; Build up a map incrementally
(define h0 hamt-empty)
(define h1 (hamt-set h0 "name" "Alice"))
(define h2 (hamt-set h1 "age" 30))
(define h3 (hamt-set h2 "city" "Portland"))

;; Lookup
(hamt-ref h3 "name" #f)        ; => "Alice"
(hamt-ref h3 "missing" 'nope)  ; => nope
(hamt-contains? h3 "age")      ; => #t
(hamt-size h3)                  ; => 3

;; The original is unchanged (persistent/immutable)
(hamt-size h1)                  ; => 1

;; Delete a key
(define h4 (hamt-delete h3 "age"))
(hamt-size h4)                  ; => 2
(hamt-contains? h4 "age")      ; => #f

;; Enumerate
(hamt-keys h3)                  ; => ("city" "age" "name")  (order may vary)
(hamt-values h3)                ; => ("Portland" 30 "Alice") (order may vary)
(hamt->alist h3)
; => (("city" . "Portland") ("age" . 30) ("name" . "Alice"))

;; Map over values
(define ages (alist->hamt '(("Alice" . 30) ("Bob" . 25))))
(define next-year (hamt-map add1 ages))
(hamt-ref next-year "Alice" #f) ; => 31

;; Fold to compute a total
(hamt-fold (lambda (k v acc) (+ v acc)) 0 ages) ; => 55

;; Round-trip through alist
(define h5 (alist->hamt '((x . 1) (y . 2) (z . 3))))
(hamt->alist h5) ; => ((z . 3) (y . 2) (x . 1))  (order may vary)
```

---

## Lazy Sequences

**Module:** `(std misc lazy-seq)`
**File:** `lib/std/misc/lazy-seq.sls`

```scheme
(import (std misc lazy-seq))
```

Clojure-style lazy sequences built from memoized thunks. A lazy sequence is a thunk that, when called, produces either `(cons head tail)` where tail is another lazy sequence, or `'()` for the end. Results are cached after the first force.

### API Reference

| Procedure / Macro | Signature | Description |
|-------------------|-----------|-------------|
| `lazy-seq` | `(lazy-seq body ...)` | Macro. Wraps body in a memoized thunk. Body should return `(cons head tail)` or `'()`. |
| `lazy-cons` | `(lazy-cons head tail-expr)` | Macro. Creates a lazy pair. `head` is evaluated eagerly; `tail-expr` is delayed. |
| `lazy-null` | value | The empty lazy sequence. |
| `lazy-null?` | `(lazy-null? lseq)` | Returns `#t` if the lazy sequence is empty. Forces the thunk. |
| `lazy-car` | `(lazy-car lseq)` | Returns the first element. Raises an error if empty. |
| `lazy-cdr` | `(lazy-cdr lseq)` | Returns the tail (another lazy sequence). Raises an error if empty. |
| `lazy-seq->list` | `(lazy-seq->list lseq)` | Forces the entire sequence and returns a list. |
| `list->lazy-seq` | `(list->lazy-seq lst)` | Converts a proper list to a lazy sequence. |
| `lazy-take` | `(lazy-take n lseq)` | Returns a lazy sequence of at most `n` elements. |
| `lazy-drop` | `(lazy-drop n lseq)` | Returns a lazy sequence with the first `n` elements removed. |
| `lazy-map` | `(lazy-map f lseq)` | Lazily applies `f` to each element. |
| `lazy-filter` | `(lazy-filter pred lseq)` | Lazily keeps only elements satisfying `pred`. |
| `lazy-append` | `(lazy-append lseq1 lseq2)` | Lazily concatenates two sequences. |
| `lazy-range` | `(lazy-range)` | Infinite sequence 0, 1, 2, ... |
| | `(lazy-range end)` | Range `[0, end)` with step 1. |
| | `(lazy-range start end)` | Range `[start, end)` with step 1. |
| | `(lazy-range start end step)` | Range `[start, end)` with the given step. |
| `lazy-iterate` | `(lazy-iterate f seed)` | Infinite sequence: `seed`, `(f seed)`, `(f (f seed))`, ... |
| `lazy-zip` | `(lazy-zip lseq1 lseq2)` | Lazily pairs elements from two sequences into cons pairs. Stops at the shorter. |

### Examples

```scheme
(import (std misc lazy-seq))

;; Finite ranges
(lazy-seq->list (lazy-range 5))         ; => (0 1 2 3 4)
(lazy-seq->list (lazy-range 2 7))       ; => (2 3 4 5 6)
(lazy-seq->list (lazy-range 0 10 3))    ; => (0 3 6 9)

;; Infinite sequences with take
(lazy-seq->list (lazy-take 5 (lazy-iterate add1 0)))
; => (0 1 2 3 4)

;; Powers of 2
(lazy-seq->list (lazy-take 8 (lazy-iterate (lambda (x) (* x 2)) 1)))
; => (1 2 4 8 16 32 64 128)

;; Filter and map
(lazy-seq->list (lazy-filter odd? (lazy-range 0 10)))
; => (1 3 5 7 9)

(lazy-seq->list (lazy-map (lambda (x) (* x x)) (lazy-range 1 6)))
; => (1 4 9 16 25)

;; Zip two sequences
(lazy-seq->list (lazy-zip (lazy-range 0 3) (list->lazy-seq '(a b c))))
; => ((0 . a) (1 . b) (2 . c))

;; Append
(lazy-seq->list (lazy-append (lazy-range 0 3) (lazy-range 10 13)))
; => (0 1 2 10 11 12)

;; Drop
(lazy-seq->list (lazy-take 3 (lazy-drop 5 (lazy-range))))
; => (5 6 7)

;; Build from scratch with lazy-cons
(define fibs
  (let fib ([a 0] [b 1])
    (lazy-cons a (fib b (+ a b)))))
(lazy-seq->list (lazy-take 10 fibs))
; => (0 1 1 2 3 5 8 13 21 34)
```

---

## Weak Collections

**Module:** `(std misc weak)`
**File:** `lib/std/misc/weak.sls`

```scheme
(import (std misc weak))
```

Weak references and collections built on Chez Scheme's GC primitives. Weak pairs hold their car weakly -- when the GC reclaims the referenced object, the car becomes `#!bwp` (broken weak pointer). Weak hash tables hold keys weakly with `eq?` comparison; entries are automatically removed when keys are collected.

### API Reference

#### Weak Pairs

| Procedure | Signature | Description |
|-----------|-----------|-------------|
| `make-weak-pair` | `(make-weak-pair key value)` | Creates a weak pair. The car (`key`) is held weakly; the cdr (`value`) is held strongly. |
| `weak-pair?` | `(weak-pair? obj)` | Returns `#t` if `obj` is a weak pair. |
| `weak-car` | `(weak-car wp)` | Returns the car of the weak pair. May be `#!bwp` if reclaimed. |
| `weak-cdr` | `(weak-cdr wp)` | Returns the cdr of the weak pair. |
| `weak-pair-value` | `(weak-pair-value wp)` | Returns the car if still live, or `#f` if reclaimed. |

#### Weak Lists

| Procedure | Signature | Description |
|-----------|-----------|-------------|
| `list->weak-list` | `(list->weak-list lst)` | Converts a list into a chain of weak pairs. Each element is held weakly. |
| `weak-list->list` | `(weak-list->list wl)` | Collects all live (non-reclaimed) elements into a regular list. |
| `weak-list-compact!` | `(weak-list-compact! wl)` | Destructively removes reclaimed entries. Returns the (possibly new) head. |

#### Weak Hash Tables

| Procedure | Signature | Description |
|-----------|-----------|-------------|
| `make-weak-hashtable` | `(make-weak-hashtable)` | Creates a weak eq-hashtable. Keys are held weakly. |
| | `(make-weak-hashtable size)` | Creates a weak eq-hashtable with initial size hint. |
| `weak-hashtable-ref` | `(weak-hashtable-ref ht key default)` | Looks up `key`, returning `default` if absent or reclaimed. |
| `weak-hashtable-set!` | `(weak-hashtable-set! ht key value)` | Associates `key` with `value`. |
| `weak-hashtable-delete!` | `(weak-hashtable-delete! ht key)` | Removes the entry for `key`. |
| `weak-hashtable-keys` | `(weak-hashtable-keys ht)` | Returns a list of all live keys (filters out `#!bwp` entries). |

### Examples

```scheme
(import (std misc weak))

;; Weak pairs
(define wp (make-weak-pair 'hello 42))
(weak-pair? wp)        ; => #t
(weak-car wp)          ; => hello
(weak-cdr wp)          ; => 42
(weak-pair-value wp)   ; => hello  (still live)

;; Weak lists
(define wl (list->weak-list '(a b c d)))
(weak-list->list wl)   ; => (a b c d)  (all still live)
;; After GC may reclaim unreferenced objects, weak-list->list
;; returns only the surviving elements.

;; Compact removes dead entries in-place
(weak-list-compact! wl) ; => new head of compacted list

;; Weak hash tables for caches
(define cache (make-weak-hashtable))
(let ([key1 (list 'data 1)]
      [key2 (list 'data 2)])
  (weak-hashtable-set! cache key1 "result-1")
  (weak-hashtable-set! cache key2 "result-2")
  (weak-hashtable-ref cache key1 #f)  ; => "result-1"
  (weak-hashtable-keys cache))        ; => ((data 2) (data 1))

(weak-hashtable-delete! cache (list 'data 1))
;; Note: weak-hashtable uses eq? comparison, so the delete above
;; would not find the key unless it is the same object (eq?).
```

**Important:** Weak hash tables use `eq?` comparison for keys, not `equal?`. This means only the exact same object (by identity) will match on lookup or deletion. This is appropriate for caching computed results keyed on object identity.

---

## Generic Collection Protocol

**Module:** `(std misc collection)`
**File:** `lib/std/misc/collection.sls`

```scheme
(import (std misc collection))
```

A protocol for writing algorithms that work across different data structures. The core abstraction is an **iterator**: a thunk that returns `(values element #t)` for each element, then `(values #f #f)` when exhausted. Built-in support for lists, vectors, strings, bytevectors, and hashtables. New types can be registered with `define-collection`.

### API Reference

| Procedure / Macro | Signature | Description |
|-------------------|-----------|-------------|
| `make-iterator` | `(make-iterator coll)` | Returns an iterator thunk for `coll`. Dispatches based on registered type predicates. |
| `define-collection` | `(define-collection pred make-iter)` | Registers a new collection type. `pred` is a type predicate; `make-iter` takes a collection and returns an iterator thunk. |
| `collection-fold` | `(collection-fold proc seed coll)` | Folds `proc` over elements. `proc` receives `(element accumulator)`. |
| `collection-map` | `(collection-map proc coll)` | Applies `proc` to each element, returns a list of results. |
| `collection-filter` | `(collection-filter pred coll)` | Returns a list of elements satisfying `pred`. |
| `collection-for-each` | `(collection-for-each proc coll)` | Calls `proc` on each element for side effects. |
| `collection-find` | `(collection-find pred coll)` | Returns the first element satisfying `pred`, or `#f`. |
| `collection-any` | `(collection-any pred coll)` | Returns `#t` if any element satisfies `pred`. |
| `collection-every` | `(collection-every pred coll)` | Returns `#t` if all elements satisfy `pred`. |
| `collection->list` | `(collection->list coll)` | Converts any collection to a list. |
| `collection-length` | `(collection-length coll)` | Returns the number of elements. |

#### Built-in Collection Types

| Type | Iterator Behavior |
|------|-------------------|
| List | Iterates over elements in order. |
| Vector | Iterates over elements by index. |
| String | Iterates over characters. |
| Bytevector | Iterates over bytes as exact integers. |
| Hashtable | Iterates over `(key . value)` pairs. |

### Examples

```scheme
(import (std misc collection))

;; Works uniformly across types
(collection->list '(1 2 3))       ; => (1 2 3)
(collection->list '#(4 5 6))      ; => (4 5 6)
(collection->list "abc")          ; => (#\a #\b #\c)
(collection->list #vu8(10 20 30)) ; => (10 20 30)

;; Fold
(collection-fold + 0 '(1 2 3 4))    ; => 10
(collection-fold + 0 '#(1 2 3 4))   ; => 10

;; Map and filter
(collection-map add1 '#(1 2 3))          ; => (2 3 4)
(collection-filter even? '(1 2 3 4 5 6)) ; => (2 4 6)

;; Search
(collection-find (lambda (x) (> x 3)) '#(1 2 3 4 5)) ; => 4
(collection-any negative? '(1 -2 3))   ; => #t
(collection-every positive? '(1 2 3))  ; => #t

;; Length
(collection-length "hello")  ; => 5
(collection-length '#(a b c)) ; => 3

;; Iterate over hashtable entries
(let ([ht (make-hashtable string-hash string=?)])
  (hashtable-set! ht "x" 1)
  (hashtable-set! ht "y" 2)
  (collection-map cdr ht))  ; => (1 2)  (order may vary)

;; Register a custom collection type
(define-record-type range-obj (fields start end))

(define-collection range-obj?
  (lambda (r)
    (let ([i (range-obj-start r)]
          [end (range-obj-end r)])
      (let ([current i])
        (lambda ()
          (if (< current end)
              (let ([v current])
                (set! current (+ current 1))
                (values v #t))
              (values #f #f)))))))

(collection->list (make-range-obj 0 5)) ; => (0 1 2 3 4)
(collection-fold + 0 (make-range-obj 1 4)) ; => 6
```

---

## Relational Data Operations

**Module:** `(std misc relation)`
**File:** `lib/std/misc/relation.sls`

```scheme
(import (std misc relation))
```

In-memory relational data operations on tabular data. A relation is a set of rows with named columns (symbols). Rows are stored internally as association lists. Supports select, project, join, group-by, sort, extend, and aggregate.

### API Reference

| Procedure | Signature | Description |
|-----------|-----------|-------------|
| `make-relation` | `(make-relation columns rows)` | Creates a relation. `columns` is a list of symbols. `rows` is a list of lists (positional) or alists. |
| `relation?` | `(relation? x)` | Returns `#t` if `x` is a relation. |
| `relation-columns` | `(relation-columns r)` | Returns the list of column names (symbols). |
| `relation-rows` | `(relation-rows r)` | Returns the rows as a list of alists. |
| `relation-count` | `(relation-count r)` | Returns the number of rows. |
| `relation-ref` | `(relation-ref row col)` | Gets a column value from a row alist. Raises an error if the column is not found. |
| `relation-select` | `(relation-select r pred)` | Filters rows. `pred` receives the row alist. |
| `relation-project` | `(relation-project r cols)` | Selects specific columns. `cols` is a list of symbols. |
| `relation-extend` | `(relation-extend r col-name proc)` | Adds a computed column. `proc` receives the row alist and returns the new column's value. |
| `relation-sort` | `(relation-sort r col comparator)` | Sorts rows by a column using `comparator`. |
| `relation-group-by` | `(relation-group-by r col)` | Groups rows by a column. Returns an alist of `(key-value . sub-relation)`. |
| `relation-join` | `(relation-join r1 r2 key-col)` | Inner join on a shared key column. |
| `relation-aggregate` | `(relation-aggregate r col proc init)` | Folds `proc` over a column's values. `proc` receives `(accumulator column-value)`. |
| `relation->alist-list` | `(relation->alist-list r)` | Returns rows as a list of alists. |
| `alist-list->relation` | `(alist-list->relation alist-list)` | Creates a relation from a list of alists. Column names are taken from the first row. |

### Examples

```scheme
(import (std misc relation))

;; Create a relation with positional rows
(define people
  (make-relation '(name age city)
    '(("Alice" 30 "Portland")
      ("Bob"   25 "Seattle")
      ("Carol" 35 "Portland")
      ("Dave"  28 "Seattle"))))

(relation-count people) ; => 4

;; Select (filter) rows
(define portlanders
  (relation-select people
    (lambda (row) (string=? (relation-ref row 'city) "Portland"))))
(relation-count portlanders) ; => 2

;; Project (pick columns)
(define names-only (relation-project people '(name)))
(relation->alist-list names-only)
; => (((name . "Alice")) ((name . "Bob")) ((name . "Carol")) ((name . "Dave")))

;; Extend with a computed column
(define with-senior
  (relation-extend people 'senior?
    (lambda (row) (>= (relation-ref row 'age) 30))))
(relation-ref (car (relation-rows with-senior)) 'senior?) ; => #t

;; Sort by age
(define by-age (relation-sort people 'age <))
(map (lambda (row) (relation-ref row 'name))
     (relation-rows by-age))
; => ("Bob" "Dave" "Alice" "Carol")

;; Group by city
(define by-city (relation-group-by people 'city))
;; by-city is an alist: (("Portland" . <relation>) ("Seattle" . <relation>))
(relation-count (cdar by-city)) ; => 2

;; Aggregate: sum of ages
(relation-aggregate people 'age + 0) ; => 118

;; Join two relations
(define depts
  (make-relation '(name dept)
    '(("Alice" "Engineering")
      ("Bob"   "Marketing")
      ("Carol" "Engineering"))))

(define joined (relation-join people depts 'name))
(relation-columns joined) ; => (name age city dept)
(relation-count joined)   ; => 3  (Dave has no dept, so excluded)

;; Round-trip via alists
(define r2
  (alist-list->relation
    '(((id . 1) (label . "first"))
      ((id . 2) (label . "second")))))
(relation-columns r2) ; => (id label)
```

---

## LCS-Based Diff

**Module:** `(std misc diff)`
**File:** `lib/std/misc/diff.sls`

```scheme
(import (std misc diff))
```

Diff and edit distance algorithms based on the Longest Common Subsequence (LCS). Works on arbitrary lists (with a configurable equality predicate) and on multiline strings.

### API Reference

| Procedure | Signature | Description |
|-----------|-----------|-------------|
| `lcs` | `(lcs xs ys)` | Returns the longest common subsequence as a list. Uses `equal?`. |
| | `(lcs xs ys =?)` | LCS with a custom equality predicate. |
| `diff` | `(diff xs ys)` | Returns a list of edit operations: `(same val)`, `(add val)`, `(remove val)`. Uses `equal?`. |
| | `(diff xs ys =?)` | Diff with a custom equality predicate. |
| `edit-distance` | `(edit-distance xs ys)` | Levenshtein edit distance between two lists. Uses `equal?`. |
| | `(edit-distance xs ys =?)` | Edit distance with a custom equality predicate. |
| `diff->string` | `(diff->string ops)` | Formats diff operations as a unified-diff-style string: `" val"` for same, `"+val"` for add, `"-val"` for remove. |
| `diff-report` | `(diff-report ops)` | Prints `diff->string` output to `current-output-port`. |
| `diff-strings` | `(diff-strings s1 s2)` | Diffs two strings line-by-line, returning a formatted diff string. |

### Examples

```scheme
(import (std misc diff))

;; Longest common subsequence
(lcs '(a b c d) '(b d f))   ; => (b d)
(lcs '(1 2 3 4) '(2 4 6 8)) ; => (2 4)

;; Diff two lists
(diff '(a b c) '(b c d))
; => ((remove a) (same b) (same c) (add d))

(diff '(1 2 3 4 5) '(1 3 4 6))
; => ((same 1) (remove 2) (same 3) (same 4) (remove 5) (add 6))

;; Custom equality
(diff '("Hello" "World") '("hello" "World") string-ci=?)
; => ((same "Hello") (same "World"))

;; Edit distance
(edit-distance '(a b c) '(b c d))       ; => 2
(edit-distance '(k i t t e n) '(s i t t i n g)) ; => 3

;; Format diff output
(display (diff->string (diff '(a b c) '(b c d))))
;; Output:
;; -a
;;  b
;;  c
;; +d

;; Diff two strings line-by-line
(display (diff-strings "line1\nline2\nline3" "line1\nchanged\nline3"))
;; Output:
;;  line1
;; -line2
;; +changed
;;  line3

;; Print diff report directly
(diff-report (diff '(x y z) '(x z w)))
;; Output:
;;  x
;; -y
;;  z
;; +w
```

---

## Cycle-Aware Equality

**Module:** `(std misc equiv)`
**File:** `lib/std/misc/equiv.sls`

```scheme
(import (std misc equiv))
```

Structural equality and hashing that handle cyclic data structures. `equiv?` is like `equal?` but tracks visited object pairs to detect cycles. `equiv-hash` uses depth-bounded traversal to produce a hash value without infinite recursion on cycles.

### API Reference

| Procedure | Signature | Description |
|-----------|-----------|-------------|
| `equiv?` | `(equiv? a b)` | Cycle-aware structural equality. Returns `#t` if `a` and `b` are structurally equal, even if they contain cycles. |
| `equiv-hash` | `(equiv-hash x)` | Cycle-aware hash with default depth limit of 64. |
| | `(equiv-hash x depth)` | Cycle-aware hash with explicit depth limit. |

#### Types Handled by `equiv?`

| Type | Comparison |
|------|------------|
| Pairs | Recursive on car and cdr, with cycle detection. |
| Vectors | Element-wise recursive, with cycle detection. |
| Strings | `string=?` |
| Bytevectors | `bytevector=?` |
| Boxes | Recursive on unboxed value, with cycle detection. |
| Hashtables | Same size, then recursive on values for each key in `a`. |
| Everything else | Falls back to `equal?`. |

### Examples

```scheme
(import (std misc equiv))

;; Basic structural equality (same as equal? for acyclic data)
(equiv? '(1 2 3) '(1 2 3))               ; => #t
(equiv? '#(a b c) '#(a b c))             ; => #t
(equiv? "hello" "hello")                  ; => #t

;; Cyclic list
(define a (list 1 2 3))
(set-cdr! (cddr a) a)   ; a is now a cycle: 1 -> 2 -> 3 -> 1 -> ...

(define b (list 1 2 3))
(set-cdr! (cddr b) b)   ; b is the same cyclic structure

(equiv? a b)  ; => #t   (equal? would loop forever)

;; Cyclic vector
(define v1 (vector 'x #f))
(vector-set! v1 1 v1)         ; v1 points to itself
(define v2 (vector 'x #f))
(vector-set! v2 1 v2)         ; v2 points to itself

(equiv? v1 v2) ; => #t

;; Hashing cyclic structures
(equiv-hash a)      ; => a fixnum (does not loop forever)
(equiv-hash a 10)   ; => hash with depth limit 10

;; Use with hashtables for cycle-safe keys
(define ht (make-hashtable equiv-hash equiv?))
```

**Note:** `equiv-hash` bounds traversal depth to avoid infinite recursion. The default depth is 64. For deeply nested but acyclic structures, you can increase the depth for better hash distribution. For cyclic structures, the depth bound ensures termination -- at the depth limit, elements contribute `0` to the hash.

---

## Cross-Cutting Patterns

### Combining Persistent Maps with Lazy Sequences

```scheme
(import (std misc persistent))
(import (std misc lazy-seq))

;; Build a HAMT from a lazy sequence of key-value pairs
(define pairs (lazy-zip (lazy-range 0 5) (list->lazy-seq '(a b c d e))))
(define h
  (let loop ([s pairs] [h hamt-empty])
    (if (lazy-null? s)
        h
        (let ([p (lazy-car s)])
          (loop (lazy-cdr s) (hamt-set h (car p) (cdr p)))))))
(hamt-ref h 3 #f) ; => d
```

### Using the Collection Protocol with Custom Types

```scheme
(import (std misc collection))
(import (std misc persistent))

;; Register HAMTs as a collection (iterates over (key . value) pairs)
(define-collection hamt?
  (lambda (h)
    (let ([pairs (hamt->alist h)]
          [rest '()])
      (set! rest pairs)
      (lambda ()
        (if (null? rest)
            (values #f #f)
            (let ([p (car rest)])
              (set! rest (cdr rest))
              (values p #t)))))))

(define h (alist->hamt '((a . 1) (b . 2) (c . 3))))
(collection-length h)                              ; => 3
(collection-map cdr h)                             ; => (1 2 3)  (order may vary)
(collection-find (lambda (p) (eq? (car p) 'b)) h) ; => (b . 2)
```
