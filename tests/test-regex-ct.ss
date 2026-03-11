#!chezscheme
;;; Tests for (std regex-ct) -- Compile-Time Regular Expressions

(import (chezscheme)
        (std regex-ct))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(printf "--- Phase 2b: Compile-Time Regular Expressions ---~%~%")

;;; ======== regex-dfa-compatible? ========

(test "dfa-compatible: simple pattern"
  (regex-dfa-compatible? "abc")
  #t)

(test "dfa-compatible: character class"
  (regex-dfa-compatible? "[a-z]+")
  #t)

(test "dfa-compatible: alternation"
  (regex-dfa-compatible? "cat|dog")
  #t)

;;; ======== define-regex ========

(define-regex digit-re "[0-9]+")
(define-regex alpha-re "[a-zA-Z]+")
(define-regex empty-re "")

(test "define-regex creates procedure"
  (procedure? digit-re)
  #t)

(test "digit-re matches digits"
  (digit-re "12345")
  #t)

(test "digit-re rejects alpha"
  (digit-re "abc")
  #f)

(test "alpha-re matches letters"
  (alpha-re "hello")
  #t)

(test "alpha-re rejects digits"
  (alpha-re "123")
  #f)

(test "empty-re matches empty string"
  (empty-re "")
  #t)

;;; ======== More complex patterns ========

(define-regex word-re "\\w+")
(define-regex space-re "\\s+")

(test "word-re matches word"
  (word-re "hello123")
  #t)

(test "space-re matches spaces"
  (space-re "   ")
  #t)

(test "space-re rejects non-space"
  (space-re "abc")
  #f)

;;; ======== Anchored patterns (via regex-match? which handles anchors correctly) ========

(test "anchored via regex-match?: matches full digits"
  (regex-match? "^[0-9]+$" "42")
  #t)

(test "anchored via regex-match?: rejects partial"
  (regex-match? "^[0-9]+$" "42abc")
  #f)

;;; ======== match-regex ========

(test "match-regex captures groups"
  (match-regex "(\\d+)-(\\d+)" "123-456")
  '("123" "456"))

(test "match-regex no match returns #f"
  (match-regex "\\d+" "abc")
  #f)

(test "match-regex no groups returns empty captures"
  (match-regex "\\d+" "42")
  '())

;;; ======== regex-match? ========

(test "regex-match? matches"
  (regex-match? "[0-9]+" "123")
  #t)

(test "regex-match? no match"
  (regex-match? "[0-9]+" "abc")
  #f)

;;; ======== regex-search ========

(test "regex-search finds match"
  (pair? (regex-search "[0-9]+" "abc 123 def"))
  #t)

(test "regex-search no match"
  (regex-search "[0-9]+" "abc")
  #f)

;;; ======== compile-regex-to-dfa ========

(test "compile-regex-to-dfa returns 3 values"
  (let-values ([(states transitions accepts) (compile-regex-to-dfa "[0-9]+")])
    (and (list? states) (list? transitions) (list? accepts)))
  #t)

;;; ======== dfa-state-count ========

(test "dfa-state-count is positive"
  (> (dfa-state-count "[0-9]+") 0)
  #t)

(test "dfa-state-count is integer"
  (integer? (dfa-state-count "abc"))
  #t)

;;; ======== dfa-dot ========

(test "dfa-dot returns string"
  (string? (dfa-dot "[0-9]+"))
  #t)

(test "dfa-dot contains digraph"
  (let ([dot (dfa-dot "a|b")])
    (string=? (substring dot 0 7) "digraph"))
  #t)

;;; ======== Summary ========

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
