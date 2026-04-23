# Single-file Jerboa packages

Most `.ss` scripts are just "run it with `scheme --script`" — they depend
only on the Jerboa standard library. But sometimes a script wants an
external package (e.g., a Jerboa binding for some C library on GitHub).
Traditionally that requires the reader to:

1. Find the package.
2. `jerboa install github.com/someone/jerboa-foo`.
3. *Then* run the script.

The **single-file package format** eliminates step 1-2 for the reader:
the script declares its dependencies in a machine-readable header, and
`jerboa exec` installs anything missing before running. LLMs can emit
complete, runnable programs in a single file.

## Format

Put a block of `;;;` comments at the top of the file, starting with the
marker `;;; jerboa-package`:

```scheme
#!/usr/bin/env jerboa
;;; jerboa-package
;;; name:    my-app
;;; version: 0.1.0
;;; requires:
;;;   github.com/alice/jerboa-fancy-json
;;;   github.com/bob/jerboa-http-ext
;;;
;;; Free-form description can follow an empty ;;;  comment —
;;; these lines are ignored by the parser.
(import (jerboa prelude))
(import (fancy-json))
;; ...rest of script
```

### Rules

1. The header must begin at the first `;;; jerboa-package` line.
2. Keys take the form `key: value` inside `;;; ` comments. Recognised
   keys: `name`, `version`, `requires`.
3. `requires:` is special — it is followed by indented `;;;   url`
   lines, one package URL per line. The sub-block ends at a bare
   `;;;` (blank comment) or at the next recognised key.
4. The header block ends at the first non-`;;;` line.
5. Unknown keys are ignored (forwards-compatible).

## Running

```bash
jerboa exec my-app.ss
```

On first run, `jerboa exec` parses the header, compares the required
packages against `jerboa list`, and for each missing one prompts:

```
jerboa exec: my-app.ss declares 2 missing package(s):
  - github.com/alice/jerboa-fancy-json
  - github.com/bob/jerboa-http-ext
Install now? [y/N]
```

On `y` it installs each via `jerboa install` and then runs the script.
Set `JERBOA_EXEC_YES=1` to skip the prompt (useful for CI or shebang
scripts).

## Shebang trick

With the executable bit set and `jerboa` on `PATH`:

```scheme
#!/usr/bin/env -S jerboa exec
;;; jerboa-package
;;; name: hello
;;; requires:
;;;   github.com/alice/jerboa-greetings
;;;
(import (jerboa prelude) (greetings))
(greet "world")
```

```bash
chmod +x hello.ss
./hello.ss
```

Note: `-S` is needed on Linux so `env` forwards two arguments to
`jerboa`. On systems without `env -S`, use an explicit two-line shell
wrapper instead.

## Why not a separate manifest file?

Scheme projects with complex layouts still want proper `package.sls` /
Makefile-style manifests. This format targets the other end of the
spectrum: **scripts small enough to live in one file** — exactly the
kind of artifact LLMs produce. A scattered-file layout is friction for
casual sharing via gist, paste, or email.

## Comparison

| Tool     | Format                                  |
|----------|-----------------------------------------|
| Deno     | `// deno-types="..."` in source        |
| Go       | `// +build ...` comments               |
| Python   | `# /// script` PEP-723 block           |
| Jerboa   | `;;; jerboa-package` comment block     |

All four live at the top of a `.ss` / `.ts` / `.go` / `.py` file, use
comment syntax native to the host language, and are parsed by a
separate runner that resolves dependencies before invoking the
interpreter/compiler.
