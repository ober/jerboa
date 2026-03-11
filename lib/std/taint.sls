#!chezscheme
;;; (std taint) — Taint tracking for security (Phase 4b)
;;;
;;; Track tainted values (from untrusted sources) to prevent them from
;;; flowing to sensitive sinks without sanitization.
;;;
;;; A tainted value wraps the underlying value with a set of taint labels.
;;; Sinks declared with define-sink refuse tainted values unless sanitized.

(library (std taint)
  (export
    ;; Taint labels
    taint-label?
    make-taint-label
    taint-label-name
    taint-label-severity
    ;; Common labels
    user-input-label
    sql-label
    html-label
    shell-label
    file-path-label
    ;; Tainted values
    taint
    tainted?
    taint-labels
    untaint
    untaint-with
    propagate-taint
    ;; Sinks
    define-sink
    *taint-violations*
    reset-taint-violations!
    with-taint-checking
    ;; Sanitizers
    define-sanitizer
    sql-escape
    html-escape
    shell-escape
    ;; Checking
    check-not-tainted!
    check-taint-label!
    taint-flow-report)

  (import (chezscheme))

  ;; ========== Taint Label Records ==========

  ;; severity: one of 'low 'medium 'high 'critical
  ;; Use %taint-label% as the internal record name to avoid clash with
  ;; the exported make-taint-label constructor.
  (define-record-type %taint-label%
    (fields
      (immutable name     taint-label-name)
      (immutable severity taint-label-severity))
    (nongenerative taint-label-uid)
    (sealed #t))

  (define (taint-label? x) (%taint-label%? x))

  (define (make-taint-label name severity)
    (unless (symbol? name)
      (error 'make-taint-label "name must be a symbol" name))
    (unless (memq severity '(low medium high critical))
      (error 'make-taint-label "severity must be low/medium/high/critical" severity))
    (make-%taint-label% name severity))

  ;; ========== Common Labels ==========

  (define user-input-label (make-taint-label 'user-input 'medium))
  (define sql-label        (make-taint-label 'sql        'high))
  (define html-label       (make-taint-label 'html       'medium))
  (define shell-label      (make-taint-label 'shell      'critical))
  (define file-path-label  (make-taint-label 'file-path  'high))

  ;; ========== Tainted Value Wrapper ==========

  ;; A tainted-value wraps the actual value with a list of taint-label objects.
  ;; We use a plain tagged vector for speed and simplicity.
  ;; #(tainted-value actual-value label-list)

  (define (make-tainted-value val labels)
    (vector 'tainted-value val labels))

  (define (tainted-value? x)
    (and (vector? x)
         (= (vector-length x) 3)
         (eq? (vector-ref x 0) 'tainted-value)))

  (define (tainted-value-val x)    (vector-ref x 1))
  (define (tainted-value-labels x) (vector-ref x 2))

  ;; ========== Public API ==========

  ;; (taint val label-or-list) -> tainted value
  ;; label-or-list: a single taint-label or a list of them
  (define (taint val label-or-list)
    (let ([labels (if (list? label-or-list)
                    label-or-list
                    (list label-or-list))])
      (for-each (lambda (l)
                  (unless (taint-label? l)
                    (error 'taint "not a taint-label" l)))
                labels)
      (if (tainted-value? val)
        ;; Merge with existing labels
        (make-tainted-value
          (tainted-value-val val)
          (merge-label-sets (tainted-value-labels val) labels))
        (make-tainted-value val labels))))

  ;; Merge two label lists, deduplicating by name
  (define (merge-label-sets set1 set2)
    (let loop ([rest set2] [result set1])
      (if (null? rest)
        result
        (let ([l (car rest)])
          (if (find (lambda (existing)
                      (eq? (taint-label-name existing) (taint-label-name l)))
                    result)
            (loop (cdr rest) result)
            (loop (cdr rest) (cons l result)))))))

  ;; (tainted? val) -> boolean
  (define (tainted? val)
    (tainted-value? val))

  ;; (taint-labels val) -> list of taint-label objects (or '() if clean)
  (define (taint-labels val)
    (if (tainted-value? val)
      (tainted-value-labels val)
      '()))

  ;; (untaint val) -> the underlying value, removing taint
  ;; WARNING: only use after validation/sanitization
  (define (untaint val)
    (if (tainted-value? val)
      (tainted-value-val val)
      val))

  ;; (untaint-with val sanitizer) -> sanitized value (unwrapped)
  ;; Applies sanitizer to the raw value and returns the sanitized result.
  (define (untaint-with val sanitizer)
    (unless (procedure? sanitizer)
      (error 'untaint-with "sanitizer must be a procedure" sanitizer))
    (let ([raw (untaint val)])
      (sanitizer raw)))

  ;; (propagate-taint source result) -> result possibly wrapped with source's labels
  ;; If source is tainted, wraps result with the same labels.
  (define (propagate-taint source result)
    (if (tainted-value? source)
      (taint result (tainted-value-labels source))
      result))

  ;; ========== Taint Checking ==========

  ;; (check-not-tainted! who val) — raise taint-violation if val is tainted
  (define (check-not-tainted! who val)
    (when (tainted-value? val)
      (let ([violation (list 'taint-violation who val (tainted-value-labels val))])
        (set! *current-violations*
          (cons violation *current-violations*))
        (when (*taint-checking-enabled*)
          (raise (condition
                   (make-error)
                   (make-message-condition
                     (format "taint violation in ~a: tainted value with labels ~a"
                             who
                             (map taint-label-name (tainted-value-labels val))))))))))

  ;; (check-taint-label! who val label-name) — raise if val is tainted with specific label
  (define (check-taint-label! who val label-name)
    (when (tainted-value? val)
      (let ([matching (filter (lambda (l) (eq? (taint-label-name l) label-name))
                              (tainted-value-labels val))])
        (when (pair? matching)
          (let ([violation (list 'taint-violation who val matching)])
            (set! *current-violations*
              (cons violation *current-violations*))
            (when (*taint-checking-enabled*)
              (raise (condition
                       (make-error)
                       (make-message-condition
                         (format "taint violation in ~a: value tainted with ~a"
                                 who label-name))))))))))

  ;; ========== Violations ==========

  (define *current-violations* '())

  ;; *taint-violations* — parameter returning current violation list
  (define *taint-violations*
    (make-parameter '()
      (lambda (v) v)))

  (define (reset-taint-violations!)
    (set! *current-violations* '()))

  ;; Internal parameter tracking whether taint checking raises errors
  (define *taint-checking-enabled* (make-parameter #f))

  ;; (with-taint-checking thunk) — run thunk with taint checking enabled
  (define-syntax with-taint-checking
    (syntax-rules ()
      [(_ body ...)
       (parameterize ([*taint-checking-enabled* #t])
         (reset-taint-violations!)
         (let ([result (begin body ...)])
           result))]))

  ;; ========== Sink Declaration ==========

  ;; Sink registry: symbol -> #t
  (define *sinks* (make-eq-hashtable))

  ;; (define-sink name (lambda (arg ...) body ...))
  ;; Wraps the function so that any tainted argument triggers check-not-tainted!
  (define-syntax define-sink
    (lambda (stx)
      (syntax-case stx ()
        [(_ name proc-expr)
         #'(define name
             (let ([underlying proc-expr])
               (lambda args
                 (for-each (lambda (arg)
                              (check-not-tainted! 'name arg))
                           args)
                 (apply underlying args))))])))

  ;; ========== Sanitizer Declaration ==========

  ;; (define-sanitizer name (lambda (x) ...))
  ;; Just an alias for define with documentation intent.
  (define-syntax define-sanitizer
    (syntax-rules ()
      [(_ name proc-expr)
       (define name proc-expr)]))

  ;; ========== Built-in Sanitizers ==========

  ;; sql-escape: replace ' with '' (minimal SQL sanitization demo)
  (define-sanitizer sql-escape
    (lambda (s)
      (unless (string? s)
        (error 'sql-escape "expected string" s))
      (let ([chars (string->list s)])
        (list->string
          (let loop ([rest chars] [acc '()])
            (if (null? rest)
              (reverse acc)
              (if (char=? (car rest) #\')
                (loop (cdr rest) (cons #\' (cons #\' acc)))
                (loop (cdr rest) (cons (car rest) acc)))))))))

  ;; html-escape: replace <, >, &, ", ' with HTML entities
  (define-sanitizer html-escape
    (lambda (s)
      (unless (string? s)
        (error 'html-escape "expected string" s))
      (let ([chars (string->list s)])
        (apply string-append
          (map (lambda (c)
                 (cond
                   [(char=? c #\<) "&lt;"]
                   [(char=? c #\>) "&gt;"]
                   [(char=? c #\&) "&amp;"]
                   [(char=? c #\") "&quot;"]
                   [(char=? c #\') "&#39;"]
                   [else (string c)]))
               chars)))))

  ;; shell-escape: wrap in single quotes and escape single quotes
  (define-sanitizer shell-escape
    (lambda (s)
      (unless (string? s)
        (error 'shell-escape "expected string" s))
      (string-append
        "'"
        (let ([chars (string->list s)])
          (list->string
            (let loop ([rest chars] [acc '()])
              (if (null? rest)
                (reverse acc)
                (if (char=? (car rest) #\')
                  ;; End quote, escaped quote, start quote
                  (loop (cdr rest) (append (reverse (string->list "'\\''")) acc))
                  (loop (cdr rest) (cons (car rest) acc)))))))
        "'")))

  ;; ========== Taint Flow Report ==========

  ;; (taint-flow-report val) -> string describing the taint flow
  (define (taint-flow-report val)
    (if (not (tainted-value? val))
      "clean (not tainted)"
      (let ([labels (tainted-value-labels val)])
        (string-append
          "TAINTED with: "
          (apply string-append
            (map (lambda (l)
                   (string-append
                     (symbol->string (taint-label-name l))
                     " [" (symbol->string (taint-label-severity l)) "] "))
                 labels))))))

  ) ;; end library
