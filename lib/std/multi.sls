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
    get-method remove-method methods)

  (import (chezscheme))

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
            (immutable lock))          ;; guards methods + default
    (sealed #t))

  (define (%new-multimethod name dispatch-fn)
    (make-%mm name dispatch-fn
              (make-hashtable equal-hash equal?)
              #f
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

  (define (%invoke mm args)
    (let* ([k  (apply (%mm-dispatch-fn mm) args)]
           [mn (with-mutex (%mm-lock mm)
                 (or (hashtable-ref (%mm-methods mm) k #f)
                     (%mm-default-method mm)))])
      (cond
        [mn (apply mn args)]
        [else
         (error (%mm-name mm)
                "no method for dispatch value" k)])))

  (define (%install name dispatch-fn)
    (let* ([mm   (%new-multimethod name dispatch-fn)]
           [proc (lambda args (%invoke mm args))])
      (%register! proc mm)
      proc))

  ;; --- Public API -------------------------------------------

  ;; (defmulti NAME DISPATCH-FN)
  ;;
  ;; Binds NAME to a procedure that, when called, applies DISPATCH-FN
  ;; to its arguments, looks up the resulting key in the multimethod's
  ;; methods table, and invokes the registered method.
  (define-syntax defmulti
    (syntax-rules ()
      [(_ name dispatch-fn)
       (define name (%install 'name dispatch-fn))]))

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

) ;; end library
