#!chezscheme
;;; (std trace) — Function tracing and debugging
;;;
;;; Re-exports Chez's built-in tracing system with convenience wrappers.

(library (std trace)
  (export trace-define trace-lambda trace-let
          untrace trace-output-port
          trace-calls)

  (import (chezscheme))

  ;; trace-define, trace-lambda, trace-let are Chez built-ins (re-exported)
  ;; untrace is a Chez built-in (re-exported)
  ;; trace-output-port is a Chez parameter (re-exported)

  ;; Convenience: trace multiple procedures by name, run body, untrace
  (define-syntax trace-calls
    (syntax-rules ()
      [(_ (proc ...) body body* ...)
       (dynamic-wind
         (lambda () (trace proc) ...)
         (lambda () body body* ...)
         (lambda () (untrace proc) ...))]))

) ;; end library
