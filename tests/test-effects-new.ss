#!chezscheme
;;; Tests for (std typed effects) — Enhanced effect typing (Phase 4b)

(import (chezscheme) (std typed effects))

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

(define-syntax test-error
  (syntax-rules ()
    [(_ name expr)
     (guard (exn [#t (set! pass (+ pass 1)) (printf "  ok ~a~%" name)])
       expr
       (set! fail (+ fail 1))
       (printf "FAIL ~a: expected error but got none~%" name))]))

(printf "--- (std typed effects) tests ---~%~%")

;; ===== Eff Type Constructor =====

(printf "-- Eff type constructor --~%")

(test "make-eff-type creates eff-type"
  (eff-type? (make-eff-type '(State IO) 'fixnum))
  #t)

(test "eff-type? false for list"
  (eff-type? '(State IO))
  #f)

(test "eff-type? false for #f"
  (eff-type? #f)
  #f)

(test "eff-type-effects"
  (eff-type-effects (make-eff-type '(State IO) 'fixnum))
  '(State IO))

(test "eff-type-return"
  (eff-type-return (make-eff-type '(State IO) 'fixnum))
  'fixnum)

(test "eff-type-effects empty"
  (eff-type-effects (make-eff-type '() 'string))
  '())

;; ===== Eff Syntax =====

(printf "~%-- Eff syntax --~%")

(test "Eff creates eff-type"
  (eff-type? (Eff (State IO) fixnum))
  #t)

(test "Eff effects"
  (eff-type-effects (Eff (State IO) fixnum))
  '(State IO))

(test "Eff return type"
  (eff-type-return (Eff (State IO) fixnum))
  'fixnum)

(test "Eff empty effects"
  (eff-type-effects (Eff () string))
  '())

;; ===== Pure =====

(printf "~%-- Pure --~%")

(test "Pure creates eff-type"
  (eff-type? (Pure fixnum))
  #t)

(test "pure? true for Pure"
  (pure? (Pure string))
  #t)

(test "pure? true for empty effects"
  (pure? (make-eff-type '() 'any))
  #t)

(test "pure? false for non-empty effects"
  (pure? (Eff (State) fixnum))
  #f)

(test "pure? false for non-eff-type"
  (pure? 42)
  #f)

(test "Pure return type"
  (eff-type-return (Pure fixnum))
  'fixnum)

;; ===== Effect Set Operations =====

(printf "~%-- effect set operations --~%")

(test "empty-effect-set is empty list"
  empty-effect-set
  '())

(test "effect-set-union combines sets"
  (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
             (effect-set-union '(State IO) '(IO Logger)))
  '(IO Logger State))

(test "effect-set-union no duplicates"
  (length (effect-set-union '(A B) '(B C)))
  3)

(test "effect-set-union with empty"
  (effect-set-union '(A B) '())
  '(A B))

(test "effect-set-union both empty"
  (effect-set-union '() '())
  '())

(test "effect-set-intersect common elements"
  (effect-set-intersect '(State IO Logger) '(IO Logger DB))
  '(IO Logger))

(test "effect-set-intersect disjoint"
  (effect-set-intersect '(A B) '(C D))
  '())

(test "effect-set-intersect empty result"
  (effect-set-intersect '(State) '(IO))
  '())

(test "effect-set-difference removes elements"
  (effect-set-difference '(State IO Logger) '(IO))
  '(State Logger))

(test "effect-set-difference all removed"
  (effect-set-difference '(A B) '(A B C))
  '())

(test "effect-set-difference none removed"
  (effect-set-difference '(A B) '(C D))
  '(A B))

(test "effect-set-member? found"
  (effect-set-member? 'State '(State IO Logger))
  #t)

(test "effect-set-member? not found"
  (effect-set-member? 'DB '(State IO Logger))
  #f)

(test "effect-set-member? empty set"
  (effect-set-member? 'State '())
  #f)

;; ===== Discharge Effect =====

(printf "~%-- discharge-effect --~%")

(test "discharge-effect removes one effect"
  (eff-type-effects (discharge-effect (Eff (State IO) fixnum) 'State))
  '(IO))

(test "discharge-effect preserves return type"
  (eff-type-return (discharge-effect (Eff (State IO) fixnum) 'State))
  'fixnum)

(test "discharge-effect removes all effects"
  (let* ([et (discharge-effect (Eff (State) fixnum) 'State)])
    (pure? et))
  #t)

(test "discharge-effect no-op for missing effect"
  (eff-type-effects (discharge-effect (Eff (State IO) fixnum) 'Logger))
  '(State IO))

;; ===== Check Effects =====

(printf "~%-- check-effects! --~%")

(test "check-effects! all handled"
  (check-effects! (Eff (State IO) fixnum) '(State IO Logger))
  #t)

(test "check-effects! exact match"
  (check-effects! (Eff (State IO) fixnum) '(State IO))
  #t)

(test "check-effects! pure type always passes"
  (check-effects! (Pure fixnum) '())
  #t)

(test "check-effects! unhandled effects returns false"
  (check-effects! (Eff (State IO Logger) fixnum) '(State))
  #f)

(test "check-effects! empty handled set fails for non-pure"
  (check-effects! (Eff (State) fixnum) '())
  #f)

;; ===== Infer Effects =====

(printf "~%-- infer-effects --~%")

(test "infer-effects finds State"
  (memq 'State (infer-effects '(State get)))
  '(State))

(test "infer-effects finds multiple effects"
  (let ([effects (infer-effects '(begin (State put 42) (IO print "hello")))])
    (and (if (memq 'State effects) #t #f)
         (if (memq 'IO effects) #t #f)))
  #t)

(test "infer-effects ignores lowercase"
  (infer-effects '(begin (define x 1) (+ x 2)))
  '())

(test "infer-effects ignores Eff and Pure"
  (infer-effects '(Eff (State) fixnum))
  '(State))

;; ===== define/te =====

(printf "~%-- define/te --~%")

(define/te (simple-func x) : (Eff (State) fixnum)
  (* x 2))

(test "define/te function works"
  (simple-func 5)
  10)

(define/te (pure-func x y) : (Pure fixnum)
  (+ x y))

(test "define/te pure function works"
  (pure-func 3 4)
  7)

(define/te (no-annotation x)
  (string-length x))

(test "define/te without annotation works"
  (no-annotation "hello")
  5)

(define/te (typed-args [x : fixnum] [y : fixnum]) : (Pure fixnum)
  (+ x y))

(test "define/te with arg types works"
  (typed-args 10 20)
  30)

;; ===== lambda/te =====

(printf "~%-- lambda/te --~%")

(test "lambda/te creates function"
  (let ([f (lambda/te (x y) : (Pure fixnum) (* x y))])
    (f 3 4))
  12)

(test "lambda/te with typed args"
  (let ([f (lambda/te ([x : fixnum]) : (Pure fixnum) (* x 2))])
    (f 7))
  14)

(test "lambda/te without annotation"
  (let ([f (lambda/te (x) (string-length x))])
    (f "hello"))
  5)

;; ===== *warn-unhandled-effects* =====

(printf "~%-- *warn-unhandled-effects* parameter --~%")

(test "*warn-unhandled-effects* default is #f"
  (*warn-unhandled-effects*)
  #f)

(test "*warn-unhandled-effects* can be set to #t"
  (parameterize ([*warn-unhandled-effects* #t])
    (*warn-unhandled-effects*))
  #t)

(test "*warn-unhandled-effects* restored after parameterize"
  (begin
    (parameterize ([*warn-unhandled-effects* #t]) (void))
    (*warn-unhandled-effects*))
  #f)

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
