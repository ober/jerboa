#!chezscheme
;;; (std net pool) — Generic Connection Pool
;;;
;;; Manages a pool of connection objects with:
;;;   - Configurable min/max pool size
;;;   - Idle timeout and health checking
;;;   - Blocking acquire with timeout
;;;   - Statistics tracking
;;;
;;; A "connection" is any opaque object. The pool is parameterized by:
;;;   factory — (lambda () conn) — creates a new connection
;;;   closer  — (lambda (conn) ...) — destroys a connection
;;;   checker — (lambda (conn) bool) — health check (returns #t if healthy)
;;;
;;; API:
;;;   (make-connection-pool factory closer checker [min-size [max-size]])
;;;   (pool-acquire! pool [timeout-ms])  → connection
;;;   (pool-release! pool conn)
;;;   (pool-close! pool)
;;;   (pool-size pool)        → total connections (available + in-use)
;;;   (pool-available pool)   → available connection count
;;;   (pool-stats pool)       → alist of statistics
;;;   (with-connection pool proc)  → calls proc with conn, releases after
;;;   (pool-health-check! pool)    → validate all idle connections

(library (std net pool)
  (export
    make-connection-pool
    connection-pool?
    pool-acquire!
    pool-release!
    pool-close!
    pool-size
    pool-available
    pool-stats
    with-connection
    pool-health-check!)

  (import (chezscheme))

  ;; ========== Pool Entry ==========

  (define-record-type pool-entry
    (fields
      conn               ;; the connection object
      (mutable healthy?) ;; last known health
      (mutable created-at) ;; creation timestamp
      (mutable used-at))   ;; last use timestamp
    (protocol
      (lambda (new)
        (lambda (conn)
          (let ([now (time-second (current-time 'time-monotonic))])
            (new conn #t now now))))))

  ;; ========== Connection Pool ==========

  (define-record-type (connection-pool %make-connection-pool connection-pool?)
    (fields
      factory          ;; (lambda () conn)
      closer           ;; (lambda (conn) ...)
      checker          ;; (lambda (conn) bool) or #f
      min-size         ;; minimum idle connections
      max-size         ;; maximum total connections
      (mutable idle)   ;; list of pool-entry (available)
      (mutable in-use) ;; list of pool-entry (checked out)
      (mutable total)  ;; current total count
      (mutable closed?)
      mutex
      not-empty        ;; condition: conn returned to pool
      ;; Stats
      (mutable stats-acquired)
      (mutable stats-released)
      (mutable stats-created)
      (mutable stats-destroyed)
      (mutable stats-health-failures)
      (mutable stats-waits)))

  (define make-connection-pool
    (case-lambda
      [(factory closer checker)
       (make-connection-pool factory closer checker 1 10)]
      [(factory closer checker min-size max-size)
       (let ([pool (%make-connection-pool
                     factory closer checker
                     min-size max-size
                     '() '() 0 #f
                     (make-mutex) (make-condition)
                     0 0 0 0 0 0)])
         ;; Pre-warm with min-size connections
         (let warm ([i 0])
           (when (< i min-size)
             (%create-connection! pool)
             (warm (+ i 1))))
         pool)]))

  ;; Internal: create a new connection and add to idle
  (define (%create-connection! pool)
    (let ([conn ((connection-pool-factory pool))])
      (let ([entry (make-pool-entry conn)])
        (connection-pool-idle-set! pool
          (cons entry (connection-pool-idle pool)))
        (connection-pool-total-set! pool
          (+ (connection-pool-total pool) 1))
        (connection-pool-stats-created-set! pool
          (+ (connection-pool-stats-created pool) 1))
        entry)))

  (define pool-acquire!
    (case-lambda
      [(pool) (pool-acquire! pool #f)]
      [(pool timeout-ms)
       (mutex-acquire (connection-pool-mutex pool))
       (when (connection-pool-closed? pool)
         (mutex-release (connection-pool-mutex pool))
         (error 'pool-acquire! "pool is closed"))
       (let try ()
         (cond
           ;; Idle connection available
           [(pair? (connection-pool-idle pool))
            (let ([entry (car (connection-pool-idle pool))])
              (connection-pool-idle-set! pool
                (cdr (connection-pool-idle pool)))
              (connection-pool-in-use-set! pool
                (cons entry (connection-pool-in-use pool)))
              (pool-entry-used-at-set! entry
                (time-second (current-time 'time-monotonic)))
              (connection-pool-stats-acquired-set! pool
                (+ (connection-pool-stats-acquired pool) 1))
              (mutex-release (connection-pool-mutex pool))
              (pool-entry-conn entry))]
           ;; Can create new connection
           [(< (connection-pool-total pool) (connection-pool-max-size pool))
            (let ([entry (%create-connection! pool)])
              (connection-pool-idle-set! pool
                (cdr (connection-pool-idle pool))) ;; remove from idle
              (connection-pool-in-use-set! pool
                (cons entry (connection-pool-in-use pool)))
              (connection-pool-stats-acquired-set! pool
                (+ (connection-pool-stats-acquired pool) 1))
              (mutex-release (connection-pool-mutex pool))
              (pool-entry-conn entry))]
           ;; Must wait
           [else
            (connection-pool-stats-waits-set! pool
              (+ (connection-pool-stats-waits pool) 1))
            (if timeout-ms
              (let* ([ns (* timeout-ms 1000000)]
                     [s  (quotient ns 1000000000)]
                     [ns-part (remainder ns 1000000000)])
                (condition-wait (connection-pool-not-empty pool)
                                (connection-pool-mutex pool)
                                (make-time 'time-duration ns-part s))
                ;; Check if still nothing available → timeout
                (if (and (null? (connection-pool-idle pool))
                         (>= (connection-pool-total pool)
                             (connection-pool-max-size pool)))
                  (begin
                    (mutex-release (connection-pool-mutex pool))
                    (error 'pool-acquire! "timeout waiting for connection"))
                  (try)))
              (begin
                (condition-wait (connection-pool-not-empty pool)
                                (connection-pool-mutex pool))
                (try)))]))]))

  (define (pool-release! pool conn)
    (mutex-acquire (connection-pool-mutex pool))
    ;; Find the entry
    (let loop ([entries (connection-pool-in-use pool)] [rest '()])
      (cond
        [(null? entries)
         ;; Not found — ignore
         (mutex-release (connection-pool-mutex pool))]
        [(eq? (pool-entry-conn (car entries)) conn)
         ;; Found: move back to idle (or close if pool is full/closed)
         (let ([entry (car entries)])
           (connection-pool-in-use-set! pool
             (append (reverse rest) (cdr entries)))
           (cond
             [(connection-pool-closed? pool)
              ;; Pool closed: destroy connection
              (guard (exn [#t (void)])
                ((connection-pool-closer pool) conn))
              (connection-pool-total-set! pool
                (- (connection-pool-total pool) 1))
              (connection-pool-stats-destroyed-set! pool
                (+ (connection-pool-stats-destroyed pool) 1))]
             [else
              ;; Return to idle
              (connection-pool-idle-set! pool
                (cons entry (connection-pool-idle pool)))
              (connection-pool-stats-released-set! pool
                (+ (connection-pool-stats-released pool) 1))
              (condition-signal (connection-pool-not-empty pool))]))
         (mutex-release (connection-pool-mutex pool))]
        [else
         (loop (cdr entries) (cons (car entries) rest))])))

  (define (pool-size pool)
    (mutex-acquire (connection-pool-mutex pool))
    (let ([n (connection-pool-total pool)])
      (mutex-release (connection-pool-mutex pool))
      n))

  (define (pool-available pool)
    (mutex-acquire (connection-pool-mutex pool))
    (let ([n (length (connection-pool-idle pool))])
      (mutex-release (connection-pool-mutex pool))
      n))

  (define (pool-stats pool)
    (mutex-acquire (connection-pool-mutex pool))
    (let ([stats
           (list
             (cons 'total     (connection-pool-total pool))
             (cons 'idle      (length (connection-pool-idle pool)))
             (cons 'in-use    (length (connection-pool-in-use pool)))
             (cons 'acquired  (connection-pool-stats-acquired pool))
             (cons 'released  (connection-pool-stats-released pool))
             (cons 'created   (connection-pool-stats-created pool))
             (cons 'destroyed (connection-pool-stats-destroyed pool))
             (cons 'health-failures (connection-pool-stats-health-failures pool))
             (cons 'waits     (connection-pool-stats-waits pool)))])
      (mutex-release (connection-pool-mutex pool))
      stats))

  (define (pool-close! pool)
    (mutex-acquire (connection-pool-mutex pool))
    (connection-pool-closed?-set! pool #t)
    ;; Close all idle connections
    (for-each
      (lambda (entry)
        (guard (exn [#t (void)])
          ((connection-pool-closer pool) (pool-entry-conn entry)))
        (connection-pool-stats-destroyed-set! pool
          (+ (connection-pool-stats-destroyed pool) 1)))
      (connection-pool-idle pool))
    (connection-pool-idle-set! pool '())
    (connection-pool-total-set! pool
      (length (connection-pool-in-use pool)))
    ;; Signal any waiters so they can get the error
    (condition-broadcast (connection-pool-not-empty pool))
    (mutex-release (connection-pool-mutex pool)))

  (define (pool-health-check! pool)
    ;; Check all idle connections; remove unhealthy ones
    (let ([checker (connection-pool-checker pool)])
      (when checker
        (mutex-acquire (connection-pool-mutex pool))
        (let ([healthy '()] [bad '()])
          (for-each
            (lambda (entry)
              (let ([ok?
                     (guard (exn [#t #f])
                       (checker (pool-entry-conn entry)))])
                (if ok?
                  (begin
                    (pool-entry-healthy?-set! entry #t)
                    (set! healthy (cons entry healthy)))
                  (begin
                    (pool-entry-healthy?-set! entry #f)
                    (set! bad (cons entry bad))
                    (connection-pool-stats-health-failures-set! pool
                      (+ (connection-pool-stats-health-failures pool) 1))))))
            (connection-pool-idle pool))
          ;; Close unhealthy
          (for-each
            (lambda (entry)
              (guard (exn [#t (void)])
                ((connection-pool-closer pool) (pool-entry-conn entry)))
              (connection-pool-total-set! pool
                (- (connection-pool-total pool) 1))
              (connection-pool-stats-destroyed-set! pool
                (+ (connection-pool-stats-destroyed pool) 1)))
            bad)
          ;; Keep healthy
          (connection-pool-idle-set! pool (reverse healthy)))
        (mutex-release (connection-pool-mutex pool)))))

  (define (with-connection pool proc)
    (let ([conn (pool-acquire! pool)])
      (dynamic-wind
        (lambda () (void))
        (lambda () (proc conn))
        (lambda ()
          (guard (exn [#t (void)])
            (pool-release! pool conn))))))

) ;; end library
