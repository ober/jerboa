#!chezscheme
;;; (std deprecation) — Deprecation warning system
;;;
;;; Provides tools for marking functions as deprecated and emitting
;;; warnings to stderr when they are called.
;;;
;;; API:
;;;   (deprecated name message)              — emit a deprecation warning
;;;   (define-deprecated old-name new-name)  — macro: define old as wrapper that warns then delegates
;;;   deprecation-warning-handler            — parameter controlling warning output
;;;   suppress-deprecation-warnings          — parameter to silence all warnings

(library (std deprecation)
  (export deprecated define-deprecated
          deprecation-warning-handler
          suppress-deprecation-warnings)

  (import (chezscheme))

  ;; Parameter: when #t, all deprecation warnings are silenced.
  (define suppress-deprecation-warnings
    (make-parameter #f))

  ;; Parameter: a procedure (name message -> void) that handles warning output.
  ;; Default writes to stderr.
  (define deprecation-warning-handler
    (make-parameter
     (lambda (name message)
       (let ([port (current-error-port)])
         (display "WARNING: " port)
         (display name port)
         (display " is deprecated. " port)
         (display message port)
         (newline port)))))

  ;; Emit a deprecation warning (respects suppression).
  (define (deprecated name message)
    (unless (suppress-deprecation-warnings)
      ((deprecation-warning-handler) name message)))

  ;; Macro: define old-name as a wrapper that warns once per call, then
  ;; delegates to new-name with all arguments.
  (define-syntax define-deprecated
    (syntax-rules ()
      [(_ old-name new-name)
       (define (old-name . args)
         (deprecated 'old-name
                     (string-append "Use " (symbol->string 'new-name) " instead."))
         (apply new-name args))]))

) ;; end library
