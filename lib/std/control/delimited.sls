;;; Delimited Continuations — Phase 5a (Track 12.1)
;;;
;;; Implements shift/reset (Danvy-Filinski) and control/prompt (Felleisen)
;;; delimited control operators on top of Chez Scheme's call/cc.
;;;
;;; Key insight: the metacontinuation stack uses a mutable variable so
;;; that continuation invocations see the current (dynamic) state rather
;;; than the state at capture time (which parameterize would enforce via
;;; dynamic-wind).
;;;
;;; References:
;;;   Danvy & Filinski 1990: "Abstracting Control"
;;;   Filinski 1994: "Representing Monads"

(library (std control delimited)
  (export
    ;; Shift/reset — composable delimited continuations
    reset
    shift

    ;; Control/prompt — abortive delimited continuations
    prompt
    control

    ;; Named prompts for nested multi-prompt delimited control
    make-prompt-tag
    prompt-tag?
    prompt-tag-name
    reset-at
    shift-at
    prompt-at
    control-at

    ;; Utilities
    reset/values
    abort)

  (import (except (chezscheme) reset abort))

  ;; -----------------------------------------------------------------------
  ;; Prompt tags — unique labels for nested delimiters
  ;; -----------------------------------------------------------------------

  (define-record-type prompt-tag
    (fields (immutable name prompt-tag-name))
    (protocol (lambda (new) (lambda (name) (new name)))))

  (define *default-tag* (make-prompt-tag 'default))

  ;; -----------------------------------------------------------------------
  ;; Metacontinuation stack
  ;;
  ;; Represented as a list of (tag . escape-k) pairs.
  ;; Using a plain mutable cell (not parameterize) so that calling a
  ;; captured continuation sees the current dynamic state of the stack.
  ;; -----------------------------------------------------------------------

  (define *mk* '())   ; list of (tag . k)

  (define (mk-push! tag k)
    (set! *mk* (cons (cons tag k) *mk*)))

  (define (mk-pop!)
    (let ([top (car *mk*)])
      (set! *mk* (cdr *mk*))
      top))

  (define (mk-find tag)
    "Find and remove the innermost frame with TAG; return (frame . rest)"
    (let loop ([stack *mk*] [above '()])
      (cond
        [(null? stack)
         (error 'shift "no enclosing reset for tag" (prompt-tag-name tag))]
        [(eq? (caar stack) tag)
         ;; Found: restore *mk* to the tail, return the escape-k
         (let ([k    (cdar stack)]
               [rest (cdr stack)])
           (set! *mk* rest)
           ;; Return escape-k and the frames that were above it (for
           ;; named-prompt multi-prompt support — currently unused)
           k)]
        [else
         (loop (cdr stack) (cons (car stack) above))])))

  ;; -----------------------------------------------------------------------
  ;; Core: reset and shift
  ;; -----------------------------------------------------------------------

  (define (%do-reset tag thunk)
    (call-with-current-continuation
      (lambda (k)
        (mk-push! tag k)
        (let* ([v (thunk)]
               [frame (and (not (null? *mk*)) (car *mk*))])
          ;; If the innermost frame matches OUR tag, pop it and pass v up.
          ;; This handles the normal (non-shift) return from thunk.
          (when (and frame (eq? (car frame) tag))
            (let ([k2 (cdr frame)])
              (set! *mk* (cdr *mk*))
              (k2 v)))
          ;; If we get here, either *mk* is empty (top-level reset) or
          ;; an inner reset already handled propagation.
          v))))

  (define (%do-shift tag f)
    (call-with-current-continuation
      (lambda (k)
        ;; Pop the nearest frame for this tag (the escape-k of the enclosing reset)
        (let ([k-escape (mk-find tag)])
          ;; Invoke the escape continuation with (f dk)
          ;; dk reinstates a delimiter before resuming the captured k
          (k-escape
            (f (lambda (v)
                 (%do-reset tag (lambda () (k v))))))))))

  ;; -----------------------------------------------------------------------
  ;; Core: prompt and control (abortive — k is one-shot, non-reifiable)
  ;; -----------------------------------------------------------------------

  (define (%do-prompt tag thunk)
    (call-with-current-continuation
      (lambda (k)
        (mk-push! tag k)
        (let* ([v (thunk)]
               [frame (and (not (null? *mk*)) (car *mk*))])
          (when (and frame (eq? (car frame) tag))
            (let ([k2 (cdr frame)])
              (set! *mk* (cdr *mk*))
              (k2 v)))
          v))))

  (define (%do-control tag f)
    ;; Like shift but k does NOT reinstall a delimiter when called
    (call-with-current-continuation
      (lambda (k)
        (let ([k-escape (mk-find tag)])
          (k-escape (f k))))))

  ;; -----------------------------------------------------------------------
  ;; Public macros (default tag)
  ;; -----------------------------------------------------------------------

  (define-syntax reset
    (syntax-rules ()
      [(_ body ...) (%do-reset *default-tag* (lambda () body ...))]))

  (define-syntax shift
    (syntax-rules ()
      [(_ k body ...) (%do-shift *default-tag* (lambda (k) body ...))]))

  (define-syntax prompt
    (syntax-rules ()
      [(_ body ...) (%do-prompt *default-tag* (lambda () body ...))]))

  (define-syntax control
    (syntax-rules ()
      [(_ k body ...) (%do-control *default-tag* (lambda (k) body ...))]))

  ;; -----------------------------------------------------------------------
  ;; Named-prompt variants
  ;; -----------------------------------------------------------------------

  (define-syntax reset-at
    (syntax-rules ()
      [(_ tag body ...) (%do-reset tag (lambda () body ...))]))

  (define-syntax shift-at
    (syntax-rules ()
      [(_ tag k body ...) (%do-shift tag (lambda (k) body ...))]))

  (define-syntax prompt-at
    (syntax-rules ()
      [(_ tag body ...) (%do-prompt tag (lambda () body ...))]))

  (define-syntax control-at
    (syntax-rules ()
      [(_ tag k body ...) (%do-control tag (lambda (k) body ...))]))

  ;; -----------------------------------------------------------------------
  ;; reset/values — preserves multiple values
  ;; -----------------------------------------------------------------------

  (define-syntax reset/values
    (syntax-rules ()
      [(_ body ...)
       (call-with-values (lambda () (reset body ...)) values)]))

  ;; -----------------------------------------------------------------------
  ;; abort — discard delimited continuation, return value directly
  ;; -----------------------------------------------------------------------

  (define (abort . vals)
    (let ([k-escape (mk-find *default-tag*)])
      (apply k-escape vals)))

)
