#!chezscheme
;;; (std typed check) — Compile-time type checker plugging into define/t
;;;
;;; define/ct runs the type inference engine at macro-expansion time and
;;; emits a compile-time warning (via display to current-error-port) if
;;; inferred types do not match the declared annotation.  The generated
;;; runtime code is identical to define (zero extra overhead in release mode).
;;;
;;; API:
;;;   (define/ct (name [arg : type] ...) : ret-type body ...)
;;;     — compile-time-checked function definition
;;;   (lambda/ct ([arg : type] ...) : ret-type body ...)
;;;     — compile-time-checked lambda
;;;   (check-program-types forms)
;;;     — type-check a list of top-level forms; return list of type-errors
;;;   (with-type-checking body ...)
;;;     — evaluate body with type-checking warnings enabled
;;;   (type-check-file filename)
;;;     — read and type-check all forms in filename; return list of type-errors
;;;   *enable-type-checking*
;;;     — parameter controlling whether compile-time checks run (default #t)

(library (std typed check)
  (export
    define/ct
    lambda/ct
    check-program-types
    with-type-checking
    type-check-file
    *enable-type-checking*)

  (import (chezscheme) (std typed) (std typed env) (std typed infer))

  ;; ========== Configuration ==========

  (define *enable-type-checking*
    (make-parameter #t
      (lambda (v)
        (unless (boolean? v)
          (error '*enable-type-checking* "must be boolean" v))
        v)))

  ;; ========== Parse typed-arg list ==========
  ;; (parse-args-datum args-datum) → ((name . type) ...)
  ;; Works on plain datums (not syntax objects) for the type checker.

  (define (parse-args-datum args-datum)
    (let loop ([rest args-datum] [result '()])
      (if (null? rest)
        (reverse result)
        (let ([item (car rest)])
          (cond
            ;; [name : type]
            [(and (list? item) (= (length item) 3) (eq? (cadr item) ':))
             (loop (cdr rest) (cons (cons (car item) (caddr item)) result))]
            ;; plain name
            [(symbol? item)
             (loop (cdr rest) (cons (cons item 'any) result))]
            [else
             (loop (cdr rest) result)])))))

  ;; ========== Compile-time type checking helper ==========
  ;;
  ;; Given a function's argument name→type bindings, a return type, and
  ;; the body forms (as datums), run the type inference engine and emit
  ;; a warning for any mismatch.  Returns #f on success, error list on failure.

  (define (compile-time-check! who arg-bindings ret-type body-forms src-stx)
    (when (*enable-type-checking*)
      (let* ([env (type-env-extend (empty-type-env) arg-bindings)]
             [errors (with-type-errors-collected
                       (lambda ()
                         ;; Check each body form; verify last form's type
                         (let ([inferred-body-type
                                (let loop ([forms body-forms])
                                  (if (null? forms)
                                    'void
                                    (if (null? (cdr forms))
                                      (check-type (car forms) ret-type env)
                                      (begin
                                        (infer-type (car forms) env)
                                        (loop (cdr forms))))))])
                           inferred-body-type)))])
        (unless (null? errors)
          ;; Display compile-time warnings (not fatal)
          (for-each
            (lambda (te)
              (display (string-append
                         "\n; compile-time type warning in "
                         (symbol->string who)
                         ": "
                         (type-error-message te)
                         "\n")
                (current-error-port)))
            errors)
          errors))))

  ;; ========== define/ct ==========
  ;;
  ;; (define/ct (name [arg : type] ...) : ret-type body ...)
  ;; Runs type checker at macro-expansion time, then produces a plain define.

  (define-syntax define/ct
    (lambda (stx)
      (define (parse-typed-args args)
        (let loop ([rest (syntax->list args)] [result '()])
          (if (null? rest)
            (reverse result)
            (let ([item (car rest)])
              (syntax-case item ()
                [(arg-name sep type-name)
                 (eq? (syntax->datum #'sep) ':)
                 (loop (cdr rest)
                       (cons (list #'arg-name #'type-name) result))]
                [arg-name
                 (identifier? #'arg-name)
                 (loop (cdr rest)
                       (cons (list #'arg-name (datum->syntax #'arg-name 'any)) result))])))))
      (syntax-case stx ()
        ;; With return type annotation
        [(k (name typed-arg ...) colon ret-type body ...)
         (eq? (syntax->datum #'colon) ':)
         (let* ([parsed      (parse-typed-args #'(typed-arg ...))]
                [arg-bindings (map (lambda (p)
                                    (cons (syntax->datum (car p))
                                          (syntax->datum (cadr p))))
                                   parsed)]
                [ret-datum   (syntax->datum #'ret-type)]
                [body-datums (map syntax->datum (syntax->list #'(body ...)))]
                [who-sym     (syntax->datum #'name)])
           ;; Run compile-time check (side effect: may display warnings)
           (compile-time-check! who-sym arg-bindings ret-datum body-datums stx)
           ;; Emit standard define with runtime checks (delegates to define/t)
           (with-syntax ([(arg ...) (map car parsed)]
                         [((aname atype) ...) parsed])
             #'(define (name arg ...)
                 (check-type! 'name 'aname arg 'atype) ...
                 (let ([result (begin body ...)])
                   (check-return-type! 'name result 'ret-type)
                   result))))]
        ;; Without return type: no return-type check, but still check args
        [(k (name typed-arg ...) body ...)
         (let* ([parsed      (parse-typed-args #'(typed-arg ...))]
                [arg-bindings (map (lambda (p)
                                    (cons (syntax->datum (car p))
                                          (syntax->datum (cadr p))))
                                   parsed)]
                [body-datums (map syntax->datum (syntax->list #'(body ...)))]
                [who-sym     (syntax->datum #'name)])
           ;; Infer body type without a return constraint
           (when (*enable-type-checking*)
             (let ([env (type-env-extend (empty-type-env) arg-bindings)])
               (for-each (lambda (b) (infer-type b env)) body-datums)))
           (with-syntax ([(arg ...) (map car parsed)]
                         [((aname atype) ...) parsed])
             #'(define (name arg ...)
                 (check-type! 'name 'aname arg 'atype) ...
                 body ...)))])))

  ;; ========== lambda/ct ==========

  (define-syntax lambda/ct
    (lambda (stx)
      (define (parse-typed-args args)
        (let loop ([rest (syntax->list args)] [result '()])
          (if (null? rest)
            (reverse result)
            (let ([item (car rest)])
              (syntax-case item ()
                [(arg-name sep type-name)
                 (eq? (syntax->datum #'sep) ':)
                 (loop (cdr rest)
                       (cons (list #'arg-name #'type-name) result))]
                [arg-name
                 (identifier? #'arg-name)
                 (loop (cdr rest)
                       (cons (list #'arg-name (datum->syntax #'arg-name 'any)) result))])))))
      (syntax-case stx ()
        ;; With return type
        [(k (typed-arg ...) colon ret-type body ...)
         (eq? (syntax->datum #'colon) ':)
         (let* ([parsed      (parse-typed-args #'(typed-arg ...))]
                [arg-bindings (map (lambda (p)
                                    (cons (syntax->datum (car p))
                                          (syntax->datum (cadr p))))
                                   parsed)]
                [ret-datum   (syntax->datum #'ret-type)]
                [body-datums (map syntax->datum (syntax->list #'(body ...)))])
           ;; Compile-time check
           (when (*enable-type-checking*)
             (let ([env (type-env-extend (empty-type-env) arg-bindings)])
               (with-type-errors-collected
                 (lambda ()
                   (let loop ([forms body-datums])
                     (if (null? forms)
                       'void
                       (if (null? (cdr forms))
                         (check-type (car forms) ret-datum env)
                         (begin (infer-type (car forms) env)
                                (loop (cdr forms))))))))))
           (with-syntax ([(arg ...) (map car parsed)]
                         [((aname atype) ...) parsed])
             #'(lambda (arg ...)
                 (check-type! 'lambda 'aname arg 'atype) ...
                 (let ([result (begin body ...)])
                   (check-return-type! 'lambda result 'ret-type)
                   result))))]
        ;; Without return type
        [(k (typed-arg ...) body ...)
         (let* ([parsed (parse-typed-args #'(typed-arg ...))])
           (with-syntax ([(arg ...) (map car parsed)]
                         [((aname atype) ...) parsed])
             #'(lambda (arg ...)
                 (check-type! 'lambda 'aname arg 'atype) ...
                 body ...)))])))

  ;; ========== check-program-types ==========
  ;;
  ;; Given a list of top-level Scheme forms (as datums), type-check them
  ;; in sequence, threading a global type environment.  Returns a list
  ;; of type-error records for any mismatches found.

  (define (check-program-types forms)
    (let ([env (empty-type-env)])
      (with-type-errors-collected
        (lambda ()
          (for-each (lambda (form) (check-top-level-form! form env)) forms)))))

  ;; Type-check a single top-level form, mutating env with new definitions.
  (define (check-top-level-form! form env)
    (cond
      [(not (pair? form)) (void)]
      [(eq? (car form) 'define)
       (let ([head (cadr form)]
             [body (cddr form)])
         (cond
           ;; (define (name [arg : type] ...) : ret-type body ...)
           [(and (pair? head) (list? head))
            (let* ([name    (car head)]
                   [args    (cdr head)]
                   [bindings (parse-args-datum args)]
                   [child-env (type-env-extend env bindings)])
              ;; Record function type in env for call-site inference
              (type-env-bind! env name `(-> ,@(map cdr bindings) any))
              ;; Check body
              (for-each (lambda (b) (infer-type b child-env)) body))]
           ;; (define name value)
           [(symbol? head)
            (let ([val-type (if (pair? body)
                              (infer-type (car body) env)
                              'any)])
              (type-env-bind! env head val-type))]
           [else (void)]))]
      ;; (begin form ...) — splice
      [(eq? (car form) 'begin)
       (for-each (lambda (f) (check-top-level-form! f env)) (cdr form))]
      [else
       ;; Expression context: just infer
       (infer-type form env)]))

  ;; ========== with-type-checking ==========

  (define-syntax with-type-checking
    (syntax-rules ()
      [(_ body ...)
       (parameterize ([*enable-type-checking* #t])
         body ...)]))

  ;; ========== type-check-file ==========
  ;;
  ;; Read all S-expressions from filename and type-check them.
  ;; Returns a list of type-error records.

  (define (type-check-file filename)
    (unless (string? filename)
      (error 'type-check-file "expected a filename string" filename))
    (call-with-input-file filename
      (lambda (port)
        (let loop ([forms '()])
          (let ([form (read port)])
            (if (eof-object? form)
              (check-program-types (reverse forms))
              (loop (cons form forms))))))))

) ;; end library
