#!chezscheme
;;; Tests for (std taint) — Taint tracking

(import (chezscheme) (std taint))

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

(define-syntax test-error
  (syntax-rules ()
    [(_ name expr)
     (guard (exn [#t (set! pass (+ pass 1)) (printf "  ok ~a~%" name)])
       expr
       (set! fail (+ fail 1))
       (printf "FAIL ~a: expected error but got none~%" name))]))

(printf "--- (std taint) tests ---~%~%")

;; ===== Taint Labels =====

(printf "-- taint labels --~%")

(test "taint-label? true for user-input-label"
  (taint-label? user-input-label)
  #t)

(test "taint-label? true for sql-label"
  (taint-label? sql-label)
  #t)

(test "taint-label? true for html-label"
  (taint-label? html-label)
  #t)

(test "taint-label? true for shell-label"
  (taint-label? shell-label)
  #t)

(test "taint-label? true for file-path-label"
  (taint-label? file-path-label)
  #t)

(test "taint-label? false for string"
  (taint-label? "not a label")
  #f)

(test "taint-label? false for symbol"
  (taint-label? 'user-input)
  #f)

(test "taint-label-name user-input"
  (taint-label-name user-input-label)
  'user-input)

(test "taint-label-name sql"
  (taint-label-name sql-label)
  'sql)

(test "taint-label-severity user-input is medium"
  (taint-label-severity user-input-label)
  'medium)

(test "taint-label-severity shell is critical"
  (taint-label-severity shell-label)
  'critical)

(test "taint-label-severity sql is high"
  (taint-label-severity sql-label)
  'high)

(test "make-taint-label creates label"
  (let ([l (make-taint-label 'custom 'low)])
    (and (taint-label? l)
         (eq? (taint-label-name l) 'custom)
         (eq? (taint-label-severity l) 'low)))
  #t)

(test-error "make-taint-label rejects invalid severity"
  (make-taint-label 'test 'extreme))

(test-error "make-taint-label rejects non-symbol name"
  (make-taint-label "not-a-symbol" 'low))

;; ===== Tainted Values =====

(printf "~%-- tainted values --~%")

(test "tainted? false for clean string"
  (tainted? "clean value")
  #f)

(test "tainted? false for number"
  (tainted? 42)
  #f)

(test "tainted? false for #f"
  (tainted? #f)
  #f)

(test "tainted? true for tainted value"
  (tainted? (taint "hello" user-input-label))
  #t)

(test "taint preserves value"
  (untaint (taint "hello" user-input-label))
  "hello")

(test "taint preserves number"
  (untaint (taint 42 user-input-label))
  42)

(test "taint-labels returns list of labels"
  (length (taint-labels (taint "x" user-input-label)))
  1)

(test "taint-labels returns empty for clean value"
  (taint-labels "clean")
  '())

(test "taint with list of labels"
  (let ([tv (taint "x" (list user-input-label html-label))])
    (length (taint-labels tv)))
  2)

(test "taint stacks on existing tainted value"
  (let* ([tv1 (taint "x" user-input-label)]
         [tv2 (taint tv1 sql-label)])
    (length (taint-labels tv2)))
  2)

(test "taint deduplicates same label"
  (let* ([tv1 (taint "x" user-input-label)]
         [tv2 (taint tv1 user-input-label)])
    (length (taint-labels tv2)))
  1)

;; ===== Untaint =====

(printf "~%-- untaint --~%")

(test "untaint removes taint"
  (tainted? (untaint (taint "hello" user-input-label)))
  #f)

(test "untaint of clean value is identity"
  (untaint "already clean")
  "already clean")

(test "untaint-with applies sanitizer"
  (untaint-with (taint "hello" html-label) string-upcase)
  "HELLO")

(test "untaint-with result is not tainted"
  (tainted? (untaint-with (taint "test" user-input-label) (lambda (x) x)))
  #f)

;; ===== Propagate Taint =====

(printf "~%-- propagate-taint --~%")

(test "propagate-taint from tainted source"
  (tainted? (propagate-taint (taint "source" user-input-label) "result"))
  #t)

(test "propagate-taint from clean source is clean"
  (tainted? (propagate-taint "clean source" "result"))
  #f)

(test "propagate-taint preserves result value"
  (untaint (propagate-taint (taint "source" user-input-label) "result"))
  "result")

;; ===== Sanitizers =====

(printf "~%-- sanitizers --~%")

(test "html-escape escapes <"
  (html-escape "<script>")
  "&lt;script&gt;")

(test "html-escape escapes &"
  (html-escape "a & b")
  "a &amp; b")

(test "html-escape escapes quotes"
  (html-escape "\"quoted\"")
  "&quot;quoted&quot;")

(test "html-escape no-op for clean string"
  (html-escape "hello world")
  "hello world")

(test "sql-escape escapes single quote"
  (sql-escape "O'Reilly")
  "O''Reilly")

(test "sql-escape no-op for clean string"
  (sql-escape "safe string")
  "safe string")

(test "shell-escape wraps in quotes"
  (let ([result (shell-escape "hello")])
    (and (string=? (substring result 0 1) "'")
         (string=? (substring result (- (string-length result) 1)
                              (string-length result)) "'")))
  #t)

;; ===== Taint Checking =====

(printf "~%-- taint checking --~%")

(test "check-not-tainted! passes for clean value"
  (begin (check-not-tainted! 'test "clean") 'ok)
  'ok)

(test "check-not-tainted! raises in taint-checking mode"
  (let ([raised #f])
    (with-taint-checking
      (guard (exn [#t (set! raised #t)])
        (check-not-tainted! 'test (taint "bad" user-input-label))))
    raised)
  #t)

(test "check-not-tainted! does not raise outside taint-checking mode"
  (let ([raised #f])
    (guard (exn [#t (set! raised #t)])
      (check-not-tainted! 'test (taint "bad" user-input-label)))
    raised)
  #f)

;; ===== Taint Flow Report =====

(printf "~%-- taint-flow-report --~%")

(test "taint-flow-report for clean value"
  (taint-flow-report "clean")
  "clean (not tainted)")

(test "taint-flow-report mentions label name"
  (let ([report (taint-flow-report (taint "x" user-input-label))])
    (string=? (substring report 0 8) "TAINTED "))
  #t)

(test "taint-flow-report is string"
  (string? (taint-flow-report (taint "x" shell-label)))
  #t)

;; ===== define-sink =====

(printf "~%-- define-sink --~%")

(define-sink safe-printer
  (lambda (x)
    (if (string? x)
      (string-length x)
      -1)))

(test "define-sink works with clean values"
  (safe-printer "hello")
  5)

(test "define-sink raises in taint-checking mode for tainted arg"
  (let ([raised #f])
    (with-taint-checking
      (guard (exn [#t (set! raised #t)])
        (safe-printer (taint "evil" sql-label))))
    raised)
  #t)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
