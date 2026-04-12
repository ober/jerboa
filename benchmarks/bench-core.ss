#!/usr/bin/env -S scheme --libdirs lib --script
;;; bench-core.ss — Core benchmarks for Jerboa
;;;
;;; Measures overhead of Jerboa's abstractions vs raw Chez Scheme.
;;;
;;; Run: bin/jerboa run benchmarks/bench-core.ss

(import (except (chezscheme)
          make-hash-table hash-table?
          sort sort! format printf fprintf
          iota 1+ 1-
          path-extension path-absolute?
          with-input-from-string with-output-to-string)
        (jerboa prelude)
        (std text json)
        (std iter))

;; --- Benchmark harness ---

(define (bench name n thunk)
  (collect)  ;; GC before benchmark
  (let* ([start (cpu-time)]
         [start-real (real-time)])
    (let loop ([i 0])
      (when (< i n)
        (thunk)
        (loop (+ i 1))))
    (let* ([end (cpu-time)]
           [end-real (real-time)]
           [cpu-ms (- end start)]
           [real-ms (- end-real start-real)]
           [per-op-ns (if (> n 0)
                        (inexact (/ (* real-ms 1000000) n))
                        0)])
      (printf "~30a  ~8d ops  ~6d ms cpu  ~6d ms real  ~8,1f ns/op\n"
              name n cpu-ms real-ms per-op-ns))))

(printf "=== Jerboa Core Benchmarks ===\n\n")
(printf "~30a  ~8a      ~6a        ~6a         ~a\n"
        "Benchmark" "Ops" "CPU" "Real" "ns/op")
(printf "~80,'-a\n" "")

;; --- Hash table benchmarks ---

(let ([ht (make-hash-table)])
  (bench "hash-put! (string keys)" 100000
    (lambda ()
      (hash-put! ht "key" 42)))

  (bench "hash-ref (string keys)" 1000000
    (lambda ()
      (hash-ref ht "key")))

  (bench "hash-key? (miss)" 1000000
    (lambda ()
      (hash-key? ht "nonexistent"))))

(let ()
  (bench "hash-table create+populate" 10000
    (lambda ()
      (let ([ht (make-hash-table)])
        (let loop ([i 0])
          (when (< i 100)
            (hash-put! ht (number->string i) i)
            (loop (+ i 1))))))))

;; --- Pattern matching ---

(bench "match (list pattern)" 1000000
  (lambda ()
    (match '(1 2 3)
      ((list a b c) (+ a b c)))))

(bench "match (predicate)" 1000000
  (lambda ()
    (match 42
      ((? string?) 'string)
      ((? number?) 'number))))

(bench "match (nested cons)" 1000000
  (lambda ()
    (match '(1 (2 3) 4)
      ((cons a (cons (cons b (cons c _)) _)) (+ a b c)))))

;; --- String operations ---

(bench "string-split" 100000
  (lambda ()
    (string-split "hello,world,foo,bar,baz" ",")))

(bench "string-join" 100000
  (lambda ()
    (string-join '("hello" "world" "foo" "bar" "baz") ",")))

(bench "string-contains" 1000000
  (lambda ()
    (string-contains "the quick brown fox jumps" "fox")))

;; --- Sort ---

(let ([data '(5 3 1 4 2 8 7 6 9 0)])
  (bench "sort (10 elems)" 100000
    (lambda ()
      (sort data <))))

(let ([data (let loop ([i 0] [acc '()])
              (if (= i 1000) acc
                (loop (+ i 1) (cons (random 10000) acc))))])
  (bench "sort (1000 elems)" 1000
    (lambda ()
      (sort data <))))

;; --- JSON ---

(let ([json-str "{\"name\":\"test\",\"value\":42,\"tags\":[\"a\",\"b\",\"c\"]}"])
  (bench "JSON parse" 10000
    (lambda ()
      (string->json-object json-str))))

(let ([obj (list->hash-table '(("name" . "test") ("value" . 42) ("tags" . ("a" "b" "c"))))])
  (bench "JSON serialize" 10000
    (lambda ()
      (json-object->string obj))))

;; --- Iterators ---

(bench "for/collect (range 100)" 10000
  (lambda ()
    (for/collect ([x (in-range 100)]) (* x x))))

(bench "for/fold (sum range 100)" 100000
  (lambda ()
    (for/fold ([sum 0]) ([x (in-range 100)]) (+ sum x))))

;; --- Struct operations ---

(defstruct point (x y))

(bench "struct create" 1000000
  (lambda ()
    (make-point 3 4)))

(let ([p (make-point 3 4)])
  (bench "struct field access" 1000000
    (lambda ()
      (+ (point-x p) (point-y p)))))

;; --- def with keyword args ---

(def (kw-func a b (c 10) (d 20))
  (+ a b c d))

(bench "def keyword call" 1000000
  (lambda ()
    (kw-func 1 2 c: 3 d: 4)))

(bench "def keyword default" 1000000
  (lambda ()
    (kw-func 1 2)))

;; --- Summary ---

(printf "\n=== Done ===\n")
