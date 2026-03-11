#!chezscheme
;;; Tests for (std effect) — Algebraic effect system

(import (chezscheme) (std effect))

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
                  (printf "FAIL ~a: got ~s, expected ~s~%" name got expected)))))]))

(printf "--- (std effect) tests ---~%")

;;;; Effect 1: State

(defeffect State
  (get)
  (put val))

(test "state/get basic"
  (let ([st 10])
    (with-handler ([State
                    (get (k) (resume k st))
                    (put (k v) (set! st v) (resume k (void)))])
      (State get)))
  10)

(test "state/put+get"
  (let ([st 0])
    (with-handler ([State
                    (get (k) (resume k st))
                    (put (k v) (set! st v) (resume k (void)))])
      (State put 42)
      (State get)))
  42)

(test "state/multiple ops in sequence"
  (let ([st 1])
    (with-handler ([State
                    (get (k) (resume k st))
                    (put (k v) (set! st v) (resume k (void)))])
      (State put (+ (State get) 10))
      (State put (+ (State get) 5))
      (State get)))
  16)

;;;; Effect 2: Logging (append-only)

(defeffect Log
  (emit msg))

(test "log/emit"
  (let ([log '()])
    (with-handler ([Log
                    (emit (k msg)
                      (set! log (append log (list msg)))
                      (resume k (void)))])
      (Log emit "hello")
      (Log emit "world")
      log))
  '("hello" "world"))

;;;; Effect 3: Abort (non-resuming)

(defeffect Abort
  (abort val))

(test "abort/basic"
  (call-with-current-continuation
    (lambda (escape)
      (with-handler ([Abort
                      (abort (k v) (escape v))])
        (Abort abort 'done)
        'never-reached)))
  'done)

(test "abort/skips remaining"
  (let ([counter 0])
    (call-with-current-continuation
      (lambda (escape)
        (with-handler ([Abort
                        (abort (k v) (escape counter))])
          (set! counter (+ counter 1))
          (Abort abort 'stop)
          (set! counter (+ counter 1)))))  ;; this line not reached
    counter)
  1)

;;;; Effect 4: Choose (nondeterminism stub — single-shot returns first choice)

(defeffect Choose
  (flip))

(test "choose/true"
  (with-handler ([Choose (flip (k) (resume k #t))])
    (Choose flip))
  #t)

(test "choose/false"
  (with-handler ([Choose (flip (k) (resume k #f))])
    (Choose flip))
  #f)

;;;; Effect 5: Unhandled effect raises condition

(defeffect Unhandled
  (boom))

(test "unhandled/raises condition"
  (guard (exn [(effect-not-handled? exn) 'caught])
    (Unhandled boom)
    'missed)
  'caught)

;;;; Effect 6: Nested handlers — inner wins

(defeffect Counter
  (tick))

(test "nested/inner wins"
  (with-handler ([Counter (tick (k) (resume k 1))])
    (with-handler ([Counter (tick (k) (resume k 2))])
      (Counter tick)))
  2)

(test "nested/outer fallback after inner exits"
  (with-handler ([Counter (tick (k) (resume k 100))])
    (let ([inner
           (with-handler ([Counter (tick (k) (resume k 200))])
             (Counter tick))])
      ;; after inner handler exits, outer handles
      (list inner (Counter tick))))
  '(200 100))

;;;; Effect 7: Combining multiple effects

(defeffect Yield
  (yield val))

(test "two effects together"
  (let ([log '()] [st 0])
    (with-handler ([State
                    (get (k) (resume k st))
                    (put (k v) (set! st v) (resume k (void)))]
                   [Log
                    (emit (k msg) (set! log (append log (list msg))) (resume k (void)))])
      (State put 5)
      (Log emit "a")
      (State put (+ (State get) 3))
      (Log emit "b")
      (list (State get) log)))
  '(8 ("a" "b")))

;;;; Effect 8: perform macro (alias)

(test "perform alias"
  (let ([st 77])
    (with-handler ([State
                    (get (k) (resume k st))
                    (put (k v) (set! st v) (resume k (void)))])
      (perform (State get))))
  77)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
