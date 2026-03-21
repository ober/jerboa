#!/usr/bin/env scheme-script
#!chezscheme
;;; fuzz-reader.ss -- Fuzzer for jerboa/reader
;;;
;;; Targets: jerboa-read-string, jerboa-read-all
;;; Bug classes: stack overflow, hangs, wrong AST, crashes

(import (chezscheme)
        (jerboa reader)
        (std test fuzz))

;;; ========== Seed corpus: known tricky inputs ==========

(define reader-seeds
  '(;; Basic forms
    "()" "[]" "{}" "#t" "#f" "'x" "`(,x ,@y)"
    ;; Keywords
    "foo:" ":bar" "#:baz"
    ;; Special literals
    "#!void" "#!eof" "#\\newline" "#\\space"
    ;; Numbers
    "42" "-3.14" "1/3" "+inf.0" "-inf.0" "+nan.0" "1+2i"
    ;; Strings
    "\"hello\"" "\"line\\nbreak\"" "\"tab\\there\""
    "\"unicode \\u0041\""
    ;; Datum comments
    "#;foo bar" "#;(a b) c" "#;#;a b c"
    ;; Block comments
    "#|comment|#" "#|nested #|deep|# end|#"
    ;; Bytevectors
    "#u8(1 2 3)" "#vu8(255 0 128)"
    ;; Hash dispatch
    "#(1 2 3)"
    ;; Heredoc
    "\"\"\"heredoc\nline2\n\"\"\""
    ;; Edge cases
    "" " " "\n" "\t"
    ))

;;; ========== Generators ==========

(define (gen-random-sexp)
  (case (random 10)
    [(0) ;; deeply nested lists
     (let ([depth (+ 1 (random 200))])
       (string-append
         (make-string depth #\()
         "x"
         (make-string depth #\))))]
    [(1) ;; deeply nested brackets
     (let ([depth (+ 1 (random 200))])
       (string-append
         (make-string depth #\[)
         "x"
         (make-string depth #\])))]
    [(2) ;; deeply nested block comments
     (let ([depth (+ 1 (random 100))])
       (string-append
         (apply string-append (make-list depth "#|"))
         "comment"
         (apply string-append (make-list depth "|#"))))]
    [(3) ;; string with escapes
     (string-append "\""
       (random-ascii-string (+ 1 (random 200)))
       "\"")]
    [(4) ;; datum comment chains
     (let ([n (+ 1 (random 20))])
       (string-append
         (apply string-append (make-list n "#;"))
         (apply string-append (make-list n "(x) "))
         "final"))]
    [(5) ;; mismatched delimiters
     (let ([chars (map (lambda (_)
                         (random-element '(#\( #\) #\[ #\] #\{ #\})))
                       (make-list (+ 1 (random 30))))])
       (list->string chars))]
    [(6) ;; random bytevector literal
     (string-append "#u8("
       (apply string-append
         (map (lambda (_) (string-append (number->string (random 300)) " "))
              (make-list (+ 1 (random 20)))))
       ")")]
    [(7) ;; hash dispatch edge cases
     (random-element
       '("#u8(not numbers here)" "#\\x0" "#\\xDEAD"
         "#;#;#;(x)(y)(z)w" "#!bwp" "#!base-rtd"
         "#3(a b c)" "#vfx(1 2 3)"))]
    [(8) ;; mutate a seed
     (mutate-string (random-element reader-seeds))]
    [(9) ;; pure random
     (random-ascii-string (+ 1 (random (fuzz-max-size))))]))

;;; ========== Run ==========

(define reader-stats
  (fuzz-run "reader"
    (lambda (input)
      (guard (exn [#t (void)])
        (jerboa-read-string input)))
    gen-random-sexp))

;; Also fuzz jerboa-read-all (reads multiple forms)
(define reader-all-stats
  (fuzz-run "reader-all"
    (lambda (input)
      (guard (exn [#t (void)])
        (let ([p (open-input-string input)])
          (jerboa-read-all p))))
    gen-random-sexp
    (quotient (fuzz-iterations) 2)))

;; Exit with failure if any crashes
(when (or (> (fuzz-stats-crashes reader-stats) 0)
          (> (fuzz-stats-crashes reader-all-stats) 0))
  (exit 1))
