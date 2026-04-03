# Zig-Inspired Ideas for Jerboa

## 1. `errdefer` — Error-Path Cleanup ✅ IMPLEMENTED

**Library:** `(std errdefer)`

### Usage

```scheme
(import (std errdefer))

;; Basic form: cleanup runs only on error
(errdefer (delete-file tmp)
  (write-file tmp data)
  (rename-file tmp dest))   ;; on success, errdefer is cancelled

;; Multiple body forms
(errdefer* (cleanup-resource res)
  (setup-phase-1)
  (setup-phase-2)
  (final-result))

;; LIFO stacking with with-errdefer
(with-errdefer
  ([(release-resource-a)]
   [(release-resource-b)]
   [(release-resource-c)])
  ;; on error: c, b, a cleanup runs in reverse order
  (acquire-resources)
  (do-work))
```

### Exports

- `errdefer` — single cleanup, single/multiple body forms
- `errdefer*` — single cleanup, multiple body forms (cleaner syntax)
- `with-errdefer` — stack multiple cleanups with LIFO order on error

---

## 2. Exhaustive Variant Matching — `defvariant` ✅ IMPLEMENTED

**Library:** `(std variant)`

### Usage

```scheme
(import (std variant))

;; Define a closed sum type
(defvariant shape
  (circle radius)
  (rect width height)
  (triangle base height))

;; Generates:
;; - shape/circle, shape/rect, shape/triangle — constructors
;; - shape/circle?, shape/rect?, shape/triangle? — predicates
;; - shape/circle-radius, shape/rect-width, etc. — accessors
;; - shape? — variant-wide predicate
;; - shape/variants — '(circle rect triangle) — closed tag set

;; Exhaustive matching (error at expand time if incomplete)
(match-variant shape s
  [(circle r) (* 3.14159 r r)]
  [(rect w h) (* w h)]
  [(triangle b h) (* 0.5 b h)])

;; Non-exhaustive with explicit wildcard (suppresses check)
(match-variant shape s
  [(circle r) "it's a circle"]
  [_ "not a circle"])

;; Non-exhaustive with else
(match-variant shape s
  [(rect w h) #t]
  [else #f])
```

### Exports

- `defvariant` — define a closed sum type with multiple variants
- `match-variant` — exhaustive pattern matching with compile-time checking
- `variant-tags` — get the list of tag symbols for a variant type
- `variant?` — check if a value is any variant of the named type
- `*variant-registry*` — runtime registry (for advanced use)

### Design Notes

- Exhaustiveness checking happens at compile/expand time via a meta-phase registry
- Missing variants cause a `syntax-violation` at expansion
- Wildcard `_` or `else` suppresses exhaustiveness checking
- Zero-field variants are supported: `(defvariant option (some value) (none))`
- Multiple variant types can coexist independently

---

## Original Design Notes (Preserved for Reference)
