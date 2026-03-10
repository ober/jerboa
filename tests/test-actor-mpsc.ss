#!chezscheme
;;; Tests for (std actor mpsc) — MPSC mailbox queue

(import (chezscheme) (std actor mpsc))

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

(printf "--- (std actor mpsc) tests ---~%")

;; Test 1: basic enqueue / dequeue
(let ([q (make-mpsc-queue)])
  (mpsc-enqueue! q 'hello)
  (mpsc-enqueue! q 'world)
  (test "dequeue-1" (mpsc-dequeue! q) 'hello)
  (test "dequeue-2" (mpsc-dequeue! q) 'world))

;; Test 2: try-dequeue on empty returns (values #f #f)
(let ([q (make-mpsc-queue)])
  (let-values ([(v ok) (mpsc-try-dequeue! q)])
    (test "try-empty-val" v #f)
    (test "try-empty-ok"  ok #f)))

;; Test 3: try-dequeue after enqueue returns value
(let ([q (make-mpsc-queue)])
  (mpsc-enqueue! q 42)
  (let-values ([(v ok) (mpsc-try-dequeue! q)])
    (test "try-val" v 42)
    (test "try-ok"  ok #t)))

;; Test 4: single-producer FIFO ordering
(let ([q (make-mpsc-queue)])
  (do ([i 0 (+ i 1)]) ((= i 100))
    (mpsc-enqueue! q i))
  (let loop ([i 0] [ok #t])
    (if (= i 100)
      (test "fifo-order" ok #t)
      (let-values ([(v got) (mpsc-try-dequeue! q)])
        (loop (+ i 1) (and ok got (= v i)))))))

;; Test 5: 10 concurrent producers, 1 consumer — all messages received
(let ([q (make-mpsc-queue)]
      [received (make-eq-hashtable)]
      [recv-mutex (make-mutex)]
      [prod-done 0]
      [prod-mutex (make-mutex)]
      [prod-cond  (make-condition)])
  (define msgs-per-thread 100)
  (define total (* 10 msgs-per-thread))
  ;; Start 10 producers
  (do ([t 0 (+ t 1)]) ((= t 10))
    (let ([tid t])
      (fork-thread
        (lambda ()
          (do ([i 0 (+ i 1)]) ((= i msgs-per-thread))
            (mpsc-enqueue! q (+ (* tid msgs-per-thread) i)))
          (with-mutex prod-mutex
            (set! prod-done (+ prod-done 1))
            (when (= prod-done 10)
              (condition-signal prod-cond)))))))
  ;; Wait for all producers
  (with-mutex prod-mutex
    (let loop () (unless (= prod-done 10) (condition-wait prod-cond prod-mutex) (loop))))
  (mpsc-close! q)
  ;; Consume all
  (let loop ([count 0])
    (let-values ([(v ok) (mpsc-try-dequeue! q)])
      (if ok
        (begin (hashtable-set! received v #t) (loop (+ count 1)))
        (test "concurrent-producers-count" count total))))
  ;; Verify every expected message was received
  (let ([missing 0])
    (do ([i 0 (+ i 1)]) ((= i total))
      (unless (hashtable-ref received i #f)
        (set! missing (+ missing 1))))
    (test "concurrent-producers-no-missing" missing 0)))

;; Test 6: close wakes a blocked consumer with an error
(let ([q (make-mpsc-queue)]
      [error-caught #f]
      [done-mutex (make-mutex)]
      [done-cond  (make-condition)])
  (fork-thread
    (lambda ()
      (guard (exn [#t (set! error-caught #t)])
        (mpsc-dequeue! q))
      (with-mutex done-mutex (condition-signal done-cond))))
  (sleep (make-time 'time-duration 50000000 0))  ;; 50ms
  (mpsc-close! q)
  (with-mutex done-mutex
    (let loop ()
      (unless error-caught
        (condition-wait done-cond done-mutex)
        (loop))))
  (test "close-wakes-consumer" error-caught #t))

;; Test 7: enqueue on closed queue raises error
(let ([q (make-mpsc-queue)])
  (mpsc-close! q)
  (let ([raised #f])
    (guard (exn [#t (set! raised #t)])
      (mpsc-enqueue! q 'x))
    (test "enqueue-closed" raised #t)))

;; Test 8: mpsc-empty? reflects state
(let ([q (make-mpsc-queue)])
  (test "empty-initially" (mpsc-empty? q) #t)
  (mpsc-enqueue! q 1)
  (test "not-empty-after-enqueue" (mpsc-empty? q) #f)
  (mpsc-try-dequeue! q)
  (test "empty-after-dequeue" (mpsc-empty? q) #t))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
