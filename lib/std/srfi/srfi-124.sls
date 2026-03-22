#!chezscheme
;;; :std/srfi/124 -- Ephemerons (SRFI-124)
;;; Wraps Chez Scheme's built-in ephemeron-pair support.
;;; An ephemeron is a key-value pair where the value is held weakly --
;;; if the key is GC'd, the datum becomes inaccessible (broken).

(library (std srfi srfi-124)
  (export
    make-ephemeron ephemeron? ephemeron-key
    ephemeron-datum ephemeron-broken?)

  (import (chezscheme))

  (define (make-ephemeron key datum)
    (ephemeron-cons key datum))

  (define (ephemeron? x)
    (ephemeron-pair? x))

  (define (ephemeron-key eph)
    (unless (ephemeron-pair? eph)
      (error 'ephemeron-key "not an ephemeron" eph))
    (let ([k (car eph)])
      (if (bwp-object? k) #f k)))

  (define (ephemeron-datum eph)
    (unless (ephemeron-pair? eph)
      (error 'ephemeron-datum "not an ephemeron" eph))
    (let ([d (cdr eph)])
      (if (bwp-object? d) #f d)))

  (define (ephemeron-broken? eph)
    (unless (ephemeron-pair? eph)
      (error 'ephemeron-broken? "not an ephemeron" eph))
    (bwp-object? (car eph)))
)
