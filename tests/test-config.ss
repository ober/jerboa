#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc config))

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
    (error 'assert-true (string-append msg ": expected #t"))))

;; Test 1: basic make-config and config-ref
(test "make-config and config-ref"
  (lambda ()
    (let ([cfg (make-config '((host . "localhost") (port . 8080)))])
      (assert-true (config? cfg) "is a config")
      (assert-equal (config-ref cfg 'host) "localhost" "host")
      (assert-equal (config-ref cfg 'port) 8080 "port"))))

;; Test 2: config-ref missing key raises error
(test "config-ref missing key errors"
  (lambda ()
    (let ([cfg (make-config '((x . 1)))])
      (let ([got-error #f])
        (guard (e [#t (set! got-error #t)])
          (config-ref cfg 'missing))
        (assert-true got-error "should error on missing key")))))

;; Test 3: parent cascading
(test "parent cascading"
  (lambda ()
    (let* ([parent (make-config '((host . "prod.example.com") (port . 443) (debug . #f)))]
           [child (make-config '((port . 9090) (name . "dev")) parent)])
      (assert-equal (config-ref child 'port) 9090 "child overrides port")
      (assert-equal (config-ref child 'host) "prod.example.com" "cascades to parent for host")
      (assert-equal (config-ref child 'debug) #f "cascades to parent for debug")
      (assert-equal (config-ref child 'name) "dev" "child-only key"))))

;; Test 4: config-ref/default
(test "config-ref/default"
  (lambda ()
    (let ([cfg (make-config '((x . 42)))])
      (assert-equal (config-ref/default cfg 'x 0) 42 "existing key")
      (assert-equal (config-ref/default cfg 'missing 99) 99 "missing key returns default"))))

;; Test 5: config-ref/default with parent
(test "config-ref/default cascades to parent"
  (lambda ()
    (let* ([parent (make-config '((a . 1)))]
           [child (make-config '((b . 2)) parent)])
      (assert-equal (config-ref/default child 'a 0) 1 "found in parent")
      (assert-equal (config-ref/default child 'b 0) 2 "found in child")
      (assert-equal (config-ref/default child 'c 99) 99 "not found anywhere"))))

;; Test 6: config-set functional update
(test "config-set returns new config"
  (lambda ()
    (let* ([cfg (make-config '((x . 1) (y . 2)))]
           [cfg2 (config-set cfg 'x 10)])
      (assert-equal (config-ref cfg 'x) 1 "original unchanged")
      (assert-equal (config-ref cfg2 'x) 10 "new config updated")
      (assert-equal (config-ref cfg2 'y) 2 "other key preserved"))))

;; Test 7: config-set adds new key
(test "config-set adds new key"
  (lambda ()
    (let* ([cfg (make-config '((x . 1)))]
           [cfg2 (config-set cfg 'y 2)])
      (assert-equal (config-ref cfg2 'x) 1 "old key")
      (assert-equal (config-ref cfg2 'y) 2 "new key"))))

;; Test 8: config-keys
(test "config-keys includes parent keys"
  (lambda ()
    (let* ([parent (make-config '((a . 1) (b . 2)))]
           [child (make-config '((b . 20) (c . 3)) parent)])
      (let ([keys (config-keys child)])
        (assert-true (memq 'a keys) "parent key a")
        (assert-true (memq 'b keys) "shared key b")
        (assert-true (memq 'c keys) "child key c")
        (assert-equal (length keys) 3 "no duplicates")))))

;; Test 9: config-merge
(test "config-merge second overrides first"
  (lambda ()
    (let* ([base (make-config '((host . "old") (port . 80) (debug . #t)))]
           [override (make-config '((port . 443) (tls . #t)))]
           [merged (config-merge base override)])
      (assert-equal (config-ref merged 'host) "old" "kept from base")
      (assert-equal (config-ref merged 'port) 443 "overridden")
      (assert-equal (config-ref merged 'debug) #t "kept from base")
      (assert-equal (config-ref merged 'tls) #t "added from override"))))

;; Test 10: config-from-file
(test "config-from-file reads s-expression"
  (lambda ()
    (let ([path "/tmp/test-config-jerboa.scm"])
      (call-with-output-file path
        (lambda (p)
          (write '((host . "filehost") (port . 3000)) p))
        'replace)
      (let ([cfg (config-from-file path)])
        (assert-equal (config-ref cfg 'host) "filehost" "host from file")
        (assert-equal (config-ref cfg 'port) 3000 "port from file"))
      (delete-file path))))

;; Test 11: config-from-file with parent
(test "config-from-file with parent"
  (lambda ()
    (let ([path "/tmp/test-config-jerboa2.scm"])
      (call-with-output-file path
        (lambda (p)
          (write '((port . 9999)) p))
        'replace)
      (let* ([parent (make-config '((host . "parent-host")))]
             [cfg (config-from-file path parent)])
        (assert-equal (config-ref cfg 'port) 9999 "from file")
        (assert-equal (config-ref cfg 'host) "parent-host" "from parent"))
      (delete-file path))))

;; Test 12: config-subsection
(test "config-subsection extracts nested alist"
  (lambda ()
    (let ([cfg (make-config
                 `((database . ((host . "db.local") (port . 5432)))
                   (app-name . "myapp")))])
      (let ([db-cfg (config-subsection cfg 'database)])
        (assert-true (config? db-cfg) "subsection is a config")
        (assert-equal (config-ref db-cfg 'host) "db.local" "nested host")
        (assert-equal (config-ref db-cfg 'port) 5432 "nested port")))))

;; Test 13: config-subsection with parent
(test "config-subsection with parent"
  (lambda ()
    (let* ([defaults (make-config '((timeout . 30)))]
           [cfg (make-config
                   `((database . ((host . "db.local")))))]
           [db-cfg (config-subsection cfg 'database defaults)])
      (assert-equal (config-ref db-cfg 'host) "db.local" "from subsection")
      (assert-equal (config-ref db-cfg 'timeout) 30 "from parent"))))

;; Test 14: config-verify valid config
(test "config-verify valid config returns empty"
  (lambda ()
    (let ([cfg (make-config '((port . 8080) (host . "localhost")))]
          [schema (list (cons 'port number?) (cons 'host string?))])
      (assert-equal (config-verify schema cfg) '() "no errors"))))

;; Test 15: config-verify missing key
(test "config-verify detects missing key"
  (lambda ()
    (let ([cfg (make-config '((port . 8080)))]
          [schema (list (cons 'port number?) (cons 'host string?))])
      (let ([errors (config-verify schema cfg)])
        (assert-equal (length errors) 1 "one error")
        (assert-true (string? (car errors)) "error is a string")))))

;; Test 16: config-verify wrong type
(test "config-verify detects wrong type"
  (lambda ()
    (let ([cfg (make-config '((port . "not-a-number") (host . "ok")))]
          [schema (list (cons 'port number?) (cons 'host string?))])
      (let ([errors (config-verify schema cfg)])
        (assert-equal (length errors) 1 "one error")))))

;; Test 17: config-verify checks parent values
(test "config-verify finds values in parent"
  (lambda ()
    (let* ([parent (make-config '((host . "parenthost")))]
           [child (make-config '((port . 80)) parent)]
           [schema (list (cons 'port number?) (cons 'host string?))])
      (assert-equal (config-verify schema child) '() "no errors"))))

;; Test 18: config->alist
(test "config->alist flattens with parent"
  (lambda ()
    (let* ([parent (make-config '((a . 1) (b . 2)))]
           [child (make-config '((b . 20) (c . 3)) parent)]
           [flat (config->alist child)])
      (assert-equal (cdr (assq 'a flat)) 1 "parent key")
      (assert-equal (cdr (assq 'b flat)) 20 "child overrides parent")
      (assert-equal (cdr (assq 'c flat)) 3 "child key")
      (assert-equal (length flat) 3 "no duplicates"))))

;; Test 19: with-config and current-config
(test "with-config sets current-config"
  (lambda ()
    (let ([cfg (make-config '((x . 42)))])
      (assert-equal (current-config) #f "initially #f")
      (with-config cfg
        (assert-true (config? (current-config)) "is a config inside")
        (assert-equal (config-ref (current-config) 'x) 42 "can read from it"))
      (assert-equal (current-config) #f "restored after"))))

;; Test 20: with-config nesting
(test "with-config nesting"
  (lambda ()
    (let ([outer (make-config '((env . "prod")))]
          [inner (make-config '((env . "test")))])
      (with-config outer
        (assert-equal (config-ref (current-config) 'env) "prod" "outer")
        (with-config inner
          (assert-equal (config-ref (current-config) 'env) "test" "inner"))
        (assert-equal (config-ref (current-config) 'env) "prod" "restored")))))

;; Test 21: empty config
(test "empty config"
  (lambda ()
    (let ([cfg (make-config '())])
      (assert-true (config? cfg) "is a config")
      (assert-equal (config-keys cfg) '() "no keys")
      (assert-equal (config->alist cfg) '() "empty alist")
      (assert-equal (config-ref/default cfg 'x 99) 99 "default for missing"))))

;; Test 22: three-level cascading
(test "three-level cascading"
  (lambda ()
    (let* ([grandparent (make-config '((a . 1) (b . 2) (c . 3)))]
           [parent (make-config '((b . 20)) grandparent)]
           [child (make-config '((c . 300)) parent)])
      (assert-equal (config-ref child 'a) 1 "from grandparent")
      (assert-equal (config-ref child 'b) 20 "from parent")
      (assert-equal (config-ref child 'c) 300 "from child"))))

;; Test 23: config-merge with parents
(test "config-merge flattens both sides"
  (lambda ()
    (let* ([p1 (make-config '((a . 1)))]
           [c1 (make-config '((b . 2)) p1)]
           [p2 (make-config '((c . 3)))]
           [c2 (make-config '((a . 10)) p2)]
           [merged (config-merge c1 c2)])
      (assert-equal (config-ref merged 'a) 10 "overridden by second")
      (assert-equal (config-ref merged 'b) 2 "from first")
      (assert-equal (config-ref merged 'c) 3 "from second's parent"))))

;; Test 24: config-verify multiple errors
(test "config-verify multiple errors"
  (lambda ()
    (let ([cfg (make-config '((port . "bad") (host . 123)))]
          [schema (list (cons 'port number?)
                        (cons 'host string?)
                        (cons 'missing symbol?))])
      (let ([errors (config-verify schema cfg)])
        (assert-equal (length errors) 3 "three errors")))))

(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
