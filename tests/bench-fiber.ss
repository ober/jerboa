#!/usr/bin/env scheme-script
#!chezscheme
;;; bench-fiber.ss — Performance benchmarks for jerboa fibers

(import (chezscheme)
        (std fiber))

;;; ---- Benchmark infrastructure ----

(define (fmt-ms ns)
  (number->string (/ (round (/ ns 100000.0)) 10.0)))

(define-syntax timed
  (syntax-rules ()
    [(_ label body ...)
     (let* ([t0 (current-time)]
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

(display "================================================================") (newline)
(display "  jerboa Fiber Benchmarks") (newline)
(display "================================================================") (newline)
(newline)

;;; ---- Bench 1: Spawn + complete (no yield) ----
(display "---- Bench 1: Spawn + complete (no yield) ----") (newline)

(timed "10K fibers, noop"
  (with-fibers
    (do ([i 0 (fx+ i 1)]) ((fx= i 10000))
      (fiber-spawn* (lambda () (void))))))

(timed "100K fibers, noop"
  (with-fibers
    (do ([i 0 (fx+ i 1)]) ((fx= i 100000))
      (fiber-spawn* (lambda () (void))))))

(newline)

;;; ---- Bench 2: Spawn + yield + complete ----
(display "---- Bench 2: Spawn + yield ----") (newline)

(timed "10K fibers, 1 yield each"
  (with-fibers
    (do ([i 0 (fx+ i 1)]) ((fx= i 10000))
      (fiber-spawn* (lambda () (fiber-yield))))))

(timed "10K fibers, 10 yields each"
  (with-fibers
    (do ([i 0 (fx+ i 1)]) ((fx= i 10000))
      (fiber-spawn* (lambda ()
        (do ([j 0 (fx+ j 1)]) ((fx= j 10))
          (fiber-yield)))))))

(newline)

;;; ---- Bench 3: Channel throughput ----
(display "---- Bench 3: Channel throughput ----") (newline)

(timed "10K messages through unbounded channel"
  (with-fibers
    (let ([ch (make-fiber-channel)])
      (fiber-spawn* (lambda ()
        (do ([i 0 (fx+ i 1)]) ((fx= i 10000))
          (fiber-channel-send ch i))))
      (fiber-spawn* (lambda ()
        (do ([i 0 (fx+ i 1)]) ((fx= i 10000))
          (fiber-channel-recv ch)))))))

(timed "10K messages through bounded(1) channel"
  (with-fibers
    (let ([ch (make-fiber-channel 1)])
      (fiber-spawn* (lambda ()
        (do ([i 0 (fx+ i 1)]) ((fx= i 10000))
          (fiber-channel-send ch i))))
      (fiber-spawn* (lambda ()
        (do ([i 0 (fx+ i 1)]) ((fx= i 10000))
          (fiber-channel-recv ch)))))))

(newline)

;;; ---- Bench 4: Ring benchmark (classic fiber benchmark) ----
(display "---- Bench 4: Ring benchmark ----") (newline)

;; N fibers in a ring, pass a token around M times
(define (ring-bench n m)
  (with-fibers
    (let ([channels (let loop ([i 0] [acc '()])
                      (if (fx= i n) (reverse acc)
                        (loop (fx+ i 1) (cons (make-fiber-channel 1) acc))))])
      ;; Spawn ring fibers
      (let loop ([chs channels] [i 0])
        (when (pair? chs)
          (let ([in-ch (car chs)]
                [out-ch (if (null? (cdr chs))
                            (car channels)  ;; wrap around
                            (cadr chs))])
            (fiber-spawn* (lambda ()
              (let msg-loop ([count 0])
                (let ([token (fiber-channel-recv in-ch)])
                  (fiber-channel-send out-ch (fx+ token 1))
                  (when (fx< count (fx- m 1))
                    (msg-loop (fx+ count 1))))))))
          (loop (cdr chs) (fx+ i 1))))
      ;; Inject the initial token
      (fiber-spawn* (lambda ()
        (fiber-channel-send (car channels) 0))))))

(timed "100-fiber ring, 100 passes"
  (ring-bench 100 100))

(timed "1000-fiber ring, 10 passes"
  (ring-bench 1000 10))

(newline)

;;; ---- Bench 5: Preemption stress ----
(display "---- Bench 5: Preemptive scheduling (busy fibers) ----") (newline)

(timed "100 busy fibers, 1M iterations each"
  (with-fibers
    (do ([i 0 (fx+ i 1)]) ((fx= i 100))
      (fiber-spawn* (lambda ()
        (let loop ([j 0])
          (when (fx< j 1000000)
            (loop (fx+ j 1)))))))))

(newline)

;;; ---- Bench 6: Compare with OS threads ----
(display "---- Bench 6: OS thread comparison ----") (newline)

(timed "1K OS threads, noop"
  (let ([threads
         (let loop ([i 0] [acc '()])
           (if (fx= i 1000) acc
             (loop (fx+ i 1)
               (cons (fork-thread (lambda () (void))) acc))))])
    ;; Wait for all to finish
    (sleep (make-time 'time-duration 100000000 0))))

(timed "1K fibers, noop"
  (with-fibers
    (do ([i 0 (fx+ i 1)]) ((fx= i 1000))
      (fiber-spawn* (lambda () (void))))))

(timed "10K OS threads, noop"
  (let ([threads
         (let loop ([i 0] [acc '()])
           (if (fx= i 10000) acc
             (loop (fx+ i 1)
               (cons (fork-thread (lambda () (void))) acc))))])
    (sleep (make-time 'time-duration 500000000 0))))

(timed "10K fibers, noop"
  (with-fibers
    (do ([i 0 (fx+ i 1)]) ((fx= i 10000))
      (fiber-spawn* (lambda () (void))))))

(newline)

;;; ---- Bench 7: fiber-sleep ----
(display "---- Bench 7: fiber-sleep ----") (newline)

(timed "100 fibers sleeping 10ms"
  (with-fibers
    (do ([i 0 (fx+ i 1)]) ((fx= i 100))
      (fiber-spawn* (lambda () (fiber-sleep 10))))))

(newline)

;;; ---- Summary ----
(display "================================================================") (newline)
(display "  Done.") (newline)
(display "================================================================") (newline)
