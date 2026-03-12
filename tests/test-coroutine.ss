#!chezscheme
;;; Tests for (std control coroutine) — Coroutines

(import (chezscheme) (std control coroutine))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    [(_ name expr expected)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn)
                           (condition-message exn)
                           exn))])
       (let ([got expr])
         (if (equal? got expected)
             (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
             (begin (set! fail (+ fail 1))
                    (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(define-syntax test-true
  (syntax-rules ()
    [(_ name expr)
     (test name (if expr #t #f) #t)]))

(printf "--- (std control coroutine) tests ---~%~%")

;;; ======== make-coroutine / coroutine? ========

(test-true "make-coroutine returns coroutine"
  (coroutine? (make-coroutine (lambda (yield) (void)))))

(test "coroutine? false for non-coroutine"
  (coroutine? 42)
  #f)

(test "coroutine? false for procedure"
  (coroutine? (lambda () 'x))
  #f)

;;; ======== coroutine-state ========

(test "initial state is ready"
  (coroutine-state (make-coroutine (lambda (yield) (void))))
  'ready)

(let ([co (make-coroutine (lambda (yield) (yield 1) (void)))])
  (coroutine-transfer co)
  (test "state after first yield is suspended"
    (coroutine-state co)
    'suspended))

(let ([co (make-coroutine (lambda (yield) (void)))])
  (coroutine-transfer co)
  (test "state after body returns is done"
    (coroutine-state co)
    'done))

;;; ======== coroutine-done? ========

(test "coroutine-done? false for ready"
  (coroutine-done? (make-coroutine (lambda (yield) (void))))
  #f)

(let ([co (make-coroutine (lambda (yield) (void)))])
  (coroutine-transfer co)
  (test "coroutine-done? true after body returns"
    (coroutine-done? co)
    #t))

;;; ======== coroutine-transfer — basic yield/resume ========

(test "transfer returns yielded value"
  (let ([co (make-coroutine (lambda (yield) (yield 'hello) (void)))])
    (coroutine-transfer co))
  'hello)

(test "transfer resumes and returns second yield"
  (let ([co (make-coroutine
              (lambda (yield)
                (yield 'first)
                (yield 'second)
                (void)))])
    (coroutine-transfer co)  ; first
    (coroutine-transfer co)) ; second
  'second)

(test "yield receives value passed to transfer"
  (let* ([received #f]
         [co (make-coroutine
               (lambda (yield)
                 (let ([v (yield 'waiting)])
                   (set! received v))))])
    (coroutine-transfer co)            ; run to first yield
    (coroutine-transfer co 'sent-back) ; resume with this value
    received)
  'sent-back)

(test "transfer on done coroutine raises error"
  (guard (exn [#t 'error-raised])
    (let ([co (make-coroutine (lambda (yield) (void)))])
      (coroutine-transfer co) ; finishes
      (coroutine-transfer co) ; should error
      'no-error))
  'error-raised)

;;; ======== coroutine body executes lazily ========

(let ([side-effects '()])
  (define co
    (make-coroutine
      (lambda (yield)
        (set! side-effects (cons 'a side-effects))
        (yield 'step-a)
        (set! side-effects (cons 'b side-effects))
        (yield 'step-b)
        (set! side-effects (cons 'c side-effects)))))

  (test "no side effects before first transfer"
    side-effects '())

  (coroutine-transfer co)
  (test "side effect A after first transfer"
    side-effects '(a))

  (coroutine-transfer co)
  (test "side effect B after second transfer"
    side-effects '(b a))

  (coroutine-transfer co)
  (test "side effect C after third transfer"
    side-effects '(c b a)))

;;; ======== multiple independent coroutines ========

(let ([log '()])
  (define (record! x) (set! log (append log (list x))))

  (define co-a
    (make-coroutine
      (lambda (yield)
        (record! 'a1) (yield)
        (record! 'a2) (yield)
        (record! 'a3))))

  (define co-b
    (make-coroutine
      (lambda (yield)
        (record! 'b1) (yield)
        (record! 'b2))))

  ; Interleave manually
  (coroutine-transfer co-a)
  (coroutine-transfer co-b)
  (coroutine-transfer co-a)
  (coroutine-transfer co-b)
  (coroutine-transfer co-a)

  (test "interleaved execution order"
    log
    '(a1 b1 a2 b2 a3)))

;;; ======== round-robin scheduler ========

(let ([log '()])
  (define sched (make-round-robin-scheduler))
  (define (record! x) (set! log (append log (list x))))

  (scheduler-add! sched
    (make-coroutine
      (lambda (yield)
        (record! 'x1) (yield)
        (record! 'x2) (yield)
        (record! 'x3))))

  (scheduler-add! sched
    (make-coroutine
      (lambda (yield)
        (record! 'y1) (yield)
        (record! 'y2))))

  (scheduler-run! sched)

  (test "round-robin interleaving"
    log
    '(x1 y1 x2 y2 x3)))

(test "scheduler-run! completes all coroutines"
  (let ([sched (make-round-robin-scheduler)]
        [count 0])
    (scheduler-add! sched
      (make-coroutine
        (lambda (yield)
          (set! count (+ count 1))
          (yield)
          (set! count (+ count 1)))))
    (scheduler-add! sched
      (make-coroutine
        (lambda (yield)
          (set! count (+ count 1)))))
    (scheduler-run! sched)
    count)
  3)

;;; ======== edge cases ========

(test "coroutine that never yields runs to completion"
  (let ([co (make-coroutine
              (lambda (yield)
                42))])
    (coroutine-transfer co)
    (coroutine-state co))
  'done)

(test "coroutine with no yield returns void from transfer"
  (let ([co (make-coroutine (lambda (yield) (void)))])
    (eq? (coroutine-transfer co) (void)))
  #t)

;;; Summary

(printf "~%~a tests: ~a passed, ~a failed~%" (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
