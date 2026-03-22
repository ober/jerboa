#!chezscheme
;;; (std misc advice) — Advice system for function wrapping/debugging
;;;
;;; Wrap any procedure with entry/exit hooks without modifying its definition.
;;;
;;; (define add (make-advisable +))
;;; (advise-before add (lambda args (display "calling add\n")))
;;; (advise-after add (lambda (result) (display "result: ") (display result) (newline)))
;;; (advise-around add (lambda (next . args) (apply next args)))
;;; (unadvise add)
;;;
;;; (define-advisable (my-add x y) (+ x y))

(library (std misc advice)
  (export make-advisable advise-before advise-after advise-around
          unadvise advised? define-advisable)
  (import (chezscheme))

  ;; Internal record storing the advice state for an advisable procedure.
  ;; - original: the unwrapped procedure
  ;; - befores: list of (lambda args ...) hooks, run before the call
  ;; - afters: list of (lambda (result) ...) hooks, run after the call
  ;; - arounds: list of (lambda (next . args) ...) wrappers, composed as middleware
  (define-record-type advice-box
    (fields
      (immutable original)
      (mutable befores)
      (mutable afters)
      (mutable arounds)))

  ;; Eq-hashtable keyed on the wrapper procedure itself.
  ;; Maps wrapper -> (box . updater) where updater sets the current dispatch fn.
  (define advice-table (make-eq-hashtable))

  (define (get-box proc)
    (hashtable-ref advice-table proc #f))

  ;; Build the composed procedure from the advice-box state.
  ;; The composition order:
  ;;   1. Run all before hooks (in order added)
  ;;   2. Build the around chain: innermost = original, each around wraps the next
  ;;   3. Run all after hooks (in order added) on the result
  (define (build-advised box)
    (let ([original (advice-box-original box)]
          [befores  (advice-box-befores box)]
          [afters   (advice-box-afters box)]
          [arounds  (advice-box-arounds box)])
      ;; Build the around chain. arounds is stored in order added.
      ;; The last-added around is outermost (wraps everything).
      ;; So we fold-left: start with original, each around wraps the current.
      (let ([chained
             (fold-left
               (lambda (next around-fn)
                 ;; around-fn receives (next . args) and should call next
                 (lambda args (apply around-fn next args)))
               original
               arounds)])
        ;; Return the fully advised procedure
        (lambda args
          ;; Run before hooks
          (for-each (lambda (bf) (apply bf args)) befores)
          ;; Run the around chain (which includes the original)
          (let ([result (apply chained args)])
            ;; Run after hooks
            (for-each (lambda (af) (af result)) afters)
            result)))))

  ;; make-advisable: wrap a procedure so it can receive advice.
  ;; Returns a new procedure that dispatches through the advice chain.
  (define (make-advisable proc)
    (let* ([box (make-advice-box proc '() '() '())]
           ;; The wrapper holds a mutable reference to the current dispatch fn
           [current-fn proc]
           [wrapper
            (lambda args (apply current-fn args))])
      (hashtable-set! advice-table wrapper
                      (cons box (lambda (fn) (set! current-fn fn))))
      wrapper))

  ;; Helper to get box and updater, or error
  (define (get-box+updater proc who)
    (let ([entry (hashtable-ref advice-table proc #f)])
      (unless entry
        (error who "not an advisable procedure" proc))
      (values (car entry) (cdr entry))))

  ;; Rebuild and install the current advised function
  (define (rebuild! proc)
    (let-values ([(box updater) (get-box+updater proc 'rebuild!)])
      (if (and (null? (advice-box-befores box))
               (null? (advice-box-afters box))
               (null? (advice-box-arounds box)))
          (updater (advice-box-original box))
          (updater (build-advised box)))))

  ;; advise-before: add a before-hook. Hook receives the same args as the function.
  (define (advise-before proc hook)
    (let-values ([(box updater) (get-box+updater proc 'advise-before)])
      (advice-box-befores-set! box
        (append (advice-box-befores box) (list hook)))
      (rebuild! proc)))

  ;; advise-after: add an after-hook. Hook receives the result value.
  (define (advise-after proc hook)
    (let-values ([(box updater) (get-box+updater proc 'advise-after)])
      (advice-box-afters-set! box
        (append (advice-box-afters box) (list hook)))
      (rebuild! proc)))

  ;; advise-around: add an around wrapper. Receives (next . args).
  ;; The wrapper should call (apply next args) to invoke the next layer.
  ;; Later-added arounds are outermost.
  (define (advise-around proc hook)
    (let-values ([(box updater) (get-box+updater proc 'advise-around)])
      (advice-box-arounds-set! box
        (append (advice-box-arounds box) (list hook)))
      (rebuild! proc)))

  ;; unadvise: remove all advice, restoring the original behavior.
  (define (unadvise proc)
    (let-values ([(box updater) (get-box+updater proc 'unadvise)])
      (advice-box-befores-set! box '())
      (advice-box-afters-set! box '())
      (advice-box-arounds-set! box '())
      (updater (advice-box-original box))))

  ;; advised?: check if a procedure currently has any advice installed.
  (define (advised? proc)
    (let ([entry (hashtable-ref advice-table proc #f)])
      (and entry
           (let ([box (car entry)])
             (or (pair? (advice-box-befores box))
                 (pair? (advice-box-afters box))
                 (pair? (advice-box-arounds box)))))))

  ;; define-advisable: syntax for defining an advisable function directly.
  (define-syntax define-advisable
    (syntax-rules ()
      [(_ (name args ...) body ...)
       (define name
         (make-advisable (lambda (args ...) body ...)))]))

) ;; end library
