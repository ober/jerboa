#!chezscheme
;;; Tests for batch 4: result, glob, validate, deque, path-util

(import (chezscheme)
        (std misc result)
        (std text glob)
        (std misc validate)
        (std misc deque)
        (std os path-util))

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
           (printf "FAIL: ~s => ~s (expected ~s)~n" 'expr result exp))))]))

(define-syntax check-true
  (syntax-rules ()
    [(_ expr)
     (let ([result expr])
       (if result
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (printf "FAIL: ~s => ~s (expected truthy)~n" 'expr result))))]))

(define-syntax check-false
  (syntax-rules ()
    [(_ expr)
     (let ([result expr])
       (if (not result)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (printf "FAIL: ~s => ~s (expected falsy)~n" 'expr result))))]))

(printf "--- Testing batch 4 modules ---~n")

;; ========== (std misc result) ==========
(printf "  Result...~n")

;; Basic ok/err
(check-true (ok? (ok 42)))
(check-true (err? (err "bad")))
(check (ok-value (ok 42)) => 42)
(check (err-value (err "bad")) => "bad")
(check-true (result? (ok 1)))
(check-true (result? (err "x")))
(check-false (result? 42))

;; result-map
(check (ok-value (result-map (ok 5) (lambda (x) (* x 2)))) => 10)
(check-true (err? (result-map (err "e") (lambda (x) (* x 2)))))

;; result-map-err
(check (err-value (result-map-err (err "e") string-upcase)) => "E")
(check (ok-value (result-map-err (ok 1) string-upcase)) => 1)

;; result-bind
(check (ok-value (result-bind (ok 5) (lambda (x) (ok (* x 3))))) => 15)
(check-true (err? (result-bind (ok 5) (lambda (x) (err "nope")))))
(check-true (err? (result-bind (err "e") (lambda (x) (ok 1)))))

;; result-and-then (alias)
(check (ok-value (result-and-then (ok 1) (lambda (x) (ok (+ x 1))))) => 2)

;; result-or-else
(check (ok-value (result-or-else (err "e") (lambda (e) (ok 99)))) => 99)
(check (ok-value (result-or-else (ok 1) (lambda (e) (ok 99)))) => 1)

;; result-unwrap
(check (result-unwrap (ok 42)) => 42)
(check-true (guard (exn [#t #t]) (result-unwrap (err "bad")) #f))

;; result-unwrap-or
(check (result-unwrap-or (ok 42) 0) => 42)
(check (result-unwrap-or (err "bad") 0) => 0)

;; result-fold
(check (result-fold (ok 5)
         (lambda (v) (* v 2))
         (lambda (e) -1))
  => 10)
(check (result-fold (err "x")
         (lambda (v) v)
         (lambda (e) -1))
  => -1)

;; try->result
(check-true (ok? (try->result (lambda () (+ 1 2)))))
(check (ok-value (try->result (lambda () (+ 1 2)))) => 3)
(check-true (err? (try->result (lambda () (/ 1 0)))))

;; results-collect
(check (ok-value (results-collect (list (ok 1) (ok 2) (ok 3)))) => '(1 2 3))
(check-true (err? (results-collect (list (ok 1) (err "bad") (ok 3)))))

;; result-> pipeline
(let ([r (result-> (ok 5)
           (result-map (lambda (x) (* x 2)))
           (result-bind (lambda (x) (if (> x 5) (ok x) (err "too small")))))])
  (check (ok-value r) => 10))

;; result-guard
(let-values ([(r) (result-guard (+ 1 2))])
  (check-true (ok? r))
  (check (ok-value r) => 3))

;; ========== (std text glob) ==========
(printf "  Glob...~n")

;; Simple patterns
(check-true (glob-match? "*.ss" "hello.ss"))
(check-false (glob-match? "*.ss" "hello.txt"))
(check-true (glob-match? "test-*" "test-core"))
(check-false (glob-match? "test-*" "xtest-core"))

;; ? wildcard
(check-true (glob-match? "?.ss" "a.ss"))
(check-false (glob-match? "?.ss" "ab.ss"))

;; Character classes
(check-true (glob-match? "[abc].txt" "a.txt"))
(check-true (glob-match? "[abc].txt" "b.txt"))
(check-false (glob-match? "[abc].txt" "d.txt"))

;; Negated class
(check-true (glob-match? "[!abc].txt" "d.txt"))
(check-false (glob-match? "[!abc].txt" "a.txt"))

;; Range
(check-true (glob-match? "[a-z].txt" "m.txt"))
(check-false (glob-match? "[a-z].txt" "5.txt"))

;; ** (double star)
(check-true (glob-match? "**/*.ss" "src/a/b.ss"))
(check-true (glob-match? "**.ss" "a/b/c.ss"))

;; * doesn't cross /
(check-false (glob-match? "*.ss" "a/b.ss"))

;; Exact match
(check-true (glob-match? "hello" "hello"))
(check-false (glob-match? "hello" "world"))

;; glob-filter
(check (glob-filter "*.ss" '("a.ss" "b.txt" "c.ss"))
  => '("a.ss" "c.ss"))

;; glob->regex-string
(let ([rx (glob->regex-string "*.ss")])
  (check-true (> (string-length rx) 0)))

;; glob-expand (on actual filesystem)
(let ([files (glob-expand "*.ss")])
  ;; May or may not have files in current dir, just check it doesn't crash
  (check-true (list? files)))

;; ========== (std misc validate) ==========
(printf "  Validate...~n")

;; v-required
(let-values ([(ok? errs) ((v-required "name") "Alice")])
  (check-true ok?)
  (check errs => '()))

(let-values ([(ok? errs) ((v-required "name") #f)])
  (check-false ok?)
  (check-true (= (length errs) 1)))

(let-values ([(ok? errs) ((v-required "name") "")])
  (check-false ok?))

;; v-string, v-number, v-integer
(let-values ([(ok? errs) ((v-string "x") "hi")])
  (check-true ok?))
(let-values ([(ok? errs) ((v-string "x") 42)])
  (check-false ok?))
(let-values ([(ok? errs) ((v-integer "x") 42)])
  (check-true ok?))
(let-values ([(ok? errs) ((v-integer "x") 3.14)])
  (check-false ok?))

;; v-range
(let-values ([(ok? errs) ((v-range "age" 0 150) 25)])
  (check-true ok?))
(let-values ([(ok? errs) ((v-range "age" 0 150) -1)])
  (check-false ok?))
(let-values ([(ok? errs) ((v-range "age" 0 150) 200)])
  (check-false ok?))

;; v-min-length, v-max-length
(let-values ([(ok? errs) ((v-min-length "s" 3) "hello")])
  (check-true ok?))
(let-values ([(ok? errs) ((v-min-length "s" 3) "hi")])
  (check-false ok?))
(let-values ([(ok? errs) ((v-max-length "s" 5) "hi")])
  (check-true ok?))
(let-values ([(ok? errs) ((v-max-length "s" 5) "hello world")])
  (check-false ok?))

;; v-pattern
(let-values ([(ok? errs) ((v-pattern "email" "@") "a@b.com")])
  (check-true ok?))
(let-values ([(ok? errs) ((v-pattern "email" "@") "invalid")])
  (check-false ok?))

;; v-and (composition)
(let ([check-age (v-and (v-required "age") (v-integer "age") (v-range "age" 0 150))])
  (let-values ([(ok? errs) (check-age 25)])
    (check-true ok?)
    (check errs => '()))
  (let-values ([(ok? errs) (check-age #f)])
    (check-false ok?))
  (let-values ([(ok? errs) (check-age -5)])
    (check-false ok?)))

;; v-or
(let ([check-id (v-or (v-string "id") (v-integer "id"))])
  (let-values ([(ok? errs) (check-id "abc")])
    (check-true ok?))
  (let-values ([(ok? errs) (check-id 42)])
    (check-true ok?))
  (let-values ([(ok? errs) (check-id 3.14)])
    (check-false ok?)))

;; v-member
(let-values ([(ok? errs) ((v-member "color" '("red" "green" "blue")) "red")])
  (check-true ok?))
(let-values ([(ok? errs) ((v-member "color" '("red" "green" "blue")) "yellow")])
  (check-false ok?))

;; v-each
(let-values ([(ok? errs) ((v-each "items" (v-positive "item")) '(1 2 3))])
  (check-true ok?))
(let-values ([(ok? errs) ((v-each "items" (v-positive "item")) '(1 -2 3))])
  (check-false ok?))

;; v-record
(let ([check-user (v-record
                    (list (cons 'name (v-and (v-required "name") (v-string "name")))
                          (cons 'age (v-and (v-required "age") (v-range "age" 0 150)))))])
  (let-values ([(ok? errs) (check-user '((name . "Alice") (age . 30)))])
    (check-true ok?))
  (let-values ([(ok? errs) (check-user '((name . "") (age . 200)))])
    (check-false ok?)))

;; v-predicate
(let-values ([(ok? errs) ((v-predicate "x" even? "must be even") 4)])
  (check-true ok?))
(let-values ([(ok? errs) ((v-predicate "x" even? "must be even") 3)])
  (check-false ok?))

;; ========== (std misc deque) ==========
(printf "  Deque...~n")

;; Basic operations
(let ([dq (make-deque)])
  (check-true (deque? dq))
  (check-true (deque-empty? dq))
  (check (deque-size dq) => 0)

  (deque-push-back! dq 1)
  (deque-push-back! dq 2)
  (deque-push-back! dq 3)
  (check (deque-size dq) => 3)
  (check-false (deque-empty? dq))

  (check (deque-peek-front dq) => 1)
  (check (deque-peek-back dq) => 3)

  (check (deque-pop-front! dq) => 1)
  (check (deque-pop-back! dq) => 3)
  (check (deque-size dq) => 1)
  (check (deque-pop-front! dq) => 2)
  (check-true (deque-empty? dq)))

;; Push front
(let ([dq (make-deque)])
  (deque-push-front! dq 3)
  (deque-push-front! dq 2)
  (deque-push-front! dq 1)
  (check (deque->list dq) => '(1 2 3)))

;; Mixed push/pop
(let ([dq (make-deque)])
  (deque-push-back! dq 'a)
  (deque-push-front! dq 'b)
  (deque-push-back! dq 'c)
  ;; b a c
  (check (deque-pop-front! dq) => 'b)
  (check (deque-pop-back! dq) => 'c)
  (check (deque-pop-front! dq) => 'a))

;; list->deque and deque->list
(let ([dq (list->deque '(10 20 30))])
  (check (deque->list dq) => '(10 20 30))
  (check (deque-size dq) => 3))

;; deque-clear!
(let ([dq (list->deque '(1 2 3))])
  (deque-clear! dq)
  (check-true (deque-empty? dq)))

;; deque-for-each
(let ([dq (list->deque '(1 2 3))]
      [sum 0])
  (deque-for-each (lambda (x) (set! sum (+ sum x))) dq)
  (check sum => 6))

;; deque-map
(let* ([dq (list->deque '(1 2 3))]
       [dq2 (deque-map (lambda (x) (* x 10)) dq)])
  (check (deque->list dq2) => '(10 20 30)))

;; deque-filter
(let* ([dq (list->deque '(1 2 3 4 5))]
       [dq2 (deque-filter even? dq)])
  (check (deque->list dq2) => '(2 4)))

;; Error on empty pop
(check-true (guard (exn [#t #t])
              (deque-pop-front! (make-deque))
              #f))
(check-true (guard (exn [#t #t])
              (deque-pop-back! (make-deque))
              #f))

;; Bounded deque
(let ([bq (make-bounded-deque 5)])
  (check-true (bounded-deque? bq))
  (check-true (deque? bq))
  (check (bounded-deque-capacity bq) => 5))

;; ========== (std os path-util) ==========
(printf "  Path-util...~n")

;; string-suffix?
(check-true (string-suffix? "hello.ss" ".ss"))
(check-false (string-suffix? "hello.ss" ".txt"))
(check-true (string-suffix? ".ss" ".ss"))

;; file-size
(let ([sz (file-size "tests/test-batch4.ss")])
  (check-true (and sz (> sz 0))))

;; directory-exists?
(check-true (directory-exists? "lib"))
(check-false (directory-exists? "nonexistent-dir-xyz"))

;; directory-files
(let ([files (directory-files "tests")])
  (check-true (> (length files) 0)))

;; path-find
(let ([ss-files (path-find "tests" (lambda (p) (string-suffix? p ".ss")))])
  (check-true (> (length ss-files) 3)))

;; path-glob
(let ([ss-files (path-glob "tests" "*.ss")])
  (check-true (> (length ss-files) 3)))

;; path-walk (just test it doesn't crash)
(let ([count 0])
  (path-walk "tests" (lambda (dir files subdirs)
    (set! count (+ count (length files)))))
  (check-true (> count 0)))

;; directory-files-recursive
(let ([all (directory-files-recursive "tests")])
  (check-true (> (length all) 3)))

;; ensure-directory + with-temp-directory
(with-temp-directory
  (lambda (dir)
    (check-true (directory-exists? dir))
    (ensure-directory (string-append dir "/a/b/c"))
    (check-true (directory-exists? (string-append dir "/a/b/c")))))

;; copy-file
(with-temp-directory
  (lambda (dir)
    (let ([src (string-append dir "/src.txt")]
          [dst (string-append dir "/dst.txt")])
      (call-with-output-file src
        (lambda (p) (display "hello" p)))
      (copy-file src dst)
      (check (call-with-input-file dst
               (lambda (p) (get-string-all p)))
        => "hello"))))

;; path-relative
(check (path-relative "/home/user" "/home/user/docs/file.txt")
  => "docs/file.txt")

;; path-common-prefix
(check (path-common-prefix '("/home/user/a" "/home/user/b"))
  => "/home/user/")

;; ========== Summary ==========
(printf "~n--- Results: ~a passed, ~a failed ---~n" pass-count fail-count)
(when (> fail-count 0) (exit 1))
