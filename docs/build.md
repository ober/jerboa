# `(jerboa build)` and `(jerboa cache)` — Native Binary Toolchain

Jerboa's build system compiles Chez Scheme source files into standalone native
binaries. The pipeline embeds Chez boot files and compiled code into a C
translation unit, links it against the Chez runtime, and optionally strips all
dynamic-library dependencies with musl libc.

Two libraries cooperate:

| Library | Role |
|---------|------|
| `(jerboa build)` | Compilation pipeline, cross-compilation, static linking |
| `(jerboa cache)` | Content-addressed `.so` cache keyed on source + deps + Chez version |

---

## Part 1: `(jerboa build)`

### Imports

```scheme
(import (jerboa build))
```

---

### Step 41 — Incremental Parallel Build Pipeline

#### `trace-imports`

```scheme
(trace-imports source-path) → list-of-import-specs
```

Reads `source-path` and returns every `(import ...)` spec found in the file as
a list of S-expressions. The file is read form-by-form; any read error causes
an early return of the forms collected so far. This is used to determine which
modules a source file depends on before compilation begins.

```scheme
(trace-imports "myapp/main.sls")
;; => ((chezscheme) (myapp util) (myapp model))
```

---

#### `compute-file-hash`

```scheme
(compute-file-hash path) → string or #f
```

Computes a 64-bit FNV-1a hash of the entire file contents and returns it as a
lowercase hex string. Returns `"empty"` for zero-length files and `#f` if the
file cannot be read. The hash is used as a cheap change-detection signal — it
is **not** a cryptographic hash.

```scheme
(compute-file-hash "lib/myapp/util.sls")
;; => "3b0c2d4f9a1e6c8d"
```

---

#### `module-changed?`

```scheme
(module-changed? path hash-table) → boolean
```

Returns `#t` if the current hash of `path` differs from the value stored in
`hash-table` under the same key, or if no entry exists yet. Used by
`build-project` to skip recompiling files whose content has not changed.

```scheme
(define ht (make-hashtable equal-hash equal?))
(module-changed? "lib/myapp/util.sls" ht)  ;; => #t  (not seen before)
;; ... after recording the hash ...
(module-changed? "lib/myapp/util.sls" ht)  ;; => #f  (unchanged)
```

---

#### `compile-modules-parallel`

```scheme
(compile-modules-parallel paths compile-fn) → alist of (path . result)
```

Spawns one Chez thread per path using `fork-thread`. Each thread calls
`(compile-fn path)` and stores its result (or exception) in a shared vector.
After all threads finish (signalled via a mutex-guarded condition variable), any
captured error is re-raised in the calling thread. Returns an alist mapping each
path to its compile result.

```scheme
(compile-modules-parallel
  '("lib/a.sls" "lib/b.sls" "lib/c.sls")
  (lambda (path)
    (compile-library path)))
;; => (("lib/a.sls" . #t) ("lib/b.sls" . #t) ("lib/c.sls" . #t))
```

---

#### `build-project`

```scheme
(build-project source-paths output-path [parallel: boolean]) → output-path
```

Incremental build for a list of source files. Checks each file against the
module-level content hash table. Only files that have changed since last build
are recompiled. When `parallel:` is `#t` (the default), changed files are
compiled concurrently via `compile-modules-parallel`.

```scheme
(build-project
  '("lib/myapp/util.sls"
    "lib/myapp/model.sls"
    "lib/myapp/main.sls")
  "build/myapp"
  'parallel: #t)
;; Prints:
;;   Recompiling 2 module(s)...
;;   [compile] lib/myapp/model.sls
;;   [compile] lib/myapp/main.sls
;; => "build/myapp"
```

If all files are up to date, prints `[up to date] build/myapp` and returns
immediately.

---

#### `file->c-array`

```scheme
(file->c-array file-path var-name) → string
```

Reads a binary file and returns a C source string containing a
`static const unsigned char var-name[]` array initialiser, with the bytes laid
out 16 per line in `0xNN` hex notation, followed by a
`static const unsigned int var-name_len` constant. Used internally by
`build-binary` to embed boot files.

```scheme
(display (file->c-array "/usr/lib/csv10.0.0/ta6le/petite.boot" "petite_boot"))
;; static const unsigned char petite_boot[] = {
;; 0x7f,0x45,0x4c,0x46,0x02,0x01,0x01,0x00,...
;; };
;; static const unsigned int petite_boot_len = 1234567;
```

---

#### `generate-main-c`

```scheme
(generate-main-c boot-arrays program-array link-libs) → string
```

Generates a complete C `main()` that initialises Chez Scheme, registers each
boot file from its embedded byte array via `Sregister_boot_file_bytes`, builds
the heap with `Sbuild_heap`, and tears down cleanly. On Linux it includes the
`memfd_create` helper for in-memory boot loading.

Parameters:
- `boot-arrays` — list of C array strings (output of `file->c-array`) for
  `petite.boot`, `scheme.boot`, and `app.boot` in that order.
- `program-array` — optional C array string for a compiled `.so` embedded as
  data, or `#f`.
- `link-libs` — reserved list (currently unused in output).

---

#### `build-boot-file`

```scheme
(build-boot-file output-path deps so-path) → void
```

Thin wrapper around Chez's `make-boot-file`. Creates a boot file at
`output-path` that chains the listed `deps` (e.g. `'("petite" "scheme")`) and
embeds the compiled `.so` at `so-path`.

```scheme
(build-boot-file "/tmp/myapp.boot" '("petite" "scheme") "/tmp/myapp.so")
```

---

#### `build-binary`

```scheme
(build-binary source-path output-path
              [optimize-level: integer]
              [release: boolean]
              [static: boolean]
              [target: cross-target-or-#f])
→ output-path
```

The main entry point for producing a single native binary. Executes the full
five-stage pipeline:

1. **Compile** — calls `compile-program` on `source-path`, producing a `.so`
   in a temporary build directory. Uses `optimize-level:` (default `2`); in
   release mode, `optimize-level` is forced to `3` and inspector information is
   suppressed.
2. **Boot** — locates `petite.boot` and `scheme.boot` under standard Chez
   install paths (respects `$SCHEMEHEAPDIRS`) and creates `app.boot` from the
   compiled `.so`.
3. **C generation** — calls `generate-main-c` with all three boot files
   embedded as C arrays.
4. **Link** — compiles the generated `main.c` with GCC (or the
   `cross-target-cc` when `target:` is given). Uses `musl-link-flags` when
   `static:` is `#t`, otherwise links with `-lm -ldl -lpthread`.
5. **Report** — prints `Built: <output-path>` on success.

```scheme
;; Simple debug build
(build-binary "src/hello.sls" "bin/hello")

;; Optimised release build
(build-binary "src/hello.sls" "bin/hello"
              'release: #t)

;; Static zero-dependency binary
(build-binary "src/hello.sls" "bin/hello"
              'static: #t)

;; Cross-compile for aarch64
(build-binary "src/hello.sls" "bin/hello-arm"
              'target: target-linux-aarch64)
```

---

### Step 42 — Release Builds with Tree Shaking (WPO)

Chez Scheme's whole-program optimiser (`compile-whole-program`) performs
inter-procedural analysis and dead-code elimination. `(jerboa build)` exposes
this as the "release" build mode.

#### `wpo-compile`

```scheme
(wpo-compile source-path output-path) → void
```

Direct interface to `compile-whole-program` with maximum settings:
`optimize-level` 3, `cp0-effort-limit` 1000, inspector information disabled.
Raises on error.

```scheme
(wpo-compile "src/myapp.sls" "build/myapp.wpo")
```

---

#### `build-release`

```scheme
(build-release source-paths output-path
               [optimize-level: integer]
               [wpo-output: string])
→ wpo-output-path or #f
```

Higher-level release build over multiple source files. Uses `compile-whole-program`
on the **first** element of `source-paths` (the program entry point) with:
- `optimize-level` defaulting to `3`
- `cp0-effort-limit` 100
- `generate-inspector-information` disabled
- `compile-imported-libraries` enabled

The WPO output file defaults to `output-path` with a `.wpo` suffix appended.
Returns the WPO output path on success, `#f` if an error occurs (the error
message is printed but not re-raised).

```scheme
(build-release
  '("src/main.sls" "src/util.sls" "src/model.sls")
  "bin/myapp")
;; Prints:
;;   [release] WPO compile (3 sources)
;;   [release] WPO: bin/myapp.wpo
;; => "bin/myapp.wpo"
```

---

#### `tree-shake-imports`

```scheme
(tree-shake-imports source-path) → list-of-import-specs
```

Reads `source-path` and returns all `import` specs while simultaneously walking
every form to collect used symbols into an `eq?` hashtable. The symbol table is
built but not yet used to filter imports — the function returns the import list
as-is. Intended as a static analysis aid; the collected usage information is
available for downstream filtering in a future pass.

```scheme
(tree-shake-imports "src/myapp.sls")
;; => ((chezscheme) (myapp util) (myapp model))
```

---

### Step 43 — Cross-Compilation

Cross-compilation in `(jerboa build)` is done by substituting the host C
compiler with a cross-toolchain wrapper specified in a `cross-target` record.

#### `make-cross-target`

```scheme
(make-cross-target os arch cc ar) → cross-target
```

Creates a cross-target descriptor. `os` and `arch` are symbols; `cc` and `ar`
are strings naming the cross-compiler and archiver executables.

```scheme
(make-cross-target 'linux 'aarch64 "aarch64-linux-gnu-gcc" "aarch64-linux-gnu-ar")
```

#### `cross-target?`

```scheme
(cross-target? x) → boolean
```

Returns `#t` if `x` is a cross-target record.

#### Accessors

| Procedure | Returns |
|-----------|---------|
| `(cross-target-os t)` | OS symbol (e.g. `'linux`, `'macos`) |
| `(cross-target-arch t)` | Architecture symbol (e.g. `'x86-64`, `'aarch64`) |
| `(cross-target-cc t)` | C compiler executable string |
| `(cross-target-ar t)` | Archiver executable string |

#### Predefined targets

| Binding | OS | Arch | CC | AR |
|---------|----|------|----|----|
| `target-linux-x64` | `linux` | `x86-64` | `x86_64-linux-gnu-gcc` | `x86_64-linux-gnu-ar` |
| `target-linux-aarch64` | `linux` | `aarch64` | `aarch64-linux-gnu-gcc` | `aarch64-linux-gnu-ar` |
| `target-macos-x64` | `macos` | `x86-64` | `o64-clang` | `x86_64-apple-darwin-ar` |
| `target-macos-aarch64` | `macos` | `aarch64` | `oa64-clang` | `arm64-apple-darwin-ar` |

#### `compile-for-target`

```scheme
(compile-for-target target c-path output-path [extra-flags]) → (values rc cmd)
```

Compiles a C file `c-path` to `output-path` using the target's C compiler.
Adds platform-appropriate flags automatically:
- Linux: `-fPIE -pie`
- macOS: `-mmacosx-version-min=11.0`

Returns two values: the shell return code and the full command string (useful
for debugging).

```scheme
(define-values (rc cmd)
  (compile-for-target target-linux-aarch64
    "/tmp/myapp/main.c"
    "bin/myapp-arm64"))

(when (not (= rc 0))
  (error 'build "cross-compile failed" cmd))
```

---

### Step 44 — Static Linking

#### `static-link-flags`

```scheme
(static-link-flags static-libs) → string
```

Returns GCC flags for a fully static build using glibc: `-static -static-libgcc`
followed by each archive in `static-libs` (space-separated), then
`-lm -lpthread -ldl`.

```scheme
(static-link-flags '("libcsv.a" "libm.a"))
;; => "-static -static-libgcc libcsv.a libm.a -lm -lpthread -ldl"
```

---

#### `musl-link-flags`

```scheme
(musl-link-flags static-libs) → string
```

Returns link flags for a musl libc static build. If `musl-gcc` or
`x86_64-linux-musl-gcc` is found on `$PATH`, returns `-static <archives> -lm
-lpthread`. Otherwise falls back to `static-link-flags`-style glibc static
flags. Musl-linked binaries have no runtime dependency on glibc.

```scheme
(musl-link-flags '())
;; => "-static -lm -lpthread"  (if musl-gcc is available)
```

---

#### `build-static-binary`

```scheme
(build-static-binary source-path output-path [options ...]) → output-path
```

Convenience wrapper: calls `build-binary` with `static: #t` prepended to the
option list. All other `build-binary` keyword options are accepted.

```scheme
(build-static-binary "src/server.sls" "bin/server-static")
```

---

#### `link-static-archives`

```scheme
(link-static-archives archives output-ar) → (values rc cmd)
```

Combines multiple `.a` archive files into a single fat archive using `ar crs`.
Raises an error if `archives` is empty. Returns the shell return code and the
`ar` command string.

```scheme
(link-static-archives
  '("build/libruntime.a" "build/libscheme.a")
  "build/libfull.a")
```

---

## Part 2: `(jerboa cache)`

### Imports

```scheme
(import (jerboa cache))
```

The compilation cache stores compiled `.so` files in a content-addressed
directory keyed by a 128-bit hash of `source-content || dep-hashes ||
chez-version || opt-level`. A cache hit copies the stored file directly to the
output path, skipping recompilation entirely.

---

### Cache Layout

```
~/.jerboa/cache/
    <hex128>.so      ← one file per unique (source, deps, version, opt) tuple
```

The directory is created lazily on first `cache-store!`.

---

### `cache-directory`

```scheme
(cache-directory)          → string (current directory)
(cache-directory "/path")  → sets the directory for this thread
```

A `make-parameter` defaulting to `$HOME/.jerboa/cache`. Override it for
testing or CI environments:

```scheme
(parameterize ([cache-directory "/tmp/ci-cache"])
  (with-compilation-cache ...))
```

---

### `cache-key`

```scheme
(cache-key source-path dep-hashes opt-level) → string
```

Computes a 128-bit hex cache key by hashing:
- The full text content of `source-path`
- Each string in `dep-hashes` concatenated in order (`#f` values become `""`)
- The decimal string of `opt-level`
- The Chez Scheme version string

Uses a dual-stream FNV-1a variant (two independent hash accumulators) producing
a 32-character hex string.

```scheme
(cache-key "lib/myapp/util.sls"
           '("3b0c2d4f" "9a1e6c8d")
           2)
;; => "a3f7c2910b4e8d1f6a3b9c1e7f4d2a5b"
```

---

### `cache-lookup`

```scheme
(cache-lookup key) → path or #f
```

Returns the absolute path to the cached `.so` if the key exists in the cache
directory, `#f` otherwise. Does not copy the file.

---

### `cache-store!`

```scheme
(cache-store! key so-path) → void
```

Copies the `.so` at `so-path` into the cache under `key`. A no-op if the entry
already exists (content-addressed storage is idempotent). Creates the cache
directory if it does not exist.

---

### `with-compilation-cache`

```scheme
(with-compilation-cache source-path output-path dep-hashes opt-level compile-thunk)
→ output-path
```

The primary high-level interface. On a cache hit, copies the cached `.so` to
`output-path` and returns immediately without calling `compile-thunk`. On a
miss, calls `compile-thunk` (which must produce `output-path`), then stores the
result in the cache.

```scheme
(with-compilation-cache
  "lib/myapp/util.sls"
  "/tmp/myapp-build/util.so"
  '()       ;; no dependency hashes yet
  2         ;; optimize-level
  (lambda ()
    (compile-library "lib/myapp/util.sls" "/tmp/myapp-build/util.so")))
```

---

### `cache-stats`

```scheme
(cache-stats) → (values count total-bytes)
```

Returns the number of entries in the cache and their combined byte size.
Returns `(values 0 0)` if the cache directory does not exist.

```scheme
(define-values (n bytes) (cache-stats))
(printf "Cache: ~a entries, ~a MB~%" n (/ bytes 1048576.0))
```

---

### `cache-clear!`

```scheme
(cache-clear!) → void
```

Deletes every file in the cache directory. The directory itself is preserved.

```scheme
(cache-clear!)
;; Cache is now empty
```

---

### How the Cache Works

1. **Key derivation** — `cache-key` concatenates the source file's full text,
   all dependency hash strings, the opt-level digit, and the Chez version
   string, then runs dual-stream FNV-1a to produce a 128-bit hex digest. This
   means any change to source content, a dependency, the Chez runtime version,
   or the optimisation level produces a different key, forcing a fresh compile.

2. **Content-addressed storage** — the key is used as a filename (`<key>.so`)
   directly. There is no metadata index; existence of the file is the hit
   signal. Multiple processes can safely write to the cache concurrently
   because `cache-store!` skips the write when the destination already exists.

3. **Eviction** — there is no automatic eviction. Use `cache-clear!` or prune
   old entries manually with `cache-stats` + `directory-list`.

---

## Complete Examples

### Build a Hello World Binary

```scheme
(import (jerboa build))

;; hello.sls
;; (import (chezscheme))
;; (display "Hello, world!\n")
;; (exit)

(build-binary "hello.sls" "bin/hello")
;; [1/5] Compiling hello.sls...
;; [2/5] Boot files...
;; [3/5] Generating C...
;; [4/5] Linking bin/hello...
;; Built: bin/hello
```

### Incremental Build of a Multi-File Project

```scheme
(import (jerboa build))

(define sources
  '("lib/myapp/util.sls"
    "lib/myapp/db.sls"
    "lib/myapp/api.sls"
    "lib/myapp/main.sls"))

;; First run: compiles all 4
(build-project sources "bin/myapp")

;; Second run after editing db.sls only: compiles 1
(build-project sources "bin/myapp")
;; Recompiling 1 module(s)...
;; [compile] lib/myapp/db.sls
```

### Cross-Compile for Linux aarch64

```scheme
(import (jerboa build))

(build-binary "src/server.sls" "dist/server-arm64"
              'target: target-linux-aarch64)
;; Uses aarch64-linux-gnu-gcc + -fPIE -pie
```

### Static musl Binary (Zero Dependencies)

```scheme
(import (jerboa build))

;; Build a binary that runs on any Linux without glibc
(build-static-binary "src/tool.sls" "dist/tool-static")

;; Verify
;; $ ldd dist/tool-static
;; => not a dynamic executable
```

### Caching a Compilation

```scheme
(import (jerboa build) (jerboa cache))

(define src "lib/heavy.sls")
(define out "/tmp/heavy.so")

;; Compute hashes of dependencies first
(define dep-hashes
  (map compute-file-hash '("lib/dep1.sls" "lib/dep2.sls")))

(with-compilation-cache src out dep-hashes 2
  (lambda ()
    (compile-library src out)))
;; First call: compiles and stores in cache
;; Subsequent calls: cache hit, copies from ~/.jerboa/cache/
```

### Release Build with WPO

```scheme
(import (jerboa build))

(build-release
  '("src/app.sls")
  "bin/app-release"
  'optimize-level: 3
  'wpo-output: "bin/app.wpo")
;; [release] WPO compile (1 sources)
;; [release] WPO: bin/app.wpo

;; Then link the WPO output as a boot file
(build-binary "src/app.sls" "bin/app-release"
              'release: #t)
```
