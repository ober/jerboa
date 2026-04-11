# Clojure Reader Literals in Jerboa

This document elaborates on §4.9 of [`clojure-remaining.md`](./clojure-remaining.md) — why Jerboa does not (yet) have Clojure's four reader literals, what the design options are, and why the item is marked "risky / could be deferred forever."

## What Clojure's reader literals buy you

Clojure has four reader-level shorthands that create data structures directly from source syntax, no constructor call:

| Clojure literal | Reads as | Equivalent call |
|---|---|---|
| `{:a 1 :b 2}` | persistent map | `(hash-map :a 1 :b 2)` |
| `#{:a :b :c}` | persistent set | `(hash-set :a :b :c)` |
| `[1 2 3]` | persistent vector | `(vector 1 2 3)` |
| `:foo` | keyword object | (none — keywords are only literals) |

They're "reader" features because the tokenizer turns `{a 1 b 2}` into a map value *before* macro expansion runs. `{}` isn't a function call — it's the data structure itself.

This matters for ergonomics because Clojure code is saturated with data literals: `(assoc m :name "Alice" :age 30)`, `(reduce-kv f {} xs)`, `(filter #{:admin :owner} roles)`. All of these compile to constructor calls in the workaround form, which feels heavier than they read in Clojure.

## Why Jerboa can't just alias them

Each of those characters is **already taken** by Jerboa's reader:

```scheme
[...]    ;; Gerbil/Chez-style alternative parentheses
         ;; (let ([x 1] [y 2]) ...)   ← used everywhere in the codebase

{method obj args}   ;; method dispatch sugar → (~ obj 'method args)
                    ;; e.g. {length s} → (~ s 'length)

name:    ;; trailing-colon keyword syntax → #:name
:std/sort ;; leading-colon module-path sugar → (std sort)
```

Look at any `.ss` file in the repo — `[x 1]` shows up in every `let`, `for`, `cond` clause, and `match` pattern. If `[...]` suddenly meant "persistent vector", every binding form in the entire codebase breaks silently.

Same for `{...}` — it's used for method dispatch, not just reserved. `{add stack 5}` is valid Jerboa today; in Clojure it would be a map literal with `add`, `stack`, `5` as alternating keys and values (which wouldn't even parse, odd arity).

So a straight alias is a non-starter. The question is whether you can get the Clojure ergonomics *some other way*.

## The design doc's proposal (§4.9)

The proposal is an **opt-in file-local reader directive**:

```scheme
#!clojure-reader
(import (std clojure))

(def user {:name "Alice" :age 30})          ;; → (hash-map :name "Alice" :age 30)
(def admins #{"alice" "bob"})               ;; → (hash-set "alice" "bob")
(def coords [1 2 3])                         ;; → (vec 1 2 3)
(def role :admin)                            ;; → 'admin (symbol)
```

The directive is the first token in the file. If present, the reader enters "Clojure literal mode" for the rest of that file only — `[...]` becomes vector construction instead of bracket parens, `{...}` becomes map construction instead of method dispatch, etc. Files without the directive are unchanged.

It's the same pattern as `#!chezscheme` / `#!r6rs` at the top of Chez files — a file-scoped reader switch.

## Why it's marked "risky"

Four reasons, roughly in order of severity:

1. **File-local state in a re-entrant reader.** `lib/jerboa/reader.sls` is hand-written and not obviously extensible. Adding file-scoped modes requires a dynamic parameter threaded through every reader production, and dynamic-wind discipline so nested reads (e.g. string ports) don't leak the mode out.

2. **Loss of `[...]` as bracket parens.** Even in opt-in files, the author loses the Gerbil convention that brackets are just prettier parens. They can't write `(let ([x 1]) ...)` any more; they have to pick one notation and stick to it. Porters often expect to mix freely.

3. **Debuggability.** `[x y]` means different things in different files. Error messages like "got vector expected list at line 5" won't tell you which reader mode was active; people will spend time hunting `#!clojure-reader` at the top of a file they didn't write.

4. **The ergonomics payoff may not justify the cost.** The design doc's last bullet:

   > **Could be deferred forever.** If we conclude the ergonomics cost isn't worth the reader complexity, skip it and document the constructor forms as the permanent Jerboa idiom.

## What you get today without it

Every structure has a constructor that reads nearly as cleanly:

```scheme
(import (std clojure))

;; Map — variadic key/value pairs
(def user (hash-map 'name "Alice" 'age 30))

;; Set — variadic args
(def admins (hash-set "alice" "bob"))

;; Vector — variadic args
(def coords (vec 1 2 3))

;; Keyword — trailing-colon reader syntax
(def role name:)                    ;; a real keyword object
;; Or use a symbol, which is what most Jerboa code does:
(def role 'admin)
```

And for access, all the polymorphic ops work uniformly (that's what §4.4–§4.10 were about):

```scheme
(get user 'name)           ;; → "Alice"
(contains? admins "alice") ;; → #t
(assoc user 'role 'admin)  ;; → new map with role added
```

So the "missing" part is purely syntactic weight at literal construction sites — not missing semantics.

## Recommendation

The polymorphic operation layer (landed in Phase E, §4.4–§4.10) is the 90% of what Clojure porters actually want. The literal-syntax layer is the last 10%, at a cost of reader surgery and permanent debuggability weirdness. The design doc itself hedges toward "deferred forever," and the current recommendation is to agree with that — unless there's a specific porting target where literal density is really hurting readability, the constructor forms are a fine permanent idiom.

If you *do* want to pursue it, the cleanest starting point isn't the full four-literal reader mode — it's adding just `:keyword` literal syntax as a reader extension (no conflict with module paths if it's behind the directive), then evaluating whether the rest is worth the `[...]` tradeoff. That's a few hours instead of a few days and tells you whether the approach is viable.

## See also

- [`clojure-remaining.md`](./clojure-remaining.md) — full design doc for the Clojure-compat campaign, including §4.9 where this item originates.
- `lib/jerboa/reader.sls` — the hand-written reader that would need to be modified.
- `lib/std/clojure.sls` — the `(std clojure)` module that provides the constructor forms (`hash-map`, `hash-set`, `vec`) used as workarounds today.
