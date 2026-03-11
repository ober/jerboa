# Developer Experience Tools

Jerboa provides three development-time tools: a time-travel debugger for
inspecting execution history, a deterministic profiler for performance analysis,
and a hot code reloader for live development.

---

## Time-Travel Debugger

**Import:** `(std dev debug)`

Records function calls, returns, and events into a circular buffer. You can
rewind and step through execution history after the fact.

### Starting a recording

```scheme
(with-recording capacity thunk)
;; Run thunk with a recording active. capacity = max entries in circular buffer.
;; Returns the recording object.

(*current-recording*)     ; parameter holding the active recording
(recording? obj)          ; predicate
(current-recording)       ; alias for (*current-recording*)
```

### Recording events manually

```scheme
(trace-event! data)                  ; record an arbitrary event
(trace-call! name args)              ; record a function call
(trace-return! name value)           ; record a return value
(trace-error! name condition)        ; record an error
```

### The `instrument` macro

```scheme
(instrument (define (name args ...) body ...))
;; Wraps the function body to automatically record calls and returns
```

### Navigating history

```scheme
(debug-history)                ; list of all recorded entries
(debug-frame-count)            ; total number of frames recorded
(debug-current-frame)          ; current frame index (0 = oldest)
(debug-rewind)                 ; jump to oldest frame
(debug-forward)                ; jump to newest frame
(debug-step n)                 ; move n frames forward (negative = backward)
```

### Inspecting frames

```scheme
(debug-locals)         ; local variables at current frame (as alist if available)
(debug-inspect entry)  ; detailed inspection of a specific entry
```

### Conditional breakpoints

```scheme
(break-when! name pred)   ; break (raise) when pred returns #t for entry with name
(break-never! name)       ; remove breakpoint for name
(check-breakpoints! entry); check if entry triggers any breakpoints
```

### Example

```scheme
(import (chezscheme) (std dev debug))

;; Instrument a function
(instrument
  (define (factorial n)
    (if (= n 0) 1 (* n (factorial (- n 1))))))

;; Run with recording
(with-recording 200
  (lambda ()
    (factorial 5)))

;; Inspect the recording
(debug-rewind)
(printf "Total frames: ~a~%" (debug-frame-count))

;; Walk through
(let loop ([i 0])
  (when (< i (min 10 (debug-frame-count)))
    (let ([entry (list-ref (debug-history) i)])
      (printf "Frame ~a: ~a~%" i entry))
    (loop (+ i 1))))
```

---

## Performance Profiler

**Import:** `(std dev profile)`

### Deterministic profiling

Records every call and measures wall-clock time.

```scheme
(profile-start!)                    ; begin recording
(profile-stop!)                     ; stop recording
(profile-reset!)                    ; clear all data

(profile-results)
;; Returns list of (name calls total-ns avg-ns min-ns max-ns)

(profile-report)                    ; print formatted table to stdout
(profile-report port)               ; print to port
```

### Instrumenting specific functions

```scheme
(with-profiling name thunk)
;; Run thunk, recording calls under name. Returns thunk's result.

(define/profiled (name args ...) body ...)
;; Define a function that automatically records itself
```

### Statistical sampling

```scheme
(sample-start!)              ; begin sampling (SIGPROF-based, simulated)
(sample-stop!)               ; stop sampling
(sample-results)             ; list of (name . hit-count)
```

### Allocation profiling

```scheme
(alloc-profile-start!)    ; begin tracking allocations
(alloc-profile-stop!)     ; stop tracking
(alloc-results)           ; list of (name . bytes-allocated)
```

### Timing utilities

```scheme
(time-call name thunk)    ; time a single call, print result
(time-thunk thunk)        ; time thunk, return nanoseconds
```

### Example

```scheme
(import (chezscheme) (std dev profile))

;; Profile a computation
(define/profiled (fib n)
  (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))

(profile-start!)
(fib 30)
(profile-stop!)

(profile-report)
;; Output:
;;   name            calls      total-ms    avg-us    min-us    max-us
;;   ---------------------------------------------------------------
;;   fib             2692537    1234.5      0.46      0.20      12.3

;; Time a single operation
(time-call "matrix-multiply"
  (lambda () (matrix-multiply A B)))
```

---

## Hot Code Reload

**Import:** `(std dev reload)`

Reload library modules without restarting the process.

### Registering modules

```scheme
(register-module! name file-path load-proc)
(register-module! name file-path load-proc dep1 dep2 ...)
;; name: symbol identifying the module (e.g., 'my-service)
;; file-path: path to the .sls source file
;; load-proc: zero-arg thunk that reloads the module
;; deps: module names this module depends on

(unregister-module! name)
(module-registered? name)   ; #t if registered
(registered-modules)        ; list of registered module names
```

### Reloading

```scheme
(reload! name)              ; force reload of module (and dependents)
(reload-if-changed! name)   ; reload only if file has changed since last load
```

### File watching

```scheme
(watch-and-reload! name interval-ms)
;; Start a background thread that checks for changes every interval-ms
;; and reloads automatically. Returns a watcher handle.

(stop-watching! name)       ; stop the background watcher
```

### Change notifications

```scheme
(on-module-change name proc)    ; register proc to call when module reloads
                                ; proc receives: (name old-mtime new-mtime)
                                ; returns handler-id
(off-module-change handler-id)  ; remove a change handler
(notify-change! name)           ; manually trigger notifications
```

### Module metadata

```scheme
(module-file name)    ; file path for module
(module-mtime name)   ; last modification time
(module-dependents name)  ; list of modules that depend on this one
```

### Example

```scheme
(import (chezscheme) (std dev reload))

;; Register the service module
(register-module! 'my-service
  "lib/my-service.sls"
  (lambda ()
    (load "lib/my-service.sls")))

;; Reload when source changes
(on-module-change 'my-service
  (lambda (name old-mtime new-mtime)
    (printf "Reloaded ~a at ~a~%" name new-mtime)))

;; Watch for changes every 500ms
(watch-and-reload! 'my-service 500)

;; ... develop with live reload ...

;; Clean up
(stop-watching! 'my-service)
```

### REPL workflow

```scheme
;; In your development REPL session:
(import (std dev reload))

;; Register all your modules
(for-each
  (lambda (mod)
    (register-module! (car mod) (cadr mod) (caddr mod)))
  '((routes   "src/routes.sls"   ,(lambda () (load "src/routes.sls")))
    (handlers "src/handlers.sls" ,(lambda () (load "src/handlers.sls")))
    (db       "src/db.sls"       ,(lambda () (load "src/db.sls")))))

;; Start file watchers
(for-each (lambda (m) (watch-and-reload! m 1000))
          '(routes handlers db))

;; Now edit source files and they reload automatically
```
