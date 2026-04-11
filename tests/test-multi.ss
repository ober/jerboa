#!chezscheme
;;; Tests for (std multi) — Clojure-style value-dispatched multimethods.

(import (except (jerboa prelude) defmethod)
        (std multi))

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

(printf "--- std/multi ---~%~%")

;;; ---- Basic dispatch (top-level defmulti is the only place
;;; ---- defmulti is allowed; tests below use `describe` as a
;;; ---- shared fixture).

(defmulti describe (lambda (x) (car x)))
(defmethod describe 'cat  (x) (list 'cat  (cadr x)))
(defmethod describe 'dog  (x) (list 'dog  (cadr x)))
(defmethod describe 'default (x) (list 'unknown (car x)))

(test "dispatch cat"
  (describe '(cat "whiskers"))
  '(cat "whiskers"))

(test "dispatch dog"
  (describe '(dog "rover"))
  '(dog "rover"))

(test "dispatch falls through to default"
  (describe '(fish "nemo"))
  '(unknown fish))

;;; ---- multimethod predicate and introspection ----

(test "multimethod? true for defmulti-created procs"
  (multimethod? describe)
  #t)

(test "multimethod? false for normal procedures"
  (multimethod? car)
  #f)

(test "multimethod-name"
  (multimethod-name describe)
  'describe)

(test "methods returns alist of registered non-default entries"
  (let ([m (methods describe)])
    (list-sort (lambda (a b)
                 (string<? (symbol->string (car a))
                           (symbol->string (car b))))
               (map (lambda (e) (cons (car e) 'proc)) m)))
  '((cat . proc) (dog . proc)))

(test "get-method finds registered key"
  (and (get-method describe 'cat) #t)
  #t)

(test "get-method returns #f for missing key"
  (get-method describe 'nonexistent)
  #f)

(test "get-method 'default returns the default method"
  (and (get-method describe 'default) #t)
  #t)

;;; ---- remove-method ----

(defmulti greeting (lambda (x) x))
(defmethod greeting 'hi (x) "hello")
(defmethod greeting 'bye (x) "goodbye")

(test "before remove-method 'hi -> hello"
  (greeting 'hi)
  "hello")

(test "remove-method drops the method"
  (begin
    (remove-method greeting 'hi)
    (guard (_ [else 'no-method])
      (greeting 'hi)))
  'no-method)

(test "remove-method idempotent"
  (begin
    (remove-method greeting 'hi)
    (remove-method greeting 'hi)
    (greeting 'bye))
  "goodbye")

(test "remove-method 'default clears the default"
  (let ()
    (defmulti op (lambda (x) x))
    (defmethod op 'default (x) 'fallback)
    (let ([before (op 'anything)])
      (remove-method op 'default)
      (list before
            (guard (_ [else 'missed]) (op 'anything)))))
  '(fallback missed))

;;; ---- No default => raise ----

(defmulti strict (lambda (x) x))
(defmethod strict 'ok (x) 'good)

(test "no default raises on miss"
  (guard (_ [else 'raised])
    (strict 'missing))
  'raised)

(test "no default still dispatches found methods"
  (strict 'ok)
  'good)

;;; ---- Redefining a method replaces ----

(defmulti tag (lambda (x) x))
(defmethod tag 'a (x) 1)

(test "redefine method replaces"
  (begin
    (defmethod tag 'a (x) 2)
    (tag 'a))
  2)

;;; ---- Equal?-based keys: any hashable value ----

(defmulti kind (lambda (x) x))
(defmethod kind "string-key"  (x) 'string)
(defmethod kind 42            (x) 'int)
(defmethod kind '(nested key) (x) 'list)

(test "string dispatch key"
  (kind "string-key")
  'string)

(test "integer dispatch key"
  (kind 42)
  'int)

(test "list dispatch key (equal? not eq?)"
  (kind (list 'nested 'key))
  'list)

;;; ---- Multi-argument dispatch ----

(defmulti encounter
  (lambda (a b) (cons (car a) (car b))))
(defmethod encounter '(cat . mouse)  (a b) 'chase)
(defmethod encounter '(dog . cat)    (a b) 'chase)
(defmethod encounter 'default        (a b) 'ignore)

(test "two-arg dispatch cat/mouse"
  (encounter '(cat whiskers) '(mouse jerry))
  'chase)

(test "two-arg dispatch fell through to default"
  (encounter '(cow bessie) '(bird tweety))
  'ignore)

;;; ---- remove-method / get-method error on non-multimethods ----

(test "remove-method on plain proc raises"
  (guard (_ [else 'raised])
    (remove-method car 'x))
  'raised)

(test "get-method on plain proc raises"
  (guard (_ [else 'raised])
    (get-method car 'x))
  'raised)

;;; ---- Summary ----
(printf "~%std/multi: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
