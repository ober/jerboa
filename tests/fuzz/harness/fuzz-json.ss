#!/usr/bin/env scheme-script
#!chezscheme
;;; fuzz-json.ss -- Fuzzer for std/text/json
;;;
;;; Targets: string->json-object, read-json, write-json
;;; Bug classes: stack overflow, Unicode crashes, memory, silent wrong output

(import (chezscheme)
        (except (jerboa runtime) make-hash-table hash-table?)
        (std text json)
        (std test fuzz))

;;; ========== Seed corpus ==========

(define json-seeds
  '("{}" "[]" "null" "true" "false"
    "0" "1" "-1" "3.14" "1e10" "1E-5"
    "\"hello\"" "\"\"" "\"\\n\\t\\r\""
    "{\"a\":1}" "{\"a\":{\"b\":2}}"
    "[1,2,3]" "[\"a\",[],{}]"
    "\"\\u0041\"" "\"\\u00e9\"" "\"\\uD800\""
    "\"\\uDFFF\"" "\"\\uD800\\uDC00\""
    "{\"a\":1,\"b\":2,\"c\":3}"
    "[null,true,false,1,\"s\"]"
    ))

;;; ========== Generators ==========

(define (gen-nested-json depth char-open char-close)
  (let ([d (+ 1 (random depth))])
    (string-append
      (make-string d char-open)
      (if (char=? char-open #\{)
        (string-append "\"k\":" (make-string (max 0 (- d 1)) char-open)
                       "1" (make-string (max 0 (- d 1)) char-close))
        "1")
      (make-string d char-close))))

(define (gen-json-string)
  (string-append "\""
    (let loop ([i 0] [acc '()])
      (if (>= i (+ 1 (random 100)))
        (list->string (reverse acc))
        (case (random 8)
          [(0) (loop (+ i 1) (cons #\\ (cons #\n acc)))]
          [(1) (loop (+ i 1) (cons #\\ (cons #\t acc)))]
          [(2) (loop (+ i 1) (cons #\\ (cons #\" acc)))]
          [(3) ;; \uXXXX
           (let ([hex (number->string (random #xFFFF) 16)])
             (let ([padded (string-append (make-string (- 4 (string-length hex)) #\0) hex)])
               (loop (+ i 1) (append (reverse (string->list (string-append "\\u" padded))) acc))))]
          [else (loop (+ i 1) (cons (integer->char (+ 32 (random 95))) acc))])))
    "\""))

(define (gen-random-json)
  (case (random 10)
    [(0) ;; deep objects
     (gen-nested-json 500 #\{ #\})]
    [(1) ;; deep arrays
     (gen-nested-json 500 #\[ #\])]
    [(2) ;; string with unicode escapes
     (gen-json-string)]
    [(3) ;; large number
     (let ([digits (make-string (+ 1 (random 100)) #\9)])
       (string-append digits "e" (number->string (random 10000))))]
    [(4) ;; trailing garbage
     (string-append (random-element '("{\"a\":1}" "[1]" "true")) "GARBAGE")]
    [(5) ;; trailing comma
     (random-element '("[1,2,3,]" "{\"a\":1,}"))]
    [(6) ;; multiple root values
     "{\"a\":1}{\"b\":2}"]
    [(7) ;; mutate seed
     (mutate-string (random-element json-seeds))]
    [(8) ;; number edge cases
     (random-element
       '("1e999999999" "0.0000000000000000000001" "-0" "0.0"
         "1e-999" "9999999999999999999999999999"))]
    [(9) ;; pure random
     (random-ascii-string (+ 1 (random 500)))]))

;;; ========== Roundtrip oracle ==========

(define (gen-simple-json-value)
  ;; Generate a value we can write then read
  (case (random 5)
    [(0) (random 1000)]
    [(1) (random-ascii-string 20)]
    [(2) #t]
    [(3) #f]
    [(4) (void)]))  ;; null

(define roundtrip-stats
  (fuzz-run "json-roundtrip"
    (lambda (input)
      (let* ([val input]
             [str (json-object->string val)]
             [back (string->json-object str)])
        (unless (equal? val back)
          (error 'json-roundtrip "mismatch" val back))))
    gen-simple-json-value
    (quotient (fuzz-iterations) 4)))

;;; ========== Parse fuzz ==========

(define json-stats
  (fuzz-run "json-parse"
    (lambda (input)
      (guard (exn [#t (void)])
        (string->json-object input)))
    gen-random-json))

;; Exit with failure if crashes
(when (or (> (fuzz-stats-crashes json-stats) 0)
          (> (fuzz-stats-crashes roundtrip-stats) 0))
  (exit 1))
