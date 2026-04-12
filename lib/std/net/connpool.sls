#!chezscheme
;;; (std net connpool) — Fiber-aware connection pool
;;;
;;; Maintains a pool of reusable TCP connections. Fibers acquire a
;;; connection, use it, and return it. The pool manages the lifecycle.
;;;
;;; API:
;;;   (make-conn-pool host port poller max-size)  — create pool
;;;   (conn-pool-acquire! pool)                    — get a connection (parks if full)
;;;   (conn-pool-release! pool fd)                 — return connection to pool
;;;   (conn-pool-discard! pool fd)                 — close and remove connection
;;;   (conn-pool-close! pool)                      — close all connections
;;;   (conn-pool-size pool)                        — current pool size
;;;   (with-pooled-connection pool body ...)        — scoped acquire/release

(library (std net connpool)
  (export
    make-conn-pool
    conn-pool?
    conn-pool-acquire!
    conn-pool-release!
    conn-pool-discard!
    conn-pool-close!
    conn-pool-size
    with-pooled-connection)

  (import (chezscheme)
          (std fiber)
          (std net io))

  ;; ========== Connection pool ==========

  (define-record-type conn-pool
    (fields
      (immutable host)
      (immutable port)
      (immutable poller)
      (immutable max-size)
      (mutable idle)        ;; list of idle fd's
      (mutable active)      ;; count of checked-out connections
      (immutable mutex)
      (immutable semaphore))  ;; fiber-semaphore for max-size
    (protocol
      (lambda (new)
        (lambda (host port poller max-size)
          (new host port poller max-size
               '() 0 (make-mutex)
               (make-fiber-semaphore max-size))))))

  (define (conn-pool-size pool)
    (with-mutex (conn-pool-mutex pool)
      (+ (length (conn-pool-idle pool))
         (conn-pool-active pool))))

  ;; Acquire a connection from the pool.
  ;; Returns an idle connection if available, or creates a new one.
  ;; Parks the fiber if the pool is at max capacity.
  (define (conn-pool-acquire! pool)
    ;; Acquire semaphore permit (parks if at max)
    (fiber-semaphore-acquire! (conn-pool-semaphore pool))
    (let ([mx (conn-pool-mutex pool)])
      (mutex-acquire mx)
      (let ([idle (conn-pool-idle pool)])
        (cond
          [(not (null? idle))
           ;; Reuse an idle connection
           (let ([fd (car idle)])
             (conn-pool-idle-set! pool (cdr idle))
             (conn-pool-active-set! pool (+ (conn-pool-active pool) 1))
             (mutex-release mx)
             fd)]
          [else
           ;; Create a new connection
           (conn-pool-active-set! pool (+ (conn-pool-active pool) 1))
           (mutex-release mx)
           (fiber-tcp-connect (conn-pool-host pool)
                              (conn-pool-port pool)
                              (conn-pool-poller pool))]))))

  ;; Return a connection to the pool for reuse.
  (define (conn-pool-release! pool fd)
    (let ([mx (conn-pool-mutex pool)])
      (mutex-acquire mx)
      (conn-pool-idle-set! pool (cons fd (conn-pool-idle pool)))
      (conn-pool-active-set! pool (max 0 (- (conn-pool-active pool) 1)))
      (mutex-release mx))
    ;; Release semaphore permit
    (fiber-semaphore-release! (conn-pool-semaphore pool)))

  ;; Close a connection and remove it from the pool (e.g., on error).
  (define (conn-pool-discard! pool fd)
    (let ([mx (conn-pool-mutex pool)])
      (mutex-acquire mx)
      (conn-pool-active-set! pool (max 0 (- (conn-pool-active pool) 1)))
      (mutex-release mx))
    (fiber-tcp-close fd)
    ;; Release semaphore permit
    (fiber-semaphore-release! (conn-pool-semaphore pool)))

  ;; Close all connections in the pool.
  (define (conn-pool-close! pool)
    (let ([mx (conn-pool-mutex pool)])
      (mutex-acquire mx)
      (for-each (lambda (fd) (fiber-tcp-close fd)) (conn-pool-idle pool))
      (conn-pool-idle-set! pool '())
      (mutex-release mx)))

  ;; Convenience macro: acquire, use, release (or discard on error).
  (define-syntax with-pooled-connection
    (syntax-rules ()
      [(_ pool fd body ...)
       (let ([fd (conn-pool-acquire! pool)])
         (guard (exn [#t
           (conn-pool-discard! pool fd)
           (raise exn)])
           (let ([result (begin body ...)])
             (conn-pool-release! pool fd)
             result)))]))

) ;; end library
