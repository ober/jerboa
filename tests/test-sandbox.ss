#!chezscheme
;;; Tests for (std security sandbox) — run-safe entry point

(import (chezscheme)
        (std security sandbox)
        (std security landlock)
        (std security seccomp)
        (std security capability)
        (std error conditions))

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

;; Helper for string-contains (not in R6RS)
(define (string-contains haystack needle)
  (let ([hlen (string-length haystack)]
        [nlen (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nlen) hlen) #f]
        [(string=? (substring haystack i (+ i nlen)) needle) #t]
        [else (loop (+ i 1))]))))

;; Config that disables kernel features (for CI / non-root testing)
(define no-kernel-config
  (make-sandbox-config 'timeout 5 'seccomp #f 'landlock #f))

(printf "--- Sandbox Tests ---~%~%")

;; ========== Parameters ==========

(printf "-- Parameters --~%")

(test "*sandbox-timeout* defaults to 30"
  (*sandbox-timeout*)
  30)

(test "*sandbox-seccomp* defaults to compute-only"
  (*sandbox-seccomp*)
  'compute-only)

(test "*sandbox-landlock* defaults to #f"
  (*sandbox-landlock*)
  #f)

;; ========== Condition type ==========

(printf "~%-- Condition type --~%")

(test "sandbox-error? works"
  (sandbox-error? (make-sandbox-error "sandbox" 'eval "test"))
  #t)

(test "sandbox-error-phase"
  (sandbox-error-phase (make-sandbox-error "sandbox" 'timeout "timed out"))
  'timeout)

(test "sandbox-error-detail"
  (sandbox-error-detail (make-sandbox-error "sandbox" 'eval "bad code"))
  "bad code")

(test "sandbox-error is a jerboa condition"
  (jerboa-condition? (make-sandbox-error "sandbox" 'eval "test"))
  #t)

;; ========== sandbox-config ==========

(printf "~%-- sandbox-config --~%")

(test "make-sandbox-config creates config"
  (sandbox-config? (make-sandbox-config))
  #t)

(test "make-sandbox-config with timeout"
  (sandbox-config-timeout (make-sandbox-config 'timeout 10))
  10)

(test "make-sandbox-config with seccomp #f"
  (sandbox-config-seccomp (make-sandbox-config 'seccomp #f))
  #f)

(test "make-sandbox-config with multiple keys"
  (let ([cfg (make-sandbox-config 'timeout 5 'seccomp #f 'landlock #f)])
    (and (= (sandbox-config-timeout cfg) 5)
         (not (sandbox-config-seccomp cfg))
         (not (sandbox-config-landlock cfg))))
  #t)

(test "make-sandbox-config uses parameter defaults"
  (parameterize ([*sandbox-timeout* 99])
    (sandbox-config-timeout (make-sandbox-config)))
  99)

(test "make-sandbox-config rejects unknown key"
  (guard (exn [#t #t])
    (make-sandbox-config 'bogus 42)
    #f)
  #t)

;; ========== run-safe: basic execution ==========

(printf "~%-- run-safe basic --~%")

(test "run-safe returns thunk result"
  (run-safe (lambda () (+ 21 21)) no-kernel-config)
  42)

(test "run-safe with string result"
  (run-safe (lambda () (string-append "hello" " " "world")) no-kernel-config)
  "hello world")

(test "run-safe with list result"
  (run-safe (lambda () (map (lambda (x) (* x x)) '(1 2 3 4))) no-kernel-config)
  '(1 4 9 16))

(test "run-safe with boolean result"
  (run-safe (lambda () (< 1 2)) no-kernel-config)
  #t)

(test "run-safe with nested data"
  (run-safe (lambda () '((a . 1) (b . 2) (c . 3))) no-kernel-config)
  '((a . 1) (b . 2) (c . 3)))

;; ========== run-safe: timeout ==========

(printf "~%-- run-safe timeout --~%")

(test "run-safe times out on infinite loop"
  (guard (exn
           [(sandbox-error? exn)
            ;; Timeout errors arrive as phase 'eval with detail containing "timeout"
            (let ([detail (sandbox-error-detail exn)])
              (and (string? detail)
                   (or (string-contains detail "timeout")
                       (string-contains detail "exceeded"))))]
           [#t #f])
    (run-safe (lambda () (let loop () (loop)))
      (make-sandbox-config 'timeout 1 'seccomp #f 'landlock #f))
    #f)
  #t)


;; ========== run-safe: error propagation ==========

(printf "~%-- run-safe errors --~%")

(test "run-safe propagates thunk errors as sandbox-error"
  (guard (exn
           [(sandbox-error? exn)
            (eq? (sandbox-error-phase exn) 'eval)]
           [#t #f])
    (run-safe (lambda () (error 'test "intentional error")) no-kernel-config)
    #f)
  #t)

;; ========== run-safe-eval: string evaluation ==========

(printf "~%-- run-safe-eval --~%")

(test "run-safe-eval basic arithmetic"
  (run-safe-eval "(+ 1 2 3)" no-kernel-config)
  6)

(test "run-safe-eval list operations"
  (run-safe-eval "(map (lambda (x) (* x x)) '(1 2 3))" no-kernel-config)
  '(1 4 9))

(test "run-safe-eval string operations"
  (run-safe-eval "(string-append \"foo\" \"bar\")" no-kernel-config)
  "foobar")

(test "run-safe-eval rejects dangerous operations"
  (guard (exn
           [(sandbox-error? exn) #t]
           [#t #t])  ;; any error = restricted env blocks it
    (run-safe-eval "(system \"echo pwned\")" no-kernel-config)
    #f)
  #t)

(test "run-safe-eval times out"
  (guard (exn
           [(sandbox-error? exn)
            (let ([detail (sandbox-error-detail exn)])
              (and (string? detail)
                   (or (string-contains detail "timeout")
                       (string-contains detail "exceeded"))))]
           [#t #f])
    (run-safe-eval "(let loop () (loop))"
      (make-sandbox-config 'timeout 1 'seccomp #f 'landlock #f))
    #f)
  #t)

;; ========== run-safe: default parameters ==========

(printf "~%-- Default parameters --~%")

(test "run-safe uses parameter defaults when no config given"
  (parameterize ([*sandbox-timeout* 5]
                 [*sandbox-seccomp* #f]
                 [*sandbox-landlock* #f])
    (run-safe (lambda () 99)))
  99)

;; ========== Summary ==========

(printf "~%Sandbox tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
