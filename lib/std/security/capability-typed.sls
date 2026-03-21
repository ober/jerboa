#!chezscheme
;;; (std security capability-typed) — Capability-typed function definitions
;;;
;;; Combines the capability system with function signatures so
;;; functions declare their required capabilities in their type.
;;;
;;; (define/cap (read-config path)
;;;   (requires: fs-read)
;;;   body ...)
;;;
;;; Calling read-config outside a capability context raises &capability-violation.

(library (std security capability-typed)
  (export
    define/cap
    lambda/cap
    requires:
    capability-requirements)

  (import (chezscheme)
          (std security capability))

  ;; ========== Capability Requirements Registry ==========

  ;; Maps procedure names to their required capability types
  (define *cap-registry* (make-eq-hashtable))
  (define *cap-registry-mutex* (make-mutex))

  (define (register-cap-requirements! name reqs)
    (with-mutex *cap-registry-mutex*
      (hashtable-set! *cap-registry* name reqs)))

  (define (capability-requirements proc-name)
    ;; Look up the capability requirements for a named procedure.
    ;; Returns a list of capability type symbols, or '() if none registered.
    (with-mutex *cap-registry-mutex*
      (hashtable-ref *cap-registry* proc-name '())))

  (define (check-has-capability-type! type who)
    ;; Check that current context has ANY capability of the given type.
    ;; Unlike check-capability!, doesn't require a specific permission.
    (let ([caps (current-capabilities)])
      (unless (exists
                (lambda (cap) (eq? (capability-type cap) type))
                caps)
        (raise (condition
                 (make-capability-violation type
                   (format #f "required by ~a" who))
                 (make-message-condition
                   (format #f "capability denied: ~a ~a" type who)))))))

  ;; ========== Keyword ==========

  (define-syntax requires:
    (lambda (stx)
      (syntax-violation 'requires: "misuse of requires: keyword" stx)))

  ;; ========== Macros ==========

  (define-syntax define/cap
    (syntax-rules (requires:)
      ;; (define/cap (name args ...) (requires: cap-type ...) body ...)
      [(_ (name args ...) (requires: cap-type ...) body ...)
       (begin
         (define (name args ...)
           (for-each
             (lambda (ct)
               (check-has-capability-type! ct 'name))
             '(cap-type ...))
           body ...)
         (register-cap-requirements! 'name '(cap-type ...)))]))

  (define-syntax lambda/cap
    (syntax-rules (requires:)
      ;; (lambda/cap (args ...) (requires: cap-type ...) body ...)
      [(_ (args ...) (requires: cap-type ...) body ...)
       (lambda (args ...)
         (for-each
           (lambda (ct)
             (check-has-capability-type! ct 'lambda/cap))
           '(cap-type ...))
         body ...)]))

  ) ;; end library
