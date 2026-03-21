#!chezscheme
;;; test-sanitize.ss -- Tests for (std security sanitize)

(import (chezscheme) (std security sanitize))

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

(define-syntax check-error
  (syntax-rules ()
    [(_ pred expr)
     (guard (exn [(pred exn) (set! pass-count (+ pass-count 1))]
                 [#t (set! fail-count (+ fail-count 1))
                     (display "FAIL: wrong error type from ") (write 'expr) (newline)])
       expr
       (set! fail-count (+ fail-count 1))
       (display "FAIL: expected error from ") (write 'expr) (newline))]))

;; === HTML Sanitization ===
(check (sanitize-html "hello") => "hello")
(check (sanitize-html "<script>alert('xss')</script>")
  => "&lt;script&gt;alert(&#x27;xss&#x27;)&lt;/script&gt;")
(check (sanitize-html "a & b") => "a &amp; b")
(check (sanitize-html "\"quoted\"") => "&quot;quoted&quot;")
(check (sanitize-html "") => "")

;; === SQL Escaping ===
(check (sql-escape "hello") => "hello")
(check (sql-escape "O'Brien") => "O''Brien")
(check (sql-escape "back\\slash") => "back\\\\slash")
(check (sql-escape "") => "")

;; === Path Sanitization ===
(check (sanitize-path "/home/user/file.txt") => "/home/user/file.txt")
(check (sanitize-path "/home/user/../other") => "/home/other")
(check (sanitize-path "/home/./user") => "/home/user")
(check (sanitize-path "relative/path") => "relative/path")
(check (sanitize-path "/a/b/c/../../d") => "/a/d")

;; NUL byte in path raises error
(check-error path-traversal?
  (sanitize-path (string-append "/etc/" (string #\nul) "passwd")))

;; === Safe Path Join ===
(check (safe-path-join "/var/data" "file.txt") => "/var/data/file.txt")
(check (safe-path-join "/var/data/" "subdir/file.txt") => "/var/data/subdir/file.txt")

;; Path traversal is neutralized by sanitize-path (.. stripped)
(check (safe-path-join "/var/data" "../../etc/passwd") => "/var/data/etc/passwd")

;; Absolute path outside base-dir raises error
(check-error path-traversal?
  (safe-path-join "/var/data" "/etc/passwd"))

;; === Header Sanitization ===
(check (sanitize-header-value "normal value") => "normal value")
(check (sanitize-header-value "text/html; charset=utf-8") => "text/html; charset=utf-8")

;; CR/LF injection raises error
(check-error header-injection?
  (sanitize-header-value (string-append "value" (string #\return) (string #\newline) "Injected: header")))

;; NUL in header raises error
(check-error header-injection?
  (sanitize-header-value (string-append "value" (string #\nul))))

;; === URL Sanitization ===
(check (sanitize-url "http://example.com") => "http://example.com")
(check (sanitize-url "https://example.com/path") => "https://example.com/path")
(check (sanitize-url "HTTP://EXAMPLE.COM") => "HTTP://EXAMPLE.COM")

;; Dangerous schemes rejected
(check-error url-scheme-violation?
  (sanitize-url "javascript:alert(1)"))
(check-error url-scheme-violation?
  (sanitize-url "data:text/html,<script>"))
(check-error url-scheme-violation?
  (sanitize-url "ftp://evil.com"))

(display "  sanitize: ")
(display pass-count) (display " passed")
(when (> fail-count 0)
  (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
