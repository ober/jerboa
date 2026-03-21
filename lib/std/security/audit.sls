#!chezscheme
;;; (std security audit) — Structured, tamper-evident audit logging
;;;
;;; Append-only audit log with hash chain. Each entry includes the SHA-256
;;; hash of the previous entry, making tampering detectable. Outputs JSONL
;;; format for machine consumption.

(library (std security audit)
  (export
    make-audit-logger
    audit-log!
    audit-logger?
    audit-logger-close!
    check-capability!/audit
    audit-event-types
    verify-audit-chain)

  (import (chezscheme)
          (std crypto digest)
          (std crypto random))

  ;; ========== Audit Logger Record ==========

  (define-record-type (%audit-logger %make-audit-logger audit-logger?)
    (sealed #t)
    (opaque #t)
    (fields
      (immutable port %audit-logger-port)
      (immutable id %audit-logger-id)
      (mutable prev-hash %audit-logger-prev-hash %audit-logger-prev-hash-set!)
      (mutable seq %audit-logger-seq %audit-logger-seq-set!)
      (immutable mutex %audit-logger-mutex)))

  ;; Standard event types
  (define audit-event-types
    '(auth-attempt auth-success auth-failure
      capability-check capability-grant capability-deny
      file-access file-modify file-delete
      net-connect net-listen
      process-spawn process-signal
      config-change
      sandbox-enter sandbox-exit sandbox-violation
      error critical))

  ;; ========== Logger Creation ==========

  (define (make-audit-logger path)
    ;; Create an audit logger that writes JSONL to the specified file.
    ;; Each entry includes a hash chain for tamper detection.
    (let ([port (open-file-output-port path
                  (file-options no-fail append)
                  (buffer-mode line)
                  (native-transcoder))]
          [logger-id (random-token 8)])
      (%make-audit-logger port logger-id
        "0000000000000000000000000000000000000000000000000000000000000000"
        0
        (make-mutex))))

  ;; ========== Logging ==========

  (define (audit-log! logger event-type . fields)
    ;; Log an audit event. Thread-safe via mutex.
    ;; fields: flat keyword list, e.g., 'actor: "user1" 'resource: "/etc/passwd"
    (with-mutex (%audit-logger-mutex logger)
      (let* ([seq (%audit-logger-seq logger)]
             [prev (%audit-logger-prev-hash logger)]
             [ts (current-time-string)]
             [event-str (symbol->string event-type)]
             [fields-json (fields->json fields)]
             ;; Build the log entry
             [entry (string-append
                      "{\"seq\":" (number->string seq)
                      ",\"ts\":\"" ts "\""
                      ",\"event\":\"" event-str "\""
                      ",\"logger\":\"" (%audit-logger-id logger) "\""
                      fields-json
                      ",\"prev\":\"" prev "\""
                      "}")]
             ;; Hash this entry for chain
             [entry-hash (sha256 entry)])
        ;; Write entry
        (display entry (%audit-logger-port logger))
        (newline (%audit-logger-port logger))
        (flush-output-port (%audit-logger-port logger))
        ;; Update chain state
        (%audit-logger-prev-hash-set! logger entry-hash)
        (%audit-logger-seq-set! logger (+ seq 1)))))

  (define (audit-logger-close! logger)
    (with-mutex (%audit-logger-mutex logger)
      (close-port (%audit-logger-port logger))))

  ;; ========== Capability Check with Audit ==========

  (define (check-capability!/audit logger cap-check-thunk event-type . detail)
    ;; Wrapper that logs capability check results.
    ;; cap-check-thunk: (lambda () ...) that raises on failure
    (guard (exn
      [#t
        (apply audit-log! logger 'capability-deny
          'event-type: (symbol->string event-type)
          'result: "deny"
          detail)
        (raise exn)])
      (cap-check-thunk)
      (apply audit-log! logger 'capability-grant
        'event-type: (symbol->string event-type)
        'result: "grant"
        detail)))

  ;; ========== Chain Verification ==========

  (define (verify-audit-chain path)
    ;; Read a JSONL audit log and verify the hash chain.
    ;; Returns #t if chain is intact, or (broken-at . seq-number) if tampered.
    (let ([port (open-input-file path)])
      (let loop ([prev "0000000000000000000000000000000000000000000000000000000000000000"]
                 [line-num 0])
        (let ([line (get-line port)])
          (if (eof-object? line)
            (begin (close-port port) #t)
            (let* ([entry-hash (sha256 line)]
                   [prev-in-entry (extract-prev-hash line)])
              (if (string=? prev-in-entry prev)
                (loop entry-hash (+ line-num 1))
                (begin
                  (close-port port)
                  (cons 'broken-at line-num)))))))))

  ;; ========== Helpers ==========

  (define (current-time-string)
    ;; ISO 8601 timestamp
    (let ([t (current-time 'time-utc)])
      (let* ([secs (time-second t)]
             [date (time-utc->date t 0)])
        (format "~4,'0d-~2,'0d-~2,'0dT~2,'0d:~2,'0d:~2,'0dZ"
          (date-year date) (date-month date) (date-day date)
          (date-hour date) (date-minute date) (date-second date)))))

  (define (fields->json fields)
    ;; Convert flat keyword list to JSON fields string.
    ;; e.g., ('actor: "user1" 'resource: "/foo") -> ",\"actor\":\"user1\",\"resource\":\"/foo\""
    (let loop ([f fields] [acc ""])
      (if (or (null? f) (null? (cdr f)))
        acc
        (let* ([key (car f)]
               [val (cadr f)]
               [key-str (let ([s (symbol->string key)])
                          ;; Remove trailing colon if present
                          (if (and (> (string-length s) 0)
                                   (char=? (string-ref s (- (string-length s) 1)) #\:))
                            (substring s 0 (- (string-length s) 1))
                            s))]
               [val-str (if (string? val) val (format "~a" val))])
          (loop (cddr f)
                (string-append acc ",\"" key-str "\":\"" (json-escape val-str) "\""))))))

  (define (json-escape s)
    ;; Escape special JSON characters
    (let ([out (open-output-string)])
      (string-for-each
        (lambda (c)
          (case c
            [(#\") (display "\\\"" out)]
            [(#\\) (display "\\\\" out)]
            [(#\newline) (display "\\n" out)]
            [(#\return) (display "\\r" out)]
            [(#\tab) (display "\\t" out)]
            [else (write-char c out)]))
        s)
      (get-output-string out)))

  (define (extract-prev-hash line)
    ;; Extract the "prev":"..." value from a JSON line.
    ;; Simple: find "prev":" and extract the 64-char hex string after it.
    (let* ([marker "\"prev\":\""]
           [mlen (string-length marker)]
           [llen (string-length line)])
      (let loop ([i 0])
        (cond
          [(> (+ i mlen 64) llen)
           ""]
          [(string=? (substring line i (+ i mlen)) marker)
           (substring line (+ i mlen) (+ i mlen 64))]
          [else (loop (+ i 1))]))))

  ) ;; end library
