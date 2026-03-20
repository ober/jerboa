#!chezscheme
;;; (std repl middleware) -- Extensible REPL Middleware System
;;;
;;; Allows users to extend the REPL with:
;;;   - Custom commands (register-repl-command!)
;;;   - Custom printers (register-repl-printer!)
;;;   - Input transformers (register-input-transformer!)
;;;   - Eval hooks (register-eval-hook!)
;;;
;;; Commands are dispatched by name (,mycommand args).
;;; Printers are tried in order for non-standard value types.
;;; Input transformers can rewrite expressions before eval.
;;; Eval hooks run before/after each evaluation.
;;;
;;; Usage:
;;;   (import (std repl middleware))
;;;
;;;   ;; Register a custom command
;;;   (register-repl-command! "greet"
;;;     "Say hello"
;;;     (lambda (args env cfg)
;;;       (display "Hello, ")
;;;       (display args)
;;;       (newline)))
;;;
;;;   ;; Register a custom printer for your record type
;;;   (register-repl-printer!
;;;     (lambda (val port)
;;;       (and (my-record? val)
;;;            (begin (display "#<my-record ...>" port) #t))))
;;;
;;;   ;; Register an input transformer
;;;   (register-input-transformer!
;;;     (lambda (str)
;;;       ;; Transform !cmd to (shell "cmd")
;;;       (if (and (> (string-length str) 0)
;;;                (char=? (string-ref str 0) #\!))
;;;         (string-append "(system \"" (substring str 1 (string-length str)) "\")")
;;;         str)))

(library (std repl middleware)
  (export
    ;; Command registration
    register-repl-command!
    unregister-repl-command!
    repl-command-registered?
    list-repl-commands
    dispatch-custom-command

    ;; Printer registration
    register-repl-printer!
    try-custom-printers

    ;; Input transformers
    register-input-transformer!
    apply-input-transformers

    ;; Eval hooks
    register-eval-hook!
    run-pre-eval-hooks
    run-post-eval-hooks

    ;; Startup hooks
    register-startup-hook!
    run-startup-hooks

    ;; Prompt customization
    register-prompt-fn!
    compute-custom-prompt)

  (import (chezscheme))

  ;; ========== Custom Commands ==========
  ;; Each entry: (name doc-string handler)
  ;; handler: (lambda (args-string env cfg) ...)

  (define *custom-commands* '())

  (define (register-repl-command! name doc handler)
    (let ([existing (assoc name *custom-commands*)])
      (if existing
        ;; Replace
        (set! *custom-commands*
          (cons (list name doc handler)
                (filter (lambda (e) (not (string=? (car e) name)))
                        *custom-commands*)))
        (set! *custom-commands*
          (cons (list name doc handler) *custom-commands*)))))

  (define (unregister-repl-command! name)
    (set! *custom-commands*
      (filter (lambda (e) (not (string=? (car e) name)))
              *custom-commands*)))

  (define (repl-command-registered? name)
    (and (assoc name *custom-commands*) #t))

  (define (list-repl-commands)
    ;; Returns list of (name . doc-string) pairs
    (map (lambda (e) (cons (car e) (cadr e))) *custom-commands*))

  (define (dispatch-custom-command name args env cfg)
    (let ([entry (assoc name *custom-commands*)])
      (if entry
        (begin ((caddr entry) args env cfg) #t)
        #f)))

  ;; assoc from (chezscheme) uses equal? which handles strings

  ;; ========== Custom Printers ==========
  ;; Each printer: (lambda (val port) -> #t if handled, #f if not)

  (define *custom-printers* '())

  (define (register-repl-printer! printer)
    (set! *custom-printers* (cons printer *custom-printers*)))

  (define (try-custom-printers val port)
    ;; Try each printer in order. Returns #t if one handled it.
    (let loop ([printers *custom-printers*])
      (cond
        [(null? printers) #f]
        [(guard (exn [#t #f])
           ((car printers) val port))
         #t]
        [else (loop (cdr printers))])))

  ;; ========== Input Transformers ==========
  ;; Each transformer: (lambda (str) -> str)

  (define *input-transformers* '())

  (define (register-input-transformer! transformer)
    (set! *input-transformers* (cons transformer *input-transformers*)))

  (define (apply-input-transformers str)
    ;; Apply all transformers in registration order (reversed since we cons)
    (let loop ([transformers (reverse *input-transformers*)] [s str])
      (if (null? transformers)
        s
        (loop (cdr transformers)
              (guard (exn [#t s])
                ((car transformers) s))))))

  ;; ========== Eval Hooks ==========
  ;; pre-eval: (lambda (expr-string env) -> void)
  ;; post-eval: (lambda (expr-string result env) -> void)

  (define *pre-eval-hooks* '())
  (define *post-eval-hooks* '())

  (define (register-eval-hook! type hook)
    (case type
      [(pre)  (set! *pre-eval-hooks* (cons hook *pre-eval-hooks*))]
      [(post) (set! *post-eval-hooks* (cons hook *post-eval-hooks*))]
      [else (error 'register-eval-hook! "type must be 'pre or 'post" type)]))

  (define (run-pre-eval-hooks expr-str env)
    (for-each (lambda (h)
                (guard (exn [#t (void)])
                  (h expr-str env)))
              *pre-eval-hooks*))

  (define (run-post-eval-hooks expr-str result env)
    (for-each (lambda (h)
                (guard (exn [#t (void)])
                  (h expr-str result env)))
              *post-eval-hooks*))

  ;; ========== Startup Hooks ==========
  (define *startup-hooks* '())

  (define (register-startup-hook! hook)
    (set! *startup-hooks* (cons hook *startup-hooks*)))

  (define (run-startup-hooks env cfg)
    (for-each (lambda (h)
                (guard (exn [#t (void)])
                  (h env cfg)))
              (reverse *startup-hooks*)))

  ;; ========== Prompt Customization ==========
  (define *prompt-fn* #f)

  (define (register-prompt-fn! fn)
    ;; fn: (lambda (env cfg) -> string)
    (set! *prompt-fn* fn))

  (define (compute-custom-prompt env cfg)
    (if *prompt-fn*
      (guard (exn [#t #f])
        (*prompt-fn* env cfg))
      #f))

) ;; end library
