#!chezscheme
;;; (std misc cpu) — CPU count probe
;;;
;;; Returns the number of logical CPUs available for scheduling.
;;; Used by fiber runtime / actor scheduler / agent pool sizing.
;;;
;;; Probe order:
;;;   1. NUMBER_OF_PROCESSORS env var (Windows + explicit override)
;;;   2. /proc/cpuinfo line count ("processor" entries) on Linux
;;;   3. `nproc` / `sysctl -n hw.ncpu` shelled out
;;;   4. Fallback: 1

(library (std misc cpu)
  (export cpu-count)

  (import (chezscheme))

  (define (%try-env)
    (let ([n (getenv "NUMBER_OF_PROCESSORS")])
      (and n (let ([v (string->number n)])
               (and v (positive? v) v)))))

  (define (%try-proc-cpuinfo)
    (guard (_ [else #f])
      (and (file-exists? "/proc/cpuinfo")
           (let ([n 0])
             (call-with-input-file "/proc/cpuinfo"
               (lambda (p)
                 (let loop ()
                   (let ([line (get-line p)])
                     (cond
                       [(eof-object? line) n]
                       [else
                        (when (and (> (string-length line) 9)
                                   (string=? (substring line 0 9) "processor"))
                          (set! n (+ n 1)))
                        (loop)])))))
             (and (positive? n) n)))))

  (define (%try-shell cmd)
    (guard (_ [else #f])
      (let* ([port (open-input-string
                     (with-output-to-string
                       (lambda ()
                         (system cmd))))]
             [line (get-line port)])
        (and (string? line)
             (let ([v (string->number (string-trim line))])
               (and v (positive? v) v))))))

  (define (string-trim s)
    (let* ([n (string-length s)]
           [start (let loop ([i 0])
                    (cond [(= i n) n]
                          [(char-whitespace? (string-ref s i)) (loop (+ i 1))]
                          [else i]))]
           [end (let loop ([i n])
                  (cond [(= i start) start]
                        [(char-whitespace? (string-ref s (- i 1))) (loop (- i 1))]
                        [else i]))])
      (substring s start end)))

  (define %cached #f)

  (define (cpu-count)
    (or %cached
        (let ([n (or (%try-env)
                     (%try-proc-cpuinfo)
                     (%try-shell "nproc 2>/dev/null")
                     (%try-shell "sysctl -n hw.ncpu 2>/dev/null")
                     1)])
          (set! %cached n)
          n)))

) ;; end library
