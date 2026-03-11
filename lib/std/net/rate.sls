#!chezscheme
;;; (std net rate) -- Rate limiting
;;;
;;; Token bucket, sliding window, fixed window, and thread-safe rate limiter.

(library (std net rate)
  (export
    ;; Token bucket
    make-token-bucket token-bucket? token-bucket-try! token-bucket-consume!
    token-bucket-tokens
    ;; Sliding window
    make-sliding-window sliding-window? sliding-window-try! sliding-window-count
    ;; Fixed window
    make-fixed-window fixed-window? fixed-window-try! fixed-window-count
    ;; Rate limiter (thread-safe wrapper)
    make-rate-limiter rate-limiter? rate-limiter-try! rate-limiter-wait!)

  (import (chezscheme))

  ;;; ========== Time utility ==========
  ;; Returns current time as a real-number (seconds since epoch).
  (define (now-seconds)
    (let ([t (current-time 'time-utc)])
      (+ (time-second t) (/ (time-nanosecond t) 1000000000.0))))

  ;;; ========== Token Bucket ==========
  ;; capacity: max tokens (integer or real)
  ;; rate:     tokens per second to add
  ;; tokens:   current token count (mutable)
  ;; last:     last refill time as real seconds (mutable)
  (define-record-type token-bucket-rec
    (fields capacity rate (mutable tokens) (mutable last))
    (protocol
      (lambda (new)
        (lambda (capacity rate)
          (new capacity rate (exact->inexact capacity) (now-seconds))))))

  (define (token-bucket? x) (token-bucket-rec? x))

  (define (make-token-bucket capacity rate)
    (make-token-bucket-rec capacity rate))

  ;; Refill tokens based on elapsed time.
  (define (token-bucket-refill! tb)
    (let* ([n        (now-seconds)]
           [elapsed  (- n (token-bucket-rec-last tb))]
           [rate     (token-bucket-rec-rate tb)]
           [cap      (exact->inexact (token-bucket-rec-capacity tb))]
           [new-toks (min cap (+ (token-bucket-rec-tokens tb)
                                 (* elapsed (exact->inexact rate))))])
      (token-bucket-rec-tokens-set! tb new-toks)
      (token-bucket-rec-last-set!   tb n)))

  ;; Return current token count (after refill).
  (define (token-bucket-tokens tb)
    (token-bucket-refill! tb)
    (token-bucket-rec-tokens tb))

  ;; Try to consume 1 token. Returns #t if available, #f otherwise.
  (define (token-bucket-try! tb)
    (token-bucket-refill! tb)
    (let ([toks (token-bucket-rec-tokens tb)])
      (if (>= toks 1.0)
        (begin
          (token-bucket-rec-tokens-set! tb (- toks 1.0))
          #t)
        #f)))

  ;; Try to consume n tokens. Returns #t if available, #f otherwise.
  (define (token-bucket-consume! tb n)
    (token-bucket-refill! tb)
    (let* ([toks    (token-bucket-rec-tokens tb)]
           [n-real  (exact->inexact n)])
      (if (>= toks n-real)
        (begin
          (token-bucket-rec-tokens-set! tb (- toks n-real))
          #t)
        #f)))

  ;;; ========== Sliding Window ==========
  ;; Allows up to `limit` requests in the last `window-seconds` seconds.
  ;; Timestamps stored as a list of real-number seconds.
  (define-record-type sliding-window-rec
    (fields limit window-seconds (mutable timestamps))
    (protocol
      (lambda (new)
        (lambda (limit window-seconds)
          (new limit window-seconds '())))))

  (define (sliding-window? x) (sliding-window-rec? x))

  (define (make-sliding-window limit window-seconds)
    (make-sliding-window-rec limit window-seconds))

  ;; Remove timestamps older than window-seconds ago.
  (define (sliding-window-prune! sw)
    (let* ([cutoff   (- (now-seconds) (exact->inexact (sliding-window-rec-window-seconds sw)))]
           [new-ts   (filter (lambda (t) (>= t cutoff))
                             (sliding-window-rec-timestamps sw))])
      (sliding-window-rec-timestamps-set! sw new-ts)))

  ;; Return count of requests in current window.
  (define (sliding-window-count sw)
    (sliding-window-prune! sw)
    (length (sliding-window-rec-timestamps sw)))

  ;; Try to allow a request. Returns #t if within limit, #f otherwise.
  (define (sliding-window-try! sw)
    (sliding-window-prune! sw)
    (let ([count (length (sliding-window-rec-timestamps sw))]
          [limit (sliding-window-rec-limit sw)])
      (if (< count limit)
        (begin
          (sliding-window-rec-timestamps-set! sw
            (cons (now-seconds) (sliding-window-rec-timestamps sw)))
          #t)
        #f)))

  ;;; ========== Fixed Window ==========
  ;; Allows up to `limit` requests per window of `window-seconds`.
  ;; Window number = floor(now / window-seconds).
  (define-record-type fixed-window-rec
    (fields limit window-seconds (mutable current-window) (mutable count))
    (protocol
      (lambda (new)
        (lambda (limit window-seconds)
          (new limit window-seconds -1 0)))))

  (define (fixed-window? x) (fixed-window-rec? x))

  (define (make-fixed-window limit window-seconds)
    (make-fixed-window-rec limit window-seconds))

  ;; Compute current window number.
  (define (fixed-window-number fw)
    (let ([ws (exact->inexact (fixed-window-rec-window-seconds fw))])
      (exact (floor (/ (now-seconds) ws)))))

  ;; Return count of requests in current window.
  (define (fixed-window-count fw)
    (let ([w (fixed-window-number fw)])
      (if (= w (fixed-window-rec-current-window fw))
        (fixed-window-rec-count fw)
        0)))

  ;; Try to allow a request. Returns #t if within limit, #f otherwise.
  (define (fixed-window-try! fw)
    (let* ([w     (fixed-window-number fw)]
           [curr  (fixed-window-rec-current-window fw)]
           [count (if (= w curr) (fixed-window-rec-count fw) 0)]
           [limit (fixed-window-rec-limit fw)])
      (when (not (= w curr))
        (fixed-window-rec-current-window-set! fw w)
        (fixed-window-rec-count-set! fw 0))
      (if (< count limit)
        (begin
          (fixed-window-rec-count-set! fw (+ count 1))
          #t)
        #f)))

  ;;; ========== Rate Limiter (thread-safe token bucket) ==========
  (define-record-type rate-limiter-rec
    (fields bucket mutex)
    (protocol
      (lambda (new)
        (lambda (capacity rate)
          (new (make-token-bucket capacity rate)
               (make-mutex))))))

  (define (rate-limiter? x) (rate-limiter-rec? x))

  (define (make-rate-limiter capacity rate)
    (make-rate-limiter-rec capacity rate))

  ;; Try to consume a token (thread-safe). Returns #t/#f.
  (define (rate-limiter-try! rl)
    (with-mutex (rate-limiter-rec-mutex rl)
      (token-bucket-try! (rate-limiter-rec-bucket rl))))

  ;; Wait until a token is available, then consume it.
  (define (rate-limiter-wait! rl)
    (let loop ()
      (unless (rate-limiter-try! rl)
        (sleep (make-time 'time-duration 100000000 0))  ; 100ms
        (loop))))

) ;; end library
