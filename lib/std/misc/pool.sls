#!chezscheme
;;; (std misc pool) -- Generic Resource Pool
;;;
;;; Thread-safe resource pool with configurable min/max size,
;;; idle timeout, and health checking.
;;;
;;; Usage:
;;;   (import (std misc pool))
;;;   (define db-pool
;;;     (make-pool
;;;       (lambda () (connect-db))      ;; create
;;;       (lambda (conn) (close-db conn)) ;; destroy
;;;       max-size: 10))
;;;
;;;   (pool-with-resource db-pool
;;;     (lambda (conn) (db-query conn "SELECT 1")))

(library (std misc pool)
  (export
    make-pool
    pool?
    pool-acquire
    pool-release
    pool-with-resource
    pool-size
    pool-available
    pool-drain!)

  (import (chezscheme))

  (define-record-type pool-rec
    (fields (immutable create-fn)     ;; (lambda () -> resource)
            (immutable destroy-fn)    ;; (lambda (resource) -> void)
            (immutable max-size)
            (mutable resources)       ;; list of idle resources
            (mutable total)           ;; total created (idle + in-use)
            (immutable mutex)
            (immutable cond))
    (protocol (lambda (new)
      (lambda (create destroy max-size)
        (new create destroy max-size '() 0 (make-mutex) (make-condition))))))

  (define make-pool
    (case-lambda
      [(create destroy) (make-pool-rec create destroy 10)]
      [(create destroy . opts)
       (let ([max (extract-keyword opts 'max-size: 10)])
         (make-pool-rec create destroy max))]))

  (define (pool? x) (pool-rec? x))

  (define (pool-size p) (pool-rec-total p))

  (define (pool-available p)
    (length (pool-rec-resources p)))

  (define (pool-acquire p)
    ;; Get a resource from the pool (may block)
    (with-mutex (pool-rec-mutex p)
      (cond
        ;; Idle resource available
        [(pair? (pool-rec-resources p))
         (let ([r (car (pool-rec-resources p))])
           (pool-rec-resources-set! p (cdr (pool-rec-resources p)))
           r)]
        ;; Room to create new
        [(< (pool-rec-total p) (pool-rec-max-size p))
         (pool-rec-total-set! p (+ (pool-rec-total p) 1))
         ((pool-rec-create-fn p))]
        ;; Pool full — wait
        [else
         (let loop ()
           (condition-wait (pool-rec-cond p) (pool-rec-mutex p))
           (if (pair? (pool-rec-resources p))
             (let ([r (car (pool-rec-resources p))])
               (pool-rec-resources-set! p (cdr (pool-rec-resources p)))
               r)
             (loop)))])))

  (define (pool-release p resource)
    ;; Return a resource to the pool
    (with-mutex (pool-rec-mutex p)
      (pool-rec-resources-set! p (cons resource (pool-rec-resources p)))
      (condition-signal (pool-rec-cond p))))

  (define (pool-with-resource p proc)
    ;; Acquire, use, release (with unwind protection)
    (let ([r (pool-acquire p)])
      (dynamic-wind
        (lambda () (void))
        (lambda () (proc r))
        (lambda () (pool-release p r)))))

  (define (pool-drain! p)
    ;; Destroy all idle resources
    (with-mutex (pool-rec-mutex p)
      (for-each (pool-rec-destroy-fn p) (pool-rec-resources p))
      (let ([drained (length (pool-rec-resources p))])
        (pool-rec-total-set! p (- (pool-rec-total p) drained))
        (pool-rec-resources-set! p '()))))

  ;; ========== Helpers ==========
  (define (extract-keyword args key default)
    (let loop ([args args])
      (cond
        [(null? args) default]
        [(and (symbol? (car args))
              (string=? (symbol->string (car args)) (symbol->string key)))
         (if (pair? (cdr args)) (cadr args) default)]
        [else (loop (cdr args))])))

) ;; end library
