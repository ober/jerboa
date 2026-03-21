#!chezscheme
;;; test-process-exec.ss -- Tests for run-process/exec (shell-injection-safe)

(import (chezscheme) (std misc process))

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

;; Basic execution
(check (run-process/exec '("echo" "hello")) => "hello\n")

;; Shell metacharacters NOT interpreted
(check (run-process/exec '("echo" "$(whoami)")) => "$(whoami)\n")
(check (run-process/exec '("echo" "`id`")) => "`id`\n")
(check (run-process/exec '("echo" "$HOME")) => "$HOME\n")
(check (run-process/exec '("echo" "a;b")) => "a;b\n")
(check (run-process/exec '("echo" "a|b")) => "a|b\n")
(check (run-process/exec '("echo" "a&&b")) => "a&&b\n")
(check (run-process/exec '("echo" "a>b")) => "a>b\n")

;; Multiple arguments
(check (run-process/exec '("printf" "%s-%s\n" "x" "y")) => "x-y\n")

;; Spaces in arguments preserved
(check (run-process/exec '("echo" "hello world")) => "hello world\n")

;; Single quotes in arguments
(check (run-process/exec '("echo" "it's")) => "it's\n")

;; Stdin data piping
(check (run-process/exec '("cat") 'stdin-data: "piped\n") => "piped\n")

;; Rejects string args (must be list)
(check (guard (e [#t 'error]) (run-process/exec "echo hi")) => 'error)

;; Rejects empty list
(check (guard (e [#t 'error]) (run-process/exec '())) => 'error)

;; Rejects non-string elements
(check (guard (e [#t 'error]) (run-process/exec '("echo" 42))) => 'error)

(display "  process-exec: ")
(display pass-count) (display " passed")
(when (> fail-count 0)
  (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
