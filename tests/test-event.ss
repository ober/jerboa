#!chezscheme
;;; Tests for (std misc event) — unified event system

(import (chezscheme) (std misc event))

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
           (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
           (begin (set! fail (+ fail 1))
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(printf "--- (std misc event) tests ---~%")

;; ===== always-event =====
(test "always-event ready"
  (event-ready? (always-event 42))
  #t)

(test "always-event value"
  (event-value (always-event 42))
  42)

;; ===== never-event =====
(test "never-event not ready"
  (event-ready? never-event)
  #f)

;; ===== make-event =====
(test "make-event ready"
  (event-value (make-event (lambda () (values #t 'hello))))
  'hello)

(test "make-event not ready"
  (event-ready? (make-event (lambda () (values #f #f))))
  #f)

;; ===== make-event with delayed readiness =====
(let ([ready #f])
  (let ([e (make-event (lambda () (values ready 'done)))])
    (test "delayed event not ready" (event-ready? e) #f)
    (set! ready #t)
    (test "delayed event now ready" (event-ready? e) #t)
    (test "delayed event value" (event-value e) 'done)))

;; ===== wrap =====
(test "wrap transforms value"
  (event-value (wrap (always-event 10) (lambda (v) (* v 2))))
  20)

(test "wrap not ready passes through"
  (event-ready? (wrap never-event (lambda (v) 'nope)))
  #f)

(test "wrap chain"
  (event-value
    (wrap (wrap (always-event 5) (lambda (v) (+ v 1)))
          (lambda (v) (* v 10))))
  60)

;; ===== handle (alias for wrap) =====
(test "handle transforms value"
  (event-value (handle (always-event 'raw) (lambda (v) (list 'handled v))))
  '(handled raw))

;; ===== choice =====
(test "choice first ready"
  (event-value (choice (always-event 'a) (always-event 'b)))
  'a)

(test "choice skips not-ready"
  (event-value (choice never-event (always-event 'b) (always-event 'c)))
  'b)

(test "choice all not-ready"
  (event-ready? (choice never-event never-event))
  #f)

(test "choice single"
  (event-value (choice (always-event 99)))
  99)

;; ===== sync =====
(test "sync single always"
  (sync (always-event 'done))
  'done)

(test "sync multiple, first ready"
  (sync (always-event 'first) (always-event 'second))
  'first)

(test "sync skips never"
  (sync never-event (always-event 'found))
  'found)

;; ===== sync with wrap =====
(test "sync with wrapped event"
  (sync (wrap (always-event 3) (lambda (v) (+ v 7))))
  10)

;; ===== sync/timeout =====
(test "sync/timeout immediate"
  (sync/timeout 100 (always-event 'fast))
  'fast)

(test "sync/timeout expires"
  (sync/timeout 50 never-event)
  #f)

;; ===== timer-event =====
(test "timer-event not ready immediately"
  (event-ready? (timer-event 500))
  #f)

(test "timer-event fires"
  (let ([e (timer-event 20)])
    (sleep (make-time 'time-duration 40000000 0))  ;; 40ms
    (event-ready? e))
  #t)

(test "timer-event value is #t"
  (let ([e (timer-event 10)])
    (sleep (make-time 'time-duration 30000000 0))
    (event-value e))
  #t)

;; ===== sync with timer =====
(test "sync timer vs always"
  (sync (timer-event 1000) (always-event 'instant))
  'instant)

(test "sync/timeout timer fires before timeout"
  (sync/timeout 200 (timer-event 20))
  #t)

(test "sync/timeout timeout fires before timer"
  (sync/timeout 20 (timer-event 500))
  #f)

;; ===== choice + sync =====
(test "sync choice"
  (sync (choice never-event (always-event 'chosen)))
  'chosen)

(test "sync choice with wrap"
  (sync (choice never-event
                (wrap (always-event 'x) (lambda (v) (list v v)))))
  '(x x))

;; ===== Channels: basic send/recv =====
(let ([ch (make-channel)])
  ;; channel-send blocks until receiver is ready, so use threads
  (fork-thread
    (lambda ()
      (channel-send ch 'hello)))
  (test "channel basic recv"
    (channel-recv ch)
    'hello))

;; ===== Channels: ordering =====
(let ([ch (make-channel)])
  (fork-thread
    (lambda ()
      (channel-send ch 1)
      (channel-send ch 2)
      (channel-send ch 3)))
  (test "channel order 1" (channel-recv ch) 1)
  (test "channel order 2" (channel-recv ch) 2)
  (test "channel order 3" (channel-recv ch) 3))

;; ===== Channels: multiple senders =====
(let ([ch (make-channel)]
      [results '()]
      [m (make-mutex)])
  (fork-thread (lambda () (channel-send ch 'a)))
  (fork-thread (lambda () (channel-send ch 'b)))
  ;; Collect two values
  (let ([v1 (channel-recv ch)]
        [v2 (channel-recv ch)])
    (let ([got (sort (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
                     (list v1 v2))])
      (test "channel multiple senders" got '(a b)))))

;; ===== channel-recv-event with sync =====
(let ([ch (make-channel)])
  (fork-thread
    (lambda ()
      (sleep (make-time 'time-duration 10000000 0))
      (channel-send ch 'async-msg)))
  (test "channel-recv-event via sync"
    (sync/timeout 500 (channel-recv-event ch))
    'async-msg))

;; ===== channel-recv-event with wrap =====
(let ([ch (make-channel)])
  (fork-thread
    (lambda ()
      (channel-send ch 42)))
  (test "channel-recv-event wrapped"
    (sync/timeout 500
      (wrap (channel-recv-event ch) (lambda (v) (* v 2))))
    84))

;; ===== sync/timeout with channel (no data) =====
(let ([ch (make-channel)])
  (test "channel-recv-event timeout"
    (sync/timeout 50 (channel-recv-event ch))
    #f))

;; ===== choice between channels =====
(let ([ch1 (make-channel)]
      [ch2 (make-channel)])
  (fork-thread
    (lambda ()
      (sleep (make-time 'time-duration 10000000 0))
      (channel-send ch2 'from-ch2)))
  (test "choice between channels"
    (sync/timeout 500
      (choice (channel-recv-event ch1)
              (channel-recv-event ch2)))
    'from-ch2))

;; ===== sync with timer-event and channel =====
(let ([ch (make-channel)])
  (test "timer wins over slow channel"
    (sync/timeout 200
      (choice (wrap (timer-event 30) (lambda (_) 'timer))
              (channel-recv-event ch)))
    'timer))

;; ===== Complex composition =====
(test "nested choice and wrap"
  (sync
    (choice
      never-event
      (choice never-event
              (wrap (always-event 'deep) (lambda (v) (list 'found v))))))
  '(found deep))

;; ===== handle with side effects =====
(let ([side-effect #f])
  (sync (handle (always-event 'trigger)
                (lambda (v) (set! side-effect v) 'result)))
  (test "handle side effect" side-effect 'trigger))

;; ===== Event created from mutable state =====
(let ([box (list #f)])
  (let ([e (make-event
             (lambda ()
               (if (car box)
                 (values #t (car box))
                 (values #f #f))))])
    (test "mutable state event not ready" (event-ready? e) #f)
    (set-car! box 'updated)
    (test "mutable state event fires" (event-value e) 'updated)))

(printf "~%~a tests, ~a passed, ~a failed~%" (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
