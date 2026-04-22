#!/usr/bin/env -S scheme --libdirs lib --script
;;; bench-string-append.ss — measure adjacent-literal string-append
;;; folding (Chez Phase 22).  Before the fold, each literal boundary
;;; is a separate argument to the string-append primitive; after the
;;; fold, consecutive literal arguments collapse into one.  The
;;; per-call allocator cost should scale linearly with arg count.

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
      (printf "~46a ~10d calls ~6d ms  ~8,2f ns/call\n"
              name n elapsed per-op-ns))))

(define N 1000000)
(define X "world")
(define Y "!")

(printf "=== string-append fold bench (n=~d) ===\n\n" N)

(bench "6-arg adjacent literals + 1 var" N
  (lambda ()
    (let loop ([i 0])
      (if (fx= i N) 'done
          (let ([_ (string-append "hello " "there " X "foo " "bar " Y)])
            (loop (fx+ i 1)))))))

(bench "2-arg pre-merged literal + 1 var" N
  (lambda ()
    (let loop ([i 0])
      (if (fx= i N) 'done
          (let ([_ (string-append "hello there " X)])
            (loop (fx+ i 1)))))))

(bench "all-literal 4-arg" N
  (lambda ()
    (let loop ([i 0])
      (if (fx= i N) 'done
          (let ([_ (string-append "a" "b" "c" "d")])
            (loop (fx+ i 1)))))))

(bench "interleaved 5-arg (2 vars)" N
  (lambda ()
    (let loop ([i 0])
      (if (fx= i N) 'done
          (let ([_ (string-append "pre-" X "-mid-" Y "-post")])
            (loop (fx+ i 1)))))))
