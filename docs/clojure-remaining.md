# Clojure Features Remaining — Worth Having

Status: **2026-04-11** — All features landed.

## Tier 2 — High value, self-contained

| Feature | Status | Module |
|---------|--------|--------|
| **Lazy sequences** | [landed] | `(std lazy-seq)` |
| **Zippers** | [landed] | `(std zipper)` |
| **Property-based testing** | [landed] | `(std test check)` |
| **EDN with tagged literals** | [landed] | `(std text edn)` |
| **Specter-style paths** | [landed] | `(std specter)` |

## Tier 3 — Worth doing but bigger

| Feature | Status | Module |
|---------|--------|--------|
| **Delay/Future/Promise** | [landed] | `(std clojure)` — `delay`, `future`, `promise`, `deref`, `realized?` |
| **`for` clause extensions** | [landed] | `(std iter)` — `:when`, `:while`, `:let` in all `for` macros |
| **`clojure.set` relational ops** | [landed] | `(std clojure)` — `set-select`, `set-project`, `set-rename`, `set-index`, `set-join`, `map-invert` |
| **Component lifecycle** | [landed] | `(std component)` — `system-map`, `system-using`, `start`, `stop` |
| **STM** | [landed] | `(std stm)` — `make-ref`, `dosync`, `alter`, `ref-set`, `commute`, `ensure` |
