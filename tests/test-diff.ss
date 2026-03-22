#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc diff))

(define test-count 0)
(define pass-count 0)

(define (test name thunk)
  (set! test-count (+ test-count 1))
  (guard (e [#t (display "FAIL: ") (display name) (newline)
              (display "  Error: ") (display (condition-message e)) (newline)])
    (thunk)
    (set! pass-count (+ pass-count 1))
    (display "PASS: ") (display name) (newline)))

(define (assert-equal actual expected msg)
  (unless (equal? actual expected)
    (error 'assert-equal
           (string-append msg ": expected " (format "~s" expected)
                          " got " (format "~s" actual)))))

;;; --- LCS tests ---

(test "lcs: both empty"
  (lambda ()
    (assert-equal (lcs '() '()) '() "lcs of empty lists")))

(test "lcs: one empty"
  (lambda ()
    (assert-equal (lcs '(a b c) '()) '() "lcs with empty second")
    (assert-equal (lcs '() '(a b c)) '() "lcs with empty first")))

(test "lcs: identical"
  (lambda ()
    (assert-equal (lcs '(a b c) '(a b c)) '(a b c) "lcs of identical")))

(test "lcs: no common"
  (lambda ()
    (assert-equal (lcs '(a b) '(c d)) '() "lcs with no common")))

(test "lcs: partial overlap"
  (lambda ()
    (assert-equal (lcs '(a b c d) '(b d f)) '(b d) "lcs partial")))

(test "lcs: interleaved"
  (lambda ()
    (let ([result (lcs '(a b c d e) '(a c e))])
      (assert-equal result '(a c e) "lcs interleaved"))))

(test "lcs: custom equality"
  (lambda ()
    (assert-equal (lcs '(1 2 3) '(1.0 2.0 3.0) =) '(1 2 3)
                  "lcs with numeric =")))

;;; --- diff tests ---

(test "diff: both empty"
  (lambda ()
    (assert-equal (diff '() '()) '() "diff of empty")))

(test "diff: identical lists"
  (lambda ()
    (assert-equal (diff '(a b c) '(a b c))
                  '((same a) (same b) (same c))
                  "diff identical")))

(test "diff: complete removal"
  (lambda ()
    (assert-equal (diff '(a b c) '())
                  '((remove a) (remove b) (remove c))
                  "diff all removed")))

(test "diff: complete addition"
  (lambda ()
    (assert-equal (diff '() '(x y z))
                  '((add x) (add y) (add z))
                  "diff all added")))

(test "diff: complete replacement"
  (lambda ()
    (assert-equal (diff '(a b) '(x y))
                  '((remove a) (remove b) (add x) (add y))
                  "diff complete replace")))

(test "diff: insertion at beginning"
  (lambda ()
    (assert-equal (diff '(b c) '(a b c))
                  '((add a) (same b) (same c))
                  "diff insert at start")))

(test "diff: insertion at end"
  (lambda ()
    (assert-equal (diff '(a b) '(a b c))
                  '((same a) (same b) (add c))
                  "diff insert at end")))

(test "diff: deletion from middle"
  (lambda ()
    (assert-equal (diff '(a b c) '(a c))
                  '((same a) (remove b) (same c))
                  "diff remove middle")))

(test "diff: mixed changes"
  (lambda ()
    (let ([result (diff '(a b c d e) '(a c d f))])
      ;; a is same, b removed, c same, d same, e removed, f added
      (assert-equal result
                    '((same a) (remove b) (same c) (same d) (remove e) (add f))
                    "diff mixed"))))

(test "diff: custom equality"
  (lambda ()
    (let ([result (diff '(1 2 3) '(1.0 3.0 4.0) =)])
      (assert-equal result
                    '((same 1) (remove 2) (same 3) (add 4.0))
                    "diff with numeric ="))))

;;; --- edit-distance tests ---

(test "edit-distance: both empty"
  (lambda ()
    (assert-equal (edit-distance '() '()) 0 "edit-dist empty")))

(test "edit-distance: one empty"
  (lambda ()
    (assert-equal (edit-distance '(a b c) '()) 3 "edit-dist from non-empty")
    (assert-equal (edit-distance '() '(a b c)) 3 "edit-dist to non-empty")))

(test "edit-distance: identical"
  (lambda ()
    (assert-equal (edit-distance '(a b c) '(a b c)) 0 "edit-dist identical")))

(test "edit-distance: single insertion"
  (lambda ()
    (assert-equal (edit-distance '(a b) '(a b c)) 1 "edit-dist insert one")))

(test "edit-distance: single deletion"
  (lambda ()
    (assert-equal (edit-distance '(a b c) '(a b)) 1 "edit-dist delete one")))

(test "edit-distance: substitution"
  (lambda ()
    (assert-equal (edit-distance '(a b c) '(a x c)) 1 "edit-dist substitute")))

(test "edit-distance: complete replacement"
  (lambda ()
    (assert-equal (edit-distance '(a b) '(x y)) 2 "edit-dist full replace")))

(test "edit-distance: custom equality"
  (lambda ()
    (assert-equal (edit-distance '(1 2 3) '(1.0 2.0 3.0) =) 0
                  "edit-dist with numeric =")))

;;; --- diff->string tests ---

(test "diff->string: formats correctly"
  (lambda ()
    (let ([result (diff->string '((same a) (remove b) (add c)))])
      (assert-equal result " a\n-b\n+c\n" "diff->string format"))))

(test "diff->string: empty diff"
  (lambda ()
    (assert-equal (diff->string '()) "" "diff->string empty")))

;;; --- diff-report tests ---

(test "diff-report: prints to stdout"
  (lambda ()
    (let ([output (with-output-to-string
                    (lambda () (diff-report '((same x) (add y)))))])
      (assert-equal output " x\n+y\n" "diff-report output"))))

;;; --- diff-strings tests ---

(test "diff-strings: identical strings"
  (lambda ()
    (let ([result (diff-strings "hello\nworld" "hello\nworld")])
      (assert-equal result " hello\n world\n" "diff-strings identical"))))

(test "diff-strings: line added"
  (lambda ()
    (let ([result (diff-strings "a\nb" "a\nb\nc")])
      (assert-equal result " a\n b\n+c\n" "diff-strings add line"))))

(test "diff-strings: line removed"
  (lambda ()
    (let ([result (diff-strings "a\nb\nc" "a\nc")])
      (assert-equal result " a\n-b\n c\n" "diff-strings remove line"))))

(test "diff-strings: line changed"
  (lambda ()
    (let ([result (diff-strings "a\nb\nc" "a\nx\nc")])
      (assert-equal result " a\n-b\n+x\n c\n" "diff-strings change line"))))

(test "diff-strings: empty strings"
  (lambda ()
    (let ([result (diff-strings "" "")])
      (assert-equal result " \n" "diff-strings empty"))))

(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
