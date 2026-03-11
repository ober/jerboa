#!chezscheme
;;; (std typed effect-typing) — Effect type signatures for handlers
;;;
;;; Annotate effect handlers with their effect signatures.
;;; Check at runtime that handlers handle the declared effects.
;;; Integrates with (std effect) by inspecting handler dispatch tables.
;;;
;;; API:
;;;   (define-effect-signature Name
;;;     handles: (Effect1 Effect2 ...)
;;;     returns: type-spec)
;;;     — define a named effect signature descriptor
;;;
;;;   (check-effect-signature sig-name handler-form)
;;;     — verify at runtime that handler-form handles all declared effects
;;;
;;;   (effect-sig? v)            — #t iff v is an effect signature descriptor
;;;   (effect-sig-handles v)     — list of effect names the sig handles
;;;   (effect-sig-returns v)     — the declared return type spec
;;;
;;;   (typed-with-handler sig-name handler-clauses body ...)
;;;     — like with-handler but checks the signature first
;;;
;;;   (infer-handler-effects handler-table)
;;;     — inspect a handler dispatch table and return the list of effect names

(library (std typed effect-typing)
  (export
    define-effect-signature
    check-effect-signature
    effect-sig?
    effect-sig-handles
    effect-sig-returns
    typed-with-handler
    infer-handler-effects)
  (import (chezscheme))

  ;; ========== Effect signature descriptor ==========
  ;;
  ;; A signature is a record: (name handles returns)
  ;;   name:    symbol — identifier for this signature
  ;;   handles: list of symbols — effect names this handler should cover
  ;;   returns: any   — type specifier for the return value (informational)

  (define-record-type effect-sig
    (fields
      (immutable name    effect-sig-name)
      (immutable handles effect-sig-handles)
      (immutable returns effect-sig-returns))
    (sealed #t))

  ;; ========== Signature registry ==========

  (define *effect-sig-registry* (make-eq-hashtable))

  (define (register-effect-sig! name sig)
    (hashtable-set! *effect-sig-registry* name sig))

  (define (lookup-effect-sig name)
    (hashtable-ref *effect-sig-registry* name #f))

  ;; ========== define-effect-signature ==========
  ;;
  ;; (define-effect-signature SigName
  ;;   handles: (Effect ...)
  ;;   returns: type-spec)
  ;;
  ;; Note: handles: and returns: are matched by datum value (not free-identifier
  ;; equality) to avoid export issues in R6RS library context.

  (define-syntax define-effect-signature
    (lambda (stx)
      (syntax-case stx ()
        [(_ SigName kw1 (effect ...) kw2 ret)
         (and (eq? (syntax->datum #'kw1) 'handles:)
              (eq? (syntax->datum #'kw2) 'returns:))
         #'(define SigName
             (let ([sig (make-effect-sig 'SigName '(effect ...) 'ret)])
               (register-effect-sig! 'SigName sig)
               sig))]
        [(_ SigName . rest)
         (syntax-violation 'define-effect-signature
           "expected: (define-effect-signature Name handles: (Effects ...) returns: type)"
           stx)])))

  ;; ========== infer-handler-effects ==========
  ;;
  ;; Given a handler dispatch table (an eq-hashtable mapping effect-descriptor
  ;; to alist-of-handlers, as used by (std effect)), extract the effect names.
  ;;
  ;; The (std effect) effect-descriptor is a record with a 'name' field.
  ;; We use inspect/object or direct record access if effect is loaded, but
  ;; to avoid a hard dependency on (std effect), we accept either:
  ;;   - a list of effect name symbols (for direct use)
  ;;   - an eq-hashtable where each key has a 'name' field (from (std effect))
  ;; The function returns a list of symbols.

  (define (infer-handler-effects handler-table)
    (cond
      ;; List of effect name symbols — already inferred
      [(list? handler-table)
       handler-table]
      ;; eq-hashtable — try to extract effect names from keys
      [(hashtable? handler-table)
       (let-values ([(keys _) (hashtable-entries handler-table)])
         (vector->list
           (vector-map
             (lambda (k)
               ;; Try to get the name field from an effect descriptor record
               (guard (exn [#t k])  ; fallback: use the key itself as name
                 ;; effect-descriptor from (std effect) has a 'name' accessor
                 ;; We can use the record inspection API
                 (if (record? k)
                   (let* ([rtd (record-rtd k)]
                          [fields (record-type-field-names rtd)]
                          [name-idx
                           (let loop ([i 0] [flds (vector->list fields)])
                             (cond
                               [(null? flds) #f]
                               [(eq? (car flds) 'name) i]
                               [else (loop (+ i 1) (cdr flds))]))])
                     (if name-idx
                       ((record-accessor rtd name-idx) k)
                       k))
                   k)))
             keys)))]
      [else
       (error 'infer-handler-effects
              "expected list or hashtable" handler-table)]))

  ;; ========== check-effect-signature ==========
  ;;
  ;; Check that a handler covers all effects declared in a signature.
  ;; handler-effects: either a list of effect name symbols, or an
  ;; eq-hashtable (as returned by (std effect) handler setup).
  ;;
  ;; Returns #t on success, raises an error if any declared effect is missing.

  (define (check-effect-signature sig handler-or-effects)
    (unless (effect-sig? sig)
      (error 'check-effect-signature "not an effect signature" sig))
    (let* ([declared  (effect-sig-handles sig)]
           [actual    (infer-handler-effects handler-or-effects)]
           [missing   (filter (lambda (e) (not (memq e actual))) declared)])
      (when (pair? missing)
        (error 'check-effect-signature
               "handler does not handle declared effects"
               (effect-sig-name sig)
               missing))
      #t))

  ;; ========== typed-with-handler ==========
  ;;
  ;; (typed-with-handler sig-name ([EffectName (op-name (k arg ...) body ...) ...] ...) body ...)
  ;;
  ;; Wraps a with-handler call (from (std effect)) with a signature check.
  ;; The check verifies the declared effects are present in the handler clauses.
  ;;
  ;; Since we can't import (std effect) without risking circular deps, we
  ;; implement typed-with-handler as a macro that:
  ;;   1. Extracts the effect names from the handler clauses at expand time
  ;;   2. Checks them against the runtime signature
  ;;   3. Delegates to with-handler (which must be in scope from (std effect))

  (define-syntax typed-with-handler
    (lambda (stx)
      (syntax-case stx ()
        [(_ sig-name ([EffectName handler-clause ...] ...) body ...)
         ;; with-handler must be imported from (std effect) at the call site.
         ;; We reference it via datum->syntax anchored to the macro keyword.
         (with-syntax ([(esym ...) #'(EffectName ...)]
                       [with-handler-ref
                        (datum->syntax (car (syntax->list stx)) 'with-handler)])
           #'(begin
               ;; Runtime signature check against the handler clause effect names
               (let ([sig sig-name])
                 (unless (effect-sig? sig)
                   (error 'typed-with-handler "not an effect signature" sig))
                 (let* ([actual-effects '(esym ...)]
                        [declared       (effect-sig-handles sig)]
                        [missing (filter (lambda (e) (not (memq e actual-effects)))
                                         declared)])
                   (when (pair? missing)
                     (error 'typed-with-handler
                            "handler missing declared effects"
                            (effect-sig-name sig) missing))))
               ;; Delegate to with-handler (must be in scope from (std effect))
               (with-handler-ref ([EffectName handler-clause ...] ...) body ...)))])))

  ) ; end library
