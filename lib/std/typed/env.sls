#!chezscheme
;;; (std typed env) — Type environment management for the static type checker
;;;
;;; A type environment maps variable names (symbols) to type descriptors.
;;; Environments are chained: each child holds a reference to its parent,
;;; enabling lexically scoped type lookup without mutation of outer scopes.
;;;
;;; API:
;;;   (empty-type-env)                  — the root (empty) environment
;;;   (make-type-env parent)            — create a child env with given parent
;;;   (type-env? x)                     — predicate
;;;   (type-env-bind! env name type)    — mutably bind name→type in env
;;;   (type-env-lookup env name)        — look up type, walking parent chain
;;;   (type-env-extend env bindings)    — new child env with alist bindings
;;;   (type-env->list env)              — list all (name . type) pairs, local first

(library (std typed env)
  (export
    make-type-env
    type-env?
    empty-type-env
    type-env-bind!
    type-env-lookup
    type-env-extend
    type-env->list)

  (import (chezscheme))

  ;; ========== Internal record type ==========

  ;; An environment is a hash table of local bindings plus an optional parent.
  (define-record-type %type-env
    (fields
      (immutable parent)   ;; #f or another %type-env
      (immutable table))   ;; eq?-hashtable : symbol → type
    (sealed #t))

  ;; ========== Constructors ==========

  ;; Create the root (empty) environment with no parent.
  (define (empty-type-env)
    (make-%type-env #f (make-eq-hashtable)))

  ;; Create a fresh child environment whose parent is parent-env.
  ;; parent-env may be #f (creates a new root) or any type-env?.
  (define (make-type-env parent-env)
    (when (and parent-env (not (type-env? parent-env)))
      (error 'make-type-env "parent must be a type-env or #f" parent-env))
    (make-%type-env parent-env (make-eq-hashtable)))

  ;; ========== Predicate ==========

  (define (type-env? x)
    (%type-env? x))

  ;; ========== Mutation ==========

  ;; Mutably bind name (symbol) to type descriptor in env's local table.
  ;; Does not affect any parent environment.
  (define (type-env-bind! env name type)
    (unless (type-env? env)
      (error 'type-env-bind! "expected a type-env" env))
    (unless (symbol? name)
      (error 'type-env-bind! "expected a symbol for name" name))
    (hashtable-set! (%type-env-table env) name type))

  ;; ========== Lookup ==========

  ;; Look up the type of name by walking env's local table, then parents.
  ;; Returns the type descriptor if found, or #f if not bound.
  (define (type-env-lookup env name)
    (unless (type-env? env)
      (error 'type-env-lookup "expected a type-env" env))
    (unless (symbol? name)
      (error 'type-env-lookup "expected a symbol for name" name))
    (let loop ([e env])
      (if (not e)
        #f
        (let ([found (hashtable-ref (%type-env-table e) name #f)])
          (if found
            found
            (loop (%type-env-parent e)))))))

  ;; ========== Functional extension ==========

  ;; Return a new child environment of env pre-populated with bindings,
  ;; an alist of (name . type) pairs.  env is unmodified.
  (define (type-env-extend env bindings)
    (unless (type-env? env)
      (error 'type-env-extend "expected a type-env" env))
    (let ([child (make-type-env env)])
      (for-each
        (lambda (pair)
          (unless (and (pair? pair) (symbol? (car pair)))
            (error 'type-env-extend "binding must be (symbol . type)" pair))
          (type-env-bind! child (car pair) (cdr pair)))
        bindings)
      child))

  ;; ========== Introspection ==========

  ;; Return a flat list of (name . type) pairs visible in env.
  ;; Local bindings appear first; parent bindings follow (without duplicates).
  (define (type-env->list env)
    (unless (type-env? env)
      (error 'type-env->list "expected a type-env" env))
    (let loop ([e env] [seen (make-eq-hashtable)] [acc '()])
      (if (not e)
        (reverse acc)
        (let ([local (hashtable->list (%type-env-table e) seen)])
          (for-each (lambda (pair)
                      (hashtable-set! seen (car pair) #t))
                    local)
          (loop (%type-env-parent e) seen (append (reverse local) acc))))))

  ;; Collect entries from a hashtable that are not already in seen.
  ;; Returns list of (key . value) in unspecified order.
  (define (hashtable->list ht seen)
    (let-values ([(keys vals) (hashtable-entries ht)])
      (let loop ([i 0] [acc '()])
        (if (= i (vector-length keys))
          acc
          (let ([k (vector-ref keys i)]
                [v (vector-ref vals i)])
            (loop (+ i 1)
                  (if (hashtable-ref seen k #f)
                    acc
                    (cons (cons k v) acc))))))))

) ;; end library
