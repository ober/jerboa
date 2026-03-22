# Jerboa Quickstart

Get from zero to a working Jerboa program in 5 minutes.

## 1. Install Chez Scheme

```bash
# Ubuntu/Debian
sudo apt install chezscheme

# macOS
brew install chezscheme

# From source: https://cisco.github.io/ChezScheme/
```

Verify: `scheme --version` should print 10.x or later.

## 2. Get Jerboa

```bash
git clone https://github.com/ober/jerboa.git
cd jerboa
```

## 3. Hello World

Create `hello.ss`:

```scheme
(import (jerboa prelude))

(displayln "Hello from Jerboa!")
```

Run it:

```bash
bin/jerboa run hello.ss
```

Or without the CLI wrapper:

```bash
scheme --libdirs lib --script hello.ss
```

## 4. Use the REPL

```bash
bin/jerboa
```

```
jerboa> (+ 1 2)
3
jerboa> (sort '(5 1 3 2 4) <)
(1 2 3 4 5)
jerboa> ,help
```

The REPL supports value history (`*`, `**`, `***`, `$1`, `$2`...),
inspection (`,type`, `,describe`), profiling (`,time`, `,bench`), and
40+ other commands. Type `,help` to see them all.

## 5. Define a Struct

```scheme
(import (jerboa prelude))

(defstruct point (x y))

(def (distance p)
  (let ([x (point-x p)]
        [y (point-y p)])
    (sqrt (+ (* x x) (* y y)))))

(let ([p (make-point 3 4)])
  (printf "Point: (~a, ~a)\n" (point-x p) (point-y p))
  (printf "Distance: ~a\n" (distance p)))
```

## 6. Pattern Matching

```scheme
(import (jerboa prelude))

(def (describe val)
  (match val
    ((list a b c) (format "three-element list: ~a ~a ~a" a b c))
    ((cons h t)   (format "pair: ~a . ~a" h t))
    ((? string?)  (format "string: ~a" val))
    ((? number?)  (format "number: ~a" val))
    (_            "something else")))

(displayln (describe '(1 2 3)))    ;; three-element list: 1 2 3
(displayln (describe "hello"))     ;; string: hello
(displayln (describe 42))          ;; number: 42
```

For struct pattern matching, use `(std match2)`:

```scheme
(import (jerboa prelude) (std match2))

(defstruct point (x y))
(define-match-type point point? point-x point-y)

(def (describe-point p)
  (match p
    [(point x y) (format "(~a, ~a)" x y)]))
```

## 7. Parse JSON

```scheme
(import (jerboa prelude))

(let ([data (string->json-object "{\"name\": \"Jerboa\", \"version\": 1}")])
  (displayln (hash-ref data "name"))     ;; Jerboa
  (displayln (hash-ref data "version"))) ;; 1

;; Write JSON
(displayln (json-object->string
  (list->hash-table '(("language" . "Jerboa") ("fast" . #t)))))
```

## 8. HTTP Server

```scheme
(import (jerboa prelude)
        (std net httpd)
        (std net router)
        (std text json))

(define routes
  (make-router
    (route "GET" "/" (lambda (req) '((status . 200) (body . "Hello!"))))
    (route "GET" "/api/status"
      (lambda (req)
        `((status . 200)
          (headers . (("Content-Type" . "application/json")))
          (body . ,(json-object->string
                     (list->hash-table '(("status" . "ok"))))))))))

;; Start server on port 8080
(start-httpd 8080 routes)
```

## 9. Run in a Security Sandbox

```scheme
(import (jerboa prelude safe))  ;; safe prelude: contracts + sandboxing

;; Run untrusted code with restrictions:
;; - Landlock filesystem sandboxing
;; - seccomp syscall filtering
;; - Engine-based timeout
(run-safe
  (lambda ()
    (displayln "I'm sandboxed!"))
  #:timeout 5
  #:allow-read '("/tmp"))
```

## 10. Run Tests

Create `tests/test-mylib.ss`:

```scheme
(import (chezscheme) (jerboa prelude) (std test))

(test-suite "my library"
  (test-case "addition works"
    (check (+ 1 2) => 3))
  (test-case "strings"
    (check (string-join '("a" "b") ",") => "a,b")))

(run-tests!)
```

Run:

```bash
bin/jerboa test tests/
```

## Next Steps

- Browse the [module inventory](../README.md) for available libraries
- Read the [security guide](safety-guide.md) for sandboxing details
- See the [type system docs](typing.md) for gradual typing
- Check [import-conflicts.md](import-conflicts.md) when porting from Gerbil
- Explore [examples/](../examples/) for complete programs
