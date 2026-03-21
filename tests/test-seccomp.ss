#!chezscheme
;;; Tests for (std security seccomp) — real seccomp-BPF implementation
;;; NOTE: Actual filter installation is IRREVERSIBLE and restricts the process.
;;; We test construction and BPF generation, not installation.

(import (chezscheme)
        (std security seccomp))

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

(printf "--- Seccomp BPF Tests ---~%~%")

;; ========== Filter construction ==========

(printf "-- Filter construction --~%")

(test "make-seccomp-filter creates filter"
  (seccomp-filter? (make-seccomp-filter seccomp-kill 'read 'write))
  #t)

(test "filter default action"
  (seccomp-filter-default-action (make-seccomp-filter seccomp-kill 'read))
  seccomp-kill)

(test "filter allowed syscalls"
  (seccomp-filter-allowed-syscalls (make-seccomp-filter seccomp-kill 'read 'write))
  '(read write))

(test "seccomp-errno creates action"
  (> (seccomp-errno 1) 0)
  #t)

;; ========== Pre-built filters ==========

(printf "~%-- Pre-built filters --~%")

(test "compute-only-filter is a filter"
  (seccomp-filter? compute-only-filter)
  #t)

(test "network-server-filter is a filter"
  (seccomp-filter? network-server-filter)
  #t)

(test "io-only-filter is a filter"
  (seccomp-filter? io-only-filter)
  #t)

(test "compute-only-filter has reasonable syscall count"
  (> (length (seccomp-filter-allowed-syscalls compute-only-filter)) 10)
  #t)

(test "network-server-filter has more syscalls than compute-only"
  (> (length (seccomp-filter-allowed-syscalls network-server-filter))
     (length (seccomp-filter-allowed-syscalls compute-only-filter)))
  #t)

;; ========== Availability ==========

(printf "~%-- Availability --~%")

(test "seccomp-available? returns boolean"
  (boolean? (seccomp-available?))
  #t)

;; ========== Error handling ==========

(printf "~%-- Error handling --~%")

(test "install! rejects non-filter"
  (guard (exn [(message-condition? exn) #t] [#t #f])
    (seccomp-install! 42)
    #f)
  #t)

(test "unknown syscall name raises error on install"
  (guard (exn [(message-condition? exn) #t]
              [#t #f])
    ;; Construction doesn't validate — installation does
    (seccomp-install! (make-seccomp-filter seccomp-kill 'nonexistent-syscall-xyz))
    #f)
  #t)

;; ========== Summary ==========

(printf "~%Seccomp tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
