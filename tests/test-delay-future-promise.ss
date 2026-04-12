(import (jerboa prelude))
(import (std clojure))

(def test-count 0)
(def pass-count 0)

(defrule (test name body ...)
  (begin
    (set! test-count (+ test-count 1))
    (guard (exn [#t
      (displayln (str "FAIL: " name))
      (displayln (str "  Error: " (if (message-condition? exn)
                                    (condition-message exn) exn)))])
      body ...
      (set! pass-count (+ pass-count 1))
      (displayln (str "PASS: " name)))))

(defrule (assert-equal got expected msg)
  (unless (equal? got expected)
    (error 'assert msg (list 'got: got 'expected: expected))))

(defrule (assert-true val msg)
  (unless val (error 'assert msg)))

;; =========================================================================
;; Delay tests
;; =========================================================================

(test "delay creates delay object"
  (let ([d (clj-delay (+ 1 2))])
    (assert-true (delay? d) "is delay")))

(test "delay not realized before deref"
  (let ([d (clj-delay (+ 1 2))])
    (assert-true (not (realized? d)) "not yet realized")))

(test "deref delay forces computation"
  (let ([d (clj-delay (+ 1 2))])
    (assert-equal (deref d) 3 "computed value")))

(test "delay memoizes result"
  (let ([count 0])
    (let ([d (clj-delay (set! count (+ count 1)) count)])
      (assert-equal (deref d) 1 "first deref")
      (assert-equal (deref d) 1 "second deref — memoized")
      (assert-equal count 1 "thunk called only once"))))

(test "delay realized after deref"
  (let ([d (clj-delay 42)])
    (deref d)
    (assert-true (realized? d) "realized after deref")))

(test "clj-force works on delay"
  (let ([d (clj-delay (* 6 7))])
    (assert-equal (clj-force d) 42 "force")))

;; =========================================================================
;; Future tests
;; =========================================================================

(test "future creates future object"
  (let ([f (clj-future (+ 1 2))])
    (assert-true (future? f) "is future")
    (deref f)))  ;; clean up

(test "deref future waits for result"
  (let ([f (clj-future 42)])
    (assert-equal (deref f) 42 "future result")))

(test "future-done? after completion"
  (let ([f (clj-future 42)])
    (deref f)
    (assert-true (future-done? f) "done after deref")))

(test "future propagates exceptions"
  (let ([f (clj-future (error 'test "boom"))])
    (guard (exn [#t
      (assert-true (message-condition? exn) "has message")
      (assert-equal (condition-message exn) "boom" "error message")])
      (deref f)
      (error 'test "should have raised"))))

(test "future-cancel"
  (let ([f (clj-future
             (let loop () (loop)))])  ;; infinite loop — will be cancelled
    (future-cancel f)
    (assert-true (future-cancelled? f) "cancelled")
    (assert-true (future-done? f) "done after cancel")))

(test "realized? on future"
  (let ([f (clj-future 99)])
    (deref f)
    (assert-true (realized? f) "realized after deref")))

;; =========================================================================
;; Promise tests
;; =========================================================================

(test "promise creates promise object"
  (let ([p (clj-promise)])
    (assert-true (promise? p) "is promise")))

(test "promise not realized before deliver"
  (let ([p (clj-promise)])
    (assert-true (not (realized? p)) "not yet realized")))

(test "deliver and deref promise"
  (let ([p (clj-promise)])
    (deliver p 42)
    (assert-equal (deref p) 42 "delivered value")))

(test "promise realized after deliver"
  (let ([p (clj-promise)])
    (deliver p "hello")
    (assert-true (realized? p) "realized after deliver")))

(test "deliver only once"
  (let ([p (clj-promise)])
    (deliver p 1)
    (deliver p 2)  ;; second deliver is a no-op
    (assert-equal (deref p) 1 "first delivery wins")))

(test "promise across threads"
  (let ([p (clj-promise)])
    (fork-thread (lambda ()
      (deliver p 42)))
    (assert-equal (deref p) 42 "delivered from thread")))

;; =========================================================================
;; Polymorphic deref tests
;; =========================================================================

(test "deref atom"
  (let ([a (atom 42)])
    (assert-equal (deref a) 42 "atom deref")))

(test "deref delay"
  (let ([d (clj-delay (+ 1 2))])
    (assert-equal (deref d) 3 "delay deref")))

(test "deref future"
  (let ([f (clj-future (* 6 7))])
    (assert-equal (deref f) 42 "future deref")))

(test "deref promise"
  (let ([p (clj-promise)])
    (deliver p 99)
    (assert-equal (deref p) 99 "promise deref")))

;; =========================================================================
;; Summary
;; =========================================================================
(newline)
(displayln (str "========================================="))
(displayln (str "Results: " pass-count "/" test-count " passed"))
(displayln (str "========================================="))
(when (< pass-count test-count)
  (exit 1))
