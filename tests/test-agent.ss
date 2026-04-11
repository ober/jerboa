#!chezscheme
;;; Tests for (std agent) — Clojure-style agents.

(import (except (jerboa prelude) make-time)
        (only (chezscheme) make-time sleep fork-thread)
        (std agent))

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

(define (brief-sleep) (sleep (make-time 'time-duration 50000000 0)))

(printf "--- std/agent ---~%~%")

;;; ---- Basic send + await ----------------------------------------

(test "agent? recognizes an agent"
  (let ([a (agent 0)])
    (let ([r (agent? a)]) (shutdown-agent! a) r))
  #t)

(test "agent? false for non-agents"
  (list (agent? 42) (agent? "str") (agent? '()))
  '(#f #f #f))

(test "initial value"
  (let ([a (agent 42)])
    (let ([v (agent-value a)]) (shutdown-agent! a) v))
  42)

(test "single send + await"
  (let ([a (agent 0)])
    (send a + 5)
    (await a)
    (let ([v (agent-value a)]) (shutdown-agent! a) v))
  5)

(test "send returns the agent"
  (let ([a (agent 0)])
    (let ([r (eq? a (send a + 1))])
      (await a)
      (shutdown-agent! a)
      r))
  #t)

(test "multiple sends are applied in order"
  (let ([a (agent 0)])
    (send a + 1)   ;; 1
    (send a * 3)   ;; 3
    (send a - 1)   ;; 2
    (await a)
    (let ([v (agent-value a)]) (shutdown-agent! a) v))
  2)

(test "send-off is an alias for send"
  (let ([a (agent 0)])
    (send-off a + 10)
    (send-off a * 2)
    (await a)
    (let ([v (agent-value a)]) (shutdown-agent! a) v))
  20)

(test "sends with multiple args"
  (let ([a (agent 0)])
    (send a + 1 2 3)
    (send a - 0 0 1)   ;; = v - 0 - 0 - 1
    (await a)
    (let ([v (agent-value a)]) (shutdown-agent! a) v))
  5)

;;; ---- agent-value / agent-error ----------------------------------

(test "agent-error is #f when no error"
  (let ([a (agent 0)])
    (send a + 1)
    (await a)
    (let ([e (agent-error a)]) (shutdown-agent! a) e))
  #f)

(test "agent-error captures thrown exception"
  (let ([a (agent 10)])
    (send a (lambda (v) (error 'boom "kaboom")))
    (brief-sleep)
    (let ([has-err (and (agent-error a) #t)])
      (shutdown-agent! a)
      has-err))
  #t)

(test "value is preserved across failing action"
  (let ([a (agent 10)])
    (send a (lambda (v) (error 'boom "kaboom")))
    (brief-sleep)
    (let ([v (agent-value a)]) (shutdown-agent! a) v))
  10)

(test "send after error raises"
  (let ([a (agent 10)])
    (send a (lambda (v) (error 'boom "kaboom")))
    (brief-sleep)
    (let ([r (guard (_ [#t 'raised]) (send a + 1))])
      (shutdown-agent! a)
      r))
  'raised)

(test "await after error raises"
  (let ([a (agent 10)])
    (send a (lambda (v) (error 'boom "kaboom")))
    (brief-sleep)
    (let ([r (guard (_ [#t 'raised]) (await a))])
      (shutdown-agent! a)
      r))
  'raised)

;;; ---- clear-agent-errors / restart-agent -------------------------

(test "clear-agent-errors clears the error"
  (let ([a (agent 10)])
    (send a (lambda (v) (error 'boom "kaboom")))
    (brief-sleep)
    (clear-agent-errors a)
    (let ([e (agent-error a)]) (shutdown-agent! a) e))
  #f)

(test "clear-agent-errors preserves value"
  (let ([a (agent 10)])
    (send a (lambda (v) (error 'boom "kaboom")))
    (brief-sleep)
    (clear-agent-errors a)
    (let ([v (agent-value a)]) (shutdown-agent! a) v))
  10)

(test "restart-agent resets value and clears error"
  (let ([a (agent 10)])
    (send a (lambda (v) (error 'boom "kaboom")))
    (brief-sleep)
    (restart-agent a 100)
    (let ([e (agent-error a)]
          [v (agent-value a)])
      (shutdown-agent! a)
      (list e v)))
  '(#f 100))

(test "send works after restart-agent"
  (let ([a (agent 10)])
    (send a (lambda (v) (error 'boom "kaboom")))
    (brief-sleep)
    (restart-agent a 0)
    (send a + 5)
    (await a)
    (let ([v (agent-value a)]) (shutdown-agent! a) v))
  5)

;;; ---- Shutdown --------------------------------------------------

(test "send after shutdown raises"
  (let ([a (agent 0)])
    (shutdown-agent! a)
    (guard (_ [#t 'raised]) (send a + 1)))
  'raised)

(test "agent-value readable after shutdown"
  (let ([a (agent 42)])
    (shutdown-agent! a)
    (agent-value a))
  42)

;;; ---- Concurrent sends -------------------------------------------
;;;
;;; Clojure guarantees agent actions are serialized — the value
;;; seen by action N is the result of action N-1 regardless of
;;; which thread called send. This confirms per-agent serialization.

(test "concurrent sends serialize through the agent"
  (let ([a (agent 0)])
    (for ([i (in-range 100)])
      (send a + 1))
    (await a)
    (let ([v (agent-value a)]) (shutdown-agent! a) v))
  100)

(test "concurrent sends from multiple threads serialize"
  (let ([a (agent 0)]
        [threads '()])
    (for ([t (in-range 10)])
      (set! threads
        (cons (fork-thread
                (lambda ()
                  (for ([i (in-range 10)])
                    (send a + 1))))
              threads)))
    ;; Give background threads time to finish sending
    (brief-sleep)
    (await a)
    (let ([v (agent-value a)]) (shutdown-agent! a) v))
  100)

;;; ---- Agent holds immutable state too ---------------------------

(test "agent holds a list"
  (let ([a (agent '())])
    ;; cons takes (item list), but send passes (current-value args ...),
    ;; so wrap in a lambda that flips the arg order.
    (send a (lambda (lst x) (cons x lst)) 1)
    (send a (lambda (lst x) (cons x lst)) 2)
    (send a (lambda (lst x) (cons x lst)) 3)
    (await a)
    (let ([v (agent-value a)]) (shutdown-agent! a) v))
  '(3 2 1))

(test "agent holds a hash-map-like alist"
  (let ([a (agent '())])
    (send a (lambda (m) (cons (cons 'a 1) m)))
    (send a (lambda (m) (cons (cons 'b 2) m)))
    (await a)
    (let ([v (agent-value a)]) (shutdown-agent! a) v))
  '((b . 2) (a . 1)))

;;; ---- Custom buffer size -----------------------------------------

(test "agent with explicit buffer size works"
  (let ([a (agent 0 8)])
    (send a + 5)
    (await a)
    (let ([v (agent-value a)]) (shutdown-agent! a) v))
  5)

;;; ---- Summary ---------------------------------------------------
(printf "~%std/agent: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
