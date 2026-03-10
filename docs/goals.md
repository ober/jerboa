# Making Jerboa (Gerbil-on-Chez) Superior to Other Schemes/Lisps

## Strategic Advantages to Exploit

### 1. True SMP Concurrency with Ergonomic Syntax

**The gap**: Chez has real OS threads and SMP. Gerbil has actors/channels syntax. But currently threading.sls is just a thin SRFI-18 shim. Nobody in Scheme-land has truly ergonomic parallel programming.

**The opportunity**: Build a work-stealing scheduler on Chez's native threads with Gerbil's actor syntax as the front-end. Think Go's goroutines but with Gerbil's `spawn`, channels, and `select`. Chez's GC is already thread-safe. You'd have:

```scheme
(spawn (lambda () (channel-put ch (heavy-computation))))
(for/collect ([x (in-channel ch)]) (process x))
```

**Why this wins**: Racket CS has green threads but no true SMP parallelism in user code. Gambit has SMP but it's fragile. Guile has Fibers but limited. Chez alone has robust SMP but no ergonomic API. You'd be the only Scheme with both.

---

### 2. Zero-Copy FFI with Chez's Native Calling Convention

**The gap**: FFI is currently stubbed. But Chez's `foreign-procedure` is one of the fastest FFIs in any Scheme -- direct C calling convention, no marshaling for simple types.

**The opportunity**: Build a Gerbil-syntax FFI that compiles to Chez's native foreign calls. Something like:

```scheme
(extern libsqlite3
  (sqlite3_open (string (* void)) -> int)
  (sqlite3_exec ((* void) string (* void) (* void) (* (* char))) -> int))
```

Compile-time type checking, automatic resource cleanup via `unwind-protect`, and GC-safe pinning. Chez's `foreign-callable` lets C call back into Scheme with full GC -- exploit this for event-driven libraries.

**Why this wins**: Racket's FFI has overhead. Gambit's is capable but requires C stub files. Chez's is the fastest but has no high-level DSL. You could have the speed of Chez's FFI with the ergonomics of Gerbil's macro system.

---

### 3. Ahead-of-Time Native Binaries with Tree Shaking

**The gap**: `jerboa-make-binary` exists in skeleton form. Chez can produce standalone executables via `compile-whole-program`. But nobody in Scheme-land does proper dead code elimination + native binary in one step.

**The opportunity**: Since the compiler already tracks module dependencies via the loader, you have the dependency graph. Add:
- Whole-program compilation via `compile-whole-program`
- Dead export elimination (you know what's imported where)
- Single static binary output (no .boot file needed)
- Startup time measured in microseconds, not milliseconds

```
$ jerboa build --static myapp.ss -o myapp
$ ldd myapp
  not a dynamic executable
$ time ./myapp
  real 0.003s
```

**Why this wins**: Go and Rust win converts partly on "single binary deployment." No Scheme does this well. Racket CS binaries are 30+ MB with slow startup. Gambit can do it but the tooling is painful. A `jerboa build` that produces a 2MB static binary starting in 3ms would be a category killer for CLI tools and microservices.

---

### 4. First-Class Structured Concurrency

**The gap**: No Scheme has structured concurrency (nurseries/task groups a la Trio/Java 21). Gerbil's actors are fire-and-forget.

**The opportunity**: Build structured concurrency as a core primitive:

```scheme
(with-task-group
  (lambda (tg)
    (task-group-spawn tg (lambda () (fetch-url url1)))
    (task-group-spawn tg (lambda () (fetch-url url2)))
    ;; both complete or both cancel when scope exits
    ))
```

Built on Chez's threads + Chez's delimited continuations for cancellation. The scope guarantees no leaked goroutines, no orphan threads. This is what Go, Erlang, and most actor systems get wrong.

**Why this wins**: This is cutting-edge in every language. Java just got it in Java 21. Python has Trio. No Lisp/Scheme has it. You'd be first.

---

### 5. Module System with Hermetic Builds

**The gap**: The module loader already caches to `/tmp/jerboa-modules/` with timestamp invalidation. But it's ad-hoc.

**The opportunity**: Content-addressed module cache. Hash the source + dependencies -> deterministic output. This gives you:
- Reproducible builds (same source -> same binary, always)
- Distributed build cache (share compiled artifacts across machines)
- Incremental recompilation (only rebuild what changed)
- Parallel module compilation (Chez's thread safety enables this)

```
/cache/
  abc123.so  <- hash of (std/sort) source + deps
  def456.so  <- hash of (std/text/json) source + deps
```

**Why this wins**: Racket has a compilation manager but it's filesystem-timestamp-based and single-threaded. Nobody has content-addressed Scheme builds. This is what Bazel/Nix do for C++ -- apply it to Scheme.

---

### 6. Gradual Typing That Doesn't Suck

**The gap**: Typed Racket exists but imposes 10-100x overhead at typed/untyped boundaries. No other Scheme has gradual typing.

**The opportunity**: Since the compiler controls code generation, you can:
- Add optional type annotations that compile to Chez assertions in debug mode
- Eliminate type checks entirely in release mode
- Use Chez's profile-guided optimization data to specialize hot paths

```scheme
(def (fibonacci [n : fixnum]) : fixnum
  (if (fx< n 2) n
      (fx+ (fibonacci (fx- n 1)) (fibonacci (fx- n 2)))))
```

Annotations are optional. When present, the compiler emits specialized code. No contracts at module boundaries -- just direct calls. Zero overhead in release mode.

**Why this wins**: Typed Racket's boundary costs are its fatal flaw. Common Lisp has `declare` but it's ugly and compiler-dependent. The position between Gerbil's syntax and Chez's optimizer is ideal for this.

---

### 7. Embeddable Runtime

**The gap**: No Scheme is easy to embed as a library in C/C++/Rust applications the way Lua is.

**The opportunity**: Chez is already a C library (`scheme.h`). Build a clean embedding API:

```c
jerboa_t *j = jerboa_new();
jerboa_eval(j, "(def greeting \"hello\")");
const char *s = jerboa_get_string(j, "greeting");
jerboa_call(j, "my-function", 2, jerboa_int(42), jerboa_string("foo"));
jerboa_destroy(j);
```

Multiple independent instances, each with their own heap. Thread-safe. This opens up the "scripting language for applications" niche that Lua dominates and Guile targets but fails at (too heavy).

---

### 8. LSP + IDE Integration from Day One

**The gap**: Scheme IDE support is universally terrible. Even Racket's is mediocre outside DrRacket.

**The opportunity**: The compiler already has source locations from the reader, module dependency graphs from the loader, and type information from the MOP. Wire this into an LSP server:
- Go-to-definition (you track where things are defined)
- Completion (you know module exports)
- Inline errors (the compiler gives file/line/column)
- Hover types (from the MOP's class info)

An LSP server written *in Jerboa itself* that's fast because it runs on Chez.

---

## Prioritized Roadmap

If picking the **top 3** that would create the most distance from the competition:

| Priority | Feature                                  | Why                                              |
|----------|------------------------------------------|--------------------------------------------------|
| **1**    | SMP actors + structured concurrency      | Unique selling point; no Scheme has this         |
| **2**    | Static native binaries with tree shaking | Practical; wins converts from Go/Rust            |
| **3**    | Zero-overhead FFI DSL                    | Unlocks real-world libraries (SQLite, TLS, etc.) |

Everything else (gradual types, LSP, embedding) is valuable but can come later. The concurrency story + deployment story + C interop story are what make people choose a language for real projects vs. hobby use.

---

## What You Already Have That Others Don't

Don't underestimate what's already unique:
- **Gerbil's syntax on Chez's runtime** -- nobody else has this combination
- **A self-hosting compiler in ~1100 lines** -- Racket CS's equivalent is 50K+ lines
- **51 stdlib modules** -- practical coverage of crypto, db, networking, OS
- **8 chez-* FFI libraries** -- sqlite, postgresql, crypto, epoll, inotify, ssl, zlib, pcre2
- **Subprocess-batched testing** -- the OOM solution is actually a good architecture for parallel test execution

The foundation is strong. The question is whether to go deep on making the existing modules fully functional (practical completeness) or go wide on the differentiators above. Recommendation: get FFI working (item 3) because it unblocks items 1 and 2, then build the concurrency story on top.
