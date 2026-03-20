#!chezscheme
;;; Tests for newer batch 1: list-builder, number, uri, walist, values, assert

(import (chezscheme)
        (std misc list-builder)
        (std misc number)
        (std net uri)
        (std misc walist)
        (std values)
        (std assert))

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

(printf "--- Testing newer batch 1 ---~n")

;; ========== List Builder ==========
(printf "  List builder...~n")
(check (with-list-builder (push!)
         (push! 1) (push! 2) (push! 3))
       => '(1 2 3))

;; Preserves insertion order
(check (with-list-builder (push!)
         (for-each (lambda (x) (when (> x 3) (push! x)))
                   '(1 5 2 7 3 8)))
       => '(5 7 8))

;; Empty builder
(check (with-list-builder (push!)) => '())

;; Two-arg form with peek
(check (with-list-builder (push! peek)
         (push! 'a)
         (push! 'b)
         (let ([so-far (peek)])
           (push! (length so-far))))
       => '(a b 2))

;; ========== Number utilities ==========
(printf "  Number utilities...~n")
(check-true (natural? 0))
(check-true (natural? 42))
(check-false (natural? -1))
(check-false (natural? 3.14))

(check-true (positive-integer? 1))
(check-false (positive-integer? 0))
(check-false (positive-integer? -1))

(check-true (negative? -1))
(check-true (negative? -0.5))
(check-false (negative? 0))
(check-false (negative? 1))

(check (clamp 5 0 10) => 5)
(check (clamp -3 0 10) => 0)
(check (clamp 15 0 10) => 10)

(let-values ([(q r) (divmod 7 3)])
  (check q => 2)
  (check r => 1))

(check (number->padded-string 42 5) => "00042")
(check (number->padded-string 12345 3) => "12345")  ;; wider than width
(check (number->padded-string 255 4 16) => "00ff")

(let ([s (number->human-readable 1536)])
  (check-true (string? s))
  ;; Should contain "K" for kilobytes
  (check-true (let loop ([i 0])
                (if (>= i (string-length s)) #f
                  (if (char=? (string-ref s i) #\K) #t
                    (loop (+ i 1)))))))

(check (number->human-readable 42) => "42")

(check (integer-length* 0) => 0)
(check (integer-length* 1) => 1)
(check (integer-length* 255) => 8)

(check (fixnum->flonum 42) => 42.0)

;; ========== URI parsing ==========
(printf "  URI parsing...~n")
(let ([u (uri-parse "https://user:pass@example.com:8080/path/to?key=val&a=b#frag")])
  (check (uri-scheme u) => "https")
  (check (uri-userinfo u) => "user:pass")
  (check (uri-host u) => "example.com")
  (check (uri-port u) => 8080)
  (check (uri-path u) => "/path/to")
  (check (uri-query u) => "key=val&a=b")
  (check (uri-fragment u) => "frag"))

;; Simple URL
(let ([u (uri-parse "http://example.com/test")])
  (check (uri-scheme u) => "http")
  (check (uri-host u) => "example.com")
  (check (uri-port u) => #f)
  (check (uri-path u) => "/test")
  (check (uri-query u) => #f)
  (check (uri-fragment u) => #f))

;; URI reconstruction
(let ([u (uri-parse "https://example.com:443/api?q=1")])
  (let ([s (uri->string u)])
    (check-true (string? s))
    ;; Should round-trip the essential parts
    (check-true (let loop ([i 0])
                  (if (>= i (- (string-length s) 10)) #f
                    (if (string=? "example.com" (substring s i (+ i 11))) #t
                      (loop (+ i 1))))))))

;; Percent encoding
(check (uri-encode "hello world") => "hello%20world")
(check (uri-encode "a+b=c&d") => "a%2Bb%3Dc%26d")
(check (uri-decode "hello%20world") => "hello world")
(check (uri-decode "a%2Bb") => "a+b")

;; Query string conversion
(let ([alist (query-string->alist "name=Alice&age=30&city=New+York")])
  (check-true (list? alist))
  (check-true (assoc "name" alist))
  (check (cdr (assoc "name" alist)) => "Alice")
  (check (cdr (assoc "age" alist)) => "30"))

(let ([qs (alist->query-string '(("x" . "1") ("y" . "hello world")))])
  (check-true (string? qs)))

;; ========== Weak alist ==========
(printf "  Weak alist...~n")
(let ([wa (make-walist)])
  (let ([key1 (list 'a)]
        [key2 (list 'b)])
    (walist-set! wa key1 "value1")
    (walist-set! wa key2 "value2")
    (check (walist-ref wa key1) => "value1")
    (check (walist-ref wa key2) => "value2")
    (check (walist-length wa) => 2)

    ;; Delete
    (walist-delete! wa key1)
    (check (walist-ref wa key1) => #f)
    (check (walist-length wa) => 1)

    ;; Keys and alist conversion
    (let ([keys (walist-keys wa)])
      (check (length keys) => 1))
    (let ([alist (walist->alist wa)])
      (check (length alist) => 1)
      (check (cdar alist) => "value2"))))

;; ========== Values utilities ==========
(printf "  Values utilities...~n")
(check (values->list (values 1 2 3)) => '(1 2 3))
(check (values->list (values 'a)) => '(a))
(check (values->list (values)) => '())

(check (values-ref (values 'a 'b 'c) 0) => 'a)
(check (values-ref (values 'a 'b 'c) 1) => 'b)
(check (values-ref (values 'a 'b 'c) 2) => 'c)

;; receive (SRFI-8)
(check (receive (a b c) (values 1 2 3) (+ a b c)) => 6)
(check (receive (x) (values 42) x) => 42)
(check (receive args (values 1 2 3) args) => '(1 2 3))

;; ========== Assert ==========
(printf "  Assert...~n")
;; assert! passes silently
(assert! #t)
(assert! (> 3 2))
(assert! (> 3 2) "three is greater than two")
(set! pass-count (+ pass-count 3))

;; assert! fails with error
(check-true (guard (exn [#t #t])
              (assert! #f)
              #f))

(check-true (guard (exn [#t #t])
              (assert! #f "custom message")
              #f))

;; assert-equal!
(assert-equal! 42 42)
(assert-equal! "hello" "hello")
(set! pass-count (+ pass-count 2))

(check-true (guard (exn [#t #t])
              (assert-equal! 1 2)
              #f))

;; assert-pred
(assert-pred number? 42)
(assert-pred string? "hello")
(set! pass-count (+ pass-count 2))

(check-true (guard (exn [#t #t])
              (assert-pred string? 42)
              #f))

;; assert-exception
(let ([exn (assert-exception (lambda () (error 'test "boom")))])
  (check-true exn))

(check-true (guard (exn [#t #t])
              (assert-exception (lambda () 42))
              #f))

;; ========== Summary ==========
(printf "~n--- Results: ~a passed, ~a failed ---~n" pass-count fail-count)
(when (> fail-count 0) (exit 1))
