#!/usr/bin/env -S scheme --libdirs lib --script
;;; bench-for-or-and.ss — exercise fused for/or and for/and forms
;;; introduced in Phase 19.  The fused path avoids the intermediate
;;; list produced by the generic multi-clause machinery.

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
      (printf "~46a ~10d iters ~6d ms  ~8,2f ns/iter\n"
              name n elapsed per-op-ns))))

(define N 2000000)
(define V (list->vector (iota N)))
(define L (iota N))
(define S (make-string N #\a))

(printf "=== for/or & for/and fusion bench (n=~d) ===\n\n" N)

;; ---- for/or over various iterators (target never hit → full sweep) ----

(bench "for/or  in-range  (no hit)" N
  (lambda ()
    (for/or ((i (in-range N)))
      (and (fx= i -1) i))))

(bench "for/or  in-vector (no hit)" N
  (lambda ()
    (for/or ((x (in-vector V)))
      (and (fx= x -1) x))))

(bench "for/or  in-string (no hit)" N
  (lambda ()
    (for/or ((c (in-string S)))
      (and (char=? c #\Z) c))))

(bench "for/or  in-list   (no hit)" N
  (lambda ()
    (for/or ((x (in-list L)))
      (and (fx= x -1) x))))

;; ---- for/or early exit at mid-point ----

(bench "for/or  in-range  (hit at N/2)" N
  (lambda ()
    (for/or ((i (in-range N)))
      (and (fx= i (fxquotient N 2)) i))))

;; ---- for/and over various iterators (always truthy → full sweep) ----

(bench "for/and in-range  (always)" N
  (lambda ()
    (for/and ((i (in-range N)))
      (fx>= i 0))))

(bench "for/and in-vector (always)" N
  (lambda ()
    (for/and ((x (in-vector V)))
      (fx>= x 0))))

(bench "for/and in-list   (always)" N
  (lambda ()
    (for/and ((x (in-list L)))
      (fx>= x 0))))

(bench "for/and in-range  (fail at N/2)" N
  (lambda ()
    (for/and ((i (in-range N)))
      (fx< i (fxquotient N 2)))))
