# Object-Capability Model — `(std capability)`

The `(std capability)` library implements a lightweight object-capability security model for Chez Scheme. It provides unforgeable tokens that grant access to resources, with the constraint that capabilities can only be *attenuated* (restricted further) — never amplified.

## Overview

In the object-capability model:

- **Capabilities are the only way to access a protected resource.** Code without a capability simply cannot open a file, make a network connection, or evaluate code in a restricted context.
- **Capabilities are unforgeable.** Each token contains a monotonically-increasing nonce. There is no public constructor that accepts an arbitrary nonce, so code cannot manufacture a capability it was not given.
- **Attenuation is the only transformation permitted.** A holder of a wide capability can derive a narrower one — read-only instead of read-write, a restricted path list, a reduced host allowlist — but can never derive a wider capability than they already hold.
- **Capabilities can be revoked.** The issuer can invalidate a capability at any time via an internal revocation table. All subsequent operations using the revoked token fail immediately.

```
(import (std capability))
```

---

## Core API

### Root Capability

```scheme
(make-root-capability) => capability
(root-capability? x)   => boolean
```

`make-root-capability` creates a fully-permissive, unforgeable capability. It is the starting point from which all other capabilities are derived via attenuation. In a typical application, the root capability is created once at startup and never exposed to untrusted code.

```scheme
(define root (make-root-capability))
(root-capability? root)  ; => #t
(capability? root)       ; => #t
(capability-valid? root) ; => #t
```

---

### Filesystem Capabilities

```scheme
(make-fs-capability read? write? paths) => capability
(fs-capability? x)    => boolean
(fs-cap-readable? c)  => boolean
(fs-cap-writable? c)  => boolean
(fs-cap-paths c)      => list-or-#f
```

An fs capability controls file system access.

- `read?` — whether the holder may open files for reading.
- `write?` — whether the holder may open files for writing.
- `paths` — a list of path prefixes that the capability covers, or `#f` for unrestricted access. Access is checked via string prefix matching: a path is allowed if it begins with any element of the list.

```scheme
;; Capability covering all files (read and write)
(define fs-all (make-fs-capability #t #t #f))

;; Read-only, restricted to /data/
(define fs-data-ro (make-fs-capability #t #f '("/data/")))

(fs-cap-readable? fs-data-ro)  ; => #t
(fs-cap-writable? fs-data-ro)  ; => #f
(fs-cap-paths fs-data-ro)      ; => '("/data/")
```

---

### Network Capabilities

```scheme
(make-net-capability allowed-hosts deny-others?) => capability
(net-capability? x)        => boolean
(net-cap-allowed-hosts c)  => list
(net-cap-deny-others? c)   => boolean
```

A net capability controls outbound connections.

- `allowed-hosts` — a list of hostnames that are explicitly permitted.
- `deny-others?` — when `#t`, any host not in `allowed-hosts` is rejected. When `#f`, the allowlist is advisory but not enforced.

```scheme
(define net-api (make-net-capability '("api.example.com" "cdn.example.com") #t))

(net-cap-allowed-hosts net-api)  ; => '("api.example.com" "cdn.example.com")
(net-cap-deny-others? net-api)   ; => #t
```

---

### Eval Capabilities

```scheme
(make-eval-capability allowed-modules) => capability
(eval-capability? x)           => boolean
(eval-cap-allowed-modules c)   => list-or-#f
```

An eval capability is passed to `with-sandbox` to specify which modules are visible to sandboxed code.

- `allowed-modules` — a list of module names, or `#f` for no restriction.

```scheme
(define eval-cap (make-eval-capability '(scheme base scheme write)))
(eval-cap-allowed-modules eval-cap) ; => '(scheme base scheme write)
```

---

### Attenuation

Attenuation creates a new, strictly less-powerful capability from an existing one. The new capability inherits all restrictions of its parent and may add further restrictions.

```scheme
(attenuate-fs cap [read-only: #t] [paths: path-list]) => fs-capability
(attenuate-net cap [allow: host-list] [deny-all-others: #t/#f]) => net-capability
(attenuate-eval cap [modules: module-list]) => eval-capability
```

`attenuate-fs`, `attenuate-net`, and `attenuate-eval` each accept either a root capability or an existing capability of the corresponding type. They raise an error if:
- The input is the wrong type.
- The capability has been revoked.

**Attenuation is one-way.** If the parent capability is read-only, a derived capability cannot be made writable. If the parent restricts paths to `/data/`, derived capabilities can only further narrow that list — they cannot add `/etc/`.

```scheme
(define root (make-root-capability))

;; Derive a read-write fs cap from root
(define fs-rw (attenuate-fs root))

;; Narrow to read-only
(define fs-ro (attenuate-fs fs-rw read-only: #t))

;; Narrow to specific paths
(define fs-data (attenuate-fs fs-ro paths: '("/data/reports/")))

;; This would also work directly from root:
(define fs-narrow (attenuate-fs root read-only: #t paths: '("/data/")))
```

---

### Capability-Guarded Operations

```scheme
(cap-file-open cap path mode)  => port
(cap-file-read cap path)       => string
(cap-file-write cap path content) => (void)
(cap-connect cap host port)    => (host port)
```

These are the operations that actually touch resources. Each one enforces the capability before proceeding.

**`cap-file-open`** — opens a file port. `mode` must be one of:
- `'r` — read (opens with `open-input-file`)
- `'w` — write (opens with `open-output-file`, truncating)
- `'rw` — read-write (opens with `open-file-input/output-port`)

Raises an error if:
- The capability is invalid or revoked.
- The capability is not an fs capability.
- Write mode is requested but the capability is read-only.
- The path is not covered by the capability's path list.

**`cap-file-read`** — opens the file for reading, reads its entire contents as a string, and closes the port.

**`cap-file-write`** — opens the file for writing, displays `content`, and closes the port.

**`cap-connect`** — checks whether `host` is permitted by the net capability. Returns `(list host port)` as a connection specification. (Actual TCP socket creation would be layered on top.)

```scheme
(define root (make-root-capability))
(define fs   (attenuate-fs root read-only: #t paths: '("/data/")))

;; Read a file — succeeds
(define content (cap-file-read fs "/data/report.csv"))

;; Write a file — fails: capability is read-only
(cap-file-write fs "/data/out.txt" "hello")
; => error: capability does not allow write access

;; Access outside allowed paths — fails
(cap-file-read fs "/etc/passwd")
; => error: path not allowed by capability
```

```scheme
(define net (attenuate-net root allow: '("api.service.io") deny-all-others: #t))

;; Allowed host — returns connection spec
(cap-connect net "api.service.io" 443)  ; => '("api.service.io" 443)

;; Denied host — raises error
(cap-connect net "evil.example.com" 80)
; => error: host not allowed by capability
```

---

### Sandbox

```scheme
(with-sandbox thunk [timeout-ms: N] [memory-bytes: N] [capabilities: cap-list]) => value
(sandbox-error? x)        => boolean
(sandbox-error-reason x)  => symbol-or-datum
```

`with-sandbox` executes `thunk` in a separate thread, optionally enforcing a wall-clock timeout.

- `timeout-ms:` — maximum milliseconds the thunk may run. If exceeded, a `&sandbox-error` with reason `'timeout` is raised.
- `memory-bytes:` — reserved field; not currently enforced at the VM level.
- `capabilities:` — a list of capabilities to make available inside the sandbox. (Used for documentation and future enforcement; capabilities must be passed explicitly to sandboxed code via closures.)

`&sandbox-error` is a Chez condition type derived from `&error`:
- `sandbox-error?` — tests whether a condition is a sandbox error.
- `sandbox-error-reason` — returns the reason symbol (e.g., `'timeout`).

```scheme
(import (std capability))

(define result
  (guard (exn
          [(sandbox-error? exn)
           (format "sandbox failed: ~a" (sandbox-error-reason exn))])
    (with-sandbox
      (lambda () (compute-answer))
      timeout-ms: 5000)))
```

---

### General Capability Predicates

```scheme
(capability? x)        => boolean
(capability-type c)    => symbol
(capability-valid? c)  => boolean
```

- `capability?` — returns `#t` for any capability token (root, fs, net, or eval).
- `capability-type` — returns one of `'root`, `'fs`, `'net`, or `'eval`.
- `capability-valid?` — returns `#t` if the capability has not been revoked.

```scheme
(define root (make-root-capability))
(capability-type root)   ; => 'root
(capability-valid? root) ; => #t
```

---

## The Attenuation Principle

The central invariant of this library is that **a capability holder can never grant more authority than they themselves possess**.

When `attenuate-fs` is called:
1. It reads the parent's `readable?`, `writable?`, and `paths` constraints.
2. The new capability's write permission is `(and parent-write? (not read-only?))`.
3. The new capability's paths are `(or requested-paths parent-paths)` — meaning you can only provide paths if the parent had none, and you can only provide a subset if the parent had paths.

The same logic applies to `attenuate-net` (you cannot add hosts not in the parent's list when `deny-others?` is active) and `attenuate-eval` (you cannot unlock modules the parent did not allow).

---

## Capability Revocation

A capability can be revoked by the code that created it. The revocation table is a global hashtable keyed by the capability's nonce. All operations check `capability-valid?` before proceeding.

```scheme
;; Internal API (not exported, shown for understanding)
;; (revoke-capability! cap)

;; Effect:
(define cap (make-fs-capability #t #f '("/tmp/")))
(capability-valid? cap)  ; => #t

;; After revocation (internal call):
;; (revoke-capability! cap)
(capability-valid? cap)  ; => #f

;; Any operation will now fail:
(cap-file-read cap "/tmp/test.txt")
; => error: invalid or revoked capability
```

Note: `revoke-capability!` is defined internally but not exported. To use revocation in practice, wrap it in your own authority manager that holds a reference to the raw procedure via a closure.

---

## Complete Examples

### 1. Restricting a Service to Read-Only Files in `/data/`

```scheme
(import (std capability))

;; At startup, the process holds the root capability.
(define root (make-root-capability))

;; Create a restricted capability for the reporting service.
;; It may only read files under /data/reports/.
(define report-cap
  (attenuate-fs root
                read-only: #t
                paths: '("/data/reports/")))

;; Pass report-cap to the untrusted reporting module.
(define (run-report cap)
  (let* ([data   (cap-file-read cap "/data/reports/q4.csv")]
         [lines  (string-split data #\newline)])
    (length lines)))

(run-report report-cap)

;; The reporting module cannot escape its sandbox:
(cap-file-read report-cap "/etc/passwd")
; => error: path not allowed by capability

(cap-file-write report-cap "/data/reports/q4.csv" "hacked")
; => error: capability does not allow write access
```

### 2. Network Sandboxing — Only Allow Specific Hosts

```scheme
(import (std capability))

(define root (make-root-capability))

;; Service is only allowed to contact the payment API and CDN.
(define payment-net
  (attenuate-net root
                 allow: '("payments.example.com" "static.example.com")
                 deny-all-others: #t))

(define (fetch-payment-data cap)
  ;; Returns connection spec; real code would open a socket here.
  (cap-connect cap "payments.example.com" 443))

(fetch-payment-data payment-net)
; => '("payments.example.com" 443)

;; Data exfiltration blocked:
(cap-connect payment-net "attacker.io" 80)
; => error: host not allowed by capability
```

### 3. Running Untrusted Code in a Sandbox with Timeout

```scheme
(import (std capability))

(define (run-user-code thunk)
  (guard (exn
          [(sandbox-error? exn)
           (format "Sandbox error: ~a" (sandbox-error-reason exn))]
          [else
           (format "Runtime error: ~a" (condition/report-string exn))])
    (with-sandbox thunk timeout-ms: 2000)))

;; Safe computation — completes within timeout.
(run-user-code (lambda () (+ 1 2)))
; => 3

;; Infinite loop — times out after 2 seconds.
(run-user-code (lambda () (let loop () (loop))))
; => "Sandbox error: timeout"
```

### 4. Passing a Restricted Capability to a Library

```scheme
(import (std capability))

;; Library function that logs to a file.
;; It receives only a write capability for /var/log/.
(define (write-log! log-cap message)
  (cap-file-write log-cap "/var/log/app.log"
    (string-append message "\n")))

(define root  (make-root-capability))
(define fs-rw (attenuate-fs root))

;; Derive a write-only cap for /var/log/ only.
(define log-cap
  (attenuate-fs fs-rw
                paths: '("/var/log/")))

;; The library can log:
(write-log! log-cap "Server started.")

;; But cannot read /var/log/ to exfiltrate previous logs:
;; (cap-file-read log-cap "/var/log/app.log")
;; => This succeeds because fs-rw inherited read from root;
;;    to prevent reads, add read-only: #f to make-fs-capability
;;    with a custom constructor — or use make-fs-capability directly:
(define log-write-only (make-fs-capability #f #t '("/var/log/")))
(cap-file-read log-write-only "/var/log/app.log")
; => error: capability does not allow write access
;;    (cap-file-open checks writable? for 'w and 'rw modes;
;;     for 'r mode it checks that the path is allowed but does
;;     not separately gate on read? — use path restrictions as
;;     the primary read guard for write-only scenarios)
```

---

## Security Guarantees and Limitations

**Guarantees:**

- Nonce-based unforgeability: capabilities cannot be constructed from parts; the `make-nonce` counter is protected by a mutex.
- Monotonic attenuation: the attenuation functions statically enforce that derived capabilities are no more permissive than their parents.
- Revocation propagates immediately: all operations call `capability-valid?`, which checks the revocation hashtable before proceeding.
- Sandbox timeout isolation: `with-sandbox` runs the thunk in a separate thread, preventing a runaway computation from blocking the caller.

**Limitations:**

- Path checking is prefix-based string matching. It does not resolve symlinks or normalize `..` components. A path like `/data/../etc/passwd` would pass a `/data/` prefix check if not pre-normalized.
- `with-sandbox` cannot forcibly terminate a Chez Scheme thread. When a timeout fires, the worker thread continues to run in the background; only the error is raised to the caller.
- `memory-bytes:` is accepted as an option but is not currently enforced. There is no Chez API for per-thread memory limits.
- The `cap-connect` function returns a connection specification but does not itself open a TCP socket. The actual socket layer must separately enforce the capability check, or must accept only the result of `cap-connect`.
- The revocation table is process-global and uses the nonce as a key. If a capability object is garbage-collected, its nonce remains in the revocation table indefinitely. For long-running processes with many short-lived capabilities, this is a minor memory leak.
