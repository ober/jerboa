#!chezscheme
;;; (std lint) -- Source code linting/analysis

(library (std lint)
  (export
    make-linter linter? lint-file lint-string lint-form
    lint-result? lint-result-file lint-result-line lint-result-col
    lint-result-severity lint-result-message lint-result-rule
    add-rule! remove-rule! make-rule-config
    default-linter severity-error severity-warn severity-info
    lint-rule-names lint-summary)

  (import (chezscheme))

  ;;; ---- Severity levels ----

  (define severity-error 'error)
  (define severity-warn  'warn)
  (define severity-info  'info)

  ;;; ---- Result ----

  (define-record-type %lint-result
    (fields file line col severity message rule)
    (protocol (lambda (new)
      (lambda (file line col severity msg rule)
        (new file line col severity msg rule)))))

  (define (lint-result? x) (%lint-result? x))
  (define (lint-result-file r) (%lint-result-file r))
  (define (lint-result-line r) (%lint-result-line r))
  (define (lint-result-col r) (%lint-result-col r))
  (define (lint-result-severity r) (%lint-result-severity r))
  (define (lint-result-message r) (%lint-result-message r))
  (define (lint-result-rule r) (%lint-result-rule r))

  (define (make-result severity msg rule)
    (make-%lint-result #f #f #f severity msg rule))

  ;;; ---- Rule config ----

  (define (make-rule-config name enabled? severity)
    (list name enabled? severity))

  ;;; ---- Linter record ----

  (define-record-type %linter
    (fields (mutable rules))
    (protocol (lambda (new) (lambda (rules) (new rules)))))

  (define (make-linter) (make-%linter (list-copy %builtin-rules)))
  (define (linter? x) (%linter? x))

  (define (add-rule! linter name fn)
    (%linter-rules-set! linter
      (cons (cons name fn) (%linter-rules linter))))

  (define (remove-rule! linter name)
    (%linter-rules-set! linter
      (filter (lambda (r) (not (eq? (car r) name)))
              (%linter-rules linter))))

  (define (lint-rule-names linter)
    (map car (%linter-rules linter)))

  ;;; ---- Common builtins that should not be shadowed ----

  (define %common-builtins
    '(car cdr cons list map filter fold append length
      not and or if cond case when unless let let* letrec
      define lambda begin quote quasiquote unquote
      set! values call-with-values apply
      equal? eq? eqv? null? pair? list? string? number? boolean?
      vector? procedure? symbol?
      + - * / < > <= >= =
      string-append string-length substring string-ref
      number->string string->number
      for-each error display write newline))

  ;;; ---- Built-in rule implementations ----

  ;; Collect all defined names in a top-level form (for unused-define)
  (define (collect-defines form)
    (cond
      [(and (pair? form) (eq? (car form) 'define))
       (cond
         [(symbol? (cadr form)) (list (cadr form))]
         [(pair? (cadr form)) (list (caadr form))]
         [else '()])]
      [else '()]))

  ;; Check if symbol appears in form (other than as the defined name)
  (define (symbol-referenced? sym form defined-at)
    (let loop ([f form] [depth 0])
      (cond
        [(eq? f sym) #t]
        [(pair? f)
         ;; Skip the name position if this is its define
         (let ([is-def? (and (eq? (car f) 'define) (= depth 0))])
           (if is-def?
             ;; Only scan the body, not the name
             (loop (cddr f) (+ depth 1))
             (or (loop (car f) (+ depth 1))
                 (loop (cdr f) (+ depth 1)))))]
        [else #f])))

  ;; Flatten a list of forms for reference scanning
  (define (all-symbols form)
    (cond
      [(symbol? form) (list form)]
      [(pair? form) (append (all-symbols (car form)) (all-symbols (cdr form)))]
      [else '()]))

  ;; Count nesting depth
  (define (max-depth form current)
    (if (pair? form)
      (+ 1 (apply max (map (lambda (sub) (max-depth sub 0)) form)))
      0))

  ;; Count body forms in a lambda
  (define (lambda-body-length form)
    (if (and (pair? form) (eq? (car form) 'lambda))
      (length (cddr form))
      0))

  ;; Check if a number is "magic" (> 100 and not in a define)
  (define (find-magic-numbers form)
    (cond
      [(and (number? form) (> (abs form) 100))
       (list form)]
      [(pair? form) (append (find-magic-numbers (car form))
                            (find-magic-numbers (cdr form)))]
      [else '()]))

  ;;; ---- Built-in rules ----

  (define (%rule-empty-begin forms)
    (let loop ([fs forms] [results '()])
      (if (null? fs) (reverse results)
          (let ([f (car fs)])
            (loop (cdr fs)
                  (if (and (pair? f) (eq? (car f) 'begin) (null? (cdr f)))
                    (cons (make-result severity-warn
                            "(begin) with no forms" 'empty-begin) results)
                    results))))))

  (define (%rule-single-arm-cond forms)
    (let loop ([fs forms] [results '()])
      (if (null? fs) (reverse results)
          (let ([f (car fs)])
            (loop (cdr fs)
                  (if (and (pair? f) (eq? (car f) 'cond)
                           (pair? (cdr f)) (null? (cddr f)))
                    (cons (make-result severity-info
                            "cond with single clause; consider using 'if'" 'single-arm-cond)
                          results)
                    results))))))

  (define (%rule-missing-else forms)
    (let loop ([fs forms] [results '()])
      (if (null? fs) (reverse results)
          (let ([f (car fs)])
            (loop (cdr fs)
                  (if (and (pair? f) (eq? (car f) 'if)
                           (pair? (cdr f)) (pair? (cddr f))
                           (null? (cdddr f)))  ; exactly 2 args: test + then
                    (cons (make-result severity-info
                            "if without else branch" 'missing-else) results)
                    results))))))

  (define (%rule-deep-nesting forms)
    (let loop ([fs forms] [results '()])
      (if (null? fs) (reverse results)
          (let* ([f (car fs)]
                 [d (max-depth f 0)])
            (loop (cdr fs)
                  (if (> d 10)
                    (cons (make-result severity-info
                            (format "expression nested ~a levels deep (max 10)" d) 'deep-nesting)
                          results)
                    results))))))

  (define (%rule-long-lambda forms)
    (let loop ([fs forms] [results '()])
      (if (null? fs) (reverse results)
          (let* ([f (car fs)]
                 [len (lambda-body-length f)])
            (loop (cdr fs)
                  (if (> len 20)
                    (cons (make-result severity-info
                            (format "lambda body has ~a forms (max 20)" len) 'long-lambda)
                          results)
                    results))))))

  (define (%rule-redefine-builtin forms)
    (let loop ([fs forms] [results '()])
      (if (null? fs) (reverse results)
          (let ([f (car fs)])
            (loop (cdr fs)
                  (if (and (pair? f) (eq? (car f) 'define))
                    (let ([name (if (symbol? (cadr f))
                                  (cadr f)
                                  (and (pair? (cadr f)) (caadr f)))])
                      (if (and name (memq name %common-builtins))
                        (cons (make-result severity-warn
                                (format "redefining builtin '~a'" name) 'redefine-builtin)
                              results)
                        results))
                    results))))))

  (define (%rule-magic-number forms)
    (let loop ([fs forms] [results '()])
      (if (null? fs) (reverse results)
          (let ([f (car fs)])
            (loop (cdr fs)
                  (let ([nums (find-magic-numbers f)])
                    (if (null? nums)
                      results
                      (cons (make-result severity-info
                              (format "magic number ~a (> 100); consider a named constant" (car nums))
                              'magic-number)
                            results))))))))

  (define (%rule-shadowed-define forms)
    ;; Find defines that shadow outer bindings
    ;; We look for let/lambda bodies that redefine things
    (define (check-form f outer-names)
      (cond
        [(not (pair? f)) '()]
        [(eq? (car f) 'define)
         (let ([name (if (symbol? (cadr f))
                        (cadr f)
                        (and (pair? (cadr f)) (caadr f)))])
           (if (and name (memq name outer-names))
             (list (make-result severity-warn
                     (format "define '~a' shadows outer binding" name) 'shadowed-define))
             '()))]
        [(memq (car f) '(let let* letrec letrec*))
         ;; bindings introduce new names
         (let* ([bindings (if (or (eq? (car f) 'let*) (eq? (car f) 'letrec*)
                                  (eq? (car f) 'letrec))
                            (cadr f)
                            ;; named let
                            (if (symbol? (cadr f)) (caddr f) (cadr f)))]
                [new-names (if (list? bindings)
                              (map car bindings)
                              '())]
                [shadowed (filter (lambda (n) (memq n outer-names)) new-names)])
           (if (null? shadowed)
             (append-map (lambda (sub) (check-form sub (append new-names outer-names))) (cdr f))
             (map (lambda (n) (make-result severity-warn
                                (format "binding '~a' shadows outer binding" n) 'shadowed-define))
                  shadowed)))]
        [else
         (append-map (lambda (sub) (check-form sub outer-names)) f)]))
    (append-map (lambda (f) (check-form f '())) forms))

  (define (append-map f lst)
    (apply append (map f lst)))

  (define (%rule-unused-define forms)
    ;; Find top-level defines never referenced in the same file
    (let* ([defined (append-map collect-defines forms)]
           [all-refs (append-map all-symbols forms)])
      (filter-map
        (lambda (name)
          (if (memq name all-refs)
            ;; Check it's referenced more than just its own definition
            (let ([ref-count (length (filter (lambda (s) (eq? s name)) all-refs))])
              ;; If only appears once (in define itself), it's unused
              (if (<= ref-count 1)
                (make-result severity-info
                  (format "defined '~a' is never referenced" name) 'unused-define)
                #f))
            (make-result severity-info
              (format "defined '~a' is never referenced" name) 'unused-define)))
        defined)))

  (define (filter-map f lst)
    (let loop ([l lst] [acc '()])
      (if (null? l) (reverse acc)
          (let ([v (f (car l))])
            (loop (cdr l) (if v (cons v acc) acc))))))

  (define %builtin-rules
    (list
      (cons 'empty-begin       %rule-empty-begin)
      (cons 'single-arm-cond   %rule-single-arm-cond)
      (cons 'missing-else      %rule-missing-else)
      (cons 'deep-nesting      %rule-deep-nesting)
      (cons 'long-lambda       %rule-long-lambda)
      (cons 'redefine-builtin  %rule-redefine-builtin)
      (cons 'magic-number      %rule-magic-number)
      (cons 'shadowed-define   %rule-shadowed-define)
      (cons 'unused-define     %rule-unused-define)))

  ;;; ---- default-linter ----

  (define default-linter (make-%linter (list-copy %builtin-rules)))

  ;;; ---- lint-form: lint a single form ----

  (define (lint-form linter form)
    (lint-forms linter (list form)))

  (define (lint-forms linter forms)
    (append-map
      (lambda (rule-entry)
        ((cdr rule-entry) forms))
      (%linter-rules linter)))

  ;;; ---- lint-string: parse string, run linter ----

  (define (lint-string linter str)
    (let ([forms (read-all-forms str)])
      (lint-forms linter forms)))

  (define (read-all-forms str)
    (let ([port (open-input-string str)])
      (let loop ([forms '()])
        (let ([form (read port)])
          (if (eof-object? form)
            (reverse forms)
            (loop (cons form forms)))))))

  ;;; ---- lint-file: lint a file ----

  (define (lint-file linter path)
    (let* ([str (with-input-from-file path
                  (lambda ()
                    (let loop ([chars '()])
                      (let ([c (read-char)])
                        (if (eof-object? c)
                          (list->string (reverse chars))
                          (loop (cons c chars)))))))]
           [results (lint-string linter str)])
      ;; Tag results with file
      (map (lambda (r)
             (make-%lint-result path (lint-result-line r) (lint-result-col r)
                                (lint-result-severity r) (lint-result-message r)
                                (lint-result-rule r)))
           results)))

  ;;; ---- lint-summary ----

  (define (lint-summary results)
    (let ([errors (length (filter (lambda (r) (eq? (lint-result-severity r) severity-error)) results))]
          [warns  (length (filter (lambda (r) (eq? (lint-result-severity r) severity-warn)) results))]
          [infos  (length (filter (lambda (r) (eq? (lint-result-severity r) severity-info)) results))])
      (list (cons 'error errors)
            (cons 'warn warns)
            (cons 'info infos))))

) ;; end library
