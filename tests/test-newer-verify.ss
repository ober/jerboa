#!chezscheme
;;; Verification tests for pre-existing modules referenced in newer.md
;;; Tests that imports work and basic APIs are functional.

(import (except (chezscheme)
          make-hash-table hash-table? iota 1+ 1- getenv
          path-extension path-absolute?
          thread? make-mutex mutex? mutex-name
          box box? unbox set-box!)
        (std gambit-compat))

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

(printf "--- Verifying pre-existing modules ---~n")

;; ========== #3 Spawn & Concurrency ==========
(printf "  #3 spawn/concurrency...~n")
(let ([b (box #f)])
  (let ([t (spawn (lambda () (set-box! b 'done)))])
    (thread-join! t)
    (check (unbox b) => 'done)))
(let ([t (spawn/name "test" (lambda () 42))])
  (check-true (thread? t))
  (thread-join! t))
(set! pass-count (+ pass-count 1))  ;; thread-sleep! exists
(thread-sleep! 0.01)

;; ========== #4 Iterator ==========
(printf "  #4 iter...~n")
(import (std iter))
(check (for/collect ([x (in-range 5)]) (* x x)) => '(0 1 4 9 16))
(check (for/fold ([sum 0]) ([x (in-list '(1 2 3 4))]) (+ sum x)) => 10)
(check-true (list? (for/collect ([c (in-string "abc")]) c)))

;; ========== #5 SRFI-13 ==========
(printf "  #5 SRFI-13...~n")
(import (std srfi srfi-13))
(check (string-contains "hello world" "world") => 6)
(check-true (string-prefix? "hel" "hello"))
(check-true (string-suffix? "llo" "hello"))
(check (string-trim "  hello  ") => "hello  ")
(check (string-trim-both "  hello  ") => "hello")
(check (string-pad "42" 5 #\0) => "00042")
(check (string-join '("a" "b" "c") ",") => "a,b,c")
(check (string-take "hello" 3) => "hel")
(check (string-drop "hello" 3) => "lo")
(check-true (string-null? ""))
(check-false (string-null? "a"))

;; ========== #6 SRFI-1 ==========
(printf "  #6 SRFI-1...~n")
(import (except (std srfi srfi-1) delete))  ;; avoid conflict with jerboa core's delete
(check (iota 5) => '(0 1 2 3 4))
(check (iota 5 1) => '(1 2 3 4 5))
(check (iota 3 0 2) => '(0 2 4))
(check (first '(a b c)) => 'a)
(check (second '(a b c)) => 'b)
(check (third '(a b c)) => 'c)
(check-true (any odd? '(2 3 4)))
(check-false (any odd? '(2 4 6)))
(check-true (every even? '(2 4 6)))
(check (fold + 0 '(1 2 3 4)) => 10)
(check (zip '(1 2 3) '(a b c)) => '((1 a) (2 b) (3 c)))
(check (take '(a b c d e) 3) => '(a b c))
(check (drop '(a b c d e) 3) => '(d e))
(check (filter-map (lambda (x) (and (even? x) (* x 10))) '(1 2 3 4 5))
       => '(20 40))

;; ========== #9 SRFI-19 ==========
(printf "  #9 SRFI-19...~n")
(import (std srfi srfi-19))
(let ([d (current-date)])
  (check-true (date? d))
  (check-true (> (date-year d) 2000))
  (check-true (<= 1 (date-month d) 12)))
(let ([t (current-time 'time-utc)])
  (check-true (time? t))
  (check-true (> (time->seconds t) 0)))
(let ([s (date->string (current-date) "~Y-~m-~d")])
  (check-true (string? s))
  (check-true (> (string-length s) 8)))

;; ========== #11 Logging ==========
(printf "  #11 logging...~n")
(import (except (std logger) errorf))  ;; avoid chez conflict
(check-true (procedure? start-logger!))
(check-true (procedure? current-logger))
(check-true (procedure? current-logger-options))
(set! pass-count (+ pass-count 1))

;; ========== #14 Crypto Digest ==========
(printf "  #14 crypto digest...~n")
(import (std crypto digest))
(let ([h (sha256 "hello")])
  (check-true (string? h))
  (check-true (= (string-length h) 64)))  ;; SHA-256 hex is 64 chars
(let ([h (md5 "hello")])
  (check-true (string? h))
  (check-true (= (string-length h) 32)))  ;; MD5 hex is 32 chars

;; ========== #16 Config ==========
(printf "  #16 config...~n")
(import (std config))
(set! pass-count (+ pass-count 1))  ;; Module loads

;; ========== #19 Channels ==========
(printf "  #19 channels...~n")
(import (std misc channel))
(let ([ch (make-channel)])
  (check-true (channel? ch))
  (check-true (channel-empty? ch))
  (channel-put ch 42)
  (check-false (channel-empty? ch))
  (check (channel-get ch) => 42)
  (channel-close ch)
  (check-true (channel-closed? ch)))

;; Bounded channel
(let ([ch (make-channel 2)])
  (channel-put ch 'a)
  (channel-put ch 'b)
  (check (channel-length ch) => 2)
  (check (channel-get ch) => 'a)
  (check (channel-get ch) => 'b))

;; ========== #29 Test Framework ==========
(printf "  #29 test framework...~n")
(import (std test))
(check-true (procedure? run-tests!))
(set! pass-count (+ pass-count 1))

;; ========== Summary ==========
(printf "~n--- Results: ~a passed, ~a failed ---~n" pass-count fail-count)
(when (> fail-count 0) (exit 1))
