#!chezscheme
;;; Tests for (std os antidebug), (std os seccomp), (std os integrity)
;;;
;;; NOTE: Some operations are irreversible (ptrace, seccomp) and cannot
;;; be safely tested in the main process. Those are documented but skipped.

(import (chezscheme)
        (std os antidebug)
        (std os seccomp)
        (std os integrity))

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

(printf "--- Binary Hardening Tests ---~%~%")

;; ========== Antidebug ==========

(printf "-- Antidebug (non-destructive checks) --~%")

(test "antidebug-traced? returns #f when not debugged"
  (antidebug-traced?)
  #f)

(test "antidebug-ld-preload? returns #f in clean env"
  (antidebug-ld-preload?)
  #f)

(test "antidebug-timing-anomaly? returns #f with generous threshold"
  (antidebug-timing-anomaly? 1000000000)  ; 1 second — very generous
  #f)

(test "antidebug-check-all returns clean alist"
  (let ([result (antidebug-check-all)])
    (and (list? result)
         (= 3 (length result))
         (assq 'traced result)
         (assq 'ld-preload result)
         (assq 'timing result)
         ;; All should be #f in normal test environment
         (not (cdr (assq 'traced result)))
         (not (cdr (assq 'ld-preload result)))
         ;; timing uses 50ms internal threshold — should be fine
         (not (cdr (assq 'timing result)))))
  #t)

;; Skip: antidebug-ptrace! is irreversible (one-shot self-trace)
;; Skip: antidebug-breakpoint? needs a valid code address (architecture-specific)

;; ========== Seccomp ==========

(printf "~%-- Seccomp --~%")

(test "seccomp-available? returns boolean"
  (boolean? (seccomp-available?))
  #t)

(test "seccomp-available? is true on modern Linux"
  (seccomp-available?)
  #t)

;; Skip: seccomp-lock! is irreversible — would kill test process on blocked syscalls
;; Skip: seccomp-lock-strict! is irreversible

;; ========== Integrity ==========

(printf "~%-- Integrity: self-hashing --~%")

(test "integrity-hash-self returns 32-byte bytevector"
  (let ([h (integrity-hash-self)])
    (and (bytevector? h) (= 32 (bytevector-length h))))
  #t)

(test "integrity-hash-self is deterministic"
  (let ([h1 (integrity-hash-self)]
        [h2 (integrity-hash-self)])
    (bytevector=? h1 h2))
  #t)

(test "integrity-verify-hash succeeds with correct hash"
  (let ([h (integrity-hash-self)])
    (integrity-verify-hash h))
  #t)

(test "integrity-verify-hash fails with wrong hash"
  (let ([bad (make-bytevector 32 0)])
    (integrity-verify-hash bad))
  #f)

(test "integrity-verify-hash rejects non-32-byte input"
  (guard (exn [(integrity-error? exn) #t] [#t #f])
    (integrity-verify-hash (make-bytevector 16 0)))
  #t)

(printf "~%-- Integrity: file hashing --~%")

;; Create a temp file with known content for testing
(define test-file "/tmp/jerboa-harden-test.dat")
(let ([p (open-file-output-port test-file (file-options no-fail)
           (buffer-mode block) (native-transcoder))])
  (put-string p "hello, jerboa hardening!")
  (close-port p))

(test "integrity-hash-file returns 32-byte bytevector"
  (let ([h (integrity-hash-file test-file)])
    (and (bytevector? h) (= 32 (bytevector-length h))))
  #t)

(test "integrity-hash-file is deterministic"
  (let ([h1 (integrity-hash-file test-file)]
        [h2 (integrity-hash-file test-file)])
    (bytevector=? h1 h2))
  #t)

(test "integrity-hash-region with offset=0 length=0 matches full hash"
  (let ([full (integrity-hash-file test-file)]
        [region (integrity-hash-region test-file 0 0)])
    (bytevector=? full region))
  #t)

(test "integrity-hash-region with partial length differs from full"
  (let ([full (integrity-hash-file test-file)]
        [partial (integrity-hash-region test-file 0 5)])
    (not (bytevector=? full partial)))
  #t)

(test "integrity-hash-file raises on nonexistent file"
  (guard (exn [(integrity-error? exn) #t] [#t #f])
    (integrity-hash-file "/nonexistent/path/to/file"))
  #t)

;; Clean up temp file
(delete-file test-file)

;; ========== Integrity: signature verification ==========

(printf "~%-- Integrity: signature verification --~%")

;; We can't test a real valid signature without a signing tool,
;; but we can test that invalid signatures are rejected.

(test "integrity-verify-signature rejects bad pubkey size"
  (guard (exn [(integrity-error? exn) #t] [#t #f])
    (integrity-verify-signature
      (make-bytevector 16 0)   ; wrong size
      (make-bytevector 64 0)
      0 0))
  #t)

(test "integrity-verify-signature rejects bad signature size"
  (guard (exn [(integrity-error? exn) #t] [#t #f])
    (integrity-verify-signature
      (make-bytevector 32 0)
      (make-bytevector 32 0)   ; wrong size
      0 0))
  #t)

(test "integrity-verify-signature returns #f for forged signature"
  (integrity-verify-signature
    (make-bytevector 32 1)    ; fake pubkey
    (make-bytevector 64 2)    ; fake signature
    0 0)
  #f)

;; ========== Summary ==========

(printf "~%Hardening tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
