#!chezscheme
;;; test-phase8.ss — Functional tests for Phase 8: Deep Gerbil Compatibility
;;;
;;; Tests: keyword args, with-catch, hash alias, struct-out, cut/cute,
;;; iterators, gerbil-import, begin-ffi, gambit compat, HTTP client

(import (except (chezscheme)
          make-hash-table hash-table? iota 1+ 1-
          void make-list thread?)
        (jerboa core)
        (except (jerboa runtime) hash-eq)
        (std sugar)
        (std iter)
        (std compat gambit)
        (std compat gerbil-import)
        (jerboa ffi)
        (std net tcp)
        (std net request)
        (only (std misc thread) spawn thread-join! thread?))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr]
           [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: ")
           (write 'expr)
           (display " => ")
           (write result)
           (display " expected ")
           (write exp)
           (newline))))]
    [(_ expr)
     (if expr
       (set! pass-count (+ pass-count 1))
       (begin
         (set! fail-count (+ fail-count 1))
         (display "FAIL: ")
         (write 'expr)
         (display " => #f")
         (newline)))]))


;;; ======================================================================
;;; Track 36: def with Keyword Arguments
;;; ======================================================================
(display "--- Track 36: Keyword Args ---\n")

;; 36a. Basic keyword arg with default
(def (greet name greeting: (greeting "Hello"))
  (string-append greeting ", " name "!"))

(check (greet "Alice") => "Hello, Alice!")
(check (greet "Bob" 'greeting: "Hi") => "Hi, Bob!")

;; 36b. Multiple keyword args
(def (make-rect width height color: (color "black") filled: (filled #f))
  (list width height color filled))

(check (make-rect 10 20) => '(10 20 "black" #f))
(check (make-rect 10 20 'color: "red") => '(10 20 "red" #f))
(check (make-rect 10 20 'filled: #t) => '(10 20 "black" #t))
(check (make-rect 10 20 'color: "blue" 'filled: #t) => '(10 20 "blue" #t))

;; 36c. Keyword args only (no positional optionals mixed in)
(def (connect host port secure: (secure #f) timeout: (timeout 30))
  (list host port secure timeout))

(check (connect "localhost" 80) => '("localhost" 80 #f 30))
(check (connect "localhost" 443 'secure: #t) => '("localhost" 443 #t 30))
(check (connect "localhost" 443 'secure: #t 'timeout: 60) => '("localhost" 443 #t 60))

;; 36d. keyword-arg-ref directly
(check (keyword-arg-ref '(color: "red" size: 42) 'color: "default") => "red")
(check (keyword-arg-ref '(color: "red" size: 42) 'size: 0) => 42)
(check (keyword-arg-ref '(color: "red") 'missing: "default") => "default")
(check (keyword-arg-ref '() 'any: 99) => 99)


;;; ======================================================================
;;; Track 37: with-catch
;;; ======================================================================
(display "--- Track 37: with-catch ---\n")

;; 37a. Catches exceptions and returns handler value
(check (with-catch
         (lambda (e) 'caught)
         (lambda () (error 'test "boom")))
       => 'caught)

;; 37b. Returns body value when no exception
(check (with-catch
         (lambda (e) 'caught)
         (lambda () (+ 1 2 3)))
       => 6)

;; 37c. Handler receives the exception object
(check (with-catch
         (lambda (e) (error-message e))
         (lambda () (error 'test "specific error")))
       => "specific error")

;; 37d. Returns #f on error (common Gerbil pattern)
(check (with-catch
         (lambda (e) #f)
         (lambda () (car '())))  ;; error: car on ()
       => #f)

;; 37e. Nested with-catch
(check (with-catch
         (lambda (e) 'outer)
         (lambda ()
           (with-catch
             (lambda (e) 'inner)
             (lambda () (error 'test "inner error")))))
       => 'inner)


;;; ======================================================================
;;; Track 38: hash Constructor Alias
;;; ======================================================================
(display "--- Track 38: hash alias ---\n")

;; 38a. Basic hash construction
(let ([h (hash (name "Alice") (age 30))])
  (check (hash-ref h 'name) => "Alice")
  (check (hash-ref h 'age) => 30))

;; 38b. Nested hash (JSON-like)
(let ([h (hash (model "gpt-4")
               (config (hash (temp 0.7) (max-tokens 100))))])
  (check (hash-ref h 'model) => "gpt-4")
  (check (hash-ref (hash-ref h 'config) 'temp) => 0.7))

;; 38c. Empty-ish hash
(let ([h (hash (x 1))])
  (check (hash-key? h 'x))
  (check (not (hash-key? h 'y))))


;;; ======================================================================
;;; Track 39: struct-out (compatibility)
;;; ======================================================================
(display "--- Track 39: struct-out ---\n")

;; 39a. struct-out is a no-op (definitions are already visible)
(defstruct point (x y))
(struct-out point)  ;; should not error

;; 39b. Verify defstruct already makes everything accessible
(let ([p (make-point 3 4)])
  (check (point? p))
  (check (point-x p) => 3)
  (check (point-y p) => 4)
  (point-x-set! p 10)
  (check (point-x p) => 10))


;;; ======================================================================
;;; Track 40: cut / cute
;;; ======================================================================
(display "--- Track 40: cut/cute ---\n")

;; 40a. Basic cut with slot
(let ([add5 (cut + <> 5)])
  (check (add5 10) => 15)
  (check (add5 0) => 5))

;; 40b. cut with multiple slots
(let ([sub (cut - <> <>)])
  (check (sub 10 3) => 7))

;; 40c. cut with slot in different position
(let ([prepend (cut cons <> '())])
  (check (prepend 'a) => '(a)))

;; 40d. cut with no slots (thunk)
(let ([get42 (cut + 40 2)])
  (check (get42) => 42))

;; 40e. cut with map
(check (map (cut * <> 2) '(1 2 3 4)) => '(2 4 6 8))

;; 40f. cut with string-append
(check (map (cut string-append "pre-" <>) '("a" "b" "c"))
       => '("pre-a" "pre-b" "pre-c"))

;; 40g. cute evaluates non-slot expressions once
(let ([counter 0])
  (let ([f (cute + <> (begin (set! counter (+ counter 1)) 10))])
    (check (f 1) => 11)
    (check (f 2) => 12)
    ;; counter should be 1, not 2 — cute evaluates the expression once
    (check counter => 1)))

;; 40h. cut with rest slot <...>
(let ([sum-all (cut + 1 <...>)])
  (check (sum-all 2 3 4) => 10))


;;; ======================================================================
;;; Track 42: for/collect and for/fold Iterators
;;; ======================================================================
(display "--- Track 42: Iterators ---\n")

;; 42a. in-list
(check (in-list '(1 2 3)) => '(1 2 3))

;; 42b. in-range
(check (in-range 5) => '(0 1 2 3 4))
(check (in-range 2 5) => '(2 3 4))
(check (in-range 0 10 3) => '(0 3 6 9))

;; 42c. in-vector
(check (in-vector '#(a b c)) => '(a b c))

;; 42d. in-string
(check (in-string "abc") => '(#\a #\b #\c))

;; 42e. in-hash-keys / in-hash-values
(let ([h (hash (a 1) (b 2))])
  (check (length (in-hash-keys h)) => 2)
  (check (length (in-hash-values h)) => 2))

;; 42f. in-indexed
(check (in-indexed '(a b c)) => '((0 . a) (1 . b) (2 . c)))

;; 42g. for — side-effecting iteration
(let ([result '()])
  (for ([x (in-list '(1 2 3))])
    (set! result (cons (* x x) result)))
  (check result => '(9 4 1)))

;; 42h. for/collect — collect results
(check (for/collect ([x (in-list '(1 2 3 4 5))])
         (* x x))
       => '(1 4 9 16 25))

;; 42i. for/collect with two iterators
(check (for/collect ([x (in-list '(1 2 3))]
                     [y (in-list '(10 20 30))])
         (+ x y))
       => '(11 22 33))

;; 42j. for/fold — accumulate
(check (for/fold ([acc 0]) ([x (in-list '(1 2 3 4 5))])
         (+ acc x))
       => 15)

;; 42k. for/or — first truthy
(check (for/or ([x (in-list '(1 2 3 4 5))])
         (and (> x 3) x))
       => 4)

;; 42l. for/and — all truthy
(check (for/and ([x (in-list '(2 4 6 8))])
         (even? x))
       => #t)
(check (for/and ([x (in-list '(2 4 5 8))])
         (even? x))
       => #f)

;; 42m. for with in-range
(check (for/collect ([i (in-range 5)])
         (* i i))
       => '(0 1 4 9 16))


;;; ======================================================================
;;; Track 43: begin-ffi (already in jerboa/ffi)
;;; ======================================================================
(display "--- Track 43: begin-ffi ---\n")

;; 43a. begin-ffi is a pass-through
(let ([result #f])
  (begin-ffi (my-func)
    (set! result 'ffi-body-executed))
  (check result => 'ffi-body-executed))

;; 43b. c-lambda creates foreign procedures
(let ([c-getpid (c-lambda () int "getpid")])
  (check (> (c-getpid) 0)))

;; 43c. define-c-lambda creates named bindings
(define-c-lambda my-getpid () int "getpid")
(check (> (my-getpid) 0))

;; 43d. c-declare is a no-op
(c-declare "#include <stdio.h>")
(check #t)  ;; no crash


;;; ======================================================================
;;; Track 44: Gambit ## Primitives Compatibility
;;; ======================================================================
(display "--- Track 44: Gambit compat ---\n")

;; 44a. gambit-object->string
(check (gambit-object->string 42) => "42")
(check (gambit-object->string "hello") => "\"hello\"")
(check (gambit-object->string '(1 2 3)) => "(1 2 3)")

;; 44b. gambit-cpu-count
(let ([n (gambit-cpu-count)])
  (check (integer? n))
  (check (> n 0)))

;; 44c. gambit-current-time-milliseconds
(let ([t1 (gambit-current-time-milliseconds)])
  (check (integer? t1))
  (check (> t1 0))
  ;; Second call should be >= first
  (let ([t2 (gambit-current-time-milliseconds)])
    (check (>= t2 t1))))

;; 44d. gambit-heap-size
(let ([size (gambit-heap-size)])
  (check (integer? size))
  (check (> size 0)))


;;; ======================================================================
;;; Track 41: Gerbil Import Translation
;;; ======================================================================
(display "--- Track 41: Import translation ---\n")

;; 41a. gerbil-import translates :std/foo to (std foo)
;; We can't test actual import inside a program easily,
;; but we can test that the module loads and export-all works
(check #t)  ;; module loaded successfully

;; 41b. export-all is a no-op
(export-all)
(check #t)


;;; ======================================================================
;;; Track 45: HTTP Client
;;; ======================================================================
(display "--- Track 45: HTTP Client ---\n")

;; We can't test real HTTP requests without a server, but we can test
;; the URL parsing and encoding utilities, and do a local round-trip.

;; 45a. parse-url — basic HTTP
(let ([u (parse-url "http://example.com/path")])
  (check (url-parts-scheme u) => "http")
  (check (url-parts-host u) => "example.com")
  (check (url-parts-port u) => 80)
  (check (url-parts-path u) => "/path"))

;; 45b. parse-url — with port
(let ([u (parse-url "http://localhost:8080/api/v1")])
  (check (url-parts-host u) => "localhost")
  (check (url-parts-port u) => 8080)
  (check (url-parts-path u) => "/api/v1"))

;; 45c. parse-url — HTTPS defaults to 443
(let ([u (parse-url "https://secure.example.com/")])
  (check (url-parts-scheme u) => "https")
  (check (url-parts-port u) => 443))

;; 45d. parse-url — no path
(let ([u (parse-url "http://example.com")])
  (check (url-parts-path u) => "/"))

;; 45e. url-encode
(check (url-encode "hello world") => "hello%20world")
(check (url-encode "a+b=c") => "a%2Bb%3Dc")
(check (url-encode "safe-string_here.txt") => "safe-string_here.txt")

;; 45f. build-query-string
(check (build-query-string '(("q" . "hello world") ("page" . "1")))
       => "q=hello%20world&page=1")

;; 45g. flatten-request-headers
(check (flatten-request-headers '(("Content-Type" . "application/json")
                                   ("Accept" . "text/html")))
       => '("Content-Type: application/json" "Accept: text/html"))

;; 45h. Local HTTP round-trip test
(let ([server (tcp-listen "127.0.0.1" 0)])
  (let ([port (tcp-server-port server)])
    ;; Start a simple HTTP server thread
    (let ([server-thread
           (spawn (lambda ()
                    (let-values ([(in out) (tcp-accept server)])
                      ;; Read request (just consume it)
                      (let loop ()
                        (let ([line (get-line in)])
                          (unless (or (eof-object? line)
                                      (string=? line "")
                                      (string=? line "\r"))
                            (loop))))
                      ;; Send response
                      (put-string out "HTTP/1.1 200 OK\r\n")
                      (put-string out "Content-Length: 13\r\n")
                      (put-string out "Content-Type: text/plain\r\n")
                      (put-string out "\r\n")
                      (put-string out "Hello, World!")
                      (flush-output-port out)
                      (close-port in)
                      (close-port out))))])
      ;; Client: make HTTP GET request
      (let ([resp (http-get (string-append "http://127.0.0.1:"
                              (number->string port) "/test"))])
        (check (request-status resp) => 200)
        (check (request-text resp) => "Hello, World!")
        (check (string? (request-header resp "content-type"))))
      (thread-join! server-thread)))
  (tcp-close server))


;;; ======================================================================
;;; Summary
;;; ======================================================================

(newline)
(display "========================================\n")
(display (string-append "Phase 8 tests: "
           (number->string pass-count) " passed, "
           (number->string fail-count) " failed\n"))
(display "========================================\n")
(when (> fail-count 0) (exit 1))
