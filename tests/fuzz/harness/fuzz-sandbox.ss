#!/usr/bin/env scheme-script
#!chezscheme
;;; fuzz-sandbox.ss -- Fuzzer for std/security/restrict
;;;
;;; Targets: restricted-eval, restricted-eval-string
;;; Bug classes: sandbox escape, capability leak
;;; Oracle: any result that indicates access beyond the safe binding set

(import (chezscheme)
        (std security restrict)
        (std test fuzz))

;;; ========== Escape attempt corpus ==========

(define escape-attempts
  '(;; Direct file access
    (open-input-file "/etc/passwd")
    (open-output-file "/tmp/pwned")
    ;; Shell/system
    (system "id")
    (process "id")
    ;; Continuation capture
    (call/cc (lambda (k) k))
    (call-with-current-continuation (lambda (k) k))
    ;; Environment access
    (interaction-environment)
    (scheme-environment)
    (top-level-value 'system)
    ;; Eval bootstrapping
    (eval '(system "id"))
    (eval '(open-input-file "/etc/passwd") (interaction-environment))
    ;; Compile
    (compile '(system "id"))
    ;; Foreign procedure (FFI)
    (foreign-procedure "system" (string) int)
    ;; Load
    (load "malicious.ss")
    ;; Macro that references blocked bindings
    (let-syntax ([escape (syntax-rules ()
                           [(_) (open-input-file "/etc/passwd")])])
      (escape))
    ;; Record type descriptor access
    (record-type-descriptor &condition)
    ;; Parameter mutation
    (parameterize ([current-directory "/"])
      (current-directory))
    ;; Exception handler manipulation
    (with-exception-handler
      (lambda (x) (open-input-file "/etc/passwd"))
      (lambda () (error 'x "y")))
    ;; Dynamic-wind abuse
    (dynamic-wind
      (lambda () (void))
      (lambda () 42)
      (lambda () (void)))
    ;; Syntax-case
    (define-syntax sneaky
      (lambda (x)
        (syntax-case x ()
          [(_) #'(system "id")])))
    ))

;;; ========== Generators ==========

(define (gen-escape-expr)
  (case (random 6)
    [(0) ;; known escape attempt
     (random-element escape-attempts)]
    [(1) ;; arithmetic (should work)
     `(+ ,(random 100) ,(random 100))]
    [(2) ;; string ops (should work)
     `(string-append "hello" " " "world")]
    [(3) ;; list ops (should work)
     `(map add1 '(1 2 3))]
    [(4) ;; nested eval
     `(eval '(+ 1 2))]
    [(5) ;; complex expression mixing safe and unsafe
     `(let ([x (+ 1 2)])
        (if (= x 3)
          (string-append "ok" "")
          (error 'test "bad")))]))

;;; ========== Escape oracle ==========

(define escape-count 0)

(define (check-escape input result)
  ;; Check for signs of sandbox escape
  (when (and result (not (condition? result)))
    (cond
      ;; Got a port — definite escape
      [(port? result)
       (set! escape-count (+ escape-count 1))
       (fprintf (current-error-port)
                "[fuzz] SANDBOX ESCAPE (port): ~s -> ~s~n" input result)]
      ;; Got an environment — can eval anything
      [(environment? result)
       (set! escape-count (+ escape-count 1))
       (fprintf (current-error-port)
                "[fuzz] SANDBOX ESCAPE (environment): ~s -> ~s~n" input result)])))

;;; ========== Run ==========

(define sandbox-env (make-restricted-environment))

(define sandbox-stats
  (fuzz-run "sandbox"
    (lambda (input)
      (let ([result
             (guard (exn [#t 'exception])
               (restricted-eval input sandbox-env))])
        (check-escape input result)))
    gen-escape-expr))

;; Also fuzz restricted-eval-string
(define sandbox-string-stats
  (fuzz-run "sandbox-string"
    (lambda (input)
      (guard (exn [#t (void)])
        (restricted-eval-string input)))
    (lambda ()
      (case (random 3)
        [(0) (format "~s" (gen-escape-expr))]
        [(1) (random-ascii-string (+ 1 (random 100)))]
        [(2) "(+ 1 2)"]))
    (quotient (fuzz-iterations) 2)))

(when (> escape-count 0)
  (fprintf (current-error-port)
           "[fuzz] *** ~a SANDBOX ESCAPES DETECTED ***~n" escape-count)
  (exit 1))
