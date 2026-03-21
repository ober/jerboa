#!/usr/bin/env scheme-script
#!chezscheme
;;; fuzz-base64.ss -- Fuzzer for std/text/base64
;;;
;;; Targets: base64-encode, base64-decode
;;; Bug classes: silent wrong output, malformed padding, roundtrip failures

(import (chezscheme)
        (std text base64)
        (std test fuzz))

;;; ========== Seed corpus ==========

(define base64-decode-seeds
  '("" "YQ==" "YWI=" "YWJj" "YWJjZA=="
    "aGVsbG8=" "aGVsbG8gd29ybGQ="
    ;; Invalid
    "!!!!" "@@@@" "=====" "YQ=" "YQ"
    ;; Whitespace
    "YW Jj" "YW\nJj" "YW\tJj"
    ;; Padding in middle
    "YQ==YQ=="
    ))

;;; ========== Generators ==========

(define (gen-random-base64-decode-input)
  (case (random 6)
    [(0) ;; valid base64 chars, random length
     (let* ([chars "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"]
            [len (+ 1 (random 200))]
            [result (make-string len)])
       (do ([i 0 (+ i 1)])
           ((= i len) result)
         (string-set! result i
           (string-ref chars (random 64)))))]
    [(1) ;; invalid characters
     (string-append "aGVsbG8" (string (integer->char (+ 128 (random 128)))))]
    [(2) ;; bad padding
     (random-element '("=" "==" "===" "a=" "a==" "a===" "ab=" "abc==="))]
    [(3) ;; very long
     (make-string (+ 100 (random 5000)) #\A)]
    [(4) ;; mutated seed
     (mutate-string (random-element base64-decode-seeds))]
    [(5) ;; pure random
     (random-ascii-string (+ 1 (random 200)))]))

;;; ========== Roundtrip oracle ==========

(define base64-rt-stats
  (fuzz-roundtrip-check "base64"
    base64-encode
    base64-decode
    (lambda () (random-bytevector (random 200)))))

;;; ========== Decode fuzz ==========

(define base64-decode-stats
  (fuzz-run "base64-decode"
    (lambda (input)
      (guard (exn [#t (void)])
        (base64-decode input)))
    gen-random-base64-decode-input))

(when (or (> (fuzz-stats-crashes base64-rt-stats) 0)
          (> (fuzz-stats-crashes base64-decode-stats) 0))
  (exit 1))
