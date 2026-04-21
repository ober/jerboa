#!/usr/bin/env -S scheme --libdirs lib --script
;;; bench-defstruct.ss — Measures the cost of defstruct accessors vs
;;; raw define-record-type accessors and raw Chez field access.
;;;
;;; Each benchmark does a tight loop summing a field over a record.
;;; If defstruct's `(define acc iacc)` alias prevents cp0 from
;;; inlining the accessor, defstruct-acc will be measurably slower
;;; than the raw DRT path under unsafe mode (o=3).

(import (except (chezscheme)
          make-hash-table hash-table? sort sort! format printf fprintf
          iota 1+ 1- path-extension path-absolute?
          with-input-from-string with-output-to-string)
        (jerboa prelude))

(define (bench name n thunk)
  (collect)
  (let* ([t0 (real-time)])
    (let loop ([i 0])
      (when (fx< i n) (thunk) (loop (fx+ i 1))))
    (let* ([elapsed (- (real-time) t0)]
           [per-op-ns (if (fx> n 0)
                        (inexact (/ (* elapsed 1000000) n))
                        0.0)])
      (printf "~40a ~8d iters ~6d ms  ~8,2f ns/call\n"
              name n elapsed per-op-ns))))

;;;; 1. defstruct (Jerboa) — accessor via `(define acc iacc)` alias.

(defstruct dspoint (x y))
(define ds (make-dspoint 3 4))

;;;; 2. define-record-type (Chez native) — baseline accessor.

(define-record-type drt-point
  (sealed #t)
  (fields (mutable x drt-x drt-x-set!)
          (mutable y drt-y drt-y-set!)))
(define drt (make-drt-point 3 4))

;;;; 3. Direct $object-ref (the raw-speed floor).

(define (raw-sum n p)
  (let loop ([i 0] [acc 0])
    (if (fx= i n)
        acc
        (loop (fx+ i 1)
              (fx+ acc (fx+ (#3%$object-ref 'scheme-object p 9)
                            (#3%$object-ref 'scheme-object p 17)))))))

(define ITERS 20000000)

(printf "=== defstruct accessor overhead bench (n=~d) ===\n\n" ITERS)

(bench "defstruct (dspoint-x + dspoint-y)" 1
  (lambda ()
    (let loop ([i 0] [acc 0])
      (if (fx= i ITERS)
          acc
          (loop (fx+ i 1)
                (fx+ acc (fx+ (dspoint-x ds) (dspoint-y ds))))))))

(bench "DRT native  (drt-x + drt-y)" 1
  (lambda ()
    (let loop ([i 0] [acc 0])
      (if (fx= i ITERS)
          acc
          (loop (fx+ i 1)
                (fx+ acc (fx+ (drt-x drt) (drt-y drt))))))))

(bench "raw $object-ref" 1
  (lambda () (raw-sum ITERS drt)))

(printf "\n(Run at o=0 for safe mode, o=3 for unsafe; wider gap under o=0\n")
(printf " means the per-call predicate check is still emitted.)\n")
