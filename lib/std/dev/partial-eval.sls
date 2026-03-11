#!chezscheme
;;; (std dev partial-eval) -- Compile-Time Partial Evaluation
;;;
;;; Extends (std staging) with CT-callable functions and binding-time analysis.
;;; Pure functions defined with define-ct can be called at compile time via (ct ...).
;;;
;;; Usage:
;;;   (import (std dev partial-eval))
;;;
;;;   (define-ct (fib n)
;;;     (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
;;;
;;;   (define answer (ct (fib 30)))
;;;   ;; At compile time: evaluates to 832040
;;;   ;; At runtime: (define answer 832040) — zero cost
;;;
;;;   (define-ct primes (sieve 1000))
;;;   ;; Sieve of Eratosthenes at compile time; runtime constant

(library (std dev partial-eval)
  (export
    ;; CT function definition — available at both compile time and runtime
    define-ct

    ;; Force compile-time evaluation — result spliced as quoted datum
    ct

    ;; Try compile-time eval; fall back to runtime on failure
    ct/try

    ;; Binding-time analysis predicates
    ct-literal?
    ct-constant-expr?

    ;; Reset the compile-time environment (testing/debugging)
    ct-env-reset!)

  (import (chezscheme))

  ;;; ========== Compile-time evaluation environment ==========
  ;; Must be a meta (phase-1) definition so macro transformers can access it.
  ;; This environment accumulates define-ct function definitions.
  ;; Initialized with the interaction-environment at compile time.
  (meta define *ct-env* (interaction-environment))

  ;; Runtime accessor — no-op at runtime since *ct-env* is phase-1
  (define (ct-env-reset!) (void))

  ;;; ========== define-ct ==========
  ;; (define-ct (name arg ...) body ...)
  ;;   Defines a function for both compile-time and runtime use.
  ;;   The function is immediately registered in *ct-env* by eval'ing
  ;;   the definition there, making it available to subsequent (ct ...) forms.
  ;;
  ;; (define-ct name expr)
  ;;   Defines a compile-time constant (expr is eval'd at expansion time).
  (define-syntax define-ct
    (lambda (stx)
      (syntax-case stx ()
        ;; Function form: (define-ct (name arg ...) body ...)
        [(_ (name arg ...) body ...)
         (let* ([name-sym  (syntax->datum #'name)]
                [args-list (syntax->datum #'(arg ...))]
                [body-list (syntax->datum #'(body ...))]
                [def-form  `(define (,name-sym ,@args-list) ,@body-list)])
           ;; Register in CT environment immediately (side-effect at expand time)
           (eval def-form *ct-env*)
           ;; Emit normal runtime definition
           #'(define (name arg ...) body ...))]

        ;; Value form: (define-ct name expr)
        [(_ name expr)
         (let* ([name-sym  (syntax->datum #'name)]
                [val-datum (syntax->datum #'expr)]
                [def-form  `(define ,name-sym ,val-datum)])
           (eval def-form *ct-env*)
           #'(define name expr))])))

  ;;; ========== ct ==========
  ;; (ct expr)
  ;; Evaluates expr at macro-expansion time in the CT env.
  ;; All previous define-ct definitions are visible.
  ;; Result is spliced in as a quoted datum — zero runtime cost.
  ;;
  ;; Example:
  ;;   (ct (fib 30))   => 832040 at compile time
  ;;   (ct (+ 2 3))    => 5
  (define-syntax ct
    (lambda (stx)
      (syntax-case stx ()
        [(_ expr)
         (let* ([datum-expr (syntax->datum #'expr)]
                [result     (eval datum-expr *ct-env*)])
           (datum->syntax #'ct `(quote ,result)))])))

  ;; Unique sentinel for ct/try failure — accessible at phase 1 via meta define
  (meta define *ct-failure-sentinel* (list 'ct-failure-unique))

  ;;; ========== ct/try ==========
  ;; (ct/try expr)
  ;; Try to evaluate expr at compile time.
  ;; If eval succeeds: splice result as quoted datum.
  ;; If eval fails (e.g., references runtime variables): leave expr as-is.
  ;;
  ;; Useful for optional compile-time optimization:
  ;;   (define x (ct/try (expensive-pure-computation)))
  (define-syntax ct/try
    (lambda (stx)
      (syntax-case stx ()
        [(_ expr)
         (let* ([datum-expr (syntax->datum #'expr)]
                [result     (guard (exn [#t *ct-failure-sentinel*])
                              (eval datum-expr *ct-env*))])
           (if (eq? result *ct-failure-sentinel*)
             #'expr                                          ; runtime fallback
             (datum->syntax #'ct/try `(quote ,result))))]))) ; compile-time result

  ;;; ========== Binding-time analysis ==========
  ;; Utilities to inspect whether a syntax form is statically known.

  ;; (ct-literal? stx)
  ;; Returns #t if stx is a self-evaluating literal (number, string, boolean, char).
  (define (ct-literal? stx)
    (let ([d (syntax->datum stx)])
      (or (number? d) (string? d) (boolean? d) (char? d) (null? d)
          (bytevector? d) (and (pair? d) (eq? (car d) 'quote)))))

  ;; (ct-constant-expr? stx)
  ;; Returns #t if stx is a simple constant expression that can be evaluated
  ;; at compile time without side effects.
  ;; This is a conservative approximation.
  (define (ct-constant-expr? stx)
    (let ([d (syntax->datum stx)])
      (cond
        ;; Self-evaluating
        [(or (number? d) (string? d) (boolean? d) (char? d) (null? d)) #t]
        ;; Quoted form
        [(and (pair? d) (eq? (car d) 'quote)) #t]
        ;; Arithmetic on constants
        [(and (pair? d) (memq (car d) '(+ - * / quotient remainder modulo
                                         expt sqrt abs max min floor ceiling
                                         truncate round))
              (for-all ct-constant-expr? (cdr (syntax->list stx)))) #t]
        ;; String operations on constants
        [(and (pair? d) (memq (car d) '(string-append string-length substring
                                         string->symbol symbol->string
                                         number->string string->number))
              (for-all ct-constant-expr? (cdr (syntax->list stx)))) #t]
        ;; List constructors on constants
        [(and (pair? d) (eq? (car d) 'list)
              (for-all ct-constant-expr? (cdr (syntax->list stx)))) #t]
        [else #f])))

) ;; end library
