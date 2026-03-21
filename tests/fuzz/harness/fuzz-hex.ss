#!/usr/bin/env scheme-script
#!chezscheme
;;; fuzz-hex.ss -- Fuzzer for std/text/hex
;;;
;;; Targets: hex-encode, hex-decode
;;; Bug classes: odd-length, invalid chars, roundtrip failures

(import (chezscheme)
        (std text hex)
        (std test fuzz))

;;; ========== Generators ==========

(define (gen-random-hex-input)
  (case (random 6)
    [(0) ;; valid hex, even length
     (let* ([len (* 2 (+ 1 (random 100)))]
            [chars "0123456789abcdef"]
            [result (make-string len)])
       (do ([i 0 (+ i 1)])
           ((= i len) result)
         (string-set! result i (string-ref chars (random 16)))))]
    [(1) ;; odd length
     (let* ([len (+ 1 (* 2 (random 50)))]
            [chars "0123456789abcdef"]
            [result (make-string len)])
       (do ([i 0 (+ i 1)])
           ((= i len) result)
         (string-set! result i (string-ref chars (random 16)))))]
    [(2) ;; invalid chars
     (random-element '("zz" "gg" "0x" "XX" "hello" "0G"))]
    [(3) ;; mixed case
     (random-element '("aAbBcC" "FF00ff" "DeAdBeEf"))]
    [(4) ;; empty
     ""]
    [(5) ;; pure random
     (random-ascii-string (+ 1 (random 200)))]))

;;; ========== Run ==========

;; Roundtrip
(define hex-rt-stats
  (fuzz-roundtrip-check "hex"
    hex-encode
    hex-decode
    (lambda () (random-bytevector (random 200)))))

;; Decode fuzz
(define hex-decode-stats
  (fuzz-run "hex-decode"
    (lambda (input)
      (guard (exn [#t (void)])
        (hex-decode input)))
    gen-random-hex-input))

(when (or (> (fuzz-stats-crashes hex-rt-stats) 0)
          (> (fuzz-stats-crashes hex-decode-stats) 0))
  (exit 1))
