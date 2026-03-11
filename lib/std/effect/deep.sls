#!chezscheme
;;; (std effect deep) — Deep algebraic effect handlers
;;;
;;; Deep handlers re-install themselves after each resume, so the handler
;;; persists for the entire scope of the computation body.  By contrast,
;;; the shallow handlers in (std effect) are consumed on each resume.
;;;
;;; API:
;;;   (with-deep-handler
;;;     ([EffectName (op-name (k arg ...) body ...) ...] ...)
;;;     body ...)
;;;
;;;   (resume/deep k val handler-frame)
;;;     Internal helper that resumes k while re-installing the handler frame.
;;;
;;; The macro captures the handler frame at the point of the
;;; with-deep-handler call and wraps every user-supplied k with a
;;; closure that re-pushes that frame before resuming, so any further
;;; effect performs inside the resumed computation are seen by the same
;;; handler.

(library (std effect deep)
  (export
    with-deep-handler
    resume/deep)

  (import (chezscheme) (std effect))

  ;; -------- resume/deep --------
  ;;
  ;; Re-installs frame onto *effect-handlers* before resuming k.
  ;; This ensures that any effect performed during the resumed
  ;; computation is caught by the same handler that originally
  ;; intercepted the operation.

  (define (resume/deep k val frame)
    (run-with-handler frame (lambda () (k val))))

  ;; -------- with-deep-handler macro --------
  ;;
  ;; (with-deep-handler
  ;;   ([Async
  ;;     (await (k promise) expr ...)
  ;;     (spawn (k thunk)   expr ...)]
  ;;    [State
  ;;     (get  (k)    expr ...)
  ;;     (put  (k v)  expr ...)])
  ;;   body ...)
  ;;
  ;; Each k received in a handler clause is automatically wrapped so
  ;; that calling (k val) is equivalent to (resume/deep k val frame).
  ;; The original k is bound to k/raw if you need the raw one-shot
  ;; continuation, but in typical usage you just use k.

  (define-syntax with-deep-handler
    (lambda (stx)
      (define (effect-desc-id eff-name-stx)
        (datum->syntax eff-name-stx
          (string->symbol
            (string-append
              (symbol->string (syntax->datum eff-name-stx))
              "::descriptor"))))

      ;; Rewrite an op-clause, wrapping k with a deep-resume closure.
      ;; Input:  (op-sym (k arg ...) body ...)
      ;; Output: (op-sym (k/raw arg ...) body ...[k->resume/deep k/raw])
      ;; We synthesize a new k name and rebind it.
      (define (build-deep-op-pair op-clause frame-id-stx)
        (syntax-case op-clause ()
          [(op-sym (k arg ...) body ...)
           ;; k-raw is used to call the original one-shot continuation
           ;; after wrapping with the frame.
           (with-syntax ([k-raw (datum->syntax #'k (gensym "k-raw"))]
                         [frame-id frame-id-stx])
             #'(cons 'op-sym
                     (lambda (k-raw arg ...)
                       ;; Rebind k to the deep-resuming wrapper.
                       (let ([k (lambda (v) (resume/deep k-raw v frame-id))])
                         body ...))))]))

      (define (build-deep-effect-entry eff-clause frame-id-stx)
        (syntax-case eff-clause ()
          [(eff-name op-clause ...)
           (with-syntax ([desc-id (effect-desc-id #'eff-name)]
                         [(op-pair ...)
                          (map (lambda (c) (build-deep-op-pair c frame-id-stx))
                               (syntax->list #'(op-clause ...)))])
             #'(list desc-id op-pair ...))]))

      (syntax-case stx ()
        [(_ (eff-clause ...) body ...)
         ;; We need frame-id to be bound before the entries are built
         ;; (it is referenced inside the lambda wrappers), so we use
         ;; letrec to allow forward reference: frame is set! once built.
         (let ([frame-id (datum->syntax #'with-deep-handler (gensym "dframe"))])
           (with-syntax ([frame-id frame-id]
                         [(entry ...)
                          (map (lambda (c) (build-deep-effect-entry c frame-id))
                               (syntax->list #'(eff-clause ...)))])
             #'(let ([frame-id #f])
                 (let ([tbl (make-eq-hashtable)])
                   (let ([e entry])
                     (hashtable-set! tbl (car e) (cdr e)))
                   ...
                   (set! frame-id tbl)
                   (run-with-handler frame-id (lambda () body ...))))))])))

  ) ;; end library
