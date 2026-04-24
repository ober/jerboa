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

;;; ---- Hierarchy (Round 5 §35) -----------------------------------

(test "fresh hierarchy has no parents for unknown tag"
  (parents (make-hierarchy) 'anything)
  '())

(test "derive adds parent relationship"
  (let ([h (make-hierarchy)])
    (derive h 'dog 'mammal)
    (parents h 'dog))
  '(mammal))

(test "derive transitive ancestors via BFS"
  (let ([h (make-hierarchy)])
    (derive h 'corgi 'dog)
    (derive h 'dog 'mammal)
    (derive h 'mammal 'animal)
    (ancestors h 'corgi))
  '(dog mammal animal))

(test "derive transitive descendants"
  (let ([h (make-hierarchy)])
    (derive h 'corgi 'dog)
    (derive h 'dog 'mammal)
    (derive h 'poodle 'dog)
    (list-sort (lambda (a b) (string<? (symbol->string a) (symbol->string b)))
               (descendants h 'mammal)))
  '(corgi dog poodle))

(test "isa? direct parent"
  (let ([h (make-hierarchy)])
    (derive h 'dog 'mammal)
    (isa? h 'dog 'mammal))
  #t)

(test "isa? transitive"
  (let ([h (make-hierarchy)])
    (derive h 'corgi 'dog)
    (derive h 'dog 'mammal)
    (isa? h 'corgi 'mammal))
  #t)

(test "isa? self"
  (isa? (make-hierarchy) 'x 'x)
  #t)

(test "isa? negative"
  (isa? (make-hierarchy) 'cat 'dog)
  #f)

(test "derive rejects self-cycle"
  (guard (_ [else 'raised])
    (derive (make-hierarchy) 'a 'a))
  'raised)

(test "derive rejects indirect cycle"
  (guard (_ [else 'raised])
    (let ([h (make-hierarchy)])
      (derive h 'a 'b)
      (derive h 'b 'a)))
  'raised)

(test "underive removes relation"
  (let ([h (make-hierarchy)])
    (derive h 'dog 'mammal)
    (underive h 'dog 'mammal)
    (parents h 'dog))
  '())

;;; ---- Hierarchy dispatch (multimethod walks ancestors) ----------

(derive 'corgi 'dog)
(derive 'dog 'mammal)

(defmulti legs (lambda (animal) animal))
(defmethod legs 'mammal (a) 4)
(defmethod legs 'bird (a) 2)

(test "exact match wins over hierarchy"
  (begin
    (defmethod legs 'corgi (a) 'stubby)
    (legs 'corgi))
  'stubby)

(test "hierarchy match: dog -> mammal"
  (legs 'dog)
  4)

(test "hierarchy match: corgi falls back to mammal when corgi removed"
  (begin
    (remove-method legs 'corgi)
    (legs 'corgi))
  4)

(test "dispatch raises on unrelated dispatch value with no default"
  (guard (_ [else 'raised])
    (legs 'sparrow-type-that-doesnt-exist))
  'raised)

;;; ---- prefer-method / preferred-methods -------------------------

(defmulti describe (lambda (x) x))
(defmethod describe 'swimmer (x) "swims")
(defmethod describe 'flyer (x) "flies")
(derive 'duck 'swimmer)
(derive 'duck 'flyer)

(test "ambiguous dispatch raises without preference"
  (guard (_ [else 'raised])
    (describe 'duck))
  'raised)

(test "prefer-method resolves ambiguity"
  (begin
    (prefer-method describe 'swimmer 'flyer)
    (describe 'duck))
  "swims")

(test "preferred-methods lists installed preferences"
  (let ([prefs (preferred-methods describe)])
    (and (member '(swimmer . flyer) prefs) #t))
  #t)

(test "prefer-method is idempotent"
  (begin
    (prefer-method describe 'swimmer 'flyer)
    (prefer-method describe 'swimmer 'flyer)
    (length (preferred-methods describe)))
  1)

(test "prefer-method rejects self"
  (guard (_ [else 'raised])
    (prefer-method describe 'a 'a))
  'raised)

(test "prefer-method rejects cycle"
  (guard (_ [else 'raised])
    (prefer-method describe 'flyer 'swimmer))
  'raised)

;;; ---- Summary ----
(printf "~%std/multi: ~a passed, ~a failed~%" pass fail)
(when (> fail 0) (exit 1))
