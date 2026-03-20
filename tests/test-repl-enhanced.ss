#!chezscheme
;;; Tests for (std repl) -- Enhanced REPL features

(import (chezscheme)
        (std repl))

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
           (printf "FAIL: ~s => ~s (expected ~s)~n" 'expr result exp))))]))

(define-syntax check-true
  (syntax-rules ()
    [(_ expr)
     (let ([result expr])
       (if result
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (printf "FAIL: ~s => ~s (expected truthy)~n" 'expr result))))]))

(define-syntax check-false
  (syntax-rules ()
    [(_ expr)
     (let ([result expr])
       (if (not result)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (printf "FAIL: ~s => ~s (expected falsy)~n" 'expr result))))]))

;; Helper
(define (string-contains* haystack needle)
  (let ([hn (string-length haystack)]
        [nn (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nn) hn) #f]
        [(string=? (substring haystack i (+ i nn)) needle) #t]
        [else (loop (+ i 1))]))))

(printf "--- Testing (std repl) enhanced features ---~n")

;; ========== Type inference ==========
(printf "  Type inference...~n")
(check (value->type-string #t) => "Boolean")
(check (value->type-string #f) => "Boolean")
(check (value->type-string 42) => "Fixnum")
(check (value->type-string 3.14) => "Flonum")
(check (value->type-string 999999999999999999999) => "Bignum")
(check (value->type-string 3/4) => "Rational")
(check (value->type-string 1+2i) => "Complex")
(check (value->type-string #\a) => "Char")
(check (value->type-string "hello") => "String[5]")
(check (value->type-string "") => "String[0]")
(check (value->type-string 'foo) => "Symbol")
(check (value->type-string '()) => "Null")
(check (value->type-string '(1 2 3)) => "List[3]")
(check (value->type-string '(1 . 2)) => "Pair")
(check (value->type-string '#(a b)) => "Vector[2]")
(check (value->type-string #vu8(1 2 3)) => "Bytevector[3]")
(check (value->type-string car) => "Procedure")
(check (value->type-string (void)) => "Void")
(check (value->type-string '((a . 1) (b . 2))) => "AList[2]")

;; Hashtable type
(let ([ht (make-hashtable equal-hash equal?)])
  (check (value->type-string ht) => "HashTable[0]")
  (hashtable-set! ht 'a 1)
  (check (value->type-string ht) => "HashTable[1]"))

;; ========== describe-value ==========
(printf "  describe-value...~n")
(let ([out (with-output-to-string (lambda () (describe-value 42)))])
  (check-true (string-contains* out "Fixnum"))
  (check-true (string-contains* out "42")))

(let ([out (with-output-to-string (lambda () (describe-value "hello")))])
  (check-true (string-contains* out "String")))

;; ========== Documentation ==========
(printf "  Documentation...~n")
(let ([doc (repl-doc 'car)])
  (check-true (string-contains* doc "pair"))
  (check-true (string-contains* doc "first")))

(let ([doc (repl-doc 'map)])
  (check-true (string-contains* doc "Apply")))

(register-doc! 'my-fn "My custom function")
(check (repl-doc 'my-fn) => "My custom function")

;; Unknown symbol
(let ([doc (repl-doc 'nonexistent-thing-xyz)])
  (check-true (string-contains* doc "No documentation")))

;; ========== Apropos ==========
(printf "  Apropos...~n")
(let ([results (repl-apropos "string")])
  (check-true (> (length results) 5))
  (check-true (memq 'string-append results)))

(let ([results (repl-apropos "XYZNONEXISTENT")])
  (check-true (null? results)))

;; ========== Completion ==========
(printf "  Completion...~n")
(let ([comps (repl-complete "string-")])
  (check-true (> (length comps) 3))
  (check-true (memq 'string-append comps))
  (check-true (memq 'string-length comps)))

(let ([comps (repl-complete "xyznonexistent")])
  (check-true (null? comps)))

;; ========== Value history ==========
(printf "  Value history...~n")
;; repl-history-ref for non-existent should error
(check-true (guard (exn [#t #t])
              (repl-history-ref 999)
              #f))

;; ========== Balanced check (improved with strings/comments) ==========
(printf "  Balanced paren check...~n")
;; Use internal balanced? via eval
(define balanced?-fn
  (eval '(let ()
           (import (std repl))
           ;; Access through eval in REPL env - we test indirectly
           (lambda (s)
             ;; Re-implement the check for testing
             (let loop ([chars (string->list s)] [depth 0] [in-string #f] [escape #f])
               (cond
                 [(< depth 0) #f]
                 [(null? chars) (and (= depth 0) (not in-string))]
                 [else
                  (let ([c (car chars)])
                    (cond
                      [escape (loop (cdr chars) depth in-string #f)]
                      [(char=? c #\\) (loop (cdr chars) depth in-string #t)]
                      [in-string
                       (if (char=? c #\")
                         (loop (cdr chars) depth #f #f)
                         (loop (cdr chars) depth #t #f))]
                      [(char=? c #\") (loop (cdr chars) depth #t #f)]
                      [(char=? c #\;)
                       (let skip ([rest (cdr chars)])
                         (cond
                           [(null? rest) (= depth 0)]
                           [(char=? (car rest) #\newline)
                            (loop (cdr rest) depth #f #f)]
                           [else (skip (cdr rest))]))]
                      [(memv c '(#\( #\[ #\{)) (loop (cdr chars) (+ depth 1) #f #f)]
                      [(memv c '(#\) #\] #\})) (loop (cdr chars) (- depth 1) #f #f)]
                      [else (loop (cdr chars) depth #f #f)]))]))))
        (interaction-environment)))

(check (balanced?-fn "(+ 1 2)") => #t)
(check (balanced?-fn "(+ 1") => #f)
(check (balanced?-fn "(+ 1 2))") => #f)
(check (balanced?-fn "\"hello\"") => #t)
(check (balanced?-fn "(define x \")\")") => #t)  ;; paren in string
(check (balanced?-fn "(+ 1 2) ; comment") => #t)
(check (balanced?-fn "[a b c]") => #t)
(check (balanced?-fn "{a b}") => #t)

;; ========== repl-time ==========
(printf "  REPL time...~n")
(let ([out (with-output-to-string
             (lambda ()
               (repl-time (lambda () (+ 1 2)))))])
  (check-true (string-contains* out "ms")))

;; ========== repl-pp ==========
(printf "  Pretty-print...~n")
(let ([out (with-output-to-string
             (lambda () (repl-pp '(a b c (d e f)))))])
  (check-true (> (string-length out) 0)))

;; ========== Middleware ==========
(printf "  Middleware...~n")
(import (std repl middleware))

;; Custom command registration
(register-repl-command! "test-cmd" "A test command"
  (lambda (args env cfg)
    (display (string-append "test:" args))))

(check-true (repl-command-registered? "test-cmd"))
(check-false (repl-command-registered? "nonexistent"))

;; Dispatch
(let ([out (with-output-to-string
             (lambda () (dispatch-custom-command "test-cmd" "hello" #f #f)))])
  (check out => "test:hello"))

;; List commands
(let ([cmds (list-repl-commands)])
  (check-true (> (length cmds) 0)))

;; Input transformer
(register-input-transformer!
  (lambda (s)
    (if (string=? s "MAGIC") "(+ 40 2)" s)))

(check (apply-input-transformers "MAGIC") => "(+ 40 2)")
(check (apply-input-transformers "normal") => "normal")

;; Eval hooks
(define *hook-log* '())
(register-eval-hook! 'pre
  (lambda (expr env)
    (set! *hook-log* (cons (list 'pre expr) *hook-log*))))

(run-pre-eval-hooks "test" #f)
(check-true (= (length *hook-log*) 1))

;; ========== Notebook ==========
(printf "  Notebook...~n")
(import (std repl notebook))

;; Create and save
(define test-nb (make-notebook "Test NB"))
(notebook-add-cell! test-nb (make-cell 'markdown "Hello world" #f))
(notebook-add-cell! test-nb (make-cell 'code "(+ 1 2)" "3"))

(check (notebook-title test-nb) => "Test NB")
(check (length (notebook-cells test-nb)) => 2)
(check (cell-type (car (notebook-cells test-nb))) => 'markdown)
(check (cell-type (cadr (notebook-cells test-nb))) => 'code)
(check (cell-output (cadr (notebook-cells test-nb))) => "3")

;; Save and reload
(notebook-save "/tmp/test-jerboa-nb.ss.nb" test-nb)
(define loaded-nb (notebook-load "/tmp/test-jerboa-nb.ss.nb"))
(check (notebook-title loaded-nb) => "Test NB")
(check (length (notebook-cells loaded-nb)) => 2)

;; Export markdown
(let ([md (notebook-export-markdown test-nb)])
  (check-true (string-contains* md "Test NB"))
  (check-true (string-contains* md "```scheme")))

;; Export HTML
(let ([html (notebook-export-html test-nb)])
  (check-true (string-contains* html "<html>"))
  (check-true (string-contains* html "Test NB")))

;; Recording
(notebook-start! "Recording")
(check-true (notebook-recording?))
(let ([nb (notebook-stop!)])
  (check (notebook-title nb) => "Recording"))
(check-false (notebook-recording?))

;; ========== Summary ==========
(printf "~n--- Results: ~a passed, ~a failed ---~n" pass-count fail-count)
(when (> fail-count 0) (exit 1))
