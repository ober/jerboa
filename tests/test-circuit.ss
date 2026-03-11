#!chezscheme
;;; Tests for (std circuit) -- Circuit breaker pattern

(import (chezscheme)
        (std circuit))

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

(printf "--- Phase 3a: Circuit Breaker ---~%~%")

;;; ======== make-circuit-config ========

(let ([cfg (make-circuit-config)])
  (test "default config is a record"
    (not (eq? cfg #f))
    #t))

(let ([cfg (make-circuit-config 3 1 30)])
  (test "custom config created without error"
    (not (eq? cfg #f))
    #t))

;;; ======== make-circuit-breaker ========

(test "circuit-breaker? true"
  (circuit-breaker? (make-circuit-breaker))
  #t)

(test "circuit-breaker? false"
  (circuit-breaker? 'nope)
  #f)

;;; ======== Initial state ========

(let ([cb (make-circuit-breaker)])
  (test "initial state is closed"
    (circuit-state cb)
    'closed)

  (test "circuit-closed? true initially"
    (circuit-closed? cb)
    #t)

  (test "circuit-open? false initially"
    (circuit-open? cb)
    #f)

  (test "circuit-half-open? false initially"
    (circuit-half-open? cb)
    #f))

;;; ======== Successful call ========

(let ([cb (make-circuit-breaker)])
  (test "circuit-call returns value"
    (circuit-call cb (lambda () 42))
    42)

  (test "state stays closed after success"
    (circuit-state cb)
    'closed))

;;; ======== Stats ========

(let ([cb (make-circuit-breaker)])
  (circuit-call cb (lambda () 1))
  (circuit-call cb (lambda () 2))
  (let ([stats (circuit-stats cb)])
    (test "stats total-calls"
      (cdr (assq 'total-calls stats))
      2)
    (test "stats total-successes"
      (cdr (assq 'total-successes stats))
      2)
    (test "stats total-failures"
      (cdr (assq 'total-failures stats))
      0)))

;;; ======== Failures open the circuit ========

(let* ([cfg (make-circuit-config 3 1 60)]  ; open after 3 failures
       [cb  (make-circuit-breaker cfg)])

  ;; Cause 3 failures
  (let fail-it ([n 3])
    (when (> n 0)
      (guard (exn [#t #f])
        (circuit-call cb (lambda () (error "test" "injected failure"))))
      (fail-it (- n 1))))

  (test "circuit opens after threshold failures"
    (circuit-state cb)
    'open)

  (test "circuit-open? true after threshold"
    (circuit-open? cb)
    #t))

;;; ======== Open circuit rejects calls ========

(let* ([cfg (make-circuit-config 2 1 60)]
       [cb  (make-circuit-breaker cfg)])

  ;; Open it
  (guard (exn [#t #f])
    (circuit-call cb (lambda () (error "t" "f"))))
  (guard (exn [#t #f])
    (circuit-call cb (lambda () (error "t" "f"))))

  (test "open circuit rejects calls"
    (guard (exn [(message-condition? exn) 'rejected])
      (circuit-call cb (lambda () 'should-not-run)))
    'rejected))

;;; ======== circuit-reset! ========

(let* ([cfg (make-circuit-config 2 1 60)]
       [cb  (make-circuit-breaker cfg)])

  ;; Open it
  (guard (exn [#t #f])
    (circuit-call cb (lambda () (error "t" "f"))))
  (guard (exn [#t #f])
    (circuit-call cb (lambda () (error "t" "f"))))

  (test "before reset: open"
    (circuit-open? cb)
    #t)

  (circuit-reset! cb)

  (test "after reset: closed"
    (circuit-closed? cb)
    #t)

  (test "can call again after reset"
    (circuit-call cb (lambda () 'ok))
    'ok))

;;; ======== Half-open: success closes ========

;; We use a very short timeout (0 seconds) so we can transition
;; to half-open immediately.
(let* ([cfg (make-circuit-config 2 1 0)]  ; timeout=0: half-open right away
       [cb  (make-circuit-breaker cfg)])

  ;; Open it
  (guard (exn [#t #f])
    (circuit-call cb (lambda () (error "t" "f"))))
  (guard (exn [#t #f])
    (circuit-call cb (lambda () (error "t" "f"))))

  (test "circuit is open"
    (circuit-open? cb)
    #t)

  ;; After 0-second timeout, the next call transitions to half-open
  ;; and if it succeeds, closes.
  (let ([result
         (guard (exn [#t 'open-error])
           (circuit-call cb (lambda () 'recovered)))])
    (test "half-open success closes circuit"
      (circuit-closed? cb)
      #t)
    (test "half-open call returns value"
      result
      'recovered)))

;;; ======== Half-open: failure reopens ========

(let* ([cfg (make-circuit-config 2 1 0)]
       [cb  (make-circuit-breaker cfg)])

  ;; Open it
  (guard (exn [#t #f])
    (circuit-call cb (lambda () (error "t" "f"))))
  (guard (exn [#t #f])
    (circuit-call cb (lambda () (error "t" "f"))))

  ;; Half-open call fails → reopen
  (guard (exn [#t #f])
    (circuit-call cb (lambda () (error "t" "half-open failure"))))

  (test "half-open failure reopens circuit"
    (circuit-open? cb)
    #t))

;;; ======== State-transitions counted ========

(let* ([cfg (make-circuit-config 2 1 0)]
       [cb  (make-circuit-breaker cfg)])

  (guard (exn [#t #f])
    (circuit-call cb (lambda () (error "t" "f"))))
  (guard (exn [#t #f])
    (circuit-call cb (lambda () (error "t" "f"))))

  ;; half-open → closed
  (guard (exn [#t #f])
    (circuit-call cb (lambda () 'ok)))

  (let ([stats (circuit-stats cb)])
    (test "state-transitions > 0"
      (> (cdr (assq 'state-transitions stats)) 0)
      #t)))

;;; Summary

(printf "~%Circuit tests: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
