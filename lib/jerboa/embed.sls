#!chezscheme
;;; (jerboa embed) — Embeddable Runtime / Sandbox API
;;;
;;; Isolated evaluation environments using Chez Scheme's environment system.

(library (jerboa embed)
  (export
    make-sandbox sandbox? sandbox-eval sandbox-eval-string
    sandbox-define! sandbox-ref sandbox-call sandbox-environment
    sandbox-error? sandbox-error-message sandbox-error-irritants
    sandbox-reset! sandbox-import!
    make-sandbox-config sandbox-config?
    with-sandbox)

  (import (chezscheme))

  ;; ========== Sandbox Config ==========

  (define-record-type (%sandbox-config make-sandbox-config sandbox-config?)
    (fields (immutable max-eval-time     sandbox-config-max-eval-time)    ;; ms or #f
            (immutable allowed-imports   sandbox-config-allowed-imports)  ;; list or #f (all)
            (immutable capture-output    sandbox-config-capture-output))) ;; #t/#f

  ;; ========== Sandbox Error ==========

  (define-record-type (%sandbox-error make-sandbox-error sandbox-error?)
    (fields (immutable message   sandbox-error-message)
            (immutable irritants sandbox-error-irritants)))

  ;; When error is called as (error "msg" irritants...) inside eval,
  ;; Chez may set the message to an internal format string and put
  ;; the actual message in the irritants list.
  ;; Pattern: msg = "invalid message argument ~s (who = ~s, irritants = ~s)"
  ;;          irritants = (first-irritant "msg" (rest-irritants...))
  (define (exn->sandbox-error exn)
    (cond
      [(message-condition? exn)
       (let ([msg  (condition-message exn)]
             [irrs (if (irritants-condition? exn) (condition-irritants exn) '())])
         ;; Detect the "invalid message argument" pattern from eval context
         (if (and (string? msg)
                  (>= (string-length msg) 24)
                  (string=? (substring msg 0 24) "invalid message argument"))
           ;; irritants = (first-arg "real-msg" (rest-args...))
           ;; Extract real message and irritants from the encoded form
           (if (and (>= (length irrs) 3)
                    (string? (list-ref irrs 1)))
             (make-sandbox-error
               (list-ref irrs 1)
               (let ([rest (list-ref irrs 2)])
                 (if (list? rest) (cons (car irrs) rest)
                     (list (car irrs)))))
             (make-sandbox-error msg irrs))
           (make-sandbox-error msg irrs)))]
      [(string? exn)
       (make-sandbox-error exn '())]
      [else
       (make-sandbox-error (format "~a" exn) '())]))

  ;; ========== Sandbox ==========

  ;; env: Chez environment (interaction-environment copy)
  ;; config: sandbox-config or #f
  ;; user-bindings: hashtable of name -> value (user definitions)

  (define-record-type (%sandbox make-sandbox-raw sandbox?)
    (fields (mutable env           sandbox-environment sandbox-environment-set!)
            (mutable user-bindings sandbox-user-bindings sandbox-user-bindings-set!)
            (immutable config      sandbox-config-field)))

  (define (make-sandbox . args)
    ;; Optional config as first arg.
    (let ([config (if (and (pair? args) (sandbox-config? (car args)))
                    (car args)
                    #f)])
      (make-sandbox-raw
        (copy-environment (interaction-environment) #t)
        (make-hashtable equal-hash equal?)
        config)))

  (define (sandbox-eval sb datum)
    ;; Evaluate a datum in the sandbox. Returns result or sandbox-error.
    (guard (exn [#t (exn->sandbox-error exn)])
      (eval datum (sandbox-environment sb))))

  (define (sandbox-eval-string sb str)
    ;; Read and eval a string in the sandbox.
    (guard (exn [#t (exn->sandbox-error exn)])
      (let ([port (open-input-string str)])
        (let loop ([last (if #f #f)])
          (let ([form (read port)])
            (if (eof-object? form)
              last
              (loop (eval form (sandbox-environment sb)))))))))

  (define (sandbox-define! sb name val)
    ;; Bind name (symbol) to val in the sandbox.
    (hashtable-set! (sandbox-user-bindings sb) name val)
    (eval `(define ,name ',val) (sandbox-environment sb)))

  (define (sandbox-ref sb name)
    ;; Look up a binding in the sandbox. Returns value or raises error.
    (guard (exn [#t (error 'sandbox-ref "unbound variable" name)])
      (eval name (sandbox-environment sb))))

  (define (sandbox-call sb name . args)
    ;; Call a procedure defined in the sandbox.
    (guard (exn [#t (exn->sandbox-error exn)])
      (let ([proc (eval name (sandbox-environment sb))])
        (apply proc args))))

  (define (sandbox-reset! sb)
    ;; Clear user-defined bindings by creating a fresh environment.
    (hashtable-clear! (sandbox-user-bindings sb))
    (sandbox-environment-set! sb
      (copy-environment (interaction-environment) #t)))

  (define (sandbox-import! sb lib-name)
    ;; Import a library into the sandbox.
    ;; lib-name: e.g., '(std log) or '(chezscheme)
    (guard (exn [#t (exn->sandbox-error exn)])
      (eval `(import ,lib-name) (sandbox-environment sb))))

  (define-syntax with-sandbox
    (syntax-rules ()
      [(_ sb body ...)
       (let ([sb (make-sandbox)])
         body ...)]))

) ;; end library
