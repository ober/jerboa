#!chezscheme
;;; Tests for (std actor engine) — Engine-based actor pool

(import (chezscheme) (std actor engine))

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
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define-syntax test-true
  (syntax-rules ()
    [(_ name expr)
     (test name (if expr #t #f) #t)]))

(printf "--- (std actor engine) tests ---~%")

;;;; Test 1: Create engine pool and verify predicate

(test-true "engine-pool/predicate"
  (let ([pool (make-engine-pool 1)])
    (let ([result (engine-pool? pool)])
      (engine-pool-stop! pool)
      result)))

;;;; Test 2: engine-pool? returns #f for non-pool values

(test "engine-pool/predicate false for non-pool"
  (engine-pool? 42)
  #f)

(test "engine-pool/predicate false for list"
  (engine-pool? '(a b c))
  #f)

;;;; Test 3: engine-pool-worker-count matches requested workers

(test "engine-pool/worker-count 1"
  (let ([pool (make-engine-pool 1)])
    (let ([n (engine-pool-worker-count pool)])
      (engine-pool-stop! pool)
      n))
  1)

(test "engine-pool/worker-count 3"
  (let ([pool (make-engine-pool 3)])
    (let ([n (engine-pool-worker-count pool)])
      (engine-pool-stop! pool)
      n))
  3)

;;;; Test 4: default-fuel returns a positive number

(test-true "engine-pool/default-fuel positive"
  (> (default-fuel) 0))

(test "engine-pool/default-fuel is 10000"
  (default-fuel)
  10000)

;;;; Test 5: Submit a thunk and wait for result using mutex/condition

(test "engine-pool/submit single thunk"
  (let* ([result #f]
         [mtx (make-mutex)]
         [cond-var (make-condition)]
         [pool (make-engine-pool 2)])
    (engine-pool-submit! pool
      (lambda ()
        (with-mutex mtx
          (set! result 42)
          (condition-signal cond-var))))
    ;; Wait for the thunk to complete
    (with-mutex mtx
      (let loop ()
        (unless result
          (condition-wait cond-var mtx)
          (loop))))
    (engine-pool-stop! pool)
    result)
  42)

;;;; Test 6: Submit thunk that does computation (sum of numbers)

(test "engine-pool/submit computation"
  (let* ([result #f]
         [mtx (make-mutex)]
         [cond-var (make-condition)]
         [pool (make-engine-pool 2)])
    (engine-pool-submit! pool
      (lambda ()
        (let ([sum (apply + '(1 2 3 4 5 6 7 8 9 10))])
          (with-mutex mtx
            (set! result sum)
            (condition-signal cond-var)))))
    (with-mutex mtx
      (let loop ()
        (unless result
          (condition-wait cond-var mtx)
          (loop))))
    (engine-pool-stop! pool)
    result)
  55)

;;;; Test 7: Submit multiple thunks, all complete

(test "engine-pool/multiple thunks all complete"
  (let* ([count 0]
         [total 3]
         [mtx (make-mutex)]
         [cond-var (make-condition)]
         [pool (make-engine-pool 2)])
    (do ([i 0 (+ i 1)])
        ((= i total))
      (engine-pool-submit! pool
        (lambda ()
          (with-mutex mtx
            (set! count (+ count 1))
            (when (= count total)
              (condition-signal cond-var))))))
    ;; Wait until all 3 thunks complete
    (with-mutex mtx
      (let loop ()
        (unless (= count total)
          (condition-wait cond-var mtx)
          (loop))))
    (engine-pool-stop! pool)
    count)
  3)

;;;; Test 8: engine-pool-stop! shuts down cleanly (no error)

(test "engine-pool/stop! is idempotent in sense that second stop doesn't crash"
  (let ([pool (make-engine-pool 1)])
    (engine-pool-stop! pool)
    ;; Calling stop again should not crash (it just broadcasts again)
    (engine-pool-stop! pool)
    'ok)
  'ok)

;;;; Test 9: Submit to stopped pool raises error

(test "engine-pool/submit to stopped pool raises"
  (let ([pool (make-engine-pool 1)])
    (engine-pool-stop! pool)
    (guard (exn [#t 'error-raised])
      (engine-pool-submit! pool (lambda () 42))
      'no-error))
  'error-raised)

;;;; Test 10: Re-create pool after stopping previous one

(test "engine-pool/recreate after stop"
  (let* ([pool1 (make-engine-pool 2)]
         [_ (engine-pool-stop! pool1)]
         [pool2 (make-engine-pool 2)]
         [n (engine-pool-worker-count pool2)])
    (engine-pool-stop! pool2)
    n)
  2)

;;;; Test 11: Default pool creation (no args) — 4 workers

(test "engine-pool/default no-args creates 4 workers"
  (let ([pool (make-engine-pool)])
    (let ([n (engine-pool-worker-count pool)])
      (engine-pool-stop! pool)
      n))
  4)

;;;; Test 12: Keyword-style creation

(test "engine-pool/keyword-style workers"
  (let ([pool (make-engine-pool '#:workers 2)])
    (let ([n (engine-pool-worker-count pool)])
      (engine-pool-stop! pool)
      n))
  2)

;;;; Test 13: Submit multiple thunks with result collection (concurrent)

(test "engine-pool/concurrent results collected"
  (let* ([results '()]
         [count 0]
         [total 5]
         [mtx (make-mutex)]
         [cond-var (make-condition)]
         [pool (make-engine-pool 3)])
    (do ([i 0 (+ i 1)])
        ((= i total))
      (let ([n i])  ;; capture loop variable
        (engine-pool-submit! pool
          (lambda ()
            (with-mutex mtx
              (set! results (cons n results))
              (set! count (+ count 1))
              (when (= count total)
                (condition-signal cond-var)))))))
    (with-mutex mtx
      (let loop ()
        (unless (= count total)
          (condition-wait cond-var mtx)
          (loop))))
    (engine-pool-stop! pool)
    ;; All 5 results should be collected (order may vary)
    (= (length results) total))
  #t)

;;;; Test 14: engine-pool? on #f returns #f

(test "engine-pool/predicate false for #f"
  (engine-pool? #f)
  #f)

;;;; Test 15: Two-arg creation (workers + fuel)

(test "engine-pool/two-arg creation"
  (let ([pool (make-engine-pool 2 5000)])
    (let ([n (engine-pool-worker-count pool)])
      (engine-pool-stop! pool)
      n))
  2)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
