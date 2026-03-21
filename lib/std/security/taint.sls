#!chezscheme
;;; (std security taint) — Taint tracking for untrusted data
;;;
;;; Marks data from untrusted sources and prevents it from reaching
;;; dangerous sinks without explicit sanitization.
;;;
;;; Taint categories: http-input, env-input, file-input, net-input, deser-input
;;; Sinks check for taint and raise &taint-violation if unsanitized data is used.

(library (std security taint)
  (export
    ;; Core
    taint
    tainted?
    taint-class
    taint-value
    untaint

    ;; Convenience
    taint-http
    taint-env
    taint-file
    taint-net
    taint-deser

    ;; Checking
    check-untainted!
    assert-untainted

    ;; Propagation
    tainted-string-append
    tainted-string-ref
    tainted-substring
    tainted-string-length

    ;; Safe wrappers (auto-check taint at dangerous sinks)
    safe-open-input-file
    safe-open-output-file
    safe-system
    safe-delete-file

    ;; Condition type
    &taint-violation
    make-taint-violation
    taint-violation?
    taint-violation-class
    taint-violation-sink)

  (import (chezscheme))

  ;; ========== Tainted Value ==========

  (define-record-type (tainted-value %make-tainted tainted?)
    (sealed #t)
    (opaque #t)
    (nongenerative std-security-tainted)
    (fields
      (immutable class taint-class)   ;; symbol: http-input, env-input, etc.
      (immutable value taint-value))) ;; the wrapped value

  (define (taint class value)
    ;; Mark a value as tainted with the given class.
    (unless (symbol? class)
      (error 'taint "class must be a symbol" class))
    (%make-tainted class value))

  (define (taint-http value) (taint 'http-input value))
  (define (taint-env value)  (taint 'env-input value))
  (define (taint-file value) (taint 'file-input value))
  (define (taint-net value)  (taint 'net-input value))
  (define (taint-deser value) (taint 'deser-input value))

  ;; ========== Untaint (explicit sanitization) ==========

  (define (untaint value)
    ;; Remove taint from a value. Only call after proper sanitization.
    (if (tainted? value)
      (taint-value value)
      value))

  ;; ========== Taint Checking ==========

  (define-condition-type &taint-violation &violation
    make-taint-violation taint-violation?
    (class taint-violation-class)
    (sink taint-violation-sink))

  (define (check-untainted! value sink-name)
    ;; Raise &taint-violation if value is tainted.
    (when (tainted? value)
      (raise (condition
               (make-taint-violation (taint-class value) sink-name)
               (make-message-condition
                 (format #f "tainted ~a data cannot reach ~a sink without sanitization"
                   (taint-class value) sink-name))))))

  (define-syntax assert-untainted
    (syntax-rules ()
      [(_ expr sink-name)
       (let ([v expr])
         (check-untainted! v 'sink-name)
         v)]))

  ;; ========== Taint-Propagating String Operations ==========

  (define (tainted-string-append . args)
    ;; If any argument is tainted, result is tainted with first taint class found.
    (let ([taint-cls #f])
      (let ([strs (map (lambda (a)
                         (cond
                           [(tainted? a)
                            (unless taint-cls (set! taint-cls (taint-class a)))
                            (let ([v (taint-value a)])
                              (if (string? v) v (error 'tainted-string-append "not a string" v)))]
                           [(string? a) a]
                           [else (error 'tainted-string-append "not a string" a)]))
                       args)])
        (let ([result (apply string-append strs)])
          (if taint-cls
            (taint taint-cls result)
            result)))))

  (define (tainted-string-ref s i)
    (if (tainted? s)
      (string-ref (taint-value s) i)
      (string-ref s i)))

  (define (tainted-substring s start end)
    (if (tainted? s)
      (taint (taint-class s) (substring (taint-value s) start end))
      (substring s start end)))

  (define (tainted-string-length s)
    (if (tainted? s)
      (string-length (taint-value s))
      (string-length s)))

  ;; ========== Safe Wrappers (auto-enforce taint at dangerous sinks) ==========
  ;;
  ;; These wrappers automatically reject tainted arguments at dangerous
  ;; operations. Use these instead of bare Chez primitives when processing
  ;; untrusted input.

  (define (safe-open-input-file path)
    ;; Reject tainted paths before opening files for reading.
    (check-untainted! path 'open-input-file)
    (open-input-file path))

  (define (safe-open-output-file path)
    ;; Reject tainted paths before opening files for writing.
    (check-untainted! path 'open-output-file)
    (open-output-file path))

  (define (safe-system cmd)
    ;; Reject tainted commands before shell execution.
    (check-untainted! cmd 'system)
    (system cmd))

  (define (safe-delete-file path)
    ;; Reject tainted paths before file deletion.
    (check-untainted! path 'delete-file)
    (delete-file path))

  ) ;; end library
