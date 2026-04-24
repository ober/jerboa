(import (jerboa prelude))
(import (std stm))

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
;; Basic TVar API
;; =========================================================================

(test "make-tvar and tvar-ref"
  (let ([tv (make-tvar 42)])
    (assert-true (tvar? tv) "is tvar")
    (assert-equal (tvar-ref tv) 42 "initial value")))

(test "tvar-read outside transaction"
  (let ([tv (make-tvar "hello")])
    (assert-equal (tvar-read tv) "hello" "direct read")))

;; =========================================================================
;; Clojure-style aliases
;; =========================================================================

(test "make-ref and ref-deref"
  (let ([r (make-ref 100)])
    (assert-true (ref? r) "is ref")
    (assert-equal (ref-deref r) 100 "deref value")))

;; =========================================================================
;; dosync / alter
;; =========================================================================

(test "dosync with alter"
  (let ([r (make-ref 0)])
    (dosync (alter r + 10))
    (assert-equal (ref-deref r) 10 "altered to 10")))

(test "multiple alters in one dosync"
  (let ([r (make-ref 0)])
    (dosync
      (alter r + 10)
      (alter r + 5)
      (alter r * 2))
    (assert-equal (ref-deref r) 30 "(0+10+5)*2 = 30")))

(test "ref-set in dosync"
  (let ([r (make-ref 'old)])
    (dosync (ref-set r 'new))
    (assert-equal (ref-deref r) 'new "set to new")))

(test "dosync returns last expression value"
  (let ([r (make-ref 0)])
    (let ([result (dosync
                    (alter r + 42)
                    'done)])
      (assert-equal result 'done "returns done")
      (assert-equal (ref-deref r) 42 "side effect applied"))))

;; =========================================================================
;; Multiple refs atomically
;; =========================================================================

(test "atomically update multiple refs"
  (let ([a (make-ref 100)]
        [b (make-ref 200)])
    (dosync
      (let ([va (ref-deref a)]
            [vb (ref-deref b)])
        (ref-set a vb)
        (ref-set b va)))
    (assert-equal (ref-deref a) 200 "a got b's value")
    (assert-equal (ref-deref b) 100 "b got a's value")))

;; =========================================================================
;; commute and ensure
;; =========================================================================

(test "commute works like alter"
  (let ([r (make-ref 0)])
    (dosync (commute r + 5))
    (assert-equal (ref-deref r) 5 "commuted to 5")))

(test "ensure reads value"
  (let ([r (make-ref 42)])
    (let ([val (dosync (ensure r))])
      (assert-equal val 42 "ensure returns value"))))

;; =========================================================================
;; Concurrent transfers (basic correctness)
;; =========================================================================

(test "concurrent transfers preserve total"
  (let ([a (make-ref 1000)]
        [b (make-ref 1000)]
        [done (make-tvar 0)])
    ;; Spawn threads that transfer between accounts
    (let ([threads
           (map (lambda (i)
                  (fork-thread
                    (lambda ()
                      (let loop ([n 100])
                        (when (> n 0)
                          (if (even? i)
                            (dosync
                              (alter a - 1)
                              (alter b + 1))
                            (dosync
                              (alter b - 1)
                              (alter a + 1)))
                          (loop (- n 1))))
                      (atomically (tvar-write! done (+ (tvar-read done) 1))))))
                '(0 1 2 3))])
      ;; Wait for all threads
      (for-each (lambda (t)
                  (let loop ()
                    (unless (= (tvar-ref done) 4)
                      (loop))))
                threads)
      ;; Total should be preserved
      (assert-equal (+ (ref-deref a) (ref-deref b)) 2000
        "total preserved"))))

;; =========================================================================
;; Error handling
;; =========================================================================

(test "exception in dosync rolls back"
  (let ([r (make-ref 42)])
    (guard (exn [#t (void)])
      (dosync
        (alter r + 100)
        (error 'test "boom")))
    (assert-equal (ref-deref r) 42 "unchanged after error")))

;; =========================================================================
;; or-else
;; =========================================================================

(test "or-else tries alternative on retry"
  (let ([r (make-ref 'fallback)])
    (let ([val (atomically
                 (or-else
                   (begin (retry) 'never)
                   (tvar-read r)))])
      (assert-equal val 'fallback "got fallback from or-else"))))

;; =========================================================================
;; io! — block side-effecting code inside transactions
;; =========================================================================

(test "io! body runs when called outside dosync"
  (let ([seen 0])
    (io! (set! seen 7))
    (assert-equal seen 7 "body ran outside txn")))

(test "io! returns body's value outside dosync"
  (assert-equal (io! (+ 1 2 3)) 6 "value returned"))

(test "io! inside dosync raises"
  (let ([r (make-ref 0)])
    (let ([caught
           (guard (exn [#t 'caught])
             (dosync
               (alter r + 1)
               (io! (displayln "should not print"))
               (alter r + 1))
             'finished)])
      (assert-equal caught 'caught "io! raised inside dosync")
      (assert-equal (ref-deref r) 0 "dosync rolled back"))))

(test "io! inside nested dosync also raises"
  (let ([caught
         (guard (exn [#t 'caught])
           (dosync
             (dosync (io! (+ 1 1)))
             'finished))])
    (assert-equal caught 'caught "io! raised inside nested dosync")))

;; =========================================================================
;; Summary
;; =========================================================================
(newline)
(displayln (str "========================================="))
(displayln (str "Results: " pass-count "/" test-count " passed"))
(displayln (str "========================================="))
(when (< pass-count test-count)
  (exit 1))
