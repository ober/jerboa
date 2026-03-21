#!/usr/bin/env scheme-script
#!chezscheme
;;; fuzz-all.ss -- Run all fuzz harnesses
;;;
;;; Usage:
;;;   FUZZ_ITERATIONS=1000 scheme --libdirs lib --script tests/fuzz/harness/fuzz-all.ss
;;;
;;; Each harness is loaded via (load ...) so they run in sequence.
;;; Reports a summary of all results at the end.

(import (chezscheme))

(define harness-dir "tests/fuzz/harness")
(define scheme-cmd (or (getenv "SCHEME") "scheme"))
(define libdirs (or (getenv "LIBDIRS") "lib"))

(define harnesses
  '("fuzz-reader.ss"
    "fuzz-json.ss"
    "fuzz-http2.ss"
    "fuzz-websocket.ss"
    "fuzz-dns.ss"
    "fuzz-pregexp.ss"
    "fuzz-csv.ss"
    "fuzz-base64.ss"
    "fuzz-hex.ss"
    "fuzz-uri.ss"
    "fuzz-format.ss"
    "fuzz-router.ss"
    "fuzz-sandbox.ss"))

(define (run-harness file)
  (let* ([path (string-append harness-dir "/" file)]
         [cmd (string-append scheme-cmd " --libdirs " libdirs " --script " path)])
    (fprintf (current-error-port) "~n========== ~a ==========~n" file)
    (let ([status (system cmd)])
      (cons file (zero? status)))))

(define results (map run-harness harnesses))

(fprintf (current-error-port) "~n~n========== SUMMARY ==========~n")
(let ([passed 0] [failed 0])
  (for-each
    (lambda (r)
      (if (cdr r)
        (begin
          (set! passed (+ passed 1))
          (fprintf (current-error-port) "  PASS  ~a~n" (car r)))
        (begin
          (set! failed (+ failed 1))
          (fprintf (current-error-port) "  FAIL  ~a~n" (car r)))))
    results)
  (fprintf (current-error-port) "~n~a passed, ~a failed out of ~a harnesses~n"
           passed failed (length results))
  (unless (zero? failed)
    (exit 1)))
