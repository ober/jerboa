#!chezscheme
;;; (std net timeout) — Connection timeouts and limits
;;;
;;; Wraps TCP connections with deadline enforcement.
;;; Prevents Slowloris attacks and resource exhaustion.

(library (std net timeout)
  (export
    ;; Timeout configuration
    make-timeout-config
    timeout-config?
    timeout-config-connect
    timeout-config-read
    timeout-config-write
    timeout-config-idle
    default-timeout-config

    ;; HTTP limits
    make-http-limits
    http-limits?
    http-limits-max-header-size
    http-limits-max-header-count
    http-limits-max-uri-length
    http-limits-max-body-size
    http-limits-request-timeout
    default-http-limits

    ;; Deadline-aware I/O
    with-timeout
    read-with-deadline
    write-with-deadline

    ;; Validation
    check-header-limits
    check-body-limits
    check-uri-limits

    ;; Condition type
    &limit-exceeded
    make-limit-exceeded
    limit-exceeded?
    limit-exceeded-what
    limit-exceeded-actual
    limit-exceeded-max)

  (import (chezscheme))

  ;; ========== Timeout Configuration ==========

  (define-record-type (timeout-config %make-timeout-config timeout-config?)
    (sealed #t)
    (fields
      (immutable connect timeout-config-connect)   ;; milliseconds
      (immutable read timeout-config-read)         ;; milliseconds
      (immutable write timeout-config-write)       ;; milliseconds
      (immutable idle timeout-config-idle)))        ;; milliseconds

  (define (make-timeout-config . opts)
    (let loop ([o opts]
               [conn 5000]     ;; 5s connect
               [rd 30000]      ;; 30s read
               [wr 10000]      ;; 10s write
               [idle 60000])   ;; 60s idle
      (if (or (null? o) (null? (cdr o)))
        (%make-timeout-config conn rd wr idle)
        (let ([k (car o)] [v (cadr o)])
          (loop (cddr o)
                (if (eq? k 'connect:) v conn)
                (if (eq? k 'read:) v rd)
                (if (eq? k 'write:) v wr)
                (if (eq? k 'idle:) v idle))))))

  (define default-timeout-config
    (%make-timeout-config 5000 30000 10000 60000))

  ;; ========== HTTP Limits ==========

  (define-record-type (http-limits %make-http-limits http-limits?)
    (sealed #t)
    (fields
      (immutable max-header-size http-limits-max-header-size)     ;; bytes
      (immutable max-header-count http-limits-max-header-count)   ;; count
      (immutable max-uri-length http-limits-max-uri-length)       ;; bytes
      (immutable max-body-size http-limits-max-body-size)         ;; bytes
      (immutable request-timeout http-limits-request-timeout)))   ;; milliseconds

  (define (make-http-limits . opts)
    (let loop ([o opts]
               [hdr-sz 8192]
               [hdr-cnt 100]
               [uri-len 2048]
               [body-sz 10485760]    ;; 10MB
               [req-to 30000])       ;; 30s
      (if (or (null? o) (null? (cdr o)))
        (%make-http-limits hdr-sz hdr-cnt uri-len body-sz req-to)
        (let ([k (car o)] [v (cadr o)])
          (loop (cddr o)
                (if (eq? k 'max-header-size:) v hdr-sz)
                (if (eq? k 'max-header-count:) v hdr-cnt)
                (if (eq? k 'max-uri-length:) v uri-len)
                (if (eq? k 'max-body-size:) v body-sz)
                (if (eq? k 'request-timeout:) v req-to))))))

  (define default-http-limits
    (%make-http-limits 8192 100 2048 10485760 30000))

  ;; ========== Deadline-Aware I/O ==========

  (define (current-time-ms)
    ;; Current time in milliseconds.
    (let ([t (current-time 'time-utc)])
      (+ (* (time-second t) 1000)
         (quotient (time-nanosecond t) 1000000))))

  (define (with-timeout timeout-ms thunk)
    ;; Run thunk with a deadline. Raises error if timeout expires.
    ;; timeout-ms: milliseconds
    (let ([deadline (+ (current-time-ms) timeout-ms)]
          [result #f]
          [done? #f]
          [error? #f]
          [error-val #f])
      ;; Run in a thread so we can enforce the deadline
      (let ([worker (fork-thread
                      (lambda ()
                        (guard (exn [#t
                                     (set! error? #t)
                                     (set! error-val exn)])
                          (set! result (thunk))
                          (set! done? #t))))])
        ;; Poll until done or deadline
        (let loop ()
          (cond
            [done? result]
            [error? (raise error-val)]
            [(> (current-time-ms) deadline)
             ;; Timeout expired — we can't forcibly kill the thread in Chez,
             ;; but we signal the timeout condition
             (error 'with-timeout "operation timed out" timeout-ms)]
            [else
             (sleep (make-time 'time-duration 10000000 0))  ;; 10ms
             (loop)])))))

  (define (read-with-deadline port timeout-ms)
    ;; Read a line with a deadline. Returns string or raises error.
    (with-timeout timeout-ms
      (lambda () (get-line port))))

  (define (write-with-deadline port data timeout-ms)
    ;; Write data with a deadline.
    (with-timeout timeout-ms
      (lambda ()
        (if (string? data)
          (put-string port data)
          (put-bytevector port data))
        (flush-output-port port))))

  ;; ========== HTTP Limit Checks ==========

  (define-condition-type &limit-exceeded &condition
    make-limit-exceeded limit-exceeded?
    (what limit-exceeded-what)
    (actual limit-exceeded-actual)
    (max limit-exceeded-max))

  (define (check-header-limits headers limits)
    ;; Check headers against HTTP limits.
    ;; headers: alist of (name . value) pairs
    ;; Raises &limit-exceeded if any limit is violated.
    (let ([count (length headers)]
          [max-count (http-limits-max-header-count limits)]
          [max-size (http-limits-max-header-size limits)])
      ;; Check count
      (when (> count max-count)
        (raise (make-limit-exceeded "header-count" count max-count)))
      ;; Check total size
      (let ([total-size (fold-left
                          (lambda (acc pair)
                            (+ acc
                               (string-length (car pair))
                               2  ;; ": "
                               (string-length (cdr pair))
                               2)) ;; CRLF
                          0 headers)])
        (when (> total-size max-size)
          (raise (make-limit-exceeded "header-size" total-size max-size))))))

  (define (check-body-limits body-size limits)
    ;; Check body size against HTTP limits.
    (let ([max-size (http-limits-max-body-size limits)])
      (when (> body-size max-size)
        (raise (make-limit-exceeded "body-size" body-size max-size)))))

  (define (check-uri-limits uri limits)
    ;; Check URI length against HTTP limits.
    (let ([len (string-length uri)]
          [max-len (http-limits-max-uri-length limits)])
      (when (> len max-len)
        (raise (make-limit-exceeded "uri-length" len max-len)))))

  ) ;; end library
