#!chezscheme
;;; Tests for (std misc channel) — ring buffer, bounded, select

(import (chezscheme) (std misc channel))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn
              [#t (set! fail (+ fail 1))
                  (printf "FAIL ~a: exception ~a~%" name
                    (if (message-condition? exn) (condition-message exn) exn))])
       (let ([got expr])
         (if (equal? got expected)
           (begin (set! pass (+ pass 1))
                  (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~a, expected ~a~%" name got expected)))))]))

(printf "--- Channel v2 tests ---~%")

;; Test 1: Basic unbounded channel
(let ([ch (make-channel)])
  (channel-put ch 'hello)
  (channel-put ch 'world)
  (test "unbounded put/get 1" (channel-get ch) 'hello)
  (test "unbounded put/get 2" (channel-get ch) 'world)
  (test "channel-empty?" (channel-empty? ch) #t))

;; Test 2: Channel length
(let ([ch (make-channel)])
  (test "empty length" (channel-length ch) 0)
  (channel-put ch 1)
  (channel-put ch 2)
  (channel-put ch 3)
  (test "length after 3 puts" (channel-length ch) 3)
  (channel-get ch)
  (test "length after 1 get" (channel-length ch) 2))

;; Test 3: Ring buffer wrap-around (put 20 items in buffer of 16)
(let ([ch (make-channel)])
  (do ([i 0 (+ i 1)]) ((= i 20))
    (channel-put ch i))
  (test "20 items put" (channel-length ch) 20)
  (test "first item" (channel-get ch) 0)
  (test "second item" (channel-get ch) 1)
  ;; Drain rest
  (do ([i 2 (+ i 1)]) ((= i 20))
    (channel-get ch))
  (test "all drained" (channel-empty? ch) #t))

;; Test 4: Bounded channel
(let ([ch (make-channel 3)])
  (channel-put ch 'a)
  (channel-put ch 'b)
  (channel-put ch 'c)
  (test "bounded length" (channel-length ch) 3)
  ;; Put should block when full — test via try-get pattern
  (test "bounded get" (channel-get ch) 'a)
  (channel-put ch 'd)  ;; now room for one more
  (test "bounded after room" (channel-get ch) 'b))

;; Test 5: Bounded channel backpressure (producer blocks until consumer reads)
(let ([ch (make-channel 2)]
      [produced 0])
  (channel-put ch 1)
  (channel-put ch 2)
  ;; Spawn producer that will block on 3rd put
  (fork-thread
    (lambda ()
      (channel-put ch 3)
      (set! produced 3)))
  ;; Give producer time to block
  (sleep (make-time 'time-duration 0 0))
  ;; Consumer reads one
  (test "backpressure get" (channel-get ch) 1)
  ;; Give producer time to unblock
  (sleep (make-time 'time-duration 50000000 0))
  (test "producer unblocked" produced 3)
  ;; Drain
  (test "backpressure remaining 1" (channel-get ch) 2)
  (test "backpressure remaining 2" (channel-get ch) 3))

;; Test 6: try-get on empty
(let ([ch (make-channel)])
  (let-values ([(val ok) (channel-try-get ch)])
    (test "try-get empty val" val #f)
    (test "try-get empty ok" ok #f)))

;; Test 7: try-get with data
(let ([ch (make-channel)])
  (channel-put ch 42)
  (let-values ([(val ok) (channel-try-get ch)])
    (test "try-get with data val" val 42)
    (test "try-get with data ok" ok #t)))

;; Test 8: channel-close
(let ([ch (make-channel)])
  (channel-put ch 'last)
  (channel-close ch)
  (test "get after close" (channel-get ch) 'last)
  (test "closed?" (channel-closed? ch) #t))

;; Test 9: channel-select with ready data
(let ([ch1 (make-channel)]
      [ch2 (make-channel)])
  (channel-put ch2 'from-ch2)
  (let ([result (channel-select
                  ((ch1 msg) (cons 'ch1 msg))
                  ((ch2 msg) (cons 'ch2 msg)))])
    (test "select ready" result '(ch2 . from-ch2))))

;; Test 10: channel-select with else (non-blocking)
(let ([ch1 (make-channel)]
      [ch2 (make-channel)])
  (let ([result (channel-select
                  ((ch1 msg) 'got-ch1)
                  ((ch2 msg) 'got-ch2)
                  (else 'nothing))])
    (test "select else" result 'nothing)))

;; Test 11: channel-select blocking
(let ([ch1 (make-channel)]
      [ch2 (make-channel)])
  ;; Send data to ch1 after a short delay
  (fork-thread
    (lambda ()
      (sleep (make-time 'time-duration 20000000 0))
      (channel-put ch1 'delayed)))
  (let ([result (channel-select
                  ((ch1 msg) (cons 'ch1 msg))
                  ((ch2 msg) (cons 'ch2 msg)))])
    (test "select blocking" result '(ch1 . delayed))))

;; Test 12: channel-select with timeout
(let ([ch1 (make-channel)])
  (let ([result (channel-select
                  ((ch1 msg) 'got-data)
                  ((timeout: 0.05) 'timed-out))])
    (test "select timeout" result 'timed-out)))

(printf "~%~a tests, ~a passed, ~a failed~%" (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
