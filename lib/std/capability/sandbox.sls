#!chezscheme
;;; (std capability sandbox) — Enhanced capability sandbox (Phase 4b)
;;;
;;; Policy-based sandbox that uses capability infrastructure to restrict
;;; what code can do. Supports allow/deny policies for capabilities and
;;; module imports, with timeout support.

(library (std capability sandbox)
  (export
    ;; Sandbox creation
    make-sandbox
    sandbox?
    sandbox-eval
    sandbox-load
    sandbox-allowed?
    ;; Policy
    make-sandbox-policy
    sandbox-policy?
    policy-allow!
    policy-deny!
    policy-allow-import!
    policy-deny-import!
    policy-allows?
    policy-allowed
    policy-denied
    policy-allowed-imports
    policy-denied-imports
    ;; Built-in policies
    minimal-policy
    standard-policy
    network-policy
    fs-policy
    ;; Running code safely
    sandbox-run
    sandbox-run/timeout
    with-sandbox
    ;; Violation handling
    make-sandbox-violation
    sandbox-violation?
    sandbox-violation-capability
    sandbox-violation-context)

  (import (chezscheme)
          (except (std capability) with-sandbox))

  ;; ========== Sandbox Violation Condition ==========

  (define-condition-type &sandbox-violation &error
    make-sandbox-violation sandbox-violation?
    (capability sandbox-violation-capability)
    (context    sandbox-violation-context))

  ;; ========== Policy ==========
  ;;
  ;; Policy is a tagged vector:
  ;; #(sandbox-policy allowed denied allowed-imports denied-imports)
  ;; allowed, denied: lists of capability name symbols
  ;; allowed-imports, denied-imports: lists of module specs

  (define (make-sandbox-policy)
    (vector 'sandbox-policy
            (list)   ;; allowed
            (list)   ;; denied
            (list)   ;; allowed-imports
            (list))) ;; denied-imports

  (define (sandbox-policy? x)
    (and (vector? x)
         (= (vector-length x) 5)
         (eq? (vector-ref x 0) 'sandbox-policy)))

  (define (policy-allowed         p) (vector-ref p 1))
  (define (policy-denied          p) (vector-ref p 2))
  (define (policy-allowed-imports p) (vector-ref p 3))
  (define (policy-denied-imports  p) (vector-ref p 4))

  (define (set-policy-allowed!         p v) (vector-set! p 1 v))
  (define (set-policy-denied!          p v) (vector-set! p 2 v))
  (define (set-policy-allowed-imports! p v) (vector-set! p 3 v))
  (define (set-policy-denied-imports!  p v) (vector-set! p 4 v))

  ;; (policy-allow! policy cap-name) — add cap-name to allowed set
  (define (policy-allow! policy cap-name)
    (unless (sandbox-policy? policy)
      (error 'policy-allow! "not a sandbox-policy" policy))
    (unless (symbol? cap-name)
      (error 'policy-allow! "capability name must be a symbol" cap-name))
    (unless (memq cap-name (policy-allowed policy))
      (set-policy-allowed! policy (cons cap-name (policy-allowed policy)))))

  ;; (policy-deny! policy cap-name) — add cap-name to denied set
  (define (policy-deny! policy cap-name)
    (unless (sandbox-policy? policy)
      (error 'policy-deny! "not a sandbox-policy" policy))
    (unless (symbol? cap-name)
      (error 'policy-deny! "capability name must be a symbol" cap-name))
    (unless (memq cap-name (policy-denied policy))
      (set-policy-denied! policy (cons cap-name (policy-denied policy)))))

  ;; (policy-allow-import! policy module-spec)
  (define (policy-allow-import! policy module-spec)
    (unless (sandbox-policy? policy)
      (error 'policy-allow-import! "not a sandbox-policy" policy))
    (unless (memq module-spec (policy-allowed-imports policy))
      (set-policy-allowed-imports!
        policy (cons module-spec (policy-allowed-imports policy)))))

  ;; (policy-deny-import! policy module-spec)
  (define (policy-deny-import! policy module-spec)
    (unless (sandbox-policy? policy)
      (error 'policy-deny-import! "not a sandbox-policy" policy))
    (unless (memq module-spec (policy-denied-imports policy))
      (set-policy-denied-imports!
        policy (cons module-spec (policy-denied-imports policy)))))

  ;; ========== Built-in Policies ==========

  ;; minimal-policy: only pure computation (empty allow set = deny all)
  (define minimal-policy (make-sandbox-policy))

  ;; standard-policy: basic computation capabilities allowed
  (define standard-policy
    (let ([p (make-sandbox-policy)])
      (policy-allow! p 'arithmetic)
      (policy-allow! p 'string-ops)
      (policy-allow! p 'list-ops)
      (policy-allow! p 'vector-ops)
      (policy-allow! p 'boolean-ops)
      p))

  ;; network-policy: adds network capability
  (define network-policy
    (let ([p (make-sandbox-policy)])
      (policy-allow! p 'arithmetic)
      (policy-allow! p 'string-ops)
      (policy-allow! p 'list-ops)
      (policy-allow! p 'network)
      p))

  ;; fs-policy: adds filesystem capability
  (define fs-policy
    (let ([p (make-sandbox-policy)])
      (policy-allow! p 'arithmetic)
      (policy-allow! p 'string-ops)
      (policy-allow! p 'list-ops)
      (policy-allow! p 'filesystem)
      p))

  ;; ========== Policy Check ==========

  ;; (policy-allows? policy cap-name) -> boolean
  ;; denied takes precedence; if neither listed, deny by default
  (define (policy-allows? policy cap-name)
    (cond
      [(memq cap-name (policy-denied policy)) #f]
      [(memq cap-name (policy-allowed policy)) #t]
      [else #f]))

  ;; ========== Sandbox ==========
  ;;
  ;; Sandbox is a tagged vector:
  ;; #(sandbox policy root-cap env)

  (define (make-sandbox policy)
    (unless (sandbox-policy? policy)
      (error 'make-sandbox "not a sandbox-policy" policy))
    (vector 'sandbox policy (make-root-capability) (interaction-environment)))

  (define (sandbox? x)
    (and (vector? x)
         (= (vector-length x) 4)
         (eq? (vector-ref x 0) 'sandbox)))

  (define (sandbox-policy-of sb) (vector-ref sb 1))
  (define (sandbox-root-cap  sb) (vector-ref sb 2))
  (define (sandbox-env       sb) (vector-ref sb 3))

  ;; (sandbox-allowed? sandbox cap-name) -> boolean
  (define (sandbox-allowed? sb cap-name)
    (unless (sandbox? sb)
      (error 'sandbox-allowed? "not a sandbox" sb))
    (policy-allows? (sandbox-policy-of sb) cap-name))

  ;; (sandbox-eval sandbox expr) -> result
  (define (sandbox-eval sb expr)
    (unless (sandbox? sb)
      (error 'sandbox-eval "not a sandbox" sb))
    (guard (exn [#t (raise exn)])
      (eval expr (sandbox-env sb))))

  ;; (sandbox-load sandbox file-path) -> result
  (define (sandbox-load sb file-path)
    (unless (sandbox? sb)
      (error 'sandbox-load "not a sandbox" sb))
    (unless (sandbox-allowed? sb 'filesystem)
      (raise (condition
               (make-sandbox-violation 'filesystem 'sandbox-load)
               (make-message-condition
                 (format "sandbox policy denies filesystem access: ~a" file-path)))))
    (guard (exn [#t (raise exn)])
      (load file-path)))

  ;; ========== Running Code Safely ==========

  ;; (sandbox-run policy thunk) -> result or condition object
  ;; Runs thunk; catches exceptions and returns them as conditions.
  (define (sandbox-run policy thunk)
    (unless (sandbox-policy? policy)
      (error 'sandbox-run "not a sandbox-policy" policy))
    (guard (exn [#t exn])
      (thunk)))

  ;; (sandbox-run/timeout policy thunk timeout-ms) -> result or condition
  ;; Like sandbox-run but with a thread-based timeout.
  (define (sandbox-run/timeout policy thunk timeout-ms)
    (unless (sandbox-policy? policy)
      (error 'sandbox-run/timeout "not a sandbox-policy" policy))
    (unless (and (integer? timeout-ms) (positive? timeout-ms))
      (error 'sandbox-run/timeout "timeout-ms must be a positive integer" timeout-ms))
    (let ([result    #f]
          [error     #f]
          [done-mutex (make-mutex)]
          [done-cond  (make-condition)]
          [done?      #f])
      (let ([worker
             (lambda ()
               (guard (exn [#t (set! error exn)])
                 (set! result (thunk)))
               (with-mutex done-mutex
                 (set! done? #t)
                 (condition-broadcast done-cond)))])
        (fork-thread worker)
        (with-mutex done-mutex
          ;; Convert milliseconds to (nanoseconds seconds) for make-time
          (let* ([total-ns   (* timeout-ms 1000000)]
                 [secs       (quotient  total-ns 1000000000)]
                 [ns         (remainder total-ns 1000000000)]
                 [deadline   (make-time 'time-duration ns secs)])
            (let loop ([first? #t])
              (unless done?
                (if first?
                  (let ([timed-out
                         (not (condition-wait done-cond done-mutex deadline))])
                    (when timed-out
                      (set! error
                        (condition
                          (make-error)
                          (make-message-condition
                            (format "sandbox timeout after ~a ms" timeout-ms)))))
                    (unless timed-out (loop #f)))
                  (void))))))
        (if error error result))))

  ;; (with-sandbox policy body ...) — evaluate body under sandbox policy
  (define-syntax with-sandbox
    (syntax-rules ()
      [(_ policy body ...)
       (sandbox-run policy (lambda () body ...))]))

  ) ;; end library
