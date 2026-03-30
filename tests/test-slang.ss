#!chezscheme
;;; test-slang.ss -- Tests for the Slang secure compiler
;;;
;;; Tests the compiler front-end (subset validation, rejection of unsafe
;;; forms), module declaration parsing, and code emission.

(import (chezscheme)
        (std secure compiler))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ((result expr)
           (exp expected))
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
           (newline))))]))

(define-syntax check-pred
  (syntax-rules ()
    [(_ pred expr)
     (let ((result expr))
       (if (pred result)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: (")
           (display 'pred)
           (display " ")
           (write 'expr)
           (display ") => ")
           (write result)
           (newline))))]))

;; Helper: validate forms and return error count
(define (error-count forms)
  (length (slang-validate forms)))

;; Helper: validate and get first error kind
(define (first-error-kind forms)
  (let ([errors (slang-validate forms)])
    (if (null? errors)
      #f
      (slang-error-kind (car errors)))))

;; Helper: validate and get first error message
(define (first-error-msg forms)
  (let ([errors (slang-validate forms)])
    (if (null? errors)
      #f
      (slang-error-message (car errors)))))


(display "=== Slang Compiler Tests ===\n\n")

;;; ============================================================
;;; 1. Basic safe forms should validate clean
;;; ============================================================

(display "--- Safe forms ---\n")

;; Literal values
(check (error-count '(42)) => 0)
(check (error-count '("hello")) => 0)
(check (error-count '(#t)) => 0)
(check (error-count '(#\a)) => 0)

;; Arithmetic
(check (error-count '((+ 1 2))) => 0)
(check (error-count '((* 3 (- 4 1)))) => 0)
(check (error-count '((sqrt 16))) => 0)
(check (error-count '((expt 2 10))) => 0)

;; Definitions
(check (error-count '((define x 42))) => 0)
(check (error-count '((define (f x) (+ x 1)))) => 0)
(check (error-count '((define (f x y) (+ x y)))) => 0)

;; Let forms
(check (error-count '((let ((x 1) (y 2)) (+ x y)))) => 0)
(check (error-count '((let* ((x 1) (y (+ x 1))) y))) => 0)
(check (error-count '((letrec ((f (lambda (n) (if (= n 0) 1 (* n (f (- n 1))))))) (f 5)))) => 0)

;; Conditionals
(check (error-count '((if #t 1 2))) => 0)
(check (error-count '((cond (#t 1)))) => 0)
(check (error-count '((when #t (displayln "yes")))) => 0)
(check (error-count '((unless #f (displayln "yes")))) => 0)

;; Lists
(check (error-count '((cons 1 '()))) => 0)
(check (error-count '((map add1 '(1 2 3)))) => 0)
(check (error-count '((filter positive? '(1 -2 3)))) => 0)

;; Strings
(check (error-count '((string-append "hello" " " "world"))) => 0)
(check (error-count '((string-length "hello"))) => 0)
(check (error-count '((string-split "a,b,c" #\,))) => 0)

;; Hash tables
(check (error-count '((let ((ht (make-hash-table)))
                        (hash-put! ht "key" "val")
                        (hash-ref ht "key")))) => 0)

;; Match
(check (error-count '((match 42 (42 "yes") (_ "no")))) => 0)

;; For loops
(check (error-count '((for ((x (in-range 5))) (displayln x)))) => 0)
(check (error-count '((for/collect ((x (in-range 5))) (* x x)))) => 0)
(check (error-count '((for/fold ((sum 0)) ((x (in-range 10))) (+ sum x)))) => 0)

;; Error handling
(check (error-count '((guard (exn (#t "error")) (+ 1 2)))) => 0)

;; Lambda
(check (error-count '((lambda (x) (+ x 1)))) => 0)

;; Begin
(check (error-count '((begin 1 2 3))) => 0)

;; Threading macros
(check (error-count '((-> 5 (+ 3) (* 2)))) => 0)

;; Result types
(check (error-count '((ok 42))) => 0)
(check (error-count '((err "bad"))) => 0)
(check (error-count '((unwrap (ok 42)))) => 0)

;; JSON
(check (error-count '((string->json-object "{\"key\":\"val\"}"))) => 0)

;; Path operations
(check (error-count '((path-join "/home" "user"))) => 0)

;; Channels
(check (error-count '((let ((ch (make-channel)))
                        (channel-put ch 42)
                        (channel-get ch)))) => 0)

;; Import allowed modules
(check (error-count '((import (jerboa prelude)))) => 0)
(check (error-count '((import (std text json)))) => 0)
(check (error-count '((import (std sort)))) => 0)

;; User-defined functions (unknown symbols in head position allowed)
(check (error-count '((define (my-fn x) (+ x 1))
                       (my-fn 42))) => 0)


;;; ============================================================
;;; 2. Forbidden forms should be rejected
;;; ============================================================

(display "--- Forbidden forms ---\n")

;; eval / compile / load
(check (first-error-kind '((eval '(+ 1 2)))) => 'forbidden)
(check (first-error-kind '((load "file.ss"))) => 'forbidden)
(check (first-error-kind '((compile "file.ss"))) => 'forbidden)

;; FFI
(check (first-error-kind '((foreign-procedure "puts" (string) int))) => 'forbidden)
(check (first-error-kind '((load-shared-object "libc.so"))) => 'forbidden)

;; call/cc
(check (first-error-kind '((call/cc (lambda (k) k)))) => 'forbidden)
(check (first-error-kind '((call-with-current-continuation (lambda (k) k)))) => 'forbidden)

;; Shell access
(check (first-error-kind '((system "ls"))) => 'forbidden)
(check (first-error-kind '((process-create "ls"))) => 'forbidden)

;; File access (ambient)
(check (first-error-kind '((open-input-file "/etc/passwd"))) => 'forbidden)
(check (first-error-kind '((open-output-file "/tmp/evil"))) => 'forbidden)
(check (first-error-kind '((delete-file "/tmp/target"))) => 'forbidden)

;; Global mutation
(check (first-error-kind '((set! x 42))) => 'forbidden)

;; User-defined macros
(check (first-error-kind '((define-syntax my-macro (syntax-rules () ((_) 42))))) => 'forbidden)

;; Dynamic scope
(check (first-error-kind '((make-parameter 42))) => 'forbidden)
(check (first-error-kind '((parameterize () 42))) => 'forbidden)

;; Raw read
(check (first-error-kind '((read))) => 'forbidden)

;; Sleep
(check (first-error-kind '((sleep 1000))) => 'forbidden)

;; Environment access
(check (first-error-kind '((gensym))) => 'forbidden)
(check (first-error-kind '((interaction-environment))) => 'forbidden)
(check (first-error-kind '((environment '(chezscheme)))) => 'forbidden)

;; Forbidden import modules
(check (first-error-kind '((import (std security seccomp)))) => 'forbidden)
(check (first-error-kind '((import (std os signal)))) => 'forbidden)


;;; ============================================================
;;; 3. Error messages should be informative
;;; ============================================================

(display "--- Error messages ---\n")

(check-pred string? (first-error-msg '((eval '(+ 1 2)))))
(check-pred string? (first-error-msg '((foreign-procedure "puts" (string) int))))
(check-pred string? (first-error-msg '((system "ls"))))
(check-pred string? (first-error-msg '((call/cc (lambda (k) k)))))
(check-pred string? (first-error-msg '((open-input-file "/etc/passwd"))))

;; Check that messages mention the right concern
(check-pred
  (lambda (s) (and (string? s) (> (string-length s) 0)))
  (first-error-msg '((eval '(+ 1 2)))))


;;; ============================================================
;;; 4. Multiple errors should be collected
;;; ============================================================

(display "--- Multiple errors ---\n")

(check (error-count '((eval 1)
                       (system "ls")
                       (foreign-procedure "f" () void))) => 3)

(check (error-count '((define (f) (eval 1))
                       (define (g) (system "ls")))) => 2)

;; Mix of safe and unsafe
(check (error-count '((define x 42)
                       (eval x)
                       (define y (+ x 1)))) => 1)


;;; ============================================================
;;; 5. Module declaration parsing
;;; ============================================================

(display "--- Module parsing ---\n")

;; Basic module
(let ([mod (parse-slang-module
             '((slang-module my-app
                 (require
                   (filesystem (read "/data/input.txt"))
                   (network (listen "0.0.0.0:8080")))
                 (limits
                   (max-memory-mb 64)
                   (max-connections 100)))
               (define (main) (displayln "hello"))))])
  (check (slang-module? mod) => #t)
  (check (slang-module-name mod) => 'my-app)
  (check (length (slang-module-requires mod)) => 2)
  (check (length (slang-module-limits mod)) => 2)
  (check (length (slang-module-body mod)) => 1)

  ;; Check require entries
  (let ([reqs (slang-module-requires mod)])
    (check (caar reqs) => 'filesystem)
    (check (caadr reqs) => 'network))

  ;; Check limits
  (let ([lims (slang-module-limits mod)])
    (check (cdar lims) => 64)
    (check (cdadr lims) => 100)))

;; Bare program (no module declaration)
(let ([mod (parse-slang-module
             '((define x 42)
               (displayln x)))])
  (check (slang-module? mod) => #t)
  (check (slang-module-name mod) => 'anonymous)
  (check (slang-module-requires mod) => '())
  (check (slang-module-limits mod) => '())
  (check (length (slang-module-body mod)) => 2))


;;; ============================================================
;;; 6. Configuration
;;; ============================================================

(display "--- Configuration ---\n")

;; Default config
(let ([cfg (make-slang-config)])
  (check (slang-config? cfg) => #t)
  (check (slang-config-debug? cfg) => #f)
  (check (slang-config-max-recursion cfg) => 1000)
  (check (slang-config-max-iteration cfg) => 10000000))

;; Custom config
(let ([cfg (make-slang-config
             'debug: #t
             'max-recursion: 500
             'max-iteration: 100000)])
  (check (slang-config-debug? cfg) => #t)
  (check (slang-config-max-recursion cfg) => 500)
  (check (slang-config-max-iteration cfg) => 100000))


;;; ============================================================
;;; 7. Nested forbidden forms should be caught
;;; ============================================================

(display "--- Nested detection ---\n")

;; Forbidden inside a function body
(check (error-count '((define (f) (eval '(+ 1 2))))) => 1)

;; Forbidden inside a let
(check (error-count '((let ((x (system "ls"))) x))) => 1)

;; Forbidden inside a lambda
(check (error-count '((lambda () (foreign-procedure "f" () void)))) => 1)

;; Forbidden inside an if branch
(check (error-count '((if #t (eval 1) 2))) => 1)

;; Deeply nested
(check (error-count '((define (f)
                        (let ((x 1))
                          (begin
                            (if #t
                              (eval x)
                              x)))))) => 1)

;; Forbidden inside for loop
(check (error-count '((for ((x (in-range 5)))
                        (system "ls")))) => 1)

;; Forbidden as argument
(check (error-count '((displayln (eval 42)))) => 1)


;;; ============================================================
;;; 8. Allowed forms subset inspection
;;; ============================================================

(display "--- Subset inspection ---\n")

(check-pred list? (slang-allowed-forms))
(check-pred list? (slang-forbidden-forms))
(check-pred (lambda (x) (> (length x) 0)) (slang-allowed-forms))
(check-pred (lambda (x) (> (length x) 0)) (slang-forbidden-forms))

;; Allowed forms include core constructs
(check-pred (lambda (x) (memq 'define x)) (slang-allowed-forms))
(check-pred (lambda (x) (memq 'lambda x)) (slang-allowed-forms))
(check-pred (lambda (x) (memq 'if x)) (slang-allowed-forms))
(check-pred (lambda (x) (memq 'match x)) (slang-allowed-forms))
(check-pred (lambda (x) (memq 'for/collect x)) (slang-allowed-forms))

;; Forbidden forms include dangerous operations
(check-pred (lambda (x) (memq 'eval x)) (slang-forbidden-forms))
(check-pred (lambda (x) (memq 'system x)) (slang-forbidden-forms))
(check-pred (lambda (x) (memq 'foreign-procedure x)) (slang-forbidden-forms))
(check-pred (lambda (x) (memq 'call/cc x)) (slang-forbidden-forms))


;;; ============================================================
;;; 9. slang-error condition type
;;; ============================================================

(display "--- Error conditions ---\n")

(let ([errors (slang-validate '((eval 42)))])
  (check (length errors) => 1)
  (let ([err (car errors)])
    (check (slang-error? err) => #t)
    (check (slang-error-kind err) => 'forbidden)
    (check-pred (lambda (x) (equal? x '(eval 42))) (slang-error-form err))
    (check-pred string? (slang-error-message err))))


;;; ============================================================
;;; 10. Edge cases
;;; ============================================================

(display "--- Edge cases ---\n")

;; Empty program is valid
(check (error-count '()) => 0)

;; Quoted forms should not be inspected
(check (error-count '((quote (eval (system "ls"))))) => 0)
(check (error-count '('(eval 1 2 3))) => 0)

;; Symbols by themselves (as references, not calls)
;; eval as a reference should still be flagged
(check (error-count '(eval)) => 1)

;; Numeric-only program
(check (error-count '(1 2 3)) => 0)

;; Vector literal
(check (error-count '(#(1 2 3))) => 0)


;;; ============================================================
;;; Report
;;; ============================================================

(newline)
(display "=== Results ===\n")
(printf "Passed: ~a~n" pass-count)
(printf "Failed: ~a~n" fail-count)
(printf "Total:  ~a~n" (+ pass-count fail-count))
(newline)

(when (> fail-count 0)
  (display "*** THERE WERE FAILURES ***\n")
  (exit 1))

(display "All Slang compiler tests passed.\n")
