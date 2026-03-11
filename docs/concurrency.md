# Concurrency Safety Toolkit

Jerboa provides three layers of concurrency safety: thread-safety annotations for
data structures, runtime deadlock detection via lock-order tracking, and resource
leak detection per thread/task.

**Import:** `(std concur)`

---

## Step 45: Thread-Safety Annotations

Annotate structs at definition time so readers of the code (and future tooling)
know the intended sharing semantics.

### Macros

```scheme
(defstruct/immutable name (field ...))
;; Fields are immutable. Instances are safe to share across threads.
;; Constructor: make-<name>
;; Predicate:   <name>?

(defstruct/thread-local name (field ...))
;; Fields are mutable. Instances should NOT be shared across threads.
;; Constructor: make-<name>
;; Predicate:   <name>?

(defstruct/thread-safe name (field ...))
;; Fields are mutable. The struct is protected by its own synchronization.
;; Constructor: make-<name>
;; Predicate:   <name>?
```

### Querying annotations

```scheme
(thread-safety-of obj)      ; => 'immutable | 'thread-local | 'thread-safe | 'unannotated
(immutable? obj)            ; #t if annotated immutable
(thread-local-marker? obj)  ; #t if annotated thread-local
```

### Example

```scheme
(import (chezscheme) (std concur))

;; Config is created once and shared everywhere
(defstruct/immutable config (host port db-url))

;; Per-thread scratch space
(defstruct/thread-local scratch (buf pos))

;; Shared counter with internal locking
(defstruct/thread-safe shared-counter (value mutex))

(let ([cfg (make-config "localhost" 5432 "mydb")])
  (printf "host: ~a~%" (config-host cfg))
  (printf "safe to share: ~a~%" (immutable? cfg)))    ; => #t

(let ([s (make-scratch (make-bytevector 1024) 0)])
  (printf "thread-local: ~a~%" (thread-local-marker? s)))  ; => #t
```

---

## Step 46: Deadlock Detection

Track mutex acquisition order across threads. When two threads acquire the same
pair of mutexes in opposite order, a potential deadlock is detected and recorded.

### Creating tracked mutexes

```scheme
(make-tracked-mutex)          ; anonymous mutex
(make-tracked-mutex "name")   ; named mutex (better error messages)
(tracked-mutex? x)            ; predicate
```

### Locking

```scheme
(tracked-lock! m)             ; acquire m, recording lock order
(tracked-unlock! m)           ; release m, removing from held set
(with-tracked-mutex m body .) ; lock, run body, unlock (unwind-safe)
```

### Inspection

```scheme
(deadlock-check!)             ; returns list of (node . path) cycles in lock graph
(lock-order-violations)       ; list of recorded potential violations
(reset-lock-tracking!)        ; clear all tracking state
```

### How it works

1. When thread T acquires mutex B while holding mutex A, an edge A→B is added to
   the global lock-order graph
2. Before adding the edge, a BFS from B checks if B can already reach A — if so,
   a cycle would form and a violation is recorded
3. `deadlock-check!` runs a full DFS over the graph to find all cycles
4. Violations are recorded but do not prevent the lock acquisition — this is a
   detector, not a prevention mechanism

### Example

```scheme
(import (chezscheme) (std concur))

(reset-lock-tracking!)

(let ([mu-db    (make-tracked-mutex "database")]
      [mu-cache (make-tracked-mutex "cache")])

  ;; Thread 1: always db → cache
  (fork-thread
    (lambda ()
      (with-tracked-mutex mu-db
        (with-tracked-mutex mu-cache
          (display "Thread 1 working\n")))))

  ;; Thread 2: accidentally cache → db (WRONG ORDER)
  (fork-thread
    (lambda ()
      (with-tracked-mutex mu-cache
        (with-tracked-mutex mu-db
          (display "Thread 2 working\n")))))

  (sleep (make-time 'time-duration 100000000 0)) ; wait 100ms

  (let ([violations (lock-order-violations)])
    (when (> (length violations) 0)
      (printf "WARNING: ~a lock-order violation(s) detected~%" (length violations))
      (for-each (lambda (v) (printf "  ~a~%" v)) violations)))

  (let ([cycles (deadlock-check!)])
    (when (> (length cycles) 0)
      (printf "CYCLES in lock graph: ~a~%" cycles))))
```

---

## Step 47: Resource Leak Detection

Track open resources (files, sockets, FFI handles) per thread. Detect when a
thread exits with unclosed resources.

### Registration

```scheme
(register-resource! type)           ; register a resource; returns resource-id
(register-resource! type "desc")    ; with optional description
(close-resource! rid)               ; mark resource as closed
```

### Inspection

```scheme
(task-resources)        ; list of (id type desc) for current thread's open resources
(open-resource-count)   ; number of open resources on current thread
(check-resource-leaks!) ; returns alist of (thread-id . resources) for ALL threads
```

### Tracking wrapper

```scheme
(with-resource-tracking thunk)
;; Runs thunk, returns (values result open-resources-at-exit)
;; open-resources-at-exit is the list of still-open resources when thunk returned
```

### Example

```scheme
(import (chezscheme) (std concur))

;; Wrap file open/close with resource tracking
(define (open-tracked-file path mode)
  (let* ([port (open-input-file path)]
         [rid  (register-resource! 'file path)])
    (cons rid port)))

(define (close-tracked-file handle)
  (close-port (cdr handle))
  (close-resource! (car handle)))

;; Safe usage
(let-values ([(result leaked)
              (with-resource-tracking
                (lambda ()
                  (let ([h (open-tracked-file "/tmp/data.txt" 'r)])
                    (let ([content (get-string-all (cdr h))])
                      (close-tracked-file h)
                      content))))])
  (printf "result: ~a~%" (string-length result))
  (when (not (null? leaked))
    (printf "LEAK: ~a unclosed resource(s)!~%" (length leaked))))

;; Find all leaks across all threads
(let ([leaks (check-resource-leaks!)])
  (for-each
    (lambda (entry)
      (printf "Thread ~a leaked: ~a~%"
        (car entry)
        (map cadr (cdr entry))))
    leaks))
```

---

## Combining All Three

```scheme
(import (chezscheme) (std concur))

;; 1. Annotate your data structures
(defstruct/immutable request (method path body))
(defstruct/thread-safe connection-pool (conns mutex))

;; 2. Use tracked mutexes for shared state
(define pool-mutex (make-tracked-mutex "pool"))

;; 3. Register resources when opening
(define (open-connection host port)
  (let ([conn (tcp-connect host port)])   ; hypothetical
    (cons (register-resource! 'tcp-conn (format "~a:~a" host port)) conn)))

(define (close-connection handle)
  (tcp-close (cdr handle))
  (close-resource! (car handle)))

;; 4. Periodically check in development
(define (run-health-check)
  (let ([violations (lock-order-violations)]
        [leaks      (check-resource-leaks!)]
        [cycles     (deadlock-check!)])
    (when (> (length violations) 0)
      (printf "Lock order violations: ~a~%" (length violations)))
    (when (> (length leaks) 0)
      (printf "Resource leaks: ~a~%" (length leaks)))
    (when (> (length cycles) 0)
      (printf "Lock cycles: ~a~%" (length cycles)))))
```
