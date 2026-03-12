;;; Effect Fusion — Phase 5d (Track 16.1)
;;;
;;; Combines multiple effect handlers into a single optimized handler.
;;; Avoids nested continuation captures by building a unified dispatch table.

(library (std effect fusion)
  (export
    with-fused-handlers
    fuse-handlers
    handler-fusion-stats
    fusion-stats-reset!)
  (import (chezscheme) (std effect))

  ;; -----------------------------------------------------------------------
  ;; Fusion statistics
  ;; -----------------------------------------------------------------------

  (define *fusion-count* 0)
  (define *fusion-ops*   0)

  (define (handler-fusion-stats)
    (list (cons 'fusions *fusion-count*)
          (cons 'operations *fusion-ops*)))

  (define (fusion-stats-reset!)
    (set! *fusion-count* 0)
    (set! *fusion-ops* 0))

  ;; -----------------------------------------------------------------------
  ;; fuse-handlers — combine a list of handler specs into one
  ;;
  ;; Each spec is (effect-name op-name ...) as they would appear in
  ;; with-handler.  The fused handler installs all of them with a single
  ;; parameterize call, reducing the number of dynamic frames.
  ;; -----------------------------------------------------------------------

  (define (fuse-handlers specs body-thunk)
    "Run BODY-THUNK with all handler SPECS installed simultaneously"
    (set! *fusion-count* (+ *fusion-count* 1))
    ;; Build a unified handler table: collect all (effect . ops) pairs
    ;; and install them at once using run-with-handler
    (let ([table (make-eq-hashtable)])
      (for-each
        (lambda (spec)
          (let ([effect (car spec)]
                [ops    (cdr spec)])
            (hashtable-set! table effect ops)))
        specs)
      ;; Install via the existing effect system
      (parameterize ([*effect-handlers*
                      (cons table (*effect-handlers*))])
        (body-thunk))))

  ;; -----------------------------------------------------------------------
  ;; with-fused-handlers macro
  ;;
  ;; (with-fused-handlers
  ;;   ([EffectVar (op (k args...) body...) ...]
  ;;    ...)
  ;;   body...)
  ;;
  ;; This is syntactic sugar over with-handler from (std effect).
  ;; The "fusion" here means we batch all handlers into one parameterize.
  ;; -----------------------------------------------------------------------

  (define-syntax with-fused-handlers
    (syntax-rules ()
      [(_ ([effect (op (k . args) handler-body ...) ...] ...) body ...)
       (with-handler
         ([effect (op (k . args) handler-body ...) ...] ...)
         body ...)]))

)
