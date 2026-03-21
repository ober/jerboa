#!chezscheme
;;; test-config-env.ss -- Tests for env-override! whitelist (V7)
;;; Must be run with specific env vars set:
;;;   JERBOA_DB_HOST=evil.com JERBOA_DB_PORT=5433 JERBOA_SECRET=leaked scheme ...

(import (chezscheme) (std config))

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

(define tmp "/tmp/jerboa-test-config-env.scm")

;; Test 1: No schema = no overrides (default-deny)
(call-with-output-file tmp (lambda (p) (write '() p)) 'truncate)
(let ([cfg (load-config tmp)])
  (check (config-ref cfg 'secret) => #f))

;; Test 2: Schema without env-overridable flag => blocked
(call-with-output-file tmp
  (lambda (p) (write '(((db host) . "localhost")) p)) 'truncate)
(let ([cfg (load-config tmp '(((db host) string "localhost")))])
  (check (config-ref cfg '(db host)) => "localhost"))

;; Test 3: Schema WITH env-overridable #t => overridden
(call-with-output-file tmp
  (lambda (p) (write '(((db port) . "5432")) p)) 'truncate)
(let ([cfg (load-config tmp '(((db port) string "5432" #t)))])
  (check (config-ref cfg '(db port)) => "5433"))

;; Test 4: Mixed schema — only overridable keys affected
(call-with-output-file tmp
  (lambda (p) (write '(((db host) . "localhost") ((db port) . "5432")) p)) 'truncate)
(let ([cfg (load-config tmp '(((db host) string "localhost")
                               ((db port) string "5432" #t)))])
  (check (config-ref cfg '(db host)) => "localhost")  ;; blocked
  (check (config-ref cfg '(db port)) => "5433"))       ;; overridden

(guard (e [#t (void)]) (delete-file tmp))

(display "  config-env: ")
(display pass-count) (display " passed")
(when (> fail-count 0)
  (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
