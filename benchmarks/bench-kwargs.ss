#!/usr/bin/env -S scheme --libdirs lib --script
;;; bench-kwargs.ss — compare Jerboa keyword-argument call overhead
;;; vs equivalent positional-argument calls, after Phase 6's single-pass
;;; kwarg extractor (jerboa 19e5a5b).

(import (except (chezscheme)
          make-hash-table hash-table? sort sort! format printf fprintf
          iota 1+ 1- path-extension path-absolute?
          with-input-from-string with-output-to-string)
        (jerboa prelude))

(define (bench name n thunk)
  (collect)
  (let* ([t0 (real-time)])
    (thunk)
    (let* ([elapsed (- (real-time) t0)]
           [per-op-ns (if (fx> n 0)
                        (inexact (/ (* elapsed 1000000) n))
                        0.0)])
      (printf "~40a ~10d calls ~6d ms  ~8,2f ns/call\n"
              name n elapsed per-op-ns))))

;; Three-keyword function.
(def (kw3 x a: (a 1) b: (b 2) c: (c 3))
  (fx+ x (fx+ a (fx+ b c))))

;; Same arity, positional-only.
(def (pos3 x a b c) (fx+ x (fx+ a (fx+ b c))))

;; Six-keyword function (more realistic for "config" calls).
(def (kw6 x a: (a 1) b: (b 2) c: (c 3) d: (d 4) e: (e 5) f: (f 6))
  (fx+ x (fx+ a (fx+ b (fx+ c (fx+ d (fx+ e f)))))))

(def (pos6 x a b c d e f) (fx+ x (fx+ a (fx+ b (fx+ c (fx+ d (fx+ e f)))))))

(define N 1000000)

(printf "=== kwarg call overhead bench (n=~d) ===\n\n" N)

(bench "kw3 positional (no kws passed)" N
  (lambda ()
    (let loop ([i 0] [acc 0])
      (if (fx= i N) acc (loop (fx+ i 1) (fx+ acc (kw3 i)))))))

(bench "kw3 all three kws passed" N
  (lambda ()
    (let loop ([i 0] [acc 0])
      (if (fx= i N) acc
          (loop (fx+ i 1) (fx+ acc (kw3 i 'a: 10 'b: 20 'c: 30)))))))

(bench "pos3 direct positional" N
  (lambda ()
    (let loop ([i 0] [acc 0])
      (if (fx= i N) acc
          (loop (fx+ i 1) (fx+ acc (pos3 i 10 20 30)))))))

(bench "kw6 no kws passed (defaults)" N
  (lambda ()
    (let loop ([i 0] [acc 0])
      (if (fx= i N) acc (loop (fx+ i 1) (fx+ acc (kw6 i)))))))

(bench "kw6 all six kws passed" N
  (lambda ()
    (let loop ([i 0] [acc 0])
      (if (fx= i N) acc
          (loop (fx+ i 1)
                (fx+ acc (kw6 i 'a: 10 'b: 20 'c: 30 'd: 40 'e: 50 'f: 60)))))))

(bench "pos6 direct positional" N
  (lambda ()
    (let loop ([i 0] [acc 0])
      (if (fx= i N) acc
          (loop (fx+ i 1) (fx+ acc (pos6 i 10 20 30 40 50 60)))))))
