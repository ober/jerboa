# Jerboa REPL Server Protocol

The Jerboa REPL server provides a SWANK-like protocol for editor integration. Editors connect via TCP and exchange s-expressions.

## Quick Start

### Starting the Server

```scheme
(import (std repl server))
(define srv (repl-server-start 4233))  ; specific port
(define srv (repl-server-start 0))     ; auto-assign port
(repl-server-port srv)                 ; → actual port number
(repl-server-stop srv)                 ; stop
```

### Port Discovery

The server writes `~/.jerboa-repl-port` with:
```
PORT=4233
PID=12345
```

Editors should read this file to auto-discover the server port.

### Connecting

```bash
# From shell
nc 127.0.0.1 4233

# From Emacs Lisp
(open-network-stream "jerboa" buf "127.0.0.1" 4233)
```

## Protocol

### Request Format

```
(id method arg1 arg2 ...)
```

- `id`: integer — unique request identifier, echoed in response
- `method`: symbol — the operation to perform
- `args`: method-specific arguments

### Response Format

Success:
```
(id :ok result)
```

Error:
```
(id :error "error message")
```

Server push (unsolicited):
```
(:push type payload)
```

## Methods

### eval

Evaluate a Scheme expression string. Returns the result and captured stdout.

```
Request:  (1 eval "(+ 1 2)")
Response: (1 :ok (:value "3" :stdout ""))

Request:  (2 eval "(begin (display 42) 99)")
Response: (2 :ok (:value "99" :stdout "42"))

Request:  (3 eval "(/ 1 0)")
Response: (3 :error "undefined for ~s")
```

### eval-region

Evaluate multiple forms. Returns the value of the last form.

```
Request:  (1 eval-region "(define x 10) (+ x 5)")
Response: (1 :ok (:value "15" :stdout ""))
```

### complete

Return symbol completions for a prefix.

```
Request:  (1 complete "string-")
Response: (1 :ok ("string-append" "string-length" "string-ref" ...))
```

### doc

Look up documentation for a symbol.

```
Request:  (1 doc car)
Response: (1 :ok "(car pair) -> any\n  Return the first element of pair.")
```

### apropos

Search for symbols matching a substring. Returns list of (name type) pairs.

```
Request:  (1 apropos "hash")
Response: (1 :ok (("hashtable-ref" "Procedure") ("hashtable-set!" "Procedure") ...))
```

### expand

Full macro expansion.

```
Request:  (1 expand "(and 1 2)")
Response: (1 :ok "(if 1 2 #f)\n")
```

### expand1

One-step macro expansion (uses Chez's `sc-expand`).

```
Request:  (1 expand1 "(and 1 2)")
Response: (1 :ok "...")
```

### type

Get the type string for an expression's value.

```
Request:  (1 type "42")
Response: (1 :ok "Fixnum")

Request:  (2 type "'(1 2 3)")
Response: (2 :ok "List[3]")
```

### describe

Get a detailed description of an expression's value.

```
Request:  (1 describe "(make-hashtable equal-hash equal?)")
Response: (1 :ok "HashTable[0]: #<hashtable>\n")
```

### import

Import a module into the REPL environment.

```
Request:  (1 import "(std text json)")
Response: (1 :ok "imported")
```

### load

Load and evaluate a file.

```
Request:  (1 load "/path/to/file.ss")
Response: (1 :ok "loaded /path/to/file.ss")
```

### env

List environment symbols, optionally filtered by pattern.

```
Request:  (1 env "cons")
Response: (1 :ok ("cons" "cons*"))

Request:  (2 env)
Response: (2 :ok ("..." ...))  ; up to 200 symbols
```

### pwd

Get current working directory.

```
Request:  (1 pwd)
Response: (1 :ok "/home/user/project")
```

### cd

Change working directory.

```
Request:  (1 cd "/tmp")
Response: (1 :ok "/tmp")
```

### ping

Health check.

```
Request:  (1 ping)
Response: (1 :ok "pong")
```

### shutdown

Stop the server.

```
Request:  (1 shutdown)
Response: (1 :ok "shutting down")
```

## Type Strings

The `type` method returns human-readable type strings:

| Type | Example |
|------|---------|
| `Boolean` | `#t`, `#f` |
| `Fixnum` | `42` |
| `Flonum` | `3.14` |
| `Bignum` | `99999999999999999` |
| `Rational` | `3/4` |
| `Complex` | `1+2i` |
| `Char` | `#\a` |
| `String[N]` | `"hello"` → `String[5]` |
| `Symbol` | `'foo` |
| `Keyword` | `':key` |
| `Null` | `'()` |
| `List[N]` | `'(1 2 3)` → `List[3]` |
| `AList[N]` | `'((a . 1) (b . 2))` → `AList[2]` |
| `Pair` | `'(1 . 2)` |
| `Vector[N]` | `#(a b c)` → `Vector[3]` |
| `Bytevector[N]` | `#vu8(1 2 3)` → `Bytevector[3]` |
| `HashTable[N]` | hash table with N entries |
| `Procedure` | any procedure |
| `Void` | `(void)` |
| `InputPort` | input ports |
| `OutputPort` | output ports |
| `InputOutputPort` | bidirectional ports |
| Record type name | e.g., `point` for `(defstruct point ...)` |

## Emacs Integration Example

```elisp
(defun jerboa-eval (expr)
  "Evaluate EXPR in the Jerboa REPL server."
  (let* ((port (jerboa-discover-port))
         (proc (open-network-stream "jerboa" nil "127.0.0.1" port))
         (id (cl-incf jerboa--request-id))
         (request (format "(%d eval %S)" id expr)))
    (process-send-string proc request)
    (process-send-string proc "\n")
    ;; Read response...
    ))

(defun jerboa-discover-port ()
  "Read the server port from ~/.jerboa-repl-port."
  (with-temp-buffer
    (insert-file-contents "~/.jerboa-repl-port")
    (when (re-search-forward "PORT=\\([0-9]+\\)" nil t)
      (string-to-number (match-string 1)))))
```

## Implementation Notes

- The server binds to `0.0.0.0` (all interfaces). For security, consider binding to `127.0.0.1` only in production.
- Each client connection runs in its own Chez thread.
- The server shares the `interaction-environment` — state changes from one client are visible to others.
- Stdout is captured per-eval via `parameterize` on `current-output-port`.
- The server auto-writes `~/.jerboa-repl-port` on start and removes it on stop.
