#!/usr/bin/env scheme-script
#!chezscheme
;;; fuzz-pregexp.ss -- Fuzzer for std/pregexp
;;;
;;; Targets: pregexp, pregexp-match
;;; Bug classes: ReDoS, stack overflow, invalid escapes

(import (chezscheme)
        (std pregexp)
        (std test fuzz))

;;; ========== Known ReDoS patterns ==========

(define redos-patterns
  '("(a+)+"
    "(a|a)*"
    "(.+)*"
    "(a+)+$"
    "(a|a)+$"
    "([a-zA-Z]+)*"
    "(.*a){10}"
    "((a+)(b+))+"))

(define evil-strings
  '("aaaaaaaaaaaaaaaaaaaab"
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    "ababababababababababababababababc"))

;;; ========== Generators ==========

(define (gen-random-pattern)
  (case (random 8)
    [(0) ;; ReDoS pattern
     (random-element redos-patterns)]
    [(1) ;; unterminated group
     (random-element '("(abc" "(?:" "(?="))]
    [(2) ;; invalid backreference
     (random-element '("\\99" "\\0" "\\999"))]
    [(3) ;; invalid POSIX class
     "[[:nonexistent:]]"]
    [(4) ;; large pattern
     (make-string (+ 100 (random 500)) #\a)]
    [(5) ;; nested quantifiers
     (let ([depth (+ 1 (random 10))])
       (string-append
         (apply string-append (make-list depth "(a+)"))
         (make-string depth #\))))]
    [(6) ;; character class edge cases
     (random-element '("[^]" "[]" "[\\]" "[a-]" "[-a]" "[a-z-]"))]
    [(7) ;; random pattern
     (random-ascii-string (+ 1 (random 100)))]))

(define (gen-random-subject)
  (case (random 3)
    [(0) (random-element evil-strings)]
    [(1) (make-string (+ 10 (random 100))
                      (random-element '(#\a #\b #\c #\x)))]
    [(2) (random-ascii-string (+ 1 (random 200)))]))

;;; ========== Run ==========

;; Fuzz pattern compilation
(define pregexp-compile-stats
  (fuzz-run "pregexp-compile"
    (lambda (pattern)
      (guard (exn [#t (void)])
        (pregexp pattern)))
    gen-random-pattern))

;; Fuzz pattern matching (compile + match)
(define pregexp-match-stats
  (fuzz-run "pregexp-match"
    (lambda (_)
      (let ([pattern (gen-random-pattern)]
            [subject (gen-random-subject)])
        (guard (exn [#t (void)])
          (pregexp-match pattern subject))))
    (lambda () #f)))

(when (or (> (fuzz-stats-crashes pregexp-compile-stats) 0)
          (> (fuzz-stats-crashes pregexp-match-stats) 0))
  (exit 1))
