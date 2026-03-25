#!chezscheme
(import (chezscheme) (std db duckdb))

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

;; Open in-memory database
(define db (duckdb-open ":memory:"))
(chk (not (zero? db)) => #t)

;; Create table + insert
(duckdb-exec db "CREATE TABLE t (id INTEGER, name VARCHAR, score DOUBLE, active BOOLEAN)")
(duckdb-eval db "INSERT INTO t VALUES (?, ?, ?, ?)" 1 "alice" 95.5 #t)
(duckdb-eval db "INSERT INTO t VALUES (?, ?, ?, ?)" 2 "bob" 87.3 #f)
(duckdb-eval db "INSERT INTO t VALUES (?, ?, ?, ?)" 3 "carol" 91.0 #t)

;; Query all rows
(let ([rows (duckdb-query db "SELECT id, name, score, active FROM t ORDER BY id")])
  (chk (length rows) => 3)
  ;; First row
  (let ([r (car rows)])
    (chk (cdr (assoc "id" r)) => 1)
    (chk (cdr (assoc "name" r)) => "alice")
    (chk (cdr (assoc "score" r)) => 95.5)
    (chk (cdr (assoc "active" r)) => #t))
  ;; Second row
  (let ([r (cadr rows)])
    (chk (cdr (assoc "id" r)) => 2)
    (chk (cdr (assoc "name" r)) => "bob")
    (chk (cdr (assoc "active" r)) => #f)))

;; Query with parameters
(let ([rows (duckdb-query db "SELECT name FROM t WHERE score > ?" 90.0)])
  (chk (length rows) => 2)
  (chk (cdr (assoc "name" (car rows))) => "alice"))

;; NULL handling
(duckdb-eval db "INSERT INTO t VALUES (?, ?, ?, ?)" 4 #f #f #f)
(let ([rows (duckdb-query db "SELECT name, score FROM t WHERE id = 4")])
  (chk (length rows) => 1)
  (chk (cdr (assoc "name" (car rows))) => #f)   ;; NULL
  (chk (cdr (assoc "score" (car rows))) => #f))  ;; NULL

;; Aggregation (DuckDB's strength)
(let ([rows (duckdb-query db "SELECT COUNT(*) as cnt, AVG(score) as avg_score FROM t WHERE score IS NOT NULL")])
  (chk (length rows) => 1)
  (chk (cdr (assoc "cnt" (car rows))) => 3))

;; DuckDB-specific features: generate_series
(let ([rows (duckdb-query db "SELECT * FROM generate_series(1, 5) AS t(n)")])
  (chk (length rows) => 5))

;; Cleanup
(duckdb-close db)

(newline)
(display "duckdb wrapper: ")
(display pass) (display " passed, ")
(display fail) (display " failed") (newline)
(when (> fail 0) (exit 1))
