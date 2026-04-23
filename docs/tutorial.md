# Jerboa Tutorial: Build a URL Shortener

This tutorial walks you from `hello world` to a deployable single-file
Jerboa service. By the end you will have built **Stubby**, a small URL
shortener with:

- A `defstruct`-modeled core
- An in-memory cache and a SQLite persistent store
- An HTTP API on top of `(std net httpd)`
- A test suite run by `jerboa test`
- A packaged, redistributable single-file script

Every code block in this document is a complete runnable or compilable
Jerboa program — the project's CI verifies that.

---

## 0. Prerequisites

- Chez Scheme ≥ 10.x (`scheme --version`)
- A clone of Jerboa with `bin/jerboa` on your `PATH`:

```bash
git clone https://github.com/ober/jerboa.git
cd jerboa
make build
export PATH="$PWD/bin:$PATH"
```

Verify:

```bash
jerboa version
```

---

## 1. Hello, world

Create `stubby.ss`:

```scheme
(import (jerboa prelude))

(displayln "Stubby is starting up.")
```

Run it:

```bash
jerboa run stubby.ss
```

One import, one line of code. `(jerboa prelude)` is the entire
language — no separate core/text/number modules to juggle. Everything
you'll use below (structs, hash tables, regex, JSON, format, match)
lives in the prelude.

---

## 2. Model the domain with `defstruct`

A short link maps a **slug** (`abc123`) to a **target URL** and tracks
how many times it has been resolved.

```scheme
(import (jerboa prelude))

(defstruct short-link (slug target hits))

(def (new-link slug target)
  (make-short-link slug target 0))

(def (bump-hits! link)
  (short-link-hits-set! link (+ (short-link-hits link) 1)))

(let ([ln (new-link "abc" "https://example.com")])
  (bump-hits! ln)
  (bump-hits! ln)
  (printf "slug=~a target=~a hits=~a~n"
          (short-link-slug ln)
          (short-link-target ln)
          (short-link-hits ln)))
```

`defstruct` autogenerates `make-short-link`, `short-link?`, one
accessor per field (`short-link-slug`), and mutators with the
`-set!` suffix (`short-link-hits-set!`). No more boilerplate.

---

## 3. Generate slugs

Real shorteners let users pass a custom slug, but fall back to a
random one. We'll use the prelude's `random` and `string-append`:

```scheme
(import (jerboa prelude))

(def *alphabet*
  (string->list "abcdefghijkmnpqrstuvwxyz23456789"))

(def (random-slug (n 6))
  (list->string
    (map (lambda (_) (list-ref *alphabet* (random (length *alphabet*))))
         (iota n))))

(displayln (random-slug))
(displayln (random-slug 8))
```

Notes:
- The ambiguous characters `0 o l 1` are omitted so slugs stay
  copy-paste-safe over voice/print.
- `(random N)` returns an integer in `[0, N)`.
- `(iota n)` is `0..n-1` — the Jerboa prelude shadows Chez's
  stricter version to give you the SRFI-1 interface.

---

## 4. An in-memory store

Wrap the map in a tiny module-like closure so the rest of the program
never touches the hash table directly:

```scheme
(import (jerboa prelude))

(defstruct short-link (slug target hits))

(def (new-link slug target) (make-short-link slug target 0))

(def (make-store)
  (let ([ht (make-hash-table)])
    (lambda (op . args)
      (case op
        [(put!)   (hash-put! ht (car args) (cadr args))]
        [(get)    (hash-get ht (car args))]
        [(has?)   (hash-key? ht (car args))]
        [(all)    (hash-values ht)]
        [(remove!) (hash-remove! ht (car args))]
        [else (error 'store "unknown op" op)]))))

(def store (make-store))
(store 'put! "abc" (new-link "abc" "https://example.com"))
(store 'put! "xyz" (new-link "xyz" "https://jerboa.dev"))

(printf "abc → ~a~n" (short-link-target (store 'get "abc")))
(printf "total: ~a links~n" (length (store 'all)))
```

This is a deliberate choice to demonstrate closure-based
encapsulation; the next section swaps it for SQLite without changing
the callers.

---

## 5. Persist to SQLite

Add `(std db sqlite)` and define a store with the same shape. We keep
a write-through cache so reads stay in-memory but survive restarts:

```scheme
(import (jerboa prelude)
        (std db sqlite))

(defstruct short-link (slug target hits))

(def (sqlite-store path)
  (let ([db (sqlite-open path)]
        [cache (make-hash-table)])
    (sqlite-exec db
      "CREATE TABLE IF NOT EXISTS links (
         slug   TEXT PRIMARY KEY,
         target TEXT NOT NULL,
         hits   INTEGER NOT NULL DEFAULT 0)")
    ;; Warm the cache from disk.
    (for-each
      (lambda (row)
        (hash-put! cache (vector-ref row 0)
          (make-short-link (vector-ref row 0)
                           (vector-ref row 1)
                           (vector-ref row 2))))
      (sqlite-query db "SELECT slug, target, hits FROM links"))
    (lambda (op . args)
      (case op
        [(put!)
         (let ([ln (cadr args)])
           (sqlite-eval db
             "INSERT OR REPLACE INTO links (slug, target, hits) VALUES (?, ?, ?)"
             (short-link-slug ln)
             (short-link-target ln)
             (short-link-hits ln))
           (hash-put! cache (car args) ln))]
        [(get)    (hash-get cache (car args))]
        [(has?)   (hash-key? cache (car args))]
        [(all)    (hash-values cache)]
        [(bump!)
         (let ([ln (hash-get cache (car args))])
           (when ln
             (short-link-hits-set! ln (+ (short-link-hits ln) 1))
             (sqlite-eval db
               "UPDATE links SET hits = hits + 1 WHERE slug = ?"
               (car args))))]
        [(close!) (sqlite-close db)]
        [else (error 'store "unknown op" op)]))))

;; Smoke test:
(def db-path "stubby-demo.db")
(when (file-exists? db-path) (delete-file db-path))
(def st (sqlite-store db-path))
(st 'put! "abc" (make-short-link "abc" "https://example.com" 0))
(st 'bump! "abc")
(printf "abc hits: ~a~n" (short-link-hits (st 'get "abc")))
(st 'close!)
(delete-file db-path)
```

Key patterns:
- `sqlite-exec` for DDL, `sqlite-eval` for parametrized writes,
  `sqlite-query` for `SELECT`.
- Parameters bind via `?` with positional args — never string-append
  SQL (injection risk, and `jerboa_security_scan` will flag it).
- `(case op ...)` dispatches symbol ops cheaply; no method-table
  overhead is needed at this scale.

---

## 6. Serve it over HTTP

Jerboa's `(std net httpd)` mirrors the simple-handler shape you'd
recognize from Ring (Clojure) or Rack (Ruby): a handler takes a
request alist and returns a response alist.

```scheme
(import (jerboa prelude)
        (std net httpd)
        (std net router)
        (std db sqlite))

(defstruct short-link (slug target hits))

;; --- tiny helpers ---------------------------------------------------
(def (json-response body (status 200))
  `((status . ,status)
    (headers . (("Content-Type" . "application/json")))
    (body . ,(json-object->string body))))

(def (redirect-to url)
  `((status . 302)
    (headers . (("Location" . ,url)))
    (body . "")))

(def (not-found msg)
  (json-response
    (list->hash-table `(("error" . ,msg)))
    404))

;; --- store (re-uses the sqlite-store closure from §5) --------------
;; For brevity this example uses an in-memory map; swap in
;; (sqlite-store "stubby.db") for persistence.
(def store
  (let ([ht (make-hash-table)])
    (lambda (op . args)
      (case op
        [(put!)  (hash-put! ht (car args) (cadr args))]
        [(get)   (hash-get ht (car args))]
        [(has?)  (hash-key? ht (car args))]
        [(bump!)
         (let ([ln (hash-get ht (car args))])
           (when ln
             (short-link-hits-set! ln (+ (short-link-hits ln) 1))))]))))

;; --- handlers -------------------------------------------------------
(def (handle-create req)
  (let* ([query (or (request-query req) "")]
         [target (query-param query "url")])
    (if target
      (let ([slug (random-slug)])
        (store 'put! slug (make-short-link slug target 0))
        (json-response
          (list->hash-table
            `(("slug" . ,slug)
              ("target" . ,target)))
          201))
      (not-found "missing 'url' query parameter"))))

(def (handle-follow req)
  (let ([slug (route-param req "slug")])
    (let ([ln (store 'get slug)])
      (if ln
        (begin
          (store 'bump! slug)
          (redirect-to (short-link-target ln)))
        (not-found (format "no such slug: ~a" slug))))))

(def (handle-stats req)
  (let ([slug (route-param req "slug")])
    (let ([ln (store 'get slug)])
      (if ln
        (json-response
          (list->hash-table
            `(("slug"   . ,(short-link-slug ln))
              ("target" . ,(short-link-target ln))
              ("hits"   . ,(short-link-hits ln)))))
        (not-found "no such slug")))))

;; --- glue -----------------------------------------------------------
(def *alphabet* (string->list "abcdefghijkmnpqrstuvwxyz23456789"))
(def (random-slug (n 6))
  (list->string
    (map (lambda (_) (list-ref *alphabet* (random (length *alphabet*))))
         (iota n))))

(def (query-param query name)
  (let loop ([pairs (string-split query "&")])
    (cond
      [(null? pairs) #f]
      [else
       (let ([kv (string-split (car pairs) "=")])
         (if (and (= (length kv) 2) (string=? (car kv) name))
           (cadr kv)
           (loop (cdr pairs))))])))

(def routes
  (make-router
    (route "POST" "/api/links"         handle-create)
    (route "GET"  "/api/links/:slug"   handle-stats)
    (route "GET"  "/:slug"             handle-follow)))

;; Uncomment to serve:
;; (start-httpd 8080 routes)
(displayln "Stubby routes compiled; uncomment start-httpd to serve.")
```

Test it with `curl`:

```bash
# Create a short link:
curl -X POST 'http://localhost:8080/api/links?url=https%3A%2F%2Fexample.com'
# → {"slug":"k4mq9v","target":"https://example.com"}

# Follow it:
curl -v http://localhost:8080/k4mq9v
# → 302 Location: https://example.com

# Get stats:
curl http://localhost:8080/api/links/k4mq9v
# → {"slug":"k4mq9v","target":"...","hits":1}
```

---

## 7. Tests

Put this in `tests/test-stubby.ss`:

```scheme
(import (jerboa prelude))

(defstruct short-link (slug target hits))

(def (new-link slug target) (make-short-link slug target 0))

(def pass 0)
(def fail 0)

(def (check name actual expected)
  (if (equal? actual expected)
    (begin (set! pass (+ pass 1))
           (printf "  PASS  ~a~n" name))
    (begin (set! fail (+ fail 1))
           (printf "  FAIL  ~a~n" name)
           (printf "        expected: ~s~n" expected)
           (printf "        got:      ~s~n" actual))))

(check "accessors"
  (let ([ln (new-link "abc" "https://example.com")])
    (list (short-link-slug ln) (short-link-target ln) (short-link-hits ln)))
  '("abc" "https://example.com" 0))

(check "hits mutator"
  (let ([ln (new-link "abc" "https://example.com")])
    (short-link-hits-set! ln 3)
    (short-link-hits ln))
  3)

(check "predicate"
  (short-link? (new-link "a" "b"))
  #t)

(printf "~n~a passed, ~a failed~n" pass fail)
(when (> fail 0) (exit 1))
```

Run the suite:

```bash
jerboa test tests/
```

`jerboa test` discovers every `tests/test-*.ss`, runs each with the
library path preconfigured, and reports pass/fail counts.

For heavier projects, use `(std test)` (matchers, fixtures,
deterministic output) — see [testing-and-infrastructure.md](testing-and-infrastructure.md).

---

## 8. Package as a single file

The moment you want to hand `stubby.ss` to a friend, they shouldn't
need to clone the Jerboa repo to run it. The
[single-file package format](single-file-packages.md) lets you
declare dependencies in the file header and `jerboa exec` auto-installs
them:

```scheme
#!/usr/bin/env -S jerboa exec
;;; jerboa-package
;;; name:    stubby
;;; version: 0.1.0
;;; requires:
;;;
;;; Stubby — minimalist URL shortener.
;;; Uses only prelude + std modules, so requires: is empty.
(import (jerboa prelude)
        (std net httpd)
        (std net router)
        (std db sqlite))

;; ...rest of the program...
(displayln "Stubby ready.")
```

Make it executable and run:

```bash
chmod +x stubby.ss
./stubby.ss
```

If Stubby later depends on a third-party Jerboa package (say, a
Markdown renderer), you add it to `requires:`:

```
;;; requires:
;;;   github.com/alice/jerboa-markdown
```

On the recipient's first run, `jerboa exec` prompts once to install
the missing dependency and then runs the script. Set
`JERBOA_EXEC_YES=1` for non-interactive CI.

---

## 9. What to read next

- [anti-cookbook.md](anti-cookbook.md) — multi-form gotchas that
  catch newcomers (hash-ref arg order, list-of? as a factory, etc.)
- [module-quickstarts.md](module-quickstarts.md) — runnable snippets
  for 22+ stdlib modules
- [reader-syntax.md](reader-syntax.md) — bracket/keyword/heredoc
  rules with exact desugaring
- [packages.md](packages.md) — how to publish Jerboa packages
- [safety-guide.md](safety-guide.md) — `(jerboa prelude strict)` and
  capability-based restrictions

## 10. The finished layout

```
my-stubby/
├── stubby.ss           # the single-file service
├── tests/
│   └── test-stubby.ss
└── README.md
```

That is a complete, deployable Jerboa project: one source file for
the program, one directory of tests, no build system, no manifest.
If Stubby grows a second source file, move to the multi-file
layout documented in [packages.md](packages.md) — but resist until
you have to.
