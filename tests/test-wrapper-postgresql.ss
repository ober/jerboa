#!chezscheme
(import (chezscheme) (std db postgresql))

(define pass 0)
(define fail 0)
(define-syntax chk
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([r expr] [e expected])
       (if (equal? r e)
         (set! pass (+ pass 1))
         (begin (set! fail (+ fail 1))
                (display "FAIL: ") (write 'expr)
                (display " => ") (write r)
                (display " expected ") (write e) (newline))))]))

;; Verify constants loaded
(chk CONNECTION_OK => 0)
(chk PGRES_COMMAND_OK => 1)
(chk PGRES_TUPLES_OK => 2)

;; Verify connection failure raises error
(chk (guard (exn [#t #t])
       (pg-connect "host=localhost port=1 dbname=x connect_timeout=1")
       #f) => #t)

(newline)
(display "postgresql wrapper: ")
(display pass) (display " passed, ")
(display fail) (display " failed") (newline)
(when (> fail 0) (exit 1))
