#!chezscheme
(import (chezscheme) (std net pool))

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

(printf "--- Phase 2d: Connection Pool ---~%~%")

;; Helpers: simple "connection" = a box (vector) with state
(define (make-test-factory)
  (let ([counter (make-vector 1 0)])
    (lambda ()
      (vector-set! counter 0 (+ (vector-ref counter 0) 1))
      (vector (vector-ref counter 0)))))

(define (test-closer conn)
  (vector-set! conn 0 'closed))

(define (test-checker conn)
  (not (equal? (vector-ref conn 0) 'closed)))

;; Test 1: make-connection-pool
(let ([pool (make-connection-pool
              (lambda () (vector 'conn))
              (lambda (c) (void))
              #f
              1 5)])
  (test "pool-created" (connection-pool? pool) #t)
  (test "pool-initial-size" (pool-size pool) 1)
  (test "pool-initial-available" (pool-available pool) 1))

;; Test 2: pool-acquire! returns a connection
(let ([pool (make-connection-pool
              (lambda () (vector 'conn))
              (lambda (c) (void))
              #f
              1 5)])
  (let ([conn (pool-acquire! pool)])
    (test "acquire-returns-connection"
      (vector? conn)
      #t)
    (pool-release! pool conn)))

;; Test 3: acquire reduces available count
(let ([pool (make-connection-pool
              (lambda () (vector 'conn))
              (lambda (c) (void))
              #f
              2 5)])
  (let ([c1 (pool-acquire! pool)])
    (test "available-after-acquire"
      (pool-available pool)
      1)
    (let ([c2 (pool-acquire! pool)])
      (test "available-after-two-acquire"
        (pool-available pool)
        0)
      (pool-release! pool c1)
      (pool-release! pool c2))))

;; Test 4: release returns connection to pool
(let ([pool (make-connection-pool
              (lambda () (vector 'conn))
              (lambda (c) (void))
              #f
              1 5)])
  (let ([conn (pool-acquire! pool)])
    (pool-release! pool conn)
    (test "available-after-release"
      (pool-available pool)
      1)))

;; Test 5: pool-stats
(let ([pool (make-connection-pool
              (lambda () (vector 'conn))
              (lambda (c) (void))
              #f
              2 5)])
  (let ([c (pool-acquire! pool)])
    (pool-release! pool c)
    (let ([stats (pool-stats pool)])
      (test "stats-acquired" (cdr (assq 'acquired stats)) 1)
      (test "stats-released" (cdr (assq 'released stats)) 1)
      (test "stats-created" (>= (cdr (assq 'created stats)) 1) #t))))

;; Test 6: with-connection acquires and releases
(let ([pool (make-connection-pool
              (lambda () (vector 'conn))
              (lambda (c) (void))
              #f
              1 5)])
  (let ([result #f])
    (with-connection pool
      (lambda (conn)
        (set! result (vector-ref conn 0))
        (test "available-in-with-connection"
          (pool-available pool)
          0)))
    (test "with-connection-saw-conn" result 'conn)
    (test "available-after-with-connection"
      (pool-available pool)
      1)))

;; Test 7: with-connection releases on exception
(let ([pool (make-connection-pool
              (lambda () (vector 'conn))
              (lambda (c) (void))
              #f
              1 3)])
  (guard (exn [#t (void)])
    (with-connection pool
      (lambda (conn)
        (error 'test "deliberate"))))
  (test "available-after-with-exception"
    (pool-available pool)
    1))

;; Test 8: pool-close! closes all idle connections
(let ([closed-count (make-vector 1 0)])
  (let ([pool (make-connection-pool
                (lambda () (vector 'conn))
                (lambda (c) (vector-set! closed-count 0
                               (+ (vector-ref closed-count 0) 1)))
                #f
                2 5)])
    (pool-close! pool)
    (test "pool-closed"
      (pool-size pool)
      0)
    (test "connections-closed"
      (>= (vector-ref closed-count 0) 2)
      #t)))

;; Test 9: pool-health-check! removes bad connections
(let ([health-vec (make-vector 1 #t)])
  (let ([pool (make-connection-pool
                (lambda () (vector 'conn))
                (lambda (c) (void))
                (lambda (c) (vector-ref health-vec 0))
                2 5)])
    ;; Make health check fail
    (vector-set! health-vec 0 #f)
    (pool-health-check! pool)
    (test "health-check-removes-bad"
      (pool-available pool)
      0)))

;; Test 10: pool grows up to max-size
(let ([pool (make-connection-pool
              (lambda () (vector 'conn))
              (lambda (c) (void))
              #f
              1 3)])
  (let ([c1 (pool-acquire! pool)]
        [c2 (pool-acquire! pool)]
        [c3 (pool-acquire! pool)])
    (test "pool-grew-to-max"
      (pool-size pool)
      3)
    (pool-release! pool c1)
    (pool-release! pool c2)
    (pool-release! pool c3)))

;; Test 11: pool-acquire! with timeout when at max
(let ([pool (make-connection-pool
              (lambda () (vector 'conn))
              (lambda (c) (void))
              #f
              1 1)])
  (let ([c (pool-acquire! pool)])
    ;; Pool is now empty and at max. Acquire with short timeout should fail.
    (guard (exn [#t
                 (test "acquire-timeout-raises" #t #t)])
      (pool-acquire! pool 10)  ;; 10ms timeout
      (test "acquire-should-have-timed-out" #f #t))
    (pool-release! pool c)))

;; Test 12: factory called for each new connection
(let ([create-count (make-vector 1 0)])
  (let ([pool (make-connection-pool
                (lambda ()
                  (vector-set! create-count 0
                    (+ (vector-ref create-count 0) 1))
                  (vector 'conn))
                (lambda (c) (void))
                #f
                0 5)])
    (let ([c1 (pool-acquire! pool)]
          [c2 (pool-acquire! pool)])
      (test "factory-called-twice"
        (vector-ref create-count 0)
        2)
      (pool-release! pool c1)
      (pool-release! pool c2))))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
