#!chezscheme
;;; test-restrict-hardened.ss -- Tests for hardened (std security restrict)
;;; Verifies allowlist-only sandbox approach

(import (chezscheme) (std security restrict))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr] [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: ") (write 'expr)
           (display " => ") (write result)
           (display " expected ") (write exp) (newline))))]))

;; === Safe operations work ===
(check (restricted-eval '(+ 1 2)) => 3)
(check (restricted-eval '(* 6 7)) => 42)
(check (restricted-eval '(string-append "a" "b")) => "ab")
(check (restricted-eval '(map (lambda (x) (* x x)) '(1 2 3))) => '(1 4 9))
(check (restricted-eval '(filter (lambda (x) (> x 2)) '(1 2 3 4))) => '(3 4))
(check (restricted-eval '(let ([h (make-eq-hashtable)]) (hashtable-set! h 'k 42) (hashtable-ref h 'k #f))) => 42)
(check (restricted-eval '(let ([p (open-output-string)]) (display "hi" p) (get-output-string p))) => "hi")
(check (restricted-eval '(guard (e [#t "caught"]) (error 'x "boom"))) => "caught")
(check (restricted-eval-string "(+ 10 20)") => 30)

;; === SECURITY: All dangerous operations blocked ===

;; File I/O
(check (guard (e [#t 'blocked]) (restricted-eval '(open-input-file "/etc/passwd"))) => 'blocked)
(check (guard (e [#t 'blocked]) (restricted-eval '(open-output-file "/tmp/x"))) => 'blocked)
(check (guard (e [#t 'blocked]) (restricted-eval '(delete-file "/tmp/x"))) => 'blocked)
(check (guard (e [#t 'blocked]) (restricted-eval '(file-exists? "/etc/passwd"))) => 'blocked)
(check (guard (e [#t 'blocked]) (restricted-eval '(directory-list "/"))) => 'blocked)

;; Process execution
(check (guard (e [#t 'blocked]) (restricted-eval '(system "echo pwned"))) => 'blocked)
(check (guard (e [#t 'blocked]) (restricted-eval '(process "echo pwned"))) => 'blocked)

;; FFI
(check (guard (e [#t 'blocked]) (restricted-eval '(foreign-procedure "puts" (string) int))) => 'blocked)
(check (guard (e [#t 'blocked]) (restricted-eval '(load-shared-object "libc.so"))) => 'blocked)

;; Self-escape (eval/compile)
(check (guard (e [#t 'blocked]) (restricted-eval '(eval '(+ 1 2)))) => 'blocked)
(check (guard (e [#t 'blocked]) (restricted-eval '(compile '(lambda () 1)))) => 'blocked)

;; call/cc (can escape dynamic scope)
(check (guard (e [#t 'blocked]) (restricted-eval '(call/cc (lambda (k) k)))) => 'blocked)
(check (guard (e [#t 'blocked]) (restricted-eval '(call-with-current-continuation (lambda (k) k)))) => 'blocked)

;; Environment access
(check (guard (e [#t 'blocked]) (restricted-eval '(scheme-environment))) => 'blocked)
(check (guard (e [#t 'blocked]) (restricted-eval '(getenv "PATH"))) => 'blocked)
(check (guard (e [#t 'blocked]) (restricted-eval '(putenv "FOO" "bar"))) => 'blocked)
(check (guard (e [#t 'blocked]) (restricted-eval '(interaction-environment))) => 'blocked)

;; Code loading
(check (guard (e [#t 'blocked]) (restricted-eval '(load "evil.ss"))) => 'blocked)

;; Thread creation
(check (guard (e [#t 'blocked]) (restricted-eval '(fork-thread (lambda () 1)))) => 'blocked)

;; Exit
(check (guard (e [#t 'blocked]) (restricted-eval '(exit))) => 'blocked)

;; Extra bindings
(let ([env (make-restricted-environment (list (cons 'double (lambda (x) (* x 2)))))])
  (check (eval '(double 21) env) => 42))

(display "  restrict-hardened: ")
(display pass-count) (display " passed")
(when (> fail-count 0)
  (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
