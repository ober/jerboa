# AI Review Session — 2026-04-04

Late-night session using Gemini Pro 3.1 (via OpenCode) and GPT-5.4 to review
Jerboa for AI-friendliness. The session produced analysis, identified the
bracket reader bug, and led to commit `027e9f6` which fixed `[]` to be plain
parentheses (matching Gerbil/Chez).

**Models used:** GPT-5.4 (OpenCode, first pass), Gemini 3.1 Preview (deeper analysis)
**Cost:** ~$60
**Key outcome:** Bracket reader fix — `[...]` no longer becomes `(list ...)`.

---

## Table of Contents

1. [The Bracket Problem](#1-the-bracket-problem)
2. [The Fix](#2-the-fix)
3. [GPT-5.4 Recommendations](#3-gpt-54-recommendations)
4. [Gemini 3.1 Recommendations](#4-gemini-31-recommendations)
5. [Gemini: Making Jerboa Premier for AI](#5-gemini-making-jerboa-premier-for-ai)
6. [Gemini's Review of GPT-5.4's Recommendations](#6-geminis-review-of-gpt-54s-recommendations)

---

## 1. The Bracket Problem

The `[]` reader translation was the **#1 syntax footgun** for LLMs writing
Jerboa code, causing a specific, frustrating failure loop.

### The "Racket/Clojure Muscle Memory"

LLMs are trained on massive corpuses of GitHub code. In the Lisp/Scheme world,
the vast majority of modern code (especially Racket and Clojure) uses square
brackets for bindings. An LLM is statistically hardwired to write:

```scheme
;; What an LLM naturally wants to write:
(let ([x 1] [y 2]) (+ x y))
(for/collect ([i (in-range 10)]) (* i i))
```

### The Translation Trap

Because Jerboa's reader translated `[...]` into `(list ...)` at read-time, the
LLM's perfectly normal-looking code was actually fed to Chez Scheme as:

```scheme
;; What Chez Scheme actually saw:
(let (list x 1) (list y 2))  ;; → crash
(for/collect (list i (in-range 10)) (* i i))  ;; → crash
```

### The "Cryptic Error" Death Loop

When Chez sees `(let (list x 1) ...)`, it throws a generic
`Exception: malformed let expression`. The AI looks at `(let ([x 1] [y 2])
(+ x y))` and sees perfectly valid Scheme. It tries changing `let` to `let*`,
wrapping in `begin`, anything — but keeps using brackets, failing over and over.

### The Gerbil Syntax Divergence

Gerbil itself treats `[]` identically to `()`. From
`src/lang/gerbil/polydactyl.ss`:

> This is :gerbil/core with a readtable that treats [] as plain parentheses.

So the bracket footgun wasn't just "Racket/Clojure bias" — it was a **direct
syntax divergence from Gerbil itself**, the language Jerboa is supposed to be
compatible with.

### The Genesis Error

The most telling part: the original `gerbil-like.md` design document explicitly
defined `[1 2 3]` → `(list 1 2 3)`, then less than 100 lines later used
brackets for `let` bindings in its own macro examples:

```scheme
→ (let ([tmp expr])
    (cond
      [(and (pair? tmp) ...)
       (let ([a (car tmp)] [b (cadr tmp)]) body1)]
      [else body3]))
```

If the language architect couldn't follow the rule, no LLM stands a chance.

---

## 2. The Fix

**Status: FIXED** in commit `027e9f6` ("cleanup []").

The fix was a one-line change in `lib/jerboa/reader.sls` — instead of wrapping
bracket contents in `(list ...)`, just treat them as plain parentheses:

```scheme
;; Before (broken):
((char=? ch #\[)
 (reader-next! rs)
 (let ((items (read-list rs #\] (+ depth 1))))
   (annotate rs (cons 'list items) loc)))

;; After (fixed):
((char=? ch #\[)
 (reader-next! rs)
 (annotate rs (read-list rs #\] (+ depth 1)) loc))
```

This restores Gerbil/Chez compatibility and eliminates the #1 AI footgun.

---

## 3. GPT-5.4 Recommendations

### Priority Order

**P0 — Immediate:**
- Make safe prelude the default in first-touch docs
- Fix sandbox memory-limit gap (`setrlimit(RLIMIT_AS)`)
- Fix sandbox temp-file race
- Resolve safe-prelude overlapping export warning

**P1 — Next:**
- Add `docs/ai-starter.md` (canonical AI-safe starter template)
- Add `docs/ai-pitfalls.md` ("What AI will get wrong" page)
- Add AI-strict lint profile
- Add machine-readable prelude manifests

**P2 — Soon after:**
- Add strict safe application templates (CLI, HTTP service, worker, library)
- Add capability manifests for modules
- Improve error explanation tooling
- Generate a live implemented-module matrix

**P3 — Longer-term:**
- Optional compatibility normalization for common AI syntax mistakes
- Stronger project-policy enforcement
- Formatter / canonicalizer for user-facing `.ss` source

### Key Recommendations

1. **Make `(jerboa prelude safe)` the default** in README, JERBOA-LANG.md,
   quickstart. Currently these all lead with `(jerboa prelude)`.

2. **Machine-readable API manifest** (`docs/api/prelude.json`) — exported
   names, arities, safety level, module source, preferred replacements.

3. **AI-strict lint profile** catching: `(import (chezscheme))` in app code,
   raw FFI, Gerbil hallucinations, wrong `sort` order, unsafe string-built SQL.

4. **"Do this / Not that" table** in README:

   | Use this | Not this | Why |
   |---|---|---|
   | `(import (jerboa prelude safe))` | `(import (chezscheme))` | safer default |
   | `(with-task-scope ...)` | `(fork-thread ...)` | structured concurrency |
   | `(sqlite-query db "...?" arg)` | string-built SQL | injection prevention |
   | `((list-of? number?) xs)` | `(list-of? number? xs)` | correct arity |

5. **Fix remaining sandbox gaps** — no memory limit in child, temp-file race,
   overlapping-symbol warning in safe prelude.

---

## 4. Gemini 3.1 Recommendations

### Key Findings

1. **Statistical Syntactic Bias** — The `[...]` → `(list ...)` mapping fought
   against massive Racket/Clojure training data. *(Now fixed.)*

2. **Context Window Anchoring** — README and JERBOA-LANG.md prioritize unsafe
   `(jerboa prelude)` instead of `(jerboa prelude safe)`, causing LLMs to
   default to the wrong path.

3. **Opaque Error Boundaries** — Generic Chez errors for missing Gerbil/Gambit
   functions slow agentic self-correction. Enhanced error mapping needed.

4. **RAG Optimization** — Scattered docs (libraries.md, import-conflicts.md,
   gaps.md) are hard for RAG pipelines. A consolidated `jerboa-llm-context.txt`
   containing all modules, syntax rules, arity rules, and API signatures would
   drastically reduce hallucination.

5. **Execution Sandboxing** — `setrlimit(RLIMIT_AS)` gap is critical; AI code
   frequently causes accidental memory bloat via runaway `for/collect` loops.

---

## 5. Gemini: Making Jerboa Premier for AI

### Hallucination Friction

- **AI-Compat Layer:** Alias common hallucinations where harmless:
  `hash-has-key?` → `hash-key?`, `directory-exists?` → `file-directory?`,
  `eql?` → `eqv?`. Eliminates ~20% of AI-generated bugs.

- **Smarter Macro Errors:** Update `let`, `for`, `match` macros to detect
  `(list var val)` in binding position and throw a specific error about
  brackets. *(Less critical now that brackets are fixed.)*

### MCP Improvements

- **Auto-correction in `jerboa_verify`:** Identify hallucinated functions and
  suggest exact replacements in MCP responses. *(Partially implemented in
  `shared-hallucinations.ts`.)*

- **Semantic "Find Similar" tool:** Levenshtein/vector search over stdlib.

### LSP Improvements

- **"Did you mean?" diagnostics:** Embed hallucination dictionary in LSP.
  *(Implemented in commit `f9a1c6e`.)*

- **Bracket-to-paren QuickFix:** LSP code action to rewrite brackets.
  *(Implemented in commit `f9a1c6e`.)*

### Language Ergonomics

- **Type hinting:** Expand `(: expr pred?)` to function signature hints for
  LSP validation. *(Already exists: `(def (f (x : integer?)) ...)`)*

- **Unified prelude:** Make `(import (jerboa prelude))` inclusive of common
  modules (`std net request`, `std text regex`, etc.) so AIs don't forget
  imports. *(Attempted but reverted — too aggressive a design decision.)*

- **Machine-readable test output:** JSON-formatted error reports from
  `jerboa_run_tests`.

---

## 6. Gemini's Review of GPT-5.4's Recommendations

### What GPT Got Right
- "What AI will get wrong" page and "Do this / Not that" table are highest-leverage
- Machine-readable API manifest is genuinely good
- Priority ordering is reasonable
- AI-strict lint profile targets the right failure modes

### Where Gemini Pushed Back
- **Safe prelude as default** depends on audience — safe for apps, full for
  libraries/infrastructure
- **Capability manifests** are a big commitment for uncertain payoff; sandbox
  approach is more practical
- **Formatter** is underrated — should be higher priority than several "high" items
- **Missing topic:** GPT didn't mention MCP tooling at all — arguably Jerboa's
  strongest AI story

### What Gemini Would Add
- **Version the hallucination list** — make the "things that don't exist"
  section a first-class maintained document, not just embedded in CLAUDE.md
- **Fix error messages at the source** — if Chez says "incorrect number of
  arguments to sort", Jerboa should intercept and say "sort takes
  (sort predicate list), not (sort list predicate)"

### Gemini's Re-ranked Priority
1. "What AI will get wrong" page + "Do this / Not that" table (cheap, huge impact)
2. AI-strict lint profile (medium effort, catches most first-draft errors)
3. Better error messages at the source (medium effort, eliminates iteration loops)
4. Machine-readable API manifest (medium effort, helps all models)
5. Formatter (medium effort, underrated)
6. Safe prelude doc alignment (cheap, audience-dependent framing)

---

## What Was Implemented

From this session, the following changes were actually made:

### Committed (kept)
- **Bracket reader fix** (`027e9f6`) — `[]` now plain parens
- **Hallucination hints** in jerboa-mcp (`c687708`, `4876bfc`) — auto-suggests
  correct functions when LLMs use Gerbil/Racket names
- **LSP "Did you mean?" diagnostics** + bracket QuickFix (`f9a1c6e`)
- **Documentation updates** across jerboa, jerboa-mcp for bracket semantics

### Reverted (broken/wrong)
- `lib/jerboa/core.sls` — broke type predicate, unsafe macro changes
- `lib/jerboa/prelude.sls` — bulk-imported 6 modules without review
- `lib/std/os/path.sls` — silent semantic change
- jerboa-mcp `package.json` — orphaned md5 dependency
- jerboa-mcp `project-template.ts` — contained wrong bracket info
