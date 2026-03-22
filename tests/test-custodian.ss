#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc custodian))

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
    (error 'assert-true (string-append msg ": expected #t got " (format "~s" val)))))

;; Test 1: make-custodian and custodian?
(test "make-custodian creates a custodian"
  (lambda ()
    (let ([c (make-custodian)])
      (assert-true (custodian? c) "custodian? should be #t")
      (assert-true (not (custodian? 42)) "42 is not a custodian")
      (custodian-shutdown-all c))))

;; Test 2: custodian-register! and custodian-managed-list
(test "register resources and list them"
  (lambda ()
    (let ([c (make-custodian)]
          [closed? #f])
      (parameterize ([current-custodian c])
        (custodian-register! 'my-resource (lambda () (set! closed? #t)))
        (let ([managed (custodian-managed-list c)])
          (assert-equal (length managed) 1 "one resource")
          (assert-equal (car managed) 'my-resource "resource identity")))
      (custodian-shutdown-all c)
      (assert-true closed? "resource was shut down"))))

;; Test 3: shutdown closes all resources
(test "custodian-shutdown-all closes all resources"
  (lambda ()
    (let ([c (make-custodian)]
          [log '()])
      (custodian-register! c 'a (lambda () (set! log (cons 'a log))))
      (custodian-register! c 'b (lambda () (set! log (cons 'b log))))
      (custodian-register! c 'c (lambda () (set! log (cons 'c log))))
      (custodian-shutdown-all c)
      (assert-equal (length log) 3 "all three resources shut down")
      (assert-equal (custodian-managed-list c) '() "no resources after shutdown"))))

;; Test 4: hierarchical shutdown
(test "parent shutdown recursively shuts down children"
  (lambda ()
    (let* ([parent (make-custodian)]
           [child (parameterize ([current-custodian parent]) (make-custodian))]
           [parent-closed? #f]
           [child-closed? #f])
      (custodian-register! parent 'p-res (lambda () (set! parent-closed? #t)))
      (custodian-register! child 'c-res (lambda () (set! child-closed? #t)))
      ;; child should appear in parent's managed list
      (let ([managed (custodian-managed-list parent)])
        (assert-true (memq child managed) "child is in parent's managed list"))
      ;; shutdown parent
      (custodian-shutdown-all parent)
      (assert-true parent-closed? "parent resource closed")
      (assert-true child-closed? "child resource closed by parent shutdown"))))

;; Test 5: deep hierarchy
(test "three-level hierarchy shuts down recursively"
  (lambda ()
    (let* ([root (make-custodian)]
           [mid (parameterize ([current-custodian root]) (make-custodian))]
           [leaf (parameterize ([current-custodian mid]) (make-custodian))]
           [leaf-closed? #f])
      (custodian-register! leaf 'deep (lambda () (set! leaf-closed? #t)))
      (custodian-shutdown-all root)
      (assert-true leaf-closed? "leaf resource closed by root shutdown"))))

;; Test 6: with-custodian normal exit
(test "with-custodian shuts down on normal exit"
  (lambda ()
    (let ([closed? #f])
      (let ([result
              (with-custodian
                (custodian-register! 'res (lambda () (set! closed? #t)))
                42)])
        (assert-equal result 42 "body returns value")
        (assert-true closed? "resource closed after with-custodian")))))

;; Test 7: with-custodian exception exit
(test "with-custodian shuts down on exception"
  (lambda ()
    (let ([closed? #f])
      (guard (e [#t (void)])
        (with-custodian
          (custodian-register! 'res (lambda () (set! closed? #t)))
          (error 'test "boom")))
      (assert-true closed? "resource closed despite exception"))))

;; Test 8: custodian-open-input-file
(test "custodian-open-input-file registers and closes port"
  (lambda ()
    (let ([tmp "/tmp/test-custodian-input.txt"])
      ;; Create a temp file with known content
      (with-output-to-file tmp (lambda () (display "hello")) 'replace)
      (let ([c (make-custodian)])
        (let ([p (parameterize ([current-custodian c])
                   (custodian-open-input-file tmp))])
          ;; open-input-file returns a textual port in Chez
          (let ([data (get-string-all p)])
            (assert-equal data "hello" "read file contents"))
          ;; Port should be in managed list
          (assert-equal (length (custodian-managed-list c)) 1 "one managed port")
          ;; Shutdown should close the port
          (custodian-shutdown-all c)
          (assert-true (port-closed? p) "port closed after shutdown")))
      (delete-file tmp))))

;; Test 9: custodian-open-output-file
(test "custodian-open-output-file registers and closes port"
  (lambda ()
    (let ([tmp "/tmp/test-custodian-output.txt"])
      (when (file-exists? tmp) (delete-file tmp))
      (let ([c (make-custodian)])
        (let ([p (parameterize ([current-custodian c])
                   (custodian-open-output-file tmp))])
          (display "world" p)
          (custodian-shutdown-all c)
          (assert-true (port-closed? p) "port closed after shutdown")))
      ;; Verify data was written before close
      (let ([data (with-input-from-file tmp (lambda () (get-string-all (current-input-port))))])
        (assert-equal data "world" "data written to file"))
      (delete-file tmp))))

;; Test 10: shutdown is idempotent
(test "double shutdown is safe"
  (lambda ()
    (let ([c (make-custodian)]
          [count 0])
      (custodian-register! c 'res (lambda () (set! count (+ count 1))))
      (custodian-shutdown-all c)
      (custodian-shutdown-all c)  ;; should not error or double-close
      (assert-equal count 1 "shutdown proc called only once"))))

;; Test 11: error in one resource shutdown doesn't prevent others
(test "error in shutdown proc does not prevent other shutdowns"
  (lambda ()
    (let ([c (make-custodian)]
          [closed? #f])
      (custodian-register! c 'good (lambda () (set! closed? #t)))
      (custodian-register! c 'bad (lambda () (error 'test "shutdown error")))
      (custodian-shutdown-all c)
      (assert-true closed? "good resource still shut down"))))

;; Test 12: child shutdown removes from parent
(test "shutting down child removes it from parent"
  (lambda ()
    (let* ([parent (make-custodian)]
           [child (parameterize ([current-custodian parent]) (make-custodian))])
      (assert-true (memq child (custodian-managed-list parent))
                   "child in parent before shutdown")
      (custodian-shutdown-all child)
      (assert-true (not (memq child (custodian-managed-list parent)))
                   "child removed from parent after shutdown"))))

;; Test 13: current-custodian parameter
(test "current-custodian parameter works"
  (lambda ()
    (let ([c (make-custodian)])
      (assert-true (not (eq? c (current-custodian))) "not current before parameterize")
      (parameterize ([current-custodian c])
        (assert-true (eq? c (current-custodian)) "current inside parameterize"))
      (custodian-shutdown-all c))))

;; Test 14: register with explicit custodian (3-arg form)
(test "custodian-register! with explicit custodian"
  (lambda ()
    (let ([c (make-custodian)]
          [closed? #f])
      (custodian-register! c 'res (lambda () (set! closed? #t)))
      (custodian-shutdown-all c)
      (assert-true closed? "resource in explicit custodian shut down"))))

;; Test 15: nested with-custodian
(test "nested with-custodian creates independent scopes"
  (lambda ()
    (let ([outer-closed? #f]
          [inner-closed? #f])
      (with-custodian
        (custodian-register! 'outer (lambda () (set! outer-closed? #t)))
        (with-custodian
          (custodian-register! 'inner (lambda () (set! inner-closed? #t))))
        ;; Inner should be closed, outer not yet
        (assert-true inner-closed? "inner closed after inner with-custodian")
        (assert-true (not outer-closed?) "outer not yet closed"))
      (assert-true outer-closed? "outer closed after outer with-custodian"))))

(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
