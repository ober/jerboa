#!chezscheme
;;; test-audit.ss -- Tests for (std security audit)

(import (chezscheme) (std security audit))

(define pass-count 0)
(define fail-count 0)

(define-syntax check
  (syntax-rules (=>)
    [(_ expr => expected)
     (let ([result expr] [exp expected])
       (if (equal? result exp)
         (set! pass-count (+ pass-count 1))
         (begin
           (set! fail-count (+ fail-count 1))
           (display "FAIL: ") (write 'expr)
           (display " => ") (write result)
           (display " expected ") (write exp) (newline))))]))

(define (string-contains s sub)
  (let ([slen (string-length s)] [sublen (string-length sub)])
    (let lp ([i 0])
      (cond [(> (+ i sublen) slen) #f]
            [(string=? (substring s i (+ i sublen)) sub) i]
            [else (lp (+ i 1))]))))

(define (string-replace s old new)
  (let ([olen (string-length old)] [slen (string-length s)])
    (let lp ([i 0] [parts '()])
      (cond
        [(> (+ i olen) slen)
         (apply string-append (reverse (cons (substring s i slen) parts)))]
        [(string=? (substring s i (+ i olen)) old)
         (lp (+ i olen) (cons new parts))]
        [else (lp (+ i 1)
                  (if (null? parts)
                    (list (substring s i (+ i 1)))
                    (let ([last (car parts)])
                      (cons (string-append last (substring s i (+ i 1)))
                            (cdr parts)))))]))))

(define log-path "/tmp/jerboa-audit-test.jsonl")

;; Clean up
(guard (e [#t (void)]) (delete-file log-path))

;; Basic creation
(define logger (make-audit-logger log-path))
(check (audit-logger? logger) => #t)
(check (audit-logger? "not-a-logger") => #f)
(check (audit-logger? 42) => #f)

;; Log events
(audit-log! logger 'auth-attempt 'actor: "user1" 'resource: "login")
(audit-log! logger 'auth-success 'actor: "user1")
(audit-log! logger 'file-access 'actor: "user1" 'resource: "/etc/config")
(audit-log! logger 'capability-deny 'actor: "attacker" 'resource: "write /root")

(audit-logger-close! logger)

;; Verify chain integrity
(check (verify-audit-chain log-path) => #t)

;; Check that entries were written (4 lines)
(let ([line-count (call-with-input-file log-path
                    (lambda (p)
                      (let loop ([n 0])
                        (if (eof-object? (get-line p)) n
                          (loop (+ n 1))))))])
  (check line-count => 4))

;; Check that entries contain expected fields
(let ([first-line (call-with-input-file log-path
                    (lambda (p) (get-line p)))])
  ;; Contains seq, ts, event, logger, actor, resource, prev
  (check (and (string-contains first-line "\"seq\":0") #t) => #t)
  (check (and (string-contains first-line "\"event\":\"auth-attempt\"") #t) => #t)
  (check (and (string-contains first-line "\"actor\":\"user1\"") #t) => #t)
  (check (and (string-contains first-line "\"resource\":\"login\"") #t) => #t)
  (check (and (string-contains first-line "\"prev\":\"0000") #t) => #t))

;; Tamper detection: modify a line and verify chain breaks
(let ([lines (call-with-input-file log-path
               (lambda (p)
                 (let loop ([acc '()])
                   (let ([line (get-line p)])
                     (if (eof-object? line) (reverse acc)
                       (loop (cons line acc)))))))])
  ;; Write tampered log (modify line 1)
  (let ([tampered-path "/tmp/jerboa-audit-tampered.jsonl"])
    (guard (e [#t (void)]) (delete-file tampered-path))
    (call-with-output-file tampered-path
      (lambda (p)
        (display (car lines) p) (newline p)
        ;; Tamper: change "auth-success" to "auth-failure"
        (display (string-replace (cadr lines) "auth-success" "TAMPERED") p) (newline p)
        (for-each (lambda (l) (display l p) (newline p)) (cddr lines)))
      'truncate)
    (let ([result (verify-audit-chain tampered-path)])
      (check (pair? result) => #t)
      (check (eq? (car result) 'broken-at) => #t))
    (delete-file tampered-path)))

;; JSON escaping
(let ([logger2 (make-audit-logger "/tmp/jerboa-audit-escape.jsonl")])
  (audit-log! logger2 'error 'detail: "line1\nline2")
  (audit-log! logger2 'error 'detail: "quote\"here")
  (audit-logger-close! logger2)
  (check (verify-audit-chain "/tmp/jerboa-audit-escape.jsonl") => #t)
  (delete-file "/tmp/jerboa-audit-escape.jsonl"))

;; audit-event-types is a list
(check (list? audit-event-types) => #t)
(check (and (memq 'auth-attempt audit-event-types) #t) => #t)
(check (and (memq 'capability-deny audit-event-types) #t) => #t)

;; Cleanup
(guard (e [#t (void)]) (delete-file log-path))

(display "  audit: ")
(display pass-count) (display " passed")
(when (> fail-count 0)
  (display ", ") (display fail-count) (display " failed"))
(newline)
(when (> fail-count 0) (exit 1))
