#!chezscheme
;;; Tests for (std actor protocol) — ask/tell/reply, defprotocol

(import (chezscheme) (jerboa core)
        (std actor core) (std actor protocol))

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

;; Helper for set comparison
(define (list->set lst) (list-sort < lst))

(printf "--- (std actor protocol) tests ---~%")

;; Test 1: ask/reply round-trip
(let ([a (spawn-actor
            (lambda (msg)
              (with-ask-context msg
                (lambda (actual)
                  (match actual
                    [('add x y) (reply (+ x y))]
                    [_ (void)])))))])
  (test "ask-reply" (ask-sync a '(add 3 4)) 7)
  (actor-kill! a))

;; Test 2: reply in non-ask context raises error
(let ([raised #f]
      [m (make-mutex)] [c (make-condition)])
  (let ([a (spawn-actor
              (lambda (msg)
                (guard (exn [#t (set! raised #t)])
                  (reply 99))
                (with-mutex m (condition-signal c))))])
    (send a 'trigger)
    (with-mutex m (let loop () (unless raised (condition-wait c m) (loop))))
    (test "reply-no-context" raised #t)
    (actor-kill! a)))

;; Test 3: tell is fire-and-forget (does not block)
(let ([got #f]
      [m (make-mutex)] [c (make-condition)])
  (let ([a (spawn-actor
              (lambda (msg)
                (with-mutex m (set! got msg) (condition-signal c))))])
    (tell a 'notification)
    (with-mutex m (let loop () (unless got (condition-wait c m) (loop))))
    (test "tell" got 'notification)
    (actor-kill! a)))

;; Test 4: ask-sync with timeout raises error on expire
(let ([a (spawn-actor (lambda (msg) (void)))])  ;; never replies
  (let ([timed-out #f])
    (guard (exn [#t (set! timed-out #t)])
      (ask-sync a 'anything 0.05))  ;; 50ms timeout
    (test "ask-timeout" timed-out #t))
  (actor-kill! a))

;; Test 5: defprotocol generates correct types and helpers
(defprotocol math
  (square x -> result)
  (log-msg text))

(let ([a (spawn-actor
            (lambda (msg)
              (with-ask-context msg
                (lambda (actual)
                  (cond
                    [(math:square? actual)
                     (reply (* (math:square-x actual) (math:square-x actual)))]
                    [(math:log-msg? actual)
                     (void)]   ;; fire-and-forget
                    [else (void)])))))])
  ;; Record predicates
  (test "struct-pred-square" (math:square? (make-math:square 5)) #t)
  (test "struct-pred-log"    (math:log-msg? (make-math:log-msg "hi")) #t)
  ;; ask helper
  (test "defprotocol-ask?!" (math:square?! a 7) 49)
  ;; tell helper (no return value check needed — fire-and-forget)
  (math:log-msg! a "hello")
  (actor-kill! a))

;; Test 6: reply-to returns sender actor-ref
(let ([sender-got #f]
      [m (make-mutex)] [c (make-condition)])
  (let* ([responder
          (spawn-actor
            (lambda (msg)
              (with-ask-context msg
                (lambda (actual)
                  (with-mutex m
                    (set! sender-got (reply-to))
                    (condition-signal c))
                  (reply 'ok)))))]
         [requester
          (spawn-actor
            (lambda (msg) (void)))])
    ;; ask from the test thread — reply-to will be #f (no actor context)
    (ask-sync responder 'check)
    ;; sender-got may be #f since we called from non-actor thread
    (test "reply-to-outside-actor" sender-got #f)
    (actor-kill! responder)
    (actor-kill! requester)))

;; Test 7: multiple concurrent asks to same actor
(let ([a (spawn-actor
            (lambda (msg)
              (with-ask-context msg
                (lambda (actual)
                  (match actual
                    [('echo v) (reply v)]
                    [_ (void)])))))]
      [results '()]
      [m (make-mutex)] [c (make-condition)])
  (do ([i 0 (+ i 1)]) ((= i 10))
    (let ([n i])
      (fork-thread
        (lambda ()
          (let ([v (ask-sync a (list 'echo n))])
            (with-mutex m
              (set! results (cons v results))
              (when (= (length results) 10) (condition-signal c))))))))
  (with-mutex m
    (let loop () (unless (= (length results) 10) (condition-wait c m) (loop))))
  (test "concurrent-asks-count"  (length results) 10)
  (test "concurrent-asks-values" (list->set results) (list->set '(0 1 2 3 4 5 6 7 8 9)))
  (actor-kill! a))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
