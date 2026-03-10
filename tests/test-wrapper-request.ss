#!chezscheme
(import (chezscheme) (std net request))

(define pass-count 0)
(define-syntax chk
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr] [exp expected])
       (if (equal? result exp) (set! pass-count (+ pass-count 1))
         (begin (display "FAIL: ") (write 'expr) (newline) (exit 1))))]))

(chk (procedure? http-get) => #t)
(chk (procedure? http-post) => #t)
(chk (procedure? url-encode) => #t)
(chk (url-encode "hello world") => "hello%20world")
(chk (url-encode "a&b=c") => "a%26b%3Dc")

(display "  request: ") (display pass-count) (display " passed") (newline)
