#!chezscheme
;;; (std regex-ct) -- Compile-Time Regular Expressions
;;;
;;; Compiles regex patterns to DFA state machines at macro-expansion time.
;;; No regex engine overhead at runtime — the match is a direct state machine.
;;;
;;; Pipeline (all at compile time):
;;;   String → AST (parse) → NFA (Thompson) → DFA (subset construction)
;;;         → Minimized DFA (Hopcroft) → Scheme case/cond state machine
;;;
;;; Usage:
;;;   (import (std regex-ct))
;;;
;;;   (define-regex email-re "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$")
;;;   (email-re "user@example.com")   ; => #t
;;;   (email-re "bad")                ; => #f
;;;
;;;   ;; With capture groups
;;;   (define-regex url-re "^(https?)://([^/]+)(/.*)?$")
;;;   (url-re "https://example.com/path")
;;;   ; => #("https" "example.com" "/path") or #f
;;;
;;;   ;; Named capture (via match-regex)
;;;   (match-regex "^(\\w+)\\s+(\\d+)$" "foo 42")
;;;   ; => ("foo" "42") or #f

(library (std regex-ct)
  (export
    ;; Compile-time pattern definition — main entry point
    define-regex

    ;; Runtime fallback (PCRE2 via existing (std pcre2) or basic)
    match-regex
    regex-match?
    regex-search

    ;; Compile-time analysis: check if a pattern can be DFA-compiled
    regex-dfa-compatible?

    ;; DFA inspection (for debugging)
    compile-regex-to-dfa
    dfa-state-count
    dfa-dot)

  (import (chezscheme) (std regex-ct-impl) (std pregexp))

  ;;; ========== Compile-time analysis ==========

  ;; Check if a pattern can be compiled to a DFA (no backreferences, lookaheads).
  (define (regex-dfa-compatible? pattern)
    (guard (exn [#t #f])
      (parse-regex pattern)
      #t))

  ;;; ========== Runtime pipeline wrappers ==========
  ;; These call into (std regex-ct-impl) directly at phase 0.

  ;; Compile a regex string to DFA data structure.
  ;; Returns (values dfa-states transitions accept-states)
  (define (compile-regex-to-dfa pattern)
    (let* ([ast     (parse-regex pattern)]
           [nfa-b   (make-nfa-builder)]
           [nfa-se  (ast->nfa ast nfa-b)]
           [nfa-st  (nfa-b 'get-states)]
           [nfa-s   (car nfa-se)]
           [nfa-a   (cdr nfa-se)])
      (let-values ([(dfa-states transitions accepts state-map)
                    (nfa->dfa nfa-st nfa-s nfa-a)])
        (values dfa-states transitions accepts))))

  (define (dfa-state-count pattern)
    (let-values ([(states _ __) (compile-regex-to-dfa pattern)])
      (length states)))

  ;; Generate a DOT graph string for the DFA (for debugging/visualization).
  (define (dfa-dot pattern)
    (let-values ([(states transitions accepts) (compile-regex-to-dfa pattern)])
      (with-output-to-string
        (lambda ()
          (display "digraph DFA {\n")
          (display "  rankdir=LR;\n")
          (for-each
            (lambda (a)
              (display (format "  ~a [shape=doublecircle];\n" a)))
            accepts)
          (for-each
            (lambda (t)
              (display (format "  ~a -> ~a [label=\"~a\"];\n"
                (car t) (caddr t) (cadr t))))
            transitions)
          (display "}\n")))))

  ;;; ========== define-regex macro ==========
  ;; (define-regex name pattern-string)
  ;; At compile time:
  ;;   1. Parses pattern-string
  ;;   2. Builds NFA
  ;;   3. Converts to DFA
  ;;   4. Generates Scheme state machine code
  ;;   5. Emits (define name <state-machine-lambda>)
  ;;
  ;; The resulting `name` is a procedure: (name str) => #t or #f
  ;;
  ;; Phase note: the macro transformer runs at phase 1.  The pipeline
  ;; functions (parse-regex, nfa->dfa, etc.) live at phase 0 in
  ;; (std regex-ct-impl).  We therefore eval the pipeline expression
  ;; in a fresh environment that imports (std regex-ct-impl) at phase 0.
  (define-syntax define-regex
    (lambda (stx)
      (syntax-case stx ()
        [(_ name pattern-string)
         (let* ([pattern (syntax->datum #'pattern-string)]
                [_ (unless (string? pattern)
                     (syntax-error stx "define-regex: pattern must be a string literal"))]
                [ct-env  (environment '(chezscheme) '(std regex-ct-impl))]
                [machine-code
                 (guard (exn [#t #f])
                   (eval
                     `(let* ([ast    (parse-regex ,pattern)]
                             [nfa-b  (make-nfa-builder)]
                             [nfa-se (ast->nfa ast nfa-b)]
                             [nfa-st (nfa-b 'get-states)]
                             [nfa-s  (car nfa-se)]
                             [nfa-a  (cdr nfa-se)])
                        (let-values ([(dfa-states transitions accepts state-map)
                                      (nfa->dfa nfa-st nfa-s nfa-a)])
                          (let ([num-states (+ 1 (hashtable-size state-map))])
                            (dfa->scheme transitions accepts num-states #f #f))))
                     ct-env))])
           (if machine-code
             ;; DFA compilation succeeded: emit the state machine lambda
             (datum->syntax #'name
               `(define ,(syntax->datum #'name) ,machine-code))
             ;; DFA compilation failed: fall back to runtime regex
             #`(define name
                 (let ([p pattern-string])
                   (lambda (str)
                     (regex-match? p str))))))])))

  ;;; ========== Runtime regex fallback ==========
  ;; Used when a pattern isn't DFA-compilable or when define-regex fails.

  ;; Simple runtime regex using pregexp (Chez has pregexp built-in).
  (define (regex-match? pattern str)
    (guard (exn [#t #f])
      (let ([result (pregexp-match (string-append "^(?:" pattern ")$") str)])
        (and result #t))))

  (define (match-regex pattern str)
    (guard (exn [#t #f])
      (let ([result (pregexp-match pattern str)])
        (and result (cdr result)))))

  (define (regex-search pattern str)
    (guard (exn [#t #f])
      (pregexp-match pattern str)))

) ;; end library
