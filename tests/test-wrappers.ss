#!chezscheme
;;; test-wrappers.ss -- Tests for chez-* wrapper modules
;;; Tests that wrapper modules load and re-export correctly.
;;; Each module is tested in a separate script invocation to handle
;;; missing dependencies gracefully.

(import (chezscheme)
        (std text yaml))

(define pass-count 0)
(define fail-count 0)

(define-syntax chk
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
           (newline))))]))

;;; ---- std/text/yaml ----
(let ([docs (yaml-load-string "name: test\nversion: 1\n")])
  (chk (list? docs) => #t)
  (chk (> (length docs) 0) => #t))

(let ([result (yaml-dump-string '(1 2 3))])
  (chk (string? result) => #t))

(let ([result (yaml-dump-string "hello")])
  (chk (string? result) => #t))

;; Round-trip
(let* ([data '((1 2 3) "hello" #t)]
       [yaml-str (yaml-dump-string data)]
       [parsed (car (yaml-load-string yaml-str))])
  (chk (list? parsed) => #t))

;; Mapping with symbol keys
(parameterize ([yaml-key-format string->symbol])
  (let ([doc (car (yaml-load-string "foo: bar\nbaz: 42\n"))])
    (chk (hashtable? doc) => #t)
    (chk (hashtable-ref doc 'foo #f) => "bar")))

;;; ---- Summary ----
(newline)
(display "Wrapper tests (yaml): ")
(display pass-count) (display " passed, ")
(display fail-count) (display " failed")
(newline)
(when (> fail-count 0) (exit 1))
