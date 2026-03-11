#!chezscheme
;;; Tests for (std select) -- Go-style channel select

(import (chezscheme)
        (std misc channel)
        (std select))

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

(printf "--- Phase 2a: Channel Select ---~%~%")

;;; ======== Basic recv ========

(printf "-- Basic recv --~%")

(test "select recv from ready channel"
  (let ([ch (make-channel)])
    (channel-put ch 42)
    (select
      [(recv ch) => (lambda (msg) msg)]))
  42)

(test "select recv first ready channel (ch1)"
  (let ([ch1 (make-channel)]
        [ch2 (make-channel)])
    (channel-put ch1 'first)
    (select
      [(recv ch1) => (lambda (msg) msg)]
      [(recv ch2) => (lambda (msg) 'second)]))
  'first)

(test "select recv second ready channel (ch2)"
  (let ([ch1 (make-channel)]
        [ch2 (make-channel)])
    (channel-put ch2 'second)
    (select
      [(recv ch1) => (lambda (msg) 'first)]
      [(recv ch2) => (lambda (msg) msg)]))
  'second)

;;; ======== Default clause ========

(printf "~%-- Default clause --~%")

(test "select default when nothing ready"
  (let ([ch (make-channel)])
    (select
      [(recv ch) => (lambda (msg) 'got-message)]
      [default   => (lambda () 'default-taken)]))
  'default-taken)

(test "select recv wins over default when ready"
  (let ([ch (make-channel)])
    (channel-put ch 'hello)
    (select
      [(recv ch) => (lambda (msg) msg)]
      [default   => (lambda () 'default-taken)]))
  'hello)

;;; ======== After (timeout) clause ========

(printf "~%-- After (timeout) clause --~%")

(test "select after fires when nothing ready"
  (let ([ch (make-channel)])
    (select
      [(recv ch)   => (lambda (msg) 'got-message)]
      [(after 50)  => (lambda () 'timed-out)]))
  'timed-out)

(test "select recv wins when ready before timeout"
  (let ([ch (make-channel)])
    ;; Put before selecting — guaranteed ready
    (channel-put ch 'quick)
    (select
      [(recv ch)   => (lambda (msg) msg)]
      [(after 100) => (lambda () 'timed-out)]))
  'quick)

;;; ======== Multiple channels blocking ========

(printf "~%-- Multi-channel blocking --~%")

(test "select waits for one channel to be ready"
  (let ([ch (make-channel)]
        [result #f])
    ;; Sender thread delivers after a short delay
    (fork-thread
      (lambda ()
        (sleep (make-time 'time-duration 10000000 0))  ; 10ms
        (channel-put ch 'delayed)))
    (set! result
      (select
        [(recv ch) => (lambda (msg) msg)]))
    result)
  'delayed)

;;; ======== channel-try-send ========

(printf "~%-- channel-try-send --~%")

(test "try-send to unbounded channel succeeds"
  (let ([ch (make-channel)])
    (let ([ok (channel-try-send ch 'test)])
      (and ok (equal? (channel-get ch) 'test))))
  #t)

;;; ======== select with send ========

(printf "~%-- select with send --~%")

(test "select send to empty unbounded channel"
  (let ([ch     (make-channel)]
        [result #f])
    (select
      [(send ch 'payload) => (lambda () (set! result 'sent))])
    ;; Now retrieve and verify
    (and (eq? result 'sent)
         (equal? (channel-get ch) 'payload)))
  #t)

;;; ======== Edge cases ========

(printf "~%-- Edge cases --~%")

(test "select with single channel and default"
  (let ([ch (make-channel)])
    (let ([results '()])
      ;; First call: nothing ready → default
      (set! results
        (cons (select
                [(recv ch) => (lambda (v) v)]
                [default   => (lambda () 'empty)])
              results))
      ;; Put something
      (channel-put ch 42)
      ;; Second call: something ready → recv
      (set! results
        (cons (select
                [(recv ch) => (lambda (v) v)]
                [default   => (lambda () 'empty)])
              results))
      (reverse results)))
  '(empty 42))

;;; Summary

(printf "~%Channel Select: ~a passed, ~a failed~%" pass fail)
(when (> fail 0)
  (exit 1))
