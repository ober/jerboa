#!chezscheme
;;; Tests for (jerboa cache) — compilation cache

(import (chezscheme) (jerboa cache))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn
              [#t (set! fail (+ fail 1))
                  (printf "FAIL ~a: exception ~a~%" name
                    (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1))
                  (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~a, expected ~a~%" name got expected)))))]))

(printf "--- (jerboa cache) tests ---~%")

;; Use a temp directory for testing
(parameterize ([cache-directory "/tmp/jerboa-cache-test"])

  ;; Clean up from previous runs
  (cache-clear!)

  ;; Test 1: Cache key generation
  (let ([test-file "/tmp/jerboa-cache-test-source.sls"])
    (call-with-output-file test-file
      (lambda (p) (display "(library (test) (export) (import (chezscheme)))" p))
      'replace)
    (let ([key (cache-key test-file '() 2)])
      (test "cache-key is string" (string? key) #t)
      (test "cache-key not empty" (> (string-length key) 0) #t)

      ;; Same input = same key
      (let ([key2 (cache-key test-file '() 2)])
        (test "cache-key deterministic" key key2))

      ;; Different opt-level = different key
      (let ([key3 (cache-key test-file '() 3)])
        (test "cache-key varies with opt" (not (string=? key key3)) #t)))

    (delete-file test-file))

  ;; Test 2: Cache lookup miss
  (test "cache-lookup miss" (cache-lookup "nonexistent-key") #f)

  ;; Test 3: Cache store and lookup
  (let ([test-so "/tmp/jerboa-cache-test.so"])
    (call-with-port (open-file-output-port test-so (file-options no-fail))
      (lambda (p) (put-bytevector p (string->bytevector "fake-so-data" (make-transcoder (utf-8-codec))))))
    (cache-store! "test-key-123" test-so)
    (let ([found (cache-lookup "test-key-123")])
      (test "cache-store+lookup" (string? found) #t)
      (test "cache-lookup file exists" (file-exists? found) #t))
    (delete-file test-so))

  ;; Test 4: Cache stats
  (let-values ([(count size) (cache-stats)])
    (test "cache-stats count" (>= count 1) #t)
    (test "cache-stats size" (> size 0) #t))

  ;; Test 5: Cache clear
  (cache-clear!)
  (let-values ([(count size) (cache-stats)])
    (test "cache-clear count" count 0))
  )

(printf "~%~a tests, ~a passed, ~a failed~%" (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
