#!chezscheme
;;; Tests for safe-by-default prelude, finalizer safety net, lint rules,
;;; and SQL injection detection.

(import (chezscheme)
        (std safe)
        (std lint)
        (std error conditions))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(printf "--- Safe Prelude & Safety Net Tests ---~%~%")

;; =========================================================================
;; 1. Finalizer safety net infrastructure
;; =========================================================================

(printf "~%-- Finalizer safety net --~%")

(test "poll-resource-finalizers! returns 0 when clean"
  (begin (collect) (poll-resource-finalizers!))
  0)

(test "*resource-finalizer-log* is a parameter"
  (procedure? *resource-finalizer-log*)
  #t)

(test "custom finalizer log captures warnings"
  (let ([warnings '()])
    (parameterize ([*resource-finalizer-log*
                    (lambda (type info)
                      (set! warnings (cons (cons type info) warnings)))])
      ;; Polling with nothing pending should be fine
      (poll-resource-finalizers!)
      (null? warnings)))
  #t)

;; =========================================================================
;; 2. Lint: unsafe-import rule
;; =========================================================================

(printf "~%-- Lint: unsafe-import rule --~%")

(test "unsafe-import: sqlite-native flagged"
  (let* ([linter (make-linter)]
         [results (lint-string linter "(import (std db sqlite-native))")]
         [rules (map lint-result-rule results)])
    (if (memq 'unsafe-import rules) #t #f))
  #t)

(test "unsafe-import: tcp-raw flagged"
  (let* ([linter (make-linter)]
         [results (lint-string linter "(import (std net tcp-raw))")]
         [rules (map lint-result-rule results)])
    (if (memq 'unsafe-import rules) #t #f))
  #t)

(test "unsafe-import: wrapped import still flagged"
  (let* ([linter (make-linter)]
         [results (lint-string linter "(import (except (std db sqlite-native) sqlite-close))")]
         [rules (map lint-result-rule results)])
    (if (memq 'unsafe-import rules) #t #f))
  #t)

(test "unsafe-import: safe import not flagged"
  (let* ([linter (make-linter)]
         [results (lint-string linter "(import (std safe))")]
         [rules (map lint-result-rule results)])
    (if (memq 'unsafe-import rules) #f #t))
  #t)

(test "unsafe-import: jerboa prelude safe not flagged"
  (let* ([linter (make-linter)]
         [results (lint-string linter "(import (jerboa prelude safe))")]
         [rules (map lint-result-rule results)])
    (if (memq 'unsafe-import rules) #f #t))
  #t)

;; =========================================================================
;; 3. Lint: bare-error rule
;; =========================================================================

(printf "~%-- Lint: bare-error rule --~%")

(test "bare-error: (error 'who msg) flagged"
  (let* ([linter (make-linter)]
         [results (lint-string linter "(error 'test \"something broke\")")]
         [rules (map lint-result-rule results)])
    (if (memq 'bare-error rules) #t #f))
  #t)

(test "bare-error: (error? x) not flagged"
  (let* ([linter (make-linter)]
         [results (lint-string linter "(error? x)")]
         [rules (map lint-result-rule results)])
    (if (memq 'bare-error rules) #f #t))
  #t)

(test "bare-error: raise with condition not flagged"
  (let* ([linter (make-linter)]
         [results (lint-string linter "(raise (condition (make-db-error 'db 'sqlite)))")]
         [rules (map lint-result-rule results)])
    (if (memq 'bare-error rules) #f #t))
  #t)

;; =========================================================================
;; 4. Lint: sql-interpolation rule
;; =========================================================================

(printf "~%-- Lint: sql-interpolation rule --~%")

(test "sql-interpolation: string-append flagged"
  (let* ([linter (make-linter)]
         [results (lint-string linter
                    "(sqlite-exec db (string-append \"SELECT * FROM \" table))")]
         [rules (map lint-result-rule results)])
    (if (memq 'sql-interpolation rules) #t #f))
  #t)

(test "sql-interpolation: format flagged"
  (let* ([linter (make-linter)]
         [results (lint-string linter
                    "(sqlite-query db (format \"SELECT * FROM ~a\" table) )")]
         [rules (map lint-result-rule results)])
    (if (memq 'sql-interpolation rules) #t #f))
  #t)

(test "sql-interpolation: safe-sqlite-exec flagged too"
  (let* ([linter (make-linter)]
         [results (lint-string linter
                    "(safe-sqlite-exec db (string-append \"DROP TABLE \" t))")]
         [rules (map lint-result-rule results)])
    (if (memq 'sql-interpolation rules) #t #f))
  #t)

(test "sql-interpolation: literal string not flagged"
  (let* ([linter (make-linter)]
         [results (lint-string linter
                    "(sqlite-query db \"SELECT * FROM users WHERE id = ?\" user-id)")]
         [rules (map lint-result-rule results)])
    (if (memq 'sql-interpolation rules) #f #t))
  #t)

;; =========================================================================
;; 5. Lint: duplicate-import rule
;; =========================================================================

(printf "~%-- Lint: duplicate-import rule --~%")

(test "duplicate-import: same module twice flagged"
  (let* ([linter (make-linter)]
         [results (lint-string linter "(import (std sort) (std sort))")]
         [rules (map lint-result-rule results)])
    (if (memq 'duplicate-import rules) #t #f))
  #t)

(test "duplicate-import: different modules not flagged"
  (let* ([linter (make-linter)]
         [results (lint-string linter "(import (std sort) (std format))")]
         [rules (map lint-result-rule results)])
    (if (memq 'duplicate-import rules) #f #t))
  #t)

;; =========================================================================
;; 6. Lint: unused-only-import rule
;; =========================================================================

(printf "~%-- Lint: unused-only-import rule --~%")

(test "unused-only-import: unused symbol flagged"
  (let* ([linter (make-linter)]
         [results (lint-string linter
                    "(import (only (std sort) sort merge)) (sort '(3 1 2))")]
         [rules (map lint-result-rule results)])
    (if (memq 'unused-only-import rules) #t #f))
  #t)

(test "unused-only-import: all symbols used not flagged"
  (let* ([linter (make-linter)]
         [results (lint-string linter
                    "(import (only (std sort) sort)) (sort '(3 1 2))")]
         [rules (map lint-result-rule results)])
    (if (memq 'unused-only-import rules) #f #t))
  #t)

;; =========================================================================
;; 7. SQL safety runtime checks
;; =========================================================================

(printf "~%-- SQL safety runtime checks --~%")

(test "check-sql-safety!: clean SQL passes"
  (guard (exn [#t #f])
    ;; Internal function, but we can test via the safe-sqlite wrappers.
    ;; Since sqlite may not be loaded, test the check indirectly:
    ;; A clean SQL string should not raise from the safety check itself.
    ;; We use *safe-mode* = 'check and call with a deliberately unavailable db
    ;; — the sql-safety check runs before the ensure-sqlite! check.
    (parameterize ([*safe-mode* 'check])
      (guard (exn
              [(db-error? exn) #t]  ;; expected: sqlite not available
              [#t #f])
        (safe-sqlite-exec 0 "SELECT 1")
        #t)))
  #t)

(test "check-sql-safety!: multi-semicolon rejected"
  (guard (exn
          [(and (db-query-error? exn)
                (message-condition? exn))
           (let ([msg (condition-message exn)])
             (and (string? msg)
                  ;; Should mention semicolons
                  (> (string-length msg) 0)))]
          [#t #f])
    (parameterize ([*safe-mode* 'check])
      (safe-sqlite-exec 0 "DROP TABLE users; DELETE FROM logs; --")
      #f))
  #t)

(test "check-sql-safety!: comment injection rejected"
  (guard (exn
          [(and (db-query-error? exn)
                (message-condition? exn))
           #t]
          [#t #f])
    (parameterize ([*safe-mode* 'check])
      (safe-sqlite-exec 0 "SELECT * FROM users WHERE 1=1 -- AND password='x'")
      #f))
  #t)

(test "check-sql-safety!: release mode skips check"
  (guard (exn
          [(db-error? exn) #t]  ;; sqlite not available — that's fine
          [#t #f])
    (parameterize ([*safe-mode* 'release])
      ;; In release mode, the SQL safety check is skipped
      (safe-sqlite-exec 0 "DROP TABLE users; DELETE FROM logs; --")
      #t))
  #t)

;; =========================================================================
;; 6. Lint rule enumeration
;; =========================================================================

(printf "~%-- Rule enumeration --~%")

(test "new rules present in default linter"
  (let ([names (lint-rule-names (make-linter))])
    (and (memq 'unsafe-import names)
         (memq 'bare-error names)
         (memq 'sql-interpolation names)
         #t))
  #t)

;; =========================================================================
;; Summary
;; =========================================================================

(printf "~%Safe prelude tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
