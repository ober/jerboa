#!chezscheme
;;; Tests for (std typed env) — Type environment management

(import (chezscheme) (std typed env))

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

(define-syntax test-true
  (syntax-rules ()
    [(_ name expr)
     (test name (if expr #t #f) #t)]))

(printf "--- (std typed env) tests ---~%")

;;;; Test 1: (empty-type-env) creates an env

(test-true "type-env/empty-type-env creates env"
  (let ([env (empty-type-env)])
    (type-env? env)))

;;;; Test 2: type-env? predicate

(test "type-env?/true for env"
  (type-env? (empty-type-env))
  #t)

(test "type-env?/false for non-env"
  (type-env? 42)
  #f)

(test "type-env?/false for #f"
  (type-env? #f)
  #f)

(test "type-env?/false for list"
  (type-env? '(a b))
  #f)

;;;; Test 3: type-env-bind! and type-env-lookup basic

(test "type-env/bind! and lookup basic"
  (let ([env (empty-type-env)])
    (type-env-bind! env 'x 'fixnum)
    (type-env-lookup env 'x))
  'fixnum)

(test "type-env/bind! multiple and lookup"
  (let ([env (empty-type-env)])
    (type-env-bind! env 'x 'fixnum)
    (type-env-bind! env 'y 'string)
    (list (type-env-lookup env 'x)
          (type-env-lookup env 'y)))
  '(fixnum string))

;;;; Test 4: Lookup in parent env when not in child

(test "type-env/lookup in parent"
  (let* ([parent (empty-type-env)]
         [_ (type-env-bind! parent 'x 'fixnum)]
         [child (make-type-env parent)])
    (type-env-lookup child 'x))
  'fixnum)

;;;; Test 5: Child env shadows parent binding

(test "type-env/child shadows parent"
  (let* ([parent (empty-type-env)]
         [_ (type-env-bind! parent 'x 'fixnum)]
         [child (make-type-env parent)]
         [_ (type-env-bind! child 'x 'string)])
    (type-env-lookup child 'x))
  'string)

(test "type-env/parent unaffected by child shadow"
  (let* ([parent (empty-type-env)]
         [_ (type-env-bind! parent 'x 'fixnum)]
         [child (make-type-env parent)]
         [_ (type-env-bind! child 'x 'string)])
    ;; parent still sees original binding
    (type-env-lookup parent 'x))
  'fixnum)

;;;; Test 6: type-env-extend returns new env without mutating parent

(test "type-env/extend returns new env"
  (let* ([parent (empty-type-env)]
         [child (type-env-extend parent '((x . fixnum) (y . string)))])
    (type-env? child))
  #t)

(test "type-env/extend child has bindings"
  (let* ([parent (empty-type-env)]
         [child (type-env-extend parent '((x . fixnum) (y . string)))])
    (list (type-env-lookup child 'x)
          (type-env-lookup child 'y)))
  '(fixnum string))

(test "type-env/extend parent unmodified"
  (let* ([parent (empty-type-env)]
         [_ (type-env-extend parent '((x . fixnum)))])
    ;; x was added to child, not parent
    (type-env-lookup parent 'x))
  #f)

;;;; Test 7: Multiple bindings in same env

(test "type-env/multiple bindings"
  (let ([env (empty-type-env)])
    (type-env-bind! env 'a 'fixnum)
    (type-env-bind! env 'b 'string)
    (type-env-bind! env 'c 'boolean)
    (type-env-bind! env 'd 'symbol)
    (list (type-env-lookup env 'a)
          (type-env-lookup env 'b)
          (type-env-lookup env 'c)
          (type-env-lookup env 'd)))
  '(fixnum string boolean symbol))

;;;; Test 8: Lookup of unbound name returns #f

(test "type-env/unbound returns #f"
  (let ([env (empty-type-env)])
    (type-env-lookup env 'nonexistent))
  #f)

(test "type-env/unbound in child and parent returns #f"
  (let* ([parent (empty-type-env)]
         [child (make-type-env parent)])
    (type-env-lookup child 'nonexistent))
  #f)

;;;; Test 9: type-env->list returns alist

(test "type-env->list/empty env"
  (type-env->list (empty-type-env))
  '())

(test "type-env->list/single binding"
  (let ([env (empty-type-env)])
    (type-env-bind! env 'x 'fixnum)
    (type-env->list env))
  '((x . fixnum)))

;; Multiple bindings: returned list contains all pairs (order may vary)
(test-true "type-env->list/multiple bindings contains all"
  (let ([env (empty-type-env)])
    (type-env-bind! env 'a 'fixnum)
    (type-env-bind! env 'b 'string)
    (let ([lst (type-env->list env)])
      (and (= (length lst) 2)
           (assq 'a lst)
           (assq 'b lst)
           (equal? (cdr (assq 'a lst)) 'fixnum)
           (equal? (cdr (assq 'b lst)) 'string)))))

;;;; Test 10: type-env->list includes parent bindings

(test-true "type-env->list/includes parent bindings"
  (let* ([parent (empty-type-env)]
         [_ (type-env-bind! parent 'x 'fixnum)]
         [child (make-type-env parent)]
         [_ (type-env-bind! child 'y 'string)])
    (let ([lst (type-env->list child)])
      ;; Should contain both x (from parent) and y (from child)
      (and (assq 'x lst)
           (assq 'y lst)))))

;;;; Test 11: make-type-env with #f parent creates root env

(test-true "type-env/make-type-env with #f parent"
  (let ([env (make-type-env #f)])
    (type-env? env)))

(test "type-env/make-type-env with #f no parent binding visible"
  (let ([env (make-type-env #f)])
    (type-env-lookup env 'x))
  #f)

;;;; Test 12: Overwriting a binding in same env

(test "type-env/overwrite binding"
  (let ([env (empty-type-env)])
    (type-env-bind! env 'x 'fixnum)
    (type-env-bind! env 'x 'string)
    (type-env-lookup env 'x))
  'string)

;;;; Test 13: Deep chain — 3 levels

(test "type-env/three-level chain lookup"
  (let* ([grandparent (empty-type-env)]
         [_ (type-env-bind! grandparent 'g 'any)]
         [parent (make-type-env grandparent)]
         [_ (type-env-bind! parent 'p 'fixnum)]
         [child (make-type-env parent)])
    (list (type-env-lookup child 'g)
          (type-env-lookup child 'p)))
  '(any fixnum))

(printf "~%~a tests: ~a passed, ~a failed~%"
  (+ pass fail) pass fail)
(when (> fail 0) (exit 1))
