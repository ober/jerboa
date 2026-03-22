#!/usr/bin/env scheme-script
#!chezscheme
(import (chezscheme)
        (std misc pool))

(define test-count 0)
(define pass-count 0)

(define (test name thunk)
  (set! test-count (+ test-count 1))
  (guard (e [#t (display "FAIL: ") (display name) (newline)
              (display "  Error: ")
              (display (if (message-condition? e) (condition-message e) e))
              (newline)])
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
    (error 'assert-true (string-append msg ": expected true"))))

;; Helper: simple resource = a gensym-tagged vector
(define (make-factory)
  (let ([counter 0])
    (lambda ()
      (set! counter (+ counter 1))
      (vector 'resource counter))))

(define (resource-id r) (vector-ref r 1))

(define destroyed '())
(define (tracking-destroyer r)
  (set! destroyed (cons (resource-id r) destroyed)))

(define (reset-destroyed!) (set! destroyed '()))

;; ----- Tests -----

;; Test 1: pool? predicate
(test "pool? recognizes pools"
  (lambda ()
    (let ([p (make-pool (make-factory) (lambda (r) (void)) 5)])
      (assert-true (pool? p) "pool?")
      (assert-true (not (pool? 42)) "not pool?"))))

;; Test 2: acquire creates a resource
(test "acquire creates a new resource"
  (lambda ()
    (let ([p (make-pool (make-factory) (lambda (r) (void)) 5)])
      (let ([r (pool-acquire p)])
        (assert-equal (vector-ref r 0) 'resource "is a resource")
        (pool-release p r)))))

;; Test 3: pool-stats after acquire
(test "pool-stats reflects acquire"
  (lambda ()
    (let ([p (make-pool (make-factory) (lambda (r) (void)) 5)])
      (let ([r (pool-acquire p)])
        (let ([s (pool-stats p)])
          (assert-equal (cdr (assq 'total s)) 1 "total")
          (assert-equal (cdr (assq 'in-use s)) 1 "in-use")
          (assert-equal (cdr (assq 'idle s)) 0 "idle"))
        (pool-release p r)))))

;; Test 4: pool-stats after release
(test "pool-stats reflects release"
  (lambda ()
    (let ([p (make-pool (make-factory) (lambda (r) (void)) 5)])
      (let ([r (pool-acquire p)])
        (pool-release p r)
        (let ([s (pool-stats p)])
          (assert-equal (cdr (assq 'total s)) 1 "total")
          (assert-equal (cdr (assq 'in-use s)) 0 "in-use")
          (assert-equal (cdr (assq 'idle s)) 1 "idle"))))))

;; Test 5: reuses idle resources
(test "acquire reuses idle resource"
  (lambda ()
    (let ([p (make-pool (make-factory) (lambda (r) (void)) 5)])
      (let ([r1 (pool-acquire p)])
        (let ([id1 (resource-id r1)])
          (pool-release p r1)
          (let ([r2 (pool-acquire p)])
            (assert-equal (resource-id r2) id1 "same resource reused")
            (pool-release p r2)))))))

;; Test 6: multiple resources
(test "multiple acquires create separate resources"
  (lambda ()
    (let ([p (make-pool (make-factory) (lambda (r) (void)) 5)])
      (let ([r1 (pool-acquire p)]
            [r2 (pool-acquire p)])
        (assert-true (not (equal? (resource-id r1) (resource-id r2)))
                     "different resources")
        (let ([s (pool-stats p)])
          (assert-equal (cdr (assq 'total s)) 2 "total=2")
          (assert-equal (cdr (assq 'in-use s)) 2 "in-use=2"))
        (pool-release p r1)
        (pool-release p r2)))))

;; Test 7: with-resource macro
(test "with-resource acquires and releases"
  (lambda ()
    (let ([p (make-pool (make-factory) (lambda (r) (void)) 5)]
          [captured-id #f])
      (with-resource p (r)
        (set! captured-id (resource-id r)))
      (assert-true captured-id "got a resource")
      (let ([s (pool-stats p)])
        (assert-equal (cdr (assq 'in-use s)) 0 "released after body")
        (assert-equal (cdr (assq 'idle s)) 1 "back in idle")))))

;; Test 8: with-resource releases on exception
(test "with-resource releases on exception"
  (lambda ()
    (let ([p (make-pool (make-factory) (lambda (r) (void)) 5)])
      (guard (e [#t (void)])
        (with-resource p (r)
          (error 'test "deliberate error")))
      (let ([s (pool-stats p)])
        (assert-equal (cdr (assq 'in-use s)) 0 "released after error")
        (assert-equal (cdr (assq 'idle s)) 1 "idle after error")))))

;; Test 9: pool-drain destroys idle resources
(test "pool-drain destroys idle resources"
  (lambda ()
    (reset-destroyed!)
    (let ([p (make-pool (make-factory) tracking-destroyer 5)])
      (let ([r1 (pool-acquire p)]
            [r2 (pool-acquire p)])
        (pool-release p r1)
        (pool-release p r2)
        ;; Both are now idle
        (pool-drain p)
        (assert-equal (length destroyed) 2 "two destroyed")
        (let ([s (pool-stats p)])
          (assert-equal (cdr (assq 'idle s)) 0 "no idle after drain")
          (assert-equal (cdr (assq 'total s)) 0 "total zero after drain"))))))

;; Test 10: pool-drain does not affect in-use resources
(test "pool-drain leaves in-use resources alone"
  (lambda ()
    (reset-destroyed!)
    (let ([p (make-pool (make-factory) tracking-destroyer 5)])
      (let ([r1 (pool-acquire p)]
            [r2 (pool-acquire p)])
        (pool-release p r1)
        ;; r1 idle, r2 in-use
        (pool-drain p)
        (assert-equal (length destroyed) 1 "only idle destroyed")
        (let ([s (pool-stats p)])
          (assert-equal (cdr (assq 'in-use s)) 1 "in-use intact")
          (assert-equal (cdr (assq 'idle s)) 0 "idle drained"))
        (pool-release p r2)))))

;; Test 11: acquire with timeout returns #f when pool full
(test "acquire with timeout returns #f at max"
  (lambda ()
    (let ([p (make-pool (make-factory) (lambda (r) (void)) 1)])
      (let ([r (pool-acquire p)])
        ;; Pool is at max (1), acquire with short timeout
        (let ([result (pool-acquire p 0.01)])
          (assert-equal result #f "timed out")
          ;; Stats: 1 in-use, 0 idle
          (let ([s (pool-stats p)])
            (assert-equal (cdr (assq 'in-use s)) 1 "still 1 in-use"))
          (pool-release p r))))))

;; Test 12: acquire without timeout blocks then succeeds (thread test)
(test "acquire blocks until resource freed"
  (lambda ()
    (let ([p (make-pool (make-factory) (lambda (r) (void)) 1)]
          [acquired-in-thread #f])
      (let ([r (pool-acquire p)])
        ;; Spawn thread that will acquire (blocks until we release)
        (let ([t (fork-thread
                   (lambda ()
                     (let ([r2 (pool-acquire p)])
                       (set! acquired-in-thread (resource-id r2))
                       (pool-release p r2))))])
          ;; Give thread time to start and block
          (sleep (make-time 'time-duration 20000000 0))  ;; 20ms
          ;; Release so thread can proceed
          (pool-release p r)
          ;; Wait for thread
          (sleep (make-time 'time-duration 50000000 0))  ;; 50ms
          (assert-true acquired-in-thread "thread acquired resource"))))))

;; Test 13: max-size limits total resources
(test "max-size limits total resources"
  (lambda ()
    (let ([create-count 0])
      (let ([p (make-pool
                 (lambda ()
                   (set! create-count (+ create-count 1))
                   (vector 'r create-count))
                 (lambda (r) (void))
                 2)])
        (let ([r1 (pool-acquire p)]
              [r2 (pool-acquire p)])
          (assert-equal create-count 2 "created 2")
          ;; Third acquire with timeout should fail
          (let ([r3 (pool-acquire p 0.01)])
            (assert-equal r3 #f "max reached, timed out")
            (assert-equal create-count 2 "still only 2 created"))
          (pool-release p r1)
          (pool-release p r2))))))

;; Test 14: with-resource returns body value
(test "with-resource returns body value"
  (lambda ()
    (let ([p (make-pool (make-factory) (lambda (r) (void)) 5)])
      (let ([result (with-resource p (r) (* 6 7))])
        (assert-equal result 42 "body value returned")))))

;; Test 15: idle timeout evicts expired resources
(test "idle-timeout evicts expired resources"
  (lambda ()
    (reset-destroyed!)
    (let ([p (make-pool (make-factory) tracking-destroyer 5 0.05)])
      ;; 50ms idle timeout
      (let ([r (pool-acquire p)])
        (pool-release p r)
        ;; Wait for it to expire
        (sleep (make-time 'time-duration 80000000 0))  ;; 80ms
        ;; Next acquire triggers eviction and creates new
        (let ([r2 (pool-acquire p)])
          (assert-true (> (length destroyed) 0) "old resource destroyed")
          (pool-release p r2))))))

;; Test 16: pool-stats is consistent
(test "pool-stats consistent across operations"
  (lambda ()
    (let ([p (make-pool (make-factory) (lambda (r) (void)) 10)])
      ;; Empty pool
      (let ([s (pool-stats p)])
        (assert-equal (cdr (assq 'total s)) 0 "initial total=0"))
      ;; Acquire 3
      (let ([r1 (pool-acquire p)]
            [r2 (pool-acquire p)]
            [r3 (pool-acquire p)])
        (let ([s (pool-stats p)])
          (assert-equal (cdr (assq 'total s)) 3 "total=3")
          (assert-equal (cdr (assq 'in-use s)) 3 "in-use=3")
          (assert-equal (cdr (assq 'idle s)) 0 "idle=0"))
        ;; Release 2
        (pool-release p r1)
        (pool-release p r2)
        (let ([s (pool-stats p)])
          (assert-equal (cdr (assq 'total s)) 3 "total still 3")
          (assert-equal (cdr (assq 'in-use s)) 1 "in-use=1")
          (assert-equal (cdr (assq 'idle s)) 2 "idle=2"))
        (pool-release p r3)))))

(newline)
(display "=========================================") (newline)
(display (format "Results: ~a/~a passed" pass-count test-count)) (newline)
(display "=========================================") (newline)
(when (< pass-count test-count)
  (exit 1))
