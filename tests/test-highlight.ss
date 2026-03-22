#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc highlight))

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

(define (assert-true val msg)
  (unless val
    (error 'assert-true (string-append msg ": expected true"))))

(define (string-contains haystack needle)
  (let ([hlen (string-length haystack)]
        [nlen (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nlen) hlen) #f]
        [(string=? (substring haystack i (+ i nlen)) needle) i]
        [else (loop (+ i 1))]))))

(define esc "\x1b;")

;; ========== Token classification tests ==========

(test "highlight-scheme returns a string"
  (lambda ()
    (assert-true (string? (highlight-scheme "(+ 1 2)"))
                 "result should be a string")))

(test "highlight-scheme preserves code text"
  (lambda ()
    ;; Stripping ANSI codes should yield the original text
    (let* ([code "(define x 42)"]
           [highlighted (highlight-scheme code)]
           ;; Remove all ANSI escape sequences
           [stripped (let loop ([i 0] [acc '()])
                       (cond
                         [(>= i (string-length highlighted))
                          (list->string (reverse acc))]
                         [(and (char=? (string-ref highlighted i) #\x1b)
                               (< (+ i 1) (string-length highlighted))
                               (char=? (string-ref highlighted (+ i 1)) #\[))
                          ;; Skip until 'm'
                          (let skip ([j (+ i 2)])
                            (cond
                              [(>= j (string-length highlighted))
                               (list->string (reverse acc))]
                              [(char=? (string-ref highlighted j) #\m)
                               (loop (+ j 1) acc)]
                              [else (skip (+ j 1))]))]
                         [else (loop (+ i 1) (cons (string-ref highlighted i) acc))]))])
      (assert-equal stripped code "stripped text matches original"))))

(test "keyword coloring"
  (lambda ()
    (let ([result (highlight-scheme "define")])
      ;; Should contain bold blue ANSI code
      (assert-true (string-contains result (string-append esc "[1;34m"))
                   "keyword should have bold blue"))))

(test "string coloring"
  (lambda ()
    (let ([result (highlight-scheme "\"hello world\"")])
      (assert-true (string-contains result (string-append esc "[32m"))
                   "string should have green"))))

(test "number coloring"
  (lambda ()
    (let ([result (highlight-scheme "42")])
      (assert-true (string-contains result (string-append esc "[36m"))
                   "number should have cyan"))))

(test "comment coloring"
  (lambda ()
    (let ([result (highlight-scheme "; a comment")])
      (assert-true (string-contains result (string-append esc "[2m"))
                   "comment should have dim"))))

(test "boolean coloring"
  (lambda ()
    (let ([result (highlight-scheme "#t")])
      (assert-true (string-contains result (string-append esc "[35m"))
                   "boolean should have magenta"))))

(test "character literal coloring"
  (lambda ()
    (let ([result (highlight-scheme "#\\x")])
      (assert-true (string-contains result (string-append esc "[33m"))
                   "char should have yellow"))))

(test "multi-character literal #\\space"
  (lambda ()
    (let ([result (highlight-scheme "#\\space")])
      (assert-true (string-contains result (string-append esc "[33m"))
                   "named char should have yellow"))))

;; ========== SXML output tests ==========

(test "highlight-scheme/sxml returns sxml"
  (lambda ()
    (let ([result (highlight-scheme/sxml "(+ 1 2)")])
      (assert-true (pair? result) "should be a list")
      (assert-equal (car result) 'highlight "root should be 'highlight"))))

(test "sxml keyword classification"
  (lambda ()
    (let ([result (highlight-scheme/sxml "define")])
      ;; Should have (span (@ (class "keyword")) "define")
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (assert-true (not (null? spans)) "should have span elements")
        (let ([span (car spans)])
          (assert-equal (cadr span) '(@ (class "keyword"))
                        "class should be keyword"))))))

(test "sxml string classification"
  (lambda ()
    (let ([result (highlight-scheme/sxml "\"hello\"")])
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (assert-true (not (null? spans)) "should have span")
        (let ([span (car spans)])
          (assert-equal (cadr span) '(@ (class "string"))
                        "class should be string"))))))

(test "sxml number classification"
  (lambda ()
    (let ([result (highlight-scheme/sxml "42")])
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (let ([span (car spans)])
          (assert-equal (cadr span) '(@ (class "number"))
                        "class should be number"))))))

(test "sxml boolean classification"
  (lambda ()
    (let ([result (highlight-scheme/sxml "#f")])
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (let ([span (car spans)])
          (assert-equal (cadr span) '(@ (class "boolean"))
                        "class should be boolean"))))))

(test "sxml comment classification"
  (lambda ()
    (let ([result (highlight-scheme/sxml "; hello")])
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (let ([span (car spans)])
          (assert-equal (cadr span) '(@ (class "comment"))
                        "class should be comment"))))))

(test "sxml paren classification"
  (lambda ()
    (let ([result (highlight-scheme/sxml "()")])
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (assert-equal (length spans) 2 "should have 2 paren spans")
        (assert-equal (cadr (car spans)) '(@ (class "paren"))
                      "class should be paren")))))

(test "sxml char classification"
  (lambda ()
    (let ([result (highlight-scheme/sxml "#\\a")])
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (let ([span (car spans)])
          (assert-equal (cadr span) '(@ (class "char"))
                        "class should be char"))))))

;; ========== Complex expression tests ==========

(test "full expression highlighting"
  (lambda ()
    (let ([result (highlight-scheme/sxml "(define (factorial n)\n  (if (< n 2) 1\n      (* n (factorial (- n 1)))))")])
      (assert-true (pair? result) "should produce sxml")
      ;; Check that we have keyword spans for 'define' and 'if'
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (let ([keyword-spans
               (filter (lambda (sp)
                         (equal? (cadr sp) '(@ (class "keyword"))))
                       spans)])
          (assert-true (>= (length keyword-spans) 2)
                       "should have at least 2 keywords"))))))

(test "block comment #| ... |#"
  (lambda ()
    (let ([result (highlight-scheme/sxml "#| block comment |#")])
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (assert-true (not (null? spans)) "should have spans")
        (assert-equal (cadr (car spans)) '(@ (class "comment"))
                      "block comment should be comment")))))

(test "nested block comments"
  (lambda ()
    (let ([result (highlight-scheme/sxml "#| outer #| inner |# outer |#")])
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (assert-equal (length spans) 1 "should be single comment span")
        (assert-equal (caddr (car spans)) "#| outer #| inner |# outer |#"
                      "should capture full nested comment")))))

(test "escaped characters in strings"
  (lambda ()
    (let ([result (highlight-scheme/sxml "\"hello \\\"world\\\"\"")])
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (assert-equal (length spans) 1 "should be single string span")
        (assert-equal (cadr (car spans)) '(@ (class "string"))
                      "should be string class")))))

(test "negative number"
  (lambda ()
    (let ([result (highlight-scheme/sxml "-42")])
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (assert-equal (cadr (car spans)) '(@ (class "number"))
                      "negative number should be number class")))))

(test "hex number prefix"
  (lambda ()
    (let ([result (highlight-scheme/sxml "#xFF")])
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (assert-equal (cadr (car spans)) '(@ (class "number"))
                      "#xFF should be number class")))))

(test "reader directive #!chezscheme"
  (lambda ()
    (let ([result (highlight-scheme/sxml "#!chezscheme")])
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (assert-equal (cadr (car spans)) '(@ (class "comment"))
                      "reader directive should be comment class")))))

;; ========== highlight-to-port test ==========

(test "highlight-to-port writes to port"
  (lambda ()
    (let ([port (open-output-string)])
      (highlight-to-port "(+ 1 2)" port)
      (let ([result (get-output-string port)])
        (assert-true (> (string-length result) 0)
                     "should write something")
        (assert-true (string-contains result esc)
                     "should contain ANSI escapes")))))

;; ========== Theme tests ==========

(test "make-theme overrides defaults"
  (lambda ()
    (let ([theme (make-theme `((keyword . ,(string-append esc "[31m"))))])
      ;; keyword should now be red
      (let ([keyword-entry (assq 'keyword theme)])
        (assert-equal (cdr keyword-entry) (string-append esc "[31m")
                      "keyword should be overridden to red"))
      ;; string should still be green (default)
      (let ([string-entry (assq 'string theme)])
        (assert-equal (cdr string-entry) (string-append esc "[32m")
                      "string should keep default green")))))

(test "with-theme changes highlight colors"
  (lambda ()
    (let ([red-keywords (make-theme `((keyword . ,(string-append esc "[31m"))))])
      (let ([result (with-theme red-keywords (highlight-scheme "define"))])
        (assert-true (string-contains result (string-append esc "[31m"))
                     "should use red for keywords with custom theme")
        (assert-true (not (string-contains result (string-append esc "[1;34m")))
                     "should not use default blue")))))

(test "with-theme is scoped"
  (lambda ()
    (let ([red-keywords (make-theme `((keyword . ,(string-append esc "[31m"))))])
      (with-theme red-keywords (highlight-scheme "define"))
      ;; After with-theme, should be back to default
      (let ([result (highlight-scheme "define")])
        (assert-true (string-contains result (string-append esc "[1;34m"))
                     "should be back to default theme")))))

(test "highlight-to-port with custom theme"
  (lambda ()
    (let ([port (open-output-string)]
          [theme (make-theme `((keyword . ,(string-append esc "[31m"))))])
      (highlight-to-port "define" port theme)
      (let ([result (get-output-string port)])
        (assert-true (string-contains result (string-append esc "[31m"))
                     "should use custom theme via highlight-to-port")))))

;; ========== Edge case tests ==========

(test "empty string"
  (lambda ()
    (assert-equal (highlight-scheme "") "" "empty input => empty output")))

(test "whitespace only"
  (lambda ()
    (assert-equal (highlight-scheme "   ") "   " "whitespace preserved")))

(test "quote shorthand"
  (lambda ()
    (let ([result (highlight-scheme/sxml "'foo")])
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (assert-true (>= (length spans) 2) "should have quote and symbol")))))

(test "quasiquote and unquote"
  (lambda ()
    (let ([result (highlight-scheme/sxml "`(a ,b ,@c)")])
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (assert-true (>= (length spans) 5) "should tokenize quasiquote expression")))))

(test "datum comment #;"
  (lambda ()
    (let ([result (highlight-scheme/sxml "#; (foo)")])
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (assert-equal (cadr (car spans)) '(@ (class "comment"))
                      "#; should be comment")))))

(test "vector literal #("
  (lambda ()
    (let ([result (highlight-scheme/sxml "#(1 2 3)")])
      (let ([spans (filter (lambda (x) (and (pair? x) (eq? (car x) 'span)))
                           (cdr result))])
        (assert-true (not (null? spans)) "should tokenize vector")))))

(test "token-categories export"
  (lambda ()
    (assert-true (list? token-categories) "should be a list")
    (assert-true (memq 'keyword token-categories) "should contain keyword")
    (assert-true (memq 'string token-categories) "should contain string")
    (assert-true (memq 'comment token-categories) "should contain comment")))

(test "default-theme export"
  (lambda ()
    (assert-true (list? default-theme) "should be a list")
    (assert-true (assq 'keyword default-theme) "should have keyword entry")
    (assert-true (assq 'string default-theme) "should have string entry")))

;; ========== Summary ==========

(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
