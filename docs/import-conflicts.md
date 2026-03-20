# Jerboa Import Conflict Reference

When porting Gerbil code to Jerboa (stock Chez Scheme), name collisions between
`(chezscheme)`, `(jerboa core)`, and `(std ...)` modules are the #1 source of
friction. This document lists every known conflict and shows how to resolve it.

## Quick Fix: Use `(std gambit-compat)`

For most ports, importing `(std gambit-compat)` is the easiest path. It
re-exports everything from `(jerboa core)` and `(std sugar)`, plus additional
Gambit compatibility functions. You only need to exclude the Chez names it
overrides:

```scheme
(import (except (chezscheme)
          make-hash-table hash-table? iota 1+ 1- getenv
          path-extension path-absolute?
          thread? make-mutex mutex? mutex-name
          box box? unbox set-box!)
        (std gambit-compat))
```

## Conflict Matrix

### (chezscheme) vs (jerboa core)

| Symbol | Chez Behavior | Jerboa Core Behavior | Resolution |
|--------|--------------|---------------------|------------|
| `make-hash-table` | R6RS hashtable | Gerbil-style string-keyed hash | `(except (chezscheme) make-hash-table)` |
| `hash-table?` | R6RS predicate | Gerbil hash predicate | `(except (chezscheme) hash-table?)` |
| `iota` | `(iota n)` only | SRFI-1: `(iota count [start [step]])` | `(except (chezscheme) iota)` |
| `1+` / `1-` | Chez `1+`/`1-` | Same semantics, re-exported | `(except (chezscheme) 1+ 1-)` |
| `getenv` | Returns string or `#f` | Same + optional default arg | `(except (chezscheme) getenv)` |
| `path-extension` | Returns `""` for no ext | Returns `#f` for no ext | `(except (chezscheme) path-extension)` |
| `path-absolute?` | Chez version | Gerbil-style version | `(except (chezscheme) path-absolute?)` |
| `thread?` | Chez thread predicate | Gerbil thread predicate | `(except (chezscheme) thread?)` |
| `make-mutex` | Chez `make-mutex` | Gerbil `make-mutex` | `(except (chezscheme) make-mutex)` |
| `mutex?` | Chez predicate | Gerbil predicate | `(except (chezscheme) mutex?)` |
| `mutex-name` | Chez accessor | Gerbil accessor | `(except (chezscheme) mutex-name)` |
| `box` / `box?` / `unbox` / `set-box!` | Chez 10 built-in | Re-exported cleanly | `(except (chezscheme) box box? unbox set-box!)` |
| `sort` | `(sort pred lst)` | `(sort lst pred)` — arg order swapped | `(except (chezscheme) sort)` |
| `format` | `(format fmt args...)` — no port | Gerbil: `(format fmt args...)` | Usually compatible |

### (chezscheme) vs (std sugar)

| Symbol | Conflict | Resolution |
|--------|----------|------------|
| None currently | `(std sugar)` avoids Chez name collisions | Direct import safe |

### (chezscheme) vs (std format)

| Symbol | Conflict | Resolution |
|--------|----------|------------|
| `format` | Chez: `(format str args...)` returns string | Use Gerbil's or exclude Chez's |
| `printf` | Chez: has `printf` | Gerbil's may differ |
| `fprintf` | Chez: has `fprintf` | Gerbil's may differ |

### (chezscheme) vs (std srfi srfi-1)

| Symbol | Conflict | Resolution |
|--------|----------|------------|
| `iota` | Different signature | SRFI-1 excludes it from Chez |

### (jerboa core) vs (std misc string)

Both export string utilities. `(jerboa core)` re-exports many string functions.
If using both:

```scheme
(import (except (std misc string)
          string-split string-join string-index string-trim string-prefix?)
        (jerboa core))
```

### (jerboa core) vs (std misc list)

Both export list utilities. If using both:

```scheme
(import (except (std misc list)
          any every take drop filter-map)
        (jerboa core))
```

## Common Import Templates

### Minimal (just Chez + Gerbil compat)
```scheme
(import (except (chezscheme)
          make-hash-table hash-table? iota 1+ 1- getenv
          path-extension path-absolute?
          thread? make-mutex mutex? mutex-name
          box box? unbox set-box!)
        (std gambit-compat))
```

### Full stdlib access
```scheme
(import (except (chezscheme)
          make-hash-table hash-table? iota 1+ 1- getenv
          path-extension path-absolute?
          thread? make-mutex mutex? mutex-name
          box box? unbox set-box!)
        (std gambit-compat)
        (std iter)
        (std srfi srfi-1)
        (std srfi srfi-13)
        (std text json))
```

### Test file template
```scheme
(import (except (chezscheme)
          make-hash-table hash-table? iota 1+ 1- getenv
          path-extension path-absolute?
          thread? make-mutex mutex? mutex-name
          box box? unbox set-box!)
        (std gambit-compat)
        (std test))
```

## Tips

1. **Start with `(std gambit-compat)`** — it handles most conflicts automatically
2. **Add `(except ...)` for Chez names** that collide — the list above is comprehensive
3. **Import specific modules after** `gambit-compat` — they'll override with Gerbil-compatible versions
4. **When in doubt**, check which version you want with `scheme --libdirs lib -q` and test interactively
