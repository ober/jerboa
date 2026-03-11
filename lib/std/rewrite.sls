#!chezscheme
;;; (std rewrite) -- Term rewriting system

(library (std rewrite)
  (export
    make-ruleset ruleset? ruleset-add! rewrite rewrite-once rewrite-all
    make-rule rule? rule-lhs rule-rhs rule-name
    normalize pattern-match pattern-vars substitute
    rewrite-fixed-point make-term term? term-head term-args)

  (import (chezscheme))

  ;;; ---- Terms ----
  ;; A term is either:
  ;;   - an atom (number, symbol, string, boolean, etc.)
  ;;   - a compound (non-empty list): (head . args)

  (define (make-term head . args)
    (cons head args))

  (define (term? x)
    (and (pair? x) (symbol? (car x))))

  (define (term-head t) (car t))
  (define (term-args t) (cdr t))

  ;;; ---- Pattern variables ----
  ;; Variables are symbols starting with ?

  (define (pattern-var? x)
    (and (symbol? x)
         (let ([s (symbol->string x)])
           (and (> (string-length s) 0)
                (char=? (string-ref s 0) #\?)))))

  (define (pattern-vars pattern)
    (cond
      [(pattern-var? pattern) (list pattern)]
      [(pair? pattern)
       (let loop ([items pattern] [vars '()])
         (cond
           [(null? items) (reverse vars)]
           [(pair? items)
            (loop (cdr items)
                  (append vars (pattern-vars (car items))))]
           [else
            (append vars (pattern-vars items))]))]
      [else '()]))

  ;;; ---- Pattern matching ----
  ;; Returns alist of (var . value) bindings, or #f on failure

  (define (pattern-match pattern value)
    (let loop ([pat pattern] [val value] [bindings '()])
      (cond
        ;; Variable: bind to value
        [(pattern-var? pat)
         (let ([existing (assq pat bindings)])
           (cond
             [(not existing)
              (cons (cons pat val) bindings)]
             [(equal? (cdr existing) val)
              bindings]
             [else #f]))]
        ;; Equal atoms
        [(and (not (pair? pat)) (not (pair? val)))
         (if (equal? pat val) bindings #f)]
        ;; Both pairs: recurse
        [(and (pair? pat) (pair? val))
         (let ([head-result (loop (car pat) (car val) bindings)])
           (if head-result
             (loop (cdr pat) (cdr val) head-result)
             #f))]
        ;; Null pattern matches null value
        [(and (null? pat) (null? val))
         bindings]
        ;; Mismatch
        [else #f])))

  ;;; ---- Substitution ----
  ;; Replace pattern variables in template using bindings

  (define (substitute template bindings)
    (cond
      [(pattern-var? template)
       (let ([binding (assq template bindings)])
         (if binding (cdr binding) template))]
      [(pair? template)
       (cons (substitute (car template) bindings)
             (substitute (cdr template) bindings))]
      [else template]))

  ;;; ---- Rules ----

  (define-record-type %rule
    (fields name lhs rhs)
    (protocol (lambda (new)
      (lambda (name lhs rhs) (new name lhs rhs)))))

  (define (make-rule name lhs rhs) (make-%rule name lhs rhs))
  (define (rule? x) (%rule? x))
  (define (rule-name r) (%rule-name r))
  (define (rule-lhs r) (%rule-lhs r))
  (define (rule-rhs r) (%rule-rhs r))

  ;;; ---- Ruleset ----

  (define-record-type %ruleset
    (fields (mutable rules))
    (protocol (lambda (new) (lambda () (new '())))))

  (define (make-ruleset) (make-%ruleset))
  (define (ruleset? x) (%ruleset? x))

  (define (ruleset-add! rs rule)
    (%ruleset-rules-set! rs (append (%ruleset-rules rs) (list rule))))

  ;;; ---- Apply one rule to a term (no recursion) ----

  (define (try-rule rule term)
    (let ([bindings (pattern-match (rule-lhs rule) term)])
      (if bindings
        (substitute (rule-rhs rule) bindings)
        #f)))

  ;;; ---- rewrite-once: apply first matching rule ----

  (define (rewrite-once rs term)
    (let loop ([rules (%ruleset-rules rs)])
      (if (null? rules)
        #f
        (let ([result (try-rule (car rules) term)])
          (if result
            result
            (loop (cdr rules)))))))

  ;;; ---- rewrite: innermost-first, apply until no change ----

  (define (rewrite rs term)
    ;; Innermost-first: rewrite subterms first
    (let* ([rewritten (if (pair? term)
                        (let ([head (rewrite rs (car term))]
                              [args (map (lambda (a) (rewrite rs a)) (cdr term))])
                          (cons head args))
                        term)]
           [result (rewrite-once rs rewritten)])
      (if result
        (rewrite rs result)
        rewritten)))

  ;;; ---- rewrite-all: apply all matching rules once ----

  (define (rewrite-all rs term)
    (let loop ([rules (%ruleset-rules rs)] [term term])
      (if (null? rules)
        term
        (let ([result (try-rule (car rules) term)])
          (loop (cdr rules) (if result result term))))))

  ;;; ---- rewrite-fixed-point: apply until stable ----

  (define (rewrite-fixed-point rs term)
    (let loop ([t term])
      (let ([result (rewrite rs t)])
        (if (equal? result t)
          result
          (loop result)))))

  ;;; ---- normalize: canonical form = fixed point ----

  (define (normalize rs term)
    (rewrite-fixed-point rs term))

) ;; end library
