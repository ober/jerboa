# Fearless FFI — Safe C Interoperability

Jerboa provides two complementary FFI layers:
- `(std foreign)` — declarative macros for binding C libraries
- `(std foreign bind)` — higher-level organization: ownership tracking, async FFI

Both eliminate boilerplate and prevent common FFI errors.

---

## `(std foreign)` — FFI DSL

### `define-ffi-library` — bind an entire C library

```scheme
(define-ffi-library library-name
  [(shared-lib "libname.so")]
  (bind scheme-name (arg-type ...) -> ret-type)
  ...)
```

Loads the shared library and creates Scheme bindings for each function.

**Type names:**
| Scheme type | C type |
|---|---|
| `int` | `int` |
| `uint` / `unsigned-int` | `unsigned int` |
| `int8` … `int64` | `int8_t` … `int64_t` |
| `uint8` … `uint64` | `uint8_t` … `uint64_t` |
| `size_t` | `size_t` |
| `float` / `double` | `float` / `double` |
| `string` | `const char *` (UTF-8) |
| `ptr` | `void *` |
| `bool` | `bool` (0/1 → #f/#t) |
| `void` | `void` |

```scheme
(import (chezscheme) (std foreign))

;; Bind libm
(define-ffi-library libm
  (shared-lib "libm.so.6")
  (bind pow  (double double) -> double)
  (bind sqrt (double)        -> double)
  (bind sin  (double)        -> double))

(sqrt 2.0)   ; => 1.4142135623730951
(pow 2.0 10) ; => 1024.0
```

### `define-foreign` — bind a single function

```scheme
(define-foreign scheme-name
  (c-function-name arg-type ...)
  -> ret-type)
```

### `define-foreign/check` — with automatic error checking

```scheme
(define-foreign/check scheme-name
  (c-function-name arg-type ...)
  -> ret-type
  (check-expr))   ; raises error if check-expr is #f
```

```scheme
;; malloc with NULL check
(define-foreign/check my-malloc
  (malloc size_t)
  -> ptr
  (not (= result 0)))  ; error if malloc returns NULL
```

### `define-const` — C compile-time constants

```scheme
(define-const name c-expression)
```

```scheme
(define-const EAGAIN 11)     ; errno value
(define-const O_RDONLY 0)
(define-const STDIN_FD 0)
```

### `define-foreign-type` — pointer type with GC destructor

```scheme
(define-foreign-type type-name
  (free-fn ptr)               ; called when GC collects the wrapper
  (wrap expr)                 ; optional: wrap raw pointer
  (unwrap expr))              ; optional: unwrap to raw pointer
```

```scheme
;; SQLite handle with automatic close
(define-foreign-type sqlite3-handle
  (sqlite3_close ptr))

;; When the Scheme wrapper is GC'd, sqlite3_close is called automatically
```

### `define-foreign-struct` — map a C struct

```scheme
(define-foreign-struct name
  (field c-type offset) ...)
```

```scheme
(define-foreign-struct timeval
  (tv-sec  long 0)
  (tv-usec long 8))

(let ([tv (foreign-alloc (foreign-sizeof 'long))])
  (let ([t (make-timeval tv)])
    (timeval-tv-sec t)))
```

### `with-foreign-resource` — deterministic cleanup

```scheme
(with-foreign-resource ([var (alloc-expr) free-fn] ...) body ...)
```

```scheme
(with-foreign-resource ([buf (foreign-alloc 1024) foreign-free])
  ;; buf is freed when body exits, even on exception
  (write-data-to buf))
```

### `define-callback` — Scheme function callable from C

```scheme
(define-callback c-name (arg-type ...) -> ret-type
  (lambda (arg ...) body ...))
```

### `start-guardian-thread!` / `stop-guardian-thread!`

Start a background thread that monitors guardians and calls foreign destructors
when GC'd objects are finalized.

```scheme
(start-guardian-thread!)   ; call at program start
(stop-guardian-thread!)    ; call at program end
```

---

## `(std foreign bind)` — Higher-Level Organization

### `define-c-library` — C library with header parsing

```scheme
(define-c-library name
  [(shared-lib "libname.so")]
  (bind scheme-name (c-arg-type ...) -> c-ret-type)
  ...)
```

Similar to `define-ffi-library` but uses the C-style type names directly.

### `defstruct/foreign` — Scheme struct backed by C memory

```scheme
(defstruct/foreign name
  (field c-type) ...)
```

Creates a struct where fields map to offsets in a C-allocated block.
The struct is automatically freed when GC'd (uses a guardian).

```scheme
(import (chezscheme) (std foreign bind))

(defstruct/foreign point3d
  (x double)
  (y double)
  (z double))

(let ([p (make-point3d 1.0 2.0 3.0)])
  (printf "~a ~a ~a~%"
    (point3d-x p)
    (point3d-y p)
    (point3d-z p)))
```

### `make-ffi-thread-pool` — non-blocking C calls

Blocking C calls (disk I/O, database queries, etc.) would block the entire
Chez Scheme runtime. Use an FFI thread pool to offload them to OS threads.

```scheme
(make-ffi-thread-pool n-workers)      ; create pool with n-workers threads
(ffi-thread-pool-call pool thunk)     ; submit thunk, returns a promise
(ffi-thread-pool-shutdown! pool)      ; drain and stop all workers
```

```scheme
(import (chezscheme) (std foreign bind) (std misc completion))

(define pool (make-ffi-thread-pool 4))

;; Blocking database query on a pool thread
(define (query-async sql)
  (ffi-thread-pool-call pool
    (lambda ()
      (db-query sql))))   ; db-query is a blocking C call

;; Fire off multiple queries in parallel
(define results
  (map (lambda (q)
         (query-async q))
       '("SELECT * FROM users"
         "SELECT * FROM orders"
         "SELECT * FROM products")))

;; Wait for all
(for-each (lambda (p) (display (completion-wait! p))) results)

(ffi-thread-pool-shutdown! pool)
```

### `define-foreign/async` — async wrapper generator

```scheme
(define-foreign/async scheme-name pool
  (c-function-name arg-type ...) -> ret-type)
```

Automatically wraps the foreign call in a thread pool call, returning a promise.

```scheme
(define pool (make-ffi-thread-pool 4))

(define-foreign/async read-file-async pool
  (read_file_blocking string) -> string)

;; Returns a promise immediately; file read happens on pool thread
(define p (read-file-async "/large/file.dat"))
;; ... do other work ...
(define content (completion-wait! p))
```

---

## Safety Guidelines

1. **Always use `with-foreign-resource`** for manually allocated memory — prevents leaks
2. **Never store raw pointers** as Scheme values — use `define-foreign-type` wrapper
3. **Don't call blocking C from the main thread** — use `ffi-thread-pool-call`
4. **Call `start-guardian-thread!` once** at program startup to enable auto-cleanup
5. **Strings**: Chez automatically converts `string` ↔ `const char*` with UTF-8 encoding.
   The C string is only valid for the duration of the call — don't store it.
6. **Bytevectors** as buffers: pass with `(bytevector-address bv)` and `(bytevector-length bv)`

---

## Complete Example: Binding libsqlite3

```scheme
(import (chezscheme) (std foreign) (std foreign bind))

(start-guardian-thread!)

;; Load and bind SQLite3
(define-ffi-library sqlite3
  (shared-lib "libsqlite3.so.0")
  (bind sqlite3-open     (string ptr) -> int)
  (bind sqlite3-close    (ptr)        -> int)
  (bind sqlite3-exec     (ptr string ptr ptr ptr) -> int)
  (bind sqlite3-errmsg   (ptr)        -> string))

;; Open a database
(let* ([db-ptr (foreign-alloc (foreign-sizeof 'ptr))]
       [rc     (sqlite3-open ":memory:" db-ptr)])
  (when (not (= rc 0))
    (error 'sqlite3-open "failed to open database" rc))
  (let ([db (foreign-ref 'ptr db-ptr 0)])
    ;; Create a table
    (sqlite3-exec db "CREATE TABLE t (x INT)" 0 0 0)
    (sqlite3-exec db "INSERT INTO t VALUES (42)" 0 0 0)
    ;; Close
    (sqlite3-close db))
  (foreign-free db-ptr))
