#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc terminal))

(define test-count 0)
(define pass-count 0)

(define (test name thunk)
  (set! test-count (+ test-count 1))
  (guard (e [#t (display "FAIL: ") (display name) (newline)
              (display "  Error: ")
              (display (if (message-condition? e) (condition-message e) e))
              (newline)])
    (thunk)
    (set! pass-count (+ pass-count 1))
    (display "PASS: ") (display name) (newline)))

(define (assert-equal actual expected msg)
  (unless (equal? actual expected)
    (error 'assert-equal
           (string-append msg ": expected " (format "~s" expected)
                          " got " (format "~s" actual)))))

;; Helper: capture output to a string by redirecting current-output-port
(define (capture-output thunk)
  (let ([p (open-output-string)])
    (parameterize ([current-output-port p])
      (thunk))
    (get-output-string p)))

(define esc "\x1b;")
(define (csi . parts)
  (apply string-append esc "[" parts))

(define (string-contains haystack needle)
  (let ([hlen (string-length haystack)]
        [nlen (string-length needle)])
    (let lp ([i 0])
      (cond
        [(> (+ i nlen) hlen) #f]
        [(string=? (substring haystack i (+ i nlen)) needle) #t]
        [else (lp (+ i 1))]))))

(display "--- (std misc terminal) tests ---\n")

;; ========== Cursor control tests ==========

(test "cursor-up default"
  (lambda ()
    (assert-equal (capture-output (lambda () (cursor-up)))
                  (csi "1" "A")
                  "cursor-up default")))

(test "cursor-up n"
  (lambda ()
    (assert-equal (capture-output (lambda () (cursor-up 5)))
                  (csi "5" "A")
                  "cursor-up 5")))

(test "cursor-down default"
  (lambda ()
    (assert-equal (capture-output (lambda () (cursor-down)))
                  (csi "1" "B")
                  "cursor-down default")))

(test "cursor-down n"
  (lambda ()
    (assert-equal (capture-output (lambda () (cursor-down 3)))
                  (csi "3" "B")
                  "cursor-down 3")))

(test "cursor-forward default"
  (lambda ()
    (assert-equal (capture-output (lambda () (cursor-forward)))
                  (csi "1" "C")
                  "cursor-forward default")))

(test "cursor-forward n"
  (lambda ()
    (assert-equal (capture-output (lambda () (cursor-forward 10)))
                  (csi "10" "C")
                  "cursor-forward 10")))

(test "cursor-back default"
  (lambda ()
    (assert-equal (capture-output (lambda () (cursor-back)))
                  (csi "1" "D")
                  "cursor-back default")))

(test "cursor-back n"
  (lambda ()
    (assert-equal (capture-output (lambda () (cursor-back 7)))
                  (csi "7" "D")
                  "cursor-back 7")))

(test "cursor-position"
  (lambda ()
    (assert-equal (capture-output (lambda () (cursor-position 10 20)))
                  (csi "10" ";" "20" "H")
                  "cursor-position 10 20")))

(test "cursor-save"
  (lambda ()
    (assert-equal (capture-output cursor-save)
                  (csi "s")
                  "cursor-save")))

(test "cursor-restore"
  (lambda ()
    (assert-equal (capture-output cursor-restore)
                  (csi "u")
                  "cursor-restore")))

(test "cursor-hide"
  (lambda ()
    (assert-equal (capture-output cursor-hide)
                  (csi "?" "25" "l")
                  "cursor-hide")))

(test "cursor-show"
  (lambda ()
    (assert-equal (capture-output cursor-show)
                  (csi "?" "25" "h")
                  "cursor-show")))

;; ========== Screen control tests ==========

(test "clear-screen"
  (lambda ()
    (assert-equal (capture-output clear-screen)
                  (csi "2" "J")
                  "clear-screen")))

(test "clear-line"
  (lambda ()
    (assert-equal (capture-output clear-line)
                  (csi "2" "K")
                  "clear-line")))

(test "clear-to-end"
  (lambda ()
    (assert-equal (capture-output clear-to-end)
                  (csi "0" "K")
                  "clear-to-end")))

(test "clear-to-beginning"
  (lambda ()
    (assert-equal (capture-output clear-to-beginning)
                  (csi "1" "K")
                  "clear-to-beginning")))

;; ========== Text styling tests ==========

(test "bold emit"
  (lambda ()
    (assert-equal (capture-output (lambda () (bold)))
                  (csi "1" "m")
                  "bold emit")))

(test "bold wrap text"
  (lambda ()
    (assert-equal (bold "hello")
                  (string-append (csi "1" "m") "hello" (csi "0" "m"))
                  "bold wrap")))

(test "dim wrap text"
  (lambda ()
    (assert-equal (dim "hello")
                  (string-append (csi "2" "m") "hello" (csi "0" "m"))
                  "dim wrap")))

(test "italic wrap text"
  (lambda ()
    (assert-equal (italic "hello")
                  (string-append (csi "3" "m") "hello" (csi "0" "m"))
                  "italic wrap")))

(test "underline wrap text"
  (lambda ()
    (assert-equal (underline "hello")
                  (string-append (csi "4" "m") "hello" (csi "0" "m"))
                  "underline wrap")))

(test "blink wrap text"
  (lambda ()
    (assert-equal (blink "hello")
                  (string-append (csi "5" "m") "hello" (csi "0" "m"))
                  "blink wrap")))

(test "reverse-video wrap text"
  (lambda ()
    (assert-equal (reverse-video "hello")
                  (string-append (csi "7" "m") "hello" (csi "0" "m"))
                  "reverse-video wrap")))

(test "reset-style"
  (lambda ()
    (assert-equal (capture-output reset-style)
                  (csi "0" "m")
                  "reset-style")))

;; ========== Color tests ==========

(test "fg-color named emit"
  (lambda ()
    (assert-equal (capture-output (lambda () (fg-color 'red)))
                  (csi "31" "m")
                  "fg red emit")))

(test "fg-color named wrap"
  (lambda ()
    (assert-equal (fg-color 'green "hi")
                  (string-append (csi "32" "m") "hi" (csi "0" "m"))
                  "fg green wrap")))

(test "fg-color all named colors"
  (lambda ()
    (for-each
      (lambda (pair)
        (let ([name (car pair)] [code (cdr pair)])
          (assert-equal
            (capture-output (lambda () (fg-color name)))
            (csi (number->string (+ 30 code)) "m")
            (format "fg ~a" name))))
      '((black . 0) (red . 1) (green . 2) (yellow . 3)
        (blue . 4) (magenta . 5) (cyan . 6) (white . 7)))))

(test "bg-color named emit"
  (lambda ()
    (assert-equal (capture-output (lambda () (bg-color 'blue)))
                  (csi "44" "m")
                  "bg blue emit")))

(test "bg-color named wrap"
  (lambda ()
    (assert-equal (bg-color 'yellow "hi")
                  (string-append (csi "43" "m") "hi" (csi "0" "m"))
                  "bg yellow wrap")))

(test "fg-color 256 emit"
  (lambda ()
    (assert-equal (capture-output (lambda () (fg-color 196)))
                  (csi "38;5;" "196" "m")
                  "fg 256 emit")))

(test "fg-color 256 wrap"
  (lambda ()
    (assert-equal (fg-color 42 "text")
                  (string-append (csi "38;5;" "42" "m") "text" (csi "0" "m"))
                  "fg 256 wrap")))

(test "bg-color 256 emit"
  (lambda ()
    (assert-equal (capture-output (lambda () (bg-color 220)))
                  (csi "48;5;" "220" "m")
                  "bg 256 emit")))

(test "bg-color 256 wrap"
  (lambda ()
    (assert-equal (bg-color 100 "text")
                  (string-append (csi "48;5;" "100" "m") "text" (csi "0" "m"))
                  "bg 256 wrap")))

(test "fg-color bad name errors"
  (lambda ()
    (let ([got-error #f])
      (guard (exn [#t (set! got-error #t)])
        (fg-color 'purple))
      (assert-equal got-error #t "should error on bad color name"))))

;; ========== Terminal dimension tests ==========

(test "terminal-width returns integer"
  (lambda ()
    (assert-equal (integer? (terminal-width)) #t "width is integer")))

(test "terminal-height returns integer"
  (lambda ()
    (assert-equal (integer? (terminal-height)) #t "height is integer")))

(test "terminal-width positive"
  (lambda ()
    (assert-equal (> (terminal-width) 0) #t "width > 0")))

(test "terminal-height positive"
  (lambda ()
    (assert-equal (> (terminal-height) 0) #t "height > 0")))

;; ========== with-alternate-screen test ==========

(test "with-alternate-screen emits correct sequences"
  (lambda ()
    (let ([body-ran #f])
      (let ([output (capture-output
                      (lambda ()
                        (with-alternate-screen
                          (lambda ()
                            (set! body-ran #t)))))])
        (assert-equal body-ran #t "body executed")
        ;; Should contain enter and exit sequences
        (assert-equal
          (string-contains output (csi "?" "1049" "h"))
          #t
          "enter alt screen")
        (assert-equal
          (string-contains output (csi "?" "1049" "l"))
          #t
          "exit alt screen")))))

;; ========== with-raw-mode test ==========
;; We can only test that it runs the body and doesn't crash.
;; Actual raw mode requires a real tty, which automated tests lack.

(test "with-raw-mode runs body"
  (lambda ()
    (let ([body-ran #f])
      (with-raw-mode (lambda () (set! body-ran #t)))
      (assert-equal body-ran #t "body executed"))))

;; ========== Composability tests ==========

(test "nested styling"
  (lambda ()
    ;; bold + fg-color produces correct nested escapes
    (let ([result (bold (fg-color 'red "hello"))])
      (assert-equal (string? result) #t "returns string")
      ;; Should contain bold open, fg red, text, reset sequences
      (assert-equal (string-contains result "hello") #t "contains text"))))

(test "multiple cursor moves captured"
  (lambda ()
    (let ([output (capture-output
                    (lambda ()
                      (cursor-up 2)
                      (cursor-forward 5)
                      (cursor-down 1)))])
      (assert-equal
        output
        (string-append (csi "2" "A") (csi "5" "C") (csi "1" "B"))
        "sequence of moves"))))

;; ========== Summary ==========

(newline)
(display (format "~a/~a tests passed~%" pass-count test-count))
(when (< pass-count test-count)
  (display (format "~a tests FAILED~%" (- test-count pass-count)))
  (exit 1))
(display "All tests passed.\n")
