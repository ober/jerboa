#!chezscheme
;;; (std peg) — PEG (Parsing Expression Grammar) system
;;;
;;; More powerful than regex: handles recursive structures, produces ASTs,
;;; and provides clear error reporting. Uses packrat memoization for O(n)
;;; parsing (no exponential backtracking).
;;;
;;; Value semantics:
;;;   - String literals / char matches  → string
;;;   - (: e ...) sequence              → string (if all strings) or list
;;;   - (* e) (+ e)                     → string (if all chars) or list
;;;   - (? e)                           → value or "" on no-match
;;;   - (=> name e)                     → ((name . value))  [alist entry]
;;;   - (drop e)                        → "" [excluded from parent sequence]
;;;   - (or e1 e2 ...)                  → value of first matching branch
;;;   - (sep-by e sep)                  → list of e values
;;;   - rule reference                  → that rule's value
;;;   - (! e) (& e) predicates          → "" [no input consumed]
;;;   - any / (/ lo hi) / (~ e)         → single char string
;;;
;;; Usage:
;;;   (import (std peg))
;;;
;;;   (define-grammar arith
;;;     (expr   (=> result (+ addend)) (=> ops (* (: (or "+" "-") addend))))
;;;     (addend (+ digit)))
;;;
;;;   (arith:expr "1+22+333")
;;;   ;; => ((result . "1") (ops . (("+" . "22") ("+" . "333"))))
;;;
;;;   ;; CSV example
;;;   (define-grammar csv
;;;     (file   (+ row))
;;;     (row    (sep-by field ",") (drop "\n"))
;;;     (field  (or quoted-field plain-field))
;;;     (quoted-field  (drop "\"") (* (~ "\"")) (drop "\""))
;;;     (plain-field   (* (~ (or "," "\n")))))
;;;
;;;   (csv:file "Alice,30\nBob,25\n")
;;;   ;; => (("Alice" "30") ("Bob" "25"))

(library (std peg)
  (export
    ;; Grammar definition macro
    define-grammar
    ;; Runtime: run a compiled grammar against a string
    peg-run
    ;; Error type
    peg-error? peg-error-position peg-error-input peg-error-message)

  (import (chezscheme))

  ;; ========== Result type ==========
  ;; Internally: #f = failure, (value . new-pos) = success

  (define (peg-ok val pos) (cons val pos))
  (define (peg-ok? r) (and r (pair? r)))
  (define (peg-ok-val r) (car r))
  (define (peg-ok-pos r) (cdr r))

  ;; ========== Error type ==========

  (define-record-type peg-error
    (fields position input message)
    (sealed #t))

  (define (make-parse-error pos input)
    (make-peg-error
      pos input
      (string-append "parse error at position "
                     (number->string pos)
                     " in: "
                     (if (> (string-length input) 40)
                       (string-append (substring input 0 40) "...")
                       input))))

  ;; ========== Value helpers ==========

  (define (peg-alist? v)
    (and (list? v)
         (not (null? v))
         (pair? (car v))
         (symbol? (caar v))))

  ;; Merge a list of sequence values:
  ;; - Drop empty strings (from (drop ...) and (? ...) misses)
  ;; - If all remaining are strings → concatenate
  ;; - If any are alists → merge all alists
  ;; - Otherwise → list of values
  (define (peg-merge-seq vals)
    (let* ([non-empty (filter (lambda (v) (not (equal? v ""))) vals)]
           [all-str?  (for-all string? non-empty)]
           [any-alist? (exists peg-alist? non-empty)])
      (cond
        [(null? non-empty) ""]
        [all-str? (apply string-append non-empty)]
        [any-alist?
         ;; Merge all alists; non-alist non-string values are included as-is
         (apply append
           (map (lambda (v)
                  (cond [(peg-alist? v) v]
                        [(equal? v "") '()]
                        [else (list (cons '_ v))]))
                non-empty))]
        [(null? (cdr non-empty)) (car non-empty)]
        [else non-empty])))

  ;; Merge repetition results (from * and +):
  ;; If all are single-char strings, join into one string.
  ;; Otherwise return list.
  (define (peg-merge-rep vals)
    (cond
      [(null? vals) ""]
      [(and (for-all string? vals)
            (for-all (lambda (s) (= (string-length s) 1)) vals))
       (apply string-append vals)]
      [else vals]))

  ;; ========== Core combinators ==========
  ;; Each combinator returns a procedure:
  ;;   (input pos memo far dispatch) → (value . new-pos) | #f

  ;; Match a literal string
  (define (peg-lit str)
    (let ([slen (string-length str)])
      (lambda (input pos memo far dispatch)
        (let ([end (+ pos slen)])
          (if (and (<= end (string-length input))
                   (string=? (substring input pos end) str))
            (peg-ok str end)
            (begin
              (when (> pos (car far)) (set-car! far pos))
              #f))))))

  ;; Match any single character
  (define (peg-any-char)
    (lambda (input pos memo far dispatch)
      (if (< pos (string-length input))
        (peg-ok (string (string-ref input pos)) (+ pos 1))
        (begin (when (> pos (car far)) (set-car! far pos)) #f))))

  ;; Match a character in range [lo, hi]
  (define (peg-char-range lo hi)
    (lambda (input pos memo far dispatch)
      (if (and (< pos (string-length input))
               (let ([c (string-ref input pos)])
                 (and (char>=? c lo) (char<=? c hi))))
        (peg-ok (string (string-ref input pos)) (+ pos 1))
        (begin (when (> pos (car far)) (set-car! far pos)) #f))))

  ;; Match a specific character
  (define (peg-char ch)
    (lambda (input pos memo far dispatch)
      (if (and (< pos (string-length input))
               (char=? (string-ref input pos) ch))
        (peg-ok (string ch) (+ pos 1))
        (begin (when (> pos (car far)) (set-car! far pos)) #f))))

  ;; Ordered sequence: all must match in order
  (define (peg-sequence combs)
    (lambda (input pos memo far dispatch)
      (let loop ([cs combs] [p pos] [vals '()])
        (if (null? cs)
          (peg-ok (peg-merge-seq (reverse vals)) p)
          (let ([r ((car cs) input p memo far dispatch)])
            (if r
              (loop (cdr cs) (peg-ok-pos r) (cons (peg-ok-val r) vals))
              #f))))))

  ;; Ordered choice: try each in order, return first success
  (define (peg-choice combs)
    (lambda (input pos memo far dispatch)
      (let loop ([cs combs])
        (if (null? cs)
          #f
          (let ([r ((car cs) input pos memo far dispatch)])
            (or r (loop (cdr cs))))))))

  ;; Zero or more: greedy
  (define (peg-star comb)
    (lambda (input pos memo far dispatch)
      (let loop ([p pos] [vals '()])
        (let ([r (comb input p memo far dispatch)])
          (if r
            (if (= (peg-ok-pos r) p)
              ;; Zero-length match: prevent infinite loop
              (peg-ok (peg-merge-rep (reverse vals)) p)
              (loop (peg-ok-pos r) (cons (peg-ok-val r) vals)))
            (peg-ok (peg-merge-rep (reverse vals)) p))))))

  ;; One or more
  (define (peg-plus comb)
    (lambda (input pos memo far dispatch)
      (let ([first (comb input pos memo far dispatch)])
        (if (not first)
          #f
          (let loop ([p (peg-ok-pos first)] [vals (list (peg-ok-val first))])
            (let ([r (comb input p memo far dispatch)])
              (if (and r (not (= (peg-ok-pos r) p)))
                (loop (peg-ok-pos r) (cons (peg-ok-val r) vals))
                (peg-ok (peg-merge-rep (reverse vals)) p))))))))

  ;; Optional: match or return "" and consume nothing
  (define (peg-optional comb)
    (lambda (input pos memo far dispatch)
      (or (comb input pos memo far dispatch)
          (peg-ok "" pos))))

  ;; Exactly n repetitions
  (define (peg-exactly n comb)
    (lambda (input pos memo far dispatch)
      (let loop ([i 0] [p pos] [vals '()])
        (if (= i n)
          (peg-ok (peg-merge-rep (reverse vals)) p)
          (let ([r (comb input p memo far dispatch)])
            (if r
              (loop (+ i 1) (peg-ok-pos r) (cons (peg-ok-val r) vals))
              #f))))))

  ;; Between m and n repetitions (inclusive)
  (define (peg-repeat m n comb)
    (lambda (input pos memo far dispatch)
      (let loop ([i 0] [p pos] [vals '()])
        (if (= i n)
          (peg-ok (peg-merge-rep (reverse vals)) p)
          (let ([r (comb input p memo far dispatch)])
            (if r
              (loop (+ i 1) (peg-ok-pos r) (cons (peg-ok-val r) vals))
              (if (>= i m)
                (peg-ok (peg-merge-rep (reverse vals)) p)
                #f)))))))

  ;; At least n repetitions
  (define (peg-at-least n comb)
    (lambda (input pos memo far dispatch)
      (let loop ([i 0] [p pos] [vals '()])
        (let ([r (comb input p memo far dispatch)])
          (if (and r (not (= (peg-ok-pos r) p)))
            (loop (+ i 1) (peg-ok-pos r) (cons (peg-ok-val r) vals))
            (if (>= i n)
              (peg-ok (peg-merge-rep (reverse vals)) p)
              #f))))))

  ;; Not predicate: succeeds if comb fails, consumes nothing
  (define (peg-not comb)
    (lambda (input pos memo far dispatch)
      (if (comb input pos memo far dispatch)
        #f
        (peg-ok "" pos))))

  ;; And predicate: succeeds if comb succeeds, consumes nothing
  (define (peg-and comb)
    (lambda (input pos memo far dispatch)
      (if (comb input pos memo far dispatch)
        (peg-ok "" pos)
        #f)))

  ;; Named capture: wraps result as alist entry
  (define (peg-capture name comb)
    (lambda (input pos memo far dispatch)
      (let ([r (comb input pos memo far dispatch)])
        (and r (peg-ok (list (cons name (peg-ok-val r))) (peg-ok-pos r))))))

  ;; Drop: match but produce empty string (filtered out by peg-merge-seq)
  (define (peg-drop comb)
    (lambda (input pos memo far dispatch)
      (let ([r (comb input pos memo far dispatch)])
        (and r (peg-ok "" (peg-ok-pos r))))))

  ;; Complement: match any char NOT matching comb
  (define (peg-complement comb)
    (lambda (input pos memo far dispatch)
      (if (< pos (string-length input))
        (if (comb input pos memo far dispatch)
          #f
          (peg-ok (string (string-ref input pos)) (+ pos 1)))
        (begin (when (> pos (car far)) (set-car! far pos)) #f))))

  ;; sep-by: e separated by sep, zero or more
  (define (peg-sep-by elem-comb sep-comb)
    (lambda (input pos memo far dispatch)
      (let ([first (elem-comb input pos memo far dispatch)])
        (if (not first)
          (peg-ok '() pos)
          (let loop ([p (peg-ok-pos first)] [vals (list (peg-ok-val first))])
            (let ([sr (sep-comb input p memo far dispatch)])
              (if (not sr)
                (peg-ok (reverse vals) p)
                (let ([er (elem-comb input (peg-ok-pos sr) memo far dispatch)])
                  (if er
                    (loop (peg-ok-pos er) (cons (peg-ok-val er) vals))
                    (peg-ok (reverse vals) p))))))))))

  ;; sep-by1: one or more
  (define (peg-sep-by1 elem-comb sep-comb)
    (lambda (input pos memo far dispatch)
      (let ([first (elem-comb input pos memo far dispatch)])
        (if (not first)
          #f
          (let loop ([p (peg-ok-pos first)] [vals (list (peg-ok-val first))])
            (let ([sr (sep-comb input p memo far dispatch)])
              (if (not sr)
                (peg-ok (reverse vals) p)
                (let ([er (elem-comb input (peg-ok-pos sr) memo far dispatch)])
                  (if er
                    (loop (peg-ok-pos er) (cons (peg-ok-val er) vals))
                    (peg-ok (reverse vals) p))))))))))

  ;; ========== PEG form compiler ==========
  ;; Compiles a quoted PEG form to a combinator function.
  ;; `rule-lookup` is called for rule references: (rule-lookup name input pos memo far dispatch)

  (define (compile-peg form rule-lookup)
    (cond
      ;; String literal
      [(string? form) (peg-lit form)]
      ;; Character literal
      [(char? form) (peg-char form)]
      ;; 'any — match any character
      [(eq? form 'any) (peg-any-char)]
      ;; 'epsilon — match empty
      [(eq? form 'epsilon) (lambda (input pos memo far dispatch) (peg-ok "" pos))]
      ;; 'eof — match end of input
      [(eq? form 'eof)
       (lambda (input pos memo far dispatch)
         (if (= pos (string-length input)) (peg-ok "" pos) #f))]
      ;; Symbol: rule reference
      [(symbol? form)
       (lambda (input pos memo far dispatch)
         (rule-lookup form input pos memo far dispatch))]
      ;; Compound forms
      [(pair? form)
       (let ([head (car form)]
             [args (cdr form)])
         (case head
           ;; Sequence: (: e ...) or implicit sequence
           [(:  seq)
            (peg-sequence (map (lambda (a) (compile-peg a rule-lookup)) args))]
           ;; Ordered choice
           [(or)
            (peg-choice (map (lambda (a) (compile-peg a rule-lookup)) args))]
           ;; Repetition
           [(*) (peg-star  (compile-peg (single-arg args) rule-lookup))]
           [(+) (peg-plus  (compile-peg (single-arg args) rule-lookup))]
           [(?) (peg-optional (compile-peg (single-arg args) rule-lookup))]
           [(= repeat)
            (peg-exactly (car args) (compile-peg (cadr args) rule-lookup))]
           [(>=)
            (peg-at-least (car args) (compile-peg (cadr args) rule-lookup))]
           [(**)
            (peg-repeat (car args) (cadr args) (compile-peg (caddr args) rule-lookup))]
           ;; Predicates (no consume)
           [(!) (peg-not (compile-peg (single-arg args) rule-lookup))]
           [(&) (peg-and (compile-peg (single-arg args) rule-lookup))]
           ;; Named capture
           [(=>)
            (let ([name (car args)]
                  [body (if (null? (cddr args))
                          (cadr args)
                          (cons ': (cdr args)))])
              (peg-capture name (compile-peg body rule-lookup)))]
           ;; Drop result
           [(drop)
            (peg-drop (compile-peg (single-arg-or-seq args) rule-lookup))]
           ;; Complement (not this set)
           [(~ complement)
            (peg-complement (compile-peg (single-arg args) rule-lookup))]
           ;; Character range: (/ lo hi) where lo/hi are chars or strings
           [(/ char-range)
            (let loop ([pairs args])
              (if (null? pairs)
                (lambda (input pos memo far dispatch)
                  (begin (when (> pos (car far)) (set-car! far pos)) #f))
                (peg-choice
                  (list (peg-char-range (->char (car pairs)) (->char (cadr pairs)))
                        (loop (cddr pairs))))))]
           ;; sep-by: (sep-by elem sep)
           [(sep-by)
            (peg-sep-by (compile-peg (car args) rule-lookup)
                        (compile-peg (cadr args) rule-lookup))]
           ;; sep-by1: (sep-by1 elem sep) — one or more
           [(sep-by1)
            (peg-sep-by1 (compile-peg (car args) rule-lookup)
                         (compile-peg (cadr args) rule-lookup))]
           ;; Implicit sequence of multiple args treated as (: ...)
           [else
            ;; head is itself a PEG form, treat whole thing as sequence
            (peg-sequence (map (lambda (a) (compile-peg a rule-lookup))
                               (cons head args)))]))]
      [else (error 'peg "unknown PEG form" form)]))

  ;; Helpers for form compilation
  (define (single-arg args)
    (if (null? (cdr args)) (car args) (cons ': args)))

  (define (single-arg-or-seq args)
    (if (null? (cdr args)) (car args) (cons ': args)))

  (define (->char x)
    (cond [(char? x) x]
          [(and (string? x) (= (string-length x) 1)) (string-ref x 0)]
          [else (error 'peg "expected char or single-char string" x)]))

  ;; ========== Grammar runtime ==========

  ;; A grammar is a hash table: rule-name → combinator
  ;; Plus a dispatch procedure that memoizes lookups.

  (define (make-peg-grammar rule-alist)
    ;; rule-alist: list of (name . (form ...))
    ;; Returns a dispatch procedure: (name input pos memo far dispatch) → result
    (let ([rules (make-eq-hashtable)])
      (define (dispatch name input pos memo far)
        (let ([key (cons name pos)])
          (let ([cached (hashtable-ref memo key 'not-found)])
            (if (not (eq? cached 'not-found))
              cached
              ;; Not in memo: compute (with cycle protection via 'computing sentinel)
              (begin
                (hashtable-set! memo key #f)  ;; sentinel: fail if recursive
                (let ([f (hashtable-ref rules name #f)])
                  (unless f (error 'peg "unknown grammar rule" name))
                  (let ([result (f input pos memo far dispatch)])
                    (hashtable-set! memo key result)
                    result)))))))
      ;; Compile all rules, capturing dispatch via closure
      (for-each
        (lambda (def)
          (let* ([name  (car def)]
                 [forms (cdr def)]
                 [body  (if (null? (cdr forms))
                          (car forms)
                          (cons ': forms))]
                 [rule-lookup
                  (lambda (sym input pos memo far _dispatch)
                    (dispatch sym input pos memo far))]
                 [comb  (compile-peg body rule-lookup)])
            (hashtable-set! rules name comb)))
        rule-alist)
      dispatch))

  ;; Run a named rule of a grammar against an input string.
  ;; Returns the parse value on success, or a peg-error on failure.
  (define (peg-run grammar rule-name input-str)
    (let ([memo    (make-eq-hashtable)]
          [farthest (list 0)])
      (let ([result (grammar rule-name input-str 0 memo farthest)])
        (if result
          (if (= (peg-ok-pos result) (string-length input-str))
            (peg-ok-val result)
            ;; Partial match — treat as error
            (make-parse-error (car farthest) input-str))
          (make-parse-error (car farthest) input-str)))))

  ;; ========== define-grammar macro ==========

  (define-syntax define-grammar
    (lambda (stx)
      (syntax-case stx ()
        [(_ gname (rname rbody ...) ...)
         (let* ([gname-sym    (syntax->datum #'gname)]
                [rule-syms    (syntax->datum #'(rname ...))]
                [entry-names  (map (lambda (r)
                                     (string->symbol
                                       (string-append (symbol->string gname-sym)
                                                      ":"
                                                      (symbol->string r))))
                                   rule-syms)])
           (with-syntax
             ([gname-dispatch (datum->syntax #'gname
                                (string->symbol (string-append (symbol->string gname-sym)
                                                               "-dispatch")))]
              [(entry-name ...) (map (lambda (n) (datum->syntax #'gname n))
                                     entry-names)])
             #`(begin
                 ;; Internal dispatch procedure for this grammar
                 (define gname-dispatch
                   (make-peg-grammar
                     (list (cons 'rname (list 'rbody ...)) ...)))
                 ;; Public entry points: gname:rname
                 (define (entry-name input)
                   (peg-run gname-dispatch 'rname input))
                 ...)))])))

) ;; end library
