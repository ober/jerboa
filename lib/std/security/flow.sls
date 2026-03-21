#!chezscheme
;;; (std security flow) — Information flow control
;;;
;;; Security labels form a lattice: public < internal < secret < top-secret
;;; Data can flow up (public → secret) but not down (secret → public)
;;; without explicit declassification which creates an audit entry.

(library (std security flow)
  (export
    ;; Security levels
    make-security-level
    security-level?
    security-level-name
    security-level<=?

    ;; Default levels
    level-public
    level-internal
    level-secret
    level-top-secret

    ;; Classified values
    classify
    classified?
    classified-level
    classified-value
    declassify

    ;; Checking
    check-flow!
    assert-flow

    ;; Condition type
    &flow-violation
    make-flow-violation
    flow-violation?
    flow-violation-from
    flow-violation-to

    ;; Declassification log
    current-declassify-handler)

  (import (chezscheme))

  ;; ========== Security Levels ==========

  (define-record-type (security-level %make-security-level security-level?)
    (sealed #t)
    (opaque #t)
    (fields
      (immutable name security-level-name)       ;; symbol
      (immutable rank %security-level-rank)))     ;; integer (higher = more secret)

  (define (make-security-level name rank)
    (%make-security-level name rank))

  (define (security-level<=? a b)
    ;; Can data flow from level a to level b?
    ;; Data flows upward: lower rank can flow to higher or equal rank.
    (<= (%security-level-rank a) (%security-level-rank b)))

  ;; Default levels
  (define level-public      (make-security-level 'public 0))
  (define level-internal    (make-security-level 'internal 1))
  (define level-secret      (make-security-level 'secret 2))
  (define level-top-secret  (make-security-level 'top-secret 3))

  ;; ========== Classified Values ==========

  (define-record-type (%classified %make-classified classified?)
    (sealed #t)
    (opaque #t)
    (nongenerative std-security-classified)
    (fields
      (immutable level classified-level)    ;; security-level
      (immutable value classified-value)))  ;; the wrapped value

  (define (classify level value)
    ;; Wrap a value with a security level.
    (unless (security-level? level)
      (error 'classify "expected security-level" level))
    (%make-classified level value))

  ;; ========== Declassification ==========

  ;; Handler called on every declassification: (lambda (value from-level to-level reason) ...)
  (define current-declassify-handler
    (make-parameter (lambda (value from-level to-level reason)
                      ;; Default: just log to current-error-port
                      (let ([p (current-error-port)])
                        (display "[DECLASSIFY] " p)
                        (display (security-level-name from-level) p)
                        (display " -> " p)
                        (display (security-level-name to-level) p)
                        (display " reason: " p)
                        (display reason p)
                        (newline p)))))

  (define (declassify classified target-level reason)
    ;; Explicitly lower the classification of a value.
    ;; Requires an audit reason string. Calls the declassify handler.
    (unless (classified? classified)
      (error 'declassify "expected classified value" classified))
    (unless (security-level? target-level)
      (error 'declassify "expected security-level" target-level))
    (unless (string? reason)
      (error 'declassify "reason must be a string" reason))
    (let ([from (classified-level classified)]
          [val  (classified-value classified)])
      ;; Call audit handler
      ((current-declassify-handler) val from target-level reason)
      ;; Return at new level (or unwrapped if target is public)
      (if (= (%security-level-rank target-level) 0)
        val  ;; fully declassified
        (classify target-level val))))

  ;; ========== Flow Checking ==========

  (define-condition-type &flow-violation &violation
    make-flow-violation flow-violation?
    (from flow-violation-from)
    (to flow-violation-to))

  (define (check-flow! classified target-level sink-name)
    ;; Check that data can flow from its current level to the target level.
    ;; Raises &flow-violation if data would flow downward (secret → public).
    (when (classified? classified)
      (let ([from-level (classified-level classified)])
        (unless (security-level<=? from-level target-level)
          (raise (condition
                   (make-flow-violation from-level target-level)
                   (make-message-condition
                     (format #f "~a data cannot flow to ~a sink ~a without declassification"
                       (security-level-name from-level)
                       (security-level-name target-level)
                       sink-name))))))))

  (define-syntax assert-flow
    (syntax-rules ()
      [(_ expr target-level sink-name)
       (let ([v expr])
         (check-flow! v target-level 'sink-name)
         v)]))

  ) ;; end library
