#!chezscheme
;;; Tests for #r"..." raw string reader syntax via jerboa-read-string
;;; The Jerboa reader is not installed as Chez's default reader, so we
;;; test #r"..." by calling jerboa-read-string on source strings.

(import (chezscheme) (jerboa reader))

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
     (guard (exn [#t (set! pass (+ pass 1)) (printf "  ok ~a (got expected error)~%" name)])
       (begin expr
              (set! fail (+ fail 1))
              (printf "FAIL ~a: expected error but got no error~%" name)))]))

;; Read one datum from a string via the Jerboa reader, return its value.
;; Without a path argument, jerboa-read-string returns plain (unannotated) values.
(define (read1 str)
  (car (jerboa-read-string str)))

(printf "--- Raw string reader syntax (#r\"...\") ---~%~%")

;;; === Basic identity ===

(test "plain chars unchanged"
  (read1 "#r\"abc\"") "abc")

(test "empty raw string"
  (read1 "#r\"\"") "")

(test "spaces preserved"
  (read1 "#r\"hello world\"") "hello world")

;;; === Backslash passthrough ===

(test "backslash-n is literal backslash-n, not newline"
  (read1 "#r\"\\n\"") "\\n")

(test "backslash-t is literal backslash-t, not tab"
  (read1 "#r\"\\t\"") "\\t")

(test "backslash-d is literal backslash-d"
  (read1 "#r\"\\d\"") "\\d")

;; Note: #r"\\" cannot be written — the \" is parsed as an escaped quote
;; consuming the closing ". Use two backslashes mid-string instead:
(test "double backslash mid-string"
  (read1 "#r\"a\\\\b\"") "a\\\\b")

(test "regex digit+ pattern"
  (read1 "#r\"\\d+\"") "\\d+")

(test "regex with escaped dot"
  (read1 "#r\"\\d+\\.\\d+\"") "\\d+\\.\\d+")

(test "anchors unchanged"
  (read1 "#r\"^[a-z]+$\"") "^[a-z]+$")

(test "complex regex pattern"
  (read1 "#r\"(\\w+)\\s+(\\d{2,4})\"") "(\\w+)\\s+(\\d{2,4})")

;;; === Key property: same chars, no doubling ===
;;; With normal strings, "\\d+" is 3 chars (backslash, d, plus).
;;; With raw strings, #r"\d+" is also 3 chars. They should be equal.

(test "raw string equals doubled string"
  (equal? (read1 "#r\"\\d+\"") "\\d+")
  #t)

(test "raw string length matches"
  (string-length (read1 "#r\"\\d+\\.\\d+\""))
  8)  ;; \d+\.\d+ = 8 chars: \d+\.d+ — backslash,d,+,backslash,.,backslash,d,+

;;; === Escaped quote inside raw string ===

(test "escaped quote produces literal quote"
  (read1 "#r\"foo\\\"bar\"") "foo\"bar")

(test "escaped quote at start"
  (read1 "#r\"\\\"hello\"") "\"hello")

(test "escaped quote at end"
  (read1 "#r\"hello\\\"\"") "hello\"")

;;; === Error cases ===

(test-error "unterminated raw string raises error"
  (read1 "#r\"unterminated"))

(test-error "#r without quote raises error"
  (read1 "#r123"))

;;; === Integration: raw strings work as real string values ===

(test "string? on result"
  (string? (read1 "#r\"hello\"")) #t)

(test "string=? comparison"
  (string=? (read1 "#r\"\\d+\"") "\\d+") #t)

(test "string-length on result"
  (string-length (read1 "#r\"abc\"")) 3)

(test "raw string as list element"
  (jerboa-read-string "(#r\"\\d+\" #r\"\\w+\")")
  '(("\\d+" "\\w+")))

;;; === Multiple reads from one string ===

(let ([all (jerboa-read-string "#r\"abc\" #r\"\\d+\" #r\"\"")])
  (test "multiple raw strings: count"
    (length all) 3)
  (test "multiple raw strings: first"
    (car all) "abc")
  (test "multiple raw strings: second"
    (cadr all) "\\d+")
  (test "multiple raw strings: third (empty)"
    (caddr all) ""))

;;; === Works with pregexp ===

(import (std pregexp))

(test "read1 result works in pregexp-match"
  (pregexp-match (read1 "#r\"\\d+\"") "abc123def")
  '("123"))

(test "read1 escaped dot works"
  (pregexp-match (read1 "#r\"\\d+\\.\\d+\"") "3.14")
  '("3.14"))

(test "escaped dot rejects non-dot"
  (pregexp-match (read1 "#r\"\\d+\\.\\d+\"") "314")
  #f)

;;; === Summary ===
(newline)
(printf "Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
