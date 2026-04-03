# Jerboa Runtime: Features to Implement

## GC Finalizer Safety Net for Unclosed Resources

**ID:** jerboa-finalizer-safety-net  
**Impact:** high  
**Votes:** 1

### What

Register Chez guardians on resource-acquiring functions (`sqlite-open`, `tcp-connect`, `open-input-file`, etc.). When a resource is garbage collected without being explicitly closed, log a warning that includes the allocation site. This catches resource leaks that `with-resource` would have prevented, without crashing.

### Why

Claude-generated code frequently forgets `with-resource` and uses bare `(let ([db (sqlite-open ...)]) ...)`. The connection leaks silently and is only discovered in production under load. With a finalizer safety net, a warning appears in the log during testing so the leak is caught early.

### Example

```
WARNING: sqlite handle #7 GC'd without close — allocated at handler.ss:42
```

Developer then wraps the `sqlite-open` in `with-resource`. Bug fixed before production.

### How to Implement

In the relevant resource-opening functions (e.g. `sqlite-open` in `lib/std/db/sqlite.sls`, `tcp-connect` in `lib/std/net/tcp.sls`), register a Chez guardian after the resource is created:

```scheme
;; After creating the resource handle:
(let ([guardian (make-guardian)])
  (guardian handle)
  (spawn
    (lambda ()
      (let loop ()
        (let ([collected (guardian)])
          (when collected
            (unless (resource-closed? collected)
              (log-warning
                (str "WARNING: " (resource-type-name collected)
                     " handle GC'd without close"
                     (if (resource-alloc-site collected)
                         (str " — allocated at " (resource-alloc-site collected))
                         ""))))
            (loop)))))))
```

Key details:
- Use `make-guardian` (Chez SRFI-115 guardian API)
- The guardian thread should be a daemon thread (low priority, doesn't prevent exit)
- Capture the allocation site via `(call-with-current-continuation ...)` or a `(fluid-let ([*alloc-site* (current-source-location)]) ...)` wrapper at the call site
- The warning should go to `current-error-port`, not `current-output-port`
- This is opt-in per module — add to: `(std db sqlite)`, `(std net tcp)`, `(std net request)`, `(std os file)` at minimum

### Affected Modules

- `lib/std/db/sqlite.sls` — `sqlite-open`
- `lib/std/net/tcp.sls` — `tcp-connect`, `tcp-listen`
- `lib/std/net/request.sls` — any connection-holding handle
- `lib/std/os/file.sls` — file handles opened without `with-resource`

### Notes

- The warning must NOT prevent GC or cause a crash — it is purely informational
- In production, this can be silenced via `(set-resource-leak-warning! #f)`
- This is a runtime change to the standard library, not an MCP tool
