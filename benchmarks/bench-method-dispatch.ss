#!/usr/bin/env -S scheme --libdirs lib --script
;;; bench-method-dispatch.ss — measures the cost of a hot monomorphic
;;; (~ obj 'method ...) call vs a direct procedure call.
;;;
;;; The gap is the cost of two eq-hashtable-refs (method-tables ->
;;; rtd -> method) plus the record-rtd call.  A per-callsite PIC
;;; would bypass both hashtable lookups on a cache hit.

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

(defstruct ctr (val))
(defmethod (inc (self ctr))  (ctr-val self))
(defmethod (inc2 (self ctr)) (ctr-val self))

(define c (make-ctr 42))

;; Direct-procedure baseline: the fastest possible "indexed" call.
(define (direct-inc c) (ctr-val c))

(define N 10000000)

(printf "=== method dispatch bench (n=~d, monomorphic) ===\n\n" N)

(bench "(~ c 'inc)  [inline ~ macro]" N
  (lambda ()
    (let loop ([i 0] [acc 0])
      (if (fx= i N) acc
          (loop (fx+ i 1) (fx+ acc (~ c 'inc)))))))

(bench "(direct-inc c) [procedure call]" N
  (lambda ()
    (let loop ([i 0] [acc 0])
      (if (fx= i N) acc
          (loop (fx+ i 1) (fx+ acc (direct-inc c)))))))

(bench "(ctr-val c)    [accessor call]" N
  (lambda ()
    (let loop ([i 0] [acc 0])
      (if (fx= i N) acc
          (loop (fx+ i 1) (fx+ acc (ctr-val c)))))))
