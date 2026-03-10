#!chezscheme
;;; test-modules.ss -- Tests for module path mapping

(import (chezscheme)
        (jerboa reader))

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
           (display "FAIL: ")
           (write 'expr)
           (display " => ")
           (write result)
           (display " expected ")
           (write exp)
           (newline))))]))

(define (read-one str)
  (car (jerboa-read-string str)))

;;; ---- Module path mapping ----

;; :std/sort → (std sort)
(check (read-one ":std/sort") => '(std sort))

;; :std/text/json → (std text json)
(check (read-one ":std/text/json") => '(std text json))

;; :std/misc/string → (std misc string)
(check (read-one ":std/misc/string") => '(std misc string))

;; :myapp/core → (myapp core)
(check (read-one ":myapp/core") => '(myapp core))

;; :gerbil/core → (gerbil core)
(check (read-one ":gerbil/core") => '(gerbil core))

;; Test in import context
(check (read-one "(import :std/sort :std/text/json)")
       => '(import (std sort) (std text json)))

;; Keywords still work (keyword: syntax)
(check (let ([v (read-one "name:")])
         (and (symbol? v)
              (let ([s (symbol->string v)])
                (and (> (string-length s) 2)
                     (char=? (string-ref s 0) #\#)
                     (char=? (string-ref s 1) #\:)))))
       => #t)

;; Regular colon in middle of symbol is just a symbol
(check (read-one "foo:bar") => 'foo:bar)

;;; ---- Summary ----
(newline)
(display "Module tests: ")
(display pass-count)
(display " passed, ")
(display fail-count)
(display " failed")
(newline)
(when (> fail-count 0) (exit 1))
