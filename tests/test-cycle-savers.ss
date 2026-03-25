#!chezscheme
(import (except (chezscheme) make-date make-time partition
                make-hash-table hash-table?
                sort sort!
                printf fprintf
                path-extension path-absolute?
                with-input-from-string with-output-to-string
                iota 1+ 1-)
        (std sugar)
        (std result)
        (std misc string)
        (std csv))

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

(define (string-contains* s sub)
  (let ([slen (string-length s)]
        [sublen (string-length sub)])
    (let loop ([i 0])
      (cond
        [(> (+ i sublen) slen) #f]
        [(string=? (substring s i (+ i sublen)) sub) #t]
        [else (loop (+ i 1))]))))

;; ========== defrecord ==========

(display "--- defrecord ---") (newline)

(defrecord point (x y))

;; Constructor
(let ([p (make-point 3 4)])
  ;; Predicate
  (chk (point? p) => #t)
  (chk (point? 42) => #f)
  ;; Accessors
  (chk (point-x p) => 3)
  (chk (point-y p) => 4)
  ;; ->alist
  (chk (point->alist p) => '((x . 3) (y . 4))))

;; Printer
(let* ([p (make-point 10 20)]
       [s (let ([port (open-output-string)])
            (write p port)
            (get-output-string port))])
  (chk (string-contains* s "point") => #t)
  (chk (string-contains* s "x=") => #t)
  (chk (string-contains* s "10") => #t))

;; Multi-field record
(defrecord person (name age email))
(let ([p (make-person "Alice" 30 "alice@example.com")])
  (chk (person? p) => #t)
  (chk (person-name p) => "Alice")
  (chk (person-age p) => 30)
  (chk (person-email p) => "alice@example.com")
  (chk (length (person->alist p)) => 3))

;; ========== let-alist ==========

(display "--- let-alist ---") (newline)

;; Named bindings
(let-alist '((name . "Alice") (age . 30))
  ([name n] [age a])
  (chk n => "Alice")
  (chk a => 30))

;; Short form (field names as variable names)
(let-alist '((x . 1) (y . 2) (z . 3))
  (x y z)
  (chk (+ x y z) => 6))

;; ========== define-enum ==========

(display "--- define-enum ---") (newline)

(define-enum color (red green blue))

(chk color-red => 0)
(chk color-green => 1)
(chk color-blue => 2)

;; Predicate
(chk (color? 0) => #t)
(chk (color? 2) => #t)
(chk (color? 3) => #f)
(chk (color? -1) => #f)

;; Name lookup
(chk (color->name 0) => 'red)
(chk (color->name 1) => 'green)
(chk (color->name 2) => 'blue)

;; Reverse lookup
(chk (name->color 'red) => 0)
(chk (name->color 'blue) => 2)

;; ========== capture ==========

(display "--- capture ---") (newline)

(chk (capture (display "hello")) => "hello")
(chk (capture (display "a") (display "b") (display "c")) => "abc")
(chk (capture (write 42)) => "42")
(chk (capture (void)) => "")

;; Nested capture doesn't leak
(let ([outer (capture
               (display "outer:")
               (let ([inner (capture (display "inner"))])
                 (display inner)))])
  (chk outer => "outer:inner"))

;; ========== string-match? / string-find / string-find-all ==========

(display "--- regex convenience ---") (newline)

;; string-match?
(chk (string-match? "^[0-9]+$" "12345") => #t)
(chk (string-match? "^[0-9]+$" "abc") => #f)
(chk (string-match? "hello" "say hello world") => #t)

;; string-find
(chk (string-find "[0-9]+" "abc 123 def") => "123")
(chk (string-find "[0-9]+" "no numbers here") => #f)

;; string-find with groups
(let ([m (string-find "([a-z]+)=([0-9]+)" "key=42")])
  (chk (car m) => "key=42")
  (chk (cadr m) => "key")
  (chk (caddr m) => "42"))

;; string-find-all
(chk (string-find-all "[0-9]+" "a1b22c333") => '("1" "22" "333"))
(chk (string-find-all "[a-z]+" "123") => '())
(chk (string-find-all "\\w+" "hello world foo") => '("hello" "world" "foo"))

;; ========== CSV ==========

(display "--- CSV ---") (newline)

;; Basic reading
(let ([rows (read-csv "a,b,c\n1,2,3\n4,5,6\n")])
  (chk (length rows) => 3)
  (chk (car rows) => '("a" "b" "c"))
  (chk (cadr rows) => '("1" "2" "3")))

;; Quoted fields
(let ([rows (read-csv "name,desc\nAlice,\"has a, comma\"\n")])
  (chk (length rows) => 2)
  (chk (cadr rows) => '("Alice" "has a, comma")))

;; Escaped quotes
(let ([rows (read-csv "val\n\"she said \"\"hi\"\"\"\n")])
  (chk (cadr rows) => '("she said \"hi\"")))

;; Writing
(let ([s (rows->csv-string '(("a" "b") ("1" "2")))])
  (chk (string-contains* s "a,b") => #t)
  (chk (string-contains* s "1,2") => #t))

;; Write with quoting
(let ([s (rows->csv-string '(("has,comma" "normal")))])
  (chk (string-contains* s "\"has,comma\"") => #t))

;; csv->alists
(let ([als (csv->alists "name,age\nAlice,30\nBob,25\n")])
  (chk (length als) => 2)
  (chk (cdr (assq 'name (car als))) => "Alice")
  (chk (cdr (assq 'age (cadr als))) => "25"))

;; alists->csv roundtrip
(let* ([data (csv->alists "x,y\n1,2\n3,4\n")]
       [csv-str (alists->csv data)]
       [data2 (csv->alists csv-str)])
  (chk (length data2) => 2)
  (chk (cdr (assq 'x (car data2))) => "1"))

;; Custom delimiter (TSV)
(let ([rows (read-csv "a\tb\n1\t2\n" #\tab)])
  (chk (car rows) => '("a" "b"))
  (chk (cadr rows) => '("1" "2")))

;; Empty input
(chk (read-csv "") => '())

;; ========== Summary ==========

(newline)
(display "cycle-savers: ")
(display pass) (display " passed, ")
(display fail) (display " failed") (newline)
(when (> fail 0) (exit 1))
