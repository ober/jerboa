#!chezscheme
;;; (std misc rate-limiter) -- Token Bucket Rate Limiter
;;;
;;; Token bucket algorithm for rate limiting API calls and resource access.
;;;
;;; Usage:
;;;   (import (std misc rate-limiter))
;;;   (define limiter (make-rate-limiter 10 1.0))  ;; 10 tokens, 1 per second refill
;;;   (rate-limiter-acquire! limiter)   ;; blocks until token available
;;;   (rate-limiter-try-acquire limiter) ;; returns #t/#f without blocking
;;;   (with-rate-limit limiter (lambda () (api-call)))

(library (std misc rate-limiter)
  (export
    make-rate-limiter
    rate-limiter?
    rate-limiter-acquire!
    rate-limiter-try-acquire
    rate-limiter-available
    rate-limiter-reset!
    with-rate-limit)

  (import (chezscheme))

  (define-record-type rate-limiter-rec
    (fields (immutable capacity)      ;; max tokens
            (immutable refill-rate)    ;; tokens per second
            (mutable tokens)           ;; current tokens (flonum)
            (mutable last-refill)      ;; timestamp of last refill
            (immutable mutex))
    (protocol (lambda (new)
      (lambda (capacity refill-rate)
        (new capacity (inexact refill-rate) (inexact capacity)
             (current-seconds) (make-mutex))))))

  (define (make-rate-limiter capacity refill-rate)
    (make-rate-limiter-rec capacity refill-rate))

  (define (rate-limiter? x) (rate-limiter-rec? x))

  (define (refill! rl)
    ;; Add tokens based on elapsed time
    (let* ([now (current-seconds)]
           [elapsed (- now (rate-limiter-rec-last-refill rl))]
           [new-tokens (+ (rate-limiter-rec-tokens rl)
                          (* elapsed (rate-limiter-rec-refill-rate rl)))]
           [capped (min new-tokens (inexact (rate-limiter-rec-capacity rl)))])
      (rate-limiter-rec-tokens-set! rl capped)
      (rate-limiter-rec-last-refill-set! rl now)))

  (define (rate-limiter-try-acquire rl)
    ;; Try to take a token. Returns #t if successful, #f if no tokens.
    (with-mutex (rate-limiter-rec-mutex rl)
      (refill! rl)
      (if (>= (rate-limiter-rec-tokens rl) 1.0)
        (begin
          (rate-limiter-rec-tokens-set! rl (- (rate-limiter-rec-tokens rl) 1.0))
          #t)
        #f)))

  (define (rate-limiter-acquire! rl)
    ;; Block until a token is available
    (let loop ()
      (if (rate-limiter-try-acquire rl)
        (void)
        (begin
          ;; Sleep a bit based on refill rate
          (let ([wait (/ 1.0 (rate-limiter-rec-refill-rate rl))])
            (sleep-seconds (min wait 0.1)))
          (loop)))))

  (define (rate-limiter-available rl)
    ;; Return current available tokens (approximate)
    (with-mutex (rate-limiter-rec-mutex rl)
      (refill! rl)
      (exact (floor (rate-limiter-rec-tokens rl)))))

  (define (rate-limiter-reset! rl)
    ;; Reset to full capacity
    (with-mutex (rate-limiter-rec-mutex rl)
      (rate-limiter-rec-tokens-set! rl (inexact (rate-limiter-rec-capacity rl)))
      (rate-limiter-rec-last-refill-set! rl (current-seconds))))

  (define (with-rate-limit rl thunk)
    ;; Acquire a token, then run thunk
    (rate-limiter-acquire! rl)
    (thunk))

  ;; ========== Helpers ==========
  (define (current-seconds)
    (let ([t (current-time)])
      (+ (time-second t) (/ (time-nanosecond t) 1000000000.0))))

  (define (sleep-seconds secs)
    (let* ([whole (exact (floor secs))]
           [frac (- secs whole)]
           [nanos (exact (round (* frac 1000000000)))])
      (sleep (make-time 'time-duration nanos whole))))

) ;; end library
