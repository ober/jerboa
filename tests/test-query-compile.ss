#!chezscheme
;;; Tests for (std db query-compile) — SQL Query Builder

(import (chezscheme) (std db query-compile))

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
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define-syntax test-pred
  (syntax-rules ()
    [(_ name expr pred)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (pred got)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: value ~s failed predicate~%" name got)))))]))

(printf "--- (std db query-compile) tests ---~%")

;; ========== make-query / query? ==========

(test "query?/true for query"
  (query? (make-query "users"))
  #t)

(test "query?/false for non-query"
  (query? "users")
  #f)

;; ========== Simple SELECT ==========

(test "compile-query/simple select all"
  (compile-query (make-query "users"))
  '("SELECT * FROM users"))

(test "compile-query/select columns"
  (compile-query (from "users" (select '(name email))))
  '("SELECT name, email FROM users"))

(test "compile-query/select single column"
  (compile-query (from "users" (select '(id))))
  '("SELECT id FROM users"))

;; ========== WHERE clause ==========

(test "compile-query/where equality"
  (compile-query (from "users" (where '(= age 30))))
  '("SELECT * FROM users WHERE age = ?" 30))

(test "compile-query/where less-than"
  (compile-query (from "orders" (where '(< total 100))))
  '("SELECT * FROM orders WHERE total < ?" 100))

(test "compile-query/where greater-than"
  (compile-query (from "orders" (where '(> total 50))))
  '("SELECT * FROM orders WHERE total > ?" 50))

(test "compile-query/where and"
  (compile-query (from "users" (where '(and (= active #t) (> age 18)))))
  '("SELECT * FROM users WHERE (active = ? AND age > ?)" #t 18))

(test "compile-query/where or"
  (compile-query (from "users" (where '(or (= role "admin") (= role "mod")))))
  '("SELECT * FROM users WHERE (role = ? OR role = ?)" "admin" "mod"))

(test "compile-query/where not"
  (compile-query (from "users" (where '(not (= deleted #t)))))
  '("SELECT * FROM users WHERE NOT (deleted = ?)" #t))

(test "compile-query/where is-null"
  (compile-query (from "users" (where '(is-null email))))
  '("SELECT * FROM users WHERE email IS NULL"))

(test "compile-query/where is-not-null"
  (compile-query (from "users" (where '(is-not-null email))))
  '("SELECT * FROM users WHERE email IS NOT NULL"))

(test "compile-query/where like"
  (compile-query (from "users" (where '(like name "%alice%"))))
  '("SELECT * FROM users WHERE name LIKE ?" "%alice%"))

(test "compile-query/where in"
  (compile-query (from "users" (where '(in status ("active" "pending")))))
  '("SELECT * FROM users WHERE status IN (?, ?)" "active" "pending"))

;; ========== LIMIT and OFFSET ==========

(test "compile-query/with limit"
  (compile-query (from "users" (limit 10)))
  '("SELECT * FROM users LIMIT 10"))

(test "compile-query/with offset"
  (compile-query (from "users" (offset 20)))
  '("SELECT * FROM users OFFSET 20"))

(test "compile-query/with limit and offset"
  (compile-query (from "users" (limit 10) (offset 20)))
  '("SELECT * FROM users LIMIT 10 OFFSET 20"))

;; ========== ORDER BY ==========

(test "compile-query/order-by asc default"
  (compile-query (from "users" (order-by 'name)))
  '("SELECT * FROM users ORDER BY name ASC"))

(test "compile-query/order-by desc"
  (compile-query (from "users" (order-by 'created_at 'desc)))
  '("SELECT * FROM users ORDER BY created_at DESC"))

(test "compile-query/order-by multiple"
  (compile-query (from "users" (order-by 'name 'asc) (order-by 'age 'desc)))
  '("SELECT * FROM users ORDER BY name ASC, age DESC"))

;; ========== Combined ==========

(test "compile-query/full query"
  (compile-query
    (from "users"
      (select '(name email))
      (where '(= active #t))
      (order-by 'name)
      (limit 10)
      (offset 0)))
  '("SELECT name, email FROM users WHERE active = ? ORDER BY name ASC LIMIT 10 OFFSET 0" #t))

;; ========== query->string ==========

(test-pred "query->string/returns string"
  (query->string (make-query "users"))
  string?)

(test "query->string/no params in string"
  (query->string (from "items" (where '(= id 5))))
  "SELECT * FROM items WHERE id = ?")

;; ========== query-param ==========

(test-pred "query-param/creates param record"
  (query-param 'user-id 42)
  (lambda (x) (not (eq? x #f))))

(test "query-param/name accessible"
  (query-param-name (query-param 'user-id 42))
  'user-id)

(test "query-param/value accessible"
  (query-param-value (query-param 'user-id 42))
  42)

;; ========== define-query macro ==========

(define-query get-all-users
  (from "users"))

(test "define-query/creates query"
  (query? get-all-users)
  #t)

(test "define-query/compiles correctly"
  (compile-query get-all-users)
  '("SELECT * FROM users"))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
