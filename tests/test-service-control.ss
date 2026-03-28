#!chezscheme
;;; test-service-control.ss — Tests for (std service control)
;;; Tests status file reading/decoding and svstat formatting.
;;; Control commands require a running supervise, so we test the
;;; status reading/formatting by writing synthetic status files.

(import (chezscheme) (std os posix) (std service control))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr]
           [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: ")
           (write 'expr)
           (display " => ")
           (write result)
           (display " expected ")
           (write exp)
           (newline))))]))

(define-syntax check-true
  (syntax-rules ()
    [(_ expr)
     (if expr
       (set! pass-count (+ pass-count 1))
       (begin
         (set! fail-count (+ fail-count 1))
         (display "FAIL: ")
         (write 'expr)
         (display " => #f (expected #t)\n")))]))

;; Simple string search (Chez doesn't have string-search)
(define (str-contains? haystack needle)
  (let ([hlen (string-length haystack)]
        [nlen (string-length needle)])
    (let loop ([i 0])
      (cond
        [(> (+ i nlen) hlen) #f]
        [(string=? (substring haystack i (+ i nlen)) needle) #t]
        [else (loop (+ i 1))]))))

(display "=== Service Control Tests ===\n")

;; ========== Setup ==========

(define TAI-OFFSET 4611686018427387904)

(define test-dir "/tmp/test-service-control")
(define sv-dir (string-append test-dir "/supervise"))

;; Create test service directory structure
(when (file-exists? test-dir)
  (when (file-exists? (string-append sv-dir "/status"))
    (delete-file (string-append sv-dir "/status")))
  (when (file-exists? (string-append sv-dir "/control"))
    (delete-file (string-append sv-dir "/control")))
  (when (file-exists? (string-append sv-dir "/ok"))
    (delete-file (string-append sv-dir "/ok")))
  (when (file-exists? sv-dir) (delete-directory sv-dir))
  (delete-directory test-dir))

(mkdir test-dir)
(mkdir sv-dir)

;; Helper: write a synthetic 18-byte status file
(define (write-test-status! unix-secs pid paused? want)
  (let ([bv (make-bytevector 18 0)]
        [status-path (string-append sv-dir "/status")]
        [tai-secs (+ unix-secs TAI-OFFSET)])
    ;; TAI64N timestamp (12 bytes: 8 secs + 4 nsecs)
    (bytevector-u64-set! bv 0 tai-secs (endianness big))
    (bytevector-u32-set! bv 8 0 (endianness big))  ;; nsecs = 0
    ;; PID (big-endian uint32)
    (bytevector-u32-set! bv 12 pid (endianness big))
    ;; Paused flag
    (bytevector-u8-set! bv 16 (if paused? 1 0))
    ;; Want flag
    (bytevector-u8-set! bv 17
      (case want
        [(up) (char->integer #\u)]
        [(down) (char->integer #\d)]
        [else 0]))
    ;; Write file
    (let ([port (open-file-output-port status-path
                  (file-options no-fail)
                  (buffer-mode block))])
      (put-bytevector port bv)
      (close-port port))))

;; ========== svstat-info Record ==========

(let ([info (make-svstat-info 1234 #t #f 'up 42)])
  (check-true (svstat-info? info))
  (check (svstat-info-pid info) => 1234)
  (check (svstat-info-up? info) => #t)
  (check (svstat-info-paused? info) => #f)
  (check (svstat-info-want info) => 'up)
  (check (svstat-info-seconds info) => 42))

;; ========== Status Reading: Process Up ==========

(let ([now (time-second (current-time 'time-utc))])
  ;; Write status: pid=4242, up, not paused, want=up, started 10 seconds ago
  (write-test-status! (- now 10) 4242 #f 'up)

  (let ([info (svstat test-dir)])
    (check-true (svstat-info? info))
    (check (svstat-info-pid info) => 4242)
    (check (svstat-info-up? info) => #t)
    (check (svstat-info-paused? info) => #f)
    (check (svstat-info-want info) => 'up)
    ;; Elapsed should be approximately 10 seconds (allow 1s tolerance)
    (check-true (>= (svstat-info-seconds info) 9))
    (check-true (<= (svstat-info-seconds info) 12))))

;; ========== Status Reading: Process Down ==========

(let ([now (time-second (current-time 'time-utc))])
  (write-test-status! (- now 5) 0 #f 'down)

  (let ([info (svstat test-dir)])
    (check-true (svstat-info? info))
    (check (svstat-info-pid info) => 0)
    (check (svstat-info-up? info) => #f)
    (check (svstat-info-paused? info) => #f)
    (check (svstat-info-want info) => 'down)
    (check-true (>= (svstat-info-seconds info) 4))
    (check-true (<= (svstat-info-seconds info) 7))))

;; ========== Status Reading: Paused ==========

(let ([now (time-second (current-time 'time-utc))])
  (write-test-status! (- now 3) 9999 #t 'up)

  (let ([info (svstat test-dir)])
    (check (svstat-info-pid info) => 9999)
    (check (svstat-info-up? info) => #t)
    (check (svstat-info-paused? info) => #t)
    (check (svstat-info-want info) => 'up)))

;; ========== Status Reading: Want Down (stopping) ==========

(let ([now (time-second (current-time 'time-utc))])
  (write-test-status! (- now 1) 5555 #f 'down)

  (let ([info (svstat test-dir)])
    (check (svstat-info-pid info) => 5555)
    (check (svstat-info-up? info) => #t)
    (check (svstat-info-want info) => 'down)))

;; ========== Status Reading: Once mode ==========

(let ([now (time-second (current-time 'time-utc))])
  (write-test-status! now 7777 #f 'once)

  (let ([info (svstat test-dir)])
    (check (svstat-info-pid info) => 7777)
    (check (svstat-info-up? info) => #t)
    (check (svstat-info-want info) => 'once)))

;; ========== svstat-string Formatting ==========

(let ([now (time-second (current-time 'time-utc))])
  ;; Up, running normally
  (write-test-status! (- now 100) 1234 #f 'up)
  (let ([s (svstat-string test-dir)])
    (check-true (string? s))
    ;; Should contain "up" and "pid"
    (check-true (str-contains? s "up"))
    (check-true (str-contains? s "pid 1234"))
    (check-true (str-contains? s "seconds"))))

(let ([now (time-second (current-time 'time-utc))])
  ;; Down
  (write-test-status! (- now 30) 0 #f 'up)
  (let ([s (svstat-string test-dir)])
    (check-true (str-contains? s "down"))
    (check-true (str-contains? s "want up"))))

(let ([now (time-second (current-time 'time-utc))])
  ;; Up but paused, want down
  (write-test-status! (- now 5) 8888 #t 'down)
  (let ([s (svstat-string test-dir)])
    (check-true (str-contains? s "paused"))
    (check-true (str-contains? s "want down"))))

;; ========== svstat: Missing Status File ==========

(delete-file (string-append sv-dir "/status"))
(let ([info (svstat test-dir)])
  (check info => #f))

;; svstat-string should handle missing status gracefully
(let ([s (svstat-string test-dir)])
  (check-true (str-contains? s "unable to read")))

;; ========== svok?: No supervise running ==========

;; Without a FIFO, svok? should return #f
(check (svok? test-dir) => #f)

;; ========== Cleanup ==========

(when (file-exists? (string-append sv-dir "/status"))
  (delete-file (string-append sv-dir "/status")))
(when (file-exists? sv-dir)
  (delete-directory sv-dir))
(when (file-exists? test-dir)
  (delete-directory test-dir))

;; ========== Summary ==========

(display (format "\nService control tests: ~a passed, ~a failed\n"
           pass-count fail-count))
(when (> fail-count 0) (exit 1))
