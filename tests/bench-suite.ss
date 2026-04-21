#!/usr/bin/env -S scheme --script
;;; tests/bench-suite.ss — Jerboa performance regression harness
;;;
;;; Usage:
;;;   scheme --libdirs lib --script tests/bench-suite.ss
;;;   scheme --libdirs lib --script tests/bench-suite.ss --baseline  ;; save baseline
;;;   scheme --libdirs lib --script tests/bench-suite.ss --check     ;; diff vs baseline
;;;
;;; Each micro-bench reports median ns/op across 5 runs. --check mode fails
;;; with exit status 1 if any bench regresses >10% vs tests/bench-baseline.scm.

(import (jerboa prelude))

;; ---- Timing ----

(def (now-ns)
  (let ([t (current-time)])
    (+ (* (time-second t) 1000000000) (time-nanosecond t))))

(def (timeit thunk iters)
  (let ([t0 (now-ns)])
    (thunk)
    (let ([t1 (now-ns)])
      (/ (- t1 t0) iters))))

(def (median lst)
  (let ([sorted (sort lst <)]
        [n (length lst)])
    (list-ref sorted (quotient n 2))))

(def (bench-run name thunk iters)
  (let ([ns (median (for/collect ([_ (in-range 5)])
                      (timeit thunk iters)))])
    (list name ns iters)))

;; ---- Micro-benchmarks ----
;; Each `bench-N` function is called with `iters`; it must do `iters`
;; repetitions of the operation under test. Keep bodies tiny so the
;; loop overhead is measurable.

;; Phase 1: sealed defstruct predicate check
(defstruct point (x y))

(def (bench-struct-pred iters)
  (let ([p (make-point 1 2)])
    (let loop ([i 0] [hits 0])
      (if (fx>= i iters) hits
          (loop (fx+ i 1) (if (point? p) (fx+ hits 1) hits))))))

;; Phase 2: match on sealed record types
(defstruct circle (radius))
(defstruct square (side))
(defstruct triangle (base height))

(def (classify s)
  (match s
    [(: circle)   'c]
    [(: square)   's]
    [(: triangle) 't]
    [_ 'unknown]))

(def (bench-match iters)
  (let ([c (make-circle 5)] [q (make-square 4)] [t (make-triangle 3 6)])
    (let loop ([i 0] [sum 0])
      (if (fx>= i iters) sum
          (let ([x (case (fxand i 3) [(0) c] [(1) q] [(2) t] [else c])])
            (loop (fx+ i 1) (fx+ sum (case (classify x) [(c) 1] [(s) 2] [(t) 3] [else 0]))))))))

;; Phase 3: str literal folding + coercion
(def (bench-str iters)
  (let loop ([i 0])
    (if (fx>= i iters) 'done
        (begin (str "value=" i "!") (loop (fx+ i 1))))))

;; Phase 4: regex memoization
(def (bench-regex iters)
  (let loop ([i 0] [hits 0])
    (if (fx>= i iters) hits
        (loop (fx+ i 1) (if (re-match? "\\d+" "12345") (fx+ hits 1) hits)))))

;; Phase 5: for/collect with in-range fusion
(def (bench-for-collect-range iters)
  (let loop ([i 0])
    (if (fx>= i iters) 'done
        (begin (for/collect ([x (in-range 20)]) (* x x))
               (loop (fx+ i 1))))))

(def (bench-for-collect-vector iters)
  (let ([v (list->vector (iota 20))])
    (let loop ([i 0])
      (if (fx>= i iters) 'done
          (begin (for/collect ([x (in-vector v)]) (* x 2))
                 (loop (fx+ i 1)))))))

;; Phase 6: single-pass kwargs
(def (kw-fn x a: (a 1) b: (b 2) c: (c 3)) (+ x a b c))

(def (bench-kwargs-none iters)
  (let loop ([i 0] [sum 0])
    (if (fx>= i iters) sum
        (loop (fx+ i 1) (+ sum (kw-fn 0))))))

(def (bench-kwargs-one iters)
  (let loop ([i 0] [sum 0])
    (if (fx>= i iters) sum
        (loop (fx+ i 1) (+ sum (kw-fn 0 'b: 20))))))

;; Cross-cutting: hashtable ref/set
(def (bench-hashtable iters)
  (let ([ht (make-hash-table)])
    (hash-put! ht "k" 42)
    (let loop ([i 0] [sum 0])
      (if (fx>= i iters) sum
          (loop (fx+ i 1) (+ sum (hash-ref ht "k" 0)))))))

;; Cross-cutting: method dispatch via ~
(defmethod (area (self circle)) (* 3.14159 (circle-radius self) (circle-radius self)))
(defmethod (area (self square)) (* (square-side self) (square-side self)))

(def (bench-method iters)
  (let ([c (make-circle 5)])
    (let loop ([i 0] [sum 0])
      (if (fx>= i iters) sum
          (loop (fx+ i 1) (+ sum (~ c 'area)))))))

;; ---- Driver ----

(def all-benches
  (list
    (list 'struct-pred         bench-struct-pred         1000000)
    (list 'match               bench-match               1000000)
    (list 'str                 bench-str                 500000)
    (list 'regex               bench-regex               500000)
    (list 'for-collect-range   bench-for-collect-range   100000)
    (list 'for-collect-vector  bench-for-collect-vector  100000)
    (list 'kwargs-none         bench-kwargs-none         1000000)
    (list 'kwargs-one          bench-kwargs-one          1000000)
    (list 'hashtable           bench-hashtable           1000000)
    (list 'method-dispatch     bench-method              500000)))

(def (run-all)
  (for/collect ([b (in-list all-benches)])
    (let ([name (car b)] [fn (cadr b)] [iters (caddr b)])
      (bench-run name (lambda () (fn iters)) iters))))

(def (format-results rs)
  (for ([r (in-list rs)])
    (let ([name (car r)] [ns (cadr r)] [iters (caddr r)])
      (displayln (format "  ~24a ~8,2f ns/op   (iters=~a)" name ns iters)))))

(def baseline-path "tests/bench-baseline.scm")

(def (save-baseline rs)
  (call-with-output-file baseline-path
    (lambda (p)
      (write (map (lambda (r) (cons (car r) (cadr r))) rs) p)
      (newline p))
    'replace)
  (displayln "Baseline saved to " baseline-path))

(def (load-baseline)
  (and (file-exists? baseline-path)
       (call-with-input-file baseline-path read)))

(def (check-against-baseline rs)
  (let ([baseline (load-baseline)])
    (unless baseline
      (displayln "No baseline at " baseline-path "; run with --baseline first.")
      (exit 1))
    (let ([regressions
           (for/fold ([acc '()]) ([r (in-list rs)])
             (let* ([name (car r)] [now (cadr r)]
                    [base (assq name baseline)])
               (if (and base (> now (* 1.10 (cdr base))))
                 (cons (list name (cdr base) now
                             (exact->inexact (/ now (cdr base))))
                       acc)
                 acc)))])
      (cond
        [(null? regressions)
         (displayln "OK: no regressions")]
        [else
         (displayln "REGRESSIONS (>10% slower than baseline):")
         (for ([r (in-list (reverse regressions))])
           (displayln (format "  ~24a  baseline ~,2f ns -> now ~,2f ns  (~,2fx)"
                              (car r) (cadr r) (caddr r) (cadddr r))))
         (exit 1)]))))

(def (main args)
  (let ([mode (if (null? args) 'run
                  (let ([flag (car args)])
                    (cond
                      [(string=? flag "--baseline") 'baseline]
                      [(string=? flag "--check") 'check]
                      [else 'run])))])
    (displayln "Running benchmark suite...")
    (let ([rs (run-all)])
      (format-results rs)
      (case mode
        [(baseline) (save-baseline rs)]
        [(check)    (check-against-baseline rs)]
        [else 'ok]))))

(main (command-line-arguments))
