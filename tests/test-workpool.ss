;;; Tests for Phase 3: Blocking work offload
;;; Tests workpool, DNS resolver, and file I/O pool.

(import (chezscheme))
(import (std fiber))
(import (std net workpool))
(import (std net resolve))
(import (std io filepool))

(define test-count 0)
(define pass-count 0)

(define-syntax test
  (syntax-rules ()
    [(_ name body ...)
     (begin
       (set! test-count (+ test-count 1))
       (guard (exn [#t
         (display "FAIL: ") (display name) (newline)
         (display "  Error: ")
         (display (if (message-condition? exn) (condition-message exn) exn))
         (newline)])
         body ...
         (set! pass-count (+ pass-count 1))
         (display "PASS: ") (display name) (newline)))]))

(define-syntax assert-equal
  (syntax-rules ()
    [(_ got expected msg)
     (unless (equal? got expected)
       (error 'assert msg (list 'got: got 'expected: expected)))]))

(define-syntax assert-true
  (syntax-rules ()
    [(_ val msg)
     (unless val (error 'assert msg))]))

;; =========================================================================
;; Test 1: Work pool — basic submit
;; =========================================================================

(test "workpool: basic submit and result"
  (let ([rt (make-fiber-runtime 2)]
        [pool (make-work-pool 2)]
        [result-box (box #f)])
    (work-pool-start! pool)
    (fiber-spawn rt
      (lambda ()
        (let ([r (work-pool-submit! pool (lambda () (* 6 7)))])
          (set-box! result-box r)))
      "compute-fiber")
    (fiber-runtime-run! rt)
    (work-pool-stop! pool)
    (assert-equal (unbox result-box) 42 "6 * 7 = 42")))

;; =========================================================================
;; Test 2: Work pool — error propagation
;; =========================================================================

(test "workpool: error propagation"
  (let ([rt (make-fiber-runtime 2)]
        [pool (make-work-pool 2)]
        [caught (box #f)])
    (work-pool-start! pool)
    (fiber-spawn rt
      (lambda ()
        (guard (exn [#t (set-box! caught #t)])
          (work-pool-submit! pool (lambda () (error 'test "boom")))))
      "error-fiber")
    (fiber-runtime-run! rt)
    (work-pool-stop! pool)
    (assert-true (unbox caught) "exception propagated to fiber")))

;; =========================================================================
;; Test 3: Work pool — concurrent submissions
;; =========================================================================

(test "workpool: 20 concurrent submissions"
  (let ([rt (make-fiber-runtime 4)]
        [pool (make-work-pool 4)]
        [results (make-vector 20 #f)])
    (work-pool-start! pool)
    (do ([i 0 (+ i 1)])
      ((= i 20))
      (let ([idx i])
        (fiber-spawn rt
          (lambda ()
            (let ([r (work-pool-submit! pool (lambda () (* idx idx)))])
              (vector-set! results idx r)))
          (string-append "fib-" (number->string idx)))))
    (fiber-runtime-run! rt)
    (work-pool-stop! pool)
    ;; Verify all results
    (do ([i 0 (+ i 1)])
      ((= i 20))
      (assert-equal (vector-ref results i) (* i i)
        (string-append "result " (number->string i))))))

;; =========================================================================
;; Test 4: DNS resolver — resolve localhost
;; =========================================================================

(test "dns: resolve localhost"
  (let ([rt (make-fiber-runtime 2)]
        [result-box (box #f)])
    (with-dns-resolver resolver
      (fiber-spawn rt
        (lambda ()
          (let ([addr (fiber-resolve "localhost" resolver)])
            (set-box! result-box addr)))
        "dns-fiber")
      (fiber-runtime-run! rt))
    (assert-equal (unbox result-box) "127.0.0.1" "localhost → 127.0.0.1")))

;; =========================================================================
;; Test 5: DNS resolver — resolve real hostname
;; =========================================================================

(test "dns: resolve dns.google"
  (let ([rt (make-fiber-runtime 2)]
        [result-box (box #f)])
    (with-dns-resolver resolver
      (fiber-spawn rt
        (lambda ()
          (let ([addr (fiber-resolve "dns.google" resolver)])
            (set-box! result-box addr)))
        "dns-fiber")
      (fiber-runtime-run! rt))
    ;; dns.google resolves to 8.8.8.8 or 8.8.4.4
    (let ([addr (unbox result-box)])
      (assert-true (or (string=? addr "8.8.8.8") (string=? addr "8.8.4.4"))
        (string-append "dns.google → " addr)))))

;; =========================================================================
;; Test 6: DNS resolver — concurrent resolutions
;; =========================================================================

(test "dns: 5 concurrent resolutions"
  (let ([rt (make-fiber-runtime 4)]
        [results (make-vector 5 #f)]
        [hosts '#("localhost" "localhost" "localhost" "localhost" "localhost")])
    (with-dns-resolver resolver
      (do ([i 0 (+ i 1)])
        ((= i 5))
        (let ([idx i])
          (fiber-spawn rt
            (lambda ()
              (let ([addr (fiber-resolve (vector-ref hosts idx) resolver)])
                (vector-set! results idx addr)))
            (string-append "dns-" (number->string idx)))))
      (fiber-runtime-run! rt))
    ;; All should resolve to 127.0.0.1
    (do ([i 0 (+ i 1)])
      ((= i 5))
      (assert-equal (vector-ref results i) "127.0.0.1"
        (string-append "host " (number->string i))))))

;; =========================================================================
;; Test 7: File pool — write and read
;; =========================================================================

(test "filepool: write and read back"
  (let ([rt (make-fiber-runtime 2)]
        [result-box (box #f)]
        [path "/tmp/jerboa-test-filepool.txt"])
    (with-file-pool fpool
      (fiber-spawn rt
        (lambda ()
          (fiber-write-file path "hello from fiber!" fpool)
          (let ([content (fiber-read-file path fpool)])
            (set-box! result-box content)))
        "file-fiber")
      (fiber-runtime-run! rt))
    (assert-equal (unbox result-box) "hello from fiber!" "read back matches")
    ;; Cleanup
    (delete-file path)))

;; =========================================================================
;; Test 8: File pool — binary read/write
;; =========================================================================

(test "filepool: binary read/write"
  (let ([rt (make-fiber-runtime 2)]
        [result-box (box #f)]
        [path "/tmp/jerboa-test-filepool-bin.dat"]
        [data (make-bytevector 256)])
    ;; Fill with test pattern
    (do ([i 0 (+ i 1)]) ((= i 256))
      (bytevector-u8-set! data i (mod i 256)))
    (with-file-pool fpool
      (fiber-spawn rt
        (lambda ()
          (fiber-write-file-bytes path data fpool)
          (let ([content (fiber-read-file-bytes path fpool)])
            (set-box! result-box content)))
        "bin-fiber")
      (fiber-runtime-run! rt))
    (assert-equal (unbox result-box) data "binary round-trip")
    (delete-file path)))

;; =========================================================================
;; Test 9: File pool — append
;; =========================================================================

(test "filepool: append"
  (let ([rt (make-fiber-runtime 2)]
        [result-box (box #f)]
        [path "/tmp/jerboa-test-filepool-append.txt"])
    (with-file-pool fpool
      (fiber-spawn rt
        (lambda ()
          (fiber-write-file path "line1\n" fpool)
          (fiber-append-file path "line2\n" fpool)
          (let ([content (fiber-read-file path fpool)])
            (set-box! result-box content)))
        "append-fiber")
      (fiber-runtime-run! rt))
    (assert-equal (unbox result-box) "line1\nline2\n" "append worked")
    (delete-file path)))

;; =========================================================================
;; Test 10: File pool — file-exists?
;; =========================================================================

(test "filepool: file-exists?"
  (let ([rt (make-fiber-runtime 2)]
        [exists-box (box #f)]
        [not-exists-box (box #t)])
    (with-file-pool fpool
      (fiber-spawn rt
        (lambda ()
          (set-box! exists-box (fiber-file-exists? "/tmp" fpool))
          (set-box! not-exists-box
            (fiber-file-exists? "/tmp/no-such-file-jerboa-test-xxx" fpool)))
        "exists-fiber")
      (fiber-runtime-run! rt))
    (assert-true (unbox exists-box) "/tmp exists")
    (assert-true (not (unbox not-exists-box)) "nonexistent file")))

;; =========================================================================
;; Test 11: File pool — concurrent file operations
;; =========================================================================

(test "filepool: 10 concurrent reads/writes"
  (let ([rt (make-fiber-runtime 4)]
        [results (make-vector 10 #f)])
    (with-file-pool fpool
      (do ([i 0 (+ i 1)])
        ((= i 10))
        (let ([idx i]
              [path (string-append "/tmp/jerboa-test-concurrent-" (number->string i) ".txt")])
          (fiber-spawn rt
            (lambda ()
              (let ([msg (string-append "fiber-" (number->string idx))])
                (fiber-write-file path msg fpool)
                (let ([content (fiber-read-file path fpool)])
                  (vector-set! results idx (string=? content msg)))))
            (string-append "file-" (number->string idx)))))
      (fiber-runtime-run! rt))
    ;; Verify and clean up
    (do ([i 0 (+ i 1)])
      ((= i 10))
      (assert-true (vector-ref results i)
        (string-append "file " (number->string i)))
      (delete-file (string-append "/tmp/jerboa-test-concurrent-" (number->string i) ".txt")))))

;; =========================================================================
;; Summary
;; =========================================================================
(newline)
(display "=========================================") (newline)
(display "Results: ") (display pass-count) (display "/")
(display test-count) (display " passed") (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
