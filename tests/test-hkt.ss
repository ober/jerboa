#!chezscheme
;;; Tests for (std typed hkt) — Higher-Kinded Types

(import (chezscheme) (std typed hkt))

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

(printf "--- (std typed hkt) tests ---~%")

;;; ===== Option type =====

(test "Some? true"  (Some? (make-Some 42))  #t)
(test "Some? false" (Some? (make-None))     #f)
(test "None? true"  (None? (make-None))     #t)
(test "None? false" (None? (make-Some 1))   #f)
(test "Some-val"    (Some-val (make-Some 99)) 99)
(test "Some-val string" (Some-val (make-Some "hi")) "hi")

;;; ===== option-fmap =====

(test "option-fmap Some"
  (Some-val (option-fmap (lambda (x) (* x 2)) (make-Some 5)))
  10)

(test "option-fmap None"
  (None? (option-fmap (lambda (x) (* x 2)) (make-None)))
  #t)

;;; ===== option-bind =====

(test "option-bind Some->Some"
  (Some-val (option-bind (make-Some 3) (lambda (x) (make-Some (+ x 1)))))
  4)

(test "option-bind Some->None"
  (None? (option-bind (make-Some 3) (lambda (_) (make-None))))
  #t)

(test "option-bind None"
  (None? (option-bind (make-None) (lambda (x) (make-Some x))))
  #t)

;;; ===== option-return =====

(test "option-return"
  (Some-val (option-return 42))
  42)

;;; ===== Result type =====

(test "Ok? true"  (Ok? (make-Ok 1))    #t)
(test "Ok? false" (Ok? (make-Err "e")) #f)
(test "Err? true" (Err? (make-Err "x")) #t)
(test "Err? false" (Err? (make-Ok 1))   #f)
(test "Ok-val"    (Ok-val (make-Ok 99)) 99)
(test "Err-val"   (Err-val (make-Err "oops")) "oops")

;;; ===== result-fmap =====

(test "result-fmap Ok"
  (Ok-val (result-fmap (lambda (x) (+ x 10)) (make-Ok 5)))
  15)

(test "result-fmap Err"
  (Err-val (result-fmap (lambda (x) (+ x 10)) (make-Err "bad")))
  "bad")

;;; ===== result-bind =====

(test "result-bind Ok->Ok"
  (Ok-val (result-bind (make-Ok 7) (lambda (x) (make-Ok (* x 3)))))
  21)

(test "result-bind Ok->Err"
  (Err-val (result-bind (make-Ok 7) (lambda (_) (make-Err "nope"))))
  "nope")

(test "result-bind Err"
  (Err? (result-bind (make-Err "fail") (lambda (x) (make-Ok x))))
  #t)

;;; ===== HKT protocol / instance lookup =====

(test-pred "hkt-instance? Functor Option"
  (hkt-instance? 'Functor 'Option))

(test-pred "hkt-instance? Functor List"
  (hkt-instance? 'Functor 'List))

(test-pred "hkt-instance? Monad Option"
  (hkt-instance? 'Monad 'Option))

(test-pred "hkt-instance? Monad List"
  (hkt-instance? 'Monad 'List))

;;; ===== Functor via hkt-dispatch =====

(test "Functor fmap Option Some"
  (Some-val (hkt-dispatch 'Functor 'fmap 'Option (lambda (x) (* x 2)) (make-Some 5)))
  10)

(test "Functor fmap Option None"
  (None? (hkt-dispatch 'Functor 'fmap 'Option (lambda (x) x) (make-None)))
  #t)

(test "Functor fmap List"
  (hkt-dispatch 'Functor 'fmap 'List (lambda (x) (* x 3)) '(1 2 3))
  '(3 6 9))

;;; ===== Monad via hkt-dispatch =====

(test "Monad return Option"
  (Some-val (hkt-dispatch 'Monad 'return 'Option 42))
  42)

(test "Monad bind List"
  (hkt-dispatch 'Monad 'bind 'List '(1 2 3) (lambda (x) (list x (* x 10))))
  '(1 10 2 20 3 30))

;;; ===== do/m notation =====

(test "do/m Option: all Some"
  (Some-val
    (do/m Option
      [x <- (make-Some 3)]
      [y <- (make-Some 4)]
      (make-Some (+ x y))))
  7)

(test "do/m Option: None short-circuits"
  (None?
    (do/m Option
      [x <- (make-Some 3)]
      [_ <- (make-None)]
      (make-Some x)))
  #t)

(test "do/m List: cartesian product"
  (do/m List
    [x <- '(1 2)]
    [y <- '(10 20)]
    (list (+ x y)))
  '(11 21 12 22))

(test "do/m Option: let binding"
  (Some-val
    (do/m Option
      [x <- (make-Some 5)]
      [let y = (* x 2)]
      (make-Some y)))
  10)

;;; ===== Applicative =====

(test "Applicative pure Option"
  (Some-val (hkt-dispatch 'Applicative 'pure 'Option 99))
  99)

(test "Applicative ap Option Some"
  (Some-val
    (hkt-dispatch 'Applicative 'ap 'Option
      (make-Some (lambda (x) (* x 5)))
      (make-Some 6)))
  30)

(test "Applicative ap Option None f"
  (None?
    (hkt-dispatch 'Applicative 'ap 'Option
      (make-None)
      (make-Some 6)))
  #t)

(test "Applicative ap List"
  (hkt-dispatch 'Applicative 'ap 'List
    (list (lambda (x) (* x 2)) (lambda (x) (+ x 10)))
    '(1 2 3))
  '(2 4 6 11 12 13))

;;; ===== Foldable =====

(test "Foldable Option fold Some"
  (hkt-dispatch 'Foldable 'fold-hkt 'Option + 0 (make-Some 42))
  42)

(test "Foldable Option fold None"
  (hkt-dispatch 'Foldable 'fold-hkt 'Option + 0 (make-None))
  0)

(test "Foldable List fold"
  (hkt-dispatch 'Foldable 'fold-hkt 'List + 0 '(1 2 3 4 5))
  15)

;;; ===== defprotocol-hkt + implement-hkt =====

(defprotocol-hkt MyTC
  (my-map f fa)
  (my-unit a))

(implement-hkt MyTC MyList
  (my-map  (lambda (f fa) (map f fa)))
  (my-unit (lambda (a) (list a))))

(test "custom HKT instance my-map"
  (hkt-dispatch 'MyTC 'my-map 'MyList (lambda (x) (* x 2)) '(1 2 3))
  '(2 4 6))

(test "custom HKT instance my-unit"
  (hkt-dispatch 'MyTC 'my-unit 'MyList 'hello)
  '(hello))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
