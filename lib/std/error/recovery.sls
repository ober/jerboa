#!chezscheme
;;; (std error recovery) — Error recovery combinators
;;;
;;; Track 28 (continued): Retry, fallback, and cleanup combinators
;;; for building resilient programs.

(library (std error recovery)
  (export
    with-retry
    with-fallback
    with-cleanup
    with-timeout
    retry-on)

  (import (chezscheme))

  ;; ========== with-retry ==========
  ;; Retry thunk up to N times with optional delay between attempts.

  (define (with-retry thunk . opts)
    (let ([max-attempts (extract-opt opts 'attempts: 3)]
          [delay-ms     (extract-opt opts 'delay: 0)]
          [on-retry     (extract-opt opts 'on-retry: #f)]
          [pred         (extract-opt opts 'when: (lambda (e) #t))])
      (let lp ([attempt 1])
        (guard (exn
                 [#t
                  (if (and (< attempt max-attempts)
                           (pred exn))
                    (begin
                      (when on-retry
                        (on-retry exn attempt))
                      (when (> delay-ms 0)
                        (sleep (make-time 'time-duration
                                          (* delay-ms 1000000) 0)))
                      (lp (+ attempt 1)))
                    (raise exn))])
          (thunk)))))

  ;; ========== with-fallback ==========
  ;; Try primary, if it fails run fallback.

  (define (with-fallback primary fallback)
    (guard (exn [#t (fallback exn)])
      (primary)))

  ;; ========== with-cleanup ==========
  ;; Like dynamic-wind but only runs cleanup on error (not normal exit).

  (define (with-cleanup thunk cleanup)
    (let ([success? #f])
      (dynamic-wind
        void
        (lambda ()
          (let ([result (thunk)])
            (set! success? #t)
            result))
        (lambda ()
          (unless success?
            (guard (e [#t (void)])
              (cleanup)))))))

  ;; ========== with-timeout ==========
  ;; Run thunk with a timeout. If it doesn't complete in time,
  ;; raise a timeout error. Uses a watcher thread.

  (define (with-timeout thunk timeout-ms . rest)
    (let ([on-timeout (if (pair? rest) (car rest) #f)]
          [result-box (box #f)]
          [done (make-condition)]
          [mutex (make-mutex)]
          [finished? #f])
      ;; Start the computation
      (fork-thread
        (lambda ()
          (guard (e [#t
                     (with-mutex mutex
                       (set-box! result-box (cons 'error e))
                       (set! finished? #t)
                       (condition-signal done))])
            (let ([r (thunk)])
              (with-mutex mutex
                (set-box! result-box (cons 'ok r))
                (set! finished? #t)
                (condition-signal done))))))
      ;; Wait with timeout
      (mutex-acquire mutex)
      (unless finished?
        (condition-wait done mutex
          (make-time 'time-duration
                     (* (mod timeout-ms 1000) 1000000)
                     (div timeout-ms 1000))))
      (let ([result (unbox result-box)])
        (mutex-release mutex)
        (cond
          [(not result)
           ;; Timeout
           (if on-timeout
             (on-timeout)
             (error 'with-timeout
                    (format "operation timed out after ~a ms" timeout-ms)))]
          [(eq? (car result) 'ok)
           (cdr result)]
          [(eq? (car result) 'error)
           (raise (cdr result))]))))

  ;; ========== retry-on ==========
  ;; Predicate builder for with-retry's when: option.

  (define (retry-on . predicates)
    ;; Returns a predicate that matches any of the given conditions
    (lambda (exn)
      (exists (lambda (pred)
                (cond
                  [(procedure? pred) (pred exn)]
                  [(string? pred)
                   (and (message-condition? exn)
                        (string-contains (condition-message exn) pred))]
                  [else #f]))
              predicates)))

  (define (string-contains s sub)
    (let ([slen (string-length s)]
          [sublen (string-length sub)])
      (let lp ([i 0])
        (cond
          [(> (+ i sublen) slen) #f]
          [(string=? (substring s i (+ i sublen)) sub) #t]
          [else (lp (+ i 1))]))))

  (define (extract-opt opts key default)
    (let lp ([opts opts])
      (cond
        [(null? opts) default]
        [(and (pair? opts) (pair? (cdr opts)) (eq? (car opts) key))
         (cadr opts)]
        [(pair? opts) (lp (cdr opts))]
        [else default])))

  ) ;; end library
