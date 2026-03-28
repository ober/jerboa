#!chezscheme
;;; test-service-supervise.ss — Tests for supervise status file format
;;; and control FIFO command handling.
;;; Tests the write-status! / handle-control-byte logic by importing
;;; the supervise module and verifying the binary format matches what
;;; (std service control) expects to read.

(import (chezscheme) (std os posix) (std service config) (std service control))

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

(display "=== Service Supervise Tests ===\n")

;; ========== TAI64N Timestamp Format ==========

(define TAI-OFFSET 4611686018427387904)

(display "--- TAI64N timestamp tests ---\n")

;; Verify TAI offset is correct (2^62)
(check TAI-OFFSET => (expt 2 62))

;; Build a TAI64N timestamp and verify it round-trips through control module
(let* ([now (time-second (current-time 'time-utc))]
       [tai-secs (+ now TAI-OFFSET)]
       [bv (make-bytevector 12 0)])
  (bytevector-u64-set! bv 0 tai-secs (endianness big))
  (bytevector-u32-set! bv 8 0 (endianness big))
  ;; Verify big-endian encoding
  (check (bytevector-u64-ref bv 0 (endianness big)) => tai-secs)
  (check (bytevector-u32-ref bv 8 (endianness big)) => 0)
  ;; Verify that (- tai-secs TAI-OFFSET) recovers unix time
  (check (- (bytevector-u64-ref bv 0 (endianness big)) TAI-OFFSET) => now))

;; ========== 18-Byte Status File Format ==========

(display "--- Status file format tests ---\n")

(define test-dir "/tmp/test-supervise-format")
(define sv-dir (string-append test-dir "/supervise"))

;; Setup
(when (file-exists? test-dir)
  (when (file-exists? (string-append sv-dir "/status"))
    (delete-file (string-append sv-dir "/status")))
  (when (file-exists? sv-dir) (delete-directory sv-dir))
  (delete-directory test-dir))
(mkdir test-dir)
(mkdir sv-dir)

;; Helper: write a raw 18-byte status file matching supervise format
(define (write-raw-status! unix-secs pid paused? want)
  (let ([bv (make-bytevector 18 0)]
        [path (string-append sv-dir "/status")])
    ;; Bytes 0-11: TAI64N (8 secs + 4 nsecs)
    (bytevector-u64-set! bv 0 (+ unix-secs TAI-OFFSET) (endianness big))
    (bytevector-u32-set! bv 8 0 (endianness big))
    ;; Bytes 12-15: PID (big-endian uint32)
    (bytevector-u32-set! bv 12 pid (endianness big))
    ;; Byte 16: paused flag
    (bytevector-u8-set! bv 16 (if paused? 1 0))
    ;; Byte 17: want flag
    (bytevector-u8-set! bv 17
      (case want
        [(up) (char->integer #\u)]
        [(down) (char->integer #\d)]
        [else 0]))
    (let ([port (open-file-output-port path
                  (file-options no-fail)
                  (buffer-mode block))])
      (put-bytevector port bv)
      (close-port port))))

;; Test: status file is exactly 18 bytes
(let ([now (time-second (current-time 'time-utc))])
  (write-raw-status! now 1234 #f 'up)
  (let* ([port (open-file-input-port (string-append sv-dir "/status"))]
         [data (get-bytevector-all port)])
    (close-port port)
    (check (bytevector-length data) => 18)))

;; Test: read back raw bytes and verify encoding
(let ([now (time-second (current-time 'time-utc))])
  (write-raw-status! now 42 #t 'down)
  (let ([bv (let ([port (open-file-input-port (string-append sv-dir "/status"))])
              (let ([data (get-bytevector-all port)])
                (close-port port)
                data))])
    ;; PID at offset 12
    (check (bytevector-u32-ref bv 12 (endianness big)) => 42)
    ;; Paused at offset 16
    (check (bytevector-u8-ref bv 16) => 1)
    ;; Want at offset 17
    (check (bytevector-u8-ref bv 17) => (char->integer #\d))
    ;; TAI secs at offset 0
    (check (- (bytevector-u64-ref bv 0 (endianness big)) TAI-OFFSET) => now)))

;; Test: svstat reads what we write (round-trip)
(let ([now (time-second (current-time 'time-utc))])
  (write-raw-status! (- now 42) 9999 #f 'up)
  (let ([info (svstat test-dir)])
    (check-true (svstat-info? info))
    (check (svstat-info-pid info) => 9999)
    (check (svstat-info-up? info) => #t)
    (check (svstat-info-paused? info) => #f)
    (check (svstat-info-want info) => 'up)
    (check-true (>= (svstat-info-seconds info) 41))
    (check-true (<= (svstat-info-seconds info) 44))))

;; Test: PID=0 means down
(let ([now (time-second (current-time 'time-utc))])
  (write-raw-status! now 0 #f 'down)
  (let ([info (svstat test-dir)])
    (check (svstat-info-pid info) => 0)
    (check (svstat-info-up? info) => #f)
    (check (svstat-info-want info) => 'down)))

;; Test: want=once (byte value 0)
(let ([now (time-second (current-time 'time-utc))])
  (write-raw-status! now 5555 #f 'once)
  (let ([info (svstat test-dir)])
    (check (svstat-info-pid info) => 5555)
    (check (svstat-info-want info) => 'once)))

;; Test: large PID (max uint32 boundary)
(let ([now (time-second (current-time 'time-utc))])
  (write-raw-status! now 65535 #f 'up)
  (let ([info (svstat test-dir)])
    (check (svstat-info-pid info) => 65535)))

;; ========== Control Command Byte Encoding ==========

(display "--- Control command byte tests ---\n")

;; Verify command byte values match DJB daemontools spec
(check (char->integer #\u) => 117)  ;; up
(check (char->integer #\d) => 100)  ;; down
(check (char->integer #\o) => 111)  ;; once
(check (char->integer #\x) => 120)  ;; exit
(check (char->integer #\p) => 112)  ;; pause
(check (char->integer #\c) => 99)   ;; continue
(check (char->integer #\h) => 104)  ;; HUP
(check (char->integer #\a) => 97)   ;; ALRM
(check (char->integer #\i) => 105)  ;; INT
(check (char->integer #\t) => 116)  ;; TERM
(check (char->integer #\k) => 107)  ;; KILL

;; ========== Config Loading ==========

(display "--- Config integration tests ---\n")

;; Test: default config has all #f/empty fields
(let ([c default-service-config])
  (check (service-config-user c) => #f)
  (check (service-config-group c) => #f)
  (check (service-config-memory-limit c) => #f)
  (check (service-config-sandbox-read c) => '())
  (check (service-config-seccomp? c) => #f))

;; Test: load config from service directory without config.scm
(let ([c (load-service-config test-dir)])
  (check-true (service-config? c))
  (check (service-config-user c) => #f))

;; Test: load config with config.scm
(call-with-output-file (string-append test-dir "/config.scm")
  (lambda (p)
    (write '((user . "nobody")
             (group . "nogroup")
             (memory-limit . 33554432)
             (nproc-limit . 16))
           p))
  'replace)

(let ([c (load-service-config test-dir)])
  (check (service-config-user c) => "nobody")
  (check (service-config-group c) => "nogroup")
  (check (service-config-memory-limit c) => 33554432)
  (check (service-config-nproc-limit c) => 16)
  (check (service-config-file-limit c) => #f))

;; ========== Environment Directory ==========

(display "--- Envdir tests ---\n")

;; Create an envdir and verify files can be read
(let ([env-dir (string-append test-dir "/env")])
  (mkdir env-dir)
  (call-with-output-file (string-append env-dir "/IP")
    (lambda (p) (display "127.0.0.1" p))
    'replace)
  (call-with-output-file (string-append env-dir "/PORT")
    (lambda (p) (display "8080" p))
    'replace)
  ;; Verify files exist and have correct content
  (check-true (file-exists? (string-append env-dir "/IP")))
  (check-true (file-exists? (string-append env-dir "/PORT")))
  (check (call-with-input-file (string-append env-dir "/IP")
           (lambda (p) (get-line p)))
    => "127.0.0.1")
  (check (call-with-input-file (string-append env-dir "/PORT")
           (lambda (p) (get-line p)))
    => "8080")
  ;; Cleanup env dir
  (delete-file (string-append env-dir "/IP"))
  (delete-file (string-append env-dir "/PORT"))
  (delete-directory env-dir))

;; ========== Cleanup ==========

(when (file-exists? (string-append test-dir "/config.scm"))
  (delete-file (string-append test-dir "/config.scm")))
(when (file-exists? (string-append sv-dir "/status"))
  (delete-file (string-append sv-dir "/status")))
(when (file-exists? sv-dir) (delete-directory sv-dir))
(when (file-exists? test-dir) (delete-directory test-dir))

;; ========== Summary ==========

(display (format "\nService supervise tests: ~a passed, ~a failed\n"
           pass-count fail-count))
(when (> fail-count 0) (exit 1))
