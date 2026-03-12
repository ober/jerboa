#!chezscheme
;;; Tests for (std dev benchmark) — Benchmark Framework

(import (chezscheme) (std dev benchmark))

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

(printf "--- (std dev benchmark) tests ---~%")

;; ========== Record Types ==========

(test "benchmark?/true for benchmark record"
  (benchmark? (make-benchmark 'test (lambda () 42)))
  #t)

(test "benchmark?/false for non-benchmark"
  (benchmark? 42)
  #f)

(test "benchmark-name/returns name"
  (benchmark-name (make-benchmark 'my-bench (lambda () 1)))
  'my-bench)

(test "benchmark-run/returns run proc"
  (let* ([run (lambda () 42)]
         [bm  (make-benchmark 'b run)])
    (eq? (benchmark-run bm) run))
  #t)

(test "benchmark-setup/default is #f"
  (benchmark-setup (make-benchmark 'b (lambda () 1)))
  #f)

(test "benchmark-teardown/default is #f"
  (benchmark-teardown (make-benchmark 'b (lambda () 1)))
  #f)

(test "benchmark-setup/with setup"
  (let* ([setup (lambda () 'data)]
         [bm    (make-benchmark 'b (lambda (d) d) setup #f)])
    (eq? (benchmark-setup bm) setup))
  #t)

;; ========== Running Benchmarks ==========

(test-pred "run-benchmark/returns result record"
  (run-benchmark (make-benchmark 'b (lambda () (+ 1 1)))
                 '#:iterations 5 '#:warmup 2)
  benchmark-result?)

(test-pred "run-benchmark/result has correct name"
  (benchmark-result-name
    (run-benchmark (make-benchmark 'my-test (lambda () 1))
                   '#:iterations 5 '#:warmup 1))
  (lambda (n) (eq? n 'my-test)))

(test-pred "run-benchmark/mean-ns is positive"
  (benchmark-result-mean-ns
    (run-benchmark (make-benchmark 'b (lambda () (iota 100)))
                   '#:iterations 10 '#:warmup 2))
  (lambda (n) (>= n 0.0)))

(test-pred "run-benchmark/min <= mean <= max"
  (let ([r (run-benchmark (make-benchmark 'b (lambda () (+ 1 1)))
                          '#:iterations 20 '#:warmup 5)])
    (and (<= (benchmark-result-min-ns r) (benchmark-result-mean-ns r))
         (<= (benchmark-result-mean-ns r) (benchmark-result-max-ns r))))
  (lambda (x) (eq? x #t)))

(test-pred "run-benchmark/samples is a list"
  (benchmark-result-samples
    (run-benchmark (make-benchmark 'b (lambda () 1))
                   '#:iterations 5 '#:warmup 1))
  list?)

(test-pred "run-benchmark/samples has correct count"
  (length
    (benchmark-result-samples
      (run-benchmark (make-benchmark 'b (lambda () 1))
                     '#:iterations 7 '#:warmup 1)))
  (lambda (n) (= n 7)))

(test-pred "run-benchmark/stddev is non-negative"
  (benchmark-result-stddev-ns
    (run-benchmark (make-benchmark 'b (lambda () (+ 1 1)))
                   '#:iterations 10 '#:warmup 2))
  (lambda (n) (>= n 0.0)))

(test-pred "run-benchmark/with setup and teardown"
  (let ([setup-ran    0]
        [teardown-ran 0])
    (run-benchmark
      (make-benchmark 'b
        (lambda (d) d)
        (lambda () (set! setup-ran (+ setup-ran 1)) 'data)
        (lambda (d) (set! teardown-ran (+ teardown-ran 1))))
      '#:iterations 3 '#:warmup 0)
    (= setup-ran teardown-ran))
  (lambda (x) (eq? x #t)))

;; ========== Suite ==========

(test-pred "run-benchmark-suite/returns list of results"
  (run-benchmark-suite
    (list (make-benchmark 'a (lambda () 1))
          (make-benchmark 'b (lambda () 2)))
    '#:iterations 3 '#:warmup 1)
  (lambda (r) (and (list? r) (= (length r) 2) (benchmark-result? (car r)))))

;; ========== define-benchmark macro ==========

(define-benchmark noop-bench
  #:run (lambda () (+ 1 2)))

(test "define-benchmark/creates benchmark"
  (benchmark? noop-bench)
  #t)

(test "define-benchmark/name is symbol"
  (benchmark-name noop-bench)
  'noop-bench)

(define-benchmark add-bench
  #:setup (lambda () '(1 2 3))
  #:run   (lambda (lst) (apply + lst))
  #:teardown #f)

(test "define-benchmark/with-setup"
  (benchmark? add-bench)
  #t)

;; ========== with-benchmark macro ==========

(test-pred "with-benchmark/returns result record"
  (with-benchmark inline-test (+ 1 2 3))
  benchmark-result?)

;; ========== Utilities ==========

(test-pred "benchmark-faster?/fast vs slow"
  (let ([fast (run-benchmark (make-benchmark 'fast (lambda () 1))
                             '#:iterations 5 '#:warmup 1)]
        [slow (run-benchmark (make-benchmark 'slow (lambda ()
                                                     (let loop ([i 0] [acc 0])
                                                       (if (= i 1000) acc
                                                           (loop (+ i 1) (+ acc i))))))
                             '#:iterations 5 '#:warmup 1)])
    (benchmark-faster? fast slow))
  (lambda (x) (boolean? x)))

(test-pred "benchmark-compare/ratio is positive"
  (let ([r1 (run-benchmark (make-benchmark 'a (lambda () 1)) '#:iterations 5 '#:warmup 1)]
        [r2 (run-benchmark (make-benchmark 'b (lambda () 2)) '#:iterations 5 '#:warmup 1)])
    (benchmark-compare r1 r2))
  (lambda (n) (>= n 0.0)))

(test-pred "benchmark->alist/has required keys"
  (let* ([bm (make-benchmark 'test (lambda () 1))]
         [r  (run-benchmark bm '#:iterations 5 '#:warmup 1)]
         [al (benchmark->alist r)])
    (and (assq 'name al)
         (assq 'mean-ns al)
         (assq 'median-ns al)
         (assq 'stddev-ns al)
         (assq 'min-ns al)
         (assq 'max-ns al)))
  (lambda (x) (if x #t #f)))

(test-pred "benchmark->alist/name matches"
  (let* ([bm (make-benchmark 'hello (lambda () 1))]
         [r  (run-benchmark bm '#:iterations 5 '#:warmup 1)]
         [al (benchmark->alist r)])
    (cdr (assq 'name al)))
  (lambda (n) (eq? n 'hello)))

;; ========== benchmark-report smoke test ==========

(test-pred "benchmark-report/does not error"
  (let ([r (run-benchmark (make-benchmark 'smoke (lambda () 1))
                          '#:iterations 5 '#:warmup 1)])
    (with-output-to-string (lambda () (benchmark-report r))))
  string?)

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
