#!chezscheme
;;; :std/interface -- Simple interface protocol system
;;;
;;; Provides a minimal interface system compatible with Gerbil usage:
;;;   (definterface Name (method1 method2 ...))
;;;     → defines record type, constructor, accessor, and predicate
;;;
;;;   (interface-satisfies? iface type-name)
;;;     → #t if type-name has all methods of iface registered
;;;
;;; Methods are registered in a global hash table keyed by
;;; (type-name . method-name) symbols. Actual method registration
;;; is done by defmethod (provided by jerboa core), which should
;;; call (interface-register-method! type-name method-name) when
;;; defining a method.

(library (std interface)
  (export
    definterface
    make-interface
    interface-name
    interface-method-names
    interface-satisfies?
    interface-register-method!
    interface-has-method?)

  (import (chezscheme))

  ;; ========== Method registry ==========

  ;; Global registry: type-name → set of method-name symbols
  ;; Outer: eq-hashtable (type-name → inner hashtable)
  ;; Inner: eq-hashtable (method-name → #t)
  (define *method-registry* (make-eq-hashtable))

  (define (interface-register-method! type-name method-name)
    (let ([methods (hashtable-ref *method-registry* type-name #f)])
      (if methods
        (hashtable-set! methods method-name #t)
        (let ([ht (make-eq-hashtable)])
          (hashtable-set! ht method-name #t)
          (hashtable-set! *method-registry* type-name ht)))))

  (define (interface-has-method? type-name method-name)
    (let ([methods (hashtable-ref *method-registry* type-name #f)])
      (and methods (hashtable-ref methods method-name #f))))

  ;; ========== Interface record type ==========

  (define-record-type interface-type
    (fields
      (immutable name)
      (immutable method-names))
    (protocol
      (lambda (new)
        (lambda (name method-names)
          (new name method-names)))))

  (define (make-interface name method-names)
    (make-interface-type name method-names))
  (define (interface-name i) (interface-type-name i))
  (define (interface-method-names i) (interface-type-method-names i))

  ;; ========== Satisfaction check ==========

  (define (interface-satisfies? iface type-name)
    "Return #t if type-name has all methods required by iface registered."
    (let loop ((methods (interface-method-names iface)))
      (cond
        ((null? methods) #t)
        ((interface-has-method? type-name (car methods))
         (loop (cdr methods)))
        (else #f))))

  ;; ========== definterface macro ==========

  ;; (definterface Name (method1 method2 ...))
  ;;
  ;; Expands to:
  ;;   - a module-level variable Name holding the interface record
  ;;   - a predicate Name? that checks interface-satisfies? for a given type-name
  ;;
  ;; Usage:
  ;;   (definterface Printable (print to-string))
  ;;   (Printable? 'my-type)  => #t if my-type registered print and to-string

  (define-syntax definterface
    (lambda (stx)
      (syntax-case stx ()
        [(_ Name (method ...))
         (with-syntax ([Name? (datum->syntax #'Name
                        (string->symbol
                          (string-append (symbol->string (syntax->datum #'Name)) "?")))])
           #'(begin
               (define Name
                 (make-interface 'Name '(method ...)))
               (define (Name? type-name)
                 (interface-satisfies? Name type-name))))])))

  ) ;; end library
