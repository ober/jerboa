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

  (import (chezscheme)
          (std security restrict)
          (jerboa reader))

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
         ;; Detect the "invalid message argument" pattern from eval context.
         ;; Guard with length checks before any list-ref access.
         (if (and (string? msg)
                  (>= (string-length msg) 24)
                  (string=? (substring msg 0 24) "invalid message argument")
                  (list? irrs)
                  (>= (length irrs) 3)
                  (string? (list-ref irrs 1)))
           ;; irritants = (first-arg "real-msg" (rest-args...))
           ;; Extract real message and irritants from the encoded form
           (make-sandbox-error
             (list-ref irrs 1)
             (let ([rest (list-ref irrs 2)])
               (if (and (list? rest) (not (null? irrs)))
                 (cons (car irrs) rest)
                 (list (car irrs)))))
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
    ;; HARDENED: Defaults to restricted environment (allowlist-only).
    ;; Use (copy-environment (interaction-environment) #t) only if you
    ;; explicitly need full access — never for untrusted code.
    (let ([config (if (and (pair? args) (sandbox-config? (car args)))
                    (car args)
                    #f)])
      (make-sandbox-raw
        (make-restricted-environment)
        (make-hashtable equal-hash equal?)
        config)))

  ;; Internal: run thunk with max-eval-time enforcement if configured.
  (define (%with-time-limit sb thunk)
    (let ([config (sandbox-config-field sb)])
      (if (and config (sandbox-config-max-eval-time config))
        (let ([timeout-ms (sandbox-config-max-eval-time config)]
              [result     #f]
              [finished?  #f]
              [lock       (make-mutex)]
              [cv         (make-condition)])
          ;; Run in a worker thread
          (fork-thread
            (lambda ()
              (let ([val (guard (exn [#t (exn->sandbox-error exn)])
                           (thunk))])
                (with-mutex lock
                  (set! result val)
                  (set! finished? #t)
                  (condition-signal cv)))))
          ;; Wait with timeout (wall-clock via time-utc, not CPU time,
          ;; so that blocked I/O operations are properly timed out)
          (with-mutex lock
            (unless finished?
              (let loop ()
                (unless finished?
                  (condition-wait cv lock (make-time 'time-duration
                                           (* timeout-ms 1000000) 0))
                  (unless finished?
                    ;; Timed out
                    (void))))))
          (if finished?
            result
            (make-sandbox-error
              (format "sandbox eval timed out after ~a ms" timeout-ms) '())))
        ;; No time limit configured — run directly
        (guard (exn [#t (exn->sandbox-error exn)])
          (thunk)))))

  (define (sandbox-eval sb datum)
    ;; Evaluate a datum in the sandbox. Returns result or sandbox-error.
    (%with-time-limit sb
      (lambda () (eval datum (sandbox-environment sb)))))

  (define (sandbox-eval-string sb str)
    ;; Read and eval a string in the sandbox.
    ;; HARDENED: Uses jerboa-read (depth-limited) instead of bare read.
    ;; Both reading and evaluation are covered by the time limit,
    ;; so pathological input (deeply nested structures) is bounded.
    (%with-time-limit sb
      (lambda ()
        (let ([port (open-input-string str)])
          (let loop ([last (if #f #f)])
            (let ([form (parameterize ([*max-read-depth* 200]
                                       [*max-list-length* 100000])
                          (jerboa-read port))])
              (if (eof-object? form)
                last
                (loop (eval form (sandbox-environment sb))))))))))

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
    ;; HARDENED: Uses restricted environment, consistent with make-sandbox.
    (hashtable-clear! (sandbox-user-bindings sb))
    (sandbox-environment-set! sb
      (make-restricted-environment)))

  (define (sandbox-import! sb lib-name)
    ;; Import a library into the sandbox.
    ;; lib-name: e.g., '(std log) or '(chezscheme)
    ;; HARDENED: Enforces allowed-imports from sandbox config.
    (let ([config (sandbox-config-field sb)])
      (when (and config (sandbox-config-allowed-imports config))
        (unless (member lib-name (sandbox-config-allowed-imports config))
          (raise (condition
                   (make-message-condition
                     (format "sandbox import denied: ~a is not in allowed-imports list"
                             lib-name))
                   (make-irritants-condition (list lib-name)))))))
    (guard (exn [#t (exn->sandbox-error exn)])
      (eval `(import ,lib-name) (sandbox-environment sb))))

  (define-syntax with-sandbox
    (syntax-rules ()
      [(_ sb body ...)
       (let ([sb (make-sandbox)])
         body ...)]))

) ;; end library
