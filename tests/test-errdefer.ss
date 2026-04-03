#!chezscheme
;;; Test: errdefer — error-path cleanup

(import (std errdefer))

(define pass 0)
(define fail 0)

(define-syntax chk
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([r expr] [e expected])
       (if (equal? r e)
         (set! pass (+ pass 1))
         (begin
           (set! fail (+ fail 1))
           (display "FAIL: ") (write 'expr)
           (display " => ") (write r)
           (display " expected ") (write e) (newline))))]))

;; Helper: track cleanup calls
(define cleanup-log '())
(define (log-cleanup! msg)
  (set! cleanup-log (append cleanup-log (list msg))))
(define (reset-log!)
  (set! cleanup-log '()))

;; --- Test 1: errdefer does NOT run on success ---
(reset-log!)
(let ([result (errdefer (log-cleanup! 'cleanup-ran)
                (+ 1 2))])
  (chk result => 3)
  (chk cleanup-log => '()))  ; cleanup should NOT run

;; --- Test 2: errdefer DOES run on exception ---
(reset-log!)
(guard (exn [#t 'caught])
  (errdefer (log-cleanup! 'cleanup-ran)
    (error 'test "intentional error")))
(chk cleanup-log => '(cleanup-ran))  ; cleanup should run

;; --- Test 3: errdefer with multiple body forms ---
(reset-log!)
(let ([result (errdefer (log-cleanup! 'cleanup)
                (log-cleanup! 'body1)
                (log-cleanup! 'body2)
                42)])
  (chk result => 42)
  ;; Body logs should be there, cleanup should NOT
  (chk cleanup-log => '(body1 body2)))

;; --- Test 4: errdefer* variant ---
(reset-log!)
(let ([result (errdefer* (log-cleanup! 'cleanup)
                (+ 10 20))])
  (chk result => 30)
  (chk cleanup-log => '()))

;; --- Test 5: LIFO stacking with with-errdefer (success) ---
(reset-log!)
(let ([result (with-errdefer
                ([(log-cleanup! 'first)]
                 [(log-cleanup! 'second)]
                 [(log-cleanup! 'third)])
                (+ 1 1))])
  (chk result => 2)
  (chk cleanup-log => '()))  ; no cleanup on success

;; --- Test 6: LIFO stacking with with-errdefer (error) ---
(reset-log!)
(guard (exn [#t 'caught])
  (with-errdefer
    ([(log-cleanup! 'first)]
     [(log-cleanup! 'second)]
     [(log-cleanup! 'third)])
    (error 'test "boom")))
;; Should run in LIFO order: third, second, first
(chk cleanup-log => '(third second first))

;; --- Test 7: Partial success with stacked errdefers ---
;; If error happens after some errdefers complete, only remaining ones fire
(reset-log!)
(guard (exn [#t 'caught])
  (errdefer (log-cleanup! 'outer)
    (log-cleanup! 'setup)
    (errdefer (log-cleanup! 'inner)
      (log-cleanup! 'middle)
      (error 'test "error in inner"))))
;; Order: setup runs, middle runs, inner and outer cleanup fire
(chk cleanup-log => '(setup middle inner outer))

;; --- Test 8: Real-world pattern: resource cleanup on error ---
(define resources '())
(define (acquire-resource name)
  (set! resources (cons name resources))
  name)
(define (release-resource name)
  (set! resources (filter (lambda (x) (not (equal? x name))) resources)))

(set! resources '())
(let ([r (errdefer (release-resource 'temp-file)
           (acquire-resource 'temp-file)
           ;; Simulate success: "rename" the file
           'renamed)])
  (chk r => 'renamed)
  ;; Resource should still be held (cleanup didn't run)
  (chk resources => '(temp-file)))

(set! resources '())
(guard (exn [#t 'caught])
  (errdefer (release-resource 'temp-file)
    (acquire-resource 'temp-file)
    (error 'test "operation failed")))
;; Resource should be released (cleanup ran)
(chk resources => '())

;; --- Summary ---
(newline)
(display "errdefer: ")
(display pass) (display " passed, ")
(display fail) (display " failed") (newline)
(when (> fail 0) (exit 1))
