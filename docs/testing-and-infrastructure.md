# Testing and Infrastructure Libraries

Jerboa standard library modules for testing, profiling, configuration, terminal interaction, and utility infrastructure.

## Table of Contents

- [1. (std test quickcheck) -- Property-Based Testing](#1-std-test-quickcheck----property-based-testing)
- [2. (std test) -- assert! Macro](#2-std-test----assert-macro)
- [3. (std misc profile) -- Profiling Framework](#3-std-misc-profile----profiling-framework)
- [4. (std misc config) -- Hierarchical Configuration](#4-std-misc-config----hierarchical-configuration)
- [5. (std misc terminal) -- Terminal Control / ANSI Codes](#5-std-misc-terminal----terminal-control--ansi-codes)
- [6. (std misc highlight) -- Scheme Syntax Highlighting](#6-std-misc-highlight----scheme-syntax-highlighting)
- [7. (std misc guardian-pool) -- Guardian-Based FFI Cleanup](#7-std-misc-guardian-pool----guardian-based-ffi-cleanup)
- [8. (std misc memoize) -- Memoization with LRU](#8-std-misc-memoize----memoization-with-lru)

---

## 1. (std test quickcheck) -- Property-Based Testing

**Module path:** `(std test quickcheck)`
**Source:** `lib/std/test/quickcheck.sls`

```scheme
(import (std test quickcheck))
```

### Overview

QuickCheck-style property-based testing. A **generator** is a procedure that takes a `size` parameter (non-negative integer) and returns a random value. Larger sizes hint generators to produce larger or more complex values. `check-property` runs a property over many random inputs with increasing sizes and, on failure, attempts to shrink the counterexample to a minimal reproduction.

### API Reference

| Name | Kind | Signature | Description |
|------|------|-----------|-------------|
| `check-property` | procedure | `(check-property n-trials generators prop)` | Run `prop` over `n-trials` random inputs. `generators` is a list of generator procedures. `prop` takes as many args as generators and returns truthy on success. Returns a result alist. |
| `for-all` | macro | `(for-all ([var gen] ...) body ...)` | Sugar for `check-property` with 100 trials. Each `var` is bound to a value from its `gen`. Returns result alist. |
| `quickcheck` | procedure | `(quickcheck n-trials property)` | Run `property` (a `(lambda (gen-fn) ...)`) for `n-trials` times. `gen-fn` takes a generator and returns a random value at the current size. Returns result alist. |
| `make-gen` | procedure | `(make-gen proc)` | Wraps a `(lambda (size) ...)` into a generator. Currently identity; kept for API clarity. |
| **Generators** | | | |
| `gen-int` | generator | `(gen-int size)` | Random integer in `[-size, size]`. |
| `gen-nat` | generator | `(gen-nat size)` | Random non-negative integer in `[0, size]`. |
| `gen-bool` | generator | `(gen-bool size)` | Random boolean. Size is ignored. |
| `gen-char` | generator | `(gen-char size)` | Random printable ASCII character (code 32--126). Size is ignored. |
| `gen-string` | generator | `(gen-string size)` | Random string of length up to `size`, using printable ASCII. |
| `gen-list` | procedure | `(gen-list elem-gen)` | Returns a generator that produces lists of length up to `size`, with elements from `elem-gen`. |
| `gen-vector` | procedure | `(gen-vector elem-gen)` | Returns a generator that produces vectors with elements from `elem-gen`. |
| `gen-one-of` | procedure | `(gen-one-of choices)` | Returns a generator that picks uniformly from a non-empty list of values. |
| `gen-pair` | procedure | `(gen-pair gen-a gen-b)` | Returns a generator producing `(cons (gen-a size) (gen-b size))`. |
| `gen-choose` | procedure | `(gen-choose lo hi)` | Returns a generator producing random integers in `[lo, hi]` inclusive. Size is ignored. |
| **Combinators** | | | |
| `gen-map` | procedure | `(gen-map f gen)` | Returns a generator that applies `f` to the output of `gen`. |
| `gen-bind` | procedure | `(gen-bind gen f)` | Monadic bind: `f` receives a generated value and returns a new generator. |
| `gen-filter` | procedure | `(gen-filter pred gen)` | Returns a generator that retries `gen` until `pred` holds (max 100 tries). |
| `gen-sized` | procedure | `(gen-sized f)` | Size-dependent generator: `f` receives the size and returns a generator. |
| **Shrinking** | | | |
| `shrink-int` | procedure | `(shrink-int n)` | Returns a list of candidate shrinks for integer `n` toward 0. |
| `shrink-list` | procedure | `(shrink-list lst)` | Returns candidate shrunk lists (empty list plus each single-element removal). |
| `shrink-string` | procedure | `(shrink-string s)` | Shrinks a string by shrinking its character list. |

### Result Alist Format

On success:

```scheme
((status . pass) (trials . 100))
```

On failure (from `check-property`):

```scheme
((status . fail) (trial . 7) (original . (inputs ...)) (shrunk . (minimal-inputs ...)))
```

On failure (from `quickcheck`):

```scheme
((status . fail) (trial . 7))
```

### Examples

**Basic property with `for-all`:**

```scheme
(import (std test quickcheck))

;; Addition is commutative
(let ([result (for-all ([x gen-int] [y gen-int])
                (= (+ x y) (+ y x)))])
  (display (cdr (assq 'status result))))  ;; => pass
```

**Detecting a bug with shrinking:**

```scheme
;; This property is false: not all integers are less than 50
(let ([result (for-all ([x gen-nat])
                (< x 50))])
  (when (eq? 'fail (cdr (assq 'status result)))
    (display "Shrunk counterexample: ")
    (display (cdr (assq 'shrunk result)))))
;; Shrunk counterexample: (50)
```

**Using `check-property` directly with custom trial count:**

```scheme
;; Reversing a list twice is identity
(let ([result (check-property 200
                (list (gen-list gen-int))
                (lambda (lst) (equal? lst (reverse (reverse lst)))))])
  (display result))
```

**Custom generator with combinators:**

```scheme
;; Generate even integers
(define gen-even
  (gen-map (lambda (n) (* 2 n)) gen-int))

;; Generate non-empty lists
(define gen-nonempty-list
  (gen-filter pair? (gen-list gen-nat)))
```

**Using `quickcheck` with gen-fn style:**

```scheme
(let ([result (quickcheck 100
                (lambda (gen-fn)
                  (let ([x (gen-fn gen-int)]
                        [y (gen-fn gen-int)])
                    (= (+ x y) (+ y x)))))])
  (display (cdr (assq 'status result))))
```

---

## 2. (std test) -- assert! Macro

**Module path:** `(std test)`
**Source:** `lib/std/test.sls`

```scheme
(import (std test))
```

### Overview

The `assert!` macro provides assertion checking with rich failure diagnostics. On failure, it displays the original expression and the evaluated value of each sub-expression, making it easy to diagnose what went wrong without a debugger. It integrates with the `(std test)` check-counting infrastructure.

### API Reference

| Name | Kind | Signature | Description |
|------|------|-----------|-------------|
| `assert!` | macro | `(assert! expr)` | Assert that `expr` is truthy. On failure, prints the expression. |
| `assert!` | macro | `(assert! (op arg ...))` | Assert that `(op arg ...)` is truthy. On failure, prints each `arg`'s value. |

### Behavior

- **Compound form** `(assert! (op arg1 arg2 ...))`: Each `arg` is evaluated once into a temporary, then `(op tmp1 tmp2 ...)` is tested. On failure, each sub-expression and its value are printed.
- **Simple form** `(assert! expr)`: Evaluates `expr`. On failure, prints the expression text.
- Both forms increment the internal check counter. On success, only the counter increments. On failure, the failure counter also increments and diagnostics are printed to `(current-error-port)`.

### Examples

**Simple assertion:**

```scheme
(import (std test))

(assert! (> 3 2))  ;; passes silently
```

**Compound assertion with diagnostics on failure:**

```scheme
(assert! (= (+ 1 2) 4))
;; Output to stderr:
;;   FAIL: (= (+ 1 2) 4)
;;     (+ 1 2) => 3
;;     4 => 4
```

**Using assert! inside test-case:**

```scheme
(import (std test))

(run-tests!
  (test-suite "math"
    (test-case "addition"
      (assert! (= (+ 2 3) 5))
      (assert! (> (* 3 4) 10)))))
```

**Boolean expression:**

```scheme
(let ([x 10])
  (assert! (even? x)))  ;; passes

(let ([x 7])
  (assert! (even? x)))
;; FAIL: (even? x)
```

---

## 3. (std misc profile) -- Profiling Framework

**Module path:** `(std misc profile)`
**Source:** `lib/std/misc/profile.sls`

```scheme
(import (std misc profile))
```

### Overview

Lightweight profiling framework for measuring function call counts and execution times. Functions defined with `define-profiled` are instrumented to record call count, total time, min time, max time, and average time -- but only when profiling is active (controlled by the `profiling-active?` parameter). When inactive, profiled functions run with zero overhead.

### API Reference

| Name | Kind | Signature | Description |
|------|------|-----------|-------------|
| `define-profiled` | macro | `(define-profiled (name args ...) body ...)` | Define a function that records timing data when `profiling-active?` is `#t`. Zero overhead when inactive. |
| `profiling-active?` | parameter | `(profiling-active?)` / `(profiling-active? bool)` | Controls whether profiled functions collect timing data. Default: `#f`. |
| `profile-reset!` | procedure | `(profile-reset!)` | Clear all collected profiling data. |
| `profile-data` | procedure | `(profile-data)` | Returns profiling data as an alist sorted by total-ms descending. Each entry: `(name . ((count . N) (total-ms . T) (min-ms . M) (max-ms . X) (avg-ms . A)))`. |
| `profile-report` | procedure | `(profile-report)` | Print a formatted table of profiling data to `(current-output-port)`. |
| `with-profiling` | macro | `(with-profiling body ...)` | Resets profile data, enables profiling, runs `body ...`, prints the report, and returns the result of the last body expression. |
| `time-it` | macro | `(time-it expr)` | Evaluate `expr` and return its results plus an extra value: the elapsed time in milliseconds. Uses `values` for multiple return. |

### Examples

**Basic profiling:**

```scheme
(import (std misc profile))

(define-profiled (fib n)
  (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))

(with-profiling
  (fib 25))
;; Prints a table like:
;; ----------------------------------------------------------------------
;; Function             Calls    Total(ms)    Avg(ms)      Min(ms)      Max(ms)
;; ----------------------------------------------------------------------
;; fib                  242785       xxx.xxx      xxx.xxx      xxx.xxx      xxx.xxx
;; ----------------------------------------------------------------------
```

**Manual profiling control:**

```scheme
(define-profiled (compute x)
  (* x x x))

(profile-reset!)
(parameterize ([profiling-active? #t])
  (do ([i 0 (+ i 1)])
    ((= i 1000))
    (compute i)))

(let ([data (profile-data)])
  (for-each
    (lambda (entry)
      (display (car entry))       ;; function name
      (display " called ")
      (display (cdr (assq 'count (cdr entry))))
      (display " times\n"))
    data))
```

**Timing a single expression:**

```scheme
(let-values ([(result elapsed) (time-it (fib 20))])
  (display (format "fib(20) = ~a in ~a ms\n" result elapsed)))
```

---

## 4. (std misc config) -- Hierarchical Configuration

**Module path:** `(std misc config)`
**Source:** `lib/std/misc/config.sls`

```scheme
(import (std misc config))
```

### Overview

Hierarchical s-expression configuration with parent-child cascading. Configs are created from alists and can have a parent config. Key lookups cascade upward: if a key is not found in the child, the parent is consulted. Configs are immutable (functional updates return new configs).

### API Reference

| Name | Kind | Signature | Description |
|------|------|-----------|-------------|
| `make-config` | procedure | `(make-config alist)` / `(make-config alist parent)` | Create a config from an alist, with optional parent config for cascading lookups. |
| `config?` | procedure | `(config? x)` | Returns `#t` if `x` is a config object. |
| `config-ref` | procedure | `(config-ref cfg key)` | Lookup `key`, cascading to parent if not found locally. Raises error if key is missing everywhere. |
| `config-ref/default` | procedure | `(config-ref/default cfg key default)` | Like `config-ref` but returns `default` instead of raising an error. |
| `config-set` | procedure | `(config-set cfg key value)` | Returns a new config with `key` set to `value`. Does not mutate the original. |
| `config-keys` | procedure | `(config-keys cfg)` | Returns all keys including parent keys, no duplicates. |
| `config-merge` | procedure | `(config-merge base override)` | Merge two configs; `override` keys take precedence. Returns a flat config with no parent. |
| `config-from-file` | procedure | `(config-from-file path)` / `(config-from-file path parent)` | Read a config from an s-expression file. The file should contain a single alist. |
| `config-subsection` | procedure | `(config-subsection cfg key)` / `(config-subsection cfg key parent)` | Extract a nested alist value and wrap it as a new config. |
| `config-verify` | procedure | `(config-verify schema cfg)` | Validate config against a schema (alist of `(key . predicate)` pairs). Returns a list of error strings, or `'()` if valid. |
| `config->alist` | procedure | `(config->alist cfg)` | Flatten config (with parent resolution) to a single alist. Child values override parent values. |
| `current-config` | parameter | `(current-config)` / `(current-config cfg)` | Parameter for dynamic scoping. Default: `#f`. |
| `with-config` | macro | `(with-config cfg body ...)` | Parameterize `current-config` with `cfg` for the dynamic extent of `body ...`. |

### Examples

**Basic usage with parent cascading:**

```scheme
(import (std misc config))

(define base (make-config '((host . "localhost") (port . 8080) (debug . #f))))
(define dev  (make-config '((port . 9090) (debug . #t)) base))

(config-ref dev 'host)   ;; => "localhost" (cascades to parent)
(config-ref dev 'port)   ;; => 9090 (child overrides)
(config-ref dev 'debug)  ;; => #t
```

**Functional update:**

```scheme
(define prod (config-set base 'debug #f))
(config-ref prod 'debug)  ;; => #f
(config-ref base 'debug)  ;; => #f (original unchanged -- was already #f)
```

**Validation with schema:**

```scheme
(define schema
  `((host . ,string?)
    (port . ,(lambda (v) (and (integer? v) (> v 0))))
    (timeout . ,number?)))

(define cfg (make-config '((host . "localhost") (port . 8080))))

(config-verify schema cfg)
;; => ("missing key: timeout")
```

**Merging configs:**

```scheme
(define defaults (make-config '((host . "0.0.0.0") (port . 80) (workers . 4))))
(define overrides (make-config '((port . 443) (tls . #t))))
(define merged (config-merge defaults overrides))

(config-ref merged 'host)     ;; => "0.0.0.0"
(config-ref merged 'port)     ;; => 443
(config-ref merged 'tls)      ;; => #t
(config-ref merged 'workers)  ;; => 4
```

**Nested configuration sections:**

```scheme
(define cfg (make-config
  `((database . ((host . "db.example.com") (port . 5432)))
    (cache    . ((host . "redis.local") (port . 6379))))))

(define db-cfg (config-subsection cfg 'database))
(config-ref db-cfg 'host)  ;; => "db.example.com"
(config-ref db-cfg 'port)  ;; => 5432
```

**Dynamic scoping with `with-config`:**

```scheme
(define (get-host)
  (config-ref (current-config) 'host))

(with-config (make-config '((host . "example.com")))
  (get-host))  ;; => "example.com"
```

**Loading from file:**

```scheme
;; Assuming /etc/app.conf contains: ((host . "prod.example.com") (port . 443))
(define cfg (config-from-file "/etc/app.conf"))
(config-ref cfg 'host)  ;; => "prod.example.com"
```

---

## 5. (std misc terminal) -- Terminal Control / ANSI Codes

**Module path:** `(std misc terminal)`
**Source:** `lib/std/misc/terminal.sls`

```scheme
(import (std misc terminal))
```

### Overview

ANSI terminal control: cursor movement, screen clearing, text styling (bold, dim, italic, underline, blink, reverse), foreground/background colors (named and 256-color), terminal dimension queries, raw mode, and alternate screen buffer. All escape sequences are written to `(current-output-port)`.

### API Reference

| Name | Kind | Signature | Description |
|------|------|-----------|-------------|
| **Cursor control** | | | |
| `cursor-up` | procedure | `(cursor-up)` / `(cursor-up n)` | Move cursor up 1 or `n` lines. |
| `cursor-down` | procedure | `(cursor-down)` / `(cursor-down n)` | Move cursor down 1 or `n` lines. |
| `cursor-forward` | procedure | `(cursor-forward)` / `(cursor-forward n)` | Move cursor right 1 or `n` columns. |
| `cursor-back` | procedure | `(cursor-back)` / `(cursor-back n)` | Move cursor left 1 or `n` columns. |
| `cursor-position` | procedure | `(cursor-position row col)` | Move cursor to absolute `row`, `col` (1-based). |
| `cursor-save` | procedure | `(cursor-save)` | Save cursor position. |
| `cursor-restore` | procedure | `(cursor-restore)` | Restore saved cursor position. |
| `cursor-hide` | procedure | `(cursor-hide)` | Hide the cursor. |
| `cursor-show` | procedure | `(cursor-show)` | Show the cursor. |
| **Screen control** | | | |
| `clear-screen` | procedure | `(clear-screen)` | Clear the entire screen. |
| `clear-line` | procedure | `(clear-line)` | Clear the entire current line. |
| `clear-to-end` | procedure | `(clear-to-end)` | Clear from cursor to end of line. |
| `clear-to-beginning` | procedure | `(clear-to-beginning)` | Clear from cursor to beginning of line. |
| **Text styling** | | | |
| `bold` | procedure | `(bold)` / `(bold text)` | No-arg: emit bold SGR code. One-arg: return `text` wrapped in bold + reset. |
| `dim` | procedure | `(dim)` / `(dim text)` | Dim/faint styling. Same calling conventions as `bold`. |
| `italic` | procedure | `(italic)` / `(italic text)` | Italic styling. |
| `underline` | procedure | `(underline)` / `(underline text)` | Underline styling. |
| `blink` | procedure | `(blink)` / `(blink text)` | Blink styling. |
| `reverse-video` | procedure | `(reverse-video)` / `(reverse-video text)` | Reverse video styling. |
| `reset-style` | procedure | `(reset-style)` | Emit the reset SGR code (turns off all styling). |
| **Colors** | | | |
| `fg-color` | procedure | `(fg-color color)` / `(fg-color color text)` | Set foreground color. `color` is a symbol (`black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`) or integer 0--255. No-arg form emits; two-arg form returns styled string. |
| `bg-color` | procedure | `(bg-color color)` / `(bg-color color text)` | Set background color. Same conventions as `fg-color`. |
| **Terminal dimensions** | | | |
| `terminal-width` | procedure | `(terminal-width)` | Returns terminal width in columns. Checks `COLUMNS` env var, then `stty size`, falls back to 80. |
| `terminal-height` | procedure | `(terminal-height)` | Returns terminal height in rows. Checks `LINES` env var, then `stty size`, falls back to 24. |
| **Raw mode** | | | |
| `with-raw-mode` | procedure | `(with-raw-mode thunk)` | Save terminal settings, switch to raw mode (no echo, no line buffering), run `thunk`, restore settings on exit. Uses `dynamic-wind` for cleanup. |
| **Alternate screen** | | | |
| `with-alternate-screen` | procedure | `(with-alternate-screen thunk)` | Switch to the alternate screen buffer, run `thunk`, switch back. Uses `dynamic-wind` for cleanup. |

### Named Colors

`black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`

### Examples

**Styled output:**

```scheme
(import (std misc terminal))

;; Return a styled string
(display (bold "Important!"))
(newline)
(display (fg-color 'red "Error: something went wrong"))
(newline)

;; Combine styles by nesting
(display (bold (fg-color 'green "Success")))
(newline)
```

**256-color support:**

```scheme
;; Use color index 208 (orange)
(display (fg-color 208 "Orange text"))
(newline)

;; Background color
(display (bg-color 'blue (fg-color 'white " Alert ")))
(newline)
```

**Cursor and screen control:**

```scheme
(clear-screen)
(cursor-position 1 1)
(display "Top-left corner")
(cursor-position 10 20)
(display "Row 10, Col 20")
```

**Terminal dimensions:**

```scheme
(let ([w (terminal-width)]
      [h (terminal-height)])
  (display (format "Terminal: ~a x ~a\n" w h)))
```

**Full-screen TUI with alternate screen:**

```scheme
(with-alternate-screen
  (lambda ()
    (clear-screen)
    (cursor-position 1 1)
    (display (bold "My Application"))
    ;; ... handle input ...
    ))
;; Original screen content is restored when thunk exits
```

---

## 6. (std misc highlight) -- Scheme Syntax Highlighting

**Module path:** `(std misc highlight)`
**Source:** `lib/std/misc/highlight.sls`

```scheme
(import (std misc highlight))
```

### Overview

Tokenizes Scheme source code and applies ANSI color codes for terminal display or produces SXML for structured output. Includes a themeable color system and recognizes keywords, strings, numbers, comments, booleans, characters, parentheses, and symbols.

### API Reference

| Name | Kind | Signature | Description |
|------|------|-----------|-------------|
| `highlight-scheme` | procedure | `(highlight-scheme code)` | Returns `code` as an ANSI-colored string using the current theme. |
| `highlight-scheme/sxml` | procedure | `(highlight-scheme/sxml code)` | Returns SXML representation: `(highlight (span (@ (class "category")) "text") ...)`. Whitespace tokens appear as bare strings. |
| `highlight-to-port` | procedure | `(highlight-to-port code port)` / `(highlight-to-port code port theme)` | Write highlighted `code` to `port`. Optionally override the theme for this call. |
| `make-theme` | procedure | `(make-theme alist)` | Create a theme from an alist of `(category . ansi-string-or-#f)`. Missing categories are filled from `default-theme`. |
| `with-theme` | macro | `(with-theme theme body ...)` | Parameterize the current theme for the dynamic extent of `body ...`. |
| `default-theme` | value | -- | The built-in theme alist. |
| `token-categories` | value | -- | List of all token category symbols: `(keyword string number comment boolean paren symbol char whitespace)`. |

### Default Theme Colors

| Category | Color |
|----------|-------|
| `keyword` | Bold blue |
| `string` | Green |
| `number` | Cyan |
| `comment` | Dim/gray |
| `boolean` | Magenta |
| `paren` | Default |
| `symbol` | Default |
| `char` | Yellow |
| `whitespace` | No styling |

### Examples

**Basic highlighting:**

```scheme
(import (std misc highlight))

(display (highlight-scheme "(define (fib n)\n  (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))"))
;; Outputs ANSI-colored text to the terminal
```

**SXML output for HTML rendering:**

```scheme
(highlight-scheme/sxml "(if #t \"yes\" \"no\")")
;; => (highlight
;;      (span (@ (class "keyword")) "if")
;;      " "
;;      (span (@ (class "boolean")) "#t")
;;      " "
;;      (span (@ (class "string")) "\"yes\"")
;;      " "
;;      (span (@ (class "string")) "\"no\""))
```

**Custom theme:**

```scheme
(define my-theme
  (make-theme
    `((keyword . ,(string-append "\x1b;" "[1;33m"))   ;; bold yellow
      (string  . ,(string-append "\x1b;" "[35m"))     ;; magenta
      (comment . ,(string-append "\x1b;" "[2;32m"))))) ;; dim green

(with-theme my-theme
  (display (highlight-scheme "(define x 42) ; a number")))
```

**Writing to a file port:**

```scheme
(call-with-output-file "highlighted.txt"
  (lambda (port)
    (highlight-to-port "(lambda (x) (* x x))" port)))
```

---

## 7. (std misc guardian-pool) -- Guardian-Based FFI Cleanup

**Module path:** `(std misc guardian-pool)`
**Source:** `lib/std/misc/guardian-pool.sls`

```scheme
(import (std misc guardian-pool))
```

### Overview

Standardized guardian-based resource cleanup for FFI handles. Resources registered with a guardian pool are automatically cleaned up when the GC reclaims them, or can be manually drained on shutdown. Includes a "pointerlike" abstraction for wrapping integer/pointer values with automatic lifecycle management, and a scoped `with-guarded-resource` macro for RAII-style cleanup.

### API Reference

| Name | Kind | Signature | Description |
|------|------|-----------|-------------|
| `make-guardian-pool` | procedure | `(make-guardian-pool cleanup-proc)` | Create a pool. `cleanup-proc` is called with each resource when it is collected or drained. |
| `guardian-pool?` | procedure | `(guardian-pool? x)` | Returns `#t` if `x` is a guardian pool. |
| `guardian-pool-register` | procedure | `(guardian-pool-register pool resource)` | Register `resource` with the pool's guardian. Returns `resource` for convenience. |
| `guardian-pool-collect!` | procedure | `(guardian-pool-collect! pool)` | Drain the guardian of GC-reclaimed resources, calling `cleanup-proc` on each. Returns the count of resources cleaned up. Skips resources already manually freed. |
| `guardian-pool-drain!` | procedure | `(guardian-pool-drain! pool)` | Clean up ALL live resources (for shutdown). First calls `collect!`, then forcibly cleans everything still registered. Returns the count cleaned. |
| `with-guarded-resource` | macro | `(with-guarded-resource (var init pool) body ...)` | Evaluate `init`, bind to `var`, register with `pool`, run `body ...`, and clean up `var` on scope exit (normal or exception). Uses `dynamic-wind`. |
| `make-pointerlike` | procedure | `(make-pointerlike pool value)` | Create a pointerlike handle wrapping `value`, auto-registered with `pool`. |
| `pointerlike?` | procedure | `(pointerlike? x)` | Returns `#t` if `x` is a pointerlike. |
| `pointerlike-value` | procedure | `(pointerlike-value p)` | Returns the wrapped value. Raises error if already freed. |
| `pointerlike-free!` | procedure | `(pointerlike-free! p)` | Manually free the pointerlike, calling the pool's cleanup proc. Removes from the live set to prevent double-free. Sets the value to `#f`. |

### Examples

**Basic resource pool:**

```scheme
(import (std misc guardian-pool))

;; Simulate FFI handles as integers
(define freed '())

(define pool
  (make-guardian-pool
    (lambda (handle)
      (set! freed (cons handle freed))
      ;; In real code: (foreign-free handle)
      )))

;; Register resources
(guardian-pool-register pool 'handle-a)
(guardian-pool-register pool 'handle-b)

;; On shutdown, drain everything
(let ([n (guardian-pool-drain! pool)])
  (display (format "Cleaned up ~a resources\n" n)))
```

**Scoped resource management (RAII-style):**

```scheme
(define pool (make-guardian-pool
  (lambda (h) (display (format "freeing ~a\n" h)))))

(with-guarded-resource (h 'my-handle pool)
  (display (format "Using ~a\n" h)))
;; Output:
;;   Using my-handle
;;   freeing my-handle
```

**Pointerlike handles:**

```scheme
(define pool (make-guardian-pool
  (lambda (p)
    (display "pointerlike cleaned up\n"))))

(define h (make-pointerlike pool 42))
(display (pointerlike-value h))  ;; => 42

;; Manual free
(pointerlike-free! h)
;; (pointerlike-value h) would now raise an error
```

**Periodic collection in a long-running process:**

```scheme
(define pool (make-guardian-pool free-foreign-handle!))

;; In your event loop or periodic task:
(let ([n (guardian-pool-collect! pool)])
  (when (> n 0)
    (display (format "GC cleaned ~a handles\n" n))))
```

---

## 8. (std misc memoize) -- Memoization with LRU

**Module path:** `(std misc memoize)`
**Source:** `lib/std/misc/memoize.sls`

```scheme
(import (std misc memoize))
```

### Overview

Memoization utilities with two strategies: unbounded hash-table caching and bounded LRU (Least Recently Used) eviction. Includes a `define-memoized` macro for defining self-recursive memoized functions. The cache key is the argument list, compared with `equal?`.

### API Reference

| Name | Kind | Signature | Description |
|------|------|-----------|-------------|
| `memoize` | procedure | `(memoize proc)` / `(memoize proc max-size)` | Wrap `proc` with memoization. One-arg form: unbounded cache. Two-arg form: delegates to `memoize/lru` with the given max size. |
| `memoize/lru` | procedure | `(memoize/lru proc max-size)` | Wrap `proc` with LRU-bounded memoization. When the cache exceeds `max-size` entries, the least recently used entry is evicted. |
| `define-memoized` | macro | `(define-memoized (name args ...) body ...)` | Define a memoized function. The cache is captured in the closure, so recursive calls to `name` within `body` hit the cache. Unbounded cache. |
| `memo-clear!` | procedure | `(memo-clear! memo-fn)` | Placeholder for clearing a memoized function's cache. Currently a no-op; clearing is available through the `define-memoized` form's internal cache. |

### Important Notes

- Cache keys are argument lists compared with `equal?`, so `(f 1 2)` and `(f 1 2)` will share a cache entry.
- The unbounded `memoize` returns `#f` for cache misses before storing, so memoized functions that legitimately return `#f` will recompute on every call. Use `memoize/lru` or `define-memoized` if this matters, though they share the same limitation.
- `memoize/lru` uses a timestamp-scan eviction strategy (linear scan on eviction, not O(1)). Suitable for moderate cache sizes.

### Examples

**Memoizing an expensive function:**

```scheme
(import (std misc memoize))

(define slow-square
  (memoize
    (lambda (n)
      (display (format "computing ~a\n" n))
      (* n n))))

(slow-square 5)  ;; prints "computing 5", returns 25
(slow-square 5)  ;; returns 25 immediately (cached)
(slow-square 3)  ;; prints "computing 3", returns 9
```

**Recursive memoized function (Fibonacci):**

```scheme
(define-memoized (fib n)
  (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))

(fib 50)  ;; instant, thanks to memoization
;; => 12586269025
```

**LRU-bounded cache:**

```scheme
;; Cache at most 100 results
(define cached-lookup
  (memoize/lru
    (lambda (key)
      (display (format "fetching ~a\n" key))
      (string-append "value-for-" (symbol->string key)))
    100))

(cached-lookup 'foo)  ;; fetches and caches
(cached-lookup 'foo)  ;; cached hit
;; After 100+ distinct keys, least-recently-used entries are evicted
```

**Using memoize with two-arg shorthand for LRU:**

```scheme
(define fast-fn (memoize slow-fn 1000))
;; Equivalent to: (memoize/lru slow-fn 1000)
```
