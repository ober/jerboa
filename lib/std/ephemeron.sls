#!chezscheme
;;; (std ephemeron) — Ephemeron tables and weak references
;;;
;;; Exposes Chez's ephemeron support for GC-aware weak references.

(library (std ephemeron)
  (export make-ephemeron-eq-hashtable
          make-weak-eq-hashtable
          ephemeron-pair ephemeron-pair?
          ephemeron-key ephemeron-value
          weak-pair? make-weak-pair
          bwp-object?)

  (import (chezscheme))

  ;; Ephemeron pair: key-value pair where value is only traced
  ;; if key is reachable through non-ephemeron paths.
  (define (ephemeron-pair key value)
    (ephemeron-cons key value))

  ;; Accessors (ephemerons are pairs)
  (define (ephemeron-key ep) (car ep))
  (define (ephemeron-value ep) (cdr ep))

  ;; Weak pair: car is weakly held. When car is GC'd, it becomes #!bwp.
  (define (make-weak-pair a d)
    (weak-cons a d))

) ;; end library
