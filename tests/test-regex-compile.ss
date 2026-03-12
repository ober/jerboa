#!/usr/bin/env scheme-script
;;; Tests for Compile-Time Regex Compilation (Phase 5a — Track 15.1)

(import
  (chezscheme)
  (std text regex-compile))

;; --------------------------------------------------------------------------
;; Minimal test framework
;; --------------------------------------------------------------------------

(define test-count 0)
(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ name expr => expected)
     (begin
       (set! test-count (+ test-count 1))
       (let ([result expr])
         (if (equal? result expected)
             (begin
               (printf "  PASS: ~a~n" name)
               (set! pass-count (+ pass-count 1)))
             (begin
               (printf "  FAIL: ~a~n" name)
               (printf "    expected: ~s~n" expected)
               (printf "    got:      ~s~n" result)
               (set! fail-count (+ fail-count 1))))))]))

(define-syntax check-true
  (syntax-rules ()
    [(_ name expr) (check name expr => #t)]))

(define-syntax check-false
  (syntax-rules ()
    [(_ name expr) (check name expr => #f)]))

;; --------------------------------------------------------------------------
;; 1. Pattern creation
;; --------------------------------------------------------------------------

(printf "~n--- Pattern Creation ---~n")

(let ([p (compile-regex "a")])
  (check-true "compile-regex returns regex-pattern?" (regex-pattern? p)))

(define-regex lit-a "a")
(check-true "define-regex works" (regex-pattern? lit-a))

;; --------------------------------------------------------------------------
;; 2. Literal matching
;; --------------------------------------------------------------------------

(printf "~n--- Literal Matching ---~n")

(define-regex pat-a "a")
(check-true  "single char matches"         (regex-match? pat-a "a"))
(check-false "single char rejects other"   (regex-match? pat-a "b"))
(check-false "single char rejects empty"   (regex-match? pat-a ""))

(define-regex pat-hello "hello")
(check-true  "multi-char matches"          (regex-match? pat-hello "hello"))
(check-false "multi-char rejects prefix"   (regex-match? pat-hello "hell"))
(check-false "multi-char rejects other"    (regex-match? pat-hello "world"))

;; --------------------------------------------------------------------------
;; 3. Character classes
;; --------------------------------------------------------------------------

(printf "~n--- Character Classes ---~n")

(let* ([digit-ast (make-regex-char-class '(#\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7 #\8 #\9) #f)]
       [digit (compile-regex digit-ast)])
  (check-true  "digit class matches 5"   (regex-match? digit "5"))
  (check-false "digit class rejects a"   (regex-match? digit "a")))

(let* ([non-digit (make-regex-char-class '(#\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7 #\8 #\9) #t)]
       [ndp (compile-regex non-digit)])
  (check-false "negated class rejects 5" (regex-match? ndp "5"))
  (check-true  "negated class matches a" (regex-match? ndp "a")))

;; --------------------------------------------------------------------------
;; 4. Sequence patterns
;; --------------------------------------------------------------------------

(printf "~n--- Sequence Patterns ---~n")

(let* ([abc (make-regex-sequence
              (list (make-regex-literal #\a)
                    (make-regex-literal #\b)
                    (make-regex-literal #\c)))]
       [p (compile-regex abc)])
  (check-true  "seq matches abc"   (regex-match? p "abc"))
  (check-false "seq rejects ab"    (regex-match? p "ab"))
  (check-false "seq rejects abcd"  (regex-match? p "abcd")))

;; --------------------------------------------------------------------------
;; 5. Alternation (or)
;; --------------------------------------------------------------------------

(printf "~n--- Alternation ---~n")

(let* ([ast (make-regex-or
              (list (make-regex-literal #\a)
                    (make-regex-literal #\b)))]
       [p (compile-regex ast)])
  (check-true  "or matches first"   (regex-match? p "a"))
  (check-true  "or matches second"  (regex-match? p "b"))
  (check-false "or rejects other"   (regex-match? p "c")))

;; --------------------------------------------------------------------------
;; 6. Optional (?)
;; --------------------------------------------------------------------------

(printf "~n--- Optional ---~n")

(let* ([ast (make-regex-optional (make-regex-literal #\a))]
       [p (compile-regex ast)])
  (check-true  "opt matches a"     (regex-match? p "a"))
  (check-true  "opt matches empty" (regex-match? p "")))

;; --------------------------------------------------------------------------
;; 7. Star (*)
;; --------------------------------------------------------------------------

(printf "~n--- Star ---~n")

(let* ([ast (make-regex-star (make-regex-literal #\a))]
       [p (compile-regex ast)])
  (check-true  "star matches empty"  (regex-match? p ""))
  (check-true  "star matches one"    (regex-match? p "a"))
  (check-true  "star matches many"   (regex-match? p "aaaa"))
  (check-false "star rejects b"      (regex-match? p "b")))

;; --------------------------------------------------------------------------
;; 8. Plus (+)
;; --------------------------------------------------------------------------

(printf "~n--- Plus ---~n")

(let* ([ast (make-regex-plus (make-regex-literal #\a))]
       [p (compile-regex ast)])
  (check-false "plus rejects empty"  (regex-match? p ""))
  (check-true  "plus matches one"    (regex-match? p "a"))
  (check-true  "plus matches many"   (regex-match? p "aaa"))
  (check-false "plus rejects b"      (regex-match? p "b")))

;; --------------------------------------------------------------------------
;; 9. Regex string parsing
;; --------------------------------------------------------------------------

(printf "~n--- String Parsing ---~n")

(let ([p (parse-regex-string "a")])
  (check-true "single char parsed as literal"    (regex-literal? p))
  (check      "literal char value" (regex-literal-char p) => #\a))

(let ([p (parse-regex-string "abc")])
  (check-true "multi-char parsed as sequence"    (regex-sequence? p))
  (check      "sequence length" (length (regex-sequence-parts p)) => 3))

(let ([p (parse-regex-string "\\.")])
  (check-true "escaped dot is literal"            (regex-literal? p))
  (check      "escaped char is dot" (regex-literal-char p) => #\.))

(let ([p (parse-regex-string "a*")])
  (check-true "a* parsed as star"                 (regex-star? p)))

(let ([p (parse-regex-string "a+")])
  (check-true "a+ parsed as plus"                 (regex-plus? p)))

(let ([p (parse-regex-string "a?")])
  (check-true "a? parsed as optional"             (regex-optional? p)))

;; --------------------------------------------------------------------------
;; 10. End-to-end string patterns
;; --------------------------------------------------------------------------

(printf "~n--- End-to-End String Patterns ---~n")

(define-regex pat-a-star "a*")
(check-true  "a* empty"  (regex-match? pat-a-star ""))
(check-true  "a* one"    (regex-match? pat-a-star "a"))
(check-true  "a* many"   (regex-match? pat-a-star "aaaa"))

(define-regex pat-ab-plus "ab+")
(check-false "ab+ rejects a"    (regex-match? pat-ab-plus "a"))
(check-true  "ab+ matches ab"   (regex-match? pat-ab-plus "ab"))
(check-true  "ab+ matches abbb" (regex-match? pat-ab-plus "abbb"))

;; --------------------------------------------------------------------------
;; 11. NFA construction
;; --------------------------------------------------------------------------

(printf "~n--- NFA Construction ---~n")

(let-values ([(start end) (build-nfa (make-regex-literal #\x))])
  (check-true "NFA start is state" (nfa-state? start))
  (check-true "NFA end is state"   (nfa-state? end))
  (check-true "NFA end is final"   (nfa-state-final? end))
  (check-false "NFA start not final" (nfa-state-final? start)))

;; --------------------------------------------------------------------------
;; 12. Epsilon closure
;; --------------------------------------------------------------------------

(printf "~n--- Epsilon Closure ---~n")

(let ([s (make-nfa-state 42 '() #f)])
  (let ([cl (epsilon-closure (list s))])
    (check-true "closure includes seed state" (and (memq s cl) #t))))

;; --------------------------------------------------------------------------
;; 13. Character matching
;; --------------------------------------------------------------------------

(printf "~n--- Character Matching ---~n")

(check-true  "char matches itself"       (char-matches? #\a #\a))
(check-false "char rejects other"        (char-matches? #\a #\b))
(check-false "epsilon never matches"     (char-matches? #\a 'epsilon))

(let ([cc (make-regex-char-class '(#\a #\b #\c) #f)])
  (check-true  "class matches member"    (char-matches? #\a cc))
  (check-false "class rejects non-member" (char-matches? #\d cc)))

(let ([ncc (make-regex-char-class '(#\a #\b #\c) #t)])
  (check-false "negated class rejects member"    (char-matches? #\a ncc))
  (check-true  "negated class matches non-member" (char-matches? #\d ncc)))

;; --------------------------------------------------------------------------
;; 14. Code generation
;; --------------------------------------------------------------------------

(printf "~n--- Code Generation ---~n")

(let-values ([(start _end) (build-nfa (make-regex-literal #\a))])
  (let* ([dfa  (nfa->dfa start)]
         [code (generate-matcher-code dfa)])
    (check-true "code is a list"       (list? code))
    (check      "code starts with lambda" (car code) => 'lambda)))

;; --------------------------------------------------------------------------
;; 15. Utility: regex-quote
;; --------------------------------------------------------------------------

(printf "~n--- regex-quote ---~n")

(check "plain text unchanged"      (regex-quote "hello")  => "hello")
(check "dot is quoted"             (regex-quote "a.b")    => "a\\.b")
(check "star is quoted"            (regex-quote "a*")     => "a\\*")
(check "multiple specials quoted"  (regex-quote "a.b*c+") => "a\\.b\\*c\\+")

;; --------------------------------------------------------------------------
;; Summary
;; --------------------------------------------------------------------------

(printf "~n===========================================~n")
(printf "Tests: ~a  |  Passed: ~a  |  Failed: ~a~n"
        test-count pass-count fail-count)
(printf "===========================================~n")
(when (> fail-count 0)
  (printf "~nFAILED~n")
  (exit 1))
(printf "~nAll tests passed!~n")
