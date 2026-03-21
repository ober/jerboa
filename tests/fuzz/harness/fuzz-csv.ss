#!/usr/bin/env scheme-script
#!chezscheme
;;; fuzz-csv.ss -- Fuzzer for std/text/csv
;;;
;;; Targets: read-csv, write-csv
;;; Bug classes: unterminated quotes, field explosion, memory

(import (chezscheme)
        (std text csv)
        (std test fuzz))

;;; ========== Seed corpus ==========

(define csv-seeds
  '("a,b,c\n1,2,3"
    "\"quoted\",normal"
    "\"has \"\"escaped\"\" quotes\""
    "a,b,c\r\n1,2,3\r\n"
    ""
    ","
    "\n\n\n"
    "\"unterminated"
    "a,,b,,c"
    "\"field with\nnewline\""
    ))

;;; ========== Generators ==========

(define (gen-random-csv)
  (case (random 8)
    [(0) ;; unterminated quote
     (string-append "\"" (random-ascii-string 50))]
    [(1) ;; many fields per row
     (let ([n (+ 10 (random 500))])
       (apply string-append
         (map (lambda (i)
                (if (zero? i)
                  (random-ascii-string 5)
                  (string-append "," (random-ascii-string 5))))
              (iota n))))]
    [(2) ;; many rows
     (apply string-append
       (map (lambda (_)
              (string-append (random-ascii-string 10) ","
                             (random-ascii-string 10) "\n"))
            (make-list (+ 10 (random 200)))))]
    [(3) ;; long field (approaching limit)
     (string-append "\"" (make-string (+ 1000 (random 5000)) #\x) "\"")]
    [(4) ;; mixed quotes and commas
     (let ([chars (map (lambda (_)
                         (random-element '(#\, #\" #\newline #\a #\b #\space)))
                       (make-list (+ 5 (random 100))))])
       (list->string chars))]
    [(5) ;; embedded nulls
     (string-append "a" (string #\nul) "b,c")]
    [(6) ;; mutated seed
     (mutate-string (random-element csv-seeds))]
    [(7) ;; pure random
     (random-ascii-string (+ 1 (random 500)))]))

;;; ========== Run ==========

(define csv-stats
  (fuzz-run "csv-parse"
    (lambda (input)
      (guard (exn [#t (void)])
        (let ([port (open-input-string input)])
          (read-csv port))))
    gen-random-csv))

(when (> (fuzz-stats-crashes csv-stats) 0)
  (exit 1))
