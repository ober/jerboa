#!chezscheme
(import (except (chezscheme) make-date make-time)
        (std result)
        (std datetime)
        (std debug pp))

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

;; Helper
(define (string-contains s sub)
  (let ([slen (string-length s)]
        [sublen (string-length sub)])
    (let loop ([i 0])
      (cond
        [(> (+ i sublen) slen) #f]
        [(string=? (substring s i (+ i sublen)) sub) #t]
        [else (loop (+ i 1))]))))

;; ========== Result type ==========

(display "--- Result type ---") (newline)

;; Constructors and predicates
(chk (ok? (ok 42)) => #t)
(chk (err? (err "bad")) => #t)
(chk (result? (ok 1)) => #t)
(chk (result? "hello") => #f)

;; Unwrap
(chk (unwrap (ok 42)) => 42)
(chk (unwrap-err (err "bad")) => "bad")
(chk (unwrap-or (ok 42) 0) => 42)
(chk (unwrap-or (err "bad") 0) => 0)
(chk (unwrap-or-else (err "bad") (lambda () 99)) => 99)

;; Mapping
(chk (unwrap (map-ok add1 (ok 5))) => 6)
(chk (err? (map-ok add1 (err "bad"))) => #t)
(chk (unwrap-err (map-err string-upcase (err "bad"))) => "BAD")
(chk (ok? (map-err string-upcase (ok 5))) => #t)

;; Chaining
(chk (unwrap (and-then (ok 5) (lambda (x) (ok (* x 2))))) => 10)
(chk (err? (and-then (err "bad") (lambda (x) (ok (* x 2))))) => #t)
(chk (unwrap (or-else (err "bad") (lambda (e) (ok 0)))) => 0)
(chk (unwrap (or-else (ok 5) (lambda (e) (ok 0)))) => 5)

;; Flatten
(chk (unwrap (flatten-result (ok (ok 42)))) => 42)
(chk (unwrap (flatten-result (ok 42))) => 42)

;; try-result
(chk (ok? (try-result (+ 1 2))) => #t)
(chk (unwrap (try-result (+ 1 2))) => 3)
(chk (err? (try-result (error 'test "boom"))) => #t)

;; Collection operations
(let ([results (list (ok 1) (err "a") (ok 2) (err "b"))])
  (let ([p (results-partition results)])
    (chk (car p) => '(1 2))
    (chk (cdr p) => '("a" "b")))
  (chk (filter-ok results) => '(1 2))
  (chk (filter-err results) => '("a" "b")))

(chk (unwrap (sequence-results (list (ok 1) (ok 2) (ok 3)))) => '(1 2 3))
(chk (err? (sequence-results (list (ok 1) (err "bad") (ok 3)))) => #t)

;; result->option
(chk (result->option (ok 42)) => 42)
(chk (result->option (err "bad")) => #f)

;; ok->list / err->list
(chk (ok->list (ok 42)) => '(42))
(chk (ok->list (err "bad")) => '())
(chk (err->list (err "bad")) => '("bad"))

;; ========== DateTime ==========

(display "--- DateTime ---") (newline)

;; Construction
(let ([d (make-datetime 2024 3 25 10 30 0)])
  (chk (datetime-year d) => 2024)
  (chk (datetime-month d) => 3)
  (chk (datetime-day d) => 25)
  (chk (datetime-hour d) => 10)
  (chk (datetime-minute d) => 30)
  (chk (datetime-second d) => 0))

;; make-date
(let ([d (make-date 2024 12 31)])
  (chk (datetime-year d) => 2024)
  (chk (datetime-hour d) => 0))

;; Parsing ISO 8601
(let ([d (parse-datetime "2024-03-25T10:30:00Z")])
  (chk (datetime-year d) => 2024)
  (chk (datetime-month d) => 3)
  (chk (datetime-day d) => 25)
  (chk (datetime-hour d) => 10)
  (chk (datetime-minute d) => 30)
  (chk (datetime-offset d) => 0))

;; Parse date only
(let ([d (parse-datetime "2024-03-25")])
  (chk (datetime-year d) => 2024)
  (chk (datetime-hour d) => 0))

;; Parse with positive timezone offset
(let ([d (parse-datetime "2024-03-25T10:30:00+05:30")])
  (chk (datetime-hour d) => 10)
  (chk (datetime-offset d) => 330))

;; Parse with negative offset
(let ([d (parse-datetime "2024-03-25T10:30:00-04:00")])
  (chk (datetime-offset d) => -240))

;; Formatting
(let ([d (make-datetime 2024 3 25 10 30 0)])
  (chk (datetime->iso8601 d) => "2024-03-25T10:30:00Z")
  (chk (date->string d) => "2024-03-25")
  (chk (time->string d) => "10:30:00"))

;; Roundtrip: parse -> format -> parse
(let* ([s "2024-03-25T10:30:00Z"]
       [d (parse-datetime s)]
       [s2 (datetime->iso8601 d)])
  (chk s2 => s))

;; Epoch conversion roundtrip
(let* ([d (make-datetime 2024 3 25 10 30 0)]
       [epoch (datetime->epoch d)]
       [d2 (epoch->datetime epoch)])
  (chk (datetime-year d2) => 2024)
  (chk (datetime-month d2) => 3)
  (chk (datetime-day d2) => 25)
  (chk (datetime-hour d2) => 10)
  (chk (datetime-minute d2) => 30))

;; Unix epoch
(let ([d (epoch->datetime 0)])
  (chk (datetime-year d) => 1970)
  (chk (datetime-month d) => 1)
  (chk (datetime-day d) => 1))

;; Arithmetic
(let* ([d (make-datetime 2024 3 25 10 0 0)]
       [d2 (datetime-add d 3600)])  ;; +1 hour
  (chk (datetime-hour d2) => 11))

(let* ([d (make-datetime 2024 3 25 23 0 0)]
       [d2 (datetime-add d 7200)])  ;; +2 hours, crosses midnight
  (chk (datetime-day d2) => 26)
  (chk (datetime-hour d2) => 1))

;; Diff
(let ([d1 (make-datetime 2024 3 25 10 0 0)]
      [d2 (make-datetime 2024 3 25 11 0 0)])
  (chk (datetime-diff d2 d1) => 3600))

;; Comparison
(let ([d1 (make-datetime 2024 3 25)]
      [d2 (make-datetime 2024 3 26)])
  (chk (datetime<? d1 d2) => #t)
  (chk (datetime>? d2 d1) => #t)
  (chk (datetime=? d1 d1) => #t))

;; Calendar utilities
(chk (leap-year? 2024) => #t)
(chk (leap-year? 2023) => #f)
(chk (leap-year? 2000) => #t)
(chk (leap-year? 1900) => #f)

(chk (days-in-month 2024 2) => 29)
(chk (days-in-month 2023 2) => 28)
(chk (days-in-month 2024 1) => 31)

;; day-of-year
(chk (day-of-year 2024 1 1) => 1)
(chk (day-of-year 2024 12 31) => 366)  ;; leap year

;; Truncation
(let ([d (make-datetime 2024 3 25 10 30 45)])
  (chk (datetime-hour (datetime-floor-day d)) => 0)
  (chk (datetime-minute (datetime-floor-hour d)) => 0)
  (chk (datetime-day (datetime-floor-month d)) => 1))

;; datetime->alist
(let ([d (make-datetime 2024 3 25)])
  (chk (cdr (assq 'year (datetime->alist d))) => 2024)
  (chk (cdr (assq 'month (datetime->alist d))) => 3))

;; datetime-now returns a valid datetime
(let ([now (datetime-now)])
  (chk (>= (datetime-year now) 2024) => #t))

;; ========== Pretty printer ==========

(display "--- Pretty printer (ppd) ---") (newline)

;; Simple values
(chk (ppd-to-string 42) => "42")
(chk (ppd-to-string "hello") => "\"hello\"")
(chk (ppd-to-string 'foo) => "foo")

;; Small alist (compact)
(let ([s (ppd-to-string '((a . 1) (b . 2)))])
  (chk (string-contains s "a") => #t)
  (chk (string-contains s "1") => #t))

;; Small list (compact)
(chk (ppd-to-string '(1 2 3)) => "(1 2 3)")

;; Hash table
(let ([ht (make-hashtable equal-hash equal?)])
  (hashtable-set! ht "name" "Alice")
  (hashtable-set! ht "age" 30)
  (let ([s (ppd-to-string ht)])
    (chk (string-contains s "name") => #t)
    (chk (string-contains s "Alice") => #t)))

;; Vector
(chk (ppd-to-string '#(1 2 3)) => "#(1 2 3)")

;; ========== Summary ==========

(newline)
(display "new features: ")
(display pass) (display " passed, ")
(display fail) (display " failed") (newline)
(when (> fail 0) (exit 1))
