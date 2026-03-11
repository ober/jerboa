# Lazy Sequences, Transducers, and Data Tables

Jerboa provides three complementary data processing abstractions:
- **Lazy sequences** for on-demand, potentially infinite data
- **Transducers** for composable, source-independent transformations
- **Data tables** for columnar in-memory analytics

---

## Lazy Sequences

**Import:** `(std seq)`

Lazy sequences produce elements on demand. The tail of a lazy sequence is a
memoized thunk — computed at most once, never re-evaluated.

### Construction

```scheme
(lazy-cons head rest-expr)    ; create a lazy pair; rest-expr is lazily evaluated
(lazy-nil)                    ; the empty lazy sequence
(lazy-nil? seq)               ; #t if seq is lazy-nil
(lazy-seq? x)                 ; #t if x is any lazy sequence (nil or cons)
```

### Accessing elements

```scheme
(lazy-first seq)   ; head element (error if nil)
(lazy-rest  seq)   ; tail (forces the thunk, memoized)
(lazy-force x)     ; if x is a thunk, call it; otherwise return x
```

### Building sequences

```scheme
(lazy-range end)                   ; 0, 1, ..., end-1
(lazy-range start end)             ; start, start+1, ..., end-1
(lazy-range start end step)        ; with step
(lazy-iterate f x)                 ; x, (f x), (f (f x)), ... — infinite
(lazy-repeat x)                    ; x, x, x, ... — infinite
(lazy-cycle lst)                   ; cycle through list elements — infinite
(list->lazy lst)                   ; convert list to lazy sequence
```

### Transformations

```scheme
(lazy-map f seq)
(lazy-filter pred seq)
(lazy-take n seq)
(lazy-drop n seq)
(lazy-take-while pred seq)
(lazy-drop-while pred seq)
(lazy-zip seq1 seq2)         ; pairs of (a b) until shorter ends
(lazy-append seq1 seq2)
(lazy-flatten seq)           ; flatten nested lazy sequences
```

### Consumption

```scheme
(lazy->list seq)             ; force entire sequence into a list
(lazy-for-each f seq)        ; iterate for side effects
(lazy-fold f init seq)       ; left fold
(lazy-count seq)             ; count elements (forces everything)
(lazy-any? pred seq)         ; short-circuits on first match
(lazy-all? pred seq)         ; short-circuits on first mismatch
(lazy-nth n seq)             ; nth element (0-indexed)
```

### Examples

```scheme
(import (chezscheme) (std seq))

;; Infinite Fibonacci sequence
(define fibs
  (let fib ([a 0] [b 1])
    (lazy-cons a (fib b (+ a b)))))

(lazy->list (lazy-take 10 fibs))
; => (0 1 1 2 3 5 8 13 21 34)

;; Infinite primes via sieve
(define (sieve seq)
  (let ([p (lazy-first seq)])
    (lazy-cons p (sieve (lazy-filter (lambda (n) (not (= 0 (mod n p))))
                                     (lazy-rest seq))))))

(define primes (sieve (lazy-range 2 +inf.0)))

(lazy->list (lazy-take 10 primes))
; => (2 3 5 7 11 13 17 19 23 29)

;; Process a large file lazily
(define (file->lazy-lines path)
  (let ([port (open-input-file path)])
    (let loop ()
      (let ([line (get-line port)])
        (if (eof-object? line)
          (begin (close-port port) (lazy-nil))
          (lazy-cons line (loop)))))))

;; Get first 100 non-empty lines
(lazy->list
  (lazy-take 100
    (lazy-filter (lambda (l) (> (string-length l) 0))
                 (file->lazy-lines "/var/log/syslog"))))
```

---

## Transducers

Transducers are composable transformations that are independent of their data source.
A transducer transforms a reducer function: `(xf rf) → new-rf`.

### Built-in transducers

```scheme
(map-xf f)              ; transform each element with f
(filter-xf pred)        ; keep elements where pred returns #t
(take-xf n)             ; keep first n elements
(drop-xf n)             ; skip first n elements
(take-while-xf pred)    ; keep while pred holds
(drop-while-xf pred)    ; skip while pred holds
(flat-map-xf f)         ; apply f returning a list, flatten results
(dedupe-xf)             ; remove consecutive duplicates
```

### Composition

```scheme
(compose-xf xf1 xf2 ...)   ; left-to-right composition
```

### Running transducers

```scheme
(transduce xf rf init coll)     ; apply xf+rf over coll (list or lazy seq)
(into '() xf coll)              ; collect into a list
(sequence xf coll)              ; alias for (into '() xf coll)
```

### Example — pipeline processing

```scheme
(import (chezscheme) (std seq))

(define data '(1 2 3 4 5 6 7 8 9 10))

;; Composable pipeline: filter evens, square, take first 3
(define pipeline
  (compose-xf
    (filter-xf even?)
    (map-xf (lambda (x) (* x x)))
    (take-xf 3)))

(into '() pipeline data)
; => (4 16 36)

;; Same pipeline over a lazy sequence
(into '() pipeline (lazy-range 1 100))
; => (4 16 36)

;; Reduce with a transducer
(transduce (filter-xf odd?) + 0 data)
; => 25  (1+3+5+7+9)
```

---

## Parallel Collections

```scheme
(par-map f lst)                         ; map in parallel (4 chunks by default)
(par-map f lst 'chunk-size: 10)        ; with custom chunk size
(par-filter pred lst)                   ; filter in parallel
(par-reduce f init lst)                 ; reduce in parallel (f must be associative)
(par-for-each f lst)                    ; side effects in parallel
```

```scheme
(import (chezscheme) (std seq))

;; Parallel image processing
(define images (map load-image (directory-list "images/")))
(define processed (par-map resize-and-compress images))

;; Parallel word count
(define files (directory-list "corpus/"))
(define total-words
  (par-reduce +
    0
    (par-map count-words files)))
```

---

## Data Tables

**Import:** `(std table)`

In-memory tables with columnar storage and SQL-like operations. Efficient for
analytics over thousands to millions of rows.

### Construction

```scheme
(make-table '(col1 col2 col3))       ; create empty table
(table? x)
(table-columns t)                    ; number of columns
(table-row-count t)                  ; number of rows
(table-column-names t)               ; list of column name symbols
```

### Adding data

```scheme
(table-add-row! t '((col1 . val1) (col2 . val2) ...))  ; add one row (alist)
(table-from-rows '(col1 col2) '((a 1) (b 2) ...))      ; from list of value lists
(table-from-alist '(col1 col2) '(((col1 . a) (col2 . 1)) ...))  ; from list of alists
```

### Reading data

```scheme
(table-column t 'col-name)    ; entire column as a list
(table-row t row-index)       ; one row as alist
(table-ref t row-idx 'col)    ; single cell
(table-rows t)                ; all rows as list of alists
```

### SQL-like operations (all return new tables)

```scheme
(table-select t '(col1 col3))          ; projection — keep subset of columns
(table-where t pred)                    ; filter — pred receives row alist
(table-sort-by t 'col)                 ; sort ascending
(table-sort-by t 'col 'descending: #t); sort descending
(table-take t n)                        ; first n rows
(table-drop t n)                        ; skip first n rows
(table-join t1 t2 'key-col)            ; inner join on shared column
(table-group-by t 'col)                ; hashtable of value → subtable
```

### Aggregation

```scheme
;; table-aggregate takes a group hashtable and vararg triples:
;; result-col-name  agg-fn  src-col-name
(table-aggregate groups
  'total   agg-sum   'sales
  'count   agg-count 'sales
  'average agg-mean  'sales)

;; Built-in aggregation functions
(agg-count col)    ; number of elements
(agg-sum col)      ; sum
(agg-mean col)     ; average
(agg-min col)      ; minimum
(agg-max col)      ; maximum
(agg-collect col)  ; return the list itself
```

### Output

```scheme
(table-print t)          ; print formatted table to stdout
(table-print t port)     ; print to port
(table->list t)          ; list of row alists
```

### Complete example

```scheme
(import (chezscheme) (std table))

;; Build a sales table
(define sales
  (table-from-rows '(product region sales qty)
    '((widget  north  1200  40)
      (gadget  north   800  25)
      (widget  south  1500  50)
      (gadget  south   600  20)
      (widget  east    900  30)
      (gadget  east   1100  35))))

;; Show it
(table-print sales)

;; Get widgets only
(define widgets
  (table-where sales (lambda (row) (equal? (cdr (assoc 'product row)) 'widget))))

;; Total sales by region
(define by-region (table-group-by sales 'region))
(define summary
  (table-aggregate by-region
    'region  agg-collect 'region
    'revenue agg-sum     'sales
    'units   agg-sum     'qty))

(table-print (table-sort-by summary 'revenue 'descending: #t))

;; Join with a discount table
(define discounts
  (table-from-rows '(region discount)
    '((north 0.10)
      (south 0.05)
      (east  0.15))))

(define with-discounts (table-join sales discounts 'region))
(table-print with-discounts)
```
