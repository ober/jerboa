#!chezscheme
;;; Tests for (std misc fmt) — format string compilation

(import (chezscheme) (std misc fmt))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn
              [#t (set! fail (+ fail 1))
                  (printf "FAIL ~a: exception ~a~%" name
                    (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1))
                  (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(printf "--- (std misc fmt) tests ---~%")

;; --- pad-left / pad-right ---
(test "pad-left basic" (pad-left "hi" 5) "   hi")
(test "pad-left no pad needed" (pad-left "hello" 3) "hello")
(test "pad-left exact" (pad-left "abc" 3) "abc")
(test "pad-left custom char" (pad-left "42" 5 #\0) "00042")
(test "pad-right basic" (pad-right "hi" 5) "hi   ")
(test "pad-right no pad needed" (pad-right "hello" 3) "hello")
(test "pad-right custom char" (pad-right "x" 4 #\.) "x...")

;; --- fmt: basic ~a directive ---
(test "fmt ~a string" (fmt "hello ~a" "world") "hello world")
(test "fmt ~a number" (fmt "n=~a" 42) "n=42")
(test "fmt ~a symbol" (fmt "sym: ~a" 'foo) "sym: foo")
(test "fmt multiple ~a" (fmt "~a + ~a = ~a" 1 2 3) "1 + 2 = 3")

;; --- fmt: ~s (write) directive ---
(test "fmt ~s string" (fmt "got ~s" "hello") "got \"hello\"")
(test "fmt ~s char" (fmt "char: ~s" #\a) "char: #\\a")

;; --- fmt: numeric directives ---
(test "fmt ~d decimal" (fmt "dec: ~d" 255) "dec: 255")
(test "fmt ~b binary" (fmt "bin: ~b" 10) "bin: 1010")
(test "fmt ~o octal" (fmt "oct: ~o" 255) "oct: 377")
(test "fmt ~x hex" (fmt "hex: ~x" 255) "hex: ff")
(test "fmt ~x hex zero" (fmt "~x" 0) "0")

;; --- fmt: ~% newline ---
(test "fmt ~% newline" (fmt "line1~%line2") "line1\nline2")
(test "fmt multiple ~%" (fmt "a~%~%b") "a\n\nb")

;; --- fmt: ~~ tilde escape ---
(test "fmt ~~ tilde" (fmt "100~~") "100~")
(test "fmt ~~ in middle" (fmt "a~~b") "a~b")

;; --- fmt: ~w fixed width ---
(test "fmt ~w pad short" (fmt "~10w|" "hi") "hi        |")
(test "fmt ~w no pad long" (fmt "~3w|" "hello") "hello|")

;; --- fmt: empty and edge cases ---
(test "fmt empty string" (fmt "") "")
(test "fmt no directives" (fmt "hello") "hello")
(test "fmt only literal" (fmt "just text") "just text")

;; --- compile-format ---
(define fmt-point (compile-format "Point(~a, ~a)"))
(test "compile-format basic" (fmt-point 3 4) "Point(3, 4)")

(define fmt-hex (compile-format "0x~x"))
(test "compile-format hex" (fmt-hex 255) "0xff")

(define fmt-greeting (compile-format "Hello, ~a! You are ~d years old."))
(test "compile-format multi" (fmt-greeting "Alice" 30) "Hello, Alice! You are 30 years old.")

(define fmt-empty (compile-format ""))
(test "compile-format empty" (fmt-empty) "")

(define fmt-no-args (compile-format "constant"))
(test "compile-format no args" (fmt-no-args) "constant")

(define fmt-escapes (compile-format "100~~ done~%"))
(test "compile-format escapes" (fmt-escapes) "100~ done\n")

(define fmt-write (compile-format "val=~s"))
(test "compile-format write" (fmt-write "hi") "val=\"hi\"")

(define fmt-binary (compile-format "~b in binary"))
(test "compile-format binary" (fmt-binary 42) "101010 in binary")

(define fmt-octal (compile-format "~o in octal"))
(test "compile-format octal" (fmt-octal 255) "377 in octal")

(define fmt-width (compile-format "|~8w|"))
(test "compile-format width" (fmt-width "hi") "|hi      |")

;; --- fmt/port ---
(test "fmt/port basic"
  (let ([p (open-output-string)])
    (fmt/port p "~a=~d" "x" 42)
    (get-output-string p))
  "x=42")

(test "fmt/port newline"
  (let ([p (open-output-string)])
    (fmt/port p "a~%b")
    (get-output-string p))
  "a\nb")

;; --- Summary ---
(printf "~%~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
