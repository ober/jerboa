# Implementation Plan: `jerbuild` — Gerbil-Style Source Module Compiler

## Overview

`jerbuild` is a build tool that transforms Gerbil-style `.ss` source files into R6RS `.sls` library files for Chez Scheme. This allows jerboa-emacs (and other projects) to write idiomatic Gerbil source while running on stock Chez Scheme.

**Input** (Gerbil-style `.ss`):
```scheme
(export (struct-out helm-source) helm-multi-match helm-filter-all)
(import :std/sugar :std/srfi/13 :jerboa-emacs/core)
(defstruct helm-source (name candidates actions fuzzy? volatile?))
(def (helm-multi-match pattern str) ...)
```

**Output** (R6RS `.sls`):
```scheme
#!chezscheme
(library (jerboa-emacs helm)
  (export make-helm-source helm-source? helm-source-name helm-source-name-set!
          helm-source-candidates helm-source-candidates-set!
          helm-source-actions helm-source-actions-set!
          helm-source-fuzzy? helm-source-fuzzy?-set!
          helm-source-volatile? helm-source-volatile?-set!
          helm-multi-match helm-filter-all)
  (import (except (chezscheme) make-hash-table hash-table? iota 1+ 1- sort sort!)
          (jerboa core)
          (jerboa runtime)
          (std sugar)
          (std srfi srfi-13)
          (jerboa-emacs core))
  (defstruct helm-source (name candidates actions fuzzy? volatile?))
  (def (helm-multi-match pattern str) ...))
```

---

## File Location

Create: `/home/jafourni/mine/jerboa/jerbuild.ss`

This is a **Chez Scheme script** (not a library), invoked as:
```bash
scheme --libdirs lib --script jerbuild.ss <src-dir> <lib-dir> [--force] [--verbose]
```

It uses `(jerboa core)`, `(jerboa runtime)`, and `(jerboa build)` for content hashing.

---

## Architecture

The script has these phases, executed in order:

1. **CLI argument parsing** — read src-dir, lib-dir, flags
2. **Discovery** — find all `.ss` files under src-dir recursively
3. **Change detection** — skip unchanged files (content hash comparison)
4. **For each changed file:**
   a. Read the `.ss` file as raw S-expressions
   b. Extract `(export ...)` and `(import ...)` forms
   c. Collect body forms (everything else)
   d. Parse defstruct declarations from body forms
   e. Expand `(struct-out X)` in exports using parsed defstruct info
   f. Handle `(export #t)` by collecting all top-level definition names
   g. Translate Gerbil import paths to R6RS library references
   h. Add the automatic `(except (chezscheme) ...)` exclusion
   i. Compute the library name from the file path
   j. Wrap everything in `(library ...)` form
   k. Write the `.sls` output file
5. **Report** — print summary of files processed

---

## Step-by-Step Implementation

### Step 1: Script Skeleton and CLI Parsing

```scheme
#!/usr/bin/env scheme-script
#!chezscheme

(import (chezscheme)
        (jerboa core)
        (jerboa runtime)
        (jerboa build))  ;; for compute-file-hash, module-changed?

;; --- CLI ---
(define *verbose* #f)
(define *force* #f)

(define (parse-args args)
  ;; args = (list of command-line arguments after script name)
  ;; Expected: <src-dir> <lib-dir> [--force] [--verbose]
  ;; Returns: (values src-dir lib-dir)
  (let loop ([args args] [positional '()])
    (cond
      [(null? args)
       (unless (= (length positional) 2)
         (error 'jerbuild "Usage: jerbuild <src-dir> <lib-dir> [--force] [--verbose]"))
       (let ([pos (reverse positional)])
         (values (car pos) (cadr pos)))]
      [(string=? (car args) "--force")
       (set! *force* #t)
       (loop (cdr args) positional)]
      [(string=? (car args) "--verbose")
       (set! *verbose* #t)
       (loop (cdr args) positional)]
      [else
       (loop (cdr args) (cons (car args) positional))])))

(define (log-verbose fmt . args)
  (when *verbose*
    (apply printf fmt args)
    (newline)))
```

**Key details:**
- Use `(command-line-arguments)` (Chez built-in) to get args
- Two positional args: `src-dir` and `lib-dir`
- `--force` rebuilds all files regardless of hash
- `--verbose` prints progress

### Step 2: File Discovery

```scheme
(define (discover-ss-files dir)
  ;; Recursively find all .ss files under dir.
  ;; Returns list of absolute paths.
  ;; Uses (directory-list dir) from Chez Scheme.
  ;; Filter: only files ending in ".ss"
  ;; Recurse into subdirectories.
  ;; Skip hidden directories (starting with ".")
  ...)
```

**Implementation notes:**
- Use Chez's `(directory-list path)` to list directory contents
- Use `(file-directory? path)` to check if entry is a directory
- Use `(file-regular? path)` to check if it's a regular file
- Filter for `.ss` extension using `(string-suffix? ".ss" filename)` — implement with substring comparison since Chez doesn't have string-suffix? built-in: `(let ([len (string-length s)]) (and (>= len 3) (string=? (substring s (- len 3) len) ".ss")))`
- Return absolute paths (use `(string-append dir "/" entry)`)

### Step 3: Path Computation — Source Path to Library Name

Given a source file path and the src-dir, compute the R6RS library name.

```scheme
(define (path->library-name src-dir file-path)
  ;; src-dir = "src/"
  ;; file-path = "src/jerboa-emacs/helm.ss"
  ;; Result: (jerboa-emacs helm)
  ;;
  ;; Steps:
  ;; 1. Strip src-dir prefix from file-path
  ;; 2. Strip ".ss" suffix
  ;; 3. Split by "/"
  ;; 4. Convert each part to a symbol
  ;;
  ;; Example: "jerboa-emacs/helm" → (jerboa-emacs helm)
  ...)
```

**Implementation notes:**
- Normalize both paths (ensure trailing `/` on src-dir)
- Strip the prefix: `(substring file-path (string-length src-dir) ...)`
- Strip `.ss`: `(substring relative 0 (- (string-length relative) 3))`
- Split by `/`: implement a simple `string-split` on `#\/`
- Convert to symbols: `(map string->symbol parts)`
- Return as a list: `'(jerboa-emacs helm)`

### Step 4: Output Path Computation

```scheme
(define (compute-output-path lib-dir library-name)
  ;; library-name = (jerboa-emacs helm)
  ;; lib-dir = "lib/"
  ;; Result: "lib/jerboa-emacs/helm.sls"
  ;;
  ;; Steps:
  ;; 1. Join library-name symbols with "/"
  ;; 2. Append ".sls"
  ;; 3. Prepend lib-dir
  ...)
```

**Implementation notes:**
- `(string-append lib-dir "/" (string-join (map symbol->string library-name) "/") ".sls")`
- Create intermediate directories with `(mkdir path)` if they don't exist — use `(unless (file-exists? dir) (mkdir dir))` for each path component

### Step 5: Reading and Parsing the Source File

```scheme
(define (read-source-file path)
  ;; Read all top-level S-expressions from a .ss file.
  ;; Returns a list of forms.
  ;; Ignores the ;;; -*- Gerbil -*- comment header (it's a comment, not read).
  ;; Also ignores (declare ...) forms (Gerbil compiler hints, not needed for Chez).
  (call-with-input-file path
    (lambda (port)
      (let loop ([forms '()])
        (let ([form (read port)])
          (if (eof-object? form)
            (reverse forms)
            (loop (cons form forms))))))))

(define (classify-forms forms)
  ;; Separate the list of forms into:
  ;;   export-forms: list of (export ...) forms (there may be multiple)
  ;;   import-forms: list of (import ...) forms (there may be multiple)
  ;;   body-forms:   everything else
  ;;
  ;; Returns: (values export-specs import-specs body-forms)
  ;; Where:
  ;;   export-specs = merged list of all export items from all (export ...) forms
  ;;   import-specs = merged list of all import items from all (import ...) forms
  ;;   body-forms = list of remaining forms in original order
  (let loop ([forms forms]
             [exports '()]
             [imports '()]
             [body '()])
    (cond
      [(null? forms)
       (values (reverse exports) (reverse imports) (reverse body))]
      [(and (pair? (car forms)) (eq? (caar forms) 'export))
       (loop (cdr forms) (append (reverse (cdar forms)) exports) imports body)]
      [(and (pair? (car forms)) (eq? (caar forms) 'import))
       (loop (cdr forms) exports (append (reverse (cdar forms)) imports) body)]
      ;; Skip (declare ...) forms — Gerbil compiler hints
      [(and (pair? (car forms)) (eq? (caar forms) 'declare))
       (loop (cdr forms) exports imports body)]
      [else
       (loop (cdr forms) exports imports (cons (car forms) body))])))
```

**Critical detail:** Gerbil files may have `(declare ...)` forms for optimizer hints. These should be **silently dropped** in the output since Chez doesn't use them.

### Step 6: Import Path Translation

This is the core translation engine. It converts Gerbil-style `:pkg/module` imports to R6RS `(pkg module)` library references.

```scheme
(define (translate-import spec)
  ;; Translate a single Gerbil import spec to R6RS.
  ;;
  ;; Cases:
  ;; 1. :std/sugar          → (std sugar)
  ;; 2. :std/srfi/13        → (std srfi srfi-13)     ** SPECIAL CASE **
  ;; 3. :std/misc/string    → (std misc string)
  ;; 4. :std/text/json      → (std text json)
  ;; 5. :std/os/path        → (std os path)
  ;; 6. :jerboa-emacs/core  → (jerboa-emacs core)
  ;; 7. :chez-scintilla/tui → (chez-scintilla tui)
  ;; 8. (only-in :foo/bar x y)   → (only (foo bar) x y)
  ;; 9. (except-in :foo/bar x y) → (except (foo bar) x y)
  ;; 10. (rename-in :foo/bar (old new)) → (rename (foo bar) (old new))
  ;; 11. Already-R6RS: (std sugar) → (std sugar) (pass through)
  ;; 12. (only (foo bar) x) → pass through
  ;;
  ;; Translation of a colon-prefixed symbol:
  ;;   - Remove leading ":"
  ;;   - Split by "/"
  ;;   - Convert parts to symbols
  ;;   - Return as list
  ;;
  ;; SRFI special case:
  ;;   :std/srfi/13 → (std srfi srfi-13)
  ;;   :std/srfi/1  → (std srfi srfi-1)
  ;;   The pattern is: if the path is (std srfi <N>), prefix the last
  ;;   component with "srfi-" to get (std srfi srfi-<N>).
  ...)
```

**Implementation:**

```scheme
(define (colon-symbol? x)
  ;; Is x a symbol starting with ":"?
  (and (symbol? x)
       (let ([s (symbol->string x)])
         (and (> (string-length s) 1)
              (char=? (string-ref s 0) #\:)))))

(define (translate-colon-path sym)
  ;; :std/sugar → (std sugar)
  ;; :std/srfi/13 → (std srfi srfi-13)
  (let* ([s (symbol->string sym)]
         [without-colon (substring s 1 (string-length s))]
         [parts (string-split-char without-colon #\/)]
         [symbols (map string->symbol parts)])
    ;; SRFI special case: (std srfi <N>) → (std srfi srfi-<N>)
    (if (and (>= (length symbols) 3)
             (eq? (car symbols) 'std)
             (eq? (cadr symbols) 'srfi))
      (let* ([last-part (symbol->string (list-ref symbols (- (length symbols) 1)))]
             ;; Check if it's a bare number like "13" or already "srfi-13"
             [srfi-name (if (string-prefix-ci? "srfi-" last-part)
                          last-part
                          (string-append "srfi-" last-part))])
        (append (list 'std 'srfi) (list (string->symbol srfi-name))))
      symbols)))

(define (translate-import spec)
  (cond
    ;; Case 1: :pkg/module symbol
    [(colon-symbol? spec)
     (translate-colon-path spec)]

    ;; Case 2: (only-in :pkg/module sym ...)
    [(and (pair? spec) (eq? (car spec) 'only-in))
     (let ([lib (translate-import (cadr spec))]
           [syms (cddr spec)])
       (cons 'only (cons lib syms)))]

    ;; Case 3: (except-in :pkg/module sym ...)
    [(and (pair? spec) (eq? (car spec) 'except-in))
     (let ([lib (translate-import (cadr spec))]
           [syms (cddr spec)])
       (cons 'except (cons lib syms)))]

    ;; Case 4: (rename-in :pkg/module (old new) ...)
    [(and (pair? spec) (eq? (car spec) 'rename-in))
     (let ([lib (translate-import (cadr spec))]
           [renames (cddr spec)])
       (cons 'rename (cons lib renames)))]

    ;; Case 5: Already R6RS — pass through
    ;; e.g. (std sugar), (only (std sugar) try), (chezscheme), etc.
    [(pair? spec) spec]

    ;; Case 6: Bare symbol (not colon-prefixed) — wrap in list
    ;; e.g. chezscheme → (chezscheme)
    [(symbol? spec) (list spec)]

    [else (error 'translate-import "Unknown import spec" spec)]))
```

**String helper needed** — `string-split-char`:
```scheme
(define (string-split-char str ch)
  ;; "std/sugar" #\/ → ("std" "sugar")
  (let ([len (string-length str)])
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(>= i len)
         (reverse (cons (substring str start len) acc))]
        [(char=? (string-ref str i) ch)
         (loop (+ i 1) (+ i 1) (cons (substring str start i) acc))]
        [else (loop (+ i 1) start acc)]))))
```

### Step 7: The Chezscheme Exclusion List

Jerboa shadows certain Chez Scheme built-in names. `jerbuild` must automatically add `(except (chezscheme) ...)` with the known set of conflicting names.

```scheme
(define *chez-exclusions*
  ;; Names that jerboa's (jerboa core) and (jerboa runtime) re-define.
  ;; When a source file imports these jerboa modules, the Chez versions
  ;; must be excluded to avoid "duplicate import" errors.
  ;;
  ;; This list is the UNION of all names that could conflict.
  ;; It is safe to exclude names that the file doesn't use — Chez
  ;; only errors on duplicate *imports*, not on unused exclusions.
  '(make-hash-table hash-table? iota 1+ 1- sort sort!
    path-extension path-absolute?
    printf fprintf
    with-input-from-string with-output-to-string))
```

**Important design decision:** Rather than analyzing which modules the file imports and conditionally excluding names, just **always exclude the full known set**. This is safe because `(except (chezscheme) name-that-doesnt-exist)` is NOT an error in Chez — it silently ignores names that aren't in the library. **VERIFY THIS** — if Chez errors on excluding non-existent names, then we need to use the conditional approach below instead.

**Fallback: conditional exclusion approach.** If Chez errors on excluding names not in the library, maintain a mapping of which imports trigger which exclusions:

```scheme
(define *exclusion-triggers*
  ;; Maps import library names to the Chez names they shadow.
  '(((jerboa core) . (make-hash-table hash-table? iota 1+ 1-))
    ((jerboa runtime) . (make-hash-table hash-table? iota 1+ 1-))
    ((std sort) . (sort sort!))
    ((std os path) . (path-extension path-absolute?))
    ((std format) . (printf fprintf))
    ((std misc ports) . (with-input-from-string with-output-to-string))))
```

Then compute the actual exclusion set from the file's translated imports:

```scheme
(define (compute-exclusions translated-imports)
  ;; For each translated import, look up what Chez names it shadows.
  ;; Return the union of all exclusions.
  (let loop ([imports translated-imports] [excls '()])
    (if (null? imports)
      (delete-duplicates excls eq?)
      (let* ([imp (car imports)]
             ;; Extract library name (strip only/except/rename wrappers)
             [lib-name (unwrap-import-lib imp)]
             [match (assoc lib-name *exclusion-triggers* equal?)])
        (loop (cdr imports)
              (if match
                (append (cdr match) excls)
                excls))))))
```

### Step 8: Defstruct Parsing (for struct-out expansion)

To expand `(struct-out foo)` in exports, we need to know foo's field names. Parse defstruct forms from the body.

```scheme
(define (collect-defstructs body-forms)
  ;; Scan body forms for (defstruct name (field ...)) patterns.
  ;; Returns an alist: ((name . (field1 field2 ...)) ...)
  ;;
  ;; Handles two forms:
  ;;   (defstruct name (f1 f2 ...))
  ;;   (defstruct (name parent) (f1 f2 ...))
  ;;
  ;; Also handles Gerbil keyword options after fields:
  ;;   (defstruct name (f1 f2 ...) transparent: #t)
  ;;   → just extract the fields list (second element after name)
  ;;
  ;; Returns: alist of (struct-name . field-list)
  (let loop ([forms body-forms] [structs '()])
    (cond
      [(null? forms) (reverse structs)]
      [(and (pair? (car forms))
            (>= (length (car forms)) 3)
            (eq? (caar forms) 'defstruct))
       (let* ([form (car forms)]
              [name-part (cadr form)]
              [name (if (pair? name-part) (car name-part) name-part)]
              [fields (caddr form)])
         (if (and (symbol? name) (list? fields))
           (loop (cdr forms) (cons (cons name fields) structs))
           (loop (cdr forms) structs)))]
      [else (loop (cdr forms) structs)])))
```

**Also handle `defclass`** — it has the same form:
```scheme
(defclass name (field1 field2 ...))
(defclass (name parent) (field1 field2 ...))
```

Add a similar scan for `defclass` forms (or treat them identically since `defclass` expands to `defstruct` in jerboa).

### Step 9: Export Expansion

```scheme
(define (expand-struct-out name fields)
  ;; Given struct name and field list, produce the list of exported symbols.
  ;; Uses the same naming convention as jerboa's (jerboa core) defstruct:
  ;;
  ;; (defstruct point (x y)) generates:
  ;;   point::t          — type descriptor
  ;;   make-point        — constructor
  ;;   point?            — predicate
  ;;   point-x           — accessor
  ;;   point-x-set!      — mutator
  ;;   point-y           — accessor
  ;;   point-y-set!      — mutator
  ;;
  ;; Note: field names may contain "?" (e.g., fuzzy?, volatile?)
  ;; The accessor becomes: helm-source-fuzzy?
  ;; The mutator becomes:  helm-source-fuzzy?-set!
  (let ([ns (symbol->string name)])
    (append
      (list
        ;; Type descriptor: name::t
        (string->symbol (string-append ns "::t"))
        ;; Constructor: make-name
        (string->symbol (string-append "make-" ns))
        ;; Predicate: name?
        (string->symbol (string-append ns "?")))
      ;; Accessors: name-field for each field
      (map (lambda (f)
             (string->symbol (string-append ns "-" (symbol->string f))))
           fields)
      ;; Mutators: name-field-set! for each field
      (map (lambda (f)
             (string->symbol (string-append ns "-" (symbol->string f) "-set!")))
           fields))))

(define (expand-exports export-specs struct-table body-forms)
  ;; Process the raw export spec list and return a flat list of symbols.
  ;;
  ;; Handles:
  ;;   - Plain symbols: pass through
  ;;   - (struct-out name): expand using struct-table
  ;;   - #t: collect all top-level def names from body-forms
  ;;   - (rename (old new)): pass through as-is for R6RS
  ;;
  ;; struct-table: alist from collect-defstructs
  ;; body-forms: for (export #t) expansion
  (let loop ([specs export-specs] [result '()])
    (cond
      [(null? specs) (reverse result)]

      ;; (struct-out name)
      [(and (pair? (car specs))
            (eq? (caar specs) 'struct-out)
            (= (length (car specs)) 2))
       (let* ([struct-name (cadar specs)]
              [entry (assq struct-name struct-table)])
         (if entry
           (let ([expanded (expand-struct-out struct-name (cdr entry))])
             (loop (cdr specs) (append (reverse expanded) result)))
           (error 'expand-exports
                  (format "struct-out: no defstruct found for ~a" struct-name))))]

      ;; #t — export everything defined in the body
      [(eq? (car specs) #t)
       (let ([all-names (collect-all-definitions body-forms struct-table)])
         (loop (cdr specs) (append (reverse all-names) result)))]

      ;; Plain symbol
      [(symbol? (car specs))
       (loop (cdr specs) (cons (car specs) result))]

      ;; (rename (old new)) — keep as-is
      [(and (pair? (car specs)) (eq? (caar specs) 'rename))
       (loop (cdr specs) (cons (car specs) result))]

      [else
       (error 'expand-exports "Unknown export spec" (car specs))])))
```

### Step 10: Collecting All Definitions (for `export #t`)

```scheme
(define (collect-all-definitions body-forms struct-table)
  ;; Collect all top-level definition names from body forms.
  ;; Used for (export #t).
  ;;
  ;; Recognizes:
  ;;   (def name ...)              → name
  ;;   (def (name args ...) ...)   → name
  ;;   (def* name ...)             → name
  ;;   (define name ...)           → name
  ;;   (define (name . args) ...)  → name
  ;;   (define-syntax name ...)    → name
  ;;   (defrule (name . pat) ...)  → name
  ;;   (defrules name ...)         → name
  ;;   (defstruct name (fields))   → expanded via struct-table
  ;;   (defstruct (name p) (f))    → expanded via struct-table
  ;;   (defclass name ...)         → expanded via struct-table
  ;;   (defmethod (name ...) ...)  → name
  ;;
  ;; Does NOT export:
  ;;   Names starting with * that also end with * are exported (Gerbil convention)
  ;;   Names starting with % are private (Gerbil convention) — SKIP
  ;;   Names starting with - are private — SKIP (optional, discuss)
  ;;
  ;; Returns: flat list of symbols
  (let loop ([forms body-forms] [names '()])
    (cond
      [(null? forms) (reverse names)]

      ;; def / define
      [(and (pair? (car forms))
            (memq (caar forms) '(def define)))
       (let ([second (cadar forms)])
         (cond
           ;; (def (name args ...) body ...)
           [(pair? second)
            (loop (cdr forms) (cons (car second) names))]
           ;; (def name expr)
           [(symbol? second)
            (loop (cdr forms) (cons second names))]
           [else (loop (cdr forms) names)]))]

      ;; def*
      [(and (pair? (car forms)) (eq? (caar forms) 'def*))
       (loop (cdr forms) (cons (cadar forms) names))]

      ;; define-syntax
      [(and (pair? (car forms)) (eq? (caar forms) 'define-syntax))
       (loop (cdr forms) (cons (cadar forms) names))]

      ;; defrule: (defrule (name . pattern) template)
      [(and (pair? (car forms)) (eq? (caar forms) 'defrule))
       (let ([pat (cadar forms)])
         (if (pair? pat)
           (loop (cdr forms) (cons (car pat) names))
           (loop (cdr forms) names)))]

      ;; defrules: (defrules name (keywords ...) clause ...)
      [(and (pair? (car forms)) (eq? (caar forms) 'defrules))
       (loop (cdr forms) (cons (cadar forms) names))]

      ;; defstruct / defclass — expand to all generated names
      [(and (pair? (car forms))
            (memq (caar forms) '(defstruct defclass)))
       (let* ([name-part (cadar forms)]
              [name (if (pair? name-part) (car name-part) name-part)]
              [entry (assq name struct-table)])
         (if entry
           (let ([expanded (expand-struct-out name (cdr entry))])
             (loop (cdr forms) (append (reverse expanded) names)))
           (loop (cdr forms) names)))]

      ;; defmethod: (defmethod (name (self type) args ...) body ...)
      [(and (pair? (car forms)) (eq? (caar forms) 'defmethod))
       ;; defmethod binds a method at runtime, not a top-level name.
       ;; Skip — the method name is dispatched via bind-method!, not exported.
       (loop (cdr forms) names)]

      ;; Anything else: skip
      [else (loop (cdr forms) names)])))
```

### Step 11: Implicit Imports — Auto-add `(jerboa core)` and `(jerboa runtime)`

Gerbil source files don't need to import the core language — it's always available. In jerboa, we need explicit imports. `jerbuild` should auto-inject these if not already present:

```scheme
(define *auto-imports*
  ;; These are always added unless the source file explicitly imports them.
  ;; (jerboa core) provides: def, defstruct, defclass, defmethod, defrule,
  ;;   match, try/catch/finally, hash, hash-eq, let-hash, struct-out,
  ;;   and re-exports from (jerboa runtime).
  ;; (jerboa runtime) is re-exported by (jerboa core), so just (jerboa core)
  ;; is sufficient. But some files import (jerboa runtime) explicitly for clarity.
  '((jerboa core)
    (jerboa runtime)))

(define (add-auto-imports translated-imports)
  ;; Add (jerboa core) and (jerboa runtime) if not already present.
  ;; Check by extracting the base library name from each import
  ;; (stripping only/except/rename wrappers).
  (let ([existing-libs (map unwrap-import-lib translated-imports)])
    (let loop ([autos *auto-imports*] [result translated-imports])
      (if (null? autos)
        result
        (if (member (car autos) existing-libs equal?)
          (loop (cdr autos) result)
          (loop (cdr autos) (cons (car autos) result)))))))

(define (unwrap-import-lib spec)
  ;; Extract the base library name from an import spec.
  ;; (only (std sugar) try) → (std sugar)
  ;; (except (foo bar) x)   → (foo bar)
  ;; (rename (foo bar) ...) → (foo bar)
  ;; (std sugar)            → (std sugar)
  (if (and (pair? spec) (memq (car spec) '(only except rename for)))
    (cadr spec)
    spec))
```

### Step 12: Assembling the Output Library Form

```scheme
(define (generate-library library-name exports imports body-forms)
  ;; Produce the complete R6RS library S-expression.
  ;;
  ;; library-name: (jerboa-emacs helm)
  ;; exports:      (make-helm-source helm-source? ...)  — flat list of symbols
  ;; imports:      ((except (chezscheme) ...) (jerboa core) (std sugar) ...)
  ;; body-forms:   ((defstruct helm-source ...) (def (helm-multi-match ...) ...) ...)
  ;;
  ;; Output form:
  ;; (library (jerboa-emacs helm)
  ;;   (export sym1 sym2 ...)
  ;;   (import (except (chezscheme) ...) (jerboa core) ...)
  ;;   body1 body2 ...)
  `(library ,library-name
     (export ,@exports)
     (import ,@imports)
     ,@body-forms))
```

### Step 13: Pretty-Printing the Output

```scheme
(define (write-library-file output-path library-form)
  ;; Write the library form to a .sls file with nice formatting.
  ;;
  ;; Strategy:
  ;; 1. Write "#!chezscheme\n" header
  ;; 2. Write ";;; Generated by jerbuild — DO NOT EDIT\n"
  ;; 3. Write ";;; Source: <relative-path-to-ss>\n\n"
  ;; 4. Pretty-print the library form
  ;;
  ;; Ensure parent directories exist before writing.
  (ensure-directory-exists (path-directory output-path))
  (call-with-output-file output-path
    (lambda (port)
      (display "#!chezscheme\n" port)
      (display ";;; Generated by jerbuild — DO NOT EDIT\n" port)
      (newline port)
      (pretty-print library-form port))
    'replace))  ;; 'replace = overwrite existing
```

**Note on `pretty-print`:** Chez Scheme's built-in `pretty-print` handles S-expressions well. The output won't be perfectly hand-formatted, but it will be correct and readable. The `(pretty-line-length)` parameter can be set to control line width (default 79).

**Helper:**
```scheme
(define (ensure-directory-exists dir)
  ;; Create directory and all parents if they don't exist.
  ;; Split path by "/" and create each component.
  (let ([parts (string-split-char dir #\/)])
    (let loop ([i 1] [path ""])
      (when (<= i (length parts))
        (let ([p (if (string=? path "")
                   (list-ref parts 0)
                   (string-append path "/" (list-ref parts (- i 1))))])
          ;; Handle leading "/" for absolute paths
          (when (and (> (string-length p) 0)
                     (not (file-exists? p)))
            (mkdir p))
          (loop (+ i 1) p))))))
```

**Simpler alternative** — use `system` to call `mkdir -p`:
```scheme
(define (ensure-directory-exists dir)
  (system (string-append "mkdir -p " dir)))
```

### Step 14: Content Hash Cache for Incremental Builds

```scheme
(define *hash-cache-file* ".jerbuild-hashes")

(define (load-hash-cache src-dir)
  ;; Load the hash cache from <src-dir>/.jerbuild-hashes
  ;; Format: alist of (file-path . hash-string)
  ;; Returns a Chez hashtable.
  (let ([cache (make-hashtable string-hash string=?)]
        [path (string-append src-dir "/" *hash-cache-file*)])
    (when (file-exists? path)
      (let ([data (call-with-input-file path read)])
        (when (list? data)
          (for-each
            (lambda (entry)
              (when (and (pair? entry) (string? (car entry)) (string? (cdr entry)))
                (hashtable-set! cache (car entry) (cdr entry))))
            data))))
    cache))

(define (save-hash-cache src-dir cache)
  ;; Save the hash cache to <src-dir>/.jerbuild-hashes
  (let ([path (string-append src-dir "/" *hash-cache-file*)])
    (call-with-output-file path
      (lambda (port)
        (let-values ([(keys vals) (hashtable-entries cache)])
          (let ([entries (map cons (vector->list keys) (vector->list vals))])
            (pretty-print entries port))))
      'replace)))

(define (file-changed? file-path hash-cache)
  ;; Check if file has changed since last build.
  ;; Uses compute-file-hash from (jerboa build).
  (or *force*
      (let ([current (compute-file-hash file-path)]
            [stored (hashtable-ref hash-cache file-path #f)])
        (not (equal? current stored)))))
```

### Step 15: The Main Build Loop

```scheme
(define (jerbuild src-dir lib-dir)
  ;; Main entry point.
  ;; 1. Discover .ss files
  ;; 2. Load hash cache
  ;; 3. For each file: check if changed, transform, write
  ;; 4. Save hash cache
  ;; 5. Print summary

  (let ([ss-files (discover-ss-files src-dir)]
        [hash-cache (load-hash-cache src-dir)]
        [processed 0]
        [skipped 0]
        [errors 0])

    (for-each
      (lambda (ss-path)
        (guard (exn
          [#t
           (set! errors (+ errors 1))
           (printf "ERROR: ~a: ~a\n" ss-path
                   (if (message-condition? exn)
                     (condition-message exn)
                     exn))])

          (if (file-changed? ss-path hash-cache)
            (begin
              (log-verbose "Processing: ~a" ss-path)

              ;; Compute library name from path
              (let* ([library-name (path->library-name src-dir ss-path)]
                     [output-path (compute-output-path lib-dir library-name)])

                ;; Read and parse
                (let ([forms (read-source-file ss-path)])
                  (let-values ([(export-specs import-specs body-forms)
                                (classify-forms forms)])

                    ;; Parse defstructs from body
                    (let* ([struct-table (collect-defstructs body-forms)]

                           ;; Expand exports
                           [expanded-exports
                            (expand-exports export-specs struct-table body-forms)]

                           ;; Translate imports
                           [translated-imports
                            (map translate-import import-specs)]

                           ;; Add auto-imports (jerboa core, jerboa runtime)
                           [with-autos
                            (add-auto-imports translated-imports)]

                           ;; Compute Chez exclusions
                           [exclusions (compute-exclusions with-autos)]

                           ;; Build final import list
                           [final-imports
                            (cons (if (null? exclusions)
                                    '(chezscheme)
                                    `(except (chezscheme) ,@exclusions))
                                  with-autos)]

                           ;; Generate library form
                           [library-form
                            (generate-library library-name
                                              expanded-exports
                                              final-imports
                                              body-forms)])

                      ;; Write output
                      (write-library-file output-path library-form)
                      (printf "  ~a → ~a\n" ss-path output-path)

                      ;; Update hash cache
                      (hashtable-set! hash-cache ss-path
                                      (compute-file-hash ss-path))
                      (set! processed (+ processed 1)))))))

            ;; File unchanged
            (begin
              (log-verbose "Skipped (unchanged): ~a" ss-path)
              (set! skipped (+ skipped 1))))))

      ss-files)

    ;; Save hash cache
    (save-hash-cache src-dir hash-cache)

    ;; Summary
    (printf "\njerbuild: ~a processed, ~a skipped, ~a errors (of ~a total)\n"
            processed skipped errors (length ss-files))))

;; --- Entry point ---
(let-values ([(src-dir lib-dir) (parse-args (command-line-arguments))])
  (jerbuild src-dir lib-dir))
```

---

## Edge Cases and Special Handling

### Edge Case 1: Gerbil `transparent: #t` and Other Struct Options

Gerbil's defstruct supports keyword options after the fields list:
```scheme
(defstruct helm-source
  (name candidates actions persistent-action display-fn real-fn
   fuzzy? volatile? candidate-limit keymap follow?)
  transparent: #t)
```

The `transparent: #t` part is **already handled** by jerboa's `defstruct` macro (it ignores unknown trailing forms). The body form is passed through verbatim. However, when **parsing** the defstruct to extract fields, `collect-defstructs` must only look at the third element (index 2) as the fields list and ignore everything after it.

### Edge Case 2: Multiple Export Forms

Gerbil files may have multiple `(export ...)` forms. The parser merges them:
```scheme
(export foo bar)
(export baz quux)
;; → merged to: (foo bar baz quux)
```

### Edge Case 3: Re-exports from Other Modules

If a file does `(export (struct-out point))` but `point` is defined in another module (imported, not local), `jerbuild` **cannot** expand it because it doesn't know the fields.

**Rule:** `(struct-out X)` only works for structs defined in the **same file**. If the struct is imported, the user must list the individual accessors manually in their export form. Print a clear error message:
```
ERROR: helm.ss: struct-out: no defstruct found for 'point' in this file.
  If 'point' is imported from another module, list its accessors explicitly.
```

### Edge Case 4: Files Without Export or Import

- **No `(export ...)`**: Error — every module must export something. (Or default to `(export #t)` — TBD, discuss with user.)
- **No `(import ...)`**: Legal — the file only uses Chez builtins and jerboa core (auto-imported).

### Edge Case 5: Nested Directories

Source: `src/jerboa-emacs/org/table.ss`
Library name: `(jerboa-emacs org table)`
Output: `lib/jerboa-emacs/org/table.sls`

The path computation handles arbitrary depth.

### Edge Case 6: `(import (jerboa prelude))` Shorthand

Some files might use `(import :jerboa/prelude)` which translates to `(import (jerboa prelude))`. This is a one-import-gets-everything module. `jerbuild` doesn't need special handling — it translates the path normally and the prelude module re-exports everything.

### Edge Case 7: `(only-in :std/srfi/19 current-date date->string)`

Translates to: `(only (std srfi srfi-19) current-date date->string)`

Note the SRFI special-case path translation applies inside `only-in`/`except-in` as well — the `translate-import` function recursively handles the library path.

### Edge Case 8: Body Forms with `begin`

Some Gerbil files wrap definitions in `(begin ...)`:
```scheme
(begin
  (def x 1)
  (def y 2))
```

For `(export #t)`, `collect-all-definitions` should recursively descend into `begin` blocks:
```scheme
;; In collect-all-definitions, add:
[(and (pair? (car forms)) (eq? (caar forms) 'begin))
 (let ([inner-names (collect-all-definitions (cdar forms) struct-table)])
   (loop (cdr forms) (append (reverse inner-names) names)))]
```

### Edge Case 9: `define-record-type` (raw R6RS)

Some files might use raw `define-record-type` instead of `defstruct`. The `collect-defstructs` function should also recognize this form:
```scheme
(define-record-type point (fields x y))
```
This is unlikely in Gerbil-style source but worth handling for completeness.

---

## The Chez Exclusion List — Complete Reference

Here is the **complete, verified** set of names that may conflict between `(chezscheme)` and jerboa's modules. This list is derived from examining the actual jerboa `.sls` files:

```scheme
(define *all-chez-exclusions*
  '(;; From (jerboa runtime) / (jerboa core):
    make-hash-table    ;; jerboa's hash tables wrap Chez hashtables
    hash-table?        ;; jerboa predicate
    iota               ;; jerboa version (SRFI-1 compatible)
    1+                 ;; jerboa versions
    1-

    ;; From (std sort):
    sort               ;; jerboa wraps with different API
    sort!

    ;; From (std os path):
    path-extension     ;; jerboa version
    path-absolute?     ;; jerboa version (present in some files)

    ;; From (std format):
    printf             ;; jerboa's printf
    fprintf

    ;; From (std misc ports):
    with-input-from-string
    with-output-to-string))
```

**Implementation strategy — recommended approach:**

Use the **conditional exclusion** approach from Step 7's fallback. For each translated import, look up which Chez names it shadows, and compute the union. This avoids potential issues with Chez erroring on excluding names from `(chezscheme)` that aren't actually there (unlikely, but safe).

---

## Testing Strategy

### Test 1: Round-trip a Simple Module

Create a test `.ss` file:
```scheme
;;; -*- Gerbil -*-
;;; test-module.ss

(export make-point point? point-x point-y double-x)
(import :std/sugar)

(defstruct point (x y))
(def (double-x p) (* 2 (point-x p)))
```

Run jerbuild, verify the `.sls` output matches expected form.

### Test 2: struct-out Expansion

```scheme
(export (struct-out point) double-x)
```

Should expand to: `(export point::t make-point point? point-x point-x-set! point-y point-y-set! double-x)`

### Test 3: export #t

```scheme
(export #t)
(import :std/sugar)
(def x 42)
(def (foo a) a)
(defstruct bar (baz quux))
```

Should export: `x foo bar::t make-bar bar? bar-baz bar-baz-set! bar-quux bar-quux-set!`

### Test 4: Import Path Translation

| Input | Expected Output |
|---|---|
| `:std/sugar` | `(std sugar)` |
| `:std/srfi/13` | `(std srfi srfi-13)` |
| `:std/text/json` | `(std text json)` |
| `:jerboa-emacs/core` | `(jerboa-emacs core)` |
| `(only-in :std/srfi/19 current-date)` | `(only (std srfi srfi-19) current-date)` |
| `(except-in :std/misc/string string-split)` | `(except (std misc string) string-split)` |

### Test 5: Incremental Build

1. Run jerbuild — all files processed
2. Run again — all files skipped (unchanged)
3. Touch one file — only that file reprocessed

### Test 6: Full jerboa-emacs Build

After converting jerboa-emacs `.sls` files to `.ss` format:
1. Run jerbuild to generate `.sls` files
2. Run the jerboa-emacs test suite
3. All tests pass

---

## Makefile Integration (for jerboa-emacs)

Add to `~/mine/jerboa-emacs/Makefile`:

```makefile
SCHEME ?= scheme
JERBOA_DIR ?= $(HOME)/mine/jerboa
JERBUILD = $(SCHEME) --libdirs $(JERBOA_DIR)/lib --script $(JERBOA_DIR)/jerbuild.ss

# Generate .sls from .ss source files
build:
	$(JERBUILD) src/ lib/

# Force rebuild all
rebuild:
	$(JERBUILD) src/ lib/ --force

# Clean generated files
clean-generated:
	rm -rf lib/jerboa-emacs/
	rm -f src/.jerbuild-hashes

# Build then test
test: build
	$(MAKE) test-tier0
```

Add to `~/mine/jerboa-emacs/.gitignore`:
```
lib/jerboa-emacs/
src/.jerbuild-hashes
```

---

## Migration Plan: Converting Existing .sls to .ss

For each `.sls` file in `jerboa-emacs/lib/jerboa-emacs/`:

1. **Copy** to `src/jerboa-emacs/<name>.ss`
2. **Remove** the `#!chezscheme` header
3. **Remove** the `(library (jerboa-emacs <name>) ...)` wrapper — extract just export, import, and body
4. **Convert** `(export ...)` — replace manual accessor lists with `(struct-out X)` where applicable
5. **Convert** `(import ...)`:
   - Remove `(except (chezscheme) ...)` — jerbuild adds it
   - Remove `(jerboa core)` and `(jerboa runtime)` — jerbuild adds them
   - Convert `(std sugar)` → `:std/sugar`
   - Convert `(std srfi srfi-13)` → `:std/srfi/13`
   - Convert `(jerboa-emacs core)` → `:jerboa-emacs/core`
   - Convert `(only (std srfi srfi-19) ...)` → `(only-in :std/srfi/19 ...)`
   - etc.
6. **Keep** body forms unchanged — they already use `def`, `defstruct`, etc.

This can be **partially automated** with a script. The key transforms are:
- Strip library wrapper (mechanical)
- Convert import paths (mechanical — reverse of translate-import)
- Replace struct accessor export lists with struct-out (heuristic — match accessor naming patterns)

---

## Implementation Order

1. **String helpers** (Steps 2-4): `string-split-char`, `string-suffix?`, path manipulation
2. **Import translation** (Step 6): `translate-import`, `colon-symbol?`, `translate-colon-path`
3. **Defstruct parsing** (Step 8): `collect-defstructs`
4. **Export expansion** (Steps 9-10): `expand-struct-out`, `expand-exports`, `collect-all-definitions`
5. **Chez exclusions** (Step 7): `*chez-exclusions*`, `compute-exclusions`
6. **Auto-imports** (Step 11): `add-auto-imports`
7. **File reading and classification** (Step 5): `read-source-file`, `classify-forms`
8. **Output generation** (Steps 12-13): `generate-library`, `write-library-file`
9. **Hash cache** (Step 14): `load-hash-cache`, `save-hash-cache`, `file-changed?`
10. **Main loop** (Step 15): `jerbuild`, CLI parsing, entry point
11. **Tests** — write test `.ss` files and verify round-trip correctness
12. **Migration script** (optional) — automate .sls → .ss conversion for jerboa-emacs

---

## Summary of Functions to Implement

| Function | Purpose |
|---|---|
| `parse-args` | CLI argument parsing |
| `log-verbose` | Conditional logging |
| `string-split-char` | Split string by delimiter character |
| `string-suffix?` | Check if string ends with suffix |
| `discover-ss-files` | Recursively find .ss files |
| `path->library-name` | `src/jerboa-emacs/helm.ss` → `(jerboa-emacs helm)` |
| `compute-output-path` | Library name → `.sls` output path |
| `ensure-directory-exists` | Create parent directories |
| `read-source-file` | Read all forms from .ss file |
| `classify-forms` | Separate export/import/body forms |
| `colon-symbol?` | Check for `:prefix` symbols |
| `translate-colon-path` | `:std/sugar` → `(std sugar)` |
| `translate-import` | Full import spec translation |
| `unwrap-import-lib` | Strip only/except/rename wrapper |
| `compute-exclusions` | Determine Chez names to exclude |
| `collect-defstructs` | Parse defstruct forms for field info |
| `expand-struct-out` | Struct name + fields → export symbols |
| `expand-exports` | Process all export specs |
| `collect-all-definitions` | Scan body for all top-level names |
| `add-auto-imports` | Inject `(jerboa core)` etc. |
| `generate-library` | Assemble the R6RS library S-expression |
| `write-library-file` | Pretty-print to .sls with header |
| `load-hash-cache` | Load incremental build state |
| `save-hash-cache` | Save incremental build state |
| `file-changed?` | Content-hash comparison |
| `jerbuild` | Main build orchestration |

---

## What This Unlocks

- **jerboa-emacs** source stays as Gerbil `.ss` files — minimal diff from `gerbil-emacs`
- New modules are added by copying a `.ss` file, no R6RS boilerplate to write
- Porting other Gerbil projects to jerboa becomes: rename `:gemacs/` prefixes, run `jerbuild`, done
- Future: jerbuild could emit a compatibility shim so the same `.ss` file compiles under both Gerbil and jerboa
