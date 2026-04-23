# LLM Divergence Sheet

_Auto-generated from `jerboa-mcp/divergence.json` (version 1.0, 2026-04-22)._
_119 entries._

> This catalog lists identifiers and forms that LLMs commonly reach for from other Scheme dialects (Gerbil, Gambit, Racket, R6RS, R7RS, Common Lisp, Clojure, SRFI) that are **wrong in Jerboa/Chez**. Each entry pairs the hallucinated form with the correct Jerboa equivalent.
>
> **Severity:** `ERROR` = won't run; `warning` = runs but wrong idiom; `aliased` = hallucination now accepted as a prelude alias.

## Contents

- [arg-order](#arg-order) (4)
- [arity](#arity) (4)
- [hash-tables](#hash-tables) (13)
- [lists](#lists) (1)
- [strings](#strings) (10)
- [collections](#collections) (2)
- [records](#records) (5)
- [pattern-matching](#pattern-matching) (2)
- [binding](#binding) (4)
- [definitions](#definitions) (6)
- [control](#control) (3)
- [mutation](#mutation) (1)
- [iterators](#iterators) (2)
- [parameters](#parameters) (1)
- [predicates](#predicates) (1)
- [values](#values) (4)
- [methods](#methods) (1)
- [typing](#typing) (1)
- [errors](#errors) (6)
- [concurrency](#concurrency) (5)
- [process](#process) (1)
- [io](#io) (12)
- [formatting](#formatting) (3)
- [filesystem](#filesystem) (2)
- [environment](#environment) (1)
- [modules](#modules) (5)
- [regex](#regex) (2)
- [numerics](#numerics) (2)
- [bitwise](#bitwise) (2)
- [bytevectors](#bytevectors) (2)
- [vectors](#vectors) (1)
- [symbols](#symbols) (1)
- [equality](#equality) (1)
- [meta](#meta) (2)
- [time](#time) (1)
- [literals](#literals) (1)
- [reader-syntax](#reader-syntax) (2)
- [logging](#logging) (1)
- [internals](#internals) (1)

## arg-order

### `(sort lst pred)` → `(sort pred lst)`

****ERROR**** · from Gerbil, SRFI-95, Common Lisp · id: `arg-order-sort`

**Wrong:**
```scheme
(sort '(3 1 2) <)
```

**Correct:**
```scheme
(sort < '(3 1 2))
```

_Chez arg order: predicate first, list second. This is the opposite of Gerbil/SRFI/Racket._

### `(hash-ref key ht)` → `(hash-ref ht key)`

****ERROR**** · from common-lisp-gethash · id: `arg-order-hash-ref`

**Wrong:**
```scheme
(hash-ref "k" ht)
```

**Correct:**
```scheme
(hash-ref ht "k")  ;; or (hash-ref ht "k" default)
```

_Table first, key second. CL's gethash reverses these._

### `(fold-left proc lst init)` → `(fold-left proc init lst)`

****ERROR**** · from srfi-1-fold · id: `arg-order-fold-left`

**Wrong:**
```scheme
(fold-left + '(1 2 3) 0)
```

**Correct:**
```scheme
(fold-left + 0 '(1 2 3))
```

_Chez R6RS order: proc, init, then list(s). SRFI-1 fold has init LAST._

### `(string-split "," str)` → `(string-split str #\delim)`

****ERROR**** · from Racket · id: `arg-order-string-split-char`

**Wrong:**
```scheme
(string-split "," "a,b,c")
```

**Correct:**
```scheme
(string-split "a,b,c" #\,)
```

_String first, delimiter second. Delimiter must be a CHAR, not a string._


## arity

### `(in-range start step end)` → `(in-range start end step)`

****ERROR**** · from pure hallucination · id: `arity-in-range`

**Wrong:**
```scheme
(in-range 0 2 10)  ;; intended: 0, 2, 4, 6, 8
```

**Correct:**
```scheme
(in-range 0 10 2)  ;; 0 2 4 6 8
```

_Step is the LAST arg, not middle. 1-arg form: (in-range end). 2-arg: (in-range start end). 3-arg: (in-range start end step)._

### `(make-rwlock 'name)` → `(make-rwlock)`

****ERROR**** · from Gerbil · id: `arity-make-rwlock`

**Wrong:**
```scheme
(make-rwlock 'my-lock)
```

**Correct:**
```scheme
(make-rwlock)
```

_Gerbil's make-rwlock takes a name; Jerboa's takes 0 args._

### `(list-of? pred lst)` → `((list-of? pred) lst)`

****ERROR**** · from pure hallucination · id: `arity-list-of-predicate`

**Wrong:**
```scheme
(list-of? number? '(1 2 3))
```

**Correct:**
```scheme
((list-of? number?) '(1 2 3))  ;; → #t
```

_list-of? RETURNS a predicate of 1 arg. It's a factory, not a direct test._

### `(maybe pred val)` → `((maybe pred) val)`

****ERROR**** · from pure hallucination · id: `arity-maybe-predicate`

**Wrong:**
```scheme
(maybe string? #f)
```

**Correct:**
```scheme
((maybe string?) #f)  ;; → #t (accepts #f or string)
```

_maybe is a predicate combinator: (maybe pred) → λval. #f is always accepted._


## hash-tables

### `hash-has-key?` → `hash-key?`

**aliased (works in prelude)** · from Racket · id: `racket-hash-has-key`

**Available in Jerboa via:** `(jerboa clojure)`, `(jerboa prelude)`

**Wrong:**
```scheme
(hash-has-key? ht "k")
```

**Correct:**
```scheme
(hash-key? ht "k")
```

_hash-has-key? is aliased to hash-key? in (jerboa prelude) for Racket-familiarity._

### `hash-table-set!` → `hash-put!`

**aliased (works in prelude)** · from Racket, SRFI-69 · id: `racket-hash-table-set-bang`

**Available in Jerboa via:** `(jerboa clojure)`, `(jerboa prelude)`, `(std srfi srfi-125)`

**Wrong:**
```scheme
(hash-table-set! ht k v)
```

**Correct:**
```scheme
(hash-put! ht k v)
```

_hash-table-set! is aliased to hash-put! in the prelude._

### `make-equal-hashtable` → `make-hash-table`

**warning** · from R6RS · id: `r6rs-make-equal-hashtable`

**Wrong:**
```scheme
(make-equal-hashtable)
```

**Correct:**
```scheme
(make-hash-table)
```

_R6RS make-equal-hashtable works in Chez but prelude's make-hash-table is the Jerboa idiom. For eq-hashtables use (make-eq-hashtable) from (chezscheme)._

### `(hash-table-ref ht key default-thunk)` → `hash-ref`

****ERROR**** · from SRFI-69 · id: `srfi-hash-table-ref`

**Wrong:**
```scheme
(hash-table-ref ht "k" (lambda () 0))
```

**Correct:**
```scheme
(hash-ref ht "k" 0)  ;; default is a value, not a thunk
```

_Jerboa's hash-ref default is a value (not a thunk). Use (hash-get ht key) to get #f if missing._

### `(hash k v ...)` → `(list->hash-table '((k . v) ...))`

****ERROR**** · from Racket · id: `racket-hash`

**Wrong:**
```scheme
(hash "a" 1 "b" 2)
```

**Correct:**
```scheme
(list->hash-table '(("a" . 1) ("b" . 2)))
```

### `(make-hash)` → `make-hash-table`

****ERROR**** · from Racket · id: `racket-make-hash`

**Wrong:**
```scheme
(make-hash)
```

**Correct:**
```scheme
(make-hash-table)
```

### `(make-eqv-hashtable)` → `(make-hashtable equal-hash equal?) or make-hash-table`

**warning** · from R6RS · id: `r6rs-make-eqv-hashtable`

**Wrong:**
```scheme
(make-eqv-hashtable)
```

**Correct:**
```scheme
(make-hash-table)  ;; for equal-keyed
;; for eqv-keyed in Chez:
(import (chezscheme))
(make-hashtable equal-hash equal?)
```

_Chez supports make-eqv-hashtable as part of R6RS but Jerboa idiom is make-hash-table (equal?)._

### `make-table, table-set!, table-ref` → `make-hash-table + hash-put!/hash-ref`

****ERROR**** · from Gambit · id: `gambit-table`

**Wrong:**
```scheme
(make-table) ; (table-set! t k v)
```

**Correct:**
```scheme
(def t (make-hash-table))
(hash-put! t k v)
(hash-ref t k)
```

_Gambit calls hash tables 'tables'. Use the hash-* family in Jerboa._

### `hash-table-walk` → `hash-for-each`

****ERROR**** · from SRFI-69 · id: `srfi-hash-table-walk`

**Wrong:**
```scheme
(hash-table-walk ht (lambda (k v) ...))
```

**Correct:**
```scheme
(hash-for-each (lambda (k v) ...) ht)
```

_Argument order: proc first, table second — opposite of SRFI-69._

### `hash-table-keys` → `hash-keys`

**compat (works via specific import)** · from SRFI-69 · id: `srfi-hash-table-keys`

**Available in Jerboa via:** `(std srfi srfi-125)`

**Wrong:**
```scheme
(hash-table-keys ht)
```

**Correct:**
```scheme
(hash-keys ht)
```

_AVAILABLE in Jerboa via: (std srfi srfi-125)._

### `(get coll k)` → `hash-get`

****ERROR**** · from Clojure · id: `clojure-get`

**Wrong:**
```scheme
(get ht "k")
```

**Correct:**
```scheme
(hash-get ht "k")  ;; #f if missing, no error
```

_hash-get returns #f if missing (like Clojure's get with no default). hash-ref raises._

### `(assoc coll k v)` → `hash-put! (mutates)`

****ERROR**** · from Clojure · id: `clojure-assoc`

**Wrong:**
```scheme
(assoc ht "k" v)
```

**Correct:**
```scheme
(hash-put! ht "k" v)
```

_Jerboa hash tables are mutable. Clojure's functional assoc returns a new map; no direct equivalent without copy._

### `(into {} pairs)` → `list->hash-table`

****ERROR**** · from Clojure · id: `clojure-map-into`

**Wrong:**
```scheme
(into {} '(("a" 1) ("b" 2)))
```

**Correct:**
```scheme
(list->hash-table '(("a" . 1) ("b" . 2)))
```

_Note dotted pair syntax for alists._


## lists

### `(first lst), (rest lst)` → `car / cdr`

****ERROR**** · from Clojure · id: `clojure-first-rest`

**Wrong:**
```scheme
(first '(1 2 3))
```

**Correct:**
```scheme
(car '(1 2 3))  ;; 1
(cdr '(1 2 3))  ;; (2 3)
```

_Classic Lisp car/cdr. first/second/third exist in SRFI-1 (std misc list) but car/cdr is preferred._


## strings

### `string-map` → `string-map`

**aliased (works in prelude)** · from Racket, R7RS · id: `racket-string-map`

**Available in Jerboa via:** `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude)`, `(std gambit-compat)`

**Wrong:**
```scheme
(string-map char-upcase "hello")
```

**Correct:**
```scheme
(string-map char-upcase "hello")
```

_string-map in the prelude is the char-level Racket/R7RS version. Chez's own string-map signature differs; prelude wraps to Racket semantics._

### `string-contains?` → `string-contains`

**compat (works via specific import)** · from Racket · id: `racket-string-contains-predicate`

**Available in Jerboa via:** `(std misc string-more)`

**Wrong:**
```scheme
(if (string-contains? s "foo") ...)
```

**Correct:**
```scheme
(if (string-contains s "foo") ...)  ;; returns index or #f — truthy if found
```

_AVAILABLE in Jerboa via: (std misc string-more). Jerboa's string-contains (no ?) returns an index or #f, NOT a boolean. Both values are truthy/falsy in conditionals, so `if` works directly._

### `string-subst` → `string-replace`

**compat (works via specific import)** · from Gerbil · id: `gerbil-string-subst`

**Available in Jerboa via:** `(jerboa core)`, `(std gambit-compat)`

**Wrong:**
```scheme
(string-subst "hello" "l" "L")
```

**Correct:**
```scheme
(string-replace "hello" "l" "L")
```

_AVAILABLE in Jerboa via: (jerboa core), (std gambit-compat). Use string-replace (Jerboa) or re-replace-all from the regex module for regex-based replacement._

### `string-search, string-search-forward` → `string-contains`

****ERROR**** · from SRFI-13 · id: `srfi-string-search`

**Wrong:**
```scheme
(string-search sub str)
```

**Correct:**
```scheme
(string-contains str sub)  ;; index or #f
```

### `"#{x}"` → `(str ...) or format`

****ERROR**** · from Ruby, python-fstring · id: `ruby-string-interpolation`

**Wrong:**
```scheme
"hello #{name}"
```

**Correct:**
```scheme
(str "hello " name)  ;; auto-coerce to string
(format "hello ~a" name)
```

_No string interpolation. Use the str auto-coerce helper or format._

### `string-starts-with?` → `string-prefix?`

****ERROR**** · from pure hallucination, racket-string · id: `hallucinated-string-starts-with`

**Wrong:**
```scheme
(string-starts-with? "hello" "he")
```

**Correct:**
```scheme
(string-prefix? "he" "hello")  ;; NOTE arg order: prefix first
```

_Note arg order is (string-prefix? PREFIX STRING). Opposite of some Racket naming._

### `string-ends-with?` → `string-suffix?`

****ERROR**** · from pure hallucination · id: `hallucinated-string-ends-with`

**Wrong:**
```scheme
(string-ends-with? "hello" "lo")
```

**Correct:**
```scheme
(string-suffix? "lo" "hello")  ;; suffix first, string second
```

### `(string-index str char)` → `string-contains with char-as-string`

**warning** · from Gerbil, SRFI-13 · id: `gerbil-string-index`

**Wrong:**
```scheme
(string-index "hello" #\l)
```

**Correct:**
```scheme
(string-contains "hello" "l")  ;; returns 2
```

_No string-index in prelude. For a single char, use string-contains with 1-char string._

### `(subs s start end)` → `substring`

****ERROR**** · from Clojure · id: `clojure-subs`

**Wrong:**
```scheme
(subs "hello" 1 3)
```

**Correct:**
```scheme
(substring "hello" 1 3)  ;; "el"
```

### `(str a b c)  ;; Clojure stringifies each arg` → `str (works, auto-coerce)`

**warning** · from Clojure · id: `clojure-str-concat`

**Wrong:**
```scheme
(str "age " 42)
```

**Correct:**
```scheme
(str "age " 42)  ;; → "age 42"
```

_Jerboa's str auto-coerces non-strings (same as Clojure). This is a correct usage._


## collections

### `count` → `length`

**compat (works via specific import)** · from Clojure · id: `clojure-count`

**Available in Jerboa via:** `(jerboa clojure)`, `(std clojure)`, `(std srfi srfi-1)`

**Wrong:**
```scheme
(count lst)
```

**Correct:**
```scheme
(length lst)  ;; for lists
(vector-length v) ;; vectors
(string-length s) ;; strings
(hash-table-size ht) ;; hash tables
```

_AVAILABLE in Jerboa via: (jerboa clojure), (std clojure), (std srfi srfi-1)._

### `len` → `length / string-length / vector-length`

****ERROR**** · from Python · id: `python-len`

**Wrong:**
```scheme
(len lst)
```

**Correct:**
```scheme
(length lst)
```


## records

### `define-struct` → `defstruct`

****ERROR**** · from Racket · id: `racket-define-struct`

**Wrong:**
```scheme
(define-struct point (x y))
```

**Correct:**
```scheme
(defstruct point (x y))
```

_Generates make-point, point?, point-x, point-y, point-x-set!. For inheritance: (defstruct (circle shape) (radius))._

### `make-class-type` → `defstruct or defclass`

****ERROR**** · from Gerbil · id: `gerbil-make-class-type`

**Wrong:**
```scheme
(make-class-type ...)
```

**Correct:**
```scheme
(defstruct point (x y))
(defclass shape () (name))
```

_Gerbil's class system is lower-level. Jerboa provides defstruct (define-record-type) and defclass._

### `(define-record-type name (constructor field ...) pred field-accessor ...)` → `defstruct`

**warning** · from R7RS · id: `r7rs-define-record-type`

**Wrong:**
```scheme
(define-record-type point (mk-point x y) point? (x point-x) (y point-y))
```

**Correct:**
```scheme
(defstruct point (x y))
```

_R6RS define-record-type works in Chez but is verbose. defstruct is the Jerboa idiom._

### `(struct name (field ...))` → `defstruct`

****ERROR**** · from Racket · id: `racket-struct`

**Wrong:**
```scheme
(struct point (x y))
```

**Correct:**
```scheme
(defstruct point (x y))
```

### `&slot-ref, slot-ref` → `accessor functions`

****ERROR**** · from Gerbil · id: `gerbil-slot-ref`

**Wrong:**
```scheme
(slot-ref obj 'x)
```

**Correct:**
```scheme
(point-x p)  ;; generated by defstruct
;; or using dot-access:
(using (p point : point?) p.x)
```


## pattern-matching

### `(list-rest ...)` → `(cons a b) in match`

****ERROR**** · from Racket · id: `racket-match-list`

**Wrong:**
```scheme
(match x ((list-rest a b) ...))
```

**Correct:**
```scheme
(match x ((cons a b) ...))  ;; b is rest
```

_Use (list a b ...) for fixed-length, (cons a rest) for head+tail._

### `(app fn pat)` → `(=> fn var)`

****ERROR**** · from racket-match · id: `racket-match-app`

**Wrong:**
```scheme
(match x ((app car 1) ...))
```

**Correct:**
```scheme
(match x ((=> string->number n) (use n)))
```

_Jerboa match uses => for view patterns instead of app._


## binding

### `(when-let* ((x e1) (y e2)) body)` → `nested when-let`

**warning** · from Racket, Clojure · id: `cl-when-let-multi`

**Wrong:**
```scheme
(when-let* ((x (find)) (y (lookup x))) (use y))
```

**Correct:**
```scheme
(when-let (x (find))
  (when-let (y (lookup x))
    (use y)))
```

_Jerboa's when-let is single-binding. For multiple, nest them or use cond-let pattern._

### `let*-values` → `let*-values (works)`

**warning** · from R6RS, R7RS · id: `gerbil-let-values-star`

**Wrong:**
```scheme
(let*-values (((a b) (f))) ...)
```

**Correct:**
```scheme
(let*-values (((a b) (f)) ((c) (g a))) ...)
```

_This actually works in Chez/R6RS. Included because LLMs sometimes second-guess whether it exists._

### `(let [[a b] pair] ...)` → `(match ...)  or (apply (lambda (a b) ...) lst)`

****ERROR**** · from Clojure · id: `clojure-let-destructure`

**Wrong:**
```scheme
(let [[a b] '(1 2)] (+ a b))
```

**Correct:**
```scheme
(match '(1 2) ((list a b) (+ a b)))
```

_let doesn't destructure in Scheme. Use match or explicit car/cadr._

### `(let ((x 1)) body)  ;; comma patterns etc.` → `standard scheme let`

**warning** · from Emacs Lisp · id: `emacs-lisp-let-binding`

**Wrong:**
```scheme
(let ((x 1) (y 2)) ,x)
```

**Correct:**
```scheme
(let ((x 1) (y 2)) (+ x y))
```

_No quasiquote unquoting in body. LLMs occasionally emit comma._


## definitions

### `defun` → `def`

****ERROR**** · from Common Lisp, Emacs Lisp · id: `cl-defun`

**Wrong:**
```scheme
(defun f (x) (* x 2))
```

**Correct:**
```scheme
(def (f x) (* x 2))
```

### `defvar` → `def`

****ERROR**** · from Common Lisp, Emacs Lisp · id: `cl-defvar`

**Wrong:**
```scheme
(defvar *x* 42)
```

**Correct:**
```scheme
(def x 42)
```

### `defparameter` → `define or make-parameter`

****ERROR**** · from Common Lisp · id: `cl-defparameter`

**Wrong:**
```scheme
(defparameter *max* 100)
```

**Correct:**
```scheme
(define max-p (make-parameter 100))
(max-p)  ;; 100
(parameterize ((max-p 200)) (max-p))  ;; 200
```

_For dynamic scoping, use make-parameter + parameterize, not a global var._

### `defn` → `def`

**compat (works via specific import)** · from Clojure · id: `clojure-defn`

**Available in Jerboa via:** `(jerboa clojure)`, `(jerboa prelude)`, `(std prelude)`, `(std sugar)`

**Wrong:**
```scheme
(defn f [x] (* x 2))
```

**Correct:**
```scheme
(def (f x) (* x 2))
```

_AVAILABLE in Jerboa via: (jerboa clojure), (jerboa prelude), (std prelude), (std sugar). Square brackets for params ARE supported (same as parens), but the macro is def not defn._

### `fn` → `lambda`

****ERROR**** · from Clojure · id: `clojure-fn`

**Wrong:**
```scheme
(fn [x] (* x 2))
```

**Correct:**
```scheme
(lambda (x) (* x 2))
```

_No fn in Jerboa prelude. Use lambda._

### `(lambda args body)  ;; args as single symbol` → `(lambda args body) OR (lambda (x . rest) body)`

**warning** · from standard Scheme · id: `racket-lambda-rest`

**Wrong:**
```scheme
(lambda args (length args))  ;; works but unusual
```

**Correct:**
```scheme
(lambda args (length args))  ;; variadic
(lambda (first . rest) body)  ;; one required + rest
```

_Both forms are valid standard Scheme. Mentioning for completeness; LLMs sometimes mix them up._


## control

### `progn` → `begin`

****ERROR**** · from Common Lisp, Emacs Lisp · id: `cl-progn`

**Wrong:**
```scheme
(progn e1 e2 e3)
```

**Correct:**
```scheme
(begin e1 e2 e3)
```

### `chain` → `->`

**warning** · from Gerbil · id: `gerbil-chain`

**Available in Jerboa via:** `(jerboa clojure)`, `(jerboa prelude clean)`, `(jerboa prelude safe)`, `(jerboa prelude)`, `(std gambit-compat)`, `(std prelude)`, `(std sugar)`

**Wrong:**
```scheme
(chain x f g h)
```

**Correct:**
```scheme
(-> x (f) (g) (h))
```

_Jerboa uses -> and ->> for threading. chain is not the Jerboa idiom but may be aliased._

### `when-not` → `unless`

****ERROR**** · from Clojure · id: `hallucinated-when-not`

**Wrong:**
```scheme
(when-not x body)
```

**Correct:**
```scheme
(unless x body)
```


## mutation

### `setq` → `set!`

****ERROR**** · from Common Lisp · id: `cl-setq`

**Wrong:**
```scheme
(setq x 10)
```

**Correct:**
```scheme
(set! x 10)
```


## iterators

### `(for/list ((x lst)) body)` → `for/collect`

****ERROR**** · from Racket · id: `racket-for-list`

**Wrong:**
```scheme
(for/list ((x '(1 2 3))) (* x x))
```

**Correct:**
```scheme
(for/collect ((x '(1 2 3))) (* x x))  ;; → (1 4 9)
```

_Jerboa names its collecting for-comprehension for/collect. Other Racket for/X forms (for/fold, for/or, for/and) do exist._

### `(for/vector ...)` → `(list->vector (for/collect ...))`

****ERROR**** · from Racket · id: `racket-for-vector`

**Wrong:**
```scheme
(for/vector ((x lst)) (* x x))
```

**Correct:**
```scheme
(list->vector (for/collect ((x '(1 2 3))) (* x x)))
```

_No for/vector in Jerboa prelude. Collect to list then convert._


## parameters

### `parameterize works as in Racket` → `parameterize with parens`

**warning** · from Racket · id: `racket-parameterize`

**Wrong:**
```scheme
(parameterize ([p v]) body)
```

**Correct:**
```scheme
(parameterize ((p v)) body)  ;; both parens/brackets ok
```

_parameterize works in Chez. Brackets and parens are interchangeable._


## predicates

### `(null? x) for general 'empty'` → `null? only for '()`

**warning** · from standard Scheme · id: `srfi-1-null`

**Wrong:**
```scheme
(null? "")  ;; #f, not the emptiness test for strings
```

**Correct:**
```scheme
(null? '())      ;; #t
(string-empty? "")  ;; #t
(= 0 (vector-length v))  ;; empty vector
```

_null? tests for the empty list only. Use type-specific predicates._


## values

### `nil` → `#f or '()`

****ERROR**** · from Clojure, Common Lisp · id: `clojure-nil`

**Wrong:**
```scheme
(if (= x nil) ...)
```

**Correct:**
```scheme
(if (not x) ...)  ;; #f-tested
(if (null? lst) ...)  ;; empty-list-tested
```

_Scheme distinguishes #f (false) from '() (empty list). There is no unified nil._

### `true, false` → `#t / #f`

****ERROR**** · from Clojure, JavaScript · id: `clojure-true-false`

**Wrong:**
```scheme
(if flag true false)
```

**Correct:**
```scheme
(if flag #t #f)
```

### `True, False` → `#t / #f`

****ERROR**** · from Python · id: `python-true-false-caps`

**Wrong:**
```scheme
(if x True False)
```

**Correct:**
```scheme
(if x #t #f)
```

### `None, Null` → `#f or void`

****ERROR**** · from Python, SQL · id: `python-none`

**Wrong:**
```scheme
(if (= x None) ...)
```

**Correct:**
```scheme
(if (not x) ...)  ;; #f-test
(if (eq? x (void)) ...)  ;; void-test
```


## methods

### `(defmethod {method obj} body)` → `(defmethod (method (self type)) body)`

****ERROR**** · from Gerbil · id: `gerbil-defmethod-signature`

**Wrong:**
```scheme
(defmethod {area shape} (* 3 3))
```

**Correct:**
```scheme
(defmethod (area (self circle)) (* 3.14 (circle-radius self) (circle-radius self)))
```

_Jerboa defmethod uses typed-arg form. Call with {method obj args} or (~ obj 'method args)._


## typing

### `(:: binding ...)` → `(: expr pred?)`

**warning** · from Gerbil · id: `gerbil-syntax-case-colon`

**Wrong:**
```scheme
(: foo : Number)
```

**Correct:**
```scheme
(: value number?)  ;; checked cast, raises if pred fails
```

_Jerboa's : is a runtime checked cast with a predicate, not a type annotation._


## errors

### `(raise "message")` → `error`

****ERROR**** · from Common Lisp, r6rs-colloquial · id: `cl-raise-string`

**Wrong:**
```scheme
(raise "something went wrong")
```

**Correct:**
```scheme
(error 'who "something went wrong" irritants ...)
```

_raise takes a condition value, not a string. Use error to signal with a message and source. Raise works if you pass a condition object, e.g. (raise (make-error))._

### `condition/report-string` → `(with-output-to-string (lambda () (display-condition c)))`

****ERROR**** · from Gerbil · id: `gerbil-condition-report-string`

**Wrong:**
```scheme
(condition/report-string c)
```

**Correct:**
```scheme
(with-output-to-string (lambda () (display-condition c)))
```

_Chez formats conditions via display-condition; capture with with-output-to-string._

### `with-exception-catcher` → `try/catch`

**compat (works via specific import)** · from Gambit · id: `gerbil-with-exception-handler`

**Available in Jerboa via:** `(jerboa core)`, `(std gambit-compat)`

**Wrong:**
```scheme
(with-exception-catcher handler thunk)
```

**Correct:**
```scheme
(try (thunk-body) (catch (e) (handler e)))
```

_AVAILABLE in Jerboa via: (jerboa core), (std gambit-compat). Jerboa's try/catch is the idiomatic form. guard and with-exception-handler (R6RS) also work._

### `error-object?` → `condition?`

****ERROR**** · from R7RS · id: `r7rs-error-object`

**Wrong:**
```scheme
(error-object? e)
```

**Correct:**
```scheme
(condition? e)
```

_Chez uses the R6RS condition system. condition?, message-condition?, irritants-condition?, etc._

### `error-object-irritants` → `condition-irritants`

****ERROR**** · from R7RS · id: `r7rs-error-irritants-accessor`

**Wrong:**
```scheme
(error-object-irritants e)
```

**Correct:**
```scheme
(condition-irritants e)  ;; or &irritants
```

### `error-object-message` → `condition-message`

****ERROR**** · from R7RS · id: `r7rs-error-message-accessor`

**Wrong:**
```scheme
(error-object-message e)
```

**Correct:**
```scheme
(condition-message e)
```


## concurrency

### `thread-sleep!` → `sleep`

**compat (works via specific import)** · from Gambit, Gerbil · id: `gambit-thread-sleep`

**Available in Jerboa via:** `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)`

**Wrong:**
```scheme
(thread-sleep! 1.5)
```

**Correct:**
```scheme
(sleep (make-time 'time-duration 500000000 1))
```

_AVAILABLE in Jerboa via: (jerboa core), (std gambit-compat), (std misc thread). Chez sleep takes a time-duration object: (make-time 'time-duration NANOSECONDS SECONDS). For fractional secs, use the nanosecond field._

### `thread-yield!` → `(sleep (make-time 'time-duration 0 0))`

**compat (works via specific import)** · from Gambit · id: `gambit-thread-yield`

**Available in Jerboa via:** `(jerboa core)`, `(std gambit-compat)`, `(std misc thread)`

**Wrong:**
```scheme
(thread-yield!)
```

**Correct:**
```scheme
(sleep (make-time 'time-duration 0 0))
```

_AVAILABLE in Jerboa via: (jerboa core), (std gambit-compat), (std misc thread). Chez has no thread-yield. sleep with zero duration is the closest equivalent (yields to scheduler)._

### `with-semaphore` → `(std misc thread) primitives`

**warning** · from Gerbil · id: `gerbil-with-semaphore`

**Wrong:**
```scheme
(with-semaphore sem body)
```

**Correct:**
```scheme
(import (std misc thread))
(import (std misc thread))
(with-lock lock body)
```

_Check (std misc thread) for current lock primitives._

### `(spawn thunk)` → `make-thread + thread-start!`

****ERROR**** · from Gambit · id: `gambit-spawn`

**Wrong:**
```scheme
(spawn (lambda () ...))
```

**Correct:**
```scheme
(import (std misc thread))
(import (std misc thread))
(thread-start! (make-thread (lambda () ...)))
```

### `make-channel, channel-put, channel-get` → `(std concur) or (std csp)`

**warning** · from Gerbil · id: `gerbil-channel`

**Wrong:**
```scheme
(def ch (make-channel))
```

**Correct:**
```scheme
(import (std concur))
(import (std concur))
;; check std concur for current channel API
```

_Jerboa has (std concur), (std csp), (std actor) — pick based on your model._


## process

### `process-status` → `(std misc process) API`

**compat (works via specific import)** · from Gerbil · id: `gerbil-process-status`

**Available in Jerboa via:** `(jerboa core)`, `(std gambit-compat)`, `(std os fd)`

**Wrong:**
```scheme
(process-status proc)
```

**Correct:**
```scheme
(import (std misc process))
(import (std misc process))
(run-process ["ls"])  ;; returns status+output
```

_AVAILABLE in Jerboa via: (jerboa core), (std gambit-compat), (std os fd). Gerbil's process model does not map directly. Use run-process from (std misc process)._


## io

### `(read-line port)` → `read-line`

**aliased (works in prelude)** · from Gambit · id: `gambit-read-line`

**Wrong:**
```scheme
(read-line (current-input-port))
```

**Correct:**
```scheme
(read-line)  ;; or (read-line port)
```

_read-line is aliased as a wrapper over get-line that also works with no args (reads current-input-port)._

### `force-output` → `flush-output-port`

**aliased (works in prelude)** · from Gambit · id: `gambit-force-output`

**Available in Jerboa via:** `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude)`, `(std gambit-compat)`

**Wrong:**
```scheme
(force-output)
```

**Correct:**
```scheme
(flush-output-port)  ;; or with port arg
```

_force-output is aliased to a flush-output-port wrapper that accepts 0 or 1 args._

### `open-fd-pair` → `(std os fd) pipe API`

****ERROR**** · from Gambit · id: `gambit-open-fd-pair`

**Wrong:**
```scheme
(open-fd-pair)
```

**Correct:**
```scheme
(import (std os fd))
(import (std os fd))
(make-pipe)  ;; check actual API
```

_No direct equivalent; use pipe operations from (std os fd) or run-process with piped stdin/stdout._

### `(displayln x port)` → `(displayln x)`

**warning** · from Racket · id: `racket-displayln-newline`

**Wrong:**
```scheme
(displayln "hi" (current-output-port))
```

**Correct:**
```scheme
(displayln "hi")  ;; uses current-output-port
```

_Jerboa's displayln accepts multiple values to display on one line: (displayln "a" " " "b"). Port arg is NOT the same as Racket's._

### `(pp obj port)` → `pp (1-arg)`

**warning** · from Gambit · id: `gambit-pp`

**Wrong:**
```scheme
(pp form (current-output-port))
```

**Correct:**
```scheme
(pp form)  ;; writes to current-output-port
```

_Chez's pp takes 1 arg. Use (pp-to-string form) for string form._

### `(newline)` → `displayln`

**warning** · from standard Scheme · id: `sicp-newline-paren`

**Wrong:**
```scheme
(display "x") (newline)
```

**Correct:**
```scheme
(displayln "x")
```

_(newline) works; displayln is the Jerboa idiom and accepts multiple values._

### `(read-string k port)` → `get-string-n`

****ERROR**** · from R7RS · id: `r7rs-read-string`

**Wrong:**
```scheme
(read-string 100 port)
```

**Correct:**
```scheme
(get-string-n port 100)  ;; R6RS: port first, count second
```

_Chez/R6RS uses get-string-n with port first._

### `(write-string s port)` → `put-string`

****ERROR**** · from R7RS · id: `r7rs-write-string`

**Wrong:**
```scheme
(write-string "hi" port)
```

**Correct:**
```scheme
(put-string port "hi")  ;; R6RS: port first
```

### `with-destination, with-input-from-string defaults` → `with-output-to-string`

**warning** · from Gerbil · id: `gerbil-with-destination`

**Wrong:**
```scheme
(with-destination #f body)
```

**Correct:**
```scheme
(with-output-to-string (lambda () body))
```

_Jerboa uses with-output-to-string / with-input-from-string from the prelude._

### `(print x)` → `display / displayln`

****ERROR**** · from Python, Ruby · id: `hallucinated-print`

**Wrong:**
```scheme
(print "hello")
```

**Correct:**
```scheme
(displayln "hello")
```

### `(println x)` → `displayln`

****ERROR**** · from Java, Clojure, Rust · id: `hallucinated-println`

**Wrong:**
```scheme
(println "hello")
```

**Correct:**
```scheme
(displayln "hello")
```

### `make-custom-binary-input-port (R6RS)` → `this works in Chez`

**warning** · from R6RS · id: `r6rs-make-custom-binary-port`

**Wrong:**
```scheme
(make-custom-binary-input-port ...)
```

**Correct:**
```scheme
(make-custom-binary-input-port id read! get-position set-position! close)
```

_R6RS custom ports work in Chez. Included as reassurance._


## formatting

### `(format "~v" x)  ;; Racket-specific directives` → `~a ~s ~d ~%`

****ERROR**** · from Racket · id: `racket-format-tilde`

**Wrong:**
```scheme
(format "~v is ~s" x y)
```

**Correct:**
```scheme
(format "~a is ~s" x y)  ;; ~a=display ~s=write ~%=newline
```

_Chez format uses Common Lisp directives: ~a, ~s, ~d, ~x, ~%, ~~. No ~v. _

### `(printf "...~n" ...)` → `(printf "...~%" ...)`

****ERROR**** · from Gerbil, Racket · id: `gerbil-printf-newline`

**Wrong:**
```scheme
(printf "hi~n")
```

**Correct:**
```scheme
(printf "hi~%")
```

_Chez uses ~% for newline. ~n is Racket/Gerbil._

### `format returns to stdout` → `format returns a string`

****ERROR**** · from Racket · id: `racket-format-shadowed`

**Wrong:**
```scheme
(format "hi ~a" name)  ;; expected to print
```

**Correct:**
```scheme
(displayln (format "hi ~a" name))
```

_format RETURNS a string. Wrap in displayln/display/printf to output._


## filesystem

### `directory-exists?` → `file-directory?`

**aliased (works in prelude)** · from Gambit · id: `gambit-directory-exists`

**Available in Jerboa via:** `(jerboa clojure)`, `(jerboa prelude)`, `(std os path-util)`

**Wrong:**
```scheme
(directory-exists? "/tmp")
```

**Correct:**
```scheme
(file-directory? "/tmp")
```

_directory-exists? is aliased to file-directory? in the prelude._

### `(path-expand relative base)` → `path-join`

****ERROR**** · from Gerbil · id: `gerbil-path-expand-2arg`

**Wrong:**
```scheme
(path-expand "foo.txt" "/home/user")
```

**Correct:**
```scheme
(path-join "/home/user" "foo.txt")
```

_Gerbil's path-expand is 2-arg; Jerboa's path-expand is 1-arg (~ expansion only). Use path-join for composition._


## environment

### `user-info-home` → `(getenv "HOME")`

**compat (works via specific import)** · from Gerbil · id: `gerbil-user-info-home`

**Available in Jerboa via:** `(jerboa core)`, `(std gambit-compat)`

**Wrong:**
```scheme
(user-info-home)
```

**Correct:**
```scheme
(getenv "HOME")
```

_AVAILABLE in Jerboa via: (jerboa core), (std gambit-compat). Jerboa/Chez has no user-info record. Read $HOME directly._


## modules

### `(library (name) (export ...) (import ...) body ...)` → `plain .ss program`

****ERROR**** · from R6RS · id: `r6rs-library-form`

**Wrong:**
```scheme
(library (my-lib) (export f) (import (rnrs)) (define (f x) x))
```

**Correct:**
```scheme
(import (jerboa prelude))
(def (f x) x)
```

_User-facing .ss files are programs, not libraries. Internal .sls files use (library ...) but you should not write those._

### `:std/sort` → `(std sort)`

**warning** · from Gerbil · id: `gerbil-module-path`

**Wrong:**
```scheme
(import :std/sort :std/text/json)
```

**Correct:**
```scheme
(import (std sort) (std text json))
```

_Both forms work — the reader supports Gerbil-style :std/path as sugar for (std path). The (std ...) form is canonical and preferred._

### `(provide name ...)` → `N/A for .ss programs`

****ERROR**** · from Racket · id: `racket-provide`

**Wrong:**
```scheme
(provide foo bar)
```

**Correct:**
```scheme
; .ss programs don't export. For a library, edit the .sls in lib/.
```

_User .ss files are programs. Libraries live in .sls files (internal)._

### `(require module)` → `import`

****ERROR**** · from Racket · id: `racket-require`

**Wrong:**
```scheme
(require racket/list)
```

**Correct:**
```scheme
(import (std misc list))
```

### `import renaming works as R7RS` → `(rename (only (mod) x) (x y))`

**warning** · from R7RS · id: `r7rs-import-only-except`

**Wrong:**
```scheme
(import (rename (foo) (old new)))
```

**Correct:**
```scheme
(import (only (chezscheme) getenv) (rename (only (chezscheme) getenv) (getenv %chez-getenv)))
```

_R6RS-style only/except/rename/prefix all work in Chez._


## regex

### `pregexp-match` → `re-search`

**compat (works via specific import)** · from Racket · id: `racket-pregexp-match`

**Available in Jerboa via:** `(std pregexp)`

**Wrong:**
```scheme
(pregexp-match "\\d+" s)
```

**Correct:**
```scheme
(re-search (re "\\d+") s)
```

_AVAILABLE in Jerboa via: (std pregexp). Jerboa's regex uses a unified API: re to compile, re-search/re-match?/re-find-all/re-replace. In prelude._

### `regexp-match` → `re-search`

****ERROR**** · from Racket · id: `racket-regexp-match`

**Wrong:**
```scheme
(regexp-match #px"\\d+" s)
```

**Correct:**
```scheme
(re-search (re "\\d+") s)
```


## numerics

### `random-integer` → `random`

**aliased (works in prelude)** · from Gambit · id: `gambit-random-integer`

**Available in Jerboa via:** `(jerboa clojure)`, `(jerboa core)`, `(jerboa prelude)`, `(std gambit-compat)`

**Wrong:**
```scheme
(random-integer 100)
```

**Correct:**
```scheme
(random 100)
```

_random-integer is aliased to random in the prelude._

### `number->string with radix as keyword` → `(number->string n radix)`

****ERROR**** · from Racket · id: `racket-number-string`

**Wrong:**
```scheme
(number->string 255 #:base 16)
```

**Correct:**
```scheme
(number->string 255 16)  ;; "ff"
```

_Chez uses positional radix arg (2/8/10/16)._


## bitwise

### `arithmetic-shift` → `bitwise-arithmetic-shift`

**compat (works via specific import)** · from Racket, R6RS · id: `racket-arithmetic-shift`

**Available in Jerboa via:** `(jerboa core)`, `(std gambit-compat)`, `(std srfi srfi-151)`

**Wrong:**
```scheme
(arithmetic-shift n 3)
```

**Correct:**
```scheme
(bitwise-arithmetic-shift n 3)  ;; or (ash n 3)
```

_AVAILABLE in Jerboa via: (jerboa core), (std gambit-compat), (std srfi srfi-151). Chez has bitwise-arithmetic-shift and a short alias ash. arithmetic-shift is not bound._

### `bitwise-and, bitwise-or, bitwise-xor` → `these work`

**warning** · from R6RS · id: `r6rs-bitwise`

**Wrong:**
```scheme
(bitwise-and 0xff x)
```

**Correct:**
```scheme
(bitwise-and #xff x)  ;; Chez uses #x not 0x for hex
```

_Functions exist. Watch for #x vs 0x hex literal syntax (Chez uses #x)._


## bytevectors

### `make-u8vector, u8vector-ref, etc.` → `bytevector`

**warning** · from Gambit · id: `gambit-u8vector`

**Wrong:**
```scheme
(make-u8vector 10 0)
```

**Correct:**
```scheme
(make-bytevector 10 0)
```

_Chez uses bytevectors (R6RS). For Gambit compat, (import (std gambit-compat)) provides u8vector aliases._

### `(bytevector-copy bv start end)` → `(subbytes bv start end) or slice`

****ERROR**** · from R6RS · id: `r6rs-bytevector-copy-3arg`

**Wrong:**
```scheme
(bytevector-copy bv 0 10)
```

**Correct:**
```scheme
(bytevector-copy bv)  ;; full copy
;; for range:
(define sub (make-bytevector (- end start)))
(bytevector-copy! bv start sub 0 (- end start))
```

_R6RS bytevector-copy is 1-arg. For subrange, use the 5-arg bytevector-copy! with a fresh destination._


## vectors

### `(make-vector n) initialized to specific default` → `(make-vector n fill)`

**warning** · from standard Scheme · id: `gambit-make-vector-init`

**Wrong:**
```scheme
(make-vector 10)  ;; contents unspecified
```

**Correct:**
```scheme
(make-vector 10 0)
```

_Without fill arg, initial contents are unspecified in standard Scheme. Always provide a fill if you care._


## symbols

### `symbol<?` → `(lambda (a b) (string<? (symbol->string a) (symbol->string b)))`

****ERROR**** · from Gerbil, SRFI-1 · id: `gerbil-symbol-lt`

**Wrong:**
```scheme
(sort symbol<? '(b a c))
```

**Correct:**
```scheme
(sort (lambda (a b) (string<? (symbol->string a) (symbol->string b))) '(b a c))
```

_No symbol<? in Jerboa/Chez. Compare via symbol->string + string<?._


## equality

### `eql?` → `eqv?`

**aliased (works in prelude)** · from Common Lisp · id: `cl-eql-predicate`

**Available in Jerboa via:** `(jerboa clojure)`, `(jerboa prelude)`

**Wrong:**
```scheme
(eql? 1 1.0)
```

**Correct:**
```scheme
(eqv? 1 1.0)
```

_eql? is aliased to eqv? in the prelude._


## meta

### `environment-bound?` → `(try (eval 'foo (interaction-environment)) (catch (e) #f))`

****ERROR**** · from Gerbil · id: `gerbil-environment-bound`

**Wrong:**
```scheme
(environment-bound? 'foo)
```

**Correct:**
```scheme
(try (begin (eval 'foo (interaction-environment)) #t) (catch (e) #f))
```

_No direct Chez equivalent. Probe via eval + catch for undefined-variable._

### `(the-environment)` → `(interaction-environment)`

****ERROR**** · from Gerbil · id: `gerbil-the-environment`

**Wrong:**
```scheme
(eval expr (the-environment))
```

**Correct:**
```scheme
(eval expr (interaction-environment))
```

_Chez uses interaction-environment for the top-level dynamic environment._


## time

### `time->seconds` → `time-second`

**compat (works via specific import)** · from Gambit, Gerbil · id: `gambit-time-to-seconds`

**Available in Jerboa via:** `(jerboa core)`, `(std gambit-compat)`, `(std srfi srfi-19)`

**Wrong:**
```scheme
(time->seconds (current-time))
```

**Correct:**
```scheme
(time-second (current-time))
```

_AVAILABLE in Jerboa via: (jerboa core), (std gambit-compat), (std srfi srfi-19). Use (time-second t) for epoch seconds, (time-nanosecond t) for sub-second part._


## literals

### `0xff hex literal` → `#xff`

****ERROR**** · from C, JavaScript · id: `js-0x-hex`

**Wrong:**
```scheme
(* 0xff 2)
```

**Correct:**
```scheme
(* #xff 2)  ;; 510
```

_Scheme hex literals use #x prefix. Also #b for binary, #o for octal._


## reader-syntax

### `#hash((k . v) ...)` → `(list->hash-table '((k . v) ...))`

****ERROR**** · from Racket · id: `racket-hash-literal`

**Wrong:**
```scheme
#hash(("a" . 1) ("b" . 2))
```

**Correct:**
```scheme
(list->hash-table '(("a" . 1) ("b" . 2)))
```

_No #hash reader literal in Chez. Use (hash-table) constructor or list->hash-table._

### `#lang racket` → `(import (jerboa prelude))`

****ERROR**** · from Racket · id: `racket-lang-header`

**Wrong:**
```scheme
#lang racket
(define x 1)
```

**Correct:**
```scheme
(import (jerboa prelude))
(def x 1)
```

_Jerboa .ss files are plain scheme programs. First form is typically (import ...). Do not write #lang._


## logging

### `log-debug, log-info via (gerbil/std/logger)` → `(std logger) in Jerboa`

**warning** · from Gerbil · id: `gerbil-logger`

**Wrong:**
```scheme
(log-info "starting")
```

**Correct:**
```scheme
(import (std logger))
(import (std logger))
;; check (std logger) for current API
```


## internals

### `##prefixed internals` → `public operator`

****ERROR**** · from Gambit · id: `gambit-host`

**Wrong:**
```scheme
(##fx+ 1 2)
```

**Correct:**
```scheme
(+ 1 2)  ;; or (fx+ 1 2) if importing (chezscheme) fixnum ops
```

_## is Gambit's namespace for unsafe/internal ops. Chez uses fx+/fx-/fx* via (chezscheme) for fixnum specifics._
