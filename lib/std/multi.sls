#!chezscheme
;;; (std multi) — Clojure-style value-dispatched multimethods.
;;;
;;; Jerboa's prelude already ships a `defmethod` that dispatches on
;;; struct type (`(defmethod (area (c circle)) ...)`). Clojure's
;;; `defmulti` / `defmethod` are orthogonal — the user supplies a
;;; dispatch function, and each method is registered against an
;;; arbitrary value returned by that function:
;;;
;;;   (defmulti area (lambda (shape) (car shape)))
;;;   (defmethod area 'circle (c) (* 3.14 (cadr c) (cadr c)))
;;;   (defmethod area 'square (s) (let ([side (cadr s)]) (* side side)))
;;;   (defmethod area 'default (x) (error 'area "unknown shape" x))
;;;   (area '(circle 3))  ;; => 28.26
;;;
;;; This module is NOT in the prelude to avoid shadowing the
;;; struct-typed `defmethod`. Users who want Clojure-style dispatch
;;; import `(std multi)` explicitly and (typically) shadow the
;;; prelude's `defmethod`:
;;;
;;;   (import (except (jerboa prelude) defmethod)
;;;           (std multi))
;;;
;;; Dispatch values
;;; ---------------
;;; Keys are compared with `equal?`, so any value is usable: symbols,
;;; numbers, strings, vectors, lists, persistent maps, etc.
;;;
;;; The symbol `'default` is reserved: registering a method with key
;;; `'default` sets the fallback method that fires when no explicit
;;; dispatch value matches (mirrors Clojure's `:default`). Without a
;;; default, a dispatch miss raises.

(library (std multi)
  (export
    ;; Core
    defmulti defmethod
    ;; Introspection / mutation
    multimethod? multimethod-name
    get-method remove-method methods
    ;; Hierarchy (Round 5 §35)
    make-hierarchy
    derive underive
    parents ancestors descendants
    isa?
    prefer-method preferred-methods
    global-hierarchy
    ;; Auxiliary keyword for (defmulti name dispatch :hierarchy h)
    :hierarchy)

  (import (chezscheme))

  ;; --- Hierarchy (Round 5 §35) --------------------------------
  ;;
  ;; A hierarchy records user-defined `isa?` relations over arbitrary
  ;; dispatch values. Clojure's default hierarchy is a shared mutable
  ;; structure seeded empty and populated by `derive`. We expose both
  ;; `global-hierarchy` (the default) and `make-hierarchy` for isolated
  ;; hierarchies used by tests or libraries that want to avoid leaking
  ;; `derive` calls into a shared table.

  (define-record-type %hierarchy
    (fields (immutable parents-ht)      ;; eqv? hashtable: tag -> list of direct parents
            (immutable descendants-ht)  ;; eqv? hashtable: tag -> list of direct children
            (immutable lock))
    (sealed #t))

  (define (make-hierarchy)
    (make-%hierarchy
      (make-hashtable equal-hash equal?)
      (make-hashtable equal-hash equal?)
      (make-mutex)))

  (define global-hierarchy (make-hierarchy))

  (define (%parents-of h tag)
    (hashtable-ref (%hierarchy-parents-ht h) tag '()))

  (define (%children-of h tag)
    (hashtable-ref (%hierarchy-descendants-ht h) tag '()))

  (define (%add-once! ht k v)
    (let ([cur (hashtable-ref ht k '())])
      (unless (member v cur)
        (hashtable-set! ht k (cons v cur)))))

  (define (%remove-once! ht k v)
    (let ([cur (hashtable-ref ht k '())])
      (hashtable-set! ht k
        (filter (lambda (x) (not (equal? x v))) cur))))

  ;; derive: register child -> parent. Accepts 2 or 3 args:
  ;;   (derive child parent)      ;; mutates global-hierarchy
  ;;   (derive h child parent)    ;; mutates given hierarchy
  ;; Rejects cycles.
  (define derive
    (case-lambda
      [(child parent) (derive global-hierarchy child parent)]
      [(h child parent)
       (unless (%hierarchy? h)
         (error 'derive "not a hierarchy" h))
       (when (equal? child parent)
         (error 'derive "cannot derive tag from itself" child))
       (with-mutex (%hierarchy-lock h)
         (when (%isa?/locked h parent child)
           (error 'derive "cycle: parent already derives from child"
                  (list child '-> parent)))
         (%add-once! (%hierarchy-parents-ht h) child parent)
         (%add-once! (%hierarchy-descendants-ht h) parent child))
       h]))

  (define underive
    (case-lambda
      [(child parent) (underive global-hierarchy child parent)]
      [(h child parent)
       (unless (%hierarchy? h)
         (error 'underive "not a hierarchy" h))
       (with-mutex (%hierarchy-lock h)
         (%remove-once! (%hierarchy-parents-ht h) child parent)
         (%remove-once! (%hierarchy-descendants-ht h) parent child))
       h]))

  (define parents
    (case-lambda
      [(tag) (parents global-hierarchy tag)]
      [(h tag)
       (unless (%hierarchy? h)
         (error 'parents "not a hierarchy" h))
       (with-mutex (%hierarchy-lock h) (%parents-of h tag))]))

  ;; Breadth-first reachable from `tag` via parents (ancestors)
  ;; or descendants (children). Unique, self-excluded.
  (define (%bfs step h tag)
    (let loop ([frontier (step h tag)] [seen '()] [acc '()])
      (cond
        [(null? frontier) (reverse acc)]
        [else
         (let ([t (car frontier)])
           (cond
             [(member t seen) (loop (cdr frontier) seen acc)]
             [else
              (loop (append (cdr frontier) (step h t))
                    (cons t seen)
                    (cons t acc))]))])))

  (define ancestors
    (case-lambda
      [(tag) (ancestors global-hierarchy tag)]
      [(h tag)
       (unless (%hierarchy? h)
         (error 'ancestors "not a hierarchy" h))
       (with-mutex (%hierarchy-lock h)
         (%bfs %parents-of h tag))]))

  (define descendants
    (case-lambda
      [(tag) (descendants global-hierarchy tag)]
      [(h tag)
       (unless (%hierarchy? h)
         (error 'descendants "not a hierarchy" h))
       (with-mutex (%hierarchy-lock h)
         (%bfs %children-of h tag))]))

  ;; isa? — Clojure returns #t when:
  ;;   - x equal? y, or
  ;;   - y appears in the ancestor closure of x
  ;; We do not model class inheritance here; for records, callers should
  ;; pass the rtd as the tag if they want record-type derivation.
  (define (%isa?/locked h x y)
    (cond
      [(equal? x y) #t]
      [else
       (let loop ([frontier (%parents-of h x)] [seen '()])
         (cond
           [(null? frontier) #f]
           [(equal? (car frontier) y) #t]
           [(member (car frontier) seen) (loop (cdr frontier) seen)]
           [else
            (loop (append (cdr frontier)
                          (%parents-of h (car frontier)))
                  (cons (car frontier) seen))]))]))

  (define isa?
    (case-lambda
      [(x y) (isa? global-hierarchy x y)]
      [(h x y)
       (unless (%hierarchy? h)
         (error 'isa? "not a hierarchy" h))
       (with-mutex (%hierarchy-lock h) (%isa?/locked h x y))]))

  ;; --- Record -----------------------------------------------
  ;;
  ;; The record is internal: user-facing `multimethod?` and
  ;; `multimethod-name` operate on the dispatching *procedure*
  ;; returned by `defmulti`, not on the record directly. We prefix
  ;; the record name to keep the auto-generated accessors out of
  ;; the export namespace.

  (define-record-type %mm
    (fields (immutable name)
            (immutable dispatch-fn)
            (immutable methods)        ;; hashtable, equal? keys
            (mutable   default-method)
            (immutable hierarchy)      ;; %hierarchy used for isa? walks
            (mutable   preferences)    ;; alist of (a . b) meaning prefer a over b
            (immutable lock))          ;; guards methods + default + prefs
    (sealed #t))

  (define (%new-multimethod name dispatch-fn hierarchy)
    (unless (%hierarchy? hierarchy)
      (error 'defmulti "not a hierarchy" hierarchy))
    (make-%mm name dispatch-fn
              (make-hashtable equal-hash equal?)
              #f
              hierarchy
              '()
              (make-mutex)))

  ;; --- Registry linking procedure -> multimethod ------------
  ;;
  ;; `defmulti` installs the dispatching procedure and registers it
  ;; in a module-level eq?-hashtable so `defmethod` can look up the
  ;; underlying record from the procedure identity. Procedures are
  ;; cheaper to compare by eq? than by name, and this sidesteps a
  ;; macro-hygiene dance to thread a second identifier around.

  (define %registry (make-eq-hashtable))
  (define %registry-lock (make-mutex))

  (define (%register! proc mm)
    (with-mutex %registry-lock
      (eq-hashtable-set! %registry proc mm)))

  (define (%lookup proc)
    (with-mutex %registry-lock
      (eq-hashtable-ref %registry proc #f)))

  ;; --- Dispatch ---------------------------------------------

  ;; Dispatch:
  ;;   1. Try exact match on dispatch value.
  ;;   2. Fall back to any registered method whose key is an ancestor
  ;;      of the dispatch value (via the multimethod's hierarchy).
  ;;      Multiple matches are disambiguated by `prefer-method`;
  ;;      remaining ambiguity raises.
  ;;   3. Fall back to the default method.
  (define (%invoke mm args)
    (let* ([k  (apply (%mm-dispatch-fn mm) args)]
           [mn (with-mutex (%mm-lock mm)
                 (or (hashtable-ref (%mm-methods mm) k #f)
                     (%hierarchy-dispatch mm k)
                     (%mm-default-method mm)))])
      (cond
        [mn (apply mn args)]
        [else
         (error (%mm-name mm)
                "no method for dispatch value" k)])))

  ;; Inner-lock helper — assumes caller already holds (%mm-lock mm).
  (define (%hierarchy-dispatch mm k)
    (let ([h (%mm-hierarchy mm)])
      (let-values ([(keys _) (hashtable-entries (%mm-methods mm))])
        (with-mutex (%hierarchy-lock h)
          (let ([applicable
                 (let loop ([i 0] [acc '()])
                   (cond
                     [(= i (vector-length keys)) acc]
                     [(%isa?/locked h k (vector-ref keys i))
                      (loop (+ i 1) (cons (vector-ref keys i) acc))]
                     [else (loop (+ i 1) acc)]))])
            (cond
              [(null? applicable) #f]
              [(null? (cdr applicable))
               (hashtable-ref (%mm-methods mm) (car applicable) #f)]
              [else
               (let ([winner (%resolve-preferences mm applicable)])
                 (hashtable-ref (%mm-methods mm) winner #f))]))))))

  ;; Given ≥2 applicable dispatch keys, pick the one preferred by
  ;; `prefer-method`. If no preference resolves the conflict, raise.
  (define (%resolve-preferences mm applicable)
    (let ([prefs (%mm-preferences mm)])
      (let loop ([cands applicable])
        (cond
          [(null? (cdr cands)) (car cands)]
          [(%preferred? prefs (car cands) (cadr cands))
           (loop (cons (car cands) (cddr cands)))]
          [(%preferred? prefs (cadr cands) (car cands))
           (loop (cdr cands))]
          [else
           (error (%mm-name mm)
                  "multiple methods match and none is preferred"
                  applicable)]))))

  (define (%preferred? prefs a b)
    ;; a is preferred over b iff (a . b) is reachable via prefs
    ;; walked transitively.
    (let loop ([frontier (list a)] [seen '()])
      (cond
        [(null? frontier) #f]
        [else
         (let ([x (car frontier)])
           (cond
             [(member x seen) (loop (cdr frontier) seen)]
             [else
              (let ([next (filter-map
                            (lambda (p)
                              (and (equal? (car p) x) (cdr p)))
                            prefs)])
                (cond
                  [(member b next) #t]
                  [else (loop (append (cdr frontier) next)
                              (cons x seen))]))]))])))

  (define (filter-map f lst)
    (let loop ([xs lst] [acc '()])
      (cond
        [(null? xs) (reverse acc)]
        [else
         (let ([v (f (car xs))])
           (loop (cdr xs) (if v (cons v acc) acc)))])))

  (define (%install name dispatch-fn hierarchy)
    (let* ([mm   (%new-multimethod name dispatch-fn hierarchy)]
           [proc (lambda args (%invoke mm args))])
      (%register! proc mm)
      proc))

  ;; --- Public API -------------------------------------------

  ;; Auxiliary keyword used by defmulti. Exported so that a literal
  ;; `:hierarchy` at a use site refers to the same binding as the
  ;; literal in this library (R6RS `syntax-rules` literal matching
  ;; requires matching bindings across library boundaries).
  (define-syntax :hierarchy
    (lambda (x)
      (syntax-violation ':hierarchy
        "misplaced auxiliary keyword" x)))

  ;; (defmulti NAME DISPATCH-FN)
  ;; (defmulti NAME DISPATCH-FN :hierarchy HIERARCHY-EXPR)
  ;;
  ;; Binds NAME to a procedure that, when called, applies DISPATCH-FN
  ;; to its arguments, looks up the resulting key in the multimethod's
  ;; methods table, and invokes the registered method.
  ;;
  ;; When the optional `:hierarchy` form is supplied, HIERARCHY-EXPR
  ;; must evaluate to a hierarchy (from `make-hierarchy`) and is used
  ;; for ancestor-walk dispatch. Otherwise the multimethod uses
  ;; `global-hierarchy`. This is the moral equivalent of Clojure's
  ;; `(defmulti name dispatch-fn :hierarchy #'my-h)`.
  (define-syntax defmulti
    (syntax-rules (:hierarchy)
      [(_ name dispatch-fn)
       (define name (%install 'name dispatch-fn global-hierarchy))]
      [(_ name dispatch-fn :hierarchy h-expr)
       (define name (%install 'name dispatch-fn h-expr))]))

  ;; (defmethod NAME DISPATCH-VAL (arg ...) body ...)
  ;;
  ;; Adds a method to the multimethod NAME for the dispatch value
  ;; DISPATCH-VAL. If DISPATCH-VAL is the symbol `'default`, sets the
  ;; fallback method instead. DISPATCH-VAL is an arbitrary expression
  ;; evaluated at definition time — use your own quoting for
  ;; symbolic keys (`'circle`, `'square`, etc.).
  (define-syntax defmethod
    (syntax-rules ()
      [(_ name dispatch-val (arg ...) body ...)
       (%add-method! name dispatch-val (lambda (arg ...) body ...))]))

  (define (%add-method! proc k method)
    (let ([mm (%lookup proc)])
      (unless mm
        (error 'defmethod "not a multimethod" proc))
      (with-mutex (%mm-lock mm)
        (cond
          [(eq? k 'default)
           (%mm-default-method-set! mm method)]
          [else
           (hashtable-set! (%mm-methods mm) k method)]))
      proc))

  ;; (multimethod? PROC) — true if PROC was created by `defmulti`.
  (define (multimethod? proc)
    (and (procedure? proc) (and (%lookup proc) #t)))

  ;; (multimethod-name PROC) — returns the symbol used in defmulti.
  (define (multimethod-name proc)
    (let ([mm (%lookup proc)])
      (unless mm
        (error 'multimethod-name "not a multimethod" proc))
      (%mm-name mm)))

  ;; (get-method NAME DISPATCH-VAL)
  ;;
  ;; Returns the registered method for DISPATCH-VAL, or #f if none.
  ;; The sentinel `'default` returns the default method.
  (define (get-method proc k)
    (let ([mm (%lookup proc)])
      (unless mm
        (error 'get-method "not a multimethod" proc))
      (with-mutex (%mm-lock mm)
        (cond
          [(eq? k 'default) (%mm-default-method mm)]
          [else (hashtable-ref (%mm-methods mm) k #f)]))))

  ;; (remove-method NAME DISPATCH-VAL)
  ;;
  ;; Removes the method registered for DISPATCH-VAL. Idempotent:
  ;; removing a key that isn't present is a no-op. Returns NAME.
  (define (remove-method proc k)
    (let ([mm (%lookup proc)])
      (unless mm
        (error 'remove-method "not a multimethod" proc))
      (with-mutex (%mm-lock mm)
        (cond
          [(eq? k 'default)
           (%mm-default-method-set! mm #f)]
          [else
           (hashtable-delete! (%mm-methods mm) k)]))
      proc))

  ;; (methods NAME) => alist of (dispatch-value . method-procedure).
  ;; Does not include the default method. Use `(get-method name 'default)`
  ;; for that.
  (define (methods proc)
    (let ([mm (%lookup proc)])
      (unless mm
        (error 'methods "not a multimethod" proc))
      (with-mutex (%mm-lock mm)
        (let-values ([(keys vals)
                      (hashtable-entries (%mm-methods mm))])
          (let loop ([i 0] [acc '()])
            (cond
              [(= i (vector-length keys)) acc]
              [else
               (loop (+ i 1)
                     (cons (cons (vector-ref keys i)
                                 (vector-ref vals i))
                           acc))]))))))

  ;; (prefer-method mm a b) — when both a and b apply via the
  ;; hierarchy, pick the method registered for `a`. Idempotent;
  ;; refuses to install cycles.
  (define (prefer-method proc a b)
    (let ([mm (%lookup proc)])
      (unless mm
        (error 'prefer-method "not a multimethod" proc))
      (when (equal? a b)
        (error 'prefer-method "cannot prefer a tag over itself" a))
      (with-mutex (%mm-lock mm)
        (when (%preferred? (%mm-preferences mm) b a)
          (error 'prefer-method
                 "cycle: b is already preferred over a"
                 (list a '-> b)))
        (let ([prefs (%mm-preferences mm)])
          (unless (member (cons a b) prefs)
            (%mm-preferences-set! mm (cons (cons a b) prefs)))))
      proc))

  ;; (preferred-methods mm) => alist of preferred (a . b) pairs.
  (define (preferred-methods proc)
    (let ([mm (%lookup proc)])
      (unless mm
        (error 'preferred-methods "not a multimethod" proc))
      (with-mutex (%mm-lock mm) (%mm-preferences mm))))

) ;; end library
