# World-Class REPL & Standard Library Expansion

## 1. SLIME-Inspired REPL (`lib/std/repl.sls`)

The REPL went from a basic 425-line read-eval-print loop to a **1500-line interactive powerhouse** modeled after Emacs SLIME for Common Lisp.

**Why it rocks:** Common Lisp developers rave about SLIME because it makes the language *feel alive*. Jerboa now has that same energy:

- **Value history** (`*`, `**`, `***`, `$1`, `$2`...) — Never lose a computed result. Refer back to any previous value by number. This is the #1 thing people miss when moving from CL to other Schemes.
- **Deep object inspector** — Drill into any value: hashtables show entries, records show fields, closures show captured names. Essential for understanding complex data at the REPL.
- **Function tracing** — Wrap any function to see calls/returns with args. Debug without adding print statements.
- **Built-in profiling & benchmarking** — Measure wall time, CPU time, memory allocation, GC pressure. No external tools needed.
- **Tab completion** — Complete any symbol in the environment. Makes discovery effortless.
- **Inline documentation** — `,doc car` gives you docs instantly. Register your own with `register-doc!`.
- **Apropos search** — `,apropos string` finds every symbol containing "string". Perfect for exploration.
- **Data engineering commands** — `,table` for formatted tables, `,stats` for descriptive statistics, `,freq` for frequency tables, `,json` for JSON output. Turn your REPL into a data workbench.
- **Balanced paren check** — Correctly handles strings and comments, so `")"` inside a string doesn't confuse it.
- **Persistent history** — Saved to `~/.jerboa_history` across sessions.

---

## 2. SWANK-Like TCP Server (`lib/std/repl/server.sls`)

A TCP server that speaks an s-expression protocol, enabling **editor integration**.

**Why it rocks:** This is the bridge between jerboa and editors like Emacs. Any editor that can open a TCP socket can:

- Evaluate code remotely and get structured results
- Get tab completions
- Look up documentation
- Expand macros
- Navigate the filesystem
- Query memory usage and thread info

The protocol uses `(id method args...) → (id :ok result)` — dead simple to implement on the editor side. Port discovery via `~/.jerboa-repl-port` means editors auto-connect. Multi-threaded so multiple editor connections work simultaneously.

---

## 3. REPL Middleware (`lib/std/repl/middleware.sls`)

An extensibility layer for the REPL — register custom commands, printers, input transformers, and eval hooks.

**Why it rocks:** Every REPL eventually needs customization. Instead of forking the REPL code, middleware lets users:

- Add `,mycommand` commands without touching core REPL code
- Register custom pretty-printers for their record types
- Transform input (e.g., `!ls` → `(system "ls")`)
- Hook into pre/post eval for logging, timing, or side effects
- Customize the prompt

This is the pattern that made Express.js and Rack successful — composable middleware.

---

## 4. Notebook System (`lib/std/repl/notebook.sls`)

Jupyter-style literate programming for Scheme. Save REPL sessions as executable `.ss.nb` files with markdown documentation.

**Why it rocks:** Data scientists live in notebooks. This brings that workflow to Scheme:

- Mix code cells with markdown documentation
- Capture outputs alongside code
- Export to HTML (shareable reports) or Markdown (documentation)
- Record live sessions — start recording, do your work, stop, save
- Files are valid Scheme — you can `load` them directly

---

## 5. Shell Execution (`lib/std/os/shell.sls`)

High-level shell command execution with multiple output modes.

**Why it rocks:** Every scripting language needs easy shell access. This gives you:

- `(shell "ls -la")` — just get stdout as a string
- `(shell! "make build")` — raise on failure (fail-fast scripting)
- `(shell/lines "ls")` — get a list of lines (no manual splitting)
- `(shell/status cmd)` — get stdout, stderr, AND exit code separately
- `(shell-pipe "ls" "grep .ss" "wc -l")` — Unix pipes as function args
- `(shell-env cmd alist)` — run with custom environment
- `(shell-async cmd)` — background execution with later collection

Replaces 50 lines of `open-process-ports` boilerplate with one-liners.

---

## 6. Template Engine (`lib/std/text/template.sls`)

Mustache-inspired string templates with sections, iteration, and conditionals.

**Why it rocks:** Code generation, email templates, report formatting — templates are everywhere. This handles:

- `{{name}}` variable substitution
- `{{#items}}...{{/items}}` iteration over lists
- `{{#flag}}...{{/flag}}` conditional sections
- `{{^empty}}fallback{{/empty}}` inverted sections
- Compile once, render many times (fast)
- Works with both symbol and string alist keys

No external dependencies. No regex. Just clean recursive-descent parsing.

---

## 7. Memoization (`lib/std/misc/memo.sls`)

Memoization with TTL expiry, LRU eviction, and cache introspection.

**Why it rocks:** Memoization is the easiest performance win in functional programming, but most implementations are toy-level. This one is production-grade:

- `(memo fn)` — simple unbounded memoization
- `(memo/lru 1000 fn)` — evicts least-recently-used when cache exceeds size
- `(memo/ttl 60 fn)` — entries expire after N seconds (perfect for API caching)
- `(memo/lru+ttl 1000 60 fn)` — combined: bounded AND time-limited
- `(memo-stats fn)` — hit rate, miss count (is your cache actually helping?)
- `(defmemo (fib n) ...)` — syntax sugar for the common case

---

## 8. Retry with Backoff (`lib/std/misc/retry.sls`)

Exponential backoff, jitter, predicates, and circuit breaker pattern.

**Why it rocks:** Networks fail. APIs return 503. Databases go down. Without retry logic, your program crashes at 3am. This gives you:

- `(retry thunk 5 1.0)` — simple retry with fixed delay
- `(retry/backoff thunk policy)` — exponential backoff with jitter (prevents thundering herd)
- `(retry/predicate thunk pred)` — only retry on specific exceptions
- **Circuit breaker** — after N failures, stop trying for a cooldown period. Prevents cascading failures in distributed systems.

The circuit breaker alone would be a separate library in most ecosystems.

---

## 9. Time Utilities (`lib/std/time.sls`)

High-level time operations that Chez doesn't provide out of the box.

**Why it rocks:** Chez has `current-time` but nothing user-friendly. Now you get:

- `(current-timestamp)` — ISO 8601 string, ready for logs and APIs
- `(elapsed thunk)` — measure how long something takes in one call
- `(time-it "label" thunk)` — print wall + CPU time (like Gerbil's `time`)
- `(duration->string 3661)` — "1h 1m" (human-readable, auto-scales from μs to days)
- **Stopwatch** with lap timing — perfect for benchmarking multi-phase operations
- **Throttle/debounce** — rate-limit function calls (UI patterns, API clients)
- `(with-timeout 5.0 thunk)` — kill long-running operations

---

## 10. Result Monad (`lib/std/misc/result.sls`)

Railway-oriented programming without exceptions.

**Why it rocks:** Exceptions are great for unexpected errors but terrible for expected ones (validation, parsing, user input). Result types let you:

- Chain operations that might fail: `(result-> (ok input) (result-map parse) (result-bind validate))`
- Never forget to handle errors (the type forces you)
- Collect errors from multiple operations: `(results-collect list-of-results)`
- Convert between exceptions and results: `(try->result thunk)`
- Pattern match cleanly: `(result-fold r on-ok on-err)`

This is the pattern that makes Rust, Haskell, and Elixir code so robust.

---

## 11. Glob Pattern Matching (`lib/std/text/glob.sls`)

File glob patterns: `*`, `**`, `?`, `[a-z]`, `[!abc]`.

**Why it rocks:** Every time you need to filter files, you reinvent glob matching. Now it's a library:

- `(glob-match? "*.ss" "hello.ss")` — pure pattern matching (no filesystem)
- `(glob-filter "*.ss" file-list)` — filter a list
- `(glob-expand "src/**/*.ss")` — actual filesystem expansion with recursive `**`
- `(glob->regex-string pattern)` — convert to regex for interop

Handles all the edge cases: `**` crosses directories, `*` doesn't, character classes with ranges and negation.

---

## 12. Data Validation (`lib/std/misc/validate.sls`)

Composable validators with structured error messages.

**Why it rocks:** Input validation is tedious and error-prone. Combinators make it declarative:

```scheme
(define check-user
  (v-record
    (list (cons 'name (v-and (v-required "name") (v-min-length "name" 1)))
          (cons 'email (v-and (v-required "email") (v-pattern "email" "@")))
          (cons 'age (v-and (v-integer "age") (v-range "age" 0 150))))))

(check-user '((name . "Alice") (email . "a@b.com") (age . 30)))
; => (values #t '())
```

Validators compose with `v-and`/`v-or`, work on records/alists, validate collections with `v-each`, and return all errors at once (not just the first one).

---

## 13. Double-Ended Queue (`lib/std/misc/deque.sls`)

O(1) amortized push/pop on both ends using the classic two-list technique.

**Why it rocks:** Lists are great but you can only efficiently access one end. Deques give you both ends, which is essential for:

- BFS algorithms
- Sliding window problems
- Work-stealing schedulers
- Undo/redo stacks

Plus: `deque-map`, `deque-filter`, `list->deque`, bounded mode.

---

## 14. Path Utilities (`lib/std/os/path-util.sls`)

Higher-level filesystem operations that Chez doesn't provide.

**Why it rocks:** Chez has `directory-list` and `file-exists?` but no recursive operations. Now:

- `(path-walk dir proc)` — Python's `os.walk` for Scheme
- `(path-find dir predicate)` — find files matching any condition
- `(path-glob dir "*.ss")` — find by glob pattern
- `(with-temp-directory proc)` — scoped temp dirs with automatic cleanup
- `(ensure-directory "a/b/c")` — `mkdir -p` equivalent
- `(copy-file src dst)` — binary-safe file copy

---

## 15. Text Diff (`lib/std/text/diff.sls`)

LCS-based line diff with unified output and edit distance.

**Why it rocks:** Testing, debugging, and version comparison all need diff:

- `(diff-lines old new)` — structured diff as `(keep/add/remove line)` entries
- `(diff-unified "a" "b" old new)` — standard unified diff format
- `(edit-distance "kitten" "sitting")` — Levenshtein distance for fuzzy matching
- `(diff-apply old hunks)` — apply a diff to reconstruct the new version
- `(diff-summary hunks)` — count additions, deletions, unchanged

---

## 16. Ring Buffer (`lib/std/misc/ringbuf.sls`)

Fixed-size circular buffer with O(1) operations.

**Why it rocks:** Ring buffers are the backbone of:

- Log rotation (keep last N log entries)
- Audio/signal processing (sliding windows)
- Network packet buffers
- Rate calculation (keep last N timestamps)

When full, new elements silently overwrite the oldest. No allocation, no GC pressure, constant memory.

---

## 17. C-Style Printf (`lib/std/text/printf.sls`)

`%d`, `%s`, `%f`, `%x`, `%o`, `%b`, `%e` with width, precision, padding, and alignment.

**Why it rocks:** Chez's `format` is powerful but uses `~a`/`~s` syntax that nobody outside Scheme knows. When porting C/Python/Go code, you want familiar format strings:

```scheme
(sprintf "%08x" 255)           ; => "000000ff"
(sprintf "%-20s|" "hello")     ; => "hello               |"
(sprintf "%.2f" 3.14159)       ; => "3.14"
(sprintf "%+d" 42)             ; => "+42"
```

Also: `cprintf` for stdout, `fprintf*` for ports, `format-one` for single values.

---

## 18. Binary Heap (`lib/std/misc/heap.sls`)

Min-heap and max-heap priority queue with O(log n) operations.

**Why it rocks:** Priority queues are essential for:

- Dijkstra's algorithm
- Task scheduling (run highest-priority job next)
- Event-driven simulation
- Top-K problems
- Merge K sorted lists

```scheme
(define h (list->heap < '(5 3 1 4 2)))
(heap->sorted-list h)  ; => (1 2 3 4 5)
```

Auto-growing backing array, works with any comparator.

---

## 19. LRU Cache (`lib/std/misc/lru-cache.sls`)

O(1) get/put/evict using hash table + doubly-linked list.

**Why it rocks:** The classic interview question, implemented properly:

- `(lru-cache-get cache key)` — O(1) lookup
- `(lru-cache-put! cache key value)` — O(1) insert with automatic eviction
- Hit/miss stats with hit rate calculation
- Key/value iteration in MRU-to-LRU order
- Thread-safe for read-heavy workloads

More efficient than `memo/lru` when you need a standalone cache without function wrapping.

---

## 20. Event Emitter (`lib/std/misc/event-emitter.sls`)

Node.js-style pub/sub for decoupled architecture.

**Why it rocks:** When module A needs to notify module B without importing it, events are the answer:

- `(on ee 'data handler)` — persistent listener
- `(once ee 'ready handler)` — fire once then auto-remove
- `(emit ee 'data 42)` — fire all handlers
- `(off ee 'data)` — unsubscribe

Error isolation: one handler crashing doesn't prevent others from running. Essential for plugin architectures and reactive programming.

---

## 21. Trie / Prefix Tree (`lib/std/misc/trie.sls`)

Efficient string prefix operations for autocomplete and search.

**Why it rocks:** The REPL completion engine uses linear search. A trie makes prefix lookup O(k) where k is the prefix length, regardless of dictionary size:

- `(trie-prefix-search t "str")` — all words starting with "str"
- `(trie-autocomplete t "he" 10)` — top 10 completions
- `(trie-search t "hello")` — exact membership test
- `(trie-starts-with? t "hel")` — any word with this prefix?

Perfect for command-line autocompletion, spell checking, and IP routing tables.

---

## 22. Token Bucket Rate Limiter (`lib/std/misc/rate-limiter.sls`)

Industry-standard rate limiting algorithm.

**Why it rocks:** When calling external APIs, you need to respect rate limits or get banned:

- Tokens refill at a constant rate
- Burst capacity for short spikes
- `try-acquire` for non-blocking check
- `acquire!` for blocking wait
- `with-rate-limit` for clean wrapping

Used by AWS, Google Cloud, and every major API gateway. Now available in Scheme.

---

## 23. Resource Pool (`lib/std/misc/pool.sls`)

Thread-safe generic resource pool with acquire/release semantics.

**Why it rocks:** Database connections, HTTP clients, file handles — any expensive resource benefits from pooling:

- Creates resources on demand up to max-size
- Reuses idle resources instead of creating new ones
- Blocks when pool is exhausted (backpressure)
- `pool-with-resource` guarantees release via `dynamic-wind`
- `pool-drain!` for graceful shutdown

---

## 24. Finite State Machine (`lib/std/misc/state-machine.sls`)

Declarative FSM with transitions, guards, actions, and history.

**Why it rocks:** State machines are the right abstraction for protocols, UI flows, and workflow engines:

```scheme
(define door (make-state-machine 'locked
  `((locked   (unlock) unlocked ,log-unlock)
    (unlocked (open)   opened   ,log-open)
    (opened   (close)  unlocked ,log-close)
    (unlocked (lock)   locked   ,log-lock))))
```

- Declarative transition table (data, not code)
- Actions fire on transitions
- Guards can prevent transitions conditionally
- Full transition history for debugging
- `sm-can-send?` for UI enable/disable logic
- On-transition callbacks for cross-cutting concerns

---

## Test Coverage

Every module has comprehensive tests:

| Batch | Tests | Modules |
|-------|-------|---------|
| REPL  | 91    | repl, server, middleware, notebook |
| Batch 3 | 94  | shell, template, memo, retry, time |
| Batch 4 | 128 | result, glob, validate, deque, path-util |
| Batch 5 | 105 | diff, ringbuf, printf, heap, lru-cache |
| Batch 6 | 70  | event-emitter, trie, rate-limiter, pool, state-machine |
| **Total** | **488+** | **25 new modules** |
