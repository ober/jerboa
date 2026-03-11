#!chezscheme
;;; (std dev devirt) -- Whole-Program Devirtualization
;;;
;;; When the compiler can see all implementations of a method, replace
;;; dynamic dispatch (hashtable lookup) with a static cond on type.
;;;
;;; Before devirtualization:
;;;   ({area} shape)  ;; → find-method → eq-hashtable-ref → call
;;;
;;; After devirtualization (when only circle, rect, triangle implement area):
;;;   (cond
;;;     [(circle?   shape) (circle-area   shape)]
;;;     [(rect?     shape) (rect-area     shape)]
;;;     [(triangle? shape) (triangle-area shape)]
;;;     [else (call-method shape 'area)])
;;;
;;; Chez's cp0 can then inline the accessor bodies if they're small.
;;;
;;; Usage:
;;;   (import (std dev devirt))
;;;
;;;   ;; Track method registrations
;;;   (defmethod/tracked area circle circle-area)
;;;   (defmethod/tracked area rect   rect-area)
;;;
;;;   ;; Generate optimized dispatch
;;;   (define-devirt-dispatch area-dispatch 'area)
;;;   ;; Now area-dispatch is a procedure: (area-dispatch shape) → dispatches statically

(library (std dev devirt)
  (export
    ;; Method registration with tracking
    defmethod/tracked
    register-method-impl!

    ;; Registry queries
    method-implementations
    method-closed?
    seal-method!
    all-sealed-methods

    ;; Code generation
    define-devirt-dispatch
    devirt-call

    ;; Method registry
    *method-registry*)

  (import (except (chezscheme) 1+ 1- iota make-hash-table hash-table?)
          (jerboa runtime))

  ;;; ========== Method implementation registry ==========
  ;; Maps method-name (symbol) → list of (rtd pred proc) triples.
  ;;
  ;; This tracks which types implement each method, enabling devirtualization
  ;; when the method implementation set is known to be closed.

  (define *method-registry* (make-eq-hashtable))
  (define *sealed-methods*  (make-eq-hashtable))  ; method-name → #t when sealed

  ;; Register a method implementation for tracking.
  ;; rtd: record-type-descriptor
  ;; pred: predicate procedure (e.g., circle?)
  ;; proc: method procedure
  (define (register-method-impl! method-name rtd pred proc)
    ;; Register in the dispatch tracking table
    (let ([impls (or (hashtable-ref *method-registry* method-name #f) '())])
      (hashtable-set! *method-registry* method-name
        (cons (list rtd pred proc) impls)))
    ;; Also register in jerboa's runtime method table for dynamic dispatch
    (bind-method! rtd method-name proc))

  ;; Query: get all (rtd pred proc) triples for a method.
  (define (method-implementations method-name)
    (reverse (or (hashtable-ref *method-registry* method-name #f) '())))

  ;; Seal a method: declare that no more implementations will be added.
  ;; After sealing, devirt-call can safely emit static dispatch.
  (define (seal-method! method-name)
    (hashtable-set! *sealed-methods* method-name #t))

  ;; Check if a method is sealed (closed implementation set).
  (define (method-closed? method-name)
    (hashtable-ref *sealed-methods* method-name #f))

  ;; List all sealed method names.
  (define (all-sealed-methods)
    (let-values ([(keys _) (hashtable-entries *sealed-methods*)])
      (vector->list keys)))

  ;;; ========== defmethod/tracked macro ==========
  ;; Like jerboa's defmethod but also records the implementation
  ;; in the devirt registry.
  ;;
  ;; (defmethod/tracked method-name type-name proc)
  ;; (defmethod/tracked method-name type-name (lambda (self ...) body))
  (define-syntax defmethod/tracked
    (lambda (stx)
      (syntax-case stx ()
        ;; (defmethod/tracked method-name type-name proc-expr)
        [(_ method-name type-name proc-expr)
         (with-syntax
           ([rtd-expr   (datum->syntax #'type-name
                          (let ([tn (syntax->datum #'type-name)])
                            (string->symbol (string-append (symbol->string tn) "::t"))))]
            [pred-expr  (datum->syntax #'type-name
                          (let ([tn (syntax->datum #'type-name)])
                            (string->symbol (string-append (symbol->string tn) "?"))))]
            [method-sym (datum->syntax #'method-name
                          (list 'quote (syntax->datum #'method-name)))])
           #'(register-method-impl! method-sym rtd-expr pred-expr proc-expr))])))

  ;;; ========== Static dispatch code generation ==========

  ;; Generate a cond-based dispatch procedure from the tracked implementations.
  ;; When the method is sealed, this is a complete closed-world dispatch.
  ;; When not sealed, adds an else clause that calls the dynamic dispatcher.
  (define (make-devirt-dispatcher method-name)
    (let ([impls (method-implementations method-name)]
          [closed? (method-closed? method-name)])
      (if (null? impls)
        ;; No implementations: fall through to dynamic dispatch
        (lambda (obj . args) (apply ~ obj method-name args))
        ;; Build static dispatch procedure
        (let ([checks (map (lambda (impl)
                             (let ([pred (cadr impl)]
                                   [proc (caddr impl)])
                               (cons pred proc)))
                           impls)])
          (lambda (obj . args)
            (let loop ([cs checks])
              (cond
                [(null? cs)
                 (if closed?
                   (error 'devirt-dispatch "no method implementation" method-name obj)
                   (apply ~ obj method-name args))]
                [((caar cs) obj)
                 (apply (cdar cs) obj args)]
                [else (loop (cdr cs))])))))))

  ;; (define-devirt-dispatch dispatch-name 'method-name)
  ;; Creates a dispatching procedure that uses static type checks
  ;; instead of hashtable lookup.
  ;;
  ;; Must be called AFTER all defmethod/tracked registrations,
  ;; and AFTER seal-method! if the method is to be considered closed.
  (define-syntax define-devirt-dispatch
    (lambda (stx)
      (syntax-case stx ()
        [(_ dispatch-name method-name-expr)
         #'(define dispatch-name
             (make-devirt-dispatcher method-name-expr))])))

  ;;; ========== devirt-call macro ==========
  ;; (devirt-call 'method-name obj arg ...)
  ;; At COMPILE TIME: if 'method-name is sealed and tracked implementations
  ;; are known, emits a cond based on the predicates we know about.
  ;; At RUNTIME: falls back to ~ dispatch if needed.
  ;;
  ;; Note: compile-time devirtualization requires method registration
  ;; to happen BEFORE this macro is expanded (i.e., at import time or
  ;; in earlier top-level forms). This works naturally for sealed methods.
  ;; devirt-call: runtime dispatch through the optimized dispatcher table.
  ;; Dispatchers are built via make-devirt-dispatcher / define-devirt-dispatch.
  ;; Falls back to ~ (dynamic dispatch) when no pre-built dispatcher exists.
  ;;
  ;; For compile-time devirtualization: use define-devirt-dispatch before calling
  ;; devirt-call to pre-build and cache the dispatcher.
  (define *dispatch-cache* (make-eq-hashtable))

  (define (get-or-build-dispatcher method-name)
    (or (hashtable-ref *dispatch-cache* method-name #f)
        (let ([d (make-devirt-dispatcher method-name)])
          (hashtable-set! *dispatch-cache* method-name d)
          d)))

  (define-syntax devirt-call
    (syntax-rules ()
      [(_ method-name-expr obj-expr arg ...)
       ((get-or-build-dispatcher method-name-expr) obj-expr arg ...)]))

) ;; end library
