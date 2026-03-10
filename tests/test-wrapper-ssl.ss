#!chezscheme
(import (chezscheme) (std net ssl))

(define pass-count 0)
(define-syntax chk
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr] [exp expected])
       (if (equal? result exp) (set! pass-count (+ pass-count 1))
         (begin (display "FAIL: ") (write 'expr) (newline) (exit 1))))]))

(chk (procedure? ssl-init!) => #t)
(chk (procedure? ssl-connect) => #t)
(chk (procedure? tcp-connect) => #t)
(chk (procedure? conn-wrap) => #t)

(display "  ssl: ") (display pass-count) (display " passed") (newline)
