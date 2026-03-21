#!chezscheme
;;; (std error context) — Error context accumulation
;;;
;;; Automatically accumulates breadcrumb context for error messages.
;;; When an error occurs inside nested with-context forms, the full
;;; context chain is included in the error message.
;;;
;;; Usage:
;;;   (with-context "processing request #1234"
;;;     (with-context "validating input"
;;;       (check-argument string? input 'validate)))
;;;   ;; Error includes: "processing request #1234 > validating input > ..."
;;;
;;;   (with-context* ('request-handler "POST /api/users" user-id: 42)
;;;     ...)  ;; structured context with metadata

(library (std error context)
  (export
    with-context
    with-context*
    current-context
    context->string
    context->list
    raise-in-context
    &context-condition make-context-condition context-condition?
    context-condition-chain)

  (import (chezscheme))

  ;; =========================================================================
  ;; Context chain — thread-local stack of context strings
  ;; =========================================================================

  (define *context-stack* (make-thread-parameter '()))

  (define (current-context)
    ;; Returns the current context stack as a list of strings (outermost first).
    (reverse (*context-stack*)))

  (define (context->string)
    ;; Format the current context chain as "a > b > c".
    (let ([ctx (current-context)])
      (if (null? ctx)
          ""
          (let loop ([parts ctx] [acc ""])
            (cond
              [(null? parts) acc]
              [(string=? acc "") (loop (cdr parts) (car parts))]
              [else (loop (cdr parts)
                         (string-append acc " > " (car parts)))])))))

  (define (context->list)
    ;; Returns context as a list of strings (outermost first).
    (current-context))

  ;; =========================================================================
  ;; Condition type for context
  ;; =========================================================================

  (define-condition-type &context-condition &condition
    make-context-condition context-condition?
    (chain context-condition-chain))  ;; list of strings

  ;; =========================================================================
  ;; with-context — push a context string for the dynamic extent of body
  ;; =========================================================================

  (define-syntax with-context
    (syntax-rules ()
      [(_ label body ...)
       (parameterize ([*context-stack* (cons label (*context-stack*))])
         (with-exception-handler
           (lambda (exn)
             ;; Re-raise with context attached if not already present
             (if (and (condition? exn) (context-condition? exn))
                 (raise exn)
                 (let* ([ctx-str (context->string)]
                        [orig-msg (cond
                                    [(and (condition? exn) (message-condition? exn))
                                     (condition-message exn)]
                                    [(string? exn) exn]
                                    [else (format #f "~a" exn)])]
                        [new-msg (string-append ctx-str " > " orig-msg)])
                   (raise (condition
                           (make-context-condition (current-context))
                           (make-message-condition new-msg))))))
           (lambda () body ...)))]))

  ;; =========================================================================
  ;; with-context* — structured context with key-value metadata
  ;; =========================================================================

  (define-syntax with-context*
    (syntax-rules ()
      [(_ (tag description kv ...) body ...)
       (let ([label (format #f "~a: ~a" 'tag description)])
         (with-context label body ...))]))

  ;; =========================================================================
  ;; raise-in-context — raise an error with current context included
  ;; =========================================================================

  (define (raise-in-context who msg . args)
    (let ([ctx (context->string)]
          [formatted (apply format #f msg args)])
      (raise (condition
              (make-who-condition who)
              (make-message-condition
               (if (string=? ctx "")
                   formatted
                   (string-append ctx " > " formatted)))
              (make-context-condition (current-context))))))

) ;; end library
