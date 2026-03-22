#!chezscheme
;;; (std db conpool) — Database connection pooling
;;;
;;; Thread-safe connection pool using Chez Scheme's mutex and condition
;;; variables.  Manages a set of idle connections and tracks active ones.
;;; Connections are created on demand up to a configurable maximum.

(library (std db conpool)
  (export
    make-connection-pool
    pool-acquire
    pool-release
    pool-close
    with-connection
    pool-size
    pool-available
    pool-stats)

  (import (chezscheme))

  ;; ========== Pool record ==========

  (define-record-type connection-pool
    (fields
     connector          ; thunk that creates a new connection
     max-size           ; maximum number of connections (idle + active)
     (mutable idle)     ; list of idle connections
     (mutable active)   ; count of connections currently checked out
     (mutable closed?)  ; #t once pool-close has been called
     (mutable total)    ; total number of connections created (idle + active)
     mutex              ; mutex for thread safety
     available-cv)      ; condition variable: signaled when a connection
                        ; becomes available or pool is closed
    (protocol
     (lambda (new)
       (lambda (connector max-size)
         (unless (procedure? connector)
           (error 'make-connection-pool "connector must be a procedure" connector))
         (unless (and (fixnum? max-size) (fx> max-size 0))
           (error 'make-connection-pool "max-size must be a positive fixnum" max-size))
         (new connector max-size
              '()    ; idle
              0      ; active
              #f     ; closed?
              0      ; total
              (make-mutex)
              (make-condition))))))

  ;; ========== Internal helpers ==========

  (define (pool-check-open pool who)
    (when (connection-pool-closed? pool)
      (error who "connection pool is closed")))

  ;; ========== Public API ==========

  (define (pool-acquire pool)
    ;; Acquire a connection from the pool.  If an idle connection is
    ;; available, return it.  Otherwise, if the pool is not at capacity,
    ;; create a new one.  If at capacity, block until one is released.
    (let ([mtx (connection-pool-mutex pool)]
          [cv  (connection-pool-available-cv pool)])
      (mutex-acquire mtx)
      (let loop ()
        (pool-check-open pool 'pool-acquire)
        (let ([idle (connection-pool-idle pool)])
          (cond
            ;; Idle connection available: take it
            [(pair? idle)
             (let ([conn (car idle)])
               (connection-pool-idle-set! pool (cdr idle))
               (connection-pool-active-set! pool
                 (fx+ (connection-pool-active pool) 1))
               (mutex-release mtx)
               conn)]
            ;; Room to create a new connection
            [(fx< (connection-pool-total pool) (connection-pool-max-size pool))
             (connection-pool-active-set! pool
               (fx+ (connection-pool-active pool) 1))
             (connection-pool-total-set! pool
               (fx+ (connection-pool-total pool) 1))
             (mutex-release mtx)
             ;; Create connection outside the lock
             (let ([conn ((connection-pool-connector pool))])
               conn)]
            ;; At capacity — wait
            [else
             (condition-wait cv mtx)
             (loop)])))))

  (define (pool-release pool conn)
    ;; Return a connection to the pool's idle list.
    (let ([mtx (connection-pool-mutex pool)]
          [cv  (connection-pool-available-cv pool)])
      (mutex-acquire mtx)
      (connection-pool-active-set! pool
        (fx- (connection-pool-active pool) 1))
      (cond
        [(connection-pool-closed? pool)
         ;; Pool is closing; decrement total and discard connection
         (connection-pool-total-set! pool
           (fx- (connection-pool-total pool) 1))
         (mutex-release mtx)
         ;; Attempt to close the connection if it has a close method
         ;; (best-effort; we don't know the type here)
         (void)]
        [else
         (connection-pool-idle-set! pool
           (cons conn (connection-pool-idle pool)))
         (condition-signal cv)
         (mutex-release mtx)])))

  (define (pool-close pool)
    ;; Close the pool: mark as closed, clear idle connections.
    ;; Does not forcibly close active connections (they will be
    ;; discarded when released).
    (let ([mtx (connection-pool-mutex pool)]
          [cv  (connection-pool-available-cv pool)])
      (mutex-acquire mtx)
      (connection-pool-closed?-set! pool #t)
      (let ([idle (connection-pool-idle pool)])
        (connection-pool-idle-set! pool '())
        (connection-pool-total-set! pool
          (connection-pool-active pool))
        ;; Wake up any threads waiting in pool-acquire so they get
        ;; the "pool is closed" error.
        (condition-broadcast cv)
        (mutex-release mtx)
        ;; Return the list of idle connections that were discarded,
        ;; so callers can close them if needed.
        idle)))

  (define (pool-size pool)
    ;; Total number of connections managed (idle + active).
    (let ([mtx (connection-pool-mutex pool)])
      (mutex-acquire mtx)
      (let ([n (connection-pool-total pool)])
        (mutex-release mtx)
        n)))

  (define (pool-available pool)
    ;; Number of idle connections available for immediate use.
    (let ([mtx (connection-pool-mutex pool)])
      (mutex-acquire mtx)
      (let ([n (length (connection-pool-idle pool))])
        (mutex-release mtx)
        n)))

  (define (pool-stats pool)
    ;; Return an alist of pool statistics.
    (let ([mtx (connection-pool-mutex pool)])
      (mutex-acquire mtx)
      (let ([total  (connection-pool-total pool)]
            [active (connection-pool-active pool)]
            [idle   (length (connection-pool-idle pool))]
            [max    (connection-pool-max-size pool)]
            [closed (connection-pool-closed? pool)])
        (mutex-release mtx)
        `((total   . ,total)
          (active  . ,active)
          (idle    . ,idle)
          (max     . ,max)
          (closed  . ,closed)))))

  ;; ========== with-connection macro ==========

  (define-syntax with-connection
    (syntax-rules ()
      [(_ (conn pool-expr) body ...)
       (let* ([p pool-expr]
              [conn (pool-acquire p)])
         (dynamic-wind
           (lambda () (void))
           (lambda () body ...)
           (lambda () (pool-release p conn))))]))

  ) ;; end library
