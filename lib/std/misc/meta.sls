#!chezscheme
;;; (std misc meta) — Clojure-style metadata on values.
;;;
;;; Clojure lets any reference value carry an immutable metadata map
;;; that doesn't affect equality or hash but can be queried and
;;; updated. Used for source-location tracking in macros, type hints,
;;; docstrings, spec annotations, cache keys, and so on.
;;;
;;;   (def m (with-meta (hash-map "x" 1) (hash-map 'source "input.edn")))
;;;   (meta m)                  ;; => (hash-map 'source "input.edn")
;;;   (strip-meta m)            ;; => the original (hash-map "x" 1)
;;;   (=? m (hash-map "x" 1))   ;; => #t — metadata does not affect =?
;;;
;;; Implementation
;;; --------------
;;; Jerboa values are not uniform — strings, numbers, and other flat
;;; types can't carry slot extensions, and modifying persistent
;;; collection records to add a metadata slot would break every
;;; existing instantiation call site.
;;;
;;; Instead, we use a lightweight wrapper record: `meta-wrapped` holds
;;; a value and its metadata. `meta` returns the metadata (or `#f`),
;;; `strip-meta` returns the underlying value. `with-meta` wraps; if
;;; the input is already wrapped, the wrapper is rebuilt rather than
;;; nested, so you get exactly one layer no matter how many times
;;; you call it.
;;;
;;; The trade-off is that meta-wrapped values are NOT transparently
;;; interchangeable with raw values for arbitrary operations. You
;;; should call `strip-meta` before handing a metadata-carrying
;;; value to an op that doesn't know about meta. The `=?` operator
;;; in `(std clojure)` is taught to unwrap on both sides so that
;;; metadata-wrapped and raw values compare equal — this matches
;;; Clojure's semantics where metadata does not participate in
;;; equality.

(library (std misc meta)
  (export
    with-meta
    meta
    vary-meta
    meta-wrapped?
    strip-meta)

  (import (except (chezscheme) meta))

  (define-record-type mwrap
    (fields (immutable val) (immutable m))
    (sealed #t))

  ;; (meta-wrapped? x) => #t if x was produced by `with-meta`.
  (define (meta-wrapped? x) (mwrap? x))

  ;; (strip-meta x) => the underlying value, or x itself if not wrapped.
  (define (strip-meta x)
    (if (mwrap? x) (mwrap-val x) x))

  ;; (meta x) => the metadata map, or #f if none.
  ;;
  ;; Returns #f rather than an empty map so that callers can use
  ;; `(or (meta x) default)` idioms in both Jerboa and Clojure style.
  (define (meta x)
    (if (mwrap? x) (mwrap-m x) #f))

  ;; (with-meta value m) => value with metadata m attached.
  ;;
  ;; If `value` is already a meta-wrapper, the new wrapper replaces
  ;; the old one rather than nesting. This keeps `(strip-meta ...)`
  ;; a single-step operation regardless of how many times `with-meta`
  ;; has been applied.
  (define (with-meta value m)
    (make-mwrap
      (if (mwrap? value) (mwrap-val value) value)
      m))

  ;; (vary-meta value f arg ...)
  ;; => (with-meta value (apply f (meta value) arg ...))
  ;;
  ;; Lets you update metadata in place, e.g.:
  ;;   (vary-meta x hash-put! 'line 42)
  ;; though most users write update functions that return a new map.
  (define (vary-meta value f . args)
    (with-meta value (apply f (meta value) args)))

) ;; end library
