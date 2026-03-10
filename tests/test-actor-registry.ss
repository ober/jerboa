#!chezscheme
;;; Tests for (std actor registry) — named actor registry

(import (chezscheme) (jerboa core)
        (std actor core) (std actor protocol) (std actor registry))

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

(define (wait-ms n)
  (sleep (make-time 'time-duration (* n 1000000) 0)))

(printf "--- (std actor registry) tests ---~%")

(start-registry!)

;; Test 1: register! then whereis returns same ref
(let ([a (spawn-actor (lambda (msg) (void)))])
  (test "register-ok"     (register! 'actor-1 a) 'ok)
  (test "whereis-found"   (whereis 'actor-1) a)
  (unregister! 'actor-1)
  (actor-kill! a))

;; Test 2: duplicate registration returns 'already-registered
(let ([a (spawn-actor (lambda (msg) (void)))])
  (register! 'dup a)
  (test "dup-register" (register! 'dup a) 'already-registered)
  (unregister! 'dup)
  (actor-kill! a))

;; Test 3: unregister then whereis returns #f
(let ([a (spawn-actor (lambda (msg) (void)))])
  (register! 'going a)
  (test "unregister-ok"    (unregister! 'going) 'ok)
  (test "whereis-after-unreg" (whereis 'going) #f)
  (actor-kill! a))

;; Test 4: actor dies → auto-unregistered via monitor
(let ([a (spawn-actor (lambda (msg) (void)))])
  (register! 'dying a)
  (actor-kill! a)
  ;; Wait for DOWN to propagate through the registry actor
  (wait-ms 200)
  (test "auto-unregister" (whereis 'dying) #f))

;; Test 5: registered-names returns all current names
(let ([a (spawn-actor (lambda (msg) (void)))]
      [b (spawn-actor (lambda (msg) (void)))])
  (register! 'first  a)
  (register! 'second b)
  (let ([names (registered-names)])
    (test "names-has-first"  (if (memq 'first  names) #t #f) #t)
    (test "names-has-second" (if (memq 'second names) #t #f) #t))
  (unregister! 'first)
  (unregister! 'second)
  (actor-kill! a)
  (actor-kill! b))

;; Test 6: register the same actor under two names
(let ([a (spawn-actor (lambda (msg) (void)))])
  (register! 'name-x a)
  (register! 'name-y a)
  (test "two-names-x" (whereis 'name-x) a)
  (test "two-names-y" (whereis 'name-y) a)
  (unregister! 'name-x)
  (unregister! 'name-y)
  (actor-kill! a))

;; Test 7: whereis unknown name returns #f
(test "whereis-unknown" (whereis 'no-such-actor) #f)

;; Test 8: registry survives multiple register/unregister cycles
(let ([a (spawn-actor (lambda (msg) (void)))])
  (do ([i 0 (+ i 1)]) ((= i 10))
    (register! 'cycling a)
    (unregister! 'cycling))
  (test "cycling-final" (whereis 'cycling) #f)
  (actor-kill! a))

(printf "~%Results: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
