;;; Profile-Guided Optimization (PGO) — Phase 5a (Track 11.3)
;;;
;;; Collects runtime profiling data and uses it to guide compilation.
;;; Provides call-count profiling, hot-function detection, and profile
;;; data persistence.

(library (std compiler pgo)
  (export
    ;; Profile collection
    profile-reset!            ; clear all collected data
    profile-running?          ; #t when collection is active
    profiling-enable!         ; turn profiling on
    profiling-disable!        ; turn profiling off

    ;; Data access
    profile-data              ; full alist of (name . count)
    profile-call-count        ; call count for a name symbol
    profile-hot-functions     ; top-N hottest functions

    ;; Persistence
    profile-save              ; write profile data to file
    profile-load              ; read profile data from file
    profile-load!             ; load and merge into current data

    ;; Annotation helpers
    define/profile            ; define + auto-instrument
    with-profiling            ; run body with profiling enabled

    ;; PGO macros
    define-pgo-module         ; mark a module for PGO
    profile-guided-inline?    ; hint: should this call site be inlined?

    ;; Reporting
    profile-report)

  (import (chezscheme))

  ;; -----------------------------------------------------------------------
  ;; State (symbol → integer call-count table)
  ;; Use an eq-hashtable keyed by symbols to avoid mutable-var-in-macro issues.
  ;; -----------------------------------------------------------------------

  (define *counts* (make-eq-hashtable))
  (define *active-cell* (list #f))   ; (active?)

  (define (profiling-enable!)  (set-car! *active-cell* #t))
  (define (profiling-disable!) (set-car! *active-cell* #f))
  (define (profile-running?)   (car *active-cell*))

  (define (profile-reset!)
    "Clear all profiling data"
    (let-values ([(keys _) (hashtable-entries *counts*)])
      (vector-for-each (lambda (k) (hashtable-set! *counts* k 0)) keys)))

  ;; -----------------------------------------------------------------------
  ;; Internal tick — called from define/profile expansions
  ;; -----------------------------------------------------------------------

  (define (pgo-tick! sym)
    (when (car *active-cell*)
      (hashtable-update! *counts* sym (lambda (n) (+ n 1)) 0)))

  ;; -----------------------------------------------------------------------
  ;; Data access
  ;; -----------------------------------------------------------------------

  (define (profile-data)
    "Return alist of (symbol . count) sorted by descending count"
    (let-values ([(keys vals) (hashtable-entries *counts*)])
      (let ([result '()])
        (vector-for-each (lambda (k v) (set! result (cons (cons k v) result)))
                         keys vals)
        (list-sort (lambda (a b) (> (cdr a) (cdr b))) result))))

  (define (profile-call-count sym)
    "Return the call count for SYM (0 if not recorded)"
    (hashtable-ref *counts* sym 0))

  (define (profile-hot-functions . args)
    "Return the top-N entries by call count.
     Usage: (profile-hot-functions) or (profile-hot-functions n)
            or (profile-hot-functions filename n)"
    (let-values ([(file n)
                  (cond
                    [(and (= (length args) 2)
                          (string? (car args)) (integer? (cadr args)))
                     (values (car args) (cadr args))]
                    [(and (= (length args) 1) (integer? (car args)))
                     (values #f (car args))]
                    [else (values #f 20)])])
      (let* ([data   (if file (profile-load file) (profile-data))]
             [sorted (list-sort (lambda (a b) (> (cdr a) (cdr b))) data)])
        (if (< n (length sorted)) (list-head sorted n) sorted))))

  ;; -----------------------------------------------------------------------
  ;; Persistence
  ;; -----------------------------------------------------------------------

  (define (profile-save filename)
    "Write current profile data to FILENAME"
    (call-with-output-file filename
      (lambda (port)
        (write `(jerboa-profile ,(profile-data)) port)
        (newline port))))

  (define (profile-load filename)
    "Load profile data from FILENAME; returns alist"
    (if (file-exists? filename)
        (call-with-input-file filename
          (lambda (port)
            (let ([form (read port)])
              (if (and (pair? form) (eq? (car form) 'jerboa-profile))
                  (cadr form)
                  (error 'profile-load "malformed profile" filename)))))
        '()))

  (define (profile-load! filename)
    "Merge profile data from FILENAME into current counts"
    (for-each
      (lambda (entry)
        (hashtable-update! *counts* (car entry)
                           (lambda (n) (+ n (cdr entry))) 0))
      (profile-load filename)))

  ;; -----------------------------------------------------------------------
  ;; define/profile — auto-instrumented define
  ;;
  ;; (define/profile (f x y) body ...)
  ;; expands to a function that ticks the symbol 'f before running body.
  ;; -----------------------------------------------------------------------

  (define-syntax define/profile
    (syntax-rules ()
      [(_ (name args ...) body ...)
       (define (name args ...)
         (pgo-tick! 'name)
         body ...)]))

  ;; -----------------------------------------------------------------------
  ;; with-profiling
  ;; -----------------------------------------------------------------------

  (define-syntax with-profiling
    (syntax-rules ()
      [(_ body ...)
       (dynamic-wind
         profiling-enable!
         (lambda () body ...)
         profiling-disable!)]))

  ;; -----------------------------------------------------------------------
  ;; define-pgo-module — documentation/annotation marker
  ;; -----------------------------------------------------------------------

  (define-syntax define-pgo-module
    (syntax-rules ()
      [(_ (lib ...) body ...) (begin body ...)]))

  ;; -----------------------------------------------------------------------
  ;; profile-guided-inline?
  ;; -----------------------------------------------------------------------

  (define (profile-guided-inline? sym threshold)
    "Return #t if SYM should be inlined (call count >= threshold)"
    (>= (hashtable-ref *counts* sym 0) threshold))

  ;; -----------------------------------------------------------------------
  ;; profile-report
  ;; -----------------------------------------------------------------------

  (define (profile-report . args)
    "Print a human-readable profile report"
    (let ([port (if (null? args) (current-output-port) (car args))]
          [n    20])
      (let ([data (profile-data)])
        (fprintf port "~n=== Profile Report (~a entries) ===~n" (length data))
        (for-each
          (lambda (entry)
            (fprintf port "  ~a: ~a calls~n" (car entry) (cdr entry)))
          (if (< n (length data)) (list-head data n) data))
        (fprintf port "====================================~n"))))

)
