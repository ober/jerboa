#!chezscheme
;;; Tests for (std actor deque) — work-stealing double-ended queue

(import (chezscheme) (std actor deque))

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

(printf "--- (std actor deque) tests ---~%")

;; Test 1: empty deque
(let ([d (make-work-deque)])
  (test "empty-pop"   (deque-pop-bottom! d) #f)
  (test "empty-size"  (deque-size d) 0)
  (test "empty?"      (deque-empty? d) #t))

;; Test 2: steal from empty deque
(let ([d (make-work-deque)])
  (let-values ([(task ok) (deque-steal-top! d)])
    (test "steal-empty-ok"   ok #f)
    (test "steal-empty-task" task #f)))

;; Test 3: push/pop is LIFO
(let ([d (make-work-deque)])
  (deque-push-bottom! d 'a)
  (deque-push-bottom! d 'b)
  (deque-push-bottom! d 'c)
  (test "pop-lifo-1" (deque-pop-bottom! d) 'c)
  (test "pop-lifo-2" (deque-pop-bottom! d) 'b)
  (test "pop-lifo-3" (deque-pop-bottom! d) 'a)
  (test "pop-lifo-empty" (deque-pop-bottom! d) #f))

;; Test 4: steal is FIFO
(let ([d (make-work-deque)])
  (deque-push-bottom! d 1)
  (deque-push-bottom! d 2)
  (deque-push-bottom! d 3)
  (let-values ([(t1 ok1) (deque-steal-top! d)]
               [(t2 ok2) (deque-steal-top! d)]
               [(t3 ok3) (deque-steal-top! d)])
    (test "steal-fifo-1" t1 1)
    (test "steal-fifo-2" t2 2)
    (test "steal-fifo-3" t3 3))
  (let-values ([(t ok) (deque-steal-top! d)])
    (test "steal-empty-after" ok #f)))

;; Test 5: push more than initial capacity (64) — grow test
(let ([d (make-work-deque)])
  (do ([i 0 (+ i 1)]) ((= i 128))
    (deque-push-bottom! d i))
  (test "grow-size" (deque-size d) 128)
  ;; Pop all and check we got 128 distinct items summing to 0+1+...+127 = 8128
  (let ([result
         (let loop ([acc '()])
           (let ([x (deque-pop-bottom! d)])
             (if (not (eq? x #f)) (loop (cons x acc)) acc)))])
    (test "grow-all-popped" (length result) 128)
    (test "grow-sum"
          (apply + result)
          (/ (* 127 128) 2))))

;; Test 6: size tracking
(let ([d (make-work-deque)])
  (deque-push-bottom! d 'x)
  (deque-push-bottom! d 'y)
  (test "size-2" (deque-size d) 2)
  (deque-pop-bottom! d)
  (test "size-1" (deque-size d) 1)
  (deque-pop-bottom! d)
  (test "size-0" (deque-size d) 0))

;; Test 7: concurrent push (owner) + steal (thief)
(let ([d (make-work-deque)]
      [results (make-vector 500 #f)]
      [done-mutex (make-mutex)]
      [done-cond  (make-condition)]
      [stolen-count 0])
  ;; Push 500 items
  (do ([i 0 (+ i 1)]) ((= i 500))
    (deque-push-bottom! d i))
  ;; Spawn a thief thread to steal all items
  (fork-thread
    (lambda ()
      (let loop ([n 0])
        (if (fx= n 500)
          (with-mutex done-mutex
            (set! stolen-count n)
            (condition-signal done-cond))
          (let-values ([(task ok) (deque-steal-top! d)])
            (if ok
              (begin
                (vector-set! results n task)
                (loop (+ n 1)))
              (loop n)))))))
  ;; Wait for thief to finish
  (with-mutex done-mutex
    (let loop ()
      (when (< stolen-count 500)
        (condition-wait done-cond done-mutex)
        (loop))))
  (test "concurrent-steal-count" stolen-count 500)
  ;; Stolen in FIFO order: should be 0..499
  (test "concurrent-steal-ordered"
        (equal? (vector->list results) (iota 500))
        #t))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
