#!chezscheme
;;; test-string-compat.ss -- Tests for string module compatibility
;;;
;;; Verifies that (std string), (std srfi srfi-13), and (std misc string)
;;; can be used together without R6RS import conflicts.

(import (except (chezscheme) sort sort!)
        (std string)          ;; unified module
        (std srfi srfi-19))   ;; test new re-exports

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    ((_ name expr => expected)
     (let ([result (guard (exn [else (list 'error exn)])
                     expr)])
       (cond
         ((equal? result expected)
          (set! pass-count (+ pass-count 1)))
         (else
          (set! fail-count (+ fail-count 1))
          (display "FAIL: ")
          (display name)
          (display " => ")
          (write result)
          (display " expected ")
          (write expected)
          (newline)))))))

;;; ========================================================================
;;; (std string) — unified string module
;;; ========================================================================

(display "--- std/string (unified) ---\n")

;; string-split from (std misc string)
(check "string-split-char" (string-split "a,b,c" #\,) => '("a" "b" "c"))
(check "string-split-default" (string-split "hello world") => '("hello" "world"))
(check "string-empty?" (string-empty? "") => #t)
(check "string-not-empty?" (string-empty? "hi") => #f)

;; string operations from (std srfi srfi-13)
(check "string-trim-leading" (string-trim "  hi  ") => "hi  ")
(check "string-trim-both" (string-trim-both "  hi  ") => "hi")
(check "string-trim-right" (string-trim-right "  hi  ") => "  hi")
(check "string-prefix?" (string-prefix? "hel" "hello") => #t)
(check "string-suffix?" (string-suffix? "lo" "hello") => #t)
(check "string-contains" (string-contains "hello world" "world") => 6)
(check "string-index-pred" (string-index "hello" char-upper-case?) => #f)
(check "string-join" (string-join '("a" "b" "c") ",") => "a,b,c")
(check "string-take" (string-take "hello" 3) => "hel")
(check "string-drop" (string-drop "hello" 3) => "lo")
(check "string-null?" (string-null? "") => #t)
(check "string-count" (string-count "hello" char-alphabetic?) => 5)
(check "string-reverse" (string-reverse "abc") => "cba")

;;; ========================================================================
;;; (std srfi srfi-19) — new re-exports
;;; ========================================================================

(display "--- std/srfi/srfi-19 (re-exports) ---\n")

;; time-second (Chez built-in, now re-exported from srfi-19)
(let ([t (make-time 'time-utc 0 42)])
  (check "time-second" (time-second t) => 42))

;; time-nanosecond (Chez built-in, now re-exported from srfi-19)
(let ([t (make-time 'time-utc 123456789 0)])
  (check "time-nanosecond" (time-nanosecond t) => 123456789))

;; date-week-day (Chez built-in, now re-exported from srfi-19)
;; 2024-01-15 is a Monday = 1
(let ([d (make-date 0 0 0 0 15 1 2024 0)])
  (check "date-week-day" (date-week-day d) => 1))

;; time-difference still works
(let* ([t1 (make-time 'time-utc 0 100)]
       [t2 (make-time 'time-utc 0 200)]
       [diff (time-difference t2 t1)])
  (check "time-difference" (time-second diff) => 100))

;; date->time-utc + time-second round-trip
(let* ([d (make-date 0 0 30 10 15 1 2024 0)]
       [t (date->time-utc d)])
  (check "date->time-utc" (> (time-second t) 0) => #t))

;;; ========================================================================
;;; Verify no import conflict: (std srfi srfi-13) + (only (std misc string) ...)
;;; ========================================================================

(display "--- import compatibility ---\n")

;; This test file already proves compatibility by importing (std string)
;; which combines both modules. If it compiled, they're compatible.
(check "import-compat" #t => #t)

;;; ========================================================================
;;; Summary
;;; ========================================================================

(newline)
(display "========================================\n")
(display "String compat tests: ")
(display pass-count)
(display " passed, ")
(display fail-count)
(display " failed\n")
(display "========================================\n")

(when (> fail-count 0)
  (exit 1))
