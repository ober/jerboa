#!chezscheme
;;; test-reader.ss -- Tests for the Jerboa reader

(import (chezscheme) (jerboa reader))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ((result expr)
           (exp expected))
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

(define (read1 str)
  (car (jerboa-read-string str)))

;;; Basic atoms
(check (read1 "42") => 42)
(check (read1 "-7") => -7)
(check (read1 "3.14") => 3.14)
(check (read1 "#t") => #t)
(check (read1 "#f") => #f)
(check (read1 "#true") => #t)
(check (read1 "#false") => #f)
(check (read1 "hello") => 'hello)
(check (read1 "+") => '+)
(check (read1 "-") => '-)
(check (read1 "...") => '...)

;;; Strings
(check (read1 "\"hello\"") => "hello")
(check (read1 "\"hello\\nworld\"") => "hello\nworld")
(check (read1 "\"tab\\there\"") => "tab\there")
(check (read1 "\"esc\\\"quote\"") => "esc\"quote")
(check (read1 "\"\\x41;\"") => "A")

;;; Characters
(check (read1 "#\\a") => #\a)
(check (read1 "#\\space") => #\space)
(check (read1 "#\\newline") => #\newline)
(check (read1 "#\\tab") => #\tab)
(check (read1 "#\\x41") => #\A)

;;; Lists
(check (read1 "(1 2 3)") => '(1 2 3))
(check (read1 "(a b c)") => '(a b c))
(check (read1 "(a (b c) d)") => '(a (b c) d))
(check (read1 "(a . b)") => '(a . b))
(check (read1 "()") => '())

;;; Square brackets → (list ...)
(check (read1 "[1 2 3]") => '(list 1 2 3))
(check (read1 "[]") => '(list))
(check (read1 "[a [b c]]") => '(list a (list b c)))

;;; Curly braces → (~ obj 'method args...)
(check (read1 "{draw p}") => '(~ p 'draw))
(check (read1 "{name obj}") => '(~ obj 'name))
(check (read1 "{move p 10 20}") => '(~ p 'move 10 20))

;;; Keywords
(check (symbol? (read1 "name:")) => #t)
(check (let ((s (symbol->string (read1 "name:"))))
         (and (>= (string-length s) 2)
              (string=? (substring s 0 2) "#:")))
       => #t)

;;; Quote, quasiquote, unquote
(check (read1 "'x") => '(quote x))
(check (read1 "`(a ,b)") => '(quasiquote (a (unquote b))))
(check (read1 "`(a ,@b)") => '(quasiquote (a (unquote-splicing b))))

;;; Vectors
(check (read1 "#(1 2 3)") => '#(1 2 3))
(check (read1 "#()") => '#())

;;; Bytevectors
(check (read1 "#u8(1 2 3)") => (bytevector 1 2 3))

;;; Hash-bang
(check (eq? (void) (read1 "#!void")) => #t)

;;; Hex/octal/binary numbers
(check (read1 "#xff") => 255)
(check (read1 "#o77") => 63)
(check (read1 "#b1010") => 10)

;;; Comments
(check (read1 "; comment\n42") => 42)
(check (read1 "#| block |# 42") => 42)
(check (read1 "#; skip 42") => 42)
(check (read1 "(a #; skip b)") => '(a b))
(check (read1 "(a #| comment |# b)") => '(a b))

;;; Heredoc strings
(check (read1 (string-append "#<<END" (string #\newline)
                             "hello" (string #\newline)
                             "world" (string #\newline)
                             "END"))
       => "hello\nworld")
(check (read1 (string-append "#<<X" (string #\newline) "X"))
       => "")

;;; Boxes
(check (box? (read1 "#&42")) => #t)
(check (unbox (read1 "#&42")) => 42)

;;; Multiple datums
(check (jerboa-read-string "1 2 3") => '(1 2 3))
(check (jerboa-read-string "(a) (b)") => '((a) (b)))

;;; Source locations (when path is provided)
(let ((result (car (jerboa-read-string "hello" "test.ss"))))
  (check (annotated-datum? result) => #t)
  (check (annotated-datum-value result) => 'hello)
  (check (source-location-path (annotated-datum-source result)) => "test.ss")
  (check (source-location-line (annotated-datum-source result)) => 1))

;;; Pipe symbols
(check (read1 "|hello world|") => (string->symbol "hello world"))
(check (read1 "|has\\|pipe|") => (string->symbol "has|pipe"))

;;; Syntax quote/quasiquote
(check (read1 "#'x") => '(syntax x))
(check (read1 "#`x") => '(quasisyntax x))
(check (read1 "#,x") => '(unsyntax x))
(check (read1 "#,@x") => '(unsyntax-splicing x))

;;; Summary
(newline)
(display "Reader tests: ")
(display pass-count)
(display " passed, ")
(display fail-count)
(display " failed")
(newline)
(when (> fail-count 0) (exit 1))
