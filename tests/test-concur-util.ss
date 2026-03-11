#!chezscheme
;;; Tests for (std concur util) — Extended concurrency utilities

(import (chezscheme)
        (std concur util))

;; Helper: sleep for N seconds (Chez sleep takes a time-duration record)
(define (sleep-secs n)
  (let ([ns (exact (round (* n 1e9)))])
    (sleep (make-time 'time-duration ns 0))))

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

(define-syntax test-pred
  (syntax-rules ()
    [(_ name expr)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (if expr
         (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
         (begin (set! fail (+ fail 1))
                (printf "FAIL ~a: expression was #f~%" name))))]))

(define-syntax test-raises
  (syntax-rules ()
    [(_ name pred expr)
     (guard (exn [(pred exn)
                  (set! pass (+ pass 1)) (printf "  ok ~a~%" name)]
                 [#t
                  (set! fail (+ fail 1))
                  (printf "FAIL ~a: unexpected condition ~s~%" name exn)])
       expr
       (set! fail (+ fail 1))
       (printf "FAIL ~a: no exception raised~%" name))]))

(printf "--- (std concur util) tests ---~%")

;;; ======== SEMAPHORES ========

(printf "~%-- Semaphores --~%")

(test "semaphore? #t"
  (semaphore? (make-semaphore 1))
  #t)

(test "semaphore? #f on non-semaphore"
  (semaphore? 42)
  #f)

(test "semaphore-count initial"
  (semaphore-count (make-semaphore 3))
  3)

(test "semaphore-count after acquire"
  (let ([s (make-semaphore 2)])
    (semaphore-acquire! s)
    (semaphore-count s))
  1)

(test "semaphore-count after acquire and release"
  (let ([s (make-semaphore 1)])
    (semaphore-acquire! s)
    (semaphore-release! s)
    (semaphore-count s))
  1)

(test "semaphore-try-acquire! succeeds when count > 0"
  (let ([s (make-semaphore 1)])
    (semaphore-try-acquire! s))
  #t)

(test "semaphore-try-acquire! fails when count = 0"
  (let ([s (make-semaphore 0)])
    (semaphore-try-acquire! s))
  #f)

(test "semaphore count 0 after failed try-acquire"
  (let ([s (make-semaphore 0)])
    (semaphore-try-acquire! s)
    (semaphore-count s))
  0)

;; Thread-safety: producer/consumer
(test "semaphore thread handoff"
  (let ([s (make-semaphore 0)]
        [result #f])
    (fork-thread
      (lambda ()
        (sleep-secs 0.01)
        (set! result 'done)
        (semaphore-release! s)))
    (semaphore-acquire! s)
    result)
  'done)

;;; ======== READ-WRITE LOCKS ========

(printf "~%-- Read-Write Locks --~%")

(test "rwlock? #t"
  (rwlock? (make-rwlock))
  #t)

(test "rwlock? #f on non-rwlock"
  (rwlock? 'not-a-rwlock)
  #f)

(test "rwlock-read-lock! and unlock basic"
  (let ([rw (make-rwlock)])
    (rwlock-read-lock! rw)
    (rwlock-read-unlock! rw)
    #t)
  #t)

(test "rwlock-write-lock! and unlock basic"
  (let ([rw (make-rwlock)])
    (rwlock-write-lock! rw)
    (rwlock-write-unlock! rw)
    #t)
  #t)

(test "with-read-lock returns body value"
  (let ([rw (make-rwlock)])
    (with-read-lock rw 42))
  42)

(test "with-write-lock returns body value"
  (let ([rw (make-rwlock)])
    (with-write-lock rw 'hello))
  'hello)

(test "multiple readers simultaneously"
  (let ([rw (make-rwlock)]
        [count 0]
        [sem (make-semaphore 0)])
    (fork-thread
      (lambda ()
        (with-read-lock rw
          (set! count (+ count 1))
          (semaphore-release! sem))))
    (fork-thread
      (lambda ()
        (with-read-lock rw
          (set! count (+ count 1))
          (semaphore-release! sem))))
    (semaphore-acquire! sem)
    (semaphore-acquire! sem)
    count)
  2)

(test "write lock is exclusive"
  (let ([rw (make-rwlock)]
        [result '()])
    (with-write-lock rw
      (set! result (cons 'a result)))
    (with-write-lock rw
      (set! result (cons 'b result)))
    (reverse result))
  '(a b))

;;; ======== BARRIERS ========

(printf "~%-- Barriers --~%")

(test "barrier? #t"
  (barrier? (make-barrier 2))
  #t)

(test "barrier? #f on non-barrier"
  (barrier? 'x)
  #f)

;; Single-thread barrier (n=1 trips immediately)
(test "barrier n=1 trips immediately"
  (let ([b (make-barrier 1)])
    (barrier-wait! b)
    'passed)
  'passed)

;; Two-thread barrier
(test "barrier n=2 two threads"
  (let ([b (make-barrier 2)]
        [result #f]
        [sem (make-semaphore 0)])
    (fork-thread
      (lambda ()
        (barrier-wait! b)
        (set! result 'thread-done)
        (semaphore-release! sem)))
    (barrier-wait! b)
    (semaphore-acquire! sem)
    result)
  'thread-done)

;; barrier-reset! allows reuse
(test "barrier-reset! allows reuse"
  (let ([b (make-barrier 1)])
    (barrier-wait! b)
    (barrier-reset! b)
    (barrier-wait! b)
    'reused)
  'reused)

;;; ======== THREAD POOLS ========

(printf "~%-- Thread Pools --~%")

(test "thread-pool? #t"
  (thread-pool? (let ([p (make-thread-pool 1)])
                  (thread-pool-stop! p)
                  p))
  #t)

(test "thread-pool? #f"
  (thread-pool? 'x)
  #f)

(test "thread-pool-worker-count"
  (let ([p (make-thread-pool 3)])
    (let ([n (thread-pool-worker-count p)])
      (thread-pool-stop! p)
      n))
  3)

(test "thread-pool-submit! runs task"
  (let ([p (make-thread-pool 2)]
        [result #f]
        [sem (make-semaphore 0)])
    (thread-pool-submit! p
      (lambda ()
        (set! result 'ran)
        (semaphore-release! sem)))
    (semaphore-acquire! sem)
    (thread-pool-stop! p)
    result)
  'ran)

(test "thread-pool submits multiple tasks"
  (let ([p (make-thread-pool 2)]
        [results '()]
        [sem (make-semaphore 0)]
        [mutex (make-mutex)])
    (do ([i 0 (+ i 1)]) ((= i 3))
      (let ([n i])
        (thread-pool-submit! p
          (lambda ()
            (with-mutex mutex
              (set! results (cons n results)))
            (semaphore-release! sem)))))
    (semaphore-acquire! sem)
    (semaphore-acquire! sem)
    (semaphore-acquire! sem)
    (thread-pool-stop! p)
    (= (length results) 3))
  #t)

(test "thread-pool-stop! stops pool"
  (let ([p (make-thread-pool 1)])
    (thread-pool-stop! p)
    ;; After stopping, submitting should raise
    (guard (exn [#t 'error-caught])
      (thread-pool-submit! p (lambda () 'x))
      'no-error))
  'error-caught)

;;; ======== FUTURES ========

(printf "~%-- Futures --~%")

(test "future? #t"
  (let ([f (spawn-future (lambda () 42))])
    (future? f))
  #t)

(test "future? #f"
  (future? 42)
  #f)

(test "spawn-future computes value"
  (future-force (spawn-future (lambda () (+ 1 2))))
  3)

(test "future-force blocks until ready"
  (let ([f (spawn-future (lambda ()
                           (sleep-secs 0.02)
                           'delayed))])
    (future-force f))
  'delayed)

(test "future-ready? #f initially"
  (let ([f (spawn-future (lambda ()
                           (sleep-secs 0.1)
                           'slow))])
    (future-ready? f))
  #f)

(test "future-ready? #t after force"
  (let ([f (spawn-future (lambda () 'fast))])
    (future-force f)
    (future-ready? f))
  #t)

(test "make-future creates a future"
  (future? (make-future))
  #t)

(test "future-map transforms result"
  (let ([f (spawn-future (lambda () 5))])
    (future-force (future-map (lambda (x) (* x 2)) f)))
  10)

(test "future-map chaining"
  (let ([f (spawn-future (lambda () 3))])
    (future-force
      (future-map
        (lambda (x) (+ x 1))
        (future-map (lambda (x) (* x x)) f))))
  10)

;;; ======== LATCHES ========

(printf "~%-- Latches --~%")

(test "latch-await with count 0 returns immediately"
  (let ([l (make-latch 0)])
    (latch-await l)
    'done)
  'done)

(test "latch count-down unblocks await"
  (let ([l (make-latch 1)]
        [result #f]
        [sem (make-semaphore 0)])
    (fork-thread
      (lambda ()
        (latch-await l)
        (set! result 'unblocked)
        (semaphore-release! sem)))
    (sleep-secs 0.01)
    (latch-count-down! l)
    (semaphore-acquire! sem)
    result)
  'unblocked)

(test "latch count-down from 2"
  (let ([l (make-latch 2)]
        [result #f]
        [sem (make-semaphore 0)])
    (fork-thread
      (lambda ()
        (latch-await l)
        (set! result 'done)
        (semaphore-release! sem)))
    (latch-count-down! l)
    (sleep-secs 0.01)
    (latch-count-down! l)
    (semaphore-acquire! sem)
    result)
  'done)

(test "latch extra count-down safe (stays at 0)"
  (let ([l (make-latch 1)])
    (latch-count-down! l)
    (latch-count-down! l)  ;; should not go negative
    (latch-await l)
    'ok)
  'ok)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
