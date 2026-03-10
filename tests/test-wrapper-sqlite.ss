#!chezscheme
(import (chezscheme) (std db sqlite))

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

(define test-db "/tmp/jerboa-sqlite-test.db")
(when (file-exists? test-db) (delete-file test-db))

;; Open
(define db (sqlite-open test-db))
(chk (not (zero? db)) => #t)

;; Create + insert
(sqlite-exec db "CREATE TABLE t (id INTEGER PRIMARY KEY, val TEXT)")
(sqlite-eval db "INSERT INTO t (val) VALUES (?)" "hello")
(sqlite-eval db "INSERT INTO t (val) VALUES (?)" "world")
(chk (sqlite-last-insert-rowid db) => 2)
(chk (sqlite-changes db) => 1)

;; Query
(let ([rows (sqlite-query db "SELECT id, val FROM t ORDER BY id")])
  (chk (length rows) => 2)
  (chk (vector-ref (car rows) 1) => "hello")
  (chk (vector-ref (cadr rows) 1) => "world"))

;; Cleanup
(sqlite-close db)
(delete-file test-db)

(newline)
(display "sqlite wrapper: ")
(display pass) (display " passed, ")
(display fail) (display " failed") (newline)
(when (> fail 0) (exit 1))
