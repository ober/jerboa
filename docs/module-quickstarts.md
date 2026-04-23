# Jerboa Module Quickstarts

_One working example per common `(std ...)` module. Each snippet is a
complete runnable `.ss` file — paste it into `/tmp/x.ss` and run with
`scheme --libdirs lib --script /tmp/x.ss` from the Jerboa repo root.
Exports referenced here are verified against `api-signatures.json`
(2026-04-22)._

All examples assume `(import (jerboa prelude))` at the top — the
snippets add the module-specific import on top of that.

---

## I/O & files

### `(std io)` — whole-file reads/writes

```scheme
(import (jerboa prelude) (std io))

(write-all "/tmp/hello.txt" "hi\nworld\n")
(displayln (read-all "/tmp/hello.txt"))

(write-sexp-file "/tmp/data.sexp" '((a 1) (b 2)))
(displayln (read-sexp-file "/tmp/data.sexp"))   ; → ((a 1) (b 2))
```

Exports: `read-all`, `write-all`, `read-sexp-file`, `write-sexp-file`,
`read-sexp-port`, `write-sexp-port`, `with-input`, `with-output`.

---

### Paths & prelude file helpers

`path-join`, `read-file-string`, `read-file-lines`, `write-file-string`
are in the **prelude** — no extra import needed:

```scheme
(import (jerboa prelude))

(define p (path-join "/tmp" "note.txt"))
(write-file-string p "line 1\nline 2\n")
(for ((line (in-list (read-file-lines p))))
  (displayln line))
```

---

## Text formats

### `(std text json)` — JSON

```scheme
(import (jerboa prelude) (std text json))

(define h (string->json-object "{\"name\":\"Alice\",\"age\":30}"))
(hash-ref h "name")                        ; → "Alice"

(hash-put! h "tags" (vector "admin" "dev"))
(displayln (json-object->string h))
```

JSON objects ↔ hash tables; JSON arrays ↔ vectors (not lists).

---

### `(std text yaml)` — YAML

```scheme
(import (jerboa prelude) (std text yaml))

;; Parsing: read-yaml-from-string (from full module, not prelude)
;; See jerboa_module_exports '(std text yaml)' for the full 66-export API —
;; common entry points: read-yaml-from-string, write-yaml-to-string.
```
_YAML module has 66 exports covering streaming, anchors, tags. Use
`jerboa_module_exports '(std text yaml)'` to see the full list before
writing YAML-specific code._

---

### `(std text utf8)` — byte ↔ string

```scheme
(import (jerboa prelude) (std text utf8))

(define bv (string->utf8 "héllo"))         ; → bytevector
(define s  (utf8->string bv))              ; → "héllo"

(displayln (bytevector-length bv))         ; 6 (é is 2 bytes)
```

---

### `(std csv)` — CSV

```scheme
(import (jerboa prelude) (std csv))

(write-csv-file "/tmp/a.csv"
                '(("name" "age") ("Alice" "30") ("Bob" "25")))

(for ((row (in-list (read-csv-file "/tmp/a.csv"))))
  (displayln row))

;; Row-of-alists mode:
(define rows (csv->alists "name,age\nAlice,30"))
(hash-ref (car rows) 'name)                ; → "Alice"
```

---

### `(std regex)` — regex (the prelude re-exports the essentials)

```scheme
(import (jerboa prelude))                   ; re, re-match?, etc. in prelude

(re-match? "\\d+" "42")                    ; → #t  (full-string match)
(re-search "\\d+" "abc 42 xyz")            ; → match-object
(re-find-all "\\w+" "hello world")         ; → ("hello" "world")
(re-replace-all "\\d" "abc1def2" "X")      ; → "abcXdefX"
(re-split "\\s+" "a   b  c")               ; → ("a" "b" "c")

;; SRE (symbolic) patterns:
(define p (rx (+ digit)))
(re-match? p "123")                        ; → #t
```

Named captures (SRE only):
```scheme
(define m (re-search (rx (: (=> year (= 4 digit))
                            "-"
                            (=> month (= 2 digit))))
                     "2026-04"))
(re-match-named m 'year)                   ; → "2026"
```

---

### `(std rx patterns)` — 30+ pre-built named patterns

```scheme
(import (jerboa prelude) (std rx patterns))

(re-match? rx:email "user@example.com")    ; → #t
(re-match? rx:uuid "550e8400-e29b-41d4-a716-446655440000")
(re-match? rx:ip4 "192.168.1.1")
```

---

### `(std peg)` — PEG grammars

```scheme
(import (jerboa prelude) (std peg))

(define-grammar calc
  (expr   (/ (: term "+" expr) term))
  (term   (/ digits))
  (digits (+ (/ "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"))))
;; Then use peg-parse or the grammar's entry point.
```
_See `jerboa_module_exports '(std peg)'` — 6 exports around
`define-grammar` and `peg-error-*`._

---

## Networking

### `(std net request)` — HTTP client

```scheme
(import (jerboa prelude) (std net request))

(define r (http-get "https://httpbin.org/get"))
(request-status r)                         ; → 200
(request-text r)                           ; → body as string

(define r2 (http-post "https://httpbin.org/post"
                      headers: '(("Content-Type" . "application/json"))
                      data: "{\"x\":1}"))
(request-close r2)                         ; always close
```

URL helpers: `parse-url`, `url-encode`, `build-query-string`,
`url-parts-host`, `url-parts-port`, `url-parts-path`, `url-parts-scheme`.

---

### `(std net httpd)` — HTTP server

```scheme
(import (jerboa prelude) (std net httpd))

;; http-req-* / http-res-* are the handler-API surface.
;; See jerboa_howto "httpd" for a complete canonical handler template —
;; don't guess the handler signature; the cookbook has it verified.
```

_28 exports. Use `jerboa_httpd_handler_scaffold` to generate a stub._

---

## OS

### `(std os env)` — environment variables

```scheme
(import (jerboa prelude) (std os env))

(getenv "PATH")                            ; → string or #f
(setenv "MY_VAR" "hello")
(unsetenv "OLD_VAR")
```

---

### `(std os signal)` — signal constants + handlers

```scheme
(import (jerboa prelude) (std os signal))

SIGINT SIGTERM SIGKILL                     ; numeric constants
;; See 32 exports including SIGABRT..SIGXCPU plus handler-install hooks.
```

---

## Concurrency

### `(std misc thread)` — threads / mutex / CV

```scheme
(import (jerboa prelude) (std misc thread))

(define t (spawn (lambda () (displayln "hi from thread"))))
(thread-join! t)

(define m (make-mutex))
(mutex-lock! m)
(mutex-unlock! m)

;; thread-sleep! is a Gambit-compat wrapper here
(thread-sleep! 0.1)
```

Note: Chez must be built with threading enabled for these to work at
runtime. If you see `variable make-mutex is not bound`, your Chez build
is non-threaded.

---

### `(std misc process)` — subprocess

```scheme
(import (jerboa prelude) (std misc process))

(define p (open-input-process "ls /tmp"))
(for ((line (in-lines p)))
  (displayln line))
(close-input-port p)
```

Exports: `open-process`, `open-input-process`, `open-output-process`,
`filter-with-process`, + 11 more.

---

### `(std actor)` — actor system

```scheme
(import (jerboa prelude) (std actor))

;; 57 exports. Use jerboa_actor_ensemble_scaffold to generate a
;; canonical actor + supervisor skeleton rather than hand-writing.
```

---

### `(std async)` — async/await

```scheme
(import (jerboa prelude) (std async))

;; Primary primitives: async-channel-get, async-channel-put, and the
;; Async abstract base. See full 14-export API via jerboa_module_exports.
```

---

## Data

### `(std sort)` — sort (Chez arg order: predicate first)

```scheme
(import (jerboa prelude) (std sort))

(sort < '(3 1 4 1 5 9 2 6))                ; → (1 1 2 3 4 5 6 9)
(stable-sort string<? '("b" "a" "c"))      ; → ("a" "b" "c")

;; In-place versions mutate the input list:
(sort! > (list 3 1 2))                     ; → (3 2 1)
```

**Do not** write `(sort '(3 1 2) <)` — that's SRFI-95 / Gerbil order,
wrong in Jerboa.

---

### `(std datetime)` — dates & times

```scheme
(import (jerboa prelude))                   ; datetime basics are in prelude

(define now (datetime-now))
(datetime->iso8601 now)                    ; → "2026-04-22T…"
(datetime-year now)                         ; → 2026

(define dt (make-datetime 2026 4 22 12 0 0))
(datetime<? dt now)                         ; → #t/#f

(day-of-week dt)                            ; → symbol
(leap-year? 2024)                           ; → #t
```

Full 50-export API includes `parse-datetime`, `duration`,
`datetime-add`, `datetime-diff`, floor/truncate ops.

---

### `(std crypto digest)` — hashes

```scheme
(import (jerboa prelude) (std crypto digest))

(define h (sha256 (string->utf8 "hello")))    ; → digest object
(digest->hex-string h)                        ; → "2cf24d…"

;; Available digests: md5, sha1, sha224, sha256, sha384, sha512
```

---

### `(std crypto hmac)` — HMAC

```scheme
(import (jerboa prelude) (std crypto hmac))

(define sig (hmac-sha256 (string->utf8 "key")
                         (string->utf8 "msg")))
(digest->hex-string sig)
```

---

### `(std db sqlite)` — SQLite

```scheme
(import (jerboa prelude) (std db sqlite))

;; 28 exports including SQLITE_OK/SQLITE_DONE constants plus connection
;; and statement APIs. Use jerboa_howto "sqlite" for a verified
;; connection-pool pattern.
```

---

## Formatting & logging

### `(std format)` — `format`, `printf`, `fprintf`

`format` and `printf` are already in the prelude (shadowed versions).
For explicit control or to get `eprintf`:

```scheme
(import (jerboa prelude) (std format))

(printf "~a / ~a = ~a~%" 10 3 (/ 10 3))
(eprintf "ERROR: ~a~%" "oh no")             ; writes to stderr
(define s (format "x=~a" 42))               ; → "x=42"
```

---

### `(std logger)` — structured logging

```scheme
(import (jerboa prelude) (std logger))

(debugf "processing ~a items" 42)
(current-log-directory "/var/log/myapp")    ; parameter
```
_12 exports; primary entry points: `debugf`, `current-logger`,
`current-log-directory`._

---

## Compatibility shims

### `(std gambit-compat)` — Gambit names

**218 exports.** Import this to get Gambit-style names (e.g.,
`thread-sleep!`, `time->seconds`, `open-fd-pair`-style aliases) working.
Only use when porting Gambit code — for new code, use the native Jerboa
spelling from the prelude.

### `(std srfi srfi-1)` — SRFI-1 list library

```scheme
(import (jerboa prelude) (std srfi srfi-1))

(fold + 0 '(1 2 3 4))                       ; → 10
(take '(a b c d e) 2)                       ; → (a b)  (also in prelude)
(delete-duplicates '(1 2 1 3 2))            ; → (1 2 3)
```

71 exports. Most commonly-used SRFI-1 procedures (`map`, `filter`,
`fold`, `take`, `drop`) are already in the Jerboa prelude under their
standard names.

---

## When in doubt

Every module's export list is authoritative via:

```
jerboa_module_exports '(std text yaml)'
```

`api-signatures.json` in `jerboa-mcp/` is the single source of truth for
"does symbol X exist and where?" questions — parsed directly from .sls
source files on every regeneration.
