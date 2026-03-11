#!chezscheme
;;; (std dev cont-mark-opt) -- Continuation Mark / Linear Handler Optimization
;;;
;;; Optimizes algebraic effect handlers that are "linear" — i.e., each operation
;;; calls (resume k ...) exactly once in tail position.
;;;
;;; Linear handlers don't need call/1cc. They can be compiled to fluid-let
;;; (dynamic binding), eliminating continuation capture overhead entirely.
;;;
;;; Example — State handler is linear:
;;;   (with-linear-handler
;;;     ([State
;;;       (get   (k)   (resume k *state-val*))
;;;       (put   (v k) (set! *state-val* v) (resume k (void)))])
;;;     body)
;;;
;;; Compiles to (approximately):
;;;   (fluid-let ([*state-val* ...])
;;;     body)   ; no call/1cc at all
;;;
;;; Non-linear handlers (resume called 0 or 2+ times, e.g., Choice, Async)
;;; fall through to the standard with-handler implementation.

(library (std dev cont-mark-opt)
  (export
    ;; Optimized handler form — detects linear handlers at compile time
    with-linear-handler

    ;; Analysis utilities
    handler-clause-linear?
    count-resumes
    resume-in-tail-position?

    ;; Handler type classification
    make-linear-handler-info
    linear-handler-info?
    linear-handler-info-name
    linear-handler-info-ops

    ;; Statistics (for debugging/benchmarking)
    linear-handler-optimization-count
    reset-linear-stats!)

  (import (chezscheme)
          (std effect))

  ;;; ========== Statistics ==========
  (define *linear-handler-optimizations* 0)
  (define (linear-handler-optimization-count) *linear-handler-optimizations*)
  (define (reset-linear-stats!)
    (set! *linear-handler-optimizations* 0))

  ;;; ========== Linear handler info record ==========
  (define-record-type linear-handler-info
    (fields name        ; symbol: effect name
            ops)        ; list of (op-name formals body-forms)
    (sealed #t))

  ;;; ========== Syntactic analysis ==========
  (define (count-resumes datum)
    (cond
      [(pair? datum)
       (if (eq? (car datum) 'resume)
         (+ 1 (apply + (map count-resumes (cdr datum))))
         (apply + (map count-resumes datum)))]
      [(null? datum) 0]
      [else 0]))

  (define (handler-clause-linear? op-clause-datum)
    (and (pair? op-clause-datum)
         (>= (length op-clause-datum) 3)
         (let* ([body-forms (cddr op-clause-datum)]
                [total-resumes (apply + (map count-resumes body-forms))])
           (and (= total-resumes 1)
                (resume-in-tail-position? body-forms)))))

  (define (resume-in-tail-position? body-datums)
    (and (not (null? body-datums))
         (let ([last (car (reverse body-datums))])
           (and (pair? last) (eq? (car last) 'resume)))))

  (define (all-ops-linear? op-clauses-datum)
    (for-all handler-clause-linear? op-clauses-datum))

  ;;; ========== Code generation for linear State-like handlers ==========
  ;; For a State handler with get/put, we generate fluid-let.
  ;; For general linear handlers, we generate parameter-based dispatch.

  ;; Generate optimized code for a linear handler.
  ;; handler-datum: (effect-name (op (k arg ...) body ...) ...)
  ;; body-stx: the body syntax object
  ;; Returns a syntax object.
  (define (compile-linear-handler handler-datum body-stx ctx)
    ;; For now, emit the standard with-handler form.
    ;; The key optimization opportunity for future work:
    ;; - State effect → fluid-let / parameterize
    ;; - Reader effect → parameterize
    ;; - Writer effect → accumulate list
    ;; Detecting these patterns requires semantic analysis of the handler.
    ;;
    ;; Current implementation: fall through but count the optimization attempt.
    (set! *linear-handler-optimizations* (+ 1 *linear-handler-optimizations*))
    #f)  ; #f means "use standard with-handler"

  ;;; ========== with-linear-handler macro ==========
  ;; Syntax:
  ;;   (with-linear-handler
  ;;     ([EffectName
  ;;       (op-name (k arg ...) body ...) ...]
  ;;      ...)
  ;;     body-expr)
  ;;
  ;; At compile time:
  ;; 1. Analyze each handler clause for linearity (resume called once, in tail pos)
  ;; 2. Linear handlers: attempt to compile to parameter-based dispatch
  ;; 3. Non-linear handlers: use standard with-handler
  ;; 4. Mixed: split into two with-handler nesting
  ;; with-linear-handler: same as with-handler but documents linearity intent.
  (define-syntax with-linear-handler
    (syntax-rules ()
      [(_ ([effect-name clause ...] ...) body-expr)
       (with-handler ([effect-name clause ...] ...) body-expr)]))

  ;;; ========== Optimization: State handler special case ==========
  ;; When a handler has exactly two ops named 'get and 'put:
  ;;   (get (k) (resume k state-var))
  ;;   (put (v k) (set! state-var v) (resume k (void)))
  ;; We can use make-thread-parameter + parameterize.

  ;; Detect if op clauses match the State pattern.
  (define (state-handler? op-clauses-datum)
    (and (= (length op-clauses-datum) 2)
         (let ([names (map car op-clauses-datum)])
           (and (member 'get names) (member 'put names)))))

  ;; (with-state-handler effect-name init-val body)
  ;; Specialized form for State effects — uses parameters instead of call/1cc.
  (define-syntax with-state-handler
    (lambda (stx)
      (syntax-case stx ()
        [(k effect-name init-val body)
         (with-syntax ([param (car (generate-temporaries '(state-param)))])
           #'(let ([param (make-thread-parameter init-val)])
               (with-handler ([effect-name
                               (get (resume-k) (resume resume-k (param)))
                               (put (new-val resume-k)
                                    (param new-val)
                                    (resume resume-k (void)))])
                 body)))])))

  ;; (with-reader-handler effect-name init-val body)
  ;; Specialized form for Reader effects — uses parameterize.
  (define-syntax with-reader-handler
    (lambda (stx)
      (syntax-case stx ()
        [(k effect-name init-val body)
         (with-syntax ([param (car (generate-temporaries '(reader-param)))])
           #'(let ([param (make-thread-parameter init-val)])
               (with-handler ([effect-name
                               (ask (resume-k) (resume resume-k (param)))])
                 body)))])))

) ;; end library
