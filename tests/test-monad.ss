#!chezscheme
;;; Tests for (std typed monad) — Monad utilities

(import (chezscheme) (std typed hkt) (std typed monad))

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

(define-syntax test-pred
  (syntax-rules ()
    [(_ name expr)
     (guard (exn [#t (set! fail (+ fail 1))
                     (printf "FAIL ~a: ~a~%" name
                       (if (message-condition? exn) (condition-message exn) exn))])
       (if expr
         (begin (set! pass (+ pass 1)) (printf "  ok ~a~%" name))
         (begin (set! fail (+ fail 1))
                (printf "FAIL ~a: expected truthy~%" name))))]))

(printf "--- (std typed monad) tests ---~%")

;;; ===== monad-map =====

(test "monad-map Option Some"
  (Some-val (monad-map 'Option (lambda (x) (* x 3)) (make-Some 4)))
  12)

(test "monad-map Option None"
  (None? (monad-map 'Option (lambda (x) (* x 3)) (make-None)))
  #t)

(test "monad-map List"
  (monad-map 'List (lambda (x) (* x 2)) '(1 2 3))
  '(2 4 6))

;;; ===== monad-sequence =====

(test "monad-sequence Option all Some"
  (Some-val (monad-sequence 'Option (list (make-Some 1) (make-Some 2) (make-Some 3))))
  '(1 2 3))

(test "monad-sequence Option with None"
  (None? (monad-sequence 'Option (list (make-Some 1) (make-None) (make-Some 3))))
  #t)

(test "monad-sequence Option empty"
  (Some-val (monad-sequence 'Option '()))
  '())

(test "monad-sequence List"
  (monad-sequence 'List '((1 2) (3 4)))
  '((1 3) (1 4) (2 3) (2 4)))

;;; ===== monad-mapM =====

(test "monad-mapM Option all Some"
  (Some-val
    (monad-mapM 'Option (lambda (x) (make-Some (* x 10))) '(1 2 3)))
  '(10 20 30))

(test "monad-mapM Option with None"
  (None?
    (monad-mapM 'Option
      (lambda (x) (if (even? x) (make-Some x) (make-None)))
      '(2 4 6)))
  #f)  ; all even, so all Some

(test "monad-mapM Option None in middle"
  (None?
    (monad-mapM 'Option
      (lambda (x) (if (even? x) (make-Some x) (make-None)))
      '(2 3 4)))
  #t)

;;; ===== monad-when =====

(test "monad-when true"
  (Some-val (monad-when 'Option #t (make-Some 42)))
  42)

(test "monad-when false"
  (Some-val (monad-when 'Option #f (make-Some 42)))
  (void))

;;; ===== monad-unless =====

(test "monad-unless false = execute"
  (Some-val (monad-unless 'Option #f (make-Some 99)))
  99)

(test "monad-unless true = skip"
  (Some-val (monad-unless 'Option #t (make-Some 99)))
  (void))

;;; ===== monad-void =====

(test "monad-void Option"
  (Some-val (monad-void 'Option (make-Some 42)))
  (void))

(test "monad-void Option None"
  (None? (monad-void 'Option (make-None)))
  #t)

;;; ===== monad-guard =====

(test "monad-guard List true"
  (monad-guard 'List #t)
  (list (void)))

(test "monad-guard List false"
  (monad-guard 'List #f)
  '())

(test "monad-guard Option true"
  (Some? (monad-guard 'Option #t))
  #t)

(test "monad-guard Option false"
  (None? (monad-guard 'Option #f))
  #t)

;;; ===== monad-join =====

(test "monad-join Option nested Some"
  (Some-val (monad-join 'Option (make-Some (make-Some 7))))
  7)

(test "monad-join Option outer None"
  (None? (monad-join 'Option (make-None)))
  #t)

(test "monad-join List"
  (monad-join 'List '((1 2) (3 4) (5)))
  '(1 2 3 4 5))

;;; ===== State monad =====

(test "run-state basic"
  (call-with-values
    (lambda ()
      (run-state (state-return 42) 'initial))
    (lambda (result state)
      (list result state)))
  '(42 initial))

(test "state-get"
  (eval-state state-get 99)
  99)

(test "state-put"
  (exec-state (state-put 'new-state) 'old)
  'new-state)

(test "state-modify"
  (exec-state (state-modify (lambda (s) (* s 2))) 5)
  10)

(test "state-bind: get then put"
  (let ([sm (state-bind state-get
              (lambda (s)
                (state-put (* s 10))))])
    (exec-state sm 3))
  30)

(test "state-bind: threaded computation"
  (let* ([sm1 (state-put 1)]
         [sm2 (state-bind sm1 (lambda (_) (state-modify (lambda (s) (+ s 1)))))]
         [sm3 (state-bind sm2 (lambda (_) state-get))])
    (eval-state sm3 0))
  2)

(test "eval-state vs exec-state"
  (let ([sm (state-bind state-get
              (lambda (n)
                (state-return (* n 3))))])
    (list (eval-state sm 7) (exec-state sm 7)))
  '(21 7))

;;; ===== Reader monad =====

(test "run-reader basic"
  (run-reader (reader-return 42) 'env)
  42)

(test "reader-ask"
  (run-reader reader-ask 'my-env)
  'my-env)

(test "reader-local"
  (run-reader
    (reader-local (lambda (env) (* env 2)) reader-ask)
    5)
  10)

(test "reader-bind"
  (run-reader
    (reader-bind reader-ask (lambda (env) (reader-return (* env 3))))
    4)
  12)

(test "reader-bind nested"
  (run-reader
    (reader-bind reader-ask
      (lambda (e1)
        (reader-local (lambda (_) (+ e1 10))
          (reader-bind reader-ask
            (lambda (e2)
              (reader-return (+ e1 e2)))))))
    5)
  20)

;;; ===== Writer monad =====

(test "run-writer basic"
  (call-with-values
    (lambda () (run-writer (writer-return 42)))
    list)
  '(42 ()))

(test "writer-tell"
  (call-with-values
    (lambda () (run-writer (writer-tell "hello")))
    list)
  (list (void) '("hello")))

(test "writer-bind accumulates log"
  (call-with-values
    (lambda ()
      (run-writer
        (writer-bind (writer-tell "a")
          (lambda (_)
            (writer-bind (writer-tell "b")
              (lambda (_)
                (writer-return 'done)))))))
    list)
  '(done ("a" "b")))

(test "writer-listen"
  (call-with-values
    (lambda ()
      (run-writer
        (writer-listen
          (writer-bind (writer-tell "msg")
            (lambda (_) (writer-return 42))))))
    (lambda (result log)
      result))
  '(42 . ("msg")))

;;; ===== Maybe monad =====

(test "maybe-bind Some"
  (Some-val (maybe-bind (make-Some 5) (lambda (x) (make-Some (* x 2)))))
  10)

(test "maybe-bind None"
  (None? (maybe-bind (make-None) (lambda (x) (make-Some x))))
  #t)

(test "maybe-return"
  (Some-val (maybe-return 77))
  77)

(test "from-maybe Some"
  (from-maybe 0 (make-Some 42))
  42)

(test "from-maybe None"
  (from-maybe 0 (make-None))
  0)

;;; ===== lift =====

(test "lift passes through"
  (lift 42)
  42)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
