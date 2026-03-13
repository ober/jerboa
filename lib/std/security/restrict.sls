#!chezscheme
;;; (std security restrict) — Restricted evaluation environments
;;;
;;; Track 29 (continued): Evaluate code in sandboxed environments with
;;; limited bindings. No access to FFI, file I/O, or system calls.

(library (std security restrict)
  (export
    make-restricted-environment
    restricted-eval
    restricted-eval-string
    safe-bindings)

  (import (chezscheme))

  ;; ========== Safe Binding Set ==========
  ;; These are the only bindings available in restricted environments.
  ;; No FFI, no file I/O, no system, no eval, no load.

  (define safe-bindings
    '(;; Core forms (always available as syntax)
      ;; lambda, if, begin, define, set!, quote, let, let*, letrec, cond, case,
      ;; and, or, when, unless, do

      ;; Arithmetic
      + - * / = < > <= >= zero? positive? negative?
      add1 sub1 abs min max gcd lcm
      quotient remainder modulo
      expt sqrt floor ceiling truncate round
      number? integer? rational? real? complex?
      exact? inexact? exact->inexact inexact->exact
      number->string string->number

      ;; Comparison
      eq? eqv? equal? not

      ;; Booleans
      boolean? boolean=?

      ;; Pairs and lists
      cons car cdr pair? null? list? list
      caar cadr cdar cddr
      length append reverse map for-each
      filter fold-left fold-right
      assoc assv assq member memv memq
      list-ref list-tail
      exists for-all

      ;; Strings
      string? string-length string-ref string-append
      string=? string<? string>? string<=? string>=?
      substring string->list list->string
      string-upcase string-downcase
      string-copy number->string symbol->string
      string->number string->symbol

      ;; Characters
      char? char=? char<? char>?
      char-alphabetic? char-numeric? char-whitespace?
      char->integer integer->char char-upcase char-downcase

      ;; Vectors
      vector? vector vector-length vector-ref vector-set!
      make-vector vector->list list->vector vector-copy
      vector-fill! vector-map vector-for-each

      ;; Bytevectors
      bytevector? make-bytevector bytevector-length
      bytevector-u8-ref bytevector-u8-set!
      bytevector-copy bytevector-copy!
      utf8->string string->utf8

      ;; Symbols
      symbol? symbol->string string->symbol gensym

      ;; Control
      apply call-with-values values
      call-with-current-continuation call/cc
      dynamic-wind

      ;; Hashtables (safe operations only)
      make-hashtable make-eq-hashtable
      hashtable? hashtable-ref hashtable-set!
      hashtable-delete! hashtable-contains?
      hashtable-keys hashtable-entries
      hashtable-size
      equal-hash string-hash symbol-hash

      ;; I/O (string ports only — no file I/O)
      open-input-string open-output-string
      get-output-string
      read write display newline
      port? input-port? output-port?
      eof-object? eof-object

      ;; Errors
      error assert assertion-violation
      condition? message-condition? condition-message
      guard

      ;; Misc
      void gensym
      sort
      format
      ))

  ;; ========== Dangerous Bindings to Remove ==========
  ;; Explicitly block these — they provide FFI, file I/O, code loading,
  ;; process execution, and other capabilities that break sandboxing.

  (define dangerous-bindings
    '(;; Code loading and evaluation
      load load-shared-object load-program load-library
      eval eval-when compile compile-file compile-port
      compile-library compile-program compile-whole-program
      compile-to-port expand include
      library-directories library-extensions
      source-directories

      ;; FFI — must be blocked to prevent arbitrary C calls
      foreign-procedure foreign-callable foreign-sizeof
      foreign-alloc foreign-free foreign-ref foreign-set!
      foreign-entry? foreign-entry
      ftype-sizeof ftype-ref ftype-set! ftype-pointer-address
      ftype-pointer-null? ftype-pointer-ftype make-ftype-pointer
      define-ftype lock-object unlock-object
      load-shared-object

      ;; Process execution
      system process

      ;; File I/O
      open-file-input-port open-file-output-port
      open-file-input/output-port
      open-input-file open-output-file
      call-with-input-file call-with-output-file
      with-input-from-file with-output-to-file
      file-exists? delete-file rename-file
      directory-list make-directory delete-directory
      file-regular? file-directory? file-symbolic-link?
      get-mode chmod

      ;; Environment manipulation
      putenv getenv
      scheme-environment interaction-environment
      copy-environment environment environment-symbols
      define-top-level-value set-top-level-value!
      top-level-value top-level-bound?

      ;; Module system manipulation
      import import-only

      ;; Ports to filesystem
      current-directory
      standard-input-port standard-output-port standard-error-port
      console-input-port console-output-port console-error-port
      transcript-on transcript-off

      ;; Low-level and unsafe
      #%$top-level-value inspect inspect/object
      sc-expand syntax->datum datum->syntax
      pretty-print trace-define trace-lambda
      with-profile-tracker profile-dump-html

      ;; Exit
      exit scheme-start

      ;; Thread creation (could be used to escape)
      fork-thread make-thread thread-start!))

  ;; ========== Restricted Environment ==========

  (define (make-restricted-environment . extra-bindings)
    ;; Create an environment with ONLY safe bindings.
    ;; Strategy: copy the scheme-environment (to get syntax/macros),
    ;; then rebind all dangerous symbols to error-raising procedures.
    (let ([restricted (copy-environment (scheme-environment) #t)]
          [safe-set (make-eq-hashtable)])
      ;; Build lookup table of safe bindings
      (for-each (lambda (name) (hashtable-set! safe-set name #t)) safe-bindings)
      ;; Remove explicitly dangerous bindings
      (for-each
        (lambda (name)
          (guard (e [#t (void)])
            (when (top-level-bound? name restricted)
              (define-top-level-value name
                (lambda args
                  (error 'restricted-eval
                    (format "~a is not available in restricted environment" name)))
                restricted))))
        dangerous-bindings)
      ;; Also scan all symbols and block anything not in safe-bindings
      ;; that looks like a procedure (conservative: block unknown procedures)
      (guard (e [#t (void)])
        (for-each
          (lambda (sym)
            (unless (hashtable-ref safe-set sym #f)
              (guard (e2 [#t (void)])
                (when (and (top-level-bound? sym restricted)
                           (procedure? (top-level-value sym restricted)))
                  (define-top-level-value sym
                    (lambda args
                      (error 'restricted-eval
                        (format "~a is not available in restricted environment" sym)))
                    restricted)))))
          (environment-symbols restricted)))
      ;; Block syntax keywords that can't be caught by procedure scanning
      ;; (foreign-procedure, etc. are special forms, not procedures)
      (for-each
        (lambda (name)
          (guard (e [#t (void)])
            (define-top-level-value name
              (lambda args
                (error 'restricted-eval
                  (format "~a is not available in restricted environment" name)))
              restricted)))
        '(foreign-procedure foreign-callable foreign-entry
          foreign-entry? ftype-sizeof ftype-ref ftype-set!
          define-ftype make-ftype-pointer
          load-shared-object
          import import-only library
          meta-cond eval-when))
      ;; Re-add safe bindings (in case we accidentally blocked any)
      (for-each
        (lambda (name)
          (guard (e [#t (void)])
            (when (top-level-bound? name (scheme-environment))
              (define-top-level-value name
                (top-level-value name (scheme-environment))
                restricted))))
        safe-bindings)
      ;; Add any extra bindings
      (when (pair? extra-bindings)
        (for-each
          (lambda (binding)
            (when (and (pair? binding) (symbol? (car binding)))
              (define-top-level-value (car binding) (cdr binding) restricted)))
          (car extra-bindings)))
      restricted))

  ;; ========== Restricted Eval ==========

  (define (restricted-eval expr . rest)
    ;; Evaluate an expression in a restricted environment.
    (let ([env (if (pair? rest) (car rest) (make-restricted-environment))])
      (eval expr env)))

  (define (restricted-eval-string str . rest)
    ;; Parse and evaluate a string in a restricted environment.
    (let ([env (if (pair? rest) (car rest) (make-restricted-environment))]
          [expr (call-with-port (open-input-string str) read)])
      (eval expr env)))

  ) ;; end library
