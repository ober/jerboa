#!chezscheme
;;; test-stdlib.ss -- Tests for Jerboa standard library modules

(import (except (chezscheme) make-hash-table hash-table? iota 1+ 1-
                             sort sort!
                             printf fprintf
                             path-extension path-absolute?
                             with-input-from-string with-output-to-string)
        (jerboa runtime)
        (std sort)
        (std format)
        (std error)
        (std text json)
        (std os path)
        (std misc string)
        (std misc list)
        (std misc alist)
        (std misc ports))

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
           (display "FAIL: ")
           (write 'expr)
           (display " => ")
           (write result)
           (display " expected ")
           (write exp)
           (newline))))]))

;;; ---- std/sort ----

(check (sort '(3 1 2) <) => '(1 2 3))
(check (sort '("b" "a" "c") string<?) => '("a" "b" "c"))
(check (sort '() <) => '())

;;; ---- std/format ----

(check (format "~a + ~a = ~a" 1 2 3) => "1 + 2 = 3")
(let ([out (open-output-string)])
  (fprintf out "hello ~a" "world")
  (check (get-output-string out) => "hello world"))

;;; ---- std/error ----

(let ([err (Error "test error" 'detail)])
  (check (error-message err) => "test error")
  (check (error-irritants err) => '(detail)))

;;; ---- std/text/json ----

;; Read
(check (string->json-object "42") => 42)
(check (string->json-object "\"hello\"") => "hello")
(check (string->json-object "true") => #t)
(check (string->json-object "false") => #f)
(check (string->json-object "[1,2,3]") => '(1 2 3))
(check (string->json-object "[]") => '())

;; Read object
(let ([obj (string->json-object "{\"name\":\"Alice\",\"age\":30}")])
  (check (hash-ref obj "name") => "Alice")
  (check (hash-ref obj "age") => 30))

;; Read nested
(let ([obj (string->json-object "{\"items\":[1,2,3]}")])
  (check (hash-ref obj "items") => '(1 2 3)))

;; Write
(check (json-object->string 42) => "42")
(check (json-object->string "hello") => "\"hello\"")
(check (json-object->string #t) => "true")
(check (json-object->string #f) => "false")
(check (json-object->string '(1 2 3)) => "[1,2,3]")

;; Write string escapes
(check (json-object->string "a\"b") => "\"a\\\"b\"")
(check (json-object->string "a\nb") => "\"a\\nb\"")

;; Roundtrip
(let ([data '(1 "two" #t #f)])
  (check (string->json-object (json-object->string data)) => data))

;;; ---- std/os/path ----

(check (path-directory "/home/user/file.txt") => "/home/user")
(check (path-strip-directory "/home/user/file.txt") => "file.txt")
(check (path-extension "/home/user/file.txt") => ".txt")
(check (path-strip-extension "/home/user/file.txt") => "/home/user/file")
(check (path-join "home" "user" "file.txt") => "home/user/file.txt")
(check (path-absolute? "/home") => #t)
(check (path-absolute? "home") => #f)

;;; ---- std/misc/string ----

(check (string-split "a,b,c" #\,) => '("a" "b" "c"))
(check (string-split "a::b::c" "::") => '("a" "b" "c"))
(check (string-split "hello") => '("hello"))
(check (string-join '("a" "b" "c") ",") => "a,b,c")
(check (string-join '("hello") " ") => "hello")
(check (string-trim "  hello  ") => "hello")
(check (string-prefix? "he" "hello") => #t)
(check (string-prefix? "xx" "hello") => #f)
(check (string-suffix? "lo" "hello") => #t)
(check (string-contains "hello world" "world") => 6)
(check (string-contains "hello" "xyz") => #f)
(check (string-index "hello" #\l) => 2)
(check (string-empty? "") => #t)
(check (string-empty? "x") => #f)

;;; ---- std/misc/list ----

(check (flatten '(1 (2 3) ((4) 5))) => '(1 2 3 4 5))
(check (unique '(1 2 1 3 2)) => '(1 2 3))
(check (snoc '(1 2) 3) => '(1 2 3))
(check (take '(1 2 3 4 5) 3) => '(1 2 3))
(check (drop '(1 2 3 4 5) 2) => '(3 4 5))
(check (every positive? '(1 2 3)) => #t)
(check (every positive? '(1 -2 3)) => #f)
(check (any negative? '(1 -2 3)) => #t)
(check (any negative? '(1 2 3)) => #f)
(check (filter-map (lambda (x) (and (> x 2) (* x 10))) '(1 2 3 4))
       => '(30 40))
(check (zip '(1 2 3) '(a b c)) => '((1 a) (2 b) (3 c)))

;;; ---- std/misc/alist ----

(let ([al '((a . 1) (b . 2) (c . 3))])
  (check (agetq 'a al) => 1)
  (check (agetq 'z al) => #f)
  (check (agetq 'z al 99) => 99))

(let ([pl '(a 1 b 2 c 3)])
  (check (pgetq 'a pl) => 1)
  (check (pgetq 'c pl) => 3)
  (check (pgetq 'z pl) => #f))

;;; ---- std/misc/ports ----

(check (with-output-to-string (lambda () (display "hello")))
       => "hello")

(check (with-input-from-string "hello"
         (lambda () (read-all-as-string (current-input-port))))
       => "hello")

(check (read-all-as-lines (open-input-string "a\nb\nc"))
       => '("a" "b" "c"))

;;; ---- Summary ----
(newline)
(display "Stdlib tests: ")
(display pass-count)
(display " passed, ")
(display fail-count)
(display " failed")
(newline)
(when (> fail-count 0) (exit 1))
