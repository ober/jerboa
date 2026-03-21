#!chezscheme
;;; (std security restrict) — Restricted evaluation environments
;;;
;;; HARDENED: Allowlist-only approach. Creates an environment via
;;; (environment '(only (chezscheme) ...)) containing ONLY approved
;;; bindings. No blocklist — nothing exists unless we put it there.
;;; Even future Chez Scheme additions cannot leak into the sandbox.

(library (std security restrict)
  (export
    make-restricted-environment
    restricted-eval
    restricted-eval-string
    safe-bindings)

  (import (chezscheme)
          (jerboa reader))

  ;; ========== Safe Binding Set ==========
  ;; These are the ONLY bindings available in restricted environments.
  ;; Allowlist approach: nothing else exists.

  (define safe-bindings
    '(;; Core syntax forms
      lambda if begin define set! quote
      let let* letrec letrec*
      cond case and or when unless do
      define-syntax syntax-rules
      quasiquote unquote unquote-splicing
      let-values

      ;; Arithmetic
      + - * / = < > <= >= zero? positive? negative?
      add1 sub1 abs min max gcd lcm
      quotient remainder modulo
      expt sqrt floor ceiling truncate round
      number? integer? rational? real? complex?
      exact? inexact? exact->inexact inexact->exact
      number->string string->number
      bitwise-and bitwise-ior bitwise-xor bitwise-not
      bitwise-arithmetic-shift-left bitwise-arithmetic-shift-right

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
      ;; HARDENED: gensym removed — leaks runtime state via monotonic counter,
      ;; and string->symbol can cause unbounded symbol table growth.
      symbol? symbol->string string->symbol

      ;; Control (no call/cc — can escape dynamic scope)
      apply call-with-values values
      dynamic-wind

      ;; Hashtables (safe operations only)
      make-hashtable make-eq-hashtable
      hashtable? hashtable-ref hashtable-set!
      hashtable-delete! hashtable-contains?
      hashtable-keys hashtable-entries
      hashtable-size
      equal-hash string-hash symbol-hash

      ;; I/O (string ports only — no file I/O)
      ;; HARDENED: bare `read` removed — it supports #. read-eval.
      ;; Use jerboa-read (added as extra binding) for safe parsing.
      open-input-string open-output-string
      get-output-string
      write display newline
      port? input-port? output-port?
      eof-object? eof-object
      read-char peek-char write-char

      ;; Errors
      error assert assertion-violation
      condition? message-condition? condition-message
      guard with-exception-handler raise

      ;; Misc
      void
      sort
      format
      ))

  ;; ========== Restricted Environment ==========

  (define (make-restricted-environment . extra-bindings)
    ;; ALLOWLIST approach: use (environment '(only (chezscheme) ...))
    ;; to create an environment with ONLY the safe bindings.
    ;; Then copy to make mutable for extra bindings.
    (let* ([import-spec `(only (chezscheme) ,@safe-bindings)]
           [base (environment import-spec)]
           [restricted (copy-environment base #t)])
      ;; Add jerboa-read as a safe replacement for bare read.
      ;; It has depth limits and no #. read-eval support.
      (define-top-level-value 'read jerboa-read restricted)
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
    ;; HARDENED: Uses jerboa-read (depth-limited) instead of bare read.
    (let ([env (if (pair? rest) (car rest) (make-restricted-environment))]
          [expr (call-with-port (open-input-string str) jerboa-read)])
      (eval expr env)))

  ) ;; end library
