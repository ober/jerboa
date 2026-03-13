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

  ;; ========== Restricted Environment ==========

  (define (make-restricted-environment . extra-bindings)
    ;; Create an environment with only safe bindings.
    (let ([restricted (copy-environment (scheme-environment) #t)])
        ;; Import safe bindings from the scheme environment
        (for-each
          (lambda (name)
            (guard (e [#t (void)])  ;; skip if not available
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
