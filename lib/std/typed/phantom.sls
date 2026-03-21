#!chezscheme
;;; (std typed phantom) — Phantom types for type-level state machines
;;;
;;; Encode protocol states in the type system so invalid transitions
;;; are caught at runtime (with clear error messages).
;;;
;;; API:
;;;   (define-phantom-type name states) — define phantom type with states
;;;   (make-phantom type state val)     — create phantom-typed value
;;;   (phantom-value pt)                — extract payload
;;;   (phantom-state pt)                — get current state
;;;   (phantom-transition pt new-state proc) — state transition with check
;;;   (phantom-check pt expected-state) — assert state
;;;   (define-phantom-protocol name transitions) — define allowed transitions

(library (std typed phantom)
  (export make-phantom phantom? phantom-value phantom-state
          phantom-transition phantom-check
          define-phantom-type define-phantom-protocol
          phantom-type-name)

  (import (chezscheme))

  ;; ========== Phantom value ==========

  (define-record-type phantom
    (fields
      (immutable type-name)
      (mutable state)
      (mutable value))
    (sealed #t))

  ;; ========== Protocol registry ==========
  ;; Maps type-name -> hashtable of (from-state -> list of to-states)

  (define *protocols* (make-eq-hashtable))

  (define (register-transitions! type-name transitions)
    (let ([ht (make-eq-hashtable)])
      (for-each
        (lambda (t)
          (let ([from (car t)]
                [to (cadr t)])
            (hashtable-update! ht from
              (lambda (existing) (cons to existing))
              '())))
        transitions)
      (hashtable-set! *protocols* type-name ht)))

  (define (valid-transition? type-name from to)
    (let ([ht (hashtable-ref *protocols* type-name #f)])
      (if (not ht)
        #t  ;; No protocol registered: allow all
        (let ([allowed (hashtable-ref ht from '())])
          (memq to allowed)))))

  ;; ========== Operations ==========

  (define (phantom-check pt expected)
    (unless (eq? (phantom-state pt) expected)
      (error 'phantom-check
        (format "expected state ~a but got ~a"
                expected (phantom-state pt)))))

  (define (phantom-transition pt new-state proc)
    (let ([from (phantom-state pt)]
          [type (phantom-type-name pt)])
      (unless (valid-transition? type from new-state)
        (error 'phantom-transition
          (format "invalid transition ~a -> ~a for type ~a"
                  from new-state type)))
      (let ([result (proc (phantom-value pt))])
        (phantom-state-set! pt new-state)
        (phantom-value-set! pt result)
        pt)))

  ;; ========== Macros ==========

  (define-syntax define-phantom-type
    (syntax-rules ()
      [(_ name (state ...))
       (begin
         ;; Just register the type name; states are symbols
         (void))]))

  (define-syntax define-phantom-protocol
    (syntax-rules (-> :)
      [(_ name (from -> to : op) ...)
       (register-transitions! 'name '((from to) ...))]
      [(_ name (from -> to) ...)
       (register-transitions! 'name '((from to) ...))]))

) ;; end library
