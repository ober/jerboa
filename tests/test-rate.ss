#!chezscheme
;;; Tests for (std net rate) -- Rate limiting

(import (chezscheme) (std net rate))

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

(printf "--- Phase 3b: Rate Limiting ---~%~%")

;;; ======== Token Bucket ========

(test "token-bucket-type"
  (token-bucket? (make-token-bucket 10 1))
  #t)

(test "token-bucket-not-type"
  (token-bucket? "not a bucket")
  #f)

(test "token-bucket-initial-tokens"
  ;; Fresh bucket starts full
  (let ([tb (make-token-bucket 10 100)])
    (>= (token-bucket-tokens tb) 9.9))
  #t)

(test "token-bucket-try-success"
  (let ([tb (make-token-bucket 5 100)])
    (token-bucket-try! tb))
  #t)

(test "token-bucket-try-drains"
  ;; Drain a bucket with capacity 3
  (let ([tb (make-token-bucket 3 0.001)])
    (token-bucket-try! tb)
    (token-bucket-try! tb)
    (token-bucket-try! tb)
    ;; Now empty (rate is very slow)
    (token-bucket-try! tb))
  #f)

(test "token-bucket-consume-multi"
  (let ([tb (make-token-bucket 10 0.001)])
    (token-bucket-consume! tb 5))
  #t)

(test "token-bucket-consume-too-many"
  (let ([tb (make-token-bucket 3 0.001)])
    (token-bucket-consume! tb 10))
  #f)

(test "token-bucket-consume-exact"
  (let ([tb (make-token-bucket 5 0.001)])
    (token-bucket-consume! tb 5))
  #t)

(test "token-bucket-try-after-consume"
  ;; Drain fully then try
  (let ([tb (make-token-bucket 2 0.001)])
    (token-bucket-consume! tb 2)
    (token-bucket-try! tb))
  #f)

;;; ======== Sliding Window ========

(test "sliding-window-type"
  (sliding-window? (make-sliding-window 5 60))
  #t)

(test "sliding-window-not-type"
  (sliding-window? 42)
  #f)

(test "sliding-window-try-success"
  (let ([sw (make-sliding-window 3 60)])
    (sliding-window-try! sw))
  #t)

(test "sliding-window-count-increments"
  (let ([sw (make-sliding-window 10 60)])
    (sliding-window-try! sw)
    (sliding-window-try! sw)
    (sliding-window-count sw))
  2)

(test "sliding-window-try-at-limit"
  (let ([sw (make-sliding-window 3 60)])
    (sliding-window-try! sw)
    (sliding-window-try! sw)
    (sliding-window-try! sw)
    (sliding-window-try! sw))  ; 4th should fail
  #f)

(test "sliding-window-count-at-limit"
  (let ([sw (make-sliding-window 3 60)])
    (sliding-window-try! sw)
    (sliding-window-try! sw)
    (sliding-window-try! sw)
    (sliding-window-try! sw)  ; fails
    (sliding-window-count sw))
  3)

(test "sliding-window-fresh-count"
  (let ([sw (make-sliding-window 10 60)])
    (sliding-window-count sw))
  0)

;;; ======== Fixed Window ========

(test "fixed-window-type"
  (fixed-window? (make-fixed-window 5 60))
  #t)

(test "fixed-window-not-type"
  (fixed-window? '())
  #f)

(test "fixed-window-try-success"
  (let ([fw (make-fixed-window 5 3600)])
    (fixed-window-try! fw))
  #t)

(test "fixed-window-count-increments"
  (let ([fw (make-fixed-window 10 3600)])
    (fixed-window-try! fw)
    (fixed-window-try! fw)
    (fixed-window-count fw))
  2)

(test "fixed-window-try-at-limit"
  (let ([fw (make-fixed-window 2 3600)])
    (fixed-window-try! fw)
    (fixed-window-try! fw)
    (fixed-window-try! fw))  ; 3rd should fail
  #f)

(test "fixed-window-count-at-limit"
  (let ([fw (make-fixed-window 2 3600)])
    (fixed-window-try! fw)
    (fixed-window-try! fw)
    (fixed-window-try! fw)  ; fails
    (fixed-window-count fw))
  2)

(test "fixed-window-fresh-count"
  (let ([fw (make-fixed-window 10 3600)])
    (fixed-window-count fw))
  0)

;;; ======== Rate Limiter ========

(test "rate-limiter-type"
  (rate-limiter? (make-rate-limiter 10 100))
  #t)

(test "rate-limiter-not-type"
  (rate-limiter? #f)
  #f)

(test "rate-limiter-try-success"
  (let ([rl (make-rate-limiter 5 100)])
    (rate-limiter-try! rl))
  #t)

(test "rate-limiter-try-drains"
  (let ([rl (make-rate-limiter 2 0.001)])
    (rate-limiter-try! rl)
    (rate-limiter-try! rl)
    (rate-limiter-try! rl))  ; 3rd fails
  #f)

(test "rate-limiter-thread-safe"
  ;; Two threads both trying to consume from a 1-token bucket.
  ;; Use shared state to verify both ran without crashing.
  (let* ([rl      (make-rate-limiter 1 0.001)]
         [results (make-vector 2 'pending)]
         [t1      (fork-thread
                    (lambda ()
                      (vector-set! results 0 (rate-limiter-try! rl))))]
         [t2      (fork-thread
                    (lambda ()
                      (vector-set! results 1 (rate-limiter-try! rl))))])
    ;; Wait for threads to finish
    (sleep (make-time 'time-duration 100000000 0))
    ;; Both results should be booleans (not 'pending means they ran)
    (and (boolean? (vector-ref results 0))
         (boolean? (vector-ref results 1))))
  #t)

;;; Summary

(printf "~%Rate limiting tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
