#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc profile))

(define test-count 0)
(define pass-count 0)

(define (test name thunk)
  (set! test-count (+ test-count 1))
  (guard (e [#t (display "FAIL: ") (display name) (newline)
              (display "  Error: ") (display (condition-message e)) (newline)])
    (thunk)
    (set! pass-count (+ pass-count 1))
    (display "PASS: ") (display name) (newline)))

(define (assert-equal actual expected msg)
  (unless (equal? actual expected)
    (error 'assert-equal
           (string-append msg ": expected " (format "~s" expected)
                          " got " (format "~s" actual)))))

(define (assert-true val msg)
  (unless val
    (error 'assert-true (string-append msg ": expected true, got " (format "~s" val)))))

(define (string-contains haystack needle)
  (let ([hlen (string-length haystack)]
        [nlen (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nlen) hlen) #f]
        [(string=? (substring haystack i (+ i nlen)) needle) #t]
        [else (loop (+ i 1))]))))

;; ---- define-profiled: basic call counting ----
(define-profiled (square x) (* x x))

(test "define-profiled tracks call count"
  (lambda ()
    (profile-reset!)
    (parameterize ([profiling-active? #t])
      (square 3)
      (square 4)
      (square 5))
    (let* ([data (profile-data)]
           [entry (assq 'square data)]
           [props (cdr entry)])
      (assert-equal (cdr (assq 'count props)) 3 "call count"))))

;; ---- define-profiled returns correct values ----
(test "define-profiled returns correct result"
  (lambda ()
    (parameterize ([profiling-active? #t])
      (assert-equal (square 7) 49 "square 7"))))

;; ---- zero overhead when profiling inactive ----
(test "no overhead when profiling inactive"
  (lambda ()
    (profile-reset!)
    ;; profiling-active? defaults to #f
    (square 10)
    (square 20)
    (let ([data (profile-data)])
      (assert-true (null? data) "no data collected when inactive"))))

;; ---- nested profiled calls ----
(define-profiled (double x) (* x 2))
(define-profiled (quad x) (double (double x)))

(test "nested profiled calls tracked independently"
  (lambda ()
    (profile-reset!)
    (parameterize ([profiling-active? #t])
      (quad 5))
    (let* ([data (profile-data)]
           [quad-entry   (assq 'quad data)]
           [double-entry (assq 'double data)])
      (assert-equal (cdr (assq 'count (cdr quad-entry))) 1 "quad called once")
      (assert-equal (cdr (assq 'count (cdr double-entry))) 2 "double called twice"))))

;; ---- profile-reset! clears data ----
(test "profile-reset! clears all data"
  (lambda ()
    (profile-reset!)
    (parameterize ([profiling-active? #t])
      (square 3))
    (let ([before (profile-data)])
      (assert-true (not (null? before)) "data exists before reset"))
    (profile-reset!)
    (let ([after (profile-data)])
      (assert-true (null? after) "data empty after reset"))))

;; ---- time-it measures elapsed time ----
(test "time-it returns result and elapsed ms"
  (lambda ()
    (let-values ([(result elapsed-ms) (time-it (begin
                                                  (sleep (make-time 'time-duration 50000000 0))
                                                  42))])
      (assert-equal result 42 "time-it result")
      (assert-true (>= elapsed-ms 40.0)
                   (format "elapsed ~a ms should be >= 40" elapsed-ms)))))

;; ---- profile-data sorted by total time ----
(define-profiled (slow-fn)
  (sleep (make-time 'time-duration 30000000 0))  ;; 30ms
  'slow)

(define-profiled (fast-fn)
  'fast)

(test "profile-data sorted by total time descending"
  (lambda ()
    (profile-reset!)
    (parameterize ([profiling-active? #t])
      (fast-fn)
      (slow-fn))
    (let* ([data (profile-data)]
           [names (map car data)])
      (assert-equal (car names) 'slow-fn "slow-fn should be first"))))

;; ---- timing values are sensible ----
(test "min/max/avg tracked correctly"
  (lambda ()
    (profile-reset!)
    (parameterize ([profiling-active? #t])
      (square 1)
      (square 2)
      (square 3))
    (let* ([data (profile-data)]
           [entry (assq 'square data)]
           [props (cdr entry)]
           [mn  (cdr (assq 'min-ms props))]
           [mx  (cdr (assq 'max-ms props))]
           [avg (cdr (assq 'avg-ms props))]
           [tot (cdr (assq 'total-ms props))])
      (assert-true (<= mn avg) "min <= avg")
      (assert-true (<= avg mx) "avg <= max")
      (assert-true (<= mn mx) "min <= max")
      (assert-true (>= tot 0.0) "total >= 0"))))

;; ---- with-profiling macro ----
(test "with-profiling resets, profiles, reports, returns result"
  (lambda ()
    ;; Seed some data that should be cleared
    (parameterize ([profiling-active? #t])
      (square 1))
    (let ([result (with-profiling
                    (square 10)
                    (square 20)
                    (+ (square 3) 1))])
      (assert-equal result 10 "with-profiling returns last body value")
      ;; After with-profiling, profiling-active? should be back to #f
      (assert-true (not (profiling-active?)) "profiling inactive after with-profiling"))))

;; ---- profile-report outputs something ----
(test "profile-report produces output"
  (lambda ()
    (profile-reset!)
    (parameterize ([profiling-active? #t])
      (square 5))
    (let ([output (with-output-to-string profile-report)])
      (assert-true (> (string-length output) 0) "report not empty")
      (assert-true (string-contains output "square") "report mentions function name"))))

;; ---- Summary ----
(newline)
(display (format "~a/~a tests passed.~%" pass-count test-count))
(unless (= pass-count test-count)
  (exit 1))
