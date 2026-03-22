#!/usr/bin/env scheme-script
#!chezscheme
;;; bench-odb.ss — Performance benchmarks for jerboa odb
;;; Ported from gerbil-odb/bench.ss
;;; Compare raw mmap baseline vs full ODB with CLOS integration.

(import (chezscheme)
        (std odb)
        (std clos)
        (std os mmap))

;; Ensure libc is loaded for raw mmap FFI calls
(load-shared-object "libc.so.6")

;;; ---- Benchmark infrastructure ----
(define *N* 100000)

(define (fmt-ms ns)
  ;; Convert nanoseconds to milliseconds string
  (number->string (/ (round (/ ns 100000.0)) 10.0)))

(define-syntax timed
  (syntax-rules ()
    [(_ label body ...)
     (let* ([start (time-utc->date (current-time))]
            [t0 (current-time)]
            [result (begin body ...)]
            [t1 (current-time)]
            [elapsed (time-difference t1 t0)]
            [ns (+ (* (time-second elapsed) 1000000000)
                   (time-nanosecond elapsed))])
       (display "  ")
       (display label)
       (display ": ")
       (display (fmt-ms ns))
       (display "ms")
       (newline)
       result)]))

(define (make-shuffled-indices n)
  (let ([v (make-vector n)])
    (do ([i 0 (fx+ i 1)]) ((fx= i n))
      (vector-set! v i i))
    ;; Fisher-Yates shuffle with fixed seed for reproducibility
    (random-seed 42)
    (do ([i (fx- n 1) (fx- i 1)]) ((fx= i 0))
      (let* ([j (random (fx+ i 1))]
             [tmp (vector-ref v i)])
        (vector-set! v i (vector-ref v j))
        (vector-set! v j tmp)))
    v))

(define test-dir "/tmp/odb-bench")

(display "================================================================") (newline)
(display (format "  jerboa odb Benchmarks — N = ~a" *N*)) (newline)
(display "================================================================") (newline)
(newline)

;;; ---- Benchmark 1: Raw mmap (baseline, no ODB overhead) ----
(display "---- Bench 1: Raw mmap (baseline, no ODB) ----") (newline)

(let* ([file-path "/tmp/odb-bench-raw.dat"]
       [file-size (* *N* 16)]  ;; 16 bytes per point (2 x s64)
       ;; Create the backing file
       [fd ((foreign-procedure "open" (string int int) int)
            file-path (bitwise-ior #x42 #x200) #o644)]  ; O_CREAT|O_RDWR|O_TRUNC
       [_ ((foreign-procedure "ftruncate" (int long) int) fd file-size)]
       [_ ((foreign-procedure "close" (int) int) fd)]
       [region (mmap file-path '#:mode 'read-write)])

  (timed "Create (raw mmap)"
    (do ([i 0 (fx+ i 1)]) ((fx= i *N*))
      (let ([off (fx* i 16)])
        (mmap-u64-set! region off i 'little)
        (mmap-u64-set! region (fx+ off 8) (fx* i 2) 'little))))

  (timed "Seq read (raw mmap)"
    (let loop ([i 0] [sum 0])
      (if (fx= i *N*) sum
        (loop (fx+ i 1) (+ sum (mmap-u64-ref region (fx* i 16) 'little))))))

  (let ([ridx (make-shuffled-indices *N*)])
    (timed "Rand read (raw mmap)"
      (let loop ([i 0] [sum 0])
        (if (fx= i *N*) sum
          (loop (fx+ i 1)
            (+ sum (mmap-u64-ref region
                     (fx* (vector-ref ridx i) 16) 'little)))))))

  (timed "Update (raw mmap)"
    (do ([i 0 (fx+ i 1)]) ((fx= i *N*))
      (let ([off (fx* i 16)])
        (mmap-u64-set! region off
          (+ (mmap-u64-ref region off 'little) 1) 'little))))

  (timed "Sync (raw mmap)"
    (msync region))

  (munmap region)
  (newline))

;;; ---- Benchmark 2: Full ODB with define-persistent-class ----
(display "---- Bench 2: Full ODB (define-persistent-class + CLOS) ----") (newline)

(system (string-append "rm -rf " test-dir))
(odb-open test-dir)

(define-persistent-class <bench-point> ()
  ((x :type :s64 :initform 0)
   (y :type :s64 :initform 0)))

(define points (make-vector *N* #f))

(timed "Create (odb)"
  (do ([i 0 (fx+ i 1)]) ((fx= i *N*))
    (vector-set! points i (odb-make <bench-point> :x i :y (fx* i 2)))))

(timed "Seq read (odb via odb-slot-ref)"
  (let loop ([i 0] [sum 0])
    (if (fx= i *N*) sum
      (loop (fx+ i 1)
        (+ sum (odb-slot-ref (vector-ref points i) 'x))))))

(timed "Seq read (odb via CLOS slot-ref)"
  (let loop ([i 0] [sum 0])
    (if (fx= i *N*) sum
      (loop (fx+ i 1)
        (+ sum (slot-ref (vector-ref points i) 'x))))))

(let ([ridx (make-shuffled-indices *N*)])
  (timed "Rand read (odb)"
    (let loop ([i 0] [sum 0])
      (if (fx= i *N*) sum
        (loop (fx+ i 1)
          (+ sum (odb-slot-ref (vector-ref points (vector-ref ridx i)) 'x)))))))

(timed "Update (odb)"
  (do ([i 0 (fx+ i 1)]) ((fx= i *N*))
    (odb-slot-set! (vector-ref points i) 'x
      (+ (odb-slot-ref (vector-ref points i) 'x) 1))))

(timed "Update (odb via CLOS slot-set!)"
  (do ([i 0 (fx+ i 1)]) ((fx= i *N*))
    (slot-set! (vector-ref points i) 'x
      (+ (slot-ref (vector-ref points i) 'x) 1))))

(timed "Sync+close (odb)"
  (odb-sync)
  (odb-close))

;; Report file sizes
(newline)
(display "  Store files:") (newline)
(for-each
  (lambda (entry)
    (let ([path (string-append test-dir "/" entry)])
      (when (file-exists? path)
        (let ([p (open-file-input-port path)])
          (let ([sz (port-length p)])
            (close-port p)
            (display (format "    ~a: ~a bytes~n" entry sz)))))))
  (directory-list test-dir))
(newline)

;;; ---- Benchmark 3: Transaction overhead ----
(display "---- Bench 3: Transaction overhead ----") (newline)

(system (string-append "rm -rf " test-dir))
(odb-open test-dir)

(define-persistent-class <txn-point> ()
  ((x :type :s64 :initform 0)
   (y :type :s64 :initform 0)))

(define tp (odb-make <txn-point> :x 0 :y 0))

(timed "1000 txns x 1 write"
  (do ([i 0 (fx+ i 1)]) ((fx= i 1000))
    (with-odb-transaction
      (odb-slot-set! tp 'x i))))

(timed "1 txn x 1000 writes"
  (with-odb-transaction
    (do ([i 0 (fx+ i 1)]) ((fx= i 1000))
      (odb-slot-set! tp 'x i))))

(odb-close)
(newline)

;;; ---- Benchmark 4: Region growing stress ----
(display "---- Bench 4: Region growing (allocate beyond initial capacity) ----") (newline)

(system (string-append "rm -rf " test-dir))
(odb-open test-dir)

(define-persistent-class <grow-point> ()
  ((x :type :s64 :initform 0)))

(timed "Create 10K objects (forces region grow)"
  (do ([i 0 (fx+ i 1)]) ((fx= i 10000))
    (odb-make <grow-point> :x i)))

(timed "Verify last object"
  (odb-find '<grow-point> (lambda (obj) (= (odb-slot-ref obj 'x) 9999))))

(odb-close)
(newline)

;;; ---- Benchmark 5: doclass iteration throughput ----
(display "---- Bench 5: Iteration throughput ----") (newline)

(system (string-append "rm -rf " test-dir))
(odb-open test-dir)

(define-persistent-class <iter-point> ()
  ((x :type :s64 :initform 0)
   (y :type :s64 :initform 0)))

;; Create 50K objects
(do ([i 0 (fx+ i 1)]) ((fx= i 50000))
  (odb-make <iter-point> :x i :y (fx* i 3)))

(timed "doclass 50K objects (sum x)"
  (let ([sum 0])
    (doclass (p <iter-point>)
      (set! sum (+ sum (odb-slot-ref p 'x))))
    sum))

(timed "odb-filter 50K (x > 25000)"
  (length (odb-filter '<iter-point> (lambda (obj)
    (> (odb-slot-ref obj 'x) 25000)))))

(timed "odb-count"
  (odb-count '<iter-point>))

(odb-close)
(newline)

;;; ---- Summary ----
(display "================================================================") (newline)
(display "  Done.") (newline)
(display "================================================================") (newline)
