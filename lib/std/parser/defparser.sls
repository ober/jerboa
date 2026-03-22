#!chezscheme
;;; (std parser defparser) — Parser definition macro
;;;
;;; Provides `defparser` for defining recursive-descent parsers over
;;; token streams produced by (std parser deflexer).
;;; Patterns: seq, alt, rep, rep1, opt, and literal token-type symbols.

(library (std parser defparser)
  (export defparser define-rule parse-tokens
          parse-error? parse-error-message parse-error-token)

  (import (chezscheme)
          (std parser deflexer))

  ;; -----------------------------------------------------------------
  ;; Parse error record
  ;; -----------------------------------------------------------------

  (define-record-type parse-error
    (fields (immutable message parse-error-message)
            (immutable token   parse-error-token))
    (protocol (lambda (new)
                (lambda (message token)
                  (new message token)))))

  ;; -----------------------------------------------------------------
  ;; Pattern matching engine
  ;;
  ;; A pattern matcher takes a token list and a rule-lookup procedure
  ;; and returns (values matched-value remaining-tokens) on success
  ;; or #f on failure.
  ;; -----------------------------------------------------------------

  ;; Match a single token by type symbol.
  ;; Returns (values token remaining) or #f.
  (define (match-token-type type tokens)
    (if (and (pair? tokens)
             (eq? (token-type (car tokens)) type))
        (values (car tokens) (cdr tokens))
        #f))

  ;; Compile a pattern form into a matcher procedure.
  ;; A matcher: (tokens rule-lookup) -> (values result remaining) or #f
  ;;
  ;; rule-lookup: symbol -> matcher-procedure

  (define (compile-pattern pat rule-lookup)
    (cond
      ;; (seq p1 p2 ...)
      [(and (pair? pat) (eq? (car pat) 'seq))
       (let ([sub-matchers (map (lambda (p) (compile-pattern p rule-lookup))
                                (cdr pat))])
         (lambda (tokens)
           (let loop ([ms sub-matchers] [toks tokens] [results '()])
             (if (null? ms)
                 (values (reverse results) toks)
                 (let-values ([(ok? val rest) (try-matcher (car ms) toks)])
                   (if ok?
                       (loop (cdr ms) rest (cons val results))
                       #f))))))]

      ;; (alt p1 p2 ...)
      [(and (pair? pat) (eq? (car pat) 'alt))
       (let ([sub-matchers (map (lambda (p) (compile-pattern p rule-lookup))
                                (cdr pat))])
         (lambda (tokens)
           (let loop ([ms sub-matchers])
             (if (null? ms)
                 #f
                 (let-values ([(ok? val rest) (try-matcher (car ms) tokens)])
                   (if ok?
                       (values val rest)
                       (loop (cdr ms))))))))]

      ;; (rep p) — zero or more
      [(and (pair? pat) (eq? (car pat) 'rep))
       (let ([sub (compile-pattern (cadr pat) rule-lookup)])
         (lambda (tokens)
           (let loop ([toks tokens] [results '()])
             (let-values ([(ok? val rest) (try-matcher sub toks)])
               (if ok?
                   (loop rest (cons val results))
                   (values (reverse results) toks))))))]

      ;; (rep1 p) — one or more
      [(and (pair? pat) (eq? (car pat) 'rep1))
       (let ([sub (compile-pattern (cadr pat) rule-lookup)])
         (lambda (tokens)
           (let-values ([(ok? val rest) (try-matcher sub tokens)])
             (if ok?
                 (let loop ([toks rest] [results (list val)])
                   (let-values ([(ok2? val2 rest2) (try-matcher sub toks)])
                     (if ok2?
                         (loop rest2 (cons val2 results))
                         (values (reverse results) toks))))
                 #f))))]

      ;; (opt p) — optional
      [(and (pair? pat) (eq? (car pat) 'opt))
       (let ([sub (compile-pattern (cadr pat) rule-lookup)])
         (lambda (tokens)
           (let-values ([(ok? val rest) (try-matcher sub tokens)])
             (if ok?
                 (values val rest)
                 (values #f tokens)))))]

      ;; A symbol — either a token type or a rule reference
      [(symbol? pat)
       (lambda (tokens)
         ;; First try as a rule reference
         (let ([rule (rule-lookup pat)])
           (if rule
               (rule tokens)
               ;; Otherwise treat as token type
               (if (and (pair? tokens)
                        (eq? (token-type (car tokens)) pat))
                   (values (car tokens) (cdr tokens))
                   #f))))]

      [else
       (error 'compile-pattern "unknown pattern form" pat)]))

  ;; Helper: call a matcher and return 3 values (ok? value remaining)
  ;; to make it easy to use with let-values and check success.
  (define (try-matcher matcher tokens)
    (call/cc
      (lambda (escape)
        (call-with-values
          (lambda ()
            (let ([r (matcher tokens)])
              (if r
                  ;; r came from a multi-value return via values
                  ;; but if matcher returned #f, we fail
                  (error 'try-matcher "unreachable")
                  (escape #f #f tokens))))
          (lambda args
            (escape #f #f tokens))))))

  ;; Actually, let's use a simpler approach with a sentinel for failure.
  ;; Matchers return (cons value remaining) on success, or #f on failure.

  ;; Re-do the pattern compilation with single-return convention:
  ;; matcher: tokens -> (cons value remaining) or #f

  (define (compile-pat pat rule-lookup)
    (cond
      ;; (seq p1 p2 ...)
      [(and (pair? pat) (eq? (car pat) 'seq))
       (let ([subs (map (lambda (p) (compile-pat p rule-lookup)) (cdr pat))])
         (lambda (tokens)
           (let loop ([ms subs] [toks tokens] [results '()])
             (if (null? ms)
                 (cons (reverse results) toks)
                 (let ([r ((car ms) toks)])
                   (and r
                        (loop (cdr ms) (cdr r) (cons (car r) results))))))))]

      ;; (alt p1 p2 ...)
      [(and (pair? pat) (eq? (car pat) 'alt))
       (let ([subs (map (lambda (p) (compile-pat p rule-lookup)) (cdr pat))])
         (lambda (tokens)
           (let loop ([ms subs])
             (if (null? ms)
                 #f
                 (or ((car ms) tokens)
                     (loop (cdr ms)))))))]

      ;; (rep p) — zero or more
      [(and (pair? pat) (eq? (car pat) 'rep))
       (let ([sub (compile-pat (cadr pat) rule-lookup)])
         (lambda (tokens)
           (let loop ([toks tokens] [results '()])
             (let ([r (sub toks)])
               (if r
                   (loop (cdr r) (cons (car r) results))
                   (cons (reverse results) toks))))))]

      ;; (rep1 p) — one or more
      [(and (pair? pat) (eq? (car pat) 'rep1))
       (let ([sub (compile-pat (cadr pat) rule-lookup)])
         (lambda (tokens)
           (let ([first (sub tokens)])
             (and first
                  (let loop ([toks (cdr first)] [results (list (car first))])
                    (let ([r (sub toks)])
                      (if r
                          (loop (cdr r) (cons (car r) results))
                          (cons (reverse results) toks))))))))]

      ;; (opt p) — optional
      [(and (pair? pat) (eq? (car pat) 'opt))
       (let ([sub (compile-pat (cadr pat) rule-lookup)])
         (lambda (tokens)
           (let ([r (sub tokens)])
             (if r
                 r
                 (cons #f tokens)))))]

      ;; A symbol — rule reference or token type
      [(symbol? pat)
       (lambda (tokens)
         (let ([rule (rule-lookup pat)])
           (if rule
               (rule tokens)
               ;; Token type match
               (and (pair? tokens)
                    (eq? (token-type (car tokens)) pat)
                    (cons (car tokens) (cdr tokens))))))]

      [else
       (error 'compile-pat "unknown pattern form" pat)]))

  ;; -----------------------------------------------------------------
  ;; Parser runtime
  ;; -----------------------------------------------------------------

  ;; A parser is a hashtable of rule-name -> (matcher . action)
  ;; where action is (lambda (matched) -> result)

  (define (make-parser-table)
    (make-hashtable symbol-hash eq?))

  ;; Add a rule to a parser table.
  ;; pattern and action-proc are already evaluated.
  (define (parser-add-rule! table name pattern action-proc)
    (hashtable-set! table name (cons pattern action-proc)))

  ;; Parse a token list starting from a named rule.
  (define (run-parser table start-rule tokens)
    (let ([rule-lookup
           (lambda (name)
             (let ([entry (hashtable-ref table name #f)])
               (if entry
                   (let ([pat (car entry)]
                         [action (cdr entry)])
                     (lambda (toks)
                       (let ([r (pat toks)])
                         (if r
                             (cons (action (car r)) (cdr r))
                             #f))))
                   #f)))])
      ;; Now compile all patterns with the rule-lookup
      ;; We need to compile lazily since rules can be mutually recursive
      ;; So rule-lookup creates matchers on demand
      (let ([entry (hashtable-ref table start-rule #f)])
        (if entry
            (let* ([pat (car entry)]
                   [action (cdr entry)]
                   [r (pat tokens)])
              (if r
                  (action (car r))
                  (make-parse-error
                    (format "parse failed at rule ~a" start-rule)
                    (if (pair? tokens) (car tokens) #f))))
            (error 'run-parser "unknown start rule" start-rule)))))

  ;; parse-tokens: convenience entry point
  ;; parser is (cons table start-rule-symbol)
  (define (parse-tokens parser tokens)
    (let ([table (car parser)]
          [start (cdr parser)])
      (run-parser table start tokens)))

  ;; -----------------------------------------------------------------
  ;; defparser and define-rule macros
  ;; -----------------------------------------------------------------

  ;; Build a compiled pattern from a quoted pattern description.
  ;; This must be done at runtime because rule-lookup needs the table.
  (define (build-matcher pattern-desc rule-lookup)
    (compile-pat pattern-desc rule-lookup))

  ;; Runtime: create a parser from a list of (name pattern-desc action) triples.
  (define (create-parser rule-specs start-rule)
    (let ([table (make-parser-table)])
      ;; Two passes: first install placeholders, then compile patterns.
      ;; This handles mutual recursion.
      (let ([rule-lookup
             (lambda (name)
               (let ([entry (hashtable-ref table name #f)])
                 (and entry
                      (lambda (toks)
                        (let ([r ((car entry) toks)])
                          (if r
                              (cons ((cdr entry) (car r)) (cdr r))
                              #f))))))])
        ;; Install each rule
        (for-each
          (lambda (spec)
            (let ([name (car spec)]
                  [pat-desc (cadr spec)]
                  [action (caddr spec)])
              (let ([matcher (build-matcher pat-desc rule-lookup)])
                (hashtable-set! table name (cons matcher action)))))
          rule-specs))
      (cons table start-rule)))

  ;; Helper to convert pattern syntax to a quoted description at expand time
  (define-syntax quote-pattern
    (syntax-rules (seq alt rep rep1 opt)
      [(_ (seq p ...))
       (list 'seq (quote-pattern p) ...)]
      [(_ (alt p ...))
       (list 'alt (quote-pattern p) ...)]
      [(_ (rep p))
       (list 'rep (quote-pattern p))]
      [(_ (rep1 p))
       (list 'rep1 (quote-pattern p))]
      [(_ (opt p))
       (list 'opt (quote-pattern p))]
      [(_ sym)
       'sym]))

  ;; (defparser name
  ;;   (rule-name pattern action-expr)
  ;;   ...)
  ;; First rule is the start rule.
  (define-syntax defparser
    (syntax-rules ()
      [(_ name (rule-name1 pattern1 action1) (rule-name2 pattern2 action2) ...)
       (define name
         (create-parser
           (list
             (list 'rule-name1 (quote-pattern pattern1) (lambda (matched) action1))
             (list 'rule-name2 (quote-pattern pattern2) (lambda (matched) action2))
             ...)
           'rule-name1))]))

  ;; define-rule: add a rule to an existing parser at runtime
  (define-syntax define-rule
    (syntax-rules ()
      [(_ parser-var rule-name pattern action-expr)
       (let* ([p parser-var]
              [table (car p)]
              [rule-lookup
               (lambda (name)
                 (let ([entry (hashtable-ref table name #f)])
                   (and entry
                        (lambda (toks)
                          (let ([r ((car entry) toks)])
                            (if r
                                (cons ((cdr entry) (car r)) (cdr r))
                                #f))))))]
              [matcher (build-matcher (quote-pattern pattern) rule-lookup)])
         (hashtable-set! table 'rule-name
                         (cons matcher (lambda (matched) action-expr))))]))

) ;; end library
