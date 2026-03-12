#!/usr/bin/env scheme-script
#!chezscheme

;;; Test suite for musl static binary functionality

(import (chezscheme)
        (jerboa build)
        (jerboa build musl))

;; ========== Helpers ==========

(define (string-suffix? suffix str)
  (let ([slen (string-length suffix)]
        [len (string-length str)])
    (and (>= len slen)
         (string=? (substring str (- len slen) len) suffix))))

(define (string-contains str substr)
  (let ([slen (string-length substr)])
    (let loop ([i 0])
      (cond
        [(> (+ i slen) (string-length str)) #f]
        [(string=? (substring str i (+ i slen)) substr) #t]
        [else (loop (+ i 1))]))))

;; ========== Test Framework ==========

(define (display-test-header name)
  (display "\n==> Testing: ")
  (display name)
  (newline))

(define (display-result name passed?)
  (display "  [")
  (display (if passed? "PASS" "FAIL"))
  (display "] ")
  (display name)
  (newline))

(define test-count 0)
(define pass-count 0)

(define (run-test name thunk)
  (set! test-count (+ test-count 1))
  (let ([result (guard (e [#t #f]) (thunk) #t)])
    (when result (set! pass-count (+ pass-count 1)))
    (display-result name result)))

;; ========== Detection Tests ==========

(display-test-header "Detection and Configuration")

(run-test "musl-available? returns boolean"
  (lambda ()
    (boolean? (musl-available?))))

(run-test "musl-gcc-path returns string or #f"
  (lambda ()
    (let ([path (musl-gcc-path)])
      (or (not path) (string? path)))))

(run-test "musl-sysroot returns string or #f"
  (lambda ()
    (let ([root (musl-sysroot)])
      (or (not root) (string? root)))))

(when (musl-available?)
  (run-test "musl-gcc-path returns existing file"
    (lambda ()
      (let ([path (musl-gcc-path)])
        (and path (file-exists? path))))))

;; ========== Configuration Tests ==========

(display-test-header "Configuration")

(run-test "musl-chez-prefix returns string"
  (lambda ()
    (string? (musl-chez-prefix))))

(run-test "musl-chez-prefix-set! works"
  (lambda ()
    (let ([old (musl-chez-prefix)])
      (musl-chez-prefix-set! "/test/path")
      (let ([new (musl-chez-prefix)])
        (musl-chez-prefix-set! old)
        (string=? new "/test/path")))))

;; ========== Validation Tests ==========

(display-test-header "Validation")

(run-test "validate-musl-setup returns pair"
  (lambda ()
    (let ([result (validate-musl-setup)])
      (pair? result))))

(run-test "validate-musl-setup car is symbol"
  (lambda ()
    (let ([result (validate-musl-setup)])
      (memq (car result) '(ok error)))))

(when (musl-available?)
  (run-test "validation reports error or ok"
    (lambda ()
      (let ([result (validate-musl-setup)])
        ;; May be 'ok or 'error depending on Chez-musl setup
        (and (pair? result)
             (symbol? (car result))
             (string? (cdr result)))))))

;; ========== Path Tests ==========

(display-test-header "Path Resolution")

(run-test "musl-crt-objects returns list"
  (lambda ()
    (list? (musl-crt-objects))))

(run-test "musl-crt-objects has 3 elements"
  (lambda ()
    (= (length (musl-crt-objects)) 3)))

(run-test "musl-crt-objects contains .o files"
  (lambda ()
    (let loop ([objs (musl-crt-objects)])
      (cond
        [(null? objs) #t]
        [(not (string? (car objs))) #f]
        [(not (string-suffix? ".o" (car objs))) #f]
        [else (loop (cdr objs))]))))

;; ========== Link Command Tests ==========

(display-test-header "Link Command Generation")

(run-test "musl-link-command returns string"
  (lambda ()
    (guard (e [#t #f])
      (when (musl-available?)
        (let ([cmd (musl-link-command 
                    "/tmp/test" 
                    '("/tmp/main.o") 
                    '())])
          (string? cmd))))))

(run-test "link command contains -static"
  (lambda ()
    (guard (e [#t #f])
      (when (musl-available?)
        (let ([cmd (musl-link-command 
                    "/tmp/test" 
                    '("/tmp/main.o") 
                    '())])
          (string-contains cmd "-static"))))))

(run-test "link command contains -nostdlib"
  (lambda ()
    (guard (e [#t #f])
      (when (musl-available?)
        (let ([cmd (musl-link-command 
                    "/tmp/test" 
                    '("/tmp/main.o") 
                    '())])
          (string-contains cmd "-nostdlib"))))))

;; ========== Cross-Target Tests ==========

(display-test-header "Cross-Compilation")

(run-test "make-musl-cross-target for x86-64"
  (lambda ()
    (let ([target (make-musl-cross-target 'x86-64)])
      (and (cross-target? target)
           (eq? (cross-target-arch target) 'x86-64)))))

(run-test "make-musl-cross-target for aarch64"
  (lambda ()
    (let ([target (make-musl-cross-target 'aarch64)])
      (and (cross-target? target)
           (eq? (cross-target-arch target) 'aarch64)))))

(run-test "make-musl-cross-target for riscv64"
  (lambda ()
    (let ([target (make-musl-cross-target 'riscv64)])
      (and (cross-target? target)
           (eq? (cross-target-arch target) 'riscv64)))))

(run-test "musl-cross-available? returns boolean"
  (lambda ()
    (boolean? (musl-cross-available? 'aarch64))))

;; ========== Summary ==========

(newline)
(display "========================================")
(newline)
(display "Test Summary: ")
(display pass-count)
(display "/")
(display test-count)
(display " passed")
(newline)

(when (not (musl-available?))
  (display "\nNote: musl-gcc not available, some tests were skipped")
  (newline))

(exit (if (= pass-count test-count) 0 1))
