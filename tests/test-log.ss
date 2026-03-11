#!chezscheme
;;; Tests for (std log) -- Structured logging

(import (chezscheme)
        (std log))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s expected ~s~%" name got expected)))))]))

(define (string-contains? str sub)
  (let ([slen (string-length str)]
        [sublen (string-length sub)])
    (if (> sublen slen) #f
      (let loop ([i 0])
        (cond
          [(> (+ i sublen) slen) #f]
          [(string=? (substring str i (+ i sublen)) sub) #t]
          [else (loop (+ i 1))])))))

(printf "--- Phase 3a: Structured Logging ---~%~%")

;;; ======== make-logger / logger? ========

(test "logger? true"
  (logger? (make-logger 'info))
  #t)

(test "logger? false"
  (logger? 'not-a-logger)
  #f)

(test "logger-level"
  (logger-level (make-logger 'debug))
  'debug)

(test "logger-level warn"
  (logger-level (make-logger 'warn))
  'warn)

;;; ======== log-level? ========

(test "log-level? debug"  (log-level? 'debug) #t)
(test "log-level? info"   (log-level? 'info)  #t)
(test "log-level? warn"   (log-level? 'warn)  #t)
(test "log-level? error"  (log-level? 'error) #t)
(test "log-level? fatal"  (log-level? 'fatal) #t)
(test "log-level? bogus"  (log-level? 'bogus) #f)
(test "log-level? string" (log-level? "info") #f)

;;; ======== logger-fields ========

(test "logger-fields empty"
  (logger-fields (make-logger 'info))
  '())

(test "logger-fields with kv"
  (logger-fields (make-logger 'info 'service "my-svc"))
  '((service . "my-svc")))

;;; ======== console sink collects records ========

(let* ([lg   (make-logger 'debug)]
       [recs '()])
  (add-sink! lg (lambda (r) (set! recs (cons r recs))))
  (log-info lg "hello")

  (test "sink receives record"
    (length recs)
    1)

  (test "record has level"
    (cdr (assq 'level (car recs)))
    'info)

  (test "record has message"
    (cdr (assq 'message (car recs)))
    "hello")

  (test "record has timestamp"
    (time? (cdr (assq 'timestamp (car recs))))
    #t))

;;; ======== structured fields in log call ========

(let* ([lg   (make-logger 'debug)]
       [recs '()])
  (add-sink! lg (lambda (r) (set! recs (cons r recs))))
  (log-debug lg "event" 'user "alice" 'count 42)

  (test "extra field user"
    (cdr (assq 'user (car recs)))
    "alice")

  (test "extra field count"
    (cdr (assq 'count (car recs)))
    42))

;;; ======== level filtering ========

(let* ([lg   (make-logger 'warn)]
       [recs '()])
  (add-sink! lg (lambda (r) (set! recs (cons r recs))))
  (log-debug lg "filtered out")
  (log-info  lg "also filtered")
  (log-warn  lg "visible")
  (log-error lg "visible too")

  (test "level filter: only warn+ emitted"
    (length recs)
    2))

;;; ======== with-logger / current-logger ========

(let* ([lg   (make-logger 'info)]
       [recs '()])
  (add-sink! lg (lambda (r) (set! recs (cons r recs))))
  (with-logger lg
    (log-info (current-logger) "via current-logger"))

  (test "with-logger sets current-logger"
    (length recs)
    1))

;;; ======== make-console-sink writes to port ========

(let* ([sp  (open-output-string)]
       [lg  (make-logger 'debug)]
       [_   (add-sink! lg (make-console-sink sp))])
  (log-info lg "test message")
  (let ([out (get-output-string sp)])
    (test "console sink includes level"
      (string-contains? out "INFO")
      #t)
    (test "console sink includes message"
      (string-contains? out "test message")
      #t)))

;;; ======== make-json-sink writes JSON ========

(let* ([sp  (open-output-string)]
       [lg  (make-logger 'info)]
       [_   (add-sink! lg (make-json-sink sp))])
  (log-warn lg "json test" 'x 1)
  (let ([out (get-output-string sp)])
    (test "json sink is non-empty"
      (> (string-length out) 0)
      #t)
    (test "json sink contains level"
      (string-contains? out "level")
      #t)))

;;; ======== fatal level emitted ========

(let* ([lg   (make-logger 'fatal)]
       [recs '()])
  (add-sink! lg (lambda (r) (set! recs (cons r recs))))
  (log-fatal lg "catastrophic")
  (test "fatal level emitted"
    (length recs)
    1))

;;; Summary

(printf "~%Log tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
